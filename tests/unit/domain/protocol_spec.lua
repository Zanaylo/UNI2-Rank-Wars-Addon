local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")
local Protocol = require("src.domain.protocol")

t.suite("domain/protocol", function()
	local env
	local protocol

	t.before_each(function()
		env = FakeEnv.new()
		protocol = Protocol.new(env.api.http)
	end)

	t.test("maps roles, slugs, retries, and match statuses", function()
		t.assert_eq(protocol:other_role("host"), "guest")
		t.assert_eq(protocol:other_role("guest"), "host")
		t.assert_eq(protocol:slug("Hyde"), "hyde")
		t.assert_eq(protocol:slug(""), "")

		t.assert_true(protocol:should_retry(0))
		t.assert_true(protocol:should_retry(429))
		t.assert_true(protocol:should_retry(500))
		t.assert_true(protocol:should_retry(503))
		t.assert_false(protocol:should_retry(400))
		t.assert_false(protocol:should_retry(404))

		t.assert_eq(protocol:state_of("PENDING_ACCEPT"), "waiting")
		t.assert_eq(protocol:state_of("COMPLETED"), "completed")
		t.assert_eq(protocol:state_of("UNDER_REVIEW"), "closed")
		t.assert_eq(protocol:state_of("CANCELLED"), "closed")
		t.assert_eq(protocol:state_of("VOIDED"), "closed")
		t.assert_eq(protocol:state_of("IN_PROGRESS"), "open")
	end)

	t.test("encodes room, abort, and sandbox bodies", function()
		local room = protocol:room_body("100", "200")
		t.assert_contains(room, '"lobbyId":"100"')
		t.assert_contains(room, '"ownerSteamId":"200"')

		local long_reason = string.rep("a", 600)
		local abort = protocol:abort_body(long_reason)
		t.assert_contains(abort, string.rep("a", 500))
		t.assert_false(abort:find(string.rep("a", 501), 1, true) ~= nil)

		local sb_default = protocol:sandbox_body("pw", 0)
		t.assert_contains(sb_default, '"password":"pw"')
		t.assert_false(sb_default:find("firstTo", 1, true) ~= nil)

		local sb_custom = protocol:sandbox_body("pw", 5)
		t.assert_contains(sb_custom, '"firstTo":5')
	end)

	t.test("builds multipart game_form with optional character fields", function()
		local ct, body = protocol:game_form("BOUND", "BYTES", "game1.rep", "host", "hyde", "")
		t.assert_eq(ct, "multipart/form-data; boundary=BOUND")
		t.assert_contains(body, 'name="winner"\r\n\r\nhost')
		t.assert_contains(body, 'name="hostCharacter"\r\n\r\nhyde')
		t.assert_false(body:find("guestCharacter", 1, true) ~= nil)
		t.assert_contains(body, 'filename="game1.rep"')
		t.assert_contains(body, "BYTES")
	end)

	t.test("parses match, game answer, and sandbox responses", function()
		env:set_json("MATCH", {
			id = "M1",
			status = "IN_PROGRESS",
			role = "guest",
			firstTo = 5,
			lobbyId = "99",
			lobbyOwnerSteamId = "88",
			score = { host = 2, guest = 1 },
			host = { displayName = "Alice", steamId64 = "111" },
			guest = { displayName = "Bob", steamId64 = "222" },
			sandbox = true,
			joinRoomUrl = "https://rw.gg/join",
		})
		local m = protocol:parse_match("MATCH")
		t.assert_eq(m.role, "guest")
		t.assert_eq(m.first_to, 5)
		t.assert_table_eq(m.score, { host = 2, guest = 1 })
		t.assert_eq(m.host.name, "Alice")
		t.assert_true(m.sandbox)
		t.assert_eq(protocol:name_of_steam_id(m, "111"), "Alice")
		t.assert_eq(protocol:name_of_steam_id(m, "222"), "Bob")
		t.assert_eq(protocol:name_of_steam_id(m, "0"), "")

		env:set_json("ANS", {
			result = "RECORDED",
			match = { status = "COMPLETED", firstTo = 3, finished = true, score = { host = 3, guest = 1 } },
		})
		local a = protocol:parse_game_answer("ANS")
		t.assert_eq(a.result, "RECORDED")
		t.assert_true(a.finished)
		t.assert_eq(a.score.host, 3)

		env:set_json("SB_OK", { matchId = "S1", hostToken = "HT", guestToken = "GT", firstTo = 3 })
		local sb = protocol:parse_sandbox("SB_OK")
		t.assert_eq(sb.match, "S1")
		t.assert_eq(sb.host_token, "HT")

		env:set_json("SB_BAD", { matchId = "" })
		t.assert_nil(protocol:parse_sandbox("SB_BAD"))
		t.assert_nil(protocol:parse_match("NOT_JSON"))
	end)

	t.test("describes HTTP errors with and without JSON details", function()
		env:set_json("E1", { error = "Not found", code = "MATCH_MISSING" })
		env:set_json("E2", { error = "Bad request" })
		env:set_json("E3", {})

		t.assert_eq(protocol:describe_error(404, "E1"), "Not found (MATCH_MISSING, HTTP 404)")
		t.assert_eq(protocol:describe_error(400, "E2"), "Bad request (HTTP 400)")
		t.assert_eq(protocol:describe_error(500, "E3"), "HTTP 500")
		t.assert_eq(protocol:describe_error(502, "RAW"), "HTTP 502")
	end)
end)
