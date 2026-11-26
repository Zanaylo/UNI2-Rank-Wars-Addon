local class = require("src.core.class")
local cooldown = require("src.core.cooldown")
local RoomCreator = require("src.infra.room_creator")

local RoomFlow = class()

local kLeaveTrainingSettleFrames = 90
local kLeaveTrainingRetryMs = 5000
local kNetworkRetryMs = 5000
local kJoinTimeoutMs = 45000
local kMainMenuFrames = 30
local kNetworkMenuRunning = 1
local kNetworkListIdle = 1
local kMaxNetworkAttempts = 1

function RoomFlow:init(deps)
	self.game = deps.game
	self.steam = deps.steam
	self.mem = deps.mem
	self.offsets = deps.offsets
	self.time = deps.time
	self.creator = deps.room_creator or RoomCreator.new({
		game = deps.game,
		mem = deps.mem,
		offsets = deps.offsets,
		time = deps.time,
		log = deps.log,
		warn = deps.warn,
	})
	self.leave_cooldown = cooldown.Cooldown.new(kLeaveTrainingRetryMs, deps.time)
	self.network_cooldown = cooldown.Cooldown.new(kNetworkRetryMs, deps.time)
	self.tracked_scene = nil
	self.tracked_frames = 0
	self.network_attempts = 0
	self.saw_network = false
	self.attempt_counted = false
	self.enter_network_cb = function()
		return self:try_enter_network()
	end
end

function RoomFlow:reset()
	self.leave_cooldown:reset()
	self.network_cooldown:reset()
	self.tracked_scene = nil
	self.tracked_frames = 0
	self.network_attempts = 0
	self.saw_network = false
	self.attempt_counted = false
	self.creator:stop()
end

function RoomFlow:reset_leave_cooldown()
	self.leave_cooldown:reset()
end

function RoomFlow:request_network_entry()
	self.game.claim_pad()
	if self.game.request_scene then
		return self.game.request_scene(self.offsets.SCENE_NETWORK)
	end
	return self.game.enter_network()
end

function RoomFlow:request_main_menu()
	if self.game.request_scene then
		return self.game.request_scene(self.offsets.SCENE_MAIN_MENU)
	end
	return self.game.leave_training()
end

function RoomFlow:note_network_scene()
	if self.game.scene() ~= self.offsets.SCENE_NETWORK then
		return
	end
	if not self.saw_network then
		self.saw_network = true
		if not self.attempt_counted then
			self.network_attempts = self.network_attempts + 1
		end
		self.attempt_counted = false
	end
end

function RoomFlow:try_enter_network()
	if not self.network_cooldown:ready() then
		return nil
	end
	if self.network_attempts >= kMaxNetworkAttempts then
		return "network_error"
	end
	self.network_cooldown:mark()
	self.network_attempts = self.network_attempts + 1
	self.attempt_counted = true
	self:request_network_entry()
	return nil
end

function RoomFlow:handle_network_bounce()
	if not self.saw_network or self.game.scene() ~= self.offsets.SCENE_MAIN_MENU then
		return nil
	end
	self.saw_network = false
	return "network_error"
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
		self:request_main_menu()
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

	if self.steam.is_ready and not self.steam.is_ready() then
		self:stop_host_room()
		return "steam_offline"
	end

	self:note_network_scene()

	local bounce = self:handle_network_bounce()
	if bounce then
		self:stop_host_room()
		return bounce
	end

	local main_menu_frames = self.steam.lobby() == "0" and self:scene_frames_for(self.offsets.SCENE_MAIN_MENU) or 0
	local outcome = self.creator:step(first_to, main_menu_frames, self.enter_network_cb)
	if outcome then
		self:stop_host_room()
		return outcome
	end

	return nil
end

function RoomFlow:stop_host_room()
	self.creator:stop()
end

function RoomFlow:host_room_status_text()
	return self.creator:status_text()
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

	if self.steam.is_ready and not self.steam.is_ready() then
		return "steam_offline"
	end

	if self.steam.lobby() ~= "0" then
		return nil
	end

	if self.game.scene() == self.offsets.SCENE_NETWORK then
		self:note_network_scene()
		if self.creator:check_network_error() then
			return "network_error"
		end
	end

	local bounce = self:handle_network_bounce()
	if bounce then
		return bounce
	end

	if self:scene_frames_for(self.offsets.SCENE_MAIN_MENU) >= kMainMenuFrames then
		return self:try_enter_network()
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

	if self.creator:raw_network_error() then
		return "flow_error"
	end

	if self.time() - started_at >= kJoinTimeoutMs then
		return "timed_out"
	end

	return nil
end

return RoomFlow
