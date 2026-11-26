local class = require("src.core.class")
local cooldown = require("src.core.cooldown")

local LaunchWatcher = class()

local kPollIntervalMs = 2000

local function build_fingerprint(cmd, link, err)
	local match_id = link and link.match or ""
	local token = link and link.token or ""
	local replay_id = link and link.replay or ""
	return cmd .. "\n" .. match_id .. "\n" .. token .. "\n" .. replay_id .. "\n" .. (err or "")
end

function LaunchWatcher:init(deps)
	local steam = deps.steam
	self.steam = steam
	self.config = deps.config
	self.launch_link = deps.launch_link
	self.cooldown = cooldown.Cooldown.new(kPollIntervalMs, deps.time)
	self.query_getter = function(key)
		return steam.launch_query(key)
	end
	self.seen = ""
end

function LaunchWatcher:check_initial(on_link)
	local link, err = self.launch_link.parse_command_line(self.config.command_line())
	on_link(link, err)
end

function LaunchWatcher:poll(on_link)
	if not self.cooldown:try_trigger() then
		return
	end

	local cmd = self.steam.launch_command_line()
	local q_link, q_err = self.launch_link.parse_query_values(self.query_getter)
	local fingerprint = build_fingerprint(cmd, q_link, q_err)

	if fingerprint == self.seen then
		return
	end
	self.seen = fingerprint

	if q_link or (q_err and q_err ~= "") then
		on_link(q_link, q_err)
		return
	end

	if cmd == "" then
		return
	end

	local link, err = self.launch_link.parse_launch_parameters(cmd)
	on_link(link, err)
end

return LaunchWatcher
