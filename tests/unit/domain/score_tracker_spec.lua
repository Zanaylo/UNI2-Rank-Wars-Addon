local t = require("tests.support.runner")
local ScoreTracker = require("src.domain.score_tracker")

t.suite("domain/score_tracker", function()
	t.test("tracks match score, local wins, and reconciliation polling backoff", function()
		local now = 1000
		local tracker = ScoreTracker.new(function()
			return now
		end)

		local changed = tracker:apply_match({
			status = "IN_PROGRESS",
			first_to = 3,
			score = { host = 1, guest = 0 },
			host = { name = "A", steam_id = "1" },
			guest = { name = "B", steam_id = "2" },
			sandbox = false,
			join_url = "",
		})
		t.assert_true(changed)
		t.assert_true(tracker.match_loaded)
		t.assert_eq(tracker.played, 1)

		local game_num = tracker:record_local_game("host")
		t.assert_eq(game_num, 2)
		tracker:apply_game_answer(2, {
			score = { host = 1, guest = 0 },
			first_to = 3,
		})
		tracker:sync_reconciliation(true, false)
		t.assert_true(tracker.score_due)
		t.assert_false(tracker:should_poll())

		now = 3000
		t.assert_true(tracker:should_poll())
		tracker:mark_polled()
		t.assert_false(tracker:should_poll())

		now = 7999
		t.assert_false(tracker:should_poll())
		now = 8000
		t.assert_true(tracker:should_poll())

		tracker:apply_game_answer(2, {
			score = { host = 2, guest = 0 },
			first_to = 3,
		})
		tracker:sync_reconciliation(true, false)
		t.assert_false(tracker.score_due)
	end)

	t.test("detects decided score and resets cleanly", function()
		local tracker = ScoreTracker.new(function()
			return 0
		end)
		t.assert_true(tracker:is_decided({ host = 3, guest = 2 }, 3))
		t.assert_false(tracker:is_decided({ host = 2, guest = 2 }, 3))
		t.assert_false(tracker:is_decided({ host = 5, guest = 0 }, 0))

		tracker:record_local_game("guest")
		tracker:reset()
		t.assert_eq(tracker.played, 0)
		t.assert_eq(tracker.local_wins.guest, 0)
		t.assert_false(tracker.match_loaded)
	end)
end)
