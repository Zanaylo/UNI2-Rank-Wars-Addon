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
		t.assert_eq(#env.events["network_menu_opened"], 1)
		t.assert_eq(#env.events["player_match_result"], 1)

		env.events["frame"][1]()
		env.events["frame"][1]()
		t.assert_eq(env.enter_network_calls, 0)

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
		t.assert_eq(env.enter_network_calls, 1)

		env:set_scene(env.api.offsets.SCENE_NETWORK, 10)
		env.events["network_menu_opened"][1](0)
		local root, rows = env:setup_create_room_screen({ room_type = 0 })
		env.events["player_match_result"][1](root, 1)
		t.assert_eq(env:get_abs(rows + env.api.offsets.ROOM_REMATCH_ROW * env.api.offsets.MENU_ROW_STRIDE + env.api.offsets.MENU_ROW_VALUE), 2)
		t.assert_eq(env:get_abs(root + env.api.offsets.PLAYER_MATCH_CREATE_ANSWER), env.api.offsets.CREATE_MENU_CREATE_ROOM)

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

	t.test("bundled dist/RankWars/main.lua runs standalone with empty package.path", function()
		local bundle_path = "dist/RankWars/main.lua"
		local f = io.open(bundle_path, "r")
		if not f then
			return
		end
		f:close()

		local saved_path = package.path
		local saved_loaded = {}
		local saved_preload = {}
		for k, v in pairs(package.loaded) do
			if k:sub(1, 4) == "src." then
				saved_loaded[k] = v
				package.loaded[k] = nil
			end
		end
		for k, v in pairs(package.preload) do
			if k:sub(1, 4) == "src." then
				saved_preload[k] = v
				package.preload[k] = nil
			end
		end

		package.path = ""
		env.fs_store[".\\addon.ini"] = "[Addon]\nVersion = 1.0.0\n"

		local ok, err = pcall(function()
			dofile(bundle_path)
			t.assert_not_nil(env.windows["rank_wars"])
			t.assert_eq(#env.events["frame"], 1)
			env.windows["rank_wars"].draw()
			env.events["frame"][1]()
			env.events["frame"][1]()
			local req = env:respond_next_http(200, env:set_json("B_MATCH", {
				id = "M123",
				status = "IN_PROGRESS",
				role = "host",
				firstTo = 3,
				score = { host = 0, guest = 0 },
				host = { displayName = "Zanaylo", steamId64 = "76561198000000001" },
				guest = { displayName = "Rival", steamId64 = "76561198000000002" },
			}))
			t.assert_eq(req.method, "GET")
		end)

		package.path = saved_path
		for k in pairs(package.loaded) do
			if k:sub(1, 4) == "src." then
				package.loaded[k] = nil
			end
		end
		for k, v in pairs(saved_loaded) do
			package.loaded[k] = v
		end
		for k in pairs(package.preload) do
			if k:sub(1, 4) == "src." then
				package.preload[k] = nil
			end
		end
		for k, v in pairs(saved_preload) do
			package.preload[k] = v
		end

		if not ok then
			error(err, 0)
		end
	end)
end)
