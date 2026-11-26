local t = require("tests.support.runner")
local StateMachine = require("src.core.state_machine")

t.suite("core/state_machine", function()
	t.test("runs on_exit, on_enter, and on_update and ignores same-state transitions", function()
		local trace = {}
		local fsm = StateMachine.new("idle", {
			idle = {
				on_exit = function(ctx, next_state)
					trace[#trace + 1] = "exit:" .. ctx.id .. "->" .. next_state
				end,
			},
			running = {
				on_enter = function(ctx, tag)
					trace[#trace + 1] = "enter:" .. ctx.id .. ":" .. tag
				end,
				on_update = function(ctx)
					trace[#trace + 1] = "update:" .. ctx.id
				end,
			},
		})
		local ctx = { id = "x" }

		t.assert_true(fsm:is("idle"))
		t.assert_false(fsm:transition("idle", ctx))
		t.assert_true(fsm:transition("running", ctx, "go"))
		t.assert_eq(fsm:state(), "running")
		fsm:update(ctx)

		t.assert_table_eq(trace, { "exit:x->running", "enter:x:go", "update:x" })
	end)
end)
