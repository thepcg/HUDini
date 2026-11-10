-- The target's block matches yours (TICK-0126, D-027): its health as tall
-- as yours on top, its power as tall as yours under it, and its cast on
-- that power bar, as yours is on yours. No row of its own for the cast, so
-- nothing empty sits above the target's health.

local function World(setup)
	local w = H.world()
	w.hasTarget = true
	if setup then setup(w.env.HUDiniDB or {}) end
	w:loadAddon()
	if setup then setup(w.env.HUDiniDB) end
	w.ns.HUDini:Layout()
	return w, w.ns, w.env.HUDiniDB
end

-- A row's bottom edge and height, as LayoutBars placed it.
local function Row(ns, key)
	local bar = ns.GetBar(key)
	if bar:GetNumPoints() == 0 then return nil end
	local point, to, toPoint, _, y = bar:GetPoint(1)
	H.eq(point, "BOTTOMLEFT", key .. ": hung by its bottom left")
	H.eq(to, ns.HUDini, key .. ": on the HUD")
	H.eq(toPoint, "TOPLEFT", key .. ": from the HUD's top left")
	return y, bar:GetHeight()
end

H.test("the stack from the bottom: power, health, target power, target health", function()
	local _, ns, db = World(function(db) db.healthHeight, db.barHeight = 30, 12 end)
	local gap = db.barGap
	local py, ph = Row(ns, "power")
	local hy, hh = Row(ns, "health")
	local tpy, tph = Row(ns, "targetpower")
	local thy, thh = Row(ns, "targethealth")
	H.eq(hh, 30, "your health: healthHeight")
	H.eq(thh, 30, "the target's health: as tall as yours")
	H.eq(ph, 12, "your power: barHeight")
	H.eq(tph, 12, "the target's power: as tall as yours")
	H.eq(hy, py + ph + gap, "your health right above your power")
	H.eq(tpy, hy + hh + gap, "the target's power right above your health")
	H.eq(thy, tpy + tph + gap, "the target's health right above its power")
	-- The aura rows hang off the box's top (TargetDebuffs.lua), so that
	-- top is the target's health top: no empty row between them.
	local _, _, _, _, top = ns.HUDini.mover:GetPoint(1)
	H.eq(top, thy + thh, "the box ends at the target's health top")
	H.eq(ns.GetBar("targetpower"):IsShown(), true, "the target's power shows")
	H.eq(ns.GetBar("targethealth").power, nil, "no power left inside the target's health")
end)

H.test("the target's cast rides on its power bar, see-through, words above", function()
	local _, ns, db = World()
	local bar, set = ns.GetBar("targetpower"), ns.casts.targetcast
	-- In the game a child stands above its parent; the fake has no such
	-- rule, so give the cast's parts high levels and lay out again.
	set.base:SetFrameLevel(10)
	set.hot:SetFrameLevel(11)
	ns.HUDini:Layout()
	local _, to = set.holder:GetPoint(1)
	H.eq(set.holder:GetNumPoints(), 1, "one anchor")
	H.eq(to, bar, "the cast covers the target's power bar")
	H.ok(set.holder:GetFrameLevel() > bar:GetFrameLevel(), "the cast is over the fill")
	H.eq(set.holder:GetAlpha(), db.castAlpha, "see-through, as yours")
	H.ok(bar.textLayer:GetFrameLevel() > set.hot:GetFrameLevel(), "the words are over the cast")
	H.ok(bar.textLayer:GetFrameLevel() > set.base:GetFrameLevel(), "and over its backdrop")
end)

-- Target power off, its cast on: the slot stays, so the cast has a place
-- and the interrupt outline a bar. The power fill stays hidden.
H.test("Target power off, Target cast bar on: the slot stays for the cast", function()
	local _, ns, db = World(function(db) db.showTargetPower = false end)
	local hy, hh = Row(ns, "health")
	local tpy, tph = Row(ns, "targetpower")
	local thy = Row(ns, "targethealth")
	H.eq(tph, db.barHeight, "the slot keeps its height")
	H.eq(tpy, hy + hh + db.barGap, "the slot is where the power would be")
	H.eq(thy, tpy + tph + db.barGap, "the target's health stays above it")
	H.eq(ns.GetBar("targetpower"):IsShown(), false, "no power fill")
	local _, to = ns.casts.targetcast.holder:GetPoint(1)
	H.eq(to, ns.GetBar("targetpower"), "the cast still has the slot")
end)

H.test("Target power and Target cast bar off: no slot, the target's health sits on yours", function()
	local _, ns, db = World(function(db) db.showTargetPower, db.showTargetCast = false, false end)
	local hy, hh = Row(ns, "health")
	local thy = Row(ns, "targethealth")
	H.eq(thy, hy + hh + db.barGap, "no empty row between the two health bars")
	H.eq(ns.casts.targetcast.holder:GetNumPoints(), 0, "the cast has no place")
	H.eq(ns.casts.targetcast.holder:IsShown(), false, "and does not show")
end)

H.test("the interrupt outline keeps its full strength over the see-through cast", function()
	local w, ns = World()
	local holder = ns.casts.targetcast.holder
	ns.OnTargetCast(false, false)
	local outline
	for _, f in ipairs(w.frames) do
		if f.edges and f:GetParent() == holder then outline = f end
	end
	H.ok(outline, "the outline is on the target's cast")
	H.eq(outline:IsIgnoringParentAlpha(), true, "it ignores the cast's alpha")
end)

-- The fake's IsVisible does not look at parents, so walk them here: a
-- shown text under a hidden frame does not draw in the game.
local function Drawn(f)
	while f do
		if not f:IsShown() then return false end
		f = f:GetParent()
	end
	return true
end

-- Review finding 1: with Target power off the power bar is hidden, but its
-- slot keeps the target's cast, so the cast's words must not hang off it.
H.test("Target power off: the target's cast still shows its name and time", function()
	local w, ns = World(function(db) db.showTargetPower = false end)
	local bar = ns.GetBar("targetpower")
	H.eq(bar:IsShown(), false, "no power fill")
	w.env.UnitCastingInfo = function(unit) if unit == "target" then return "Shadow Bolt" end end
	w.env.UnitCastingDuration = function(unit) if unit == "target" then return {} end end
	local tc = ns.casts.targetcast
	tc.base.SetTimerDuration = function() end
	tc.hot.SetTimerDuration = tc.base.SetTimerDuration
	w:fire("UNIT_SPELLCAST_START", "target")
	H.eq(Drawn(tc.holder), true, "the cast draws")
	H.eq(bar.castName:GetText(), "Shadow Bolt", "the name is set")
	H.eq(Drawn(bar.castName), true, "the name draws")
	H.eq(Drawn(bar.castTime), true, "the time draws")
	H.eq(Drawn(bar.numbers) and bar.numbers:GetText() ~= "", false, "no power number")
end)

H.test("Target power off, /hud test: the sample cast's name draws", function()
	local w, ns = World(function(db) db.showTargetPower = false end)
	ns.FeedTest = function() end -- the feed's sample needs item calls the fake lacks
	w.hasTarget = false -- the sample target shows only with no real one
	w:fire("PLAYER_TARGET_CHANGED")
	w:slash("/hud test")
	local bar = ns.GetBar("targetpower")
	H.eq(bar.castName:GetText(), "Sample cast", "the sample name")
	H.eq(Drawn(bar.castName), true, "it draws")
end)

-- TICK-0132: the power number's text layer hangs off the HUD, not the bar,
-- so hiding the bar does not hide the number. With no target, the cast's
-- hide draws no number, even with a stale powerShown.

-- The game's percent: 100 for the target, 0 for no unit, as in the game.
local function Percents(w)
	w.env.CurveConstants = { ScaleTo100 = {} }
	w.env.UnitPowerPercent = function() return w.hasTarget and 100 or 0 end
	w.env.UnitHealthPercent = w.env.UnitPowerPercent
end
H.test("the target goes away: no power number stays", function()
	local w, ns = World(function(db) db.barNumbers = "percent" end)
	Percents(w)
	w:fire("PLAYER_TARGET_CHANGED")
	local bar = ns.GetBar("targetpower")
	H.eq(bar.powerShown, true, "a target with mana: the bar has a fill")
	H.ok(bar.numbers:GetText() ~= "", "and a number")
	w.hasTarget = false
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(bar.numbers:GetText(), "", "no target: no number")
	H.eq(bar.powerShown, false, "and no fill")
	ns.UpdateCastBars()
	H.eq(bar.numbers:GetText(), "", "the target's cast hides again: still no number")
end)

H.test("no target and a stale fill flag: the cast's hide draws no number", function()
	local w, ns = World(function(db) db.barNumbers = "percent" end)
	Percents(w)
	local bar = ns.GetBar("targetpower")
	w.hasTarget = false
	w:fire("PLAYER_TARGET_CHANGED")
	bar.powerShown = true
	ns.UpdateCastBars()
	H.eq(bar.numbers:GetText(), "", "no unit: no number")
end)
