local t = require("tests.support.runner")
local class = require("src.core.class")

t.suite("core/class", function()
	t.test("instantiates independent objects and invokes init", function()
		local Counter = class()
		function Counter:init(start)
			self.value = start or 0
		end
		function Counter:inc()
			self.value = self.value + 1
		end

		local a = Counter.new(10)
		local b = Counter.new()
		a:inc()

		t.assert_eq(a.value, 11)
		t.assert_eq(b.value, 0)
	end)
end)
