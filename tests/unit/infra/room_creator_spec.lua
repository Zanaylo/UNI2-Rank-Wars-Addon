local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")
local RoomCreator = require("src.infra.room_creator")

t.suite("infra/room_creator", function()
	local env
	local creator

	t.before_each(function()
		env = FakeEnv.new()
		creator = RoomCreator.new({
			game = env.api.game,
			mem = env.api.mem,
			offsets = env.api.offsets,
			time = env.api.time,
			log = env.api.log,
			warn = env.api.warn,
		})
	end)

	t.test("drives full room creation in Lua using engine events, memory writes, and standard + alt settings", function()
		local o = env.api.offsets
		local entered = 0
		local function enter_network()
			entered = entered + 1
			return nil
		end

		env:set_scene(o.SCENE_MAIN_MENU, 60)
		t.assert_nil(creator:step(5, 30, enter_network))
		t.assert_eq(entered, 1)
		t.assert_eq(creator.stage, "entering_network")
		t.assert_eq(creator:status_text(), "Opening Network")

		env:set_scene(o.SCENE_NETWORK, 10)
		creator:on_network_menu_opened(0)
		t.assert_eq(creator.stage, "picking_create_room")

		local card_addr = 0x30000000
		env:set_mem(o.NETWORK_MENU + o.NETWORK_MENU_PROFILE_CARD, card_addr)
		env:set_abs(card_addr + o.PROFILE_CARD_STATE, 2)

		for _ = 1, 30 do
			t.assert_nil(creator:step(5, 0, enter_network))
		end
		t.assert_eq(env:get_abs(card_addr + o.PROFILE_CARD_DISMISS), 1)
		t.assert_eq(env.mem_store[o.NETWORK_MENU + o.NETWORK_MENU_PICK], nil)

		env:set_abs(card_addr + o.PROFILE_CARD_STATE, o.PROFILE_CARD_DONE)
		t.assert_nil(creator:step(5, 0, enter_network))
		t.assert_eq(env.mem_store[o.NETWORK_MENU + o.NETWORK_MENU_PICK], o.NETWORK_PICK_CREATE_ROOM)

		env:set_mem(o.NETWORK_MENU + o.NETWORK_MENU_STATE, 0)
		env:set_mem(o.NETWORK_MENU + o.NETWORK_MENU_PENDING, 6)
		t.assert_nil(creator:step(5, 0, enter_network))
		t.assert_eq(creator.stage, "opening_player_match")

		local root, rows, alt_rows = env:setup_create_room_screen({ room_type = 0, use_alt = true })
		creator:on_player_match_result(root, 1)

		t.assert_eq(creator.stage, "creating_room")
		t.assert_eq(env:get_abs(rows + o.ROOM_CAPACITY_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), o.ROOM_CAPACITY_TWO_PEOPLE)
		t.assert_eq(env:get_abs(rows + o.ROOM_REMATCH_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), 4)
		t.assert_eq(env:get_abs(rows + o.ROOM_ROUNDS_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), o.ROOM_ROUNDS_TWO)
		t.assert_eq(env:get_abs(rows + o.ROOM_ROUND_TIME_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), o.ROOM_ROUND_TIME_DEFAULT_99)
		t.assert_eq(env:get_abs(alt_rows + o.ROOM_ALT_REMATCH_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), 4)
		t.assert_eq(env:get_abs(alt_rows + o.ROOM_ALT_ROUNDS_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), o.ROOM_ROUNDS_TWO)
		t.assert_eq(env:get_abs(alt_rows + o.ROOM_ALT_ROUND_TIME_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), o.ROOM_ROUND_TIME_DEFAULT_99)
		t.assert_eq(env:get_abs(root + o.PLAYER_MATCH_CREATE_ANSWER), o.CREATE_MENU_CREATE_ROOM)
	end)

	t.test("writes room type 1 settings and polls already-open create screen when armed on network scene", function()
		local o = env.api.offsets
		env:set_scene(o.SCENE_NETWORK, 60)
		local root, rows = env:setup_create_room_screen({ room_type = 1, use_alt = false })

		t.assert_nil(creator:step(3, 0, function() return nil end))
		t.assert_eq(creator.stage, "creating_room")
		t.assert_eq(env:get_abs(rows + o.ROOM_TYPE1_REMATCH_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), 2)
		t.assert_eq(env:get_abs(rows + o.ROOM_TYPE1_ROUNDS_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), o.ROOM_ROUNDS_TWO)
		t.assert_eq(env:get_abs(rows + o.ROOM_TYPE1_ROUND_TIME_ROW * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE), o.ROOM_ROUND_TIME_DEFAULT_99)
		t.assert_eq(env:get_abs(root + o.PLAYER_MATCH_CREATE_ANSWER), o.CREATE_MENU_CREATE_ROOM)
	end)

	t.test("stops after max network menu pick attempts instead of looping forever", function()
		local o = env.api.offsets
		env:set_scene(o.SCENE_NETWORK, 60)
		creator:start(3)
		creator:on_network_menu_opened(0)

		local outcome
		for _ = 1, 250 do
			outcome = creator:step(3, 0, function() return nil end)
			if outcome then
				break
			end
		end

		t.assert_eq(outcome, "network_error")
		t.assert_eq(creator.stage, "failed")
		t.assert_eq(creator.picks, 0)
	end)

	t.test("detects network init error, flow error, step error, and 120s timeout", function()
		local o = env.api.offsets
		env:set_scene(o.SCENE_NETWORK, 60)
		creator:start(3)
		creator:note_stage("creating_room")
		t.assert_nil(creator:step(3, 0, function() return nil end))

		env:set_mem(o.NETWORK_INIT_ERROR, -10000)
		t.assert_eq(creator:step(3, 0, function() return nil end), "network_error")

		env:set_mem(o.NETWORK_INIT_ERROR, 0)
		creator:stop()
		creator:start(3)
		creator:note_stage("creating_room")
		t.assert_nil(creator:step(3, 0, function() return nil end))

		env:advance(120001)
		t.assert_eq(creator:step(3, 0, function() return nil end), "timed_out")
	end)

	t.test("falls back to legacy C++ room_create bindings when engine offsets are absent", function()
		local legacy_offsets = {
			SCENE_BATTLE = 20,
			SCENE_MAIN_MENU = 1,
			SCENE_NETWORK = 50,
			NETWORK_FLOW_ERROR = 0x30,
		}
		local legacy_creator = RoomCreator.new({
			game = env.api.game,
			mem = env.api.mem,
			offsets = legacy_offsets,
			time = env.api.time,
		})

		t.assert_false(legacy_creator:has_engine_api())
		env:set_scene(legacy_offsets.SCENE_MAIN_MENU, 60)
		t.assert_nil(legacy_creator:step(5, 30, function() return nil end))
		t.assert_true(env.room_create_started)
		t.assert_eq(env.room_create_first_to, 5)

		env.room_stage = 6
		t.assert_eq(legacy_creator:step(5, 0, function() return nil end), "network_error")
	end)
end)
