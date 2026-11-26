local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")
local RoomFlow = require("src.infra.room_flow")

t.suite("infra/room_flow", function()
	local env
	local flow

	t.before_each(function()
		env = FakeEnv.new()
		flow = RoomFlow.new({
			game = env.api.game,
			steam = env.api.steam,
			mem = env.api.mem,
			offsets = env.api.offsets,
			time = env.api.time,
		})
	end)

	t.test("leaves training only in SCENE_BATTLE after 90 settle frames and ignores stale training flag on main menu", function()
		env.is_training = true
		env:set_scene(env.api.offsets.SCENE_MAIN_MENU, 60)
		t.assert_false(flow:leave_training_if_needed())
		t.assert_eq(env.leave_training_calls, 0)

		env:set_scene(env.api.offsets.SCENE_BATTLE, 4)
		for _ = 1, 89 do
			t.assert_true(flow:leave_training_if_needed())
		end
		t.assert_eq(env.leave_training_calls, 0)

		t.assert_true(flow:leave_training_if_needed())
		t.assert_eq(env.leave_training_calls, 1)

		flow:leave_training_if_needed()
		t.assert_eq(env.leave_training_calls, 1)

		env:advance(5000)
		flow:leave_training_if_needed()
		t.assert_eq(env.leave_training_calls, 2)
	end)

	t.test("detects owned lobby and drives host room creation including armed main menu fallback", function()
		t.assert_nil(flow:owned_lobby("111"))
		env:set_lobby("999", "222")
		t.assert_nil(flow:owned_lobby("111"))

		env:set_lobby("999", "111")
		t.assert_eq(flow:owned_lobby("111"), "999")

		env:set_lobby("0", "0")
		env:set_scene(env.api.offsets.SCENE_MAIN_MENU, 4)
		for _ = 1, 29 do
			t.assert_nil(flow:step_host_room(5))
		end
		t.assert_true(flow.creator:is_active())
		t.assert_eq(flow.creator.first_to, 5)
		t.assert_eq(env.enter_network_calls, 0)

		t.assert_nil(flow:step_host_room(5))
		t.assert_eq(env.enter_network_calls, 1)

		env:advance(120001)
		t.assert_eq(flow:step_host_room(5), "timed_out")
	end)

	t.test("drives guest navigation from main menu into network join even when scene_frames caps at 4", function()
		env:set_scene(env.api.offsets.SCENE_MAIN_MENU, 4)
		for _ = 1, 29 do
			t.assert_nil(flow:step_guest_prepare("777", "222"))
		end
		t.assert_eq(env.enter_network_calls, 0)

		t.assert_nil(flow:step_guest_prepare("777", "222"))
		t.assert_eq(env.enter_network_calls, 1)

		env:set_scene(env.api.offsets.SCENE_NETWORK, 4)
		t.assert_eq(flow:step_guest_prepare("777", "222"), "joining")
		t.assert_eq(env.joined_lobby, "777")
		t.assert_eq(env.joined_owner, "222")
		t.assert_eq(env.claim_pad_calls, 2)

		env.can_join_room = false
		t.assert_eq(flow:step_guest_prepare("777", "222"), "unsupported")
	end)

	t.test("reports guest join success, flow error, and timeout", function()
		t.assert_nil(flow:step_guest_joining("777", 1000))

		env:set_mem(env.api.offsets.NETWORK_FLOW_ERROR, 1)
		t.assert_eq(flow:step_guest_joining("777", 1000), "flow_error")

		env:set_mem(env.api.offsets.NETWORK_FLOW_ERROR, 0)
		env:advance(45000)
		t.assert_eq(flow:step_guest_joining("777", 1000), "timed_out")

		env:set_lobby("777", "222")
		t.assert_eq(flow:step_guest_joining("777", 1000), "joined")
	end)

	t.test("stops host room creation immediately on network init, flow, step error, or failed stage", function()
		env:set_scene(env.api.offsets.SCENE_NETWORK, 60)
		flow.creator:start(3)
		flow.creator:note_stage("creating_room")
		t.assert_nil(flow:step_host_room(3))

		env:set_mem(env.api.offsets.NETWORK_INIT_ERROR, -10000)
		t.assert_eq(flow:step_host_room(3), "network_error")
		t.assert_false(flow.creator:is_active())

		flow:reset()
		env:set_mem(env.api.offsets.NETWORK_INIT_ERROR, 0)
		flow.creator:start(3)
		flow.creator:note_stage("creating_room")
		t.assert_nil(flow:step_host_room(3))
		env:set_mem(env.api.offsets.NETWORK_FLOW_ERROR, 3)
		t.assert_eq(flow:step_host_room(3), "network_error")

		flow:reset()
		env:set_mem(env.api.offsets.NETWORK_FLOW_ERROR, 0)
		flow.creator:start(3)
		flow.creator:note_stage("creating_room")
		t.assert_nil(flow:step_host_room(3))
		env:set_mem(env.api.offsets.NETWORK_STEP_STATE, 10)
		t.assert_eq(flow:step_host_room(3), "network_error")

		flow:reset()
		env:set_mem(env.api.offsets.NETWORK_STEP_STATE, 0)
		flow.creator:note_stage("failed")
		t.assert_eq(flow:step_host_room(3), "network_error")
	end)

	t.test("fails immediately without retrying when network bounces back to main menu", function()
		env:set_scene(env.api.offsets.SCENE_MAIN_MENU, 60)
		t.assert_nil(flow:step_host_room(5))
		t.assert_eq(env.enter_network_calls, 1)

		env:set_scene(env.api.offsets.SCENE_NETWORK, 10)
		t.assert_nil(flow:step_host_room(5))

		env:set_scene(env.api.offsets.SCENE_MAIN_MENU, 60)
		t.assert_eq(flow:step_host_room(5), "network_error")
		t.assert_eq(env.enter_network_calls, 1)
		t.assert_false(flow.creator:is_active())
	end)

	t.test("fails fast when Steam goes offline and stops guest after single main menu entry fails", function()
		env.steam_id = "0"
		t.assert_eq(flow:step_host_room(3), "steam_offline")
		t.assert_eq(flow:step_guest_prepare("777", "222"), "steam_offline")

		env.steam_id = "76561198000000001"
		flow:reset()
		env:set_scene(env.api.offsets.SCENE_MAIN_MENU, 60)
		t.assert_nil(flow:step_guest_prepare("777", "222"))
		t.assert_eq(env.enter_network_calls, 1)

		env:advance(1000)
		t.assert_nil(flow:step_guest_prepare("777", "222"))
		t.assert_eq(env.enter_network_calls, 1)

		env:advance(4000)
		t.assert_eq(flow:step_guest_prepare("777", "222"), "network_error")
		t.assert_eq(env.enter_network_calls, 1)
	end)
end)
