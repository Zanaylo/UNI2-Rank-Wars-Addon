local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")

t.suite("app/replay_viewer", function()
	local app
	local env
	local viewer

	t.before_each(function()
		env = FakeEnv.new()
		app = env:build_app()
		viewer = app.replay_viewer
	end)

	t.test("refuses to start while a match is live", function()
		viewer:start({ replay = "r1", api = "https://rw.gg", token = "T" }, true)

		t.assert_eq(viewer:stage(), "off")
		t.assert_eq(#env.toasts, 1)
		t.assert_eq(env.toasts[1].kind, "warning")
	end)

	t.test("leaves training battle, ignores stale is_training on main menu, and plays even with capped scene_frames", function()
		env.is_training = true
		env:set_scene(env.api.offsets.SCENE_BATTLE, 90)
		viewer:start({ replay = "rep_7", api = "https://rw.gg", token = "RT" }, false)
		viewer:on_frame()

		local req = env:respond_next_http(200, "REPLAY_BYTES")
		t.assert_contains(req.url, "/replays/rep_7")
		t.assert_eq(viewer:stage(), "waiting")
		t.assert_eq(env.fs_store["UNI2-IM\\Replays\\RankWars_rep_7.rep"], "REPLAY_BYTES")

		viewer:on_frame()
		t.assert_eq(env.leave_training_calls, 1)
		t.assert_eq(#env.playback_requests, 0)

		env:set_scene(env.api.offsets.SCENE_MAIN_MENU, 4)
		for _ = 1, 29 do
			viewer:on_frame()
		end
		t.assert_eq(#env.playback_requests, 0)
		t.assert_eq(env.leave_training_calls, 1)

		viewer:on_frame()
		t.assert_eq(#env.playback_requests, 1)
		t.assert_eq(viewer:stage(), "off")
		t.assert_eq(env.toasts[#env.toasts].kind, "success")
	end)

	t.test("reports HTTP 401/404 and file write errors cleanly", function()
		viewer:start({ replay = "r401", api = "https://rw.gg", token = "RT" }, false)
		viewer:on_frame()
		env:respond_next_http(401, "")
		t.assert_eq(viewer:stage(), "off")
		t.assert_contains(env.toasts[#env.toasts].text, "expired")

		viewer:start({ replay = "r404", api = "https://rw.gg", token = "RT" }, false)
		viewer:on_frame()
		env:respond_next_http(404, "")
		t.assert_contains(env.toasts[#env.toasts].text, "not on Rank Wars")

		env.fs_write_ok = false
		viewer:start({ replay = "rfs", api = "https://rw.gg", token = "RT" }, false)
		viewer:on_frame()
		env:respond_next_http(200, "DATA")
		t.assert_contains(env.toasts[#env.toasts].text, "could not be saved")
	end)

	t.test("reports patch loading and playback errors and supports cancellation", function()
		viewer:start({ replay = "rcancel", api = "https://rw.gg", token = "RT" }, false)
		viewer:cancel()
		t.assert_eq(viewer:stage(), "off")

		env.is_loading_patch = true
		viewer:start({ replay = "rpatch", api = "https://rw.gg", token = "RT" }, false)
		viewer:on_frame()
		env:respond_next_http(200, "DATA")
		env:set_scene(env.api.offsets.SCENE_MAIN_MENU, 30)
		viewer:on_frame()
		t.assert_contains(env.toasts[#env.toasts].text, "loading game version")

		env.is_loading_patch = false
		env.playback_ok = false
		env.playback_err = "busy"
		viewer:start({ replay = "rerr", api = "https://rw.gg", token = "RT" }, false)
		viewer:on_frame()
		env:respond_next_http(200, "DATA")
		viewer:on_frame()
		t.assert_eq(env.toasts[#env.toasts].kind, "error")
		t.assert_contains(env.toasts[#env.toasts].text, "busy")
	end)
end)
