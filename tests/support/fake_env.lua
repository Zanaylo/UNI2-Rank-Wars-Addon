local class = require("src.core.class")
local bootstrap = require("src.app.bootstrap")

local FakeEnv = class()

local function json_encode(val)
	local t = type(val)
	if t == "nil" then
		return "null"
	end
	if t == "boolean" then
		return val and "true" or "false"
	end
	if t == "number" then
		return tostring(val)
	end
	if t == "string" then
		return '"' .. val:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
	end
	if t ~= "table" then
		return "null"
	end

	local keys = {}
	for k in pairs(val) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = json_encode(tostring(k)) .. ":" .. json_encode(val[k])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local kBaseAddress = 0x10000000

local kOffsets = {
	SCENE_ID = 0x10,
	SCENE_REQUEST = 0x14,
	SCENE_BATTLE = 20,
	SCENE_MAIN_MENU = 1,
	SCENE_NETWORK = 50,
	SCENE_CHARA_SELECT = 10,
	SCENE_REPLAY_LIST = 60,
	NETWORK_MENU = 0x100,
	NETWORK_MENU_STATE = 0x00,
	NETWORK_MENU_PENDING = 0x08,
	NETWORK_MENU_LIST = 0x10,
	NETWORK_MENU_PICK = 0x14,
	NETWORK_MENU_PROFILE_CARD = 0x4c,
	NETWORK_PICK_CREATE_ROOM = 5,
	PROFILE_CARD_STATE = 0x00,
	PROFILE_CARD_DISMISS = 0x08,
	PROFILE_CARD_DONE = 4,
	NETWORK_INIT_ERROR = 0x24,
	NETWORK_STEP_STATE = 0x28,
	NETWORK_STEP_ERROR = 0x2c,
	NETWORK_STEP_ERROR_VALUE = 10,
	NETWORK_FLOW_ERROR = 0x30,
	ROOM_TASK_STATE = 0x40,
	PLAYER_MATCH_ROOT = 0x2000,
	PLAYER_MATCH_STATE = 0x00,
	PLAYER_MATCH_DIALOG_STEP = 0x2c,
	PLAYER_MATCH_CREATE_MENU = 0x3c,
	PLAYER_MATCH_CREATE_ANSWER = 0x40,
	PLAYER_MATCH_ROOM_TYPE = 0x708,
	PLAYER_MATCH_SETTINGS = 0x728,
	PLAYER_MATCH_ALT_SETTINGS = 0x7d4,
	PLAYER_MATCH_USE_ALT_SETTINGS = 0xd6c,
	PLAYER_MATCH_CREATE_SCREEN = 4,
	PLAYER_MATCH_DIALOG_OPEN = 1,
	CREATE_MENU_CHOOSING = 0,
	CREATE_MENU_UNANSWERED = -1,
	CREATE_MENU_CREATE_ROOM = 0,
	MENU_PAGES = 0x04,
	MENU_PAGE_STRIDE = 0x0c,
	MENU_ROW_STRIDE = 0xfc,
	MENU_ROW_VALUE = 0x4c,
	ROOM_CAPACITY_ROW = 3,
	ROOM_CAPACITY_TWO_PEOPLE = 0,
	ROOM_REMATCH_ROW = 11,
	ROOM_ROUNDS_ROW = 12,
	ROOM_ROUND_TIME_ROW = 13,
	ROOM_TYPE1_REMATCH_ROW = 7,
	ROOM_TYPE1_ROUNDS_ROW = 8,
	ROOM_TYPE1_ROUND_TIME_ROW = 9,
	ROOM_ALT_REMATCH_ROW = 5,
	ROOM_ALT_ROUNDS_ROW = 6,
	ROOM_ALT_ROUND_TIME_ROW = 7,
	ROOM_ROUNDS_TWO = 1,
	ROOM_ROUND_TIME_DEFAULT_99 = 2,
	MATCH_KIND = 0x50,
	MATCH_KIND_RANK = 1,
	MATCH_KIND_PLAYER = 2,
}

function FakeEnv:init(opts)
	opts = opts or {}
	self.now_ms = opts.now_ms or 1000
	self.command_line = opts.command_line or ""
	self.steam_id = opts.steam_id or "76561198000000001"
	self.lobby = opts.lobby or "0"
	self.lobby_owner = opts.lobby_owner or "0"
	self.launch_cmd = ""
	self.launch_queries = {}
	self.presence_notes = {}
	self.scene = opts.scene or kOffsets.SCENE_MAIN_MENU
	self.scene_frames = opts.scene_frames or 60
	self.in_match = false
	self.is_online = false
	self.is_spectating = false
	self.is_training = false
	self.local_side = 0
	self.can_join_room = true
	self.can_play_replay = true
	self.is_loading_patch = false
	self.playback_ok = true
	self.playback_err = ""
	self.playback_requests = {}
	self.fs_write_ok = true
	self.save_record_ok = true
	self.room_stage = 0
	self.room_stage_text = "Creating"
	self.room_create_started = false
	self.room_create_first_to = -1
	self.room_create_timed_out = false
	self.room_create_stops = 0
	self.leave_training_calls = 0
	self.enter_network_calls = 0
	self.requested_scenes = {}
	self.claim_pad_calls = 0
	self.joined_lobby = nil
	self.joined_owner = nil
	self.events = {}
	self.windows = {}
	self.http_queue = {}
	self.config_store = {}
	self.fs_store = {}
	self.json_map = {}
	self.mem_store = {}
	self.abs_mem = {}
	self.toasts = {}
	self.logs = {}
	self.warnings = {}
	self.draw_fills = {}
	self.ui_texts = {}
	self.ui_clicks = {}
	self.ui_hovered = false
	self.ui_tooltips = {}
	self.ui_clipboard = nil
	self.ui_checkbox_change = nil
	self.ui_collapsing_open = false
	self.ui_inputs = {}
	self.ui_slider = nil

	self.mem_store[kOffsets.NETWORK_MENU + kOffsets.NETWORK_MENU_STATE] = 1
	self.mem_store[kOffsets.NETWORK_MENU + kOffsets.NETWORK_MENU_LIST] = 1
	self.mem_store[kOffsets.NETWORK_FLOW_ERROR] = 0

	self.api = self:build_api()
end

function FakeEnv:build_api()
	local env = self
	return {
		log = function(msg)
			env.logs[#env.logs + 1] = msg
		end,
		warn = function(msg)
			env.warnings[#env.warnings + 1] = msg
		end,
		error = function(msg)
			env.warnings[#env.warnings + 1] = msg
		end,
		time = function()
			return env.now_ms
		end,
		clock = function()
			return env.now_ms / 1000.0
		end,
		version = function()
			return "0.8.1"
		end,
		language = function()
			return "en"
		end,
		tr = function(s)
			return s
		end,
		toast = function(kind, title, text)
			env.toasts[#env.toasts + 1] = { kind = kind, title = title, text = text }
		end,
		notify = function() end,
		on = function(ev, fn)
			env.events[ev] = env.events[ev] or {}
			env.events[ev][#env.events[ev] + 1] = fn
		end,
		config = {
			get_string = function(s, k, fb)
				local v = env.config_store[s .. "." .. k]
				return v ~= nil and v or (fb or "")
			end,
			get_int = function(s, k, fb)
				local v = env.config_store[s .. "." .. k]
				return v ~= nil and v or (fb or 0)
			end,
			set_string = function(s, k, v)
				env.config_store[s .. "." .. k] = v
			end,
			set_int = function(s, k, v)
				env.config_store[s .. "." .. k] = v
			end,
			command_line = function()
				return env.command_line
			end,
		},
		fs = {
			read = function(p)
				return env.fs_store[p]
			end,
			write = function(p, d)
				if not env.fs_write_ok then
					return false
				end
				env.fs_store[p] = d
				return true
			end,
			exists = function(p)
				return env.fs_store[p] ~= nil
			end,
			mkdir = function()
				return true
			end,
			addon_dir = function()
				return "."
			end,
			mod_root = function()
				return "UNI2-IM"
			end,
		},
		mem = {
			rva = function(rva)
				return kBaseAddress + rva
			end,
			read_i32 = function(addr)
				local v = env.abs_mem[addr]
				if v ~= nil then
					return v
				end
				if addr >= kBaseAddress then
					return env.mem_store[addr - kBaseAddress] or 0
				end
				return 0
			end,
			read_u32 = function(addr)
				local v = env.abs_mem[addr]
				if v ~= nil then
					return v
				end
				if addr >= kBaseAddress then
					return env.mem_store[addr - kBaseAddress] or 0
				end
				return 0
			end,
			read_u16 = function(addr)
				return env.abs_mem[addr] or 0
			end,
			read_u8 = function(addr)
				return env.abs_mem[addr] or 0
			end,
			write_i32 = function(addr, value)
				env.abs_mem[addr] = value
				if addr >= kBaseAddress then
					env.mem_store[addr - kBaseAddress] = value
				end
				return true
			end,
			write_u16 = function(addr, value)
				env.abs_mem[addr] = value
				return true
			end,
			write_u8 = function(addr, value)
				env.abs_mem[addr] = value
				return true
			end,
			read_rva_i32 = function(rva)
				return env.mem_store[rva] or 0
			end,
			write_rva_i32 = function(rva, value)
				env.mem_store[rva] = value
				env.abs_mem[kBaseAddress + rva] = value
				return true
			end,
		},
		game = {
			scene = function()
				return env.scene
			end,
			scene_frames = function()
				return env.scene_frames
			end,
			in_match = function()
				return env.in_match
			end,
			is_training = function()
				return env.is_training
			end,
			is_online = function()
				return env.is_online
			end,
			is_spectating = function()
				return env.is_spectating
			end,
			local_side = function()
				return env.local_side
			end,
			character = function()
				return 0
			end,
			character_name = function(id)
				return id == 0 and "Hyde" or "Linne"
			end,
			claim_pad = function()
				env.claim_pad_calls = env.claim_pad_calls + 1
				return 0
			end,
			request_scene = function(scene)
				env.requested_scenes[#env.requested_scenes + 1] = scene
				if scene == kOffsets.SCENE_NETWORK then
					env.enter_network_calls = env.enter_network_calls + 1
				elseif scene == kOffsets.SCENE_MAIN_MENU then
					env.leave_training_calls = env.leave_training_calls + 1
				end
				return true
			end,
			enter_network = function()
				env.enter_network_calls = env.enter_network_calls + 1
				return true
			end,
			leave_training = function()
				env.leave_training_calls = env.leave_training_calls + 1
				return true
			end,
			can_join_room = function()
				return env.can_join_room
			end,
			join_room = function(lobby, owner)
				env.joined_lobby = lobby
				env.joined_owner = owner
				return true
			end,
			room_create_start = function(ft)
				env.room_create_started = true
				env.room_create_first_to = ft or 0
				env.room_stage = 1
			end,
			room_create_set_first_to = function(ft)
				env.room_create_first_to = ft or 0
			end,
			room_create_stop = function()
				env.room_stage = 0
				env.room_create_stops = env.room_create_stops + 1
			end,
			room_create_step = function()
				return env.room_stage
			end,
			room_create_stage = function()
				return env.room_stage, env.room_stage_text
			end,
			room_create_timed_out = function()
				return env.room_create_timed_out
			end,
		},
		steam = {
			is_ready = function()
				return env.steam_id ~= "0" and env.steam_id ~= ""
			end,
			own_id = function()
				return env.steam_id
			end,
			lobby = function()
				return env.lobby
			end,
			lobby_owner = function()
				return env.lobby_owner
			end,
			lobby_limit = function()
				return 2
			end,
			launch_command_line = function()
				return env.launch_cmd
			end,
			launch_query = function(key)
				return env.launch_queries[key] or ""
			end,
			set_rich_presence_note = function(note)
				env.presence_notes[#env.presence_notes + 1] = note
			end,
		},
		replay = {
			folder = function()
				return "UNI2-IM\\Replays\\"
			end,
			can_play = function()
				return env.can_play_replay
			end,
			is_loading_patch = function()
				return env.is_loading_patch
			end,
			refresh = function() end,
			save_record = function(rec, note)
				if not env.save_record_ok then
					return ""
				end
				local p = "UNI2-IM\\Replays\\" .. note .. ".rep"
				env.fs_store[p] = rec
				return p
			end,
			describe_header = function()
				return {
					steam_id_0 = "76561198000000001",
					steam_id_1 = "76561198000000002",
					chara_0 = 0,
					chara_1 = 1,
				}
			end,
			matchup_of = function()
				return "Hyde vs Linne"
			end,
			request_playback = function(path)
				env.playback_requests[#env.playback_requests + 1] = path
				return env.playback_ok, env.playback_err
			end,
		},
		http = {
			request = function(req, cb)
				env.http_queue[#env.http_queue + 1] = { req = req, cb = cb }
			end,
			json_encode = json_encode,
			json_decode = function(body)
				return env.json_map[body]
			end,
		},
		draw = {
			fill = function(x, y, w, h, colour, layer)
				env.draw_fills[#env.draw_fills + 1] = {
					x = x,
					y = y,
					w = w,
					h = h,
					colour = colour,
					layer = layer,
				}
				return true
			end,
			frame = function()
				return true
			end,
			text = function()
				return true
			end,
		},
		offsets = kOffsets,
		ui = {
			register_window = function(id, title, wopts, fn)
				env.windows[id] = { title = title, opts = wopts, draw = fn, open = wopts.open or false }
			end,
			set_open = function(id, open)
				env.windows[id] = env.windows[id] or { open = false }
				env.windows[id].open = open
			end,
			is_open = function(id)
				return env.windows[id] ~= nil and env.windows[id].open or false
			end,
			scaled = function(v)
				return v
			end,
			avail_width = function()
				return 440
			end,
			reserve = function()
				return 10, 10
			end,
			dummy = function() end,
			separator = function() end,
			same_line = function() end,
			text = function(t)
				env.ui_texts[#env.ui_texts + 1] = t
			end,
			text_wrapped = function(t)
				env.ui_texts[#env.ui_texts + 1] = t
			end,
			text_muted = function(t)
				env.ui_texts[#env.ui_texts + 1] = t
			end,
			text_warn = function(t)
				env.ui_texts[#env.ui_texts + 1] = t
			end,
			text_good = function(t)
				env.ui_texts[#env.ui_texts + 1] = t
			end,
			button = function(label)
				return env.ui_clicks[label] == true
			end,
			small_button = function(label)
				return env.ui_clicks[label] == true
			end,
			checkbox = function(_, value)
				if env.ui_checkbox_change ~= nil then
					local next_val = env.ui_checkbox_change
					env.ui_checkbox_change = nil
					return true, next_val
				end
				return false, value
			end,
			input_text = function(id, _, value)
				if env.ui_inputs[id] ~= nil then
					return true, env.ui_inputs[id]
				end
				return false, value
			end,
			slider_int = function(_, value)
				if env.ui_slider ~= nil then
					return true, env.ui_slider
				end
				return false, value
			end,
			collapsing_header = function()
				return env.ui_collapsing_open
			end,
			set_next_item_width = function() end,
			begin_disabled = function() end,
			end_disabled = function() end,
			is_item_hovered = function()
				return env.ui_hovered
			end,
			set_tooltip = function(tip)
				env.ui_tooltips[#env.ui_tooltips + 1] = tip
			end,
			set_clipboard = function(text)
				env.ui_clipboard = text
			end,
			begin_child_card = function()
				return true
			end,
			end_child_card = function() end,
			push_button_color = function() end,
			pop_style_color = function() end,
			draw_rect_filled = function() end,
			draw_rect_filled_multi = function() end,
			draw_rect = function() end,
			draw_circle = function() end,
			draw_circle_filled = function() end,
			draw_line = function() end,
			draw_text = function(_, _, _, text)
				env.ui_texts[#env.ui_texts + 1] = text
			end,
			draw_text_centered = function(_, _, _, text)
				env.ui_texts[#env.ui_texts + 1] = text
			end,
			calc_text_size = function(t)
				return #t * 7, 14
			end,
			push_clip_rect = function() end,
			pop_clip_rect = function() end,
		},
	}
end

function FakeEnv:advance(ms)
	self.now_ms = self.now_ms + ms
end

function FakeEnv:set_lobby(lobby, owner)
	self.lobby = lobby
	self.lobby_owner = owner or "0"
end

function FakeEnv:set_scene(scene, frames)
	self.scene = scene
	self.scene_frames = frames or 60
end

function FakeEnv:set_mem(rva, value)
	self.mem_store[rva] = value
	self.abs_mem[kBaseAddress + rva] = value
end

function FakeEnv:set_abs(addr, value)
	self.abs_mem[addr] = value
end

function FakeEnv:get_abs(addr)
	return self.abs_mem[addr]
end

function FakeEnv:setup_create_room_screen(opts)
	opts = opts or {}
	local o = kOffsets
	local root = kBaseAddress + o.PLAYER_MATCH_ROOT
	local page_addr = opts.page_addr or 0x20000000
	local rows_addr = opts.rows_addr or 0x21000000
	local row_count = opts.row_count or 16

	self.abs_mem[root + o.PLAYER_MATCH_STATE] = o.PLAYER_MATCH_CREATE_SCREEN
	self.abs_mem[root + o.PLAYER_MATCH_DIALOG_STEP] = o.PLAYER_MATCH_DIALOG_OPEN
	self.abs_mem[root + o.PLAYER_MATCH_CREATE_MENU] = o.CREATE_MENU_CHOOSING
	self.abs_mem[root + o.PLAYER_MATCH_CREATE_ANSWER] = o.CREATE_MENU_UNANSWERED
	self.abs_mem[root + o.PLAYER_MATCH_ROOM_TYPE] = opts.room_type or 0
	self.abs_mem[root + o.PLAYER_MATCH_USE_ALT_SETTINGS] = opts.use_alt and 1 or 0

	self.abs_mem[root + o.PLAYER_MATCH_SETTINGS + o.MENU_PAGES] = page_addr
	self.abs_mem[root + o.PLAYER_MATCH_SETTINGS + o.MENU_PAGES + 4] = page_addr + o.MENU_PAGE_STRIDE
	self.abs_mem[page_addr] = rows_addr
	self.abs_mem[page_addr + 4] = rows_addr + row_count * o.MENU_ROW_STRIDE

	local alt_rows_addr = opts.alt_rows_addr or 0x22000000
	if opts.use_alt then
		local alt_page_addr = opts.alt_page_addr or 0x20100000
		local alt_count = opts.alt_row_count or 10
		self.abs_mem[root + o.PLAYER_MATCH_ALT_SETTINGS + o.MENU_PAGES] = alt_page_addr
		self.abs_mem[root + o.PLAYER_MATCH_ALT_SETTINGS + o.MENU_PAGES + 4] = alt_page_addr + o.MENU_PAGE_STRIDE
		self.abs_mem[alt_page_addr] = alt_rows_addr
		self.abs_mem[alt_page_addr + 4] = alt_rows_addr + alt_count * o.MENU_ROW_STRIDE
	end

	return root, rows_addr, alt_rows_addr
end

function FakeEnv:set_json(body, tbl)
	self.json_map[body] = tbl
	return body
end

function FakeEnv:pop_http()
	return table.remove(self.http_queue, 1)
end

function FakeEnv:respond_next_http(status, body, err, sent)
	local item = self:pop_http()
	if not item then
		error("no pending HTTP request to respond to", 2)
	end
	item.cb({
		sent = sent == nil and true or sent,
		status = status,
		body = body or "",
		error = err or "",
	})
	return item.req
end

function FakeEnv:build_app()
	local app = bootstrap.build(self.api)
	app.env = self
	return app
end

return FakeEnv
