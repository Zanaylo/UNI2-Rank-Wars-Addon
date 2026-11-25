local failed = 0
local passed = 0

local function check(cond, name)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		io.stderr:write("FAIL: " .. tostring(name) .. "\n")
	end
end

local events = {}
local windows = {}
local http_queue = {}
local config_store = {}
local fs_store = {}
local toasts = {}
local draw_calls = 0
local now_ms = 1000
local current_lobby = "0"
local current_owner = "0"
local current_scene = 1
local current_scene_frames = 60
local in_match = false
local is_online = false
local is_training = false
local room_stage = 0
local room_create_started = false
local room_create_first_to = -1
local joined_lobby = nil

local function json_encode(val)
	local t = type(val)
	if t == "nil" then return "null" end
	if t == "boolean" then return val and "true" or "false" end
	if t == "number" then return tostring(val) end
	if t == "string" then
		return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
	end
	if t == "table" then
		local parts = {}
		for k, v in pairs(val) do
			parts[#parts + 1] = json_encode(tostring(k)) .. ":" .. json_encode(v)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local json_mock_map = {}

_G.uni2 = {
	log = function() end,
	warn = function() end,
	error = function() end,
	time = function() return now_ms end,
	clock = function() return now_ms / 1000.0 end,
	version = function() return "0.8.1" end,
	language = function() return "en" end,
	tr = function(s) return s end,
	toast = function(kind, title, text)
		toasts[#toasts + 1] = { kind = kind, title = title, text = text }
	end,
	notify = function() end,
	on = function(ev, fn)
		events[ev] = events[ev] or {}
		events[ev][#events[ev] + 1] = fn
	end,
	config = {
		get_string = function(s, k, fb) return config_store[s .. "." .. k] or fb or "" end,
		get_int = function(s, k, fb)
			local v = config_store[s .. "." .. k]
			return v ~= nil and v or (fb or 0)
		end,
		set_string = function(s, k, v) config_store[s .. "." .. k] = v end,
		set_int = function(s, k, v) config_store[s .. "." .. k] = v end,
		command_line = function()
			return 'uni2.exe "?action=create&match=M123&token=TOK_HOST&api=https%3A%2F%2Frankwars.test"'
		end,
	},
	fs = {
		read = function(p) return fs_store[p] end,
		write = function(p, d) fs_store[p] = d; return true end,
		exists = function(p) return fs_store[p] ~= nil end,
		mkdir = function() return true end,
		addon_dir = function() return "." end,
		mod_root = function() return "UNI2-IM" end,
	},
	mem = {
		read_rva_i32 = function() return 1 end,
		write_rva_i32 = function() return true end,
	},
	game = {
		scene = function() return current_scene end,
		scene_frames = function() return current_scene_frames end,
		in_match = function() return in_match end,
		is_training = function() return is_training end,
		is_online = function() return is_online end,
		is_spectating = function() return false end,
		local_side = function() return 0 end,
		character = function() return 0 end,
		character_name = function(id) return id == 0 and "Hyde" or "Linne" end,
		claim_pad = function() return 0 end,
		enter_network = function() return true end,
		leave_training = function() return true end,
		can_join_room = function() return true end,
		join_room = function(lobby) joined_lobby = lobby; return true end,
		room_create_start = function(ft) room_create_started = true; room_create_first_to = ft or 0; room_stage = 1 end,
		room_create_set_first_to = function(ft) room_create_first_to = ft or 0 end,
		room_create_stop = function() room_stage = 0 end,
		room_create_step = function() return room_stage end,
		room_create_stage = function() return room_stage, "Creating" end,
		room_create_timed_out = function() return false end,
	},
	steam = {
		is_ready = function() return true end,
		own_id = function() return "76561198000000001" end,
		lobby = function() return current_lobby end,
		lobby_owner = function() return current_owner end,
		lobby_limit = function() return 2 end,
		launch_command_line = function() return "" end,
		launch_query = function() return "" end,
		set_rich_presence_note = function() end,
	},
	replay = {
		folder = function() return "UNI2-IM\\Replays\\" end,
		can_play = function() return true end,
		is_loading_patch = function() return false end,
		refresh = function() end,
		save_record = function(rec, note)
			local p = "UNI2-IM\\Replays\\" .. note .. ".rep"
			fs_store[p] = rec
			return p
		end,
		describe_header = function()
			return { steam_id_0 = "76561198000000001", steam_id_1 = "76561198000000002", chara_0 = 0, chara_1 = 1 }
		end,
		matchup_of = function() return "Hyde vs Linne" end,
		request_playback = function() return true, "" end,
	},
	http = {
		request = function(req, cb)
			http_queue[#http_queue + 1] = { req = req, cb = cb }
		end,
		json_encode = json_encode,
		json_decode = function(body) return json_mock_map[body] end,
	},
	draw = {
		fill = function() draw_calls = draw_calls + 1; return true end,
		frame = function() draw_calls = draw_calls + 1; return true end,
		text = function() draw_calls = draw_calls + 1; return true end,
	},
	offsets = {
		SCENE_BATTLE = 20,
		SCENE_MAIN_MENU = 1,
		SCENE_NETWORK = 50,
		SCENE_CHARA_SELECT = 10,
		SCENE_REPLAY_LIST = 60,
		NETWORK_MENU = 0x100,
		NETWORK_MENU_STATE = 0x10,
		NETWORK_MENU_LIST = 0x20,
		NETWORK_FLOW_ERROR = 0x30,
		ROOM_TASK_STATE = 0x40,
	},
	ui = {
		register_window = function(id, title, opts, fn)
			windows[id] = { title = title, opts = opts, draw = fn, open = opts.open or false }
		end,
		set_open = function(id, open) if windows[id] then windows[id].open = open end end,
		is_open = function(id) return windows[id] and windows[id].open or false end,
		scaled = function(v) return v end,
		avail_width = function() return 440 end,
		reserve = function() return 10, 10 end,
		dummy = function() end,
		separator = function() end,
		same_line = function() end,
		text = function() end,
		text_wrapped = function() end,
		text_muted = function() end,
		text_warn = function() end,
		text_good = function() end,
		button = function() return false end,
		small_button = function() return false end,
		checkbox = function(_, v) return false, v end,
		input_text = function(_, _, v) return false, v end,
		slider_int = function(_, v) return false, v end,
		collapsing_header = function() return false end,
		set_next_item_width = function() end,
		begin_disabled = function() end,
		end_disabled = function() end,
		is_item_hovered = function() return false end,
		set_tooltip = function() end,
		set_clipboard = function() end,
		begin_child_card = function() return true end,
		end_child_card = function() end,
		push_button_color = function() end,
		pop_style_color = function() end,
		draw_rect_filled = function() end,
		draw_rect_filled_multi = function() end,
		draw_rect = function() end,
		draw_circle = function() end,
		draw_circle_filled = function() end,
		draw_line = function() end,
		draw_text = function() end,
		draw_text_centered = function() end,
		calc_text_size = function(t) return #t * 7, 14 end,
		push_clip_rect = function() end,
		pop_clip_rect = function() end,
	},
}

dofile("main.lua")

check(windows["rank_wars"] ~= nil, "main.lua registers rank_wars window")
check(windows["rank_wars"].opts.max_width == 560 and windows["rank_wars"].opts.max_height == 680, "rank_wars window bounds max size")
check(events["frame"] and #events["frame"] == 1, "main.lua registers frame callback")
check(events["hud"] and #events["hud"] == 1, "main.lua registers hud callback")
check(events["game_started"] and #events["game_started"] == 1, "main.lua registers game_started callback")
check(events["game_ended"] and #events["game_ended"] == 1, "main.lua registers game_ended callback")

local launch_link = require("launch_link")
local jl, jerr = launch_link.parse_launch_parameters("action=join&match=M9&token=T9&api=https%3A%2F%2Frw.gg&lobby=109775240912345&owner=76561198000000002")
check(jl ~= nil and jerr == nil and jl.action == "join" and jl.api == "https://rw.gg", "launch_link parses join params")

local rl, rerr = launch_link.parse_launch_parameters("action=replay&replay=rep_42&token=RT&api=https://rw.gg")
check(rl ~= nil and rerr == nil and rl.action == "replay" and rl.replay == "rep_42", "launch_link parses replay params")

local protocol = require("protocol")
local ct, form = protocol.game_form("BOUND", "REPLAYBYTES", "game1.rep", "host", "hyde", "linne")
check(ct:find("multipart/form-data", 1, true) ~= nil and form:find("REPLAYBYTES", 1, true) ~= nil, "protocol builds multipart game form")

local session = require("session")
check(session.view().phase == "waiting_steam", "session parsed initial create launch link")

events["frame"][1]()
events["frame"][1]()
check(not room_create_started, "host waits for GET /match before starting room creation")
check(#http_queue == 1 and http_queue[1].req.method == "GET", "host fetches initial match state")

local match_body = "MATCH_OK"
json_mock_map[match_body] = {
	id = "M123",
	status = "IN_PROGRESS",
	role = "host",
	firstTo = 3,
	score = { host = 0, guest = 0 },
	host = { displayName = "Zanaylo", steamId64 = "76561198000000001" },
	guest = { displayName = "Rival", steamId64 = "76561198000000002" },
}
http_queue[1].cb({ sent = true, status = 200, body = match_body, error = "" })
http_queue = {}

events["frame"][1]()
check(room_create_started and room_create_first_to == 3, "host starts room creation with server firstTo after GET /match")

current_lobby = "109775240999999"
current_owner = "76561198000000001"
events["frame"][1]()
events["frame"][1]()
check(#http_queue == 1 and http_queue[1].req.method == "PUT" and http_queue[1].req.url:find("/room", 1, true) ~= nil, "host reports created lobby to API")
http_queue[1].cb({ sent = true, status = 200, body = "{}", error = "" })
http_queue = {}
check(session.view().phase == "in_match", "session enters in_match after room reported")

events["frame"][1]()
if #http_queue == 1 then
	http_queue[1].cb({ sent = true, status = 200, body = match_body, error = "" })
	http_queue = {}
end

in_match = true
is_online = true
events["hud"][1]()
check(draw_calls > 0, "hud draws score pips during live online match")

windows["rank_wars"].draw()
check(true, "rank_wars UI draws without errors")

windows["rank_wars"].open = true
events["game_started"][1]()
check(windows["rank_wars"].open == false, "game_started auto-closes rank_wars window")
events["frame"][1]()
if #http_queue == 1 then
	http_queue[1].cb({ sent = true, status = 200, body = match_body, error = "" })
	http_queue = {}
end

events["game_ended"][1]({
	ending = "decided",
	winner = 0,
	local_side = 0,
	steam_id = { "76561198000000001", "76561198000000002" },
	chara = { 0, 1 },
	record = "MOCK_REPLAY_PAYLOAD",
})
events["frame"][1]()
check(#http_queue >= 1 and http_queue[1].req.method == "PUT" and http_queue[1].req.url:find("/games/1", 1, true) ~= nil, "game_ended uploads replay via PUT /games/1")

local game_ans = "GAME1_OK"
json_mock_map[game_ans] = {
	result = "RECORDED",
	match = { status = "IN_PROGRESS", firstTo = 3, finished = false, score = { host = 1, guest = 0 } },
}
http_queue[1].cb({ sent = true, status = 200, body = game_ans, error = "" })
check(session.view().score.host == 1 and session.view().score.guest == 0, "score updates after API confirms game 1")

print(string.format("RankWars Lua tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	os.exit(1)
end
