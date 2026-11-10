-- The Flair setting (D-011, TICK-0055): one setting picks how much flair
-- HUDini's words have, 0 Light (the default), 1 Modest, 2 Full. ns.Text
-- picks a line's text at the level now; a level with no text for a line
-- uses the level below it (Locales/enUS.lua).


-- The %-codes in a text, in order: "%d %s".
local function Codes(s)
	local out = {}
	for code in s:gmatch("%%[%-%d%.]*[%a%%]") do out[#out + 1] = code end
	return table.concat(out, " ")
end

-- Everything printed from one slash command.
local function Said(w, line)
	local from = #w.printed
	w:slash(line)
	local out = {}
	for i = from + 1, #w.printed do out[#out + 1] = w.printed[i] end
	return table.concat(out, "\n")
end

H.test("a new install has flair 0, Light", function()
	local w = H.world()
	local ns = w:loadAddon()
	H.eq(ns.defaults.flair, 0)
	H.eq(w.env.HUDiniDB.flair, 0)
	H.eq(ns.FlairLevel(), 0)
end)

H.test("a saved flair that is not 0, 1 or 2 counts as 0", function()
	local w = H.world()
	local ns = w:loadAddon()
	local db = w.env.HUDiniDB
	for _, c in ipairs({ { 1, 1 }, { 2, 2 }, { 0, 0 }, { 3, 0 }, { -1, 0 }, { 1.5, 0 }, { "1", 0 }, { true, 0 } }) do
		db.flair = c[1]
		H.eq(ns.FlairLevel(), c[2], "flair " .. tostring(c[1]))
	end
	db.flair = nil
	H.eq(ns.FlairLevel(), 0, "no flair saved")
end)

H.test("every level 1 and level 2 line has a level 0 text, with the same %-codes", function()
	local w = H.world()
	local ns = w:loadAddon()
	local T = ns.TEXT
	for level = 1, 2 do
		H.ok(next(T[level]) ~= nil, "level " .. level .. " has lines")
		for key, s in pairs(T[level]) do
			H.ok(T[0][key] ~= nil, ("level %d: %s has a level 0 text"):format(level, key))
			if T[0][key] then
				H.eq(Codes(s), Codes(T[0][key]), ("level %d: %s joins in the same values"):format(level, key))
			end
		end
	end
end)

H.test("every Text(\"key\") with a whole key in the addon's files has a level 0 text", function()
	local w = H.world()
	local ns = w:loadAddon()
	local used = 0
	-- Only files that bind the lookup (local Text = ns.Text, or call
	-- ns.Text directly). Alerts.lua has its own local Text, which is not it.
	for _, rel in ipairs(H.tocFiles()) do
		local src = H.readFile(rel)
		local pattern = src:find("local Text = ns.Text", 1, true)
			and "Text%(\"([^\"]+)\"[,)]" or "ns%.Text%(\"([^\"]+)\"[,)]"
		for key in src:gmatch(pattern) do
			used = used + 1
			H.ok(ns.TEXT[0][key] ~= nil, rel .. ": " .. key)
		end
	end
	H.ok(used >= 16, "the /hud why lines and the Flair lines use the lookup")
end)

H.test("a line missing at level 2 uses level 1, then level 0; a missing key comes back as itself", function()
	local w = H.world()
	local ns = w:loadAddon()
	local T, db = ns.TEXT, w.env.HUDiniDB
	T[0]["test.line"], T[1]["test.line"], T[2]["test.line"] = "zero %d", "one %d", "two %d"
	db.flair = 2
	H.eq(ns.Text("test.line", 5), "two 5", "level 2's own text")
	T[2]["test.line"] = nil
	H.eq(ns.Text("test.line", 5), "one 5", "no level 2 text: level 1")
	T[1]["test.line"] = nil
	H.eq(ns.Text("test.line", 5), "zero 5", "no level 1 text either: level 0")
	db.flair = 1
	H.eq(ns.Text("test.line", 5), "zero 5", "level 1 with no text of its own")
	db.flair = 0
	T[1]["test.line"] = "one %d"
	H.eq(ns.Text("test.line", 5), "zero 5", "level 0 never reads a higher level")
	H.eq(ns.Text("test.nothing"), "test.nothing", "no text at all")
	T[0]["test.pct"] = "100%"
	H.eq(ns.Text("test.pct"), "100%", "no values: the text as it is")
end)

H.test("/hud why prints the level's own line at each level", function()
	local w = H.world()
	local ns = w:loadAddon()
	local T, db = ns.TEXT, w.env.HUDiniDB
	db.locked = false
	local seen = {}
	for level = 0, 2 do
		db.flair = level
		local said = Said(w, "/hud why")
		H.ok(said:find(T[level]["why.unlocked"], 1, true) ~= nil, "level " .. level .. ": " .. said)
		H.eq(said:find("showing: ", 1, true), nil, "no old prefix")
		H.eq(seen[said], nil, "level " .. level .. " reads differently")
		seen[said] = true
	end
end)

H.test("each /hud why line has a level 1 and a level 2 text", function()
	local w = H.world()
	local ns = w:loadAddon()
	local T = ns.TEXT
	for key in pairs(T[0]) do
		if key:find("^why%.") then
			H.ok(T[1][key] and T[1][key] ~= T[0][key], key .. " at level 1")
			H.ok(T[2][key] and T[2][key] ~= T[1][key], key .. " at level 2")
		end
	end
end)

H.test("an unknown command gives the same error at every level", function()
	local w = H.world()
	local ns = w:loadAddon()
	local first
	for level = 0, 2 do
		w.env.HUDiniDB.flair = level
		local said = Said(w, "/hud nosuchcommand")
		H.ok(said ~= "", "an error is printed")
		first = first or said
		H.eq(said, first, "level " .. level)
	end
	H.eq(ns.FlairLevel(), 2)
end)

