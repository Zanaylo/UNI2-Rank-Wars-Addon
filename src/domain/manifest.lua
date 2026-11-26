local M = {}

function M.parse_version(text)
	if not text or text == "" then
		return ""
	end
	for line in text:gmatch("[^\r\n]+") do
		local version = line:match("^%s*[Vv][Ee][Rr][Ss][Ii][Oo][Nn]%s*=%s*(.-)%s*$")
		if version and version ~= "" then
			return (version:gsub("^[vV]", ""))
		end
	end
	return ""
end

function M.read_version(fs)
	if not fs then
		return ""
	end
	local dir = fs.addon_dir()
	if not dir or dir == "" then
		return ""
	end
	local last = dir:sub(-1)
	local path = (last == "\\" or last == "/") and (dir .. "addon.ini") or (dir .. "\\addon.ini")
	return M.parse_version(fs.read(path))
end

return M
