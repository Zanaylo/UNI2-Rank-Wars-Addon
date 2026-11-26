local class = require("src.core.class")

local Protocol = class()

local kLineBreak = "\r\n"
local kMaxAbortReasonLen = 500
local kPlayerRoles = { "host", "guest" }

local kStatusStates = {
	PENDING_ACCEPT = "waiting",
	COMPLETED = "completed",
	UNDER_REVIEW = "closed",
	CANCELLED = "closed",
	VOIDED = "closed",
}

local function as_table(value)
	return type(value) == "table" and value or {}
end

local function parse_score(raw)
	local score = as_table(raw)
	return {
		host = tonumber(score.host) or 0,
		guest = tonumber(score.guest) or 0,
	}
end

local function parse_player(raw)
	local player = as_table(raw)
	return {
		name = tostring(player.displayName or ""),
		steam_id = tostring(player.steamId64 or "0"),
	}
end

local function append_form_field(parts, boundary, name, value)
	parts[#parts + 1] = "--" .. boundary .. kLineBreak
	parts[#parts + 1] = 'Content-Disposition: form-data; name="' .. name .. '"' .. kLineBreak .. kLineBreak
	parts[#parts + 1] = value .. kLineBreak
end

function Protocol:init(json)
	self.json = json
end

function Protocol:decode_object(body)
	local root = self.json.json_decode(body or "")
	if type(root) ~= "table" then
		return nil
	end
	return root
end

function Protocol:other_role(role)
	return role == "host" and "guest" or "host"
end

function Protocol:slug(name)
	if not name or name == "" then
		return ""
	end
	return name:lower()
end

function Protocol:room_body(lobby, owner)
	return self.json.json_encode({
		lobbyId = tostring(lobby),
		ownerSteamId = tostring(owner),
	})
end

function Protocol:abort_body(reason)
	return self.json.json_encode({
		reason = (reason or ""):sub(1, kMaxAbortReasonLen),
	})
end

function Protocol:sandbox_body(password, first_to)
	local payload = { password = password or "" }
	if first_to and first_to > 0 then
		payload.firstTo = first_to
	end
	return self.json.json_encode(payload)
end

function Protocol:game_form(boundary, replay_bytes, file_name, winner_role, host_chara, guest_chara)
	local parts = {}
	local fields = {
		{ "winner", winner_role },
		{ "hostCharacter", host_chara },
		{ "guestCharacter", guest_chara },
	}

	for _, entry in ipairs(fields) do
		if entry[2] and entry[2] ~= "" then
			append_form_field(parts, boundary, entry[1], entry[2])
		end
	end

	parts[#parts + 1] = "--" .. boundary .. kLineBreak
	parts[#parts + 1] = 'Content-Disposition: form-data; name="replay"; filename="' .. file_name .. '"' .. kLineBreak
	parts[#parts + 1] = "Content-Type: application/octet-stream" .. kLineBreak .. kLineBreak
	parts[#parts + 1] = replay_bytes
	parts[#parts + 1] = kLineBreak .. "--" .. boundary .. "--" .. kLineBreak

	return "multipart/form-data; boundary=" .. boundary, table.concat(parts)
end

function Protocol:parse_match(body)
	local root = self:decode_object(body)
	if not root then
		return nil
	end

	return {
		id = tostring(root.id or ""),
		status = tostring(root.status or ""),
		role = root.role == "guest" and "guest" or "host",
		first_to = tonumber(root.firstTo) or 0,
		lobby = tostring(root.lobbyId or "0"),
		lobby_owner = tostring(root.lobbyOwnerSteamId or "0"),
		score = parse_score(root.score),
		host = parse_player(root.host),
		guest = parse_player(root.guest),
		sandbox = root.sandbox == true,
		join_url = tostring(root.joinRoomUrl or ""),
	}
end

function Protocol:parse_game_answer(body)
	local root = self:decode_object(body)
	if not root then
		return nil
	end

	local match = as_table(root.match)
	return {
		result = tostring(root.result or ""),
		status = tostring(match.status or ""),
		first_to = tonumber(match.firstTo) or 0,
		finished = match.finished == true,
		score = parse_score(match.score),
	}
end

function Protocol:parse_sandbox(body)
	local root = self:decode_object(body)
	if not root then
		return nil
	end

	local match_id = tostring(root.matchId or "")
	local host_token = tostring(root.hostToken or "")
	if match_id == "" or host_token == "" then
		return nil
	end

	return {
		match = match_id,
		first_to = tonumber(root.firstTo) or 0,
		host_token = host_token,
		guest_token = tostring(root.guestToken or ""),
	}
end

function Protocol:describe_error(status, body)
	local suffix = "HTTP " .. tostring(status or 0)
	local root = self:decode_object(body)
	if not root then
		return suffix
	end

	local message = tostring(root.error or "")
	if message == "" then
		return suffix
	end

	local code = tostring(root.code or "")
	if code ~= "" then
		return message .. " (" .. code .. ", " .. suffix .. ")"
	end
	return message .. " (" .. suffix .. ")"
end

function Protocol:should_retry(status)
	return status == 0 or status == 429 or status >= 500
end

function Protocol:state_of(status)
	return kStatusStates[status] or "open"
end

function Protocol:name_of_steam_id(info, steam_id)
	if not info or not steam_id or steam_id == "" or steam_id == "0" then
		return ""
	end
	for _, role in ipairs(kPlayerRoles) do
		local player = info[role]
		if player and steam_id == player.steam_id then
			return player.name or ""
		end
	end
	return ""
end

return Protocol
