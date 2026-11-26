local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")

t.suite("presentation/window", function()
	t.test("renders status, toggles HUD checkbox, and copies sandbox guest link", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M5&token=T5&api=https://rw.gg"',
		})
		local app = env:build_app()

		app.session:initialize()
		app.session:on_frame()
		app.session:on_frame()
		env:respond_next_http(200, env:set_json("SB_VIEW", {
			id = "M5",
			status = "IN_PROGRESS",
			role = "host",
			firstTo = 3,
			score = { host = 1, guest = 2 },
			host = { displayName = "Zanaylo", steamId64 = "1" },
			guest = { displayName = "Rival", steamId64 = "2" },
			sandbox = true,
			joinRoomUrl = "https://rw.gg/join/M5",
		}))

		env.ui_clicks["Copy the guest's link"] = true
		env.ui_checkbox_change = false
		app.window:draw()

		t.assert_eq(env.ui_clipboard, "https://rw.gg/join/M5")
		t.assert_false(app.hud:is_visible())
	end)

	t.test("handles abort confirmation flow and test match creation", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M6&token=T6&api=https://rw.gg"',
		})
		env.config_store["RankWars.TestTools"] = 1
		env.config_store["RankWars.TestApi"] = "https://rw.gg"
		env.config_store["RankWars.TestPassword"] = "pass"
		local app = env:build_app()

		app.session:initialize()
		app.session:on_frame()

		env.ui_clicks["Cancel this match"] = true
		app.window:draw()
		t.assert_true(app.window.confirming)

		env.ui_clicks["Cancel this match"] = false
		env.ui_clicks["Cancel the match"] = true
		env.ui_inputs["##rw_reason"] = "lag"
		app.window:draw()
		t.assert_false(app.window.confirming)

		app.session:on_frame()
		env:respond_next_http(200, "{}")
		app.session:on_frame()
		local abort_req = env:respond_next_http(200, "{}")
		t.assert_contains(abort_req.body, "lag")

		env.ui_clicks["Cancel the match"] = false
		env.ui_collapsing_open = true
		env.ui_clicks["Create a test match"] = true
		env.ui_clicks["Show the test HUD"] = true
		app.window:draw()

		t.assert_true(app.hud:is_previewing())
		t.assert_eq(app.session:view().phase, "creating_test")
	end)
end)
