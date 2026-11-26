local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")

local function host_match_json(env, overrides)
	overrides = overrides or {}
	return env:set_json("MATCH_" .. tostring(overrides.tag or "1"), {
		id = overrides.id or "M123",
		status = overrides.status or "IN_PROGRESS",
		role = overrides.role or "host",
		firstTo = overrides.firstTo or 3,
		score = overrides.score or { host = 0, guest = 0 },
		host = { displayName = "Zanaylo", steamId64 = "76561198000000001" },
		guest = { displayName = "Rival", steamId64 = "76561198000000002" },
		sandbox = overrides.sandbox or false,
		joinRoomUrl = overrides.joinRoomUrl or "",
	})
end

t.suite("app/session", function()
	t.test("host waits for GET /match before starting room creation and stops room creation on exit", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M123&token=TOK_HOST&api=https%3A%2F%2Frankwars.test"',
		})
		local app = env:build_app()
		local session = app.session

		session:initialize()
		t.assert_eq(session:view().phase, "waiting_steam")
		t.assert_true(env.windows["rank_wars"].open)

		session:on_frame()
		session:on_frame()
		t.assert_false(app.room_creator:is_active())
		t.assert_eq(session:view().detail, "Reading match settings")

		local req = env:respond_next_http(200, host_match_json(env))
		t.assert_eq(req.method, "GET")

		session:on_frame()
		t.assert_true(app.room_creator:is_active())
		t.assert_eq(app.room_creator.first_to, 3)

		env:set_lobby("109775240999999", "76561198000000001")
		session:on_frame()
		t.assert_false(app.room_creator:is_active())

		session:on_frame()
		local room_req = env:respond_next_http(200, "{}")
		t.assert_eq(room_req.method, "PUT")
		t.assert_contains(room_req.url, "/room")
		t.assert_eq(session:view().phase, "in_match")
		t.assert_false(app.room_creator:is_active())
	end)

	t.test("auto-closes window on game_started and uploads replay on game_ended", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M123&token=TOK_HOST&api=https://rw.gg"',
		})
		local session = env:build_app().session
		local match_body = host_match_json(env)

		session:initialize()
		session:on_frame()
		session:on_frame()
		env:respond_next_http(200, match_body)
		env:set_lobby("555", "76561198000000001")
		session:on_frame()
		session:on_frame()
		env:respond_next_http(200, "{}")
		session:on_frame()
		env:respond_next_http(200, match_body)

		env.windows["rank_wars"].open = true
		session:on_game_started()
		t.assert_false(env.windows["rank_wars"].open)
		session:on_frame()
		env:respond_next_http(200, match_body)

		session:on_game_ended({
			ending = "decided",
			winner = 0,
			local_side = 0,
			chara = { 0, 1 },
			record = "REPLAY_BYTES",
		})
		session:on_frame()
		local put_req = env:respond_next_http(200, env:set_json("G1", {
			result = "RECORDED",
			match = { status = "IN_PROGRESS", firstTo = 3, finished = false, score = { host = 1, guest = 0 } },
		}))
		t.assert_eq(put_req.method, "PUT")
		t.assert_contains(put_req.url, "/games/1")
		t.assert_eq(session:view().score.host, 1)
		t.assert_eq(session:scoreboard().first_to, 3)
	end)

	t.test("ignores connection_lost endings and finishes when target score is reached", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M123&token=TOK_HOST&api=https://rw.gg"',
		})
		local session = env:build_app().session
		local match_body = host_match_json(env, { firstTo = 1 })

		session:initialize()
		session:on_frame()
		session:on_frame()
		env:respond_next_http(200, match_body)

		session:on_game_ended({ ending = "connection_lost", winner = 0, local_side = 0, chara = { 0, 1 }, record = "R" })
		t.assert_eq(#env.http_queue, 0)

		session:on_game_ended({ ending = "decided", winner = 0, local_side = 0, chara = { 0, 1 }, record = "R" })
		session:on_frame()
		env:respond_next_http(200, env:set_json("GFIN", {
			result = "RECORDED",
			match = { status = "COMPLETED", firstTo = 1, finished = true, score = { host = 1, guest = 0 } },
		}))
		t.assert_eq(session:view().phase, "finished")
	end)

	t.test("guest joins room, handles timeout, and retries after failure", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=join&match=M9&token=TG&api=https://rw.gg&lobby=777&owner=222"',
		})
		local session = env:build_app().session

		session:initialize()
		env:set_scene(env.api.offsets.SCENE_NETWORK, 10)
		session:on_frame()
		t.assert_eq(session:view().phase, "joining")
		t.assert_eq(env.joined_lobby, "777")

		env:advance(45000)
		session:on_frame()
		t.assert_eq(session:view().phase, "failed")
		t.assert_true(session:can_retry())

		session:retry()
		t.assert_eq(session:view().phase, "waiting_join")

		env:set_lobby("777", "222")
		session:on_frame()
		t.assert_eq(session:view().phase, "in_match")
	end)

	t.test("handles PENDING_ACCEPT, closed match statuses, abort, and sandbox creation", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M1&token=T1&api=https://rw.gg"',
		})
		local session = env:build_app().session

		session:initialize()
		session:on_frame()
		session:on_frame()
		env:respond_next_http(200, host_match_json(env, { status = "PENDING_ACCEPT", tag = "wait" }))
		t.assert_eq(session:view().phase, "failed")

		session:retry()
		session:on_frame()
		env:respond_next_http(200, host_match_json(env, { status = "CANCELLED", tag = "cancel" }))
		t.assert_eq(session:view().phase, "closed")
		t.assert_contains(session:view().detail, "cancelled")

		t.assert_true(session:can_start_test())
		session:start_test("https://rw.gg", "secret", 3)
		t.assert_eq(session:view().phase, "creating_test")
		session:on_frame()
		env:respond_next_http(200, env:set_json("SB", { matchId = "SB1", hostToken = "SBT", firstTo = 3 }))
		t.assert_eq(session:view().phase, "waiting_steam")
		t.assert_eq(session:view().match, "SB1")

		session:on_frame()
		t.assert_true(session:can_abort())
		session:abort("")
		session:on_frame()
		env:respond_next_http(200, host_match_json(env, { id = "SB1", tag = "sb" }))
		session:on_frame()
		local abort_req = env:respond_next_http(200, "{}")
		t.assert_eq(abort_req.method, "POST")
		t.assert_contains(abort_req.url, "/abort")
		t.assert_eq(session:view().phase, "aborted")
	end)

	t.test("surfaces host network failure in window and error toast, then resets on retry", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M77&token=TOK_HOST&api=https://rw.gg"',
		})
		local app = env:build_app()
		local session = app.session
		local match_body = host_match_json(env, { id = "M77", tag = "net" })

		session:initialize()
		session:on_frame()
		session:on_frame()
		env:respond_next_http(200, match_body)

		env.windows["rank_wars"].open = false
		env:set_scene(env.api.offsets.SCENE_NETWORK, 60)
		app.room_creator:start(3)
		app.room_creator:note_stage("creating_room")
		session:on_frame()

		env:set_mem(env.api.offsets.NETWORK_FLOW_ERROR, 3)
		session:on_frame()

		t.assert_eq(session:view().phase, "failed")
		t.assert_contains(session:view().error, "restart the game")
		t.assert_true(env.windows["rank_wars"].open)
		t.assert_true(#env.toasts >= 1)
		t.assert_eq(env.toasts[#env.toasts].kind, "error")

		env:set_mem(env.api.offsets.NETWORK_FLOW_ERROR, 0)
		session:retry()
		t.assert_eq(session:view().phase, "waiting_room")
		t.assert_eq(session:view().error, "")
	end)
end)
