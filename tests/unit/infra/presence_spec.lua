local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")
local Presence = require("src.infra.presence")

t.suite("infra/presence", function()
	t.test("formats rich presence with and without first_to and avoids duplicate updates", function()
		local env = FakeEnv.new()
		local presence = Presence.new(env.api.steam)

		presence:update(true, { host = 2, guest = 1 }, 3)
		presence:update(true, { host = 2, guest = 1 }, 3)
		t.assert_table_eq(env.presence_notes, { "Rank Wars 2-1, first to 3" })

		presence:update(true, { host = 2, guest = 2 }, 0)
		presence:update(false, { host = 2, guest = 2 }, 3)
		t.assert_table_eq(env.presence_notes, {
			"Rank Wars 2-1, first to 3",
			"Rank Wars 2-2",
			"",
		})
	end)
end)
