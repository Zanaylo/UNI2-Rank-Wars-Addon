local class = require("src.core.class")

local RoomCreator = class()

local kMenuSettleFrames = 30
local kPickRetryFrames = 60
local kMaxPickAttempts = 4
local kCardDismissTimeoutFrames = 90
local kMainMenuFrames = 30
local kNetworkMenuRunning = 1
local kNetworkListIdle = 1
local kNetworkResultCreateRoom = 6
local kRematchUnlimited = 10
local kMostWinsListed = 10
local kGiveUpMs = 120000
local kLegacyStageIdle = 0
local kLegacyStageArmed = 1
local kLegacyStageEntering = 2
local kLegacyStageFailed = 6
local kDefaultStepError = 10

local kStageText = {
	idle = "Create a Player Match room and it is sent by itself",
	armed = "Go to the main menu and the room is created for you",
	entering_network = "Opening Network",
	picking_create_room = "Opening Player Match",
	opening_player_match = "Opening Player Match",
	creating_room = "Creating the room",
	failed = "Network error while creating the room",
}

local function rematch_limit_for(first_to)
	if first_to <= 0 or first_to > kMostWinsListed then
		return kRematchUnlimited
	end
	return first_to - 1
end

function RoomCreator:init(deps)
	self.game = deps.game
	self.mem = deps.mem
	self.offsets = deps.offsets
	self.time = deps.time
	self.log = deps.log or function() end
	self.warn = deps.warn or function() end
	self.stage = "idle"
	self.first_to = 0
	self.stage_since = 0
	self.menu_frames = 0
	self.card_dismiss_frames = 0
	self.picks = 0
	self.error_armed = false
end

function RoomCreator:has_engine_api()
	local o = self.offsets
	local m = self.mem
	return o ~= nil
		and o.PLAYER_MATCH_ROOT ~= nil
		and o.NETWORK_MENU_PICK ~= nil
		and m ~= nil
		and m.rva ~= nil
		and m.read_u32 ~= nil
		and m.read_i32 ~= nil
		and m.read_u8 ~= nil
		and m.write_i32 ~= nil
		and m.write_u8 ~= nil
end

function RoomCreator:note_stage(stage)
	self.stage = stage
	self.stage_since = self.time()
	self.menu_frames = 0
	self.card_dismiss_frames = 0
	self.picks = 0
	self.log("room creator: " .. (kStageText[stage] or stage))
end

function RoomCreator:raw_network_error()
	local o = self.offsets
	if o.NETWORK_INIT_ERROR and self.mem.read_rva_i32(o.NETWORK_INIT_ERROR) < 0 then
		return true
	end
	if self.mem.read_rva_i32(o.NETWORK_FLOW_ERROR) ~= 0 then
		return true
	end
	if o.NETWORK_STEP_ERROR and self.mem.read_rva_i32(o.NETWORK_STEP_ERROR) ~= 0 then
		return true
	end
	local step_err_val = o.NETWORK_STEP_ERROR_VALUE or kDefaultStepError
	if o.NETWORK_STEP_STATE and self.mem.read_rva_i32(o.NETWORK_STEP_STATE) == step_err_val then
		return true
	end
	return false
end

function RoomCreator:check_network_error()
	local active = self:raw_network_error()
	if not active then
		self.error_armed = true
		return false
	end
	return self.error_armed
end

function RoomCreator:read_setting_rows(root_addr, menu_offset)
	local o = self.offsets
	local menu = root_addr + menu_offset
	local pages_begin = self.mem.read_u32(menu + o.MENU_PAGES) or 0
	local pages_end = self.mem.read_u32(menu + o.MENU_PAGES + 4) or 0
	if pages_begin == 0 or pages_end - pages_begin < o.MENU_PAGE_STRIDE then
		return 0, 0
	end
	local rows_begin = self.mem.read_u32(pages_begin) or 0
	local rows_end = self.mem.read_u32(pages_begin + 4) or 0
	if rows_begin == 0 or rows_end < rows_begin then
		return 0, 0
	end
	return rows_begin, math.floor((rows_end - rows_begin) / o.MENU_ROW_STRIDE)
end

function RoomCreator:set_setting(first, count, row, value)
	if row < 0 or row >= count then
		return false
	end
	local o = self.offsets
	return self.mem.write_i32(first + row * o.MENU_ROW_STRIDE + o.MENU_ROW_VALUE, value)
end

function RoomCreator:choose_create_room(root_addr)
	local o = self.offsets
	local first, count = self:read_setting_rows(root_addr, o.PLAYER_MATCH_SETTINGS)
	local room_type = self.mem.read_u32(root_addr + o.PLAYER_MATCH_ROOM_TYPE) or 0
	local use_alt = (self.mem.read_u8(root_addr + o.PLAYER_MATCH_USE_ALT_SETTINGS) or 0) ~= 0
	local rematches = rematch_limit_for(self.first_to)

	if room_type == 1 then
		self:set_setting(first, count, o.ROOM_TYPE1_REMATCH_ROW, rematches)
		self:set_setting(first, count, o.ROOM_TYPE1_ROUNDS_ROW, o.ROOM_ROUNDS_TWO)
		self:set_setting(first, count, o.ROOM_TYPE1_ROUND_TIME_ROW, o.ROOM_ROUND_TIME_DEFAULT_99)
	else
		self:set_setting(first, count, o.ROOM_CAPACITY_ROW, o.ROOM_CAPACITY_TWO_PEOPLE)
		self:set_setting(first, count, o.ROOM_REMATCH_ROW, rematches)
		self:set_setting(first, count, o.ROOM_ROUNDS_ROW, o.ROOM_ROUNDS_TWO)
		self:set_setting(first, count, o.ROOM_ROUND_TIME_ROW, o.ROOM_ROUND_TIME_DEFAULT_99)
	end

	if use_alt then
		local alt_first, alt_count = self:read_setting_rows(root_addr, o.PLAYER_MATCH_ALT_SETTINGS)
		self:set_setting(alt_first, alt_count, o.ROOM_ALT_REMATCH_ROW, rematches)
		self:set_setting(alt_first, alt_count, o.ROOM_ALT_ROUNDS_ROW, o.ROOM_ROUNDS_TWO)
		self:set_setting(alt_first, alt_count, o.ROOM_ALT_ROUND_TIME_ROW, o.ROOM_ROUND_TIME_DEFAULT_99)
	end

	self.log(string.format(
		"room creator: type=%d alt=%d rows=%d firstTo=%d rematchOpt=%d rounds=2 time=99",
		room_type,
		use_alt and 1 or 0,
		count,
		self.first_to,
		rematches
	))

	self.mem.write_i32(root_addr + o.PLAYER_MATCH_CREATE_ANSWER, o.CREATE_MENU_CREATE_ROOM)
end

function RoomCreator:dismiss_profile_card()
	local o = self.offsets
	local ptr_addr = self.mem.rva(o.NETWORK_MENU + o.NETWORK_MENU_PROFILE_CARD)
	local card_addr = (ptr_addr and ptr_addr ~= 0) and (self.mem.read_u32(ptr_addr) or 0) or 0
	if card_addr == 0 then
		return true
	end
	local card_state = self.mem.read_u32(card_addr + o.PROFILE_CARD_STATE)
	if not card_state or card_state == 0 or card_state == o.PROFILE_CARD_DONE then
		return true
	end
	if self.card_dismiss_frames == 0 then
		self.mem.write_u8(card_addr + o.PROFILE_CARD_DISMISS, 1)
		self.log(string.format("room creator: dismissing network profile card (state=%d)", card_state))
	end
	self.card_dismiss_frames = self.card_dismiss_frames + 1
	return self.card_dismiss_frames >= kCardDismissTimeoutFrames
end

function RoomCreator:is_create_screen_ready(root_addr)
	if not root_addr or root_addr == 0 then
		return false
	end
	local o = self.offsets
	if (self.mem.read_u32(root_addr + o.PLAYER_MATCH_STATE) or 0) ~= o.PLAYER_MATCH_CREATE_SCREEN
		or (self.mem.read_u32(root_addr + o.PLAYER_MATCH_DIALOG_STEP) or 0) ~= o.PLAYER_MATCH_DIALOG_OPEN
		or (self.mem.read_u32(root_addr + o.PLAYER_MATCH_CREATE_MENU) or 0) ~= o.CREATE_MENU_CHOOSING
		or self.mem.read_i32(root_addr + o.PLAYER_MATCH_CREATE_ANSWER) ~= o.CREATE_MENU_UNANSWERED
	then
		return false
	end
	local _, count = self:read_setting_rows(root_addr, o.PLAYER_MATCH_SETTINGS)
	return count > 0
end

function RoomCreator:try_create_from_current_screen()
	local root_addr = self.mem.rva(self.offsets.PLAYER_MATCH_ROOT)
	if not root_addr or root_addr == 0 then
		return false
	end
	if not self:is_create_screen_ready(root_addr) then
		return false
	end
	self:note_stage("creating_room")
	self:choose_create_room(root_addr)
	return true
end

function RoomCreator:is_network_menu_running()
	local o = self.offsets
	return self.mem.read_rva_i32(o.NETWORK_MENU + o.NETWORK_MENU_STATE) == kNetworkMenuRunning
end

function RoomCreator:step_network_menu()
	local o = self.offsets
	self.menu_frames = self.menu_frames + 1

	local state = self.mem.read_rva_i32(o.NETWORK_MENU + o.NETWORK_MENU_STATE)
	local list_state = self.mem.read_rva_i32(o.NETWORK_MENU + o.NETWORK_MENU_LIST)
	local pending = self.mem.read_rva_i32(o.NETWORK_MENU + o.NETWORK_MENU_PENDING)

	if state ~= kNetworkMenuRunning then
		if pending == kNetworkResultCreateRoom then
			self:note_stage("opening_player_match")
		end
		return
	end

	if list_state ~= kNetworkListIdle or self.menu_frames < kMenuSettleFrames then
		return
	end

	if not self:dismiss_profile_card() then
		return
	end

	if self.picks > 0 and (self.menu_frames % kPickRetryFrames) ~= 0 then
		return
	end

	if self.picks >= kMaxPickAttempts then
		self.warn(string.format("room creator: Create Room did not open after %d attempts", self.picks))
		self:note_stage("failed")
		return
	end

	self.mem.write_rva_i32(o.NETWORK_MENU + o.NETWORK_MENU_PICK, o.NETWORK_PICK_CREATE_ROOM)
	self.picks = self.picks + 1
end

function RoomCreator:request_network_scene()
	self.game.claim_pad()
	if self.game.request_scene then
		return self.game.request_scene(self.offsets.SCENE_NETWORK)
	end
	return self.game.enter_network()
end

function RoomCreator:on_network_menu_opened()
	if not self:has_engine_api() then
		return
	end
	if self.stage == "armed" or self.stage == "entering_network" then
		self:note_stage("picking_create_room")
	end
end

function RoomCreator:on_player_match_result(root_addr)
	if not self:has_engine_api() then
		return
	end
	if self.stage ~= "armed" and self.stage ~= "picking_create_room" and self.stage ~= "opening_player_match" then
		return
	end
	if not self:is_create_screen_ready(root_addr) then
		return
	end
	self:note_stage("creating_room")
	self:choose_create_room(root_addr)
end

function RoomCreator:start(first_to)
	self.first_to = first_to or 0
	if not self:has_engine_api() then
		self.game.room_create_start(self.first_to)
		return
	end
	self.error_armed = not self:raw_network_error()
	self:note_stage("armed")
end

function RoomCreator:stop()
	if not self:has_engine_api() then
		self.game.room_create_stop()
		return
	end
	if self.stage == "idle" then
		return
	end
	self.error_armed = false
	self:note_stage("idle")
end

function RoomCreator:is_active()
	if not self:has_engine_api() then
		return self.game.room_create_stage() ~= kLegacyStageIdle
	end
	return self.stage ~= "idle"
end

function RoomCreator:status_text()
	if not self:has_engine_api() then
		local _, text = self.game.room_create_stage()
		return text
	end
	return kStageText[self.stage] or kStageText.idle
end

function RoomCreator:is_timed_out()
	if not self:has_engine_api() then
		return self.game.room_create_timed_out()
	end
	return self.stage ~= "idle"
		and self.stage ~= "armed"
		and self.stage ~= "failed"
		and (self.time() - self.stage_since) > kGiveUpMs
end

function RoomCreator:step_legacy(first_to, main_menu_frames, enter_network_fn)
	if self.game.room_create_stage() == kLegacyStageIdle then
		self.game.room_create_start(first_to)
	end
	self.game.room_create_set_first_to(first_to)
	local stage = self.game.room_create_step()

	if stage == kLegacyStageFailed then
		return "network_error"
	end

	if stage >= kLegacyStageEntering and self:check_network_error() then
		return "network_error"
	end

	if stage == kLegacyStageArmed and main_menu_frames >= kMainMenuFrames then
		local err = enter_network_fn()
		if err then
			return err
		end
	end

	if self.game.room_create_timed_out() then
		return "timed_out"
	end
	return nil
end

function RoomCreator:step(first_to, main_menu_frames, enter_network_fn)
	self.first_to = first_to or 0
	if not self:has_engine_api() then
		return self:step_legacy(self.first_to, main_menu_frames, enter_network_fn)
	end

	if self.stage == "idle" then
		self:start(self.first_to)
	end

	if self.stage == "failed" then
		return "network_error"
	end

	if self.stage ~= "armed" and self:check_network_error() then
		self.warn("room creator: network error detected during " .. self.stage)
		self:note_stage("failed")
		return "network_error"
	end

	local scene = self.game.scene()
	if scene == self.offsets.SCENE_NETWORK then
		if (self.stage == "armed" or self.stage == "picking_create_room" or self.stage == "opening_player_match")
			and self:try_create_from_current_screen()
		then
			return nil
		end
		if self.stage == "armed" and self:is_network_menu_running() then
			self:note_stage("picking_create_room")
			return nil
		end
	end

	if self.stage == "picking_create_room" then
		self:step_network_menu()
		if self.stage == "failed" then
			return "network_error"
		end
		return nil
	end

	if self.stage == "armed" and scene == self.offsets.SCENE_MAIN_MENU and main_menu_frames >= kMainMenuFrames then
		local err = enter_network_fn()
		if err then
			self:note_stage("failed")
			return err
		end
		self:note_stage("entering_network")
		return nil
	end

	if self:is_timed_out() then
		return "timed_out"
	end
	return nil
end

return RoomCreator
