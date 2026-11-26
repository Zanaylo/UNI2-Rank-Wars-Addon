local class = require("src.core.class")

local Presence = class()

local function format_note(live, score, first_to)
	if not live then
		return ""
	end
	if first_to > 0 then
		return string.format("Rank Wars %d-%d, first to %d", score.host, score.guest, first_to)
	end
	return string.format("Rank Wars %d-%d", score.host, score.guest)
end

function Presence:init(steam)
	self.steam = steam
	self.note = ""
end

function Presence:update(live, score, first_to)
	local wanted = format_note(live, score, first_to)
	if wanted == self.note then
		return
	end
	self.note = wanted
	self.steam.set_rich_presence_note(wanted)
end

return Presence
