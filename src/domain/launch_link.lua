local M = {}

local kKeys = { "action", "match", "token", "api", "lobby", "owner", "replay" }

local kActionNames = {
	create = "host",
	join = "guest",
	replay = "viewer",
}

local function decode_hex_byte(hex)
	return string.char(tonumber(hex, 16))
end

local function is_token_start(text, index)
	if index == 1 then
		return true
	end
	local prev = text:sub(index - 1, index - 1)
	return prev == " " or prev == '"'
end

local function find_query(command_line)
	local quoted = false
	local start_idx = nil

	for i = 1, #command_line do
		local c = command_line:sub(i, i)
		if start_idx and (c == '"' or (c == " " and not quoted)) then
			return command_line:sub(start_idx, i - 1)
		end
		if c == '"' then
			quoted = not quoted
		elseif not start_idx and c == "?" and is_token_start(command_line, i) then
			start_idx = i + 1
		end
	end

	if not start_idx then
		return ""
	end
	return command_line:sub(start_idx)
end

local function split_fields(query)
	local fields = {}
	for pair in (query .. "&"):gmatch("([^&]*)&") do
		local eq = pair:find("=", 1, true)
		if eq then
			fields[pair:sub(1, eq - 1)] = M.url_decode(pair:sub(eq + 1))
		end
	end
	return fields
end

local function is_decimal_id(text)
	return text ~= nil and text ~= "" and text ~= "0" and text:match("^%d+$") ~= nil
end

local function is_plain_id(text)
	return text ~= nil and text ~= "" and text:match("^[%w_%-]+$") ~= nil
end

local function is_http(url)
	return url:sub(1, 8) == "https://" or url:sub(1, 7) == "http://"
end

local function validate_match_credentials(link)
	if link.match == "" or link.token == "" then
		return "the link has no match or token"
	end
	return nil
end

local kActionValidators = {
	create = validate_match_credentials,
	join = function(link)
		local cred_err = validate_match_credentials(link)
		if cred_err then
			return cred_err
		end
		if not is_decimal_id(link.lobby) or not is_decimal_id(link.owner) then
			return "the join link has no valid lobby or owner"
		end
		return nil
	end,
	replay = function(link)
		link.match = ""
		if not is_plain_id(link.replay) then
			return "the replay link has no valid replay"
		end
		if link.token == "" then
			return "the replay link has no token"
		end
		return nil
	end,
}

local function build_link(fields)
	local action = fields.action or ""
	local validator = kActionValidators[action]
	if not validator then
		return nil, "the link does not say whether to create or join a room"
	end

	local api = (fields.api or ""):gsub("/+$", "")
	if not is_http(api) then
		return nil, "the API address in the link is not an http address"
	end

	local link = {
		action = action,
		match = fields.match or "",
		token = fields.token or "",
		api = api,
		lobby = fields.lobby or "0",
		owner = fields.owner or "0",
		replay = fields.replay or "",
	}

	local err = validator(link)
	if err then
		return nil, err
	end
	return link, nil
end

function M.url_decode(text)
	if not text or text == "" then
		return ""
	end
	return (text:gsub("+", " "):gsub("%%(%x%x)", decode_hex_byte))
end

function M.parse_command_line(command_line)
	local query = find_query(command_line or "")
	if query == "" then
		return nil, nil
	end
	return build_link(split_fields(query))
end

function M.parse_launch_parameters(params)
	local bare = (params or ""):gsub("^[/?]+", ""):gsub("/+$", "")
	if bare == "" then
		return nil, nil
	end
	return build_link(split_fields(bare))
end

function M.parse_query_values(getter)
	local fields = {}
	local any = false

	for _, key in ipairs(kKeys) do
		local value = getter(key)
		if value and value ~= "" then
			fields[key] = value
			any = true
		end
	end

	if not any then
		return nil, nil
	end
	return build_link(fields)
end

function M.host_link(match, token, api)
	return build_link({
		action = "create",
		match = match,
		token = token,
		api = api,
	})
end

function M.action_name(action)
	return kActionNames[action] or "none"
end

return M
