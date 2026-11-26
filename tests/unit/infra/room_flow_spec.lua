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
		t.assert_true(env.room_create_started)
		t.assert_eq(env.room_create_first_to, 5)
		t.assert_eq(env.enter_network_calls, 0)

		t.assert_nil(flow:step_host_room(5))
		t.assert_eq(env.enter_network_calls, 1)

		env.room_create_timed_out = true
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
		t.assert_eq(env.claim_pad_calls, 1)

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
end)
