local class = require("src.core.class")
local cooldown = require("src.core.cooldown")

local ScoreTracker = class()

local kScoreCheckDelays = { 2000, 5000, 10000, 15000 }

local function default_info()
	return {
		status = "",
		first_to = 0,
		score = { host = 0, guest = 0 },
		host = { name = "", steam_id = "0" },
		guest = { name = "", steam_id = "0" },
		sandbox = false,
		join_url = "",
	}
end

function ScoreTracker:init(clock_fn)
	self.info = default_info()
	self.played = 0
	self.local_wins = { host = 0, guest = 0 }
	self.answered_games = 0
	self.match_loaded = false
	self.score_due = false
	self.backoff = cooldown.Backoff.new(kScoreCheckDelays, clock_fn)
end

function ScoreTracker:reset()
	self.info = default_info()
	self.played = 0
	self.local_wins.host = 0
	self.local_wins.guest = 0
	self.answered_games = 0
	self.match_loaded = false
	self.score_due = false
	self.backoff:reset()
end

function ScoreTracker:is_decided(score, first_to)
	local s = score or self.info.score
	local ft = first_to or self.info.first_to
	return ft > 0 and (s.host >= ft or s.guest >= ft)
end

function ScoreTracker:apply_match(parsed)
	local changed = self.info.score.host ~= parsed.score.host or self.info.score.guest ~= parsed.score.guest
	self.info = parsed
	self.match_loaded = true

	local recorded = parsed.score.host + parsed.score.guest
	if recorded > self.played then
		self.played = recorded
	end

	return changed
end

function ScoreTracker:record_local_game(winner_role)
	self.played = self.played + 1
	self.local_wins[winner_role] = (self.local_wins[winner_role] or 0) + 1
	return self.played
end

function ScoreTracker:apply_game_answer(game_num, parsed)
	local incoming = parsed.score.host + parsed.score.guest
	local current = self.info.score.host + self.info.score.guest
	if incoming >= current then
		self.info.score = parsed.score
	end
	if parsed.first_to > 0 then
		self.info.first_to = parsed.first_to
	end
	if game_num > self.answered_games then
		self.answered_games = game_num
	end
end

function ScoreTracker:is_settled(live, finished)
	if not live or finished or self:is_decided() then
		return true
	end
	local total = self.info.score.host + self.info.score.guest
	return total >= self.answered_games
		and self.info.score.host >= self.local_wins.host
		and self.info.score.guest >= self.local_wins.guest
end

function ScoreTracker:sync_reconciliation(live, finished)
	local settled = self:is_settled(live, finished)
	if not settled and not self.score_due then
		self.backoff:reset()
		self.backoff:schedule_next(true)
	end
	self.score_due = not settled
end

function ScoreTracker:should_poll()
	return self.score_due and self.backoff:ready()
end

function ScoreTracker:mark_polled()
	self.backoff:schedule_next(true)
end

return ScoreTracker
