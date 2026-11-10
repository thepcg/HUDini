-- Styles (TICK-0068): one table, ns.ApplyStyle and ns.MatchStyle. A style
-- sets the same five settings as every other, Standard is the defaults,
-- and picking one writes those five and nothing else.

local function World()
	local w = H.world()
	w:loadAddon()
	return w, w.ns, w.env.HUDiniDB
end

-- Count the HUD's Apply calls from here on.
local function CountApply(ns)
	local hud, n = ns.HUDini, { 0 }
	local real = hud.Apply
	hud.Apply = function(self, ...)
		n[1] = n[1] + 1
		return real(self, ...)
	end
	return n
end

-- Every saved value but the five, one level deep (a table by its keys).
local function Others(ns, db)
	local five, copy = {}, {}
	for _, key in ipairs(ns.STYLE_KEYS) do five[key] = true end
	for k, v in pairs(db) do
		if not five[k] then
			if type(v) == "table" then
				local t = {}
				for k2, v2 in pairs(v) do t[k2] = v2 end
				copy[k] = t
			else
				copy[k] = v
			end
		end
	end
	return copy
end

local function SameOthers(a, b, label)
	for k, v in pairs(a) do
		if type(v) == "table" then
			for k2, v2 in pairs(v) do H.eq(b[k][k2], v2, label .. ": " .. k .. "." .. tostring(k2)) end
		else
			H.eq(b[k], v, label .. ": " .. k)
		end
	end
	for k in pairs(b) do H.ok(a[k] ~= nil, label .. ": no new key " .. k) end
end

H.test("three styles, each with the same five settings and no other", function()
	local _, ns = World()
	H.eq(#ns.STYLE_ORDER, 3, "three styles")
	H.eq(#ns.STYLE_KEYS, 5, "five settings")
	for _, name in ipairs(ns.STYLE_ORDER) do
		local style, n = ns.styles[name], 0
		H.ok(style ~= nil, name .. " is in the table")
		for _, key in ipairs(ns.STYLE_KEYS) do
			H.eq(type(style[key]), "boolean", name .. "." .. key)
		end
		for _ in pairs(style) do n = n + 1 end
		H.eq(n, 5, name .. ": no sixth setting")
	end
	local n = 0
	for _ in pairs(ns.styles) do n = n + 1 end
	H.eq(n, 3, "no fourth style in the table")
end)

H.test("Standard is the defaults, and each setting differs in some style", function()
	local _, ns = World()
	for _, key in ipairs(ns.STYLE_KEYS) do
		H.eq(ns.styles.standard[key], ns.defaults[key], "standard." .. key)
		local seen = {}
		for _, name in ipairs(ns.STYLE_ORDER) do seen[tostring(ns.styles[name][key])] = true end
		H.ok(seen["true"] and seen["false"], key .. " differs between the styles")
	end
end)

H.test("a new install matches Standard", function()
	local _, ns = World()
	H.eq(ns.MatchStyle(), "standard")
end)

H.test("apply then match gives each style, with one Apply", function()
	local _, ns, db = World()
	local n = CountApply(ns)
	for _, name in ipairs({ "minimal", "leveling", "standard", "leveling", "minimal" }) do
		local before = n[1]
		H.eq(ns.ApplyStyle(name), true, name .. " applies")
		H.eq(n[1] - before, 1, name .. ": one Apply")
		H.eq(ns.MatchStyle(), name, name .. " matches")
		for _, key in ipairs(ns.STYLE_KEYS) do
			H.eq(db[key], ns.styles[name][key], name .. ": " .. key .. " saved")
		end
	end
end)

H.test("one changed setting matches no style", function()
	local _, ns, db = World()
	for _, name in ipairs(ns.STYLE_ORDER) do
		for _, key in ipairs(ns.STYLE_KEYS) do
			ns.ApplyStyle(name)
			db[key] = not db[key]
			H.eq(ns.MatchStyle(), nil, name .. " with " .. key .. " changed")
		end
	end
end)

H.test("a style changes nothing but its five settings", function()
	local _, ns, db = World()
	-- Not the defaults, so a style that reset them would show.
	db.point, db.x, db.y, db.locked, db.scale = "TOP", 40, -120, false, 1.4
	db.hideWhenIdle, db.showTargetHealth, db.showTargetCast, db.iconSize = false, false, false, 52
	ns.ClassDB().point, ns.ClassDB().x = "LEFT", 7
	for _, name in ipairs(ns.STYLE_ORDER) do
		local before = Others(ns, db)
		local class = { point = ns.ClassDB().point, x = ns.ClassDB().x }
		ns.ApplyStyle(name)
		SameOthers(before, Others(ns, db), name)
		H.eq(ns.ClassDB().point, class.point, name .. ": the class's position")
		H.eq(ns.ClassDB().x, class.x, name .. ": the class's x")
	end
end)

H.test("Custom, or a name that is not a style, changes nothing", function()
	local _, ns, db = World()
	ns.ApplyStyle("leveling")
	db.feedUpgrade = false
	local n = CountApply(ns)
	for _, name in ipairs({ "custom", "Minimal", "", 1 }) do
		H.eq(ns.ApplyStyle(name), false, tostring(name) .. " does not apply")
	end
	H.eq(ns.ApplyStyle(nil), false, "nil does not apply")
	H.eq(n[1], 0, "no Apply")
	H.eq(db.showXP, true, "showXP kept"); H.eq(db.feedQuestProgress, true, "feedQuestProgress kept")
	H.eq(db.feedUpgrade, false, "feedUpgrade kept")
end)

H.test("Minimal turns the feed and the XP bar off, and Standard back on", function()
	local _, ns = World()
	ns.ApplyStyle("minimal")
	H.eq(ns.GetModule("feed").enabled, false, "the feed is off")
	H.eq(ns.GetModule("xp").enabled, false, "the XP bar is off")
	ns.ApplyStyle("standard")
	H.eq(ns.GetModule("feed").enabled, true, "the feed is on")
	H.eq(ns.GetModule("xp").enabled, true, "the XP bar is on")
end)
