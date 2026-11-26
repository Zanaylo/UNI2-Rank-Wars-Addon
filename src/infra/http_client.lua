local class = require("src.core.class")
local cooldown = require("src.core.cooldown")

local HttpClient = class()

local kApiPath = "/api/im/v1"
local kRetryDelays = { 2000, 5000, 10000, 20000, 30000, 60000 }

local function is_success(status)
	return status >= 200 and status <= 299
end

function HttpClient:init(api_url, token, steam_id, deps)
	self.base = api_url .. kApiPath
	self.token = token or ""
	self.steam_id = tostring(steam_id or "0")
	self.http = deps.http
	self.time = deps.time
	self.log = deps.log
	self.protocol = deps.protocol
	self.queue = {}
	self.in_flight = false
	self.pending_retry = nil
	self.retry_backoff = cooldown.Backoff.new(kRetryDelays, deps.time)
end

function HttpClient:build_headers(job)
	local headers = {
		Accept = job.accept or "application/json",
	}
	if self.token ~= "" then
		headers["Authorization"] = "Bearer " .. self.token
	end
	if self.steam_id ~= "" and self.steam_id ~= "0" then
		headers["X-Steam-Id"] = self.steam_id
	end
	if job.content_type and job.content_type ~= "" then
		headers["Content-Type"] = job.content_type
	end
	return headers
end

function HttpClient:handle_response(job, resp)
	self.in_flight = false

	local status = resp.sent and resp.status or 0
	local ok = resp.sent and is_success(status)
	local err = ""
	if not ok then
		err = resp.sent and self.protocol:describe_error(status, resp.body) or resp.error
	end

	self.log(string.format("%s %s attempt %d -> %d %s", job.method, job.path, job.attempt, status, ok and "ok" or err))

	if not ok and job.retries and self.protocol:should_retry(status) and self.retry_backoff:can_advance() then
		self.retry_backoff:schedule_next(false)
		job.attempt = job.attempt + 1
		self.pending_retry = job
		return
	end

	self.retry_backoff:reset()
	if not job.callback then
		return
	end

	job.callback({
		ok = ok,
		status = status,
		body = resp.body or "",
		error = err,
		game_number = job.game_number or 0,
	})
end

function HttpClient:dispatch(job)
	self.in_flight = true
	self.http.request({
		method = job.method,
		url = self.base .. job.path,
		headers = self:build_headers(job),
		body = job.body or "",
	}, function(resp)
		self:handle_response(job, resp)
	end)
end

function HttpClient:next_ready_job()
	if self.pending_retry then
		if not self.retry_backoff:ready() then
			return nil
		end
		local job = self.pending_retry
		self.pending_retry = nil
		return job
	end

	if #self.queue == 0 then
		return nil
	end
	return table.remove(self.queue, 1)
end

function HttpClient:enqueue(job)
	job.attempt = 1
	if job.retries == nil then
		job.retries = true
	end
	self.queue[#self.queue + 1] = job
end

function HttpClient:tick()
	if self.in_flight then
		return
	end
	local job = self:next_ready_job()
	if not job then
		return
	end
	self:dispatch(job)
end

function HttpClient:pending()
	return #self.queue + (self.in_flight and 1 or 0) + (self.pending_retry and 1 or 0)
end

function HttpClient:put_room(lobby, owner, cb)
	self:enqueue({
		method = "PUT",
		path = "/room",
		content_type = "application/json",
		body = self.protocol:room_body(lobby, owner),
		callback = cb,
	})
end

function HttpClient:put_game(number, winner_role, host_chara, guest_chara, file_name, replay_bytes, cb)
	local boundary = string.format("----RankWars%08x%s", self.time() % 0xFFFFFFFF, self.steam_id)
	local content_type, body = self.protocol:game_form(boundary, replay_bytes, file_name, winner_role, host_chara, guest_chara)
	self:enqueue({
		method = "PUT",
		path = "/games/" .. tostring(number),
		content_type = content_type,
		body = body,
		game_number = number,
		callback = cb,
	})
end

function HttpClient:abort(reason, cb)
	self:enqueue({
		method = "POST",
		path = "/abort",
		content_type = "application/json",
		body = self.protocol:abort_body(reason),
		callback = cb,
	})
end

function HttpClient:fetch_match(cb)
	self:enqueue({
		method = "GET",
		path = "/match",
		callback = cb,
	})
end

function HttpClient:create_sandbox(password, first_to, cb)
	self:enqueue({
		method = "POST",
		path = "/debug/session",
		content_type = "application/json",
		body = self.protocol:sandbox_body(password, first_to),
		retries = false,
		callback = cb,
	})
end

function HttpClient:fetch_replay(replay_id, cb)
	self:enqueue({
		method = "GET",
		path = "/replays/" .. replay_id,
		accept = "application/octet-stream",
		callback = cb,
	})
end

return HttpClient
