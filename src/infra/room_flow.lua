local class = require("src.core.class")
local cooldown = require("src.core.cooldown")

local RoomFlow = class()

local kLeaveTrainingSettleFrames = 90
local kLeaveTrainingRetryMs = 5000
local kNetworkRetryMs = 5000
local kJoinTimeoutMs = 45000
local kMainMenuFrames = 30
local kNetworkMenuRunning = 1
local kNetworkListIdle = 1
local kCreateStageIdle = 0
local kCreateStageArmed = 1

function RoomFlow:init(deps)
	self.game = deps.game
	self.steam = deps.steam
	self.mem = deps.mem
	self.offsets = deps.offsets
	self.time = deps.time
	self.leave_cooldown = cooldown.Cooldown.new(kLeaveTrainingRetryMs, deps.time)
	self.network_cooldown = cooldown.Cooldown.new(kNetworkRetryMs, deps.time)
	self.tracked_scene = nil
	self.tracked_frames = 0
end

function RoomFlow:reset_leave_cooldown()
	self.leave_cooldown:reset()
end

function RoomFlow:scene_frames_for(expected_scene)
	local current = self.game.scene()
	if current ~= expected_scene then
		self.tracked_scene = current
		self.tracked_frames = 0
		return 0
	end
	if self.tracked_scene ~= current then
		self.tracked_scene = current
		self.tracked_frames = 0
	end
	self.tracked_frames = self.tracked_frames + 1
	return math.max(self.game.scene_frames(), self.tracked_frames)
end

function RoomFlow:leave_training_if_needed()
	if self.game.scene() ~= self.offsets.SCENE_BATTLE or not self.game.is_training() then
		return false
	end
	if self:scene_frames_for(self.offsets.SCENE_BATTLE) < kLeaveTrainingSettleFrames then
		return true
	end
	if self.leave_cooldown:try_trigger() then
		self.game.leave_training()
	end
	return true
end

function RoomFlow:owned_lobby(self_id)
	local lobby = self.steam.lobby()
	if lobby == "0" or self.steam.lobby_owner(lobby) ~= self_id then
		return nil
	end
	return lobby
end

function RoomFlow:step_host_room(first_to)
	if self:leave_training_if_needed() then
		return nil
	end

	if self.game.room_create_stage() == kCreateStageIdle then
		self.game.room_create_start(first_to)
	end
	self.game.room_create_set_first_to(first_to)
	local stage = self.game.room_create_step()

	if stage == kCreateStageArmed and self.steam.lobby() == "0"
		and self:scene_frames_for(self.offsets.SCENE_MAIN_MENU) >= kMainMenuFrames
	then
		if self.network_cooldown:try_trigger() then
			self.game.enter_network()
		end
	end

	if self.game.room_create_timed_out() then
		return "timed_out"
	end
	return nil
end

function RoomFlow:stop_host_room()
	self.game.room_create_stop()
end

function RoomFlow:host_room_status_text()
	local _, text = self.game.room_create_stage()
	return text
end

function RoomFlow:is_network_list_ready()
	if self.game.scene() ~= self.offsets.SCENE_NETWORK then
		return false
	end
	local menu_state = self.mem.read_rva_i32(self.offsets.NETWORK_MENU + self.offsets.NETWORK_MENU_STATE)
	local list_state = self.mem.read_rva_i32(self.offsets.NETWORK_MENU + self.offsets.NETWORK_MENU_LIST)
	return menu_state == kNetworkMenuRunning and list_state == kNetworkListIdle
end

function RoomFlow:step_guest_prepare(target_lobby, target_owner)
	if self.steam.lobby() == target_lobby then
		return "joined"
	end

	if self:leave_training_if_needed() then
		return nil
	end

	if self.steam.lobby() ~= "0" then
		return nil
	end

	if self:scene_frames_for(self.offsets.SCENE_MAIN_MENU) >= kMainMenuFrames then
		if self.network_cooldown:try_trigger() then
			self.game.enter_network()
		end
		return nil
	end

	if not self:is_network_list_ready() then
		return nil
	end

	if not self.game.can_join_room() then
		return "unsupported"
	end

	self.game.claim_pad()
	self.game.join_room(target_lobby, target_owner)
	return "joining"
end

function RoomFlow:step_guest_joining(target_lobby, started_at)
	if self.steam.lobby() == target_lobby then
		return "joined"
	end

	if self.mem.read_rva_i32(self.offsets.NETWORK_FLOW_ERROR) ~= 0 then
		return "flow_error"
	end

	if self.time() - started_at >= kJoinTimeoutMs then
		return "timed_out"
	end

	return nil
end

return RoomFlow
