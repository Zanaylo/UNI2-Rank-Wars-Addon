local t = require("tests.support.runner")
local FakeEnv = require("tests.support.fake_env")
local manifest = require("src.domain.manifest")

t.suite("domain/manifest", function()
	t.test("parse_version extracts and normalizes version from addon.ini text", function()
		t.assert_eq(manifest.parse_version("[Addon]\nVersion = 1.0.0\n"), "1.0.0")
		t.assert_eq(manifest.parse_version("Version=v2.3.4\r\n"), "2.3.4")
		t.assert_eq(manifest.parse_version("[Addon]\nName = Rank Wars\n"), "")
		t.assert_eq(manifest.parse_version(nil), "")
	end)

	t.test("read_version loads Version from addon_dir/addon.ini", function()
		local env = FakeEnv.new()
		env.fs_store[".\\addon.ini"] = "[Addon]\nId = rank-wars\nVersion = 1.2.3\n"
		t.assert_eq(manifest.read_version(env.api.fs), "1.2.3")
	end)
end)
