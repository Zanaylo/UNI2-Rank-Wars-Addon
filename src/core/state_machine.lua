local class = require("src.core.class")

local StateMachine = class()

function StateMachine:init(initial_state, states)
	self.states = states or {}
	self.current = initial_state
end

function StateMachine:state()
	return self.current
end

function StateMachine:definition(name)
	return self.states[name or self.current]
end

function StateMachine:is(name)
	return self.current == name
end

function StateMachine:transition(next_state, context, ...)
	if self.current == next_state then
		return false
	end

	local prev_def = self.states[self.current]
	if prev_def and prev_def.on_exit then
		prev_def.on_exit(context, next_state)
	end

	self.current = next_state

	local next_def = self.states[next_state]
	if next_def and next_def.on_enter then
		next_def.on_enter(context, ...)
	end

	return true
end

function StateMachine:update(context)
	local def = self.states[self.current]
	if not def or not def.on_update then
		return
	end
	def.on_update(context)
end

return StateMachine
