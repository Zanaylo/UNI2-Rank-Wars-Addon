local Runner = {}

local suites = {}
local current_suite = nil

local function deep_equal(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not deep_equal(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function Runner.suite(name, fn)
	local entry = {
		name = name,
		tests = {},
		before_each = nil,
		after_each = nil,
	}
	suites[#suites + 1] = entry
	current_suite = entry
	fn()
	current_suite = nil
end

function Runner.before_each(fn)
	if current_suite then
		current_suite.before_each = fn
	end
end

function Runner.after_each(fn)
	if current_suite then
		current_suite.after_each = fn
	end
end

function Runner.test(name, fn)
	local target = current_suite
	if not target then
		target = { name = "default", tests = {} }
		suites[#suites + 1] = target
	end
	target.tests[#target.tests + 1] = { name = name, fn = fn }
end

function Runner.fail(message)
	error(message or "assertion failed", 3)
end

function Runner.assert_true(value, message)
	if value ~= true then
		Runner.fail(string.format("%s (expected true, got %s)", message or "assert_true", tostring(value)))
	end
end

function Runner.assert_false(value, message)
	if value ~= false then
		Runner.fail(string.format("%s (expected false, got %s)", message or "assert_false", tostring(value)))
	end
end

function Runner.assert_nil(value, message)
	if value ~= nil then
		Runner.fail(string.format("%s (expected nil, got %s)", message or "assert_nil", tostring(value)))
	end
end

function Runner.assert_not_nil(value, message)
	if value == nil then
		Runner.fail(string.format("%s (expected non-nil)", message or "assert_not_nil"))
	end
end

function Runner.assert_eq(actual, expected, message)
	if actual ~= expected then
		Runner.fail(string.format("%s (expected %s, got %s)", message or "assert_eq", tostring(expected), tostring(actual)))
	end
end

function Runner.assert_table_eq(actual, expected, message)
	if not deep_equal(actual, expected) then
		Runner.fail(message or "assert_table_eq: tables differ")
	end
end

function Runner.assert_contains(haystack, needle, message)
	if type(haystack) ~= "string" or haystack:find(needle, 1, true) == nil then
		Runner.fail(string.format("%s (expected %q to contain %q)", message or "assert_contains", tostring(haystack), tostring(needle)))
	end
end

function Runner.assert_error(fn, needle, message)
	local ok, err = pcall(fn)
	if ok then
		Runner.fail(message or "assert_error: expected function to throw")
	end
	if needle and tostring(err):find(needle, 1, true) == nil then
		Runner.fail(string.format("%s (error %q did not contain %q)", message or "assert_error", tostring(err), needle))
	end
end

local function run_case(suite, case)
	if suite.before_each then
		suite.before_each()
	end
	local ok, err = pcall(case.fn)
	if suite.after_each then
		local clean_ok, clean_err = pcall(suite.after_each)
		if ok and not clean_ok then
			return false, clean_err
		end
	end
	return ok, err
end

function Runner.run()
	local passed = 0
	local failed = 0

	for _, suite in ipairs(suites) do
		for _, case in ipairs(suite.tests) do
			local ok, err = run_case(suite, case)
			if ok then
				passed = passed + 1
			else
				failed = failed + 1
				io.stderr:write(string.format("FAIL [%s] %s: %s\n", suite.name, case.name, tostring(err)))
			end
		end
	end

	print(string.format("RankWars Lua tests: %d passed, %d failed (%d suites)", passed, failed, #suites))
	return failed == 0 and 0 or 1
end

return Runner
