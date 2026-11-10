-- The hot path (TICK-0010): a health or power tick runs no alert scan, the
-- HUD poll draws nothing while the HUD is hidden and stops when nothing can
-- bring it back, the mouseover ticker runs only while a group fades, and a
-- slider drag gathers its steps into one Apply.

local function Live(w)
	local n = 0
	for _, t in ipairs(w.tickers) do
		if not t.cancelled then n = n + 1 end
	end
	return n
end

-- A world logged in, with every setting change callback kept by name.
local function HotWorld()
	local w = H.world()
	w.changed = {}
	w.env.Settings.SetOnValueChangedCallback = function(variable, fn)
		w.changed[variable] = fn
	end
	w:loadAddon()
	return w, w.ns, w.ns.HUDini
end

-- Count each call to ns[name] (or HUDini[name] with on), then pass it on.
local function Count(tbl, name)
	local real, box = tbl[name], { n = 0 }
	tbl[name] = function(...)
		box.n = box.n + 1
		if real then return real(...) end
	end
	return box
end

-- One spell on the grid, so hide when idle has something to hide; full
-- mana, and no fade, so nothing needs you and the HUD hides at once. The
-- drawing calls are counted, not run: the fake spell has no button.
local function Grid(w, hud)
	hud.spells = { {} }
	w.env.UnitPower = function() return 100 end
	w.env.HUDiniDB.fadeOutTime = 0
	hud.body.fadeLeft = nil -- a fade the login began
	return {
		bars   = Count(w.ns, "UpdateBars"),
		casts  = Count(w.ns, "UpdateCastBars"),
		assist = Count(hud, "UpdateAssist"),
		usable = Count(hud, "UpdateUsable"),
	}
end

H.test("a power or health tick runs no alert scan", function()
	local w, ns = HotWorld()
	local scans = Count(ns, "UpdateAlerts")
	w:fire("UNIT_POWER_FREQUENT", "player")
	w:fire("UNIT_POWER_UPDATE", "player")
	w:fire("UNIT_HEALTH", "player")
	ns.UpdateBars()
	H.eq(scans.n, 0, "alert scans on power and health ticks")
	w:fire("UNIT_AURA", "player")
	H.ok(scans.n > 0, "an aura change still updates the alerts")
end)

H.test("the HUD poll draws nothing while the HUD is hidden", function()
	local w, _, hud = HotWorld()
	local c = Grid(w, hud)
	hud:UpdateVisibility()
	H.eq(hud.body:IsShown(), false, "the HUD is hidden when nothing needs you")
	local checks = Count(hud, "UpdateVisibility")
	w:runTickers()
	H.ok(checks.n > 0, "the show check still runs while hidden")
	H.eq(c.bars.n + c.casts.n, 0, "bar fills while hidden")
	H.eq(c.assist.n + c.usable.n, 0, "grid polls while hidden")
end)

H.test("the HUD poll draws while the HUD is shown", function()
	local w, _, hud = HotWorld()
	local c = Grid(w, hud)
	w.combat = true
	hud:UpdateVisibility()
	H.eq(hud.body:IsShown(), true, "the HUD shows in a fight")
	w:runTickers()
	H.ok(c.bars.n > 0 and c.casts.n > 0, "the bars fill while shown")
	H.ok(c.assist.n > 0 and c.usable.n > 0, "the grid polls while shown")
	w.combat = false
end)

H.test("a target bar keeps the bars filling while the grid is hidden", function()
	local w, _, hud = HotWorld()
	local c = Grid(w, hud)
	w.hasTarget = true
	hud:UpdateVisibility()
	H.eq(hud.body:IsShown(), false, "a friendly target does not show the grid")
	w:runTickers()
	H.ok(c.bars.n > 0, "the target bar fills")
	H.eq(c.assist.n, 0, "no grid poll with the grid hidden")
end)

H.test("the HUD poll stops with nothing to show and nothing to wake it", function()
	local w, _, hud = HotWorld()
	Grid(w, hud)
	hud:UpdateVisibility()
	local idle = Live(w)
	hud.spells = {}
	hud:UpdateVisibility()
	H.eq(Live(w), idle - 1, "the poll stops with no spells and no target")
	w.hasTarget = true
	hud:UpdateVisibility()
	H.eq(Live(w), idle, "a target starts it again")
	w.hasTarget = false
	hud.spells = { {} }
	hud:UpdateVisibility()
	H.eq(Live(w), idle, "hide when idle keeps it running")
	w.env.HUDiniDB.hideWhenIdle = false
	hud.body:Hide()
	hud.spells = {}
	hud:UpdateVisibility()
	H.eq(Live(w), idle - 1, "with hide when idle off it stops too")
end)

H.test("the mouseover ticker runs only while a group fades", function()
	local w, _, hud = HotWorld()
	local db = w.env.HUDiniDB
	hud:Apply()
	local off = Live(w)
	db.bagBarMouseover = true
	hud:Apply()
	H.eq(Live(w), off + 1, "a fade setting starts it")
	db.minimapMouseover = true
	hud:Apply()
	H.eq(Live(w), off + 1, "a second one does not start another")
	db.bagBarMouseover, db.minimapMouseover = false, false
	hud:Apply()
	H.eq(Live(w), off, "it stops when every fade is off")
end)

H.test("the mouseover ticker starts at login when a fade is on", function()
	local w = H.world()
	w:load(unpack(H.tocFiles()))
	w:fire("ADDON_LOADED", "HUDini")
	local before = Live(w)
	w.env.HUDiniDB.menuBarMouseover = true
	w:fire("PLAYER_LOGIN")
	w:fire("PLAYER_ENTERING_WORLD", true, false)
	local on = Live(w)

	local w2 = H.world()
	w2:load(unpack(H.tocFiles()))
	w2:fire("ADDON_LOADED", "HUDini")
	H.eq(Live(w2), before, "the same start")
	w2:fire("PLAYER_LOGIN")
	w2:fire("PLAYER_ENTERING_WORLD", true, false)
	H.eq(on, Live(w2) + 1, "one more ticker with a fade on")
end)

H.test("a slider drag runs Apply once, on the next frame", function()
	local w, _, hud = HotWorld()
	local applies = Count(hud, "Apply")
	local changed = w.changed.HUDini_scale or w.changed.HUDini_barHeight
	H.ok(changed ~= nil, "a slider setting has a change callback")
	for _ = 1, 5 do changed() end
	H.eq(applies.n, 0, "no Apply during the drag")
	w:runTimers()
	H.eq(applies.n, 1, "one Apply after it")
	changed()
	w:runTimers()
	H.eq(applies.n, 2, "the next change applies again")
end)

H.test("a /reload in a fight with a target starts the HUD poll", function()
	local w = H.world()
	w.hasTarget = true
	w:load(unpack(H.tocFiles()))
	w:fire("ADDON_LOADED", "HUDini")
	w:fire("PLAYER_LOGIN")
	-- The lockdown from PLAYER_ENTERING_WORLD on: the secure click buttons
	-- are made at load, which the harness would block in a fight.
	w.combat = true
	local fills = Count(w.ns, "UpdateBars")
	w:fire("PLAYER_ENTERING_WORLD", false, true)
	fills.n = 0
	w:runTickers()
	H.ok(fills.n > 0, "the target bar fills in the fight")
	w.combat = false
end)

H.test("an alert setting changed in a fight takes effect at once", function()
	local w, ns, hud = HotWorld()
	w.combat = true
	local scans = Count(ns, "UpdateAlerts")
	hud:Apply()
	H.ok(scans.n > 0, "Apply in a fight updates the alerts")
	w.combat = false
end)

-- TICK-0065: the alerts follow events (test_alert_events.lua), so the poll
-- runs no alert scan, shown or hidden.
H.test("the HUD poll runs no alert scan", function()
	local w, ns, hud = HotWorld()
	Grid(w, hud)
	hud:UpdateVisibility()
	local scans = Count(ns, "UpdateAlerts")
	w:runTickers()
	H.eq(scans.n, 0, "no alert scan with the HUD hidden")
	w.combat = true
	hud:UpdateVisibility()
	H.eq(hud.body:IsShown(), true, "shown in a fight")
	w.time = w.time + 1
	w:runTickers()
	H.eq(scans.n, 0, "no alert scan with the HUD shown")
	w.combat = false
end)

H.test("unlocking a hidden HUD keeps the poll running", function()
	local w, _, hud = HotWorld()
	local c = Grid(w, hud)
	hud:UpdateVisibility()
	H.eq(hud.body:IsShown(), false, "hidden first")
	w.env.HUDiniDB.locked = false
	hud:UpdateVisibility()
	H.eq(hud.body:IsShown(), true, "unlocked, it shows")
	w:runTickers()
	H.ok(c.assist.n > 0 and c.bars.n > 0, "the grid and the bars are polled")
end)

H.test("only the target cast bar on: it is polled while the grid is hidden", function()
	local w, _, hud = HotWorld()
	local c = Grid(w, hud)
	local db = w.env.HUDiniDB
	db.showTargetHealth, db.showTargetCast = false, true
	hud.spells = {} -- nothing else keeps the poll running
	w.hasTarget = true
	hud:UpdateVisibility()
	H.eq(hud.body:IsShown(), false, "the grid is hidden")
	w:runTickers()
	H.ok(c.casts.n > 0, "the target cast bar is polled")
end)

H.test("a new target starts a stopped HUD poll", function()
	local w, _, hud = HotWorld()
	local c = Grid(w, hud)
	hud.spells = {}
	hud:UpdateVisibility()
	local stopped = Live(w)
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(Live(w), stopped + 1, "the poll runs again")
	c.bars.n = 0
	w:runTickers()
	H.ok(c.bars.n > 0, "the target bar fills")
end)
