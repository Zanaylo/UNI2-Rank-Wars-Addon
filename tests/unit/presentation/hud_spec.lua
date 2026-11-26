local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")

t.suite("presentation/hud", function()
	local env
	local hud

	t.before_each(function()
		env = FakeEnv.new()
		hud = env:build_app().hud
	end)

	t.test("draws nothing outside a match or when hidden, offline, or spectating", function()
		local board = { is_host = true, score = { host = 2, guest = 1 }, first_to = 3 }
		local function get_board()
			return board
		end

		hud:draw(get_board)
		t.assert_eq(#env.draw_fills, 0)

		env.in_match = true
		hud:draw(get_board)
		t.assert_eq(#env.draw_fills, 0)

		env.is_online = true
		env.is_spectating = true
		hud:draw(get_board)
		t.assert_eq(#env.draw_fills, 0)

		env.is_spectating = false
		hud:set_visible(false)
		t.assert_eq(env.config_store["RankWars.ShowHud"], 0)
		hud:draw(get_board)
		t.assert_eq(#env.draw_fills, 0)
	end)

	t.test("draws score pips for live match and preview mode", function()
		env.in_match = true
		env.is_online = true
		hud:draw(function()
			return { is_host = false, score = { host = 1, guest = 2 }, first_to = 3 }
		end)
		t.assert_eq(#env.draw_fills, 36)

		env.draw_fills = {}
		env.is_online = false
		hud:set_previewing(true)
		hud:draw(function()
			return nil
		end)
		t.assert_eq(#env.draw_fills, 60)
	end)
end)
