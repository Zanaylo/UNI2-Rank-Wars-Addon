local t = require("tests.support.runner")
local cooldown = require("src.core.cooldown")

t.suite("core/cooldown", function()
	t.test("triggers immediately on first call then respects interval", function()
		local now = 100
		local cd = cooldown.Cooldown.new(3000, function()
			return now
		end)

		t.assert_true(cd:ready())
		t.assert_true(cd:try_trigger())
		t.assert_false(cd:ready())
		t.assert_false(cd:try_trigger())

		now = 3099
		t.assert_false(cd:try_trigger())

		now = 3100
		t.assert_true(cd:try_trigger())
	end)

	t.test("reset makes cooldown immediately ready again", function()
		local now = 500
		local cd = cooldown.Cooldown.new(2000, function()
			return now
		end)

		cd:mark()
		t.assert_false(cd:ready())
		cd:reset()
		t.assert_true(cd:ready())
	end)

	t.test("backoff advances through delays and stops when unclamped", function()
		local now = 1000
		local backoff = cooldown.Backoff.new({ 2000, 5000 }, function()
			return now
		end)

		t.assert_true(backoff:can_advance())
		t.assert_eq(backoff:schedule_next(false), 2000)
		t.assert_false(backoff:ready())

		now = 3000
		t.assert_true(backoff:ready())

		t.assert_eq(backoff:schedule_next(false), 5000)
		t.assert_false(backoff:can_advance())
		t.assert_nil(backoff:schedule_next(false))

		backoff:reset()
		t.assert_true(backoff:can_advance())
	end)

	t.test("backoff clamps to final delay when requested", function()
		local now = 0
		local backoff = cooldown.Backoff.new({ 1000, 3000 }, function()
			return now
		end)

		t.assert_eq(backoff:schedule_next(true), 1000)
		t.assert_eq(backoff:schedule_next(true), 3000)
		t.assert_eq(backoff:schedule_next(true), 3000)
	end)
end)
