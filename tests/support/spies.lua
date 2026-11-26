local Spies = {}

function Spies.new(handler)
	local record = {
		calls = {},
	}

	local function fn(...)
		local args = table.pack(...)
		record.calls[#record.calls + 1] = args
		if handler then
			return handler(...)
		end
		return nil
	end

	function record:count()
		return #self.calls
	end

	function record:last()
		return self.calls[#self.calls]
	end

	return fn, record
end

return Spies
