local class = require("src.core.class")
local cooldown = require("src.core.cooldown")
local StateMachine = require("src.core.state_machine")

local Session = class()

local kToastTitle = "RANK WARS"
local kMatchFetchPollMs = 2000

local kClosedText = {
	UNDER_REVIEW = "The match went to the organisers for review",
	CANCELLED = "Rank Wars cancelled this match",
	VOIDED = "Rank Wars voided this match",
}

local kGameResultLabels = {
	RECORDED = "recorded",
	DUPLICATE = "already recorded",
	DISPUTED = "DISPUTED, sent for review",
}

local kHostRoomErrors = {
	network_error = "Network failed while creating the room. UNI2 cannot recover from this automatically; restart the game and open the Rank Wars link again",
	steam_offline = "Steam is offline. Reconnect Steam and click Try again",
	timed_out = "The room could not be created automatically. Create a Player Match room and it is sent by itself",
}

local kGuestJoinErrors = {
	unsupported = "This game version cannot join the room by itself. Join through the Steam invite",
	network_error = "Network failed while connecting to online mode. UNI2 cannot recover from this automatically; restart the game and open the Rank Wars link again",
	steam_offline = "Steam is offline. Reconnect Steam and click Try again",
	flow_error = "The host's room is closed or could not be reached. Ask the host for a new link",
	timed_out = "Could not get into the room in time. Ask the host for a new link",
}

local kStatusHandlers = {
	completed = function(self)
		self:finish()
	end,
	closed = function(self, status)
		self:close_match(status)
	end,
}

local kStates = {
	off = {
		text = "Open the Rank Wars link on Discord to start",
		step = 0,
		idle = true,
	},
	creating_test = {
		text = "Creating the test match",
		step = 0,
		idle = true,
	},
	bad_link = {
		text = "The Rank Wars link could not be read",
		step = 0,
		idle = true,
	},
	waiting_steam = {
		text = "Waiting for Steam",
		step = 1,
		live = true,
	},
	waiting_room = {
		text = "Creating your room",
		step = 2,
		live = true,
		detail = function(self)
			if not self.tracker.match_loaded then
				return "Reading match settings"
			end
			return self.room_flow:host_room_status_text()
		end,
		on_update = function(self)
			self:step_waiting_room()
		end,
		on_exit = function(self)
			self.room_flow:stop_host_room()
		end,
	},
	reporting_room = {
		text = "Sending the room to Rank Wars",
		step = 2,
		live = true,
	},
	waiting_join = {
		text = "Joining the room from the main menu",
		step = 2,
		live = true,
		on_update = function(self)
			self:step_waiting_join()
		end,
	},
	joining = {
		text = "Joining the room",
		step = 2,
		live = true,
		on_update = function(self)
			self:step_joining()
		end,
	},
	in_match = {
		text = "In the match. Each game is sent when it ends",
		step = 3,
		live = true,
		on_update = function(self)
			self:step_in_match()
		end,
	},
	finished = {
		text = "Match over and recorded",
		step = 4,
	},
	aborted = {
		text = "Match cancelled",
		step = 4,
	},
	closed = {
		text = "Rank Wars closed this match. Nothing more will be sent",
		step = 4,
		detail = function(self)
			return kClosedText[self.tracker.info.status] or "Rank Wars closed this match"
		end,
	},
	failed = {
		text = "Something went wrong, see below",
		live = true,
		preserve_step = true,
	},
}

function Session:init(deps)
	self.game = deps.game
	self.steam = deps.steam
	self.replay = deps.replay
	self.fs = deps.fs
	self.ui = deps.ui
	self.time = deps.time
	self.log = deps.log
	self.warn = deps.warn
	self.toast = deps.toast
	self.launch_link = deps.launch_link
	self.protocol = deps.protocol
	self.client_factory = deps.client_factory
	self.replay_viewer = deps.replay_viewer
	self.room_flow = deps.room_flow
	self.presence = deps.presence
	self.tracker = deps.score_tracker
	self.launch_watcher = deps.launch_watcher
	self.match_fetch_cooldown = cooldown.Cooldown.new(kMatchFetchPollMs, deps.time)
	self.fsm = StateMachine.new("off", kStates)
	self.step = 0
	self.link = nil
	self.api = nil
	self.sandbox = nil
	self.sandbox_api = ""
	self.self_id = "0"
	self.reported_lobby = "0"
	self.local_role = "host"
	self.finished = false
	self.join_started_at = 0
	self.error = ""
	self.last_game = ""
	self.view_cache = {}
	self.scoreboard_cache = {}
	self.on_link_callback = function(link, err)
		self:take_link(link, err)
	end
end

function Session:phase()
	return self.fsm:state()
end

function Session:set_phase(next_phase)
	self.fsm:transition(next_phase, self)
	local def = self.fsm:definition()
	if def and not def.preserve_step then
		self.step = def.step or 0
	end
end

function Session:is_live()
	local def = self.fsm:definition()
	return self.link ~= nil and def ~= nil and def.live == true
end

function Session:is_host()
	return self.link ~= nil and self.link.action == "create"
end

function Session:fail(message)
	self:set_phase("failed")
	self.error = message
	self.ui.set_open("rank_wars", true)
	self.toast("error", kToastTitle, message)
	self.warn("rank wars: " .. message)
end

function Session:finish()
	if self.fsm:is("finished") then
		return
	end
	self.finished = true
	self:set_phase("finished")
	local score = self.tracker.info.score
	self.toast("success", kToastTitle, string.format("Match over: %d - %d", score.host, score.guest))
end

function Session:close_match(status)
	self.finished = true
	self:set_phase("closed")
	local reason = kClosedText[status] or "Rank Wars closed this match"
	local score = self.tracker.info.score
	self.toast("warning", kToastTitle, string.format("%s\nScore %d - %d", reason, score.host, score.guest))
end

function Session:follow_status(status)
	local mapped = self.protocol:state_of(status)
	local handler = kStatusHandlers[mapped]
	if handler then
		handler(self, status)
	end
end

function Session:sync_presence()
	self.presence:update(self:is_live(), self.tracker.info.score, self.tracker.info.first_to)
end

function Session:handle_match_response(answer)
	if not answer.ok then
		if not self.fsm:is("in_match") then
			self.error = "The match could not be read: " .. answer.error
		end
		return
	end

	local parsed = self.protocol:parse_match(answer.body)
	if not parsed then
		return
	end

	local score_changed = self.tracker:apply_match(parsed)
	self.error = ""

	if not self:is_live() then
		return
	end

	if self.fsm:is("in_match") and score_changed then
		self.toast("info", kToastTitle, string.format("Score updated: %d - %d", parsed.score.host, parsed.score.guest))
	end

	if self.protocol:state_of(parsed.status) == "waiting" then
		self:fail("This match has not been accepted on Discord yet. Accept it there and try again")
		return
	end

	if self.tracker:is_decided(parsed.score, parsed.first_to) then
		self:finish()
		return
	end

	self:follow_status(parsed.status)
	self.tracker:sync_reconciliation(self:is_live(), self.finished)
end

function Session:fetch_match()
	if not self.api then
		return
	end

	self.match_fetch_cooldown:mark()
	self.api:fetch_match(function(answer)
		self:handle_match_response(answer)
	end)
end

function Session:start_match(link)
	if self.link and self.link.match == link.match and self.link.token == link.token then
		return
	end

	self.link = link
	self.local_role = link.action == "create" and "host" or "guest"
	self.api = nil
	self.reported_lobby = "0"
	self.finished = false
	self.error = ""
	self.last_game = ""
	self.tracker:reset()
	self.room_flow:reset()
	self.match_fetch_cooldown:reset()
	self:set_phase("waiting_steam")

	self.replay_viewer:cancel()
	self.ui.set_open("rank_wars", true)
	self.log("match " .. link.match .. " as " .. self.launch_link.action_name(link.action))
end

function Session:take_link(link, err)
	if link and link.action == "replay" then
		self.replay_viewer:start(link, self:is_live())
		return
	end

	if link then
		self:start_match(link)
		return
	end

	if not err or err == "" then
		return
	end

	if self:is_live() then
		self.warn("ignored bad link while match live: " .. err)
		return
	end

	self:set_phase("bad_link")
	self.error = err
	self.ui.set_open("rank_wars", true)
end

function Session:report_room(lobby)
	self.reported_lobby = lobby
	self:set_phase("reporting_room")
	self.api:put_room(lobby, self.self_id, function(answer)
		if not answer.ok then
			self:fail("The room could not be sent: " .. answer.error)
			return
		end
		self:set_phase("in_match")
		self:fetch_match()
		self.toast("success", kToastTitle, "Room sent. The opponent gets the link now")
	end)
end

function Session:enter_match_as_guest()
	self:set_phase("in_match")
	self.toast("success", kToastTitle, "You are in the room")
end

function Session:ensure_api()
	if self.api then
		return true
	end

	local own = self.steam.own_id()
	if own == "0" or own == "" then
		return false
	end

	self.self_id = own
	self.api = self.client_factory(self.link.api, self.link.token, own)
	self:fetch_match()
	self:set_phase(self:is_host() and "waiting_room" or "waiting_join")
	return true
end

function Session:step_waiting_room()
	local lobby = self.room_flow:owned_lobby(self.self_id)
	if lobby then
		self:report_room(lobby)
		return
	end

	if not self.tracker.match_loaded then
		if self.api and self.api:pending() == 0 and self.match_fetch_cooldown:ready() then
			self:fetch_match()
		end
		return
	end

	local outcome = self.room_flow:step_host_room(self.tracker.info.first_to)
	local err = kHostRoomErrors[outcome]
	if err then
		self:fail(err)
	end
end

function Session:step_waiting_join()
	local outcome = self.room_flow:step_guest_prepare(self.link.lobby, self.link.owner)
	if outcome == "joined" then
		self:enter_match_as_guest()
		return
	end
	if outcome == "joining" then
		self.join_started_at = self.time()
		self:set_phase("joining")
		return
	end
	local err = kGuestJoinErrors[outcome]
	if err then
		self:fail(err)
	end
end

function Session:step_joining()
	local outcome = self.room_flow:step_guest_joining(self.link.lobby, self.join_started_at)
	if outcome == "joined" then
		self:enter_match_as_guest()
		return
	end
	local err = kGuestJoinErrors[outcome]
	if err then
		self:fail(err)
	end
end

function Session:step_in_match()
	if self:is_host() and self.tracker.played == 0 then
		local lobby = self.room_flow:owned_lobby(self.self_id)
		if lobby and lobby ~= self.reported_lobby then
			self:report_room(lobby)
		end
	end

	if self.tracker:should_poll() then
		self.tracker:mark_polled()
		self:fetch_match()
	end
end

function Session:initialize()
	self.launch_watcher:check_initial(self.on_link_callback)
end

function Session:on_frame()
	self.launch_watcher:poll(self.on_link_callback)
	self.replay_viewer:on_frame()

	if self.sandbox then
		self.sandbox:tick()
	end
	if self.api then
		self.api:tick()
	end

	local def = self.fsm:definition()
	if def and def.idle then
		self:sync_presence()
		return
	end

	if not self:ensure_api() then
		return
	end

	self.fsm:update(self)
	self:sync_presence()
end

function Session:on_game_started()
	if not self:is_live() then
		return
	end
	self.ui.set_open("rank_wars", false)
	self:fetch_match()
end

function Session:role_of_side(side, local_side)
	if side == local_side then
		return self.local_role
	end
	return self.protocol:other_role(self.local_role)
end

function Session:save_game_replay(record, game_num)
	local name0 = ""
	local name1 = ""
	local header = self.replay.describe_header(record)
	if header then
		name0 = self.protocol:name_of_steam_id(self.tracker.info, header.steam_id_0)
		name1 = self.protocol:name_of_steam_id(self.tracker.info, header.steam_id_1)
	end

	local saved_path = self.replay.save_record(record, "rankwars-game" .. tostring(game_num), name0, name1)
	if saved_path == "" then
		return nil
	end
	return self.fs.read(saved_path)
end

function Session:handle_game_answer(game_num, answer)
	if answer.status == 409 then
		self.last_game = string.format("Game %d: the match was already closed on Rank Wars", game_num)
		self:fetch_match()
		return
	end

	if not answer.ok then
		self.last_game = string.format("Game %d: not recorded, %s", game_num, answer.error)
		self.toast("error", kToastTitle, self.last_game)
		return
	end

	local parsed = self.protocol:parse_game_answer(answer.body)
	if not parsed then
		return
	end

	self.tracker:apply_game_answer(game_num, parsed)

	local label = kGameResultLabels[parsed.result] or "unknown answer"
	self.last_game = string.format("Game %d: %s", game_num, label)
	local kind = parsed.result == "DISPUTED" and "warning" or "success"
	local score = self.tracker.info.score
	self.toast(kind, kToastTitle, string.format("%s\nScore %d - %d", self.last_game, score.host, score.guest))

	if parsed.finished or self.tracker:is_decided() then
		self:finish()
		return
	end

	self:follow_status(parsed.status)
	self.tracker:sync_reconciliation(self:is_live(), self.finished)
end

function Session:on_game_ended(report)
	if not self:is_live() or self.finished or report.ending == "connection_lost" then
		return
	end

	local winner_role = self:role_of_side(report.winner, report.local_side)
	local game_num = self.tracker:record_local_game(winner_role)
	local host_first = self:role_of_side(0, report.local_side) == "host"
	local host_chara = self.protocol:slug(self.game.character_name(report.chara[host_first and 1 or 2]))
	local guest_chara = self.protocol:slug(self.game.character_name(report.chara[host_first and 2 or 1]))
	local replay_bytes = self:save_game_replay(report.record, game_num)

	if not replay_bytes or replay_bytes == "" then
		self.last_game = string.format("Game %d: the replay could not be saved, so it was not sent", game_num)
		self:fetch_match()
		return
	end

	self.last_game = string.format("Game %d: the %s won, sending", game_num, winner_role)
	self.api:put_game(game_num, winner_role, host_chara, guest_chara, "game" .. tostring(game_num) .. ".rep", replay_bytes, function(answer)
		self:handle_game_answer(game_num, answer)
	end)

	self:fetch_match()
end

function Session:view()
	local def = self.fsm:definition() or kStates.off
	local info = self.tracker.info
	local v = self.view_cache

	v.phase = self:phase()
	v.phase_text = def.text or kStates.off.text
	v.detail = def.detail and def.detail(self) or ""
	v.step = self.step
	v.is_host = self:is_host()
	v.role = self.link and self.local_role or ""
	v.match = self.link and self.link.match or ""
	v.host = info.host.name or ""
	v.guest = info.guest.name or ""
	v.score = info.score
	v.first_to = info.first_to
	v.pending = self.api and self.api:pending() or 0
	v.last_game = self.last_game
	v.error = self.error
	v.sandbox = info.sandbox
	v.guest_link = info.join_url

	return v
end

function Session:scoreboard()
	if not self.link or (not self:is_live() and not self.fsm:is("finished")) then
		return nil
	end

	local board = self.scoreboard_cache
	board.is_host = self:is_host()
	board.score = self.tracker.info.score
	board.first_to = self.tracker.info.first_to
	return board
end

function Session:can_retry()
	return self.fsm:is("failed")
end

function Session:retry()
	if not self:can_retry() or not self.api then
		return
	end
	self.error = ""
	self.room_flow:reset()
	self:set_phase(self:is_host() and "waiting_room" or "waiting_join")
	self:fetch_match()
end

function Session:can_abort()
	return self.api ~= nil and self:is_live() and not self.finished
end

function Session:abort(reason)
	if not self:can_abort() then
		return
	end
	local final_reason = (reason and reason ~= "") and reason or "cancelled in-game"
	self.api:abort(final_reason, function(answer)
		if not answer.ok then
			self.error = "The match could not be cancelled: " .. answer.error
			return
		end
		self:set_phase("aborted")
		self.toast("warning", kToastTitle, "Match cancelled")
	end)
end

function Session:can_start_test()
	return (not self:is_live() or self.fsm:is("failed")) and not self.fsm:is("creating_test")
end

function Session:fail_sandbox(message)
	self:set_phase("off")
	self.error = message
end

function Session:handle_sandbox_response(answer)
	if not answer.ok then
		self:fail_sandbox("The test match could not be created: " .. answer.error)
		return
	end

	local parsed = self.protocol:parse_sandbox(answer.body)
	if not parsed then
		self:fail_sandbox("The test match response could not be read")
		return
	end

	local link, err = self.launch_link.host_link(parsed.match, parsed.host_token, self.sandbox_api)
	if not link then
		self:fail_sandbox("The test match link is invalid: " .. tostring(err))
		return
	end

	self:start_match(link)
end

function Session:start_test(api_url, password, first_to)
	if not self:can_start_test() then
		return
	end

	if not self.sandbox or self.sandbox_api ~= api_url then
		self.sandbox_api = api_url
		self.sandbox = self.client_factory(api_url, "", "0")
	end

	self.link = nil
	self.error = ""
	self.last_game = ""
	self:set_phase("creating_test")

	self.sandbox:create_sandbox(password, first_to, function(answer)
		self:handle_sandbox_response(answer)
	end)
end

return Session
