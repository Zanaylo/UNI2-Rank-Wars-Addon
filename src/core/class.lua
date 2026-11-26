local function class()
	local cls = {}
	cls.__index = cls

	function cls.new(...)
		local instance = setmetatable({}, cls)
		if cls.init then
			cls.init(instance, ...)
		end
		return instance
	end

	return cls
end

return class
