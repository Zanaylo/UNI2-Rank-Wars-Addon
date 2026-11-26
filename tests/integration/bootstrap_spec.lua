local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")

t.suite("integration/bootstrap", function()
	local previous_uni2
	local env

	t.before_each(function()
		previous_uni2 = _G.uni2
		env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M123&token=TOK_HOST&api=https%3A%2F%2Frankwars.test"',
		})
		_G.uni2 = env.api
	end)

	t.after_each(function()
		_G.uni2 = previous_uni2
	end)

	t.test("main.lua wires window and events and runs a full host match flow", function()
		dofile("main.lua")

		t.assert_not_nil(env.windows["rank_wars"])
		t.assert_eq(env.windows["rank_wars"].opts.max_width, 560)
		t.assert_eq(env.windows["rank_wars"].opts.max_height, 680)
		t.assert_eq(#env.events["frame"], 1)
		t.assert_eq(#env.events["hud"], 1)
		t.assert_eq(#env.events["game_started"], 1)
		t.assert_eq(#env.events["game_ended"], 1)

		env.events["frame"][1]()
		env.events["frame"][1]()
		t.assert_false(env.room_create_started)

		local match_body = env:set_json("INT_MATCH", {
			id = "M123",
			status = "IN_PROGRESS",
			role = "host",
			firstTo = 3,
			score = { host = 0, guest = 0 },
			host = { displayName = "Zanaylo", steamId64 = "76561198000000001" },
			guest = { displayName = "Rival", steamId64 = "76561198000000002" },
		})
		env:respond_next_http(200, match_body)

		env.events["frame"][1]()
		t.assert_true(env.room_create_started)
		t.assert_eq(env.room_create_first_to, 3)

		env:set_lobby("109775240999999", "76561198000000001")
		env.events["frame"][1]()
		env.events["frame"][1]()
		local room_req = env:respond_next_http(200, "{}")
		t.assert_eq(room_req.method, "PUT")
		t.assert_contains(room_req.url, "/room")

		env.events["frame"][1]()
		env:respond_next_http(200, match_body)

		env.in_match = true
		env.is_online = true
		env.events["hud"][1]()
		t.assert_true(#env.draw_fills > 0)

		env.windows["rank_wars"].draw()
		env.windows["rank_wars"].open = true
		env.events["game_started"][1]()
		t.assert_false(env.windows["rank_wars"].open)
		env.events["frame"][1]()
		env:respond_next_http(200, match_body)

		env.events["game_ended"][1]({
			ending = "decided",
			winner = 0,
			local_side = 0,
			steam_id = { "76561198000000001", "76561198000000002" },
			chara = { 0, 1 },
			record = "MOCK_REPLAY_PAYLOAD",
		})
		env.events["frame"][1]()
		local game_req = env:respond_next_http(200, env:set_json("INT_GAME1", {
			result = "RECORDED",
			match = { status = "IN_PROGRESS", firstTo = 3, finished = false, score = { host = 1, guest = 0 } },
		}))
		t.assert_eq(game_req.method, "PUT")
		t.assert_contains(game_req.url, "/games/1")
	end)
end)
