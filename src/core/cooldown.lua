local class = require("src.core.class")

local Cooldown = class()

function Cooldown:init(interval_ms, clock_fn)
	self.interval_ms = interval_ms
	self.clock_fn = clock_fn
	self.last_at = nil
end

function Cooldown:ready()
	if not self.last_at then
		return true
	end
	return self.clock_fn() - self.last_at >= self.interval_ms
end

function Cooldown:try_trigger()
	if not self:ready() then
		return false
	end
	self.last_at = self.clock_fn()
	return true
end

function Cooldown:mark()
	self.last_at = self.clock_fn()
end

function Cooldown:reset()
	self.last_at = nil
end

local Backoff = class()

function Backoff:init(delays, clock_fn)
	self.delays = delays
	self.clock_fn = clock_fn
	self.attempt = 0
	self.scheduled_at = 0
	self.delay = 0
end

function Backoff:reset()
	self.attempt = 0
	self.scheduled_at = 0
	self.delay = 0
end

function Backoff:can_advance()
	return self.attempt < #self.delays
end

function Backoff:schedule_next(clamp)
	if not clamp and not self:can_advance() then
		return nil
	end
	self.attempt = self.attempt + 1
	local idx = math.min(self.attempt, #self.delays)
	self.delay = self.delays[idx]
	self.scheduled_at = self.clock_fn()
	return self.delay
end

function Backoff:ready()
	return self.clock_fn() - self.scheduled_at >= self.delay
end

return {
	Cooldown = Cooldown,
	Backoff = Backoff,
}
