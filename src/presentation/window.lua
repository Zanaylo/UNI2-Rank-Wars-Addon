local class = require("src.core.class")

local Window = class()

local kAccent = { 0.063, 0.725, 0.506, 1.00 }
local kAccentDark = { 0.055, 0.240, 0.180, 1.00 }
local kShade = { 0.00, 0.00, 0.00, 0.35 }
local kCard = { 0.075, 0.098, 0.090, 0.96 }
local kCardEdge = { 0.118, 0.161, 0.145, 1.00 }
local kDone = { 0.204, 0.827, 0.600, 1.00 }
local kIdle = { 0.35, 0.42, 0.39, 1.00 }
local kText = { 0.922, 0.949, 0.933, 1.00 }
local kMuted = { 0.490, 0.573, 0.537, 1.00 }
local kGlow = { 0.063, 0.725, 0.506, 0.35 }
local kProblem = { 0.320, 0.078, 0.118, 0.65 }
local kProblemEdge = { 0.957, 0.247, 0.369, 0.85 }

local kHostStepLabels = { "Link", "Rank Wars", "Room", "Games", "Result" }
local kGuestStepLabels = { "Link", "Rank Wars", "Join", "Games", "Result" }

local kWorkingPhases = {
	creating_test = true,
	waiting_steam = true,
	waiting_room = true,
	reporting_room = true,
	waiting_join = true,
	joining = true,
}

function Window:init(session, hud, deps)
	self.session = session
	self.hud = hud
	self.ui = deps.ui
	self.config = deps.config
	self.clock = deps.clock
	self.version_label = (deps.version and deps.version ~= "") and ("v" .. deps.version) or ""
	self.confirming = false
	self.reason = ""
	self.test_loaded = false
	self.test_tools = false
	self.test_api = ""
	self.test_password = ""
	self.test_first_to = 0
end

function Window:load_test_settings()
	if self.test_loaded then
		return
	end
	self.test_loaded = true
	self.test_tools = self.config.get_int("RankWars", "TestTools", 0) ~= 0
	self.test_api = self.config.get_string("RankWars", "TestApi", "")
	self.test_password = self.config.get_string("RankWars", "TestPassword", "")
end

function Window:dots()
	local n = math.floor(self.clock() * 2.5) % 4
	return string.rep(".", n)
end

function Window:draw_pips(cx, y, wins, needed)
	local ui = self.ui
	local r = ui.scaled(5.0)
	local gap = ui.scaled(14.0)
	local left = cx - gap * (needed - 1) * 0.5

	for pip = 0, needed - 1 do
		local x = left + gap * pip
		if pip < wins then
			ui.draw_circle_filled(x, y, r, kAccent)
		else
			ui.draw_circle(x, y, r, kIdle, ui.scaled(1.5))
		end
	end
end

function Window:draw_header(view)
	local ui = self.ui
	local width = ui.avail_width()
	local height = ui.scaled(46.0)
	local x, y = ui.reserve(height)
	local x2 = x + width
	local y2 = y + height

	ui.draw_rect_filled_multi(x, y, x2, y2, kAccent, kAccentDark)
	local tw, th = ui.calc_text_size("RANK WARS", 1.35)
	local title_x = x + ui.scaled(12.0)
	local title_y = y + (height - th) * 0.5
	ui.draw_text(title_x, title_y, kText, "RANK WARS", 1.35)

	if self.version_label ~= "" then
		local _, vh = ui.calc_text_size(self.version_label, 0.85)
		ui.draw_text(title_x + tw + ui.scaled(8.0), title_y + th - vh, kText, self.version_label, 0.85)
	end

	if view.role == "" then
		return
	end

	local pill = view.is_host and "HOST" or "GUEST"
	local pw, ph = ui.calc_text_size(pill, 1.0)
	local px = ui.scaled(8.0)
	local py = ui.scaled(3.0)
	local mid = y2 - height * 0.5
	local rx2 = x2 - ui.scaled(12.0)
	local rx1 = rx2 - pw - px * 2.0
	local ry1 = mid - ph * 0.5 - py
	local ry2 = mid + ph * 0.5 + py

	ui.draw_rect_filled(rx1, ry1, rx2, ry2, kShade, ui.scaled(10.0))
	ui.draw_text(rx1 + px, ry1 + py, kText, pill, 1.0)
	ui.text_muted("Match " .. view.match)
end

function Window:draw_player_column(col_x, y, y2, third, pad, name, is_you)
	local ui = self.ui
	local cx = col_x + third * 0.5
	ui.push_clip_rect(col_x, y, col_x + third, y2)
	ui.draw_text_centered(cx, y + pad, is_you and kText or kMuted, name, 1.1)
	ui.pop_clip_rect()

	if not is_you then
		return
	end
	local _, nh = ui.calc_text_size(name, 1.1)
	ui.draw_text_centered(cx, y + pad + nh + ui.scaled(2.0), kAccent, "YOU", 0.85)
end

function Window:draw_scoreboard(view)
	if view.role == "" then
		return
	end

	local ui = self.ui
	local width = ui.avail_width()
	local height = ui.scaled(96.0)
	local x, y = ui.reserve(height)
	local x2 = x + width
	local y2 = y + height
	local pad = ui.scaled(12.0)
	local third = width / 3.0

	ui.draw_rect_filled(x, y, x2, y2, kCard, ui.scaled(8.0))
	ui.draw_rect(x, y, x2, y2, kCardEdge, ui.scaled(8.0))

	local host_name = view.host ~= "" and view.host or "Host"
	local guest_name = view.guest ~= "" and view.guest or "Guest"
	self:draw_player_column(x, y, y2, third, pad, host_name, view.is_host)
	self:draw_player_column(x + third * 2.0, y, y2, third, pad, guest_name, not view.is_host)

	local score_str = string.format("%d - %d", view.score.host, view.score.guest)
	local _, sh = ui.calc_text_size(score_str, 2.4)
	ui.draw_text_centered(x + width * 0.5, y + (height - sh) * 0.5 - pad * 0.4, kText, score_str, 2.4)

	if view.first_to <= 0 then
		return
	end

	local pip_y = y2 - pad
	self:draw_pips(x + third * 0.5, pip_y, view.score.host, view.first_to)
	self:draw_pips(x + third * 2.5, pip_y, view.score.guest, view.first_to)

	local ft_text = "First to " .. tostring(view.first_to)
	local _, fh = ui.calc_text_size(ft_text, 0.85)
	ui.draw_text_centered(x + width * 0.5, pip_y - fh * 0.5, kMuted, ft_text, 0.85)
end

function Window:draw_step_node(cx, cy, radius, line_w, index, step, finished)
	local ui = self.ui
	if index < step or (finished and index == step) then
		ui.draw_circle_filled(cx, cy, radius, kDone)
		ui.draw_line(cx - radius * 0.45, cy + radius * 0.02, cx - radius * 0.10, cy + radius * 0.38, kText, line_w)
		ui.draw_line(cx - radius * 0.10, cy + radius * 0.38, cx + radius * 0.50, cy - radius * 0.35, kText, line_w)
		return
	end

	if index > step then
		ui.draw_circle(cx, cy, radius, kIdle, line_w)
		return
	end

	local pulse = 0.5 + 0.5 * math.sin(self.clock() * 4.0)
	ui.draw_circle_filled(cx, cy, radius + ui.scaled(3.0) * pulse, kGlow)
	ui.draw_circle_filled(cx, cy, radius, kAccent)
end

function Window:draw_steps(view)
	local ui = self.ui
	ui.dummy(0.0, ui.scaled(6.0))
	local width = ui.avail_width()
	local x, y = ui.reserve(ui.scaled(54.0))
	local radius = ui.scaled(9.0)
	local pad = ui.scaled(21.0)
	local labels = view.is_host and kHostStepLabels or kGuestStepLabels
	local span = (width - pad * 2.0) / 4.0
	local cy = y + radius + ui.scaled(4.0)
	local line_w = ui.scaled(2.0)
	local finished = view.phase == "finished"

	for i = 0, 3 do
		ui.draw_line(x + pad + span * i, cy, x + pad + span * (i + 1), cy, i < view.step and kDone or kIdle, line_w)
	end

	for i = 0, 4 do
		local cx = x + pad + span * i
		self:draw_step_node(cx, cy, radius, line_w, i, view.step, finished)
		ui.draw_text_centered(cx, cy + radius + ui.scaled(6.0), i <= view.step and kText or kMuted, labels[i + 1], 0.85)
	end
end

function Window:draw_status(view)
	local ui = self.ui
	local suffix = kWorkingPhases[view.phase] and self:dots() or ""
	ui.text_wrapped(view.phase_text .. suffix)

	if view.detail ~= "" then
		ui.text_muted(view.detail)
	end
	if view.last_game ~= "" then
		ui.text_wrapped(view.last_game)
	end
	if view.pending > 0 then
		ui.text_muted(string.format("Sending %d update(s)%s", view.pending, self:dots()))
	end
end

function Window:draw_error_card(view)
	if view.error == "" then
		return
	end

	local ui = self.ui
	ui.dummy(0.0, ui.scaled(6.0))
	if ui.begin_child_card("##rw_problem", kProblem, kProblemEdge, 8.0) then
		ui.text_wrapped(view.error)
		if self.session:can_retry() and ui.button("Try again", ui.scaled(150.0), 0.0) then
			self.session:retry()
		end
	end
	ui.end_child_card()
end

function Window:draw_sandbox_controls(view)
	if not view.sandbox then
		return
	end

	local ui = self.ui
	ui.dummy(0.0, ui.scaled(6.0))
	ui.text_muted("Test match: it does not count for the ranking")

	if view.guest_link == "" then
		return
	end

	if ui.button("Copy the guest's link", ui.scaled(210.0), 0.0) then
		ui.set_clipboard(view.guest_link)
	end
	if ui.is_item_hovered() then
		ui.set_tooltip("Send it to the other player to open. They join your room by themselves")
	end
end

function Window:draw_abort_confirmation()
	local ui = self.ui
	ui.text_wrapped("Tell Rank Wars this match will not happen?")
	ui.set_next_item_width(-1.0)
	local _, reason = ui.input_text("##rw_reason", "Reason (optional)", self.reason, false)
	self.reason = reason

	ui.push_button_color(kAccent)
	local confirm = ui.button("Cancel the match")
	ui.pop_style_color(1)

	if confirm then
		self.session:abort(self.reason)
		self.confirming = false
	end

	ui.same_line()
	if ui.button("Keep playing") then
		self.confirming = false
	end
end

function Window:draw_abort_controls()
	if not self.session:can_abort() then
		return
	end

	local ui = self.ui
	ui.dummy(0.0, ui.scaled(6.0))
	ui.separator()

	if self.confirming then
		self:draw_abort_confirmation()
		return
	end

	if ui.small_button("Cancel this match") then
		self.confirming = true
	end
end

function Window:draw_hud_toggle()
	local ui = self.ui
	ui.dummy(0.0, ui.scaled(6.0))

	local changed, visible = ui.checkbox("Score in the fight", self.hud:is_visible())
	if changed then
		self.hud:set_visible(visible)
	end
	if ui.is_item_hovered() then
		ui.set_tooltip("Shows a dot for every win under each character's icon: yours in green, the opponent's in red.")
	end
end

function Window:draw_test_match_form()
	if not self.session:can_start_test() then
		return
	end

	local ui = self.ui
	ui.dummy(0.0, ui.scaled(6.0))
	if not ui.collapsing_header("Test match") then
		return
	end

	ui.set_next_item_width(-1.0)
	local _, api = ui.input_text("##rw_api", "API", self.test_api, false)
	self.test_api = api

	ui.set_next_item_width(-1.0)
	local _, pw = ui.input_text("##rw_pw", "Test password", self.test_password, true)
	self.test_password = pw

	ui.set_next_item_width(ui.scaled(150.0))
	local _, ft = ui.slider_int("First to", self.test_first_to, 0, 7, self.test_first_to == 0 and "default" or "%d")
	self.test_first_to = ft

	ui.begin_disabled(self.test_password == "")
	if ui.button("Create a test match", ui.scaled(210.0), 0.0) then
		self.config.set_string("RankWars", "TestApi", self.test_api)
		self.config.set_string("RankWars", "TestPassword", self.test_password)
		self.session:start_test(self.test_api, self.test_password, self.test_first_to)
	end
	ui.end_disabled()
	ui.text_muted("You become the host. It does not touch the ranking or tell Discord")
end

function Window:draw_test_tools()
	if not self.test_tools then
		return
	end

	local ui = self.ui
	local preview = self.hud:is_previewing()
	if ui.button(preview and "Hide the test HUD" or "Show the test HUD", ui.scaled(210.0), 0.0) then
		self.hud:set_previewing(not preview)
	end

	self:draw_test_match_form()
end

function Window:draw()
	self:load_test_settings()
	local view = self.session:view()

	self:draw_header(view)
	self:draw_scoreboard(view)
	self:draw_steps(view)
	self:draw_status(view)
	self:draw_error_card(view)
	self:draw_sandbox_controls(view)
	self:draw_abort_controls()
	self:draw_hud_toggle()
	self:draw_test_tools()
end

return Window
