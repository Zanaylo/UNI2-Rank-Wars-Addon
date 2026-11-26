local class = require("src.core.class")
local StateMachine = require("src.core.state_machine")

local ReplayViewer = class()

local kToastTitle = "RANK WARS"
local kMainMenuSettleFrames = 30

local kFailureText = {
	[401] = "The Watch link expired. Press Watch again on the panel",
	[403] = "This replay is not on Rank Wars",
	[404] = "This replay is not on Rank Wars",
}

local kStates = {
	off = {
		on_enter = function(self)
			self.api = nil
		end,
	},
	downloading = {},
	waiting = {
		on_update = function(self)
			self:step_waiting()
		end,
	},
}

local function failure_text(status)
	return kFailureText[status] or "The replay could not be downloaded"
end

function ReplayViewer:init(deps)
	self.game = deps.game
	self.replay = deps.replay
	self.fs = deps.fs
	self.offsets = deps.offsets
	self.toast = deps.toast
	self.log = deps.log
	self.client_factory = deps.client_factory
	self.room_flow = deps.room_flow
	self.fsm = StateMachine.new("off", kStates)
	self.api = nil
	self.replay_id = ""
	self.path = ""
	self.matchup = ""
end

function ReplayViewer:stage()
	return self.fsm:state()
end

function ReplayViewer:reset()
	self.fsm:transition("off", self)
end

function ReplayViewer:fail(message)
	self.toast("error", kToastTitle, message)
	self:reset()
end

function ReplayViewer:cancel()
	if self.fsm:is("off") then
		return
	end
	self.log("replay " .. self.replay_id .. " dropped, a match link came in")
	self:reset()
end

function ReplayViewer:on_downloaded(answer)
	if not self.fsm:is("downloading") then
		return
	end

	if not answer.ok or answer.body == "" then
		self:fail(failure_text(answer.status))
		return
	end

	local folder = self.replay.folder()
	self.fs.mkdir(folder)
	local path = folder .. "RankWars_" .. self.replay_id .. ".rep"

	if not self.fs.write(path, answer.body) then
		self:fail("The replay could not be saved")
		return
	end

	self.replay.refresh()
	self.path = path
	self.matchup = self.replay.matchup_of(path)
	self.room_flow:reset_leave_cooldown()
	self.fsm:transition("waiting", self)
	self.toast("info", kToastTitle, self.matchup .. " is ready. It starts in the main menu")
end

function ReplayViewer:start(link, match_live)
	if match_live then
		self.toast("warning", kToastTitle, "Finish the Rank Wars match first, then press Watch again")
		return
	end

	self.replay_id = link.replay
	self.path = ""
	self.matchup = ""
	self.api = self.client_factory(link.api, link.token, "0")
	self.fsm:transition("downloading", self)

	self.toast("info", kToastTitle, "Downloading the replay")
	self.api:fetch_replay(link.replay, function(answer)
		self:on_downloaded(answer)
	end)
end

function ReplayViewer:launch_playback()
	self:reset()

	local ok, err = self.replay.request_playback(self.path)
	if not ok then
		self.toast("error", kToastTitle, "The replay could not start: " .. tostring(err))
		return
	end

	if self.replay.is_loading_patch() then
		self.toast("info", kToastTitle, self.matchup .. ": loading game version, starts automatically")
		return
	end

	self.toast("success", kToastTitle, "Playing " .. self.matchup)
end

function ReplayViewer:step_waiting()
	if self.room_flow:leave_training_if_needed() then
		return
	end

	if self.room_flow:scene_frames_for(self.offsets.SCENE_MAIN_MENU) < kMainMenuSettleFrames then
		return
	end

	if not self.replay.can_play() then
		return
	end

	self:launch_playback()
end

function ReplayViewer:on_frame()
	if self.api then
		self.api:tick()
	end
	self.fsm:update(self)
end

return ReplayViewer
