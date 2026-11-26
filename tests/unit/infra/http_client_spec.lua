local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")
local Protocol = require("src.domain.protocol")
local HttpClient = require("src.infra.http_client")

local function create_client(env, token, steam_id)
	return HttpClient.new("https://rw.gg", token, steam_id, {
		http = env.api.http,
		time = env.api.time,
		log = env.api.log,
		protocol = Protocol.new(env.api.http),
	})
end

t.suite("infra/http_client", function()
	t.test("sends requests sequentially with expected headers", function()
		local env = FakeEnv.new()
		local client = create_client(env, "SECRET", "76561198000000001")
		local results = {}

		client:fetch_match(function(ans)
			results[#results + 1] = ans
		end)
		client:put_room("555", "76561198000000001", function(ans)
			results[#results + 1] = ans
		end)

		t.assert_eq(client:pending(), 2)
		client:tick()
		t.assert_eq(#env.http_queue, 1)

		local req1 = env:respond_next_http(200, "{}")
		t.assert_eq(req1.method, "GET")
		t.assert_eq(req1.url, "https://rw.gg/api/im/v1/match")
		t.assert_eq(req1.headers["Authorization"], "Bearer SECRET")
		t.assert_eq(req1.headers["X-Steam-Id"], "76561198000000001")

		client:tick()
		local req2 = env:respond_next_http(200, "{}")
		t.assert_eq(req2.method, "PUT")
		t.assert_eq(req2.headers["Content-Type"], "application/json")
		t.assert_eq(#results, 2)
		t.assert_eq(client:pending(), 0)
	end)

	t.test("retries transient failures with backoff and succeeds on later attempt", function()
		local env = FakeEnv.new()
		local client = create_client(env, "TOK", "0")
		local answer = nil

		client:fetch_match(function(ans)
			answer = ans
		end)

		client:tick()
		env:respond_next_http(503, "")
		t.assert_nil(answer)
		t.assert_eq(client:pending(), 1)

		env:advance(1999)
		client:tick()
		t.assert_eq(#env.http_queue, 0)

		env:advance(1)
		client:tick()
		t.assert_eq(#env.http_queue, 1)

		env:respond_next_http(200, "OK")
		t.assert_not_nil(answer)
		t.assert_true(answer.ok)
		t.assert_eq(client:pending(), 0)
	end)

	t.test("does not retry 4xx errors or non-retriable sandbox requests", function()
		local env = FakeEnv.new()
		local client = create_client(env, "", "0")
		local answers = {}

		client:fetch_match(function(ans)
			answers[#answers + 1] = ans
		end)
		client:create_sandbox("pw", 3, function(ans)
			answers[#answers + 1] = ans
		end)

		client:tick()
		env:respond_next_http(404, "")
		t.assert_eq(#answers, 1)
		t.assert_false(answers[1].ok)

		client:tick()
		env:respond_next_http(500, "")
		t.assert_eq(#answers, 2)
		t.assert_false(answers[2].ok)
		t.assert_eq(client:pending(), 0)
	end)

	t.test("stops retrying after exhausting retry schedule", function()
		local env = FakeEnv.new()
		local client = create_client(env, "TOK", "0")
		local final_answer = nil

		client:fetch_match(function(ans)
			final_answer = ans
		end)

		local delays = { 2000, 5000, 10000, 20000, 30000, 60000 }
		client:tick()
		env:respond_next_http(0, "", "timeout", false)

		for _, delay in ipairs(delays) do
			t.assert_nil(final_answer)
			env:advance(delay)
			client:tick()
			env:respond_next_http(0, "", "timeout", false)
		end

		t.assert_not_nil(final_answer)
		t.assert_false(final_answer.ok)
		t.assert_eq(final_answer.error, "timeout")
	end)
end)
