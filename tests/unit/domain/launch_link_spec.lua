local t = require("tests.support.runner")
local launch_link = require("src.domain.launch_link")

t.suite("domain/launch_link", function()
	t.test("url_decode handles percent encoding, pluses, invalid escapes, and empty input", function()
		t.assert_eq(launch_link.url_decode(nil), "")
		t.assert_eq(launch_link.url_decode(""), "")
		t.assert_eq(launch_link.url_decode("https%3A%2F%2Frw.gg%2Fapi+v1"), "https://rw.gg/api v1")
		t.assert_eq(launch_link.url_decode("bad%ZZand%2"), "bad%ZZand%2")
	end)

	t.test("parse_command_line parses quoted and unquoted query tokens", function()
		local link, err = launch_link.parse_command_line('uni2.exe "?action=create&match=M1&token=T1&api=https%3A%2F%2Frw.gg/"')
		t.assert_nil(err)
		t.assert_eq(link.action, "create")
		t.assert_eq(link.match, "M1")
		t.assert_eq(link.token, "T1")
		t.assert_eq(link.api, "https://rw.gg")

		local unquoted, uerr = launch_link.parse_command_line("uni2.exe ?action=create&match=M2&token=T2&api=http://localhost:3000 -windowed")
		t.assert_nil(uerr)
		t.assert_eq(unquoted.match, "M2")
		t.assert_eq(unquoted.api, "http://localhost:3000")
	end)

	t.test("parse_command_line returns nil without error when no query exists", function()
		local link, err = launch_link.parse_command_line("uni2.exe -fullscreen")
		t.assert_nil(link)
		t.assert_nil(err)
	end)

	t.test("parse_launch_parameters parses join and replay links", function()
		local jl, jerr = launch_link.parse_launch_parameters("/?action=join&match=M9&token=T9&api=https%3A%2F%2Frw.gg&lobby=109775240912345&owner=76561198000000002")
		t.assert_nil(jerr)
		t.assert_eq(jl.action, "join")
		t.assert_eq(jl.lobby, "109775240912345")
		t.assert_eq(jl.owner, "76561198000000002")

		local rl, rerr = launch_link.parse_launch_parameters("action=replay&match=IGNORED&replay=rep_42-a&token=RT&api=https://rw.gg")
		t.assert_nil(rerr)
		t.assert_eq(rl.action, "replay")
		t.assert_eq(rl.replay, "rep_42-a")
		t.assert_eq(rl.match, "")
	end)

	t.test("validates action, api scheme, credentials, join ids, and replay ids", function()
		local _, e1 = launch_link.parse_launch_parameters("action=unknown&api=https://rw.gg")
		t.assert_contains(e1, "create or join")

		local _, e2 = launch_link.parse_launch_parameters("action=create&match=M1&token=T1&api=ftp://rw.gg")
		t.assert_contains(e2, "http address")

		local _, e3 = launch_link.parse_launch_parameters("action=create&match=M1&api=https://rw.gg")
		t.assert_contains(e3, "match or token")

		local _, e4 = launch_link.parse_launch_parameters("action=join&match=M1&token=T1&api=https://rw.gg&lobby=0&owner=123")
		t.assert_contains(e4, "lobby or owner")

		local _, e5 = launch_link.parse_launch_parameters("action=replay&replay=../bad&token=RT&api=https://rw.gg")
		t.assert_contains(e5, "valid replay")

		local _, e6 = launch_link.parse_launch_parameters("action=replay&replay=rep_1&api=https://rw.gg")
		t.assert_contains(e6, "no token")
	end)

	t.test("parse_query_values, host_link, and action_name work as expected", function()
		local values = { action = "create", match = "M7", token = "TK", api = "https://rw.gg" }
		local link, err = launch_link.parse_query_values(function(k)
			return values[k]
		end)
		t.assert_nil(err)
		t.assert_eq(link.match, "M7")

		local empty, eerr = launch_link.parse_query_values(function()
			return ""
		end)
		t.assert_nil(empty)
		t.assert_nil(eerr)

		local hl, herr = launch_link.host_link("M8", "T8", "https://rw.gg")
		t.assert_nil(herr)
		t.assert_eq(hl.action, "create")

		t.assert_eq(launch_link.action_name("create"), "host")
		t.assert_eq(launch_link.action_name("join"), "guest")
		t.assert_eq(launch_link.action_name("replay"), "viewer")
		t.assert_eq(launch_link.action_name("other"), "none")
	end)
end)
