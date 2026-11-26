package.path = "./?.lua;./?/init.lua;" .. package.path

local runner = require("tests.support.runner")

local specs = {
	"tests.unit.core.class_spec",
	"tests.unit.core.cooldown_spec",
	"tests.unit.core.state_machine_spec",
	"tests.unit.domain.launch_link_spec",
	"tests.unit.domain.protocol_spec",
	"tests.unit.domain.score_tracker_spec",
	"tests.unit.infra.http_client_spec",
	"tests.unit.infra.launch_watcher_spec",
	"tests.unit.infra.presence_spec",
	"tests.unit.infra.room_flow_spec",
	"tests.unit.app.replay_viewer_spec",
	"tests.unit.app.session_spec",
	"tests.unit.presentation.hud_spec",
	"tests.unit.presentation.window_spec",
	"tests.integration.bootstrap_spec",
}

for _, spec in ipairs(specs) do
	require(spec)
end

local code = runner.run()
if code ~= 0 then
	os.exit(code)
end
