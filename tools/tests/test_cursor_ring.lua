-- Cursor ring (TICK-0245, D-052): a see-through picture on the cursor, off
-- at the start, with DK's BetterTools values when turned on. Its opacity
-- has three states: out of a fight, in a fight alone, in a fight in a
-- party or raid.

local function World(saved)
	local w = H.world()
	w.group = false
	w.env.IsInGroup = function() return w.group end
	w.env.IsInRaid = function() return false end
	w.env.HUDiniDB = saved
	w:loadAddon()
	return w, w.ns, w.env.HUDiniDB, w.ns.GetModule("cursorRing")
end

local function On(saved)
	saved = saved or {}
	saved.cursorRing = true
	return World(saved)
end

local MEDIA = "Interface\\AddOns\\HUDini\\Media\\"

H.test("the defaults: off, 250 across, the ring, BetterTools' three opacities", function()
	local _, _, db, M = World()
	H.eq(db.cursorRing, false, "off at the start")
	H.eq(db.cursorRingSize, 250)
	H.eq(db.cursorRingShape, "ring")
	H.eq(db.cursorRingAlpha, 0.04, "out of a fight")
	H.eq(db.cursorRingAlphaCombat, 0.10, "in a fight, alone")
	H.eq(db.cursorRingAlphaGroup, 0.17, "in a fight, in a group")
	H.eq(M.enabled, false, "the module is off")
	H.eq(M.ring, nil, "never on: no frame made")
end)

H.test("the shape-to-picture map: three pictures in Media", function()
	local _, ns = World()
	local files = ns.CURSOR_RING_FILES
	H.eq(files.ring, MEDIA .. "CursorRing")
	H.eq(files.halo, MEDIA .. "CursorHalo")
	H.eq(files.arrows, MEDIA .. "CursorArrows")
	local n = 0
	for _ in pairs(files) do n = n + 1 end
	H.eq(n, 3, "three shapes")
end)

H.test("on: a frame over everything that takes no clicks, the saved shape and size", function()
	local w, ns, db, M = On({ cursorRingShape = "halo", cursorRingSize = 300 })
	local h = M.ring.__h
	H.eq(h.shown, true, "shown")
	H.eq(h.strata, "TOOLTIP", "over everything")
	H.eq(h.mouse, false, "no clicks")
	H.eq(h.parent, w.env.UIParent, "on UIParent")
	H.eq(h.width, 300, "the saved size")
	H.eq(h.height, 300)
	H.eq(M.file, MEDIA .. "CursorHalo", "the saved shape")
	db.cursorRingShape = "arrows"
	ns.RefreshCursorRing()
	H.eq(M.file, MEDIA .. "CursorArrows", "a new shape at once")
	db.cursorRingShape = "square"
	ns.RefreshCursorRing()
	H.eq(M.file, MEDIA .. "CursorRing", "an unknown shape is the ring")
end)

H.test("the size stays between 50 and 600", function()
	local _, ns, db, M = On({ cursorRingSize = 10 })
	H.eq(M.ring.__h.width, 50, "too small: 50")
	db.cursorRingSize = 900
	ns.RefreshCursorRing()
	H.eq(M.ring.__h.width, 600, "too large: 600")
	db.cursorRingSize = "big"
	ns.RefreshCursorRing()
	H.eq(M.ring.__h.width, 250, "not a number: the default")
end)

H.test("the three opacities: out of a fight, alone in a fight, in a group in a fight", function()
	local w, _, _, M = On()
	H.eq(M.ring.__h.alpha, 0.04, "out of a fight")
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(M.ring.__h.alpha, 0.10, "a fight starts, alone")
	w.group = true
	w:fire("GROUP_ROSTER_UPDATE")
	H.eq(M.ring.__h.alpha, 0.17, "a party joined in the fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(M.ring.__h.alpha, 0.04, "the fight ends, in a group: back to out of a fight")
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(M.ring.__h.alpha, 0.17, "a fight in a group")
end)

H.test("turned on in a fight: the fight opacity at once", function()
	local w, ns, db, M = World()
	w.combat = true
	db.cursorRing = true
	ns.RefreshCursorRing()
	H.eq(M.enabled, true, "on")
	H.eq(M.ring.__h.alpha, 0.10, "in a fight, alone")
end)

H.test("a changed opacity shows at once; an opacity stays between 0 and 1", function()
	local _, ns, db, M = On()
	db.cursorRingAlpha = 0.5
	ns.RefreshCursorRing()
	H.eq(M.ring.__h.alpha, 0.5)
	db.cursorRingAlpha = 3
	ns.RefreshCursorRing()
	H.eq(M.ring.__h.alpha, 1, "at most 1")
	db.cursorRingAlpha = -1
	ns.RefreshCursorRing()
	H.eq(M.ring.__h.alpha, 0, "at least 0")
end)

H.test("the ring follows the cursor, in UI units", function()
	local w, _, _, M = On()
	w.env.UIParent.__h.scale = 2
	w.cursor = { 800, 400 }
	w:Run(M.ring, "OnUpdate", 0.016)
	local point, rel, relPoint, x, y = M.ring:GetPoint(1)
	H.eq(point, "CENTER")
	H.eq(rel, w.env.UIParent)
	H.eq(relPoint, "BOTTOMLEFT")
	H.eq(x, 400, "800 screen pixels at scale 2")
	H.eq(y, 200)
end)

H.test("off: hidden, no events, no per-frame work", function()
	local w, ns, db, M = On()
	db.cursorRing = false
	ns.RefreshCursorRing()
	H.eq(M.enabled, false)
	H.eq(M.ring.__h.shown, false, "hidden")
	H.eq(M.ring:GetScript("OnUpdate"), nil, "no OnUpdate")
	H.eq(M.frame:IsEventRegistered("PLAYER_REGEN_DISABLED"), false, "no events")
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(M.ring.__h.shown, false, "a fight does not show it")
	db.cursorRing = true
	ns.RefreshCursorRing()
	H.eq(M.ring.__h.shown, true, "on again")
	H.ok(M.ring:GetScript("OnUpdate") ~= nil, "follows again")
end)

H.test("a cinematic hides the ring until it ends", function()
	local w, _, _, M = On()
	w:fire("CINEMATIC_START")
	H.eq(M.ring.__h.shown, false, "hidden in a cinematic")
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(M.ring.__h.shown, false, "still hidden")
	w:fire("CINEMATIC_STOP")
	H.eq(M.ring.__h.shown, true, "back")
end)

H.test("turned off in a cinematic and on again later: shown", function()
	local w, ns, db, M = On()
	w:fire("CINEMATIC_START")
	db.cursorRing = false
	ns.RefreshCursorRing()
	db.cursorRing = true
	ns.RefreshCursorRing()
	H.eq(M.ring.__h.shown, true, "a new turn-on starts out of a cinematic")
end)
