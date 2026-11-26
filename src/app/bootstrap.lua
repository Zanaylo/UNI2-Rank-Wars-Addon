local launch_link = require("src.domain.launch_link")
local manifest = require("src.domain.manifest")
local Protocol = require("src.domain.protocol")
local ScoreTracker = require("src.domain.score_tracker")
local HttpClient = require("src.infra.http_client")
local LaunchWatcher = require("src.infra.launch_watcher")
local Presence = require("src.infra.presence")
local RoomCreator = require("src.infra.room_creator")
local RoomFlow = require("src.infra.room_flow")
local ReplayViewer = require("src.app.replay_viewer")
local Session = require("src.app.session")
local Hud = require("src.presentation.hud")
local Window = require("src.presentation.window")

local M = {}

local kWindowOptions = {
	summary = "Automated ranked matches, live score pips HUD and replay uploads.",
	width = 440,
	height = 400,
	min_width = 380,
	min_height = 280,
	max_width = 560,
	max_height = 680,
	open = false,
}

function M.build(env)
	local protocol = Protocol.new(env.http)
	local client_deps = {
		http = env.http,
		time = env.time,
		log = env.log,
		protocol = protocol,
	}

	local function client_factory(api_url, token, steam_id)
		return HttpClient.new(api_url, token, steam_id, client_deps)
	end

	local room_creator = RoomCreator.new({
		game = env.game,
		mem = env.mem,
		offsets = env.offsets,
		time = env.time,
		log = env.log,
		warn = env.warn,
	})

	local room_flow = RoomFlow.new({
		game = env.game,
		steam = env.steam,
		mem = env.mem,
		offsets = env.offsets,
		time = env.time,
		log = env.log,
		warn = env.warn,
		room_creator = room_creator,
	})

	local replay_viewer = ReplayViewer.new({
		game = env.game,
		replay = env.replay,
		fs = env.fs,
		offsets = env.offsets,
		toast = env.toast,
		log = env.log,
		client_factory = client_factory,
		room_flow = room_flow,
	})

	local launch_watcher = LaunchWatcher.new({
		steam = env.steam,
		config = env.config,
		time = env.time,
		launch_link = launch_link,
	})

	local presence = Presence.new(env.steam)
	local tracker = ScoreTracker.new(env.time)

	local session = Session.new({
		game = env.game,
		steam = env.steam,
		mem = env.mem,
		offsets = env.offsets,
		replay = env.replay,
		fs = env.fs,
		ui = env.ui,
		time = env.time,
		log = env.log,
		warn = env.warn,
		toast = env.toast,
		launch_link = launch_link,
		protocol = protocol,
		client_factory = client_factory,
		replay_viewer = replay_viewer,
		room_flow = room_flow,
		presence = presence,
		score_tracker = tracker,
		launch_watcher = launch_watcher,
	})

	local hud = Hud.new({
		game = env.game,
		draw = env.draw,
		config = env.config,
	})

	local window = Window.new(session, hud, {
		ui = env.ui,
		config = env.config,
		clock = env.clock,
		version = manifest.read_version(env.fs),
	})

	return {
		protocol = protocol,
		client_factory = client_factory,
		room_creator = room_creator,
		room_flow = room_flow,
		replay_viewer = replay_viewer,
		launch_watcher = launch_watcher,
		presence = presence,
		tracker = tracker,
		session = session,
		hud = hud,
		window = window,
	}
end

function M.start(env)
	local app = M.build(env)

	local function scoreboard()
		return app.session:scoreboard()
	end

	env.ui.register_window("rank_wars", "Rank Wars", kWindowOptions, function()
		app.window:draw()
	end)

	app.session:initialize()

	env.on("frame", function()
		app.session:on_frame()
	end)

	env.on("hud", function()
		app.hud:draw(scoreboard)
	end)

	env.on("game_started", function()
		app.session:on_game_started()
	end)

	env.on("game_ended", function(report)
		app.session:on_game_ended(report)
	end)

	env.on("network_menu_opened", function(mode)
		app.room_creator:on_network_menu_opened(mode)
	end)

	env.on("player_match_result", function(root_addr, result)
		app.room_creator:on_player_match_result(root_addr, result)
	end)

	env.log("Rank Wars Lua add-on initialized")
	return app
end

return M
