local t = require("tests.support.runner")
local spies = require("tests.support.spies")
local FakeEnv = require("tests.support.fake_env")
local launch_link = require("src.domain.launch_link")
local LaunchWatcher = require("src.infra.launch_watcher")

local function create_watcher(env)
	return LaunchWatcher.new({
		steam = env.api.steam,
		config = env.api.config,
		time = env.api.time,
		launch_link = launch_link,
	})
end

t.suite("infra/launch_watcher", function()
	t.test("check_initial parses initial command line", function()
		local env = FakeEnv.new({
			command_line = 'uni2.exe "?action=create&match=M1&token=T1&api=https://rw.gg"',
		})
		local watcher = create_watcher(env)
		local cb, rec = spies.new()

		watcher:check_initial(cb)

		t.assert_eq(rec:count(), 1)
		t.assert_eq(rec:last()[1].match, "M1")
	end)

	t.test("polls Steam query values on cooldown and deduplicates identical values", function()
		local env = FakeEnv.new()
		local watcher = create_watcher(env)
		local cb, rec = spies.new()

		env.launch_queries = {
			action = "create",
			match = "M2",
			token = "T2",
			api = "https://rw.gg",
		}

		watcher:poll(cb)
		t.assert_eq(rec:count(), 1)

		watcher:poll(cb)
		t.assert_eq(rec:count(), 1)

		env:advance(2000)
		watcher:poll(cb)
		t.assert_eq(rec:count(), 1)

		env.launch_queries.match = "M3"
		env:advance(2000)
		watcher:poll(cb)
		t.assert_eq(rec:count(), 2)
	end)

	t.test("falls back to Steam launch command line when query values are empty", function()
		local env = FakeEnv.new()
		local watcher = create_watcher(env)
		local cb, rec = spies.new()

		env.launch_cmd = "?action=replay&replay=rep_9&token=RT&api=https://rw.gg"
		watcher:poll(cb)

		t.assert_eq(rec:count(), 1)
		t.assert_eq(rec:last()[1].action, "replay")
		t.assert_eq(rec:last()[1].replay, "rep_9")
	end)
end)
