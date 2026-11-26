local class = require("src.core.class")

local Hud = class()

local kScreenWidth = 1280
local kIconCentreX = 74
local kRowCentreY = 114
local kStep = 14
local kRadius = 5
local kRingWidth = 1
local kRingLayer = 286
local kFillLayer = 287

local kRing = 0xE6FFFFFF
local kOpen = 0x99000000
local kOwnWin = 0xFF34D15C
local kRivalWin = 0xFFDC1A33

local kPreviewBoard = {
	local_side = 0,
	is_host = true,
	host_wins = 3,
	guest_wins = 1,
	first_to = 5,
}

local function pip_centre_x(side, pip, needed)
	local left = side == 0
	local direction = left and 1 or -1
	local centre = left and kIconCentreX or (kScreenWidth - kIconCentreX)
	local first = centre - math.floor(direction * (kStep * (needed - 1)) / 2)
	return first + direction * kStep * pip
end

function Hud:init(deps)
	self.game = deps.game
	self.draw_api = deps.draw
	self.config = deps.config
	self.visible = true
	self.preview = false
	self.loaded = false
	self.live_board = {
		local_side = 0,
		is_host = true,
		host_wins = 0,
		guest_wins = 0,
		first_to = 0,
	}
end

function Hud:ensure_loaded()
	if self.loaded then
		return
	end
	self.loaded = true
	self.visible = self.config.get_int("RankWars", "ShowHud", 1) ~= 0
end

function Hud:fill_disc(cx, cy, radius, colour, layer)
	local arm = math.floor(radius * 41 / 100)
	local core = math.floor(radius * 70 / 100)

	self.draw_api.fill(cx - radius, cy - arm, radius * 2 + 1, arm * 2 + 1, colour, layer)
	self.draw_api.fill(cx - arm, cy - radius, arm * 2 + 1, radius * 2 + 1, colour, layer)
	self.draw_api.fill(cx - core, cy - core, core * 2 + 1, core * 2 + 1, colour, layer)
end

function Hud:paint_side(side, wins, needed, own)
	local won = own and kOwnWin or kRivalWin

	for pip = 0, needed - 1 do
		local x = pip_centre_x(side, pip, needed)
		self:fill_disc(x, kRowCentreY, kRadius + kRingWidth, kRing, kRingLayer)
		self:fill_disc(x, kRowCentreY, kRadius, pip < wins and won or kOpen, kFillLayer)
	end
end

function Hud:resolve_board(scoreboard_fn)
	if self.preview then
		return kPreviewBoard
	end

	if not self.visible or not self.game.is_online() or self.game.is_spectating() then
		return nil
	end

	local board = scoreboard_fn()
	if not board or board.first_to <= 0 then
		return nil
	end

	local local_side = self.game.local_side()
	if local_side ~= 0 and local_side ~= 1 then
		return nil
	end

	local live = self.live_board
	live.local_side = local_side
	live.is_host = board.is_host
	live.host_wins = board.score.host
	live.guest_wins = board.score.guest
	live.first_to = board.first_to
	return live
end

function Hud:is_visible()
	self:ensure_loaded()
	return self.visible
end

function Hud:set_visible(visible)
	self:ensure_loaded()
	self.visible = visible
	self.config.set_int("RankWars", "ShowHud", visible and 1 or 0)
end

function Hud:is_previewing()
	return self.preview
end

function Hud:set_previewing(preview)
	self.preview = preview
end

function Hud:draw(scoreboard_fn)
	self:ensure_loaded()

	if not self.game.in_match() then
		return
	end

	local board = self:resolve_board(scoreboard_fn)
	if not board then
		return
	end

	for side = 0, 1 do
		local host_side = (side == board.local_side) == board.is_host
		local wins = host_side and board.host_wins or board.guest_wins
		self:paint_side(side, wins, board.first_to, side == board.local_side)
	end
end

return Hud
