-- One UNIT_AURA handler, alert events, alert tickers that stop (TICK-0065).
-- One aura change reaches the resource bar, the icon auras and the alerts
-- once each, from one handler. The alerts also follow a duel on the target,
-- an equipment change and the fight's first frame. The bait and target buff
-- tickers run only while their warning can matter.

local function Live(w)
	local n = 0
	for _, t in ipairs(w.tickers) do
		if not t.cancelled then n = n + 1 end
	end
	return n
end

-- Count each call to ns[name], then pass it on.
local function Count(ns, name)
	local real, box = ns[name], { n = 0 }
	ns[name] = function(...)
		box.n = box.n + 1
		if real then return real(...) end
	end
	return box
end

-- The frames listening to an event.
local function Listeners(w, event)
	local n = 0
	for _, f in ipairs(w.frames) do
		if f:IsEventRegistered(event) then n = n + 1 end
	end
	return n
end

local function World()
	local w = H.world()
	w:loadAddon()
	return w, w.ns
end

H.test("one UNIT_AURA handler reaches the bars, the icon auras and the alerts once each", function()
	local w, ns = World()
	H.eq(Listeners(w, "UNIT_AURA"), 1, "frames listening to UNIT_AURA")
	local res, icons, alerts = Count(ns, "UpdateResource"), Count(ns, "UpdateIconAuras"), Count(ns, "UpdateAlerts")
	w:fire("UNIT_AURA", "player")
	H.eq(res.n, 1, "resource bar")
	H.eq(icons.n, 1, "icon auras")
	H.eq(alerts.n, 1, "alerts")
end)

H.test("a target aura change reaches only the alerts", function()
	local w, ns = World()
	local res, icons, alerts = Count(ns, "UpdateResource"), Count(ns, "UpdateIconAuras"), Count(ns, "UpdateAlerts")
	w.hasTarget = true
	w:fire("UNIT_AURA", "target")
	H.eq(res.n + icons.n, 0, "resource bar and icon auras")
	H.eq(alerts.n, 1, "alerts")
end)

H.test("UNIT_AURA is heard for you and your target only", function()
	local w, ns = World()
	local res, icons, alerts = Count(ns, "UpdateResource"), Count(ns, "UpdateIconAuras"), Count(ns, "UpdateAlerts")
	for _, unit in ipairs({ "party1", "focus", "nameplate1", "pet" }) do w:fire("UNIT_AURA", unit) end
	H.eq(res.n + icons.n + alerts.n, 0, "updates for other units")
	w:fire("UNIT_AURA", "player")
	w:fire("UNIT_AURA", "target")
	H.eq(alerts.n, 2, "both registered units reach the alerts")
end)

H.test("an error in one aura update does not stop the others", function()
	local w, ns = World()
	local errors = {}
	w.env.geterrorhandler = function() return function(e) errors[#errors + 1] = e end end
	ns.UpdateResource = function() error("boom") end
	local icons, alerts = Count(ns, "UpdateIconAuras"), Count(ns, "UpdateAlerts")
	w:fire("UNIT_AURA", "player")
	H.eq(#errors, 1, "the error reaches the error handler")
	H.eq(icons.n, 1, "the icon auras still update")
	H.eq(alerts.n, 1, "the alerts still update")
end)

H.test("a duel on the target and an equipment change re-run the alerts", function()
	local w, ns = World()
	for _, event in ipairs({ "UNIT_FACTION", "DUEL_FINISHED", "PLAYER_EQUIPMENT_CHANGED" }) do
		-- UNIT_FACTION: the alerts, and Bars.lua for the PvP marks (TICK-0097).
		H.eq(Listeners(w, event), event == "UNIT_FACTION" and 2 or 1, event .. " listened to")
		local alerts = Count(ns, "UpdateAlerts")
		w:fire(event, event == "UNIT_FACTION" and "target" or 16)
		H.eq(alerts.n, 1, event .. " re-runs the alerts")
	end
	local alerts = Count(ns, "UpdateAlerts")
	w:fire("UNIT_FACTION", "player")
	w:fire("UNIT_FACTION", "party1")
	H.eq(alerts.n, 0, "UNIT_FACTION for another unit")
end)

H.test("the alerts look again one frame after a fight starts", function()
	local w, ns = World()
	local alerts = Count(ns, "UpdateAlerts")
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(alerts.n, 1, "at the event")
	w.combat = true
	w:runTimers()
	H.eq(alerts.n, 2, "and on the next frame")
	w.combat = false
end)

H.test("the bait ticker runs only with the warning on and a fishing pole in hand", function()
	local w, ns = World()
	local idle = Live(w)
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	H.eq(Live(w), idle + 1, "a pole in hand starts it")
	w.env.HUDiniDB.warnNoBait = false
	ns.UpdateAlerts()
	H.eq(Live(w), idle, "the warning off stops it")
	w.env.HUDiniDB.warnNoBait = true
	ns.UpdateAlerts()
	H.eq(Live(w), idle + 1, "on again")
	w:holdItem(16, nil)
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	H.eq(Live(w), idle, "the pole put away stops it")
end)

H.test("the target buff ticker runs only on a friendly player out of a fight", function()
	local w, ns = World()
	local idle = Live(w)
	w.env.UnitIsPlayer = function() return true end
	w.hasTarget = true
	ns.UpdateAlerts()
	H.eq(Live(w), idle + 1, "a friendly player target starts it")
	w.env.UnitIsDeadOrGhost = function() return true end
	w:runTickers()
	H.eq(Live(w), idle + 1, "a dead friend keeps it, to see them come back")
	w.combat = true
	w:runTickers()
	H.eq(Live(w), idle, "a fight stops it at its next tick")
	w.combat = false
	ns.UpdateAlerts()
	H.eq(Live(w), idle + 1, "out of the fight it runs again")
	w.env.HUDiniDB.warnTargetBuff = false
	ns.UpdateAlerts()
	H.eq(Live(w), idle, "the warning off stops it")
end)

H.test("with the alerts off, no alert ticker runs", function()
	local w, ns = World()
	local idle = Live(w)
	local db = w.env.HUDiniDB
	db.warnNoBait, db.warnTargetBuff = false, false
	w.env.UnitIsPlayer = function() return true end
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	w.hasTarget = true
	ns.UpdateAlerts()
	H.eq(Live(w), idle, "no alert ticker")
	db.warnNoBait, db.warnTargetBuff = true, true
	ns.UpdateAlerts()
	H.eq(Live(w), idle + 2, "both start with the alerts on: they did not run before")
end)

H.test("with health off, the bait ticker does not run", function()
	local w = World()
	local idle = Live(w)
	w.env.HUDiniDB.showHealth = false
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	H.eq(Live(w), idle, "no bait ticker without the health bar")
end)

--------------------------------------------------------------------------------
-- What is drawn, from the real events
--------------------------------------------------------------------------------

-- The "No bait" icon: the frame whose label says so.
local function BaitIcon(w)
	for _, f in ipairs(w.frames) do
		if f:GetText() == "No bait" then return f:GetParent() end
	end
end

-- The target buff icon: the alert icon left of the target bar (D-027).
local function TargetBuffIcon(w)
	local bar = w.ns.GetBar("targethealth")
	for _, f in ipairs(w.frames) do
		local point, to, rel = f:GetPoint(1)
		if f:GetParent() == bar and f.tex and point == "RIGHT" and to == bar and rel == "LEFT" then
			return f
		end
	end
end

H.test("the No bait icon shows with a bare pole and hides when it is put away", function()
	local w = World()
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	w.env.C_TooltipInfo = { GetInventoryItem = function()
		return { lines = { { leftText = "Fishing Pole" } } }
	end }
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	H.ok(BaitIcon(w) ~= nil, "the icon is made")
	H.eq(BaitIcon(w):IsShown(), true, "a pole with no bait: shown at the event")
	w:holdItem(16, nil)
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	H.eq(BaitIcon(w):IsShown(), false, "the pole put away: hidden at the event")
end)

-- A Mage who keeps Arcane Intellect up, and a friendly player target who
-- lacks it.
local AI = 7
local function BuffWorld()
	local w = H.world()
	w.class, w.className = "MAGE", "Mage"
	local env = w.env
	env.C_Spell.GetSpellName = function(id) return id == AI and "Arcane Intellect" or nil end
	env.C_Spell.GetSpellInfo = function(n)
		if n == "Arcane Intellect" or n == AI then return { spellID = AI, name = "Arcane Intellect" } end
	end
	env.IsPlayerSpell = function(id) return id == AI end
	env.SpellHasRange = function() return true end
	env.UnitIsPlayer = function() return true end
	w:loadAddon()
	w.ns.ClassDB().buffSpells = { ["Arcane Intellect"] = true }
	w.ns.HUDini.spells = {}
	return w, w.ns
end

H.test("a new friendly target lacking your buff shows the target buff icon", function()
	local w = BuffWorld()
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	H.ok(TargetBuffIcon(w) ~= nil, "the icon is made")
	H.eq(TargetBuffIcon(w):IsShown(), true, "shown at the target change")
	w.hasTarget = false
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(TargetBuffIcon(w):IsShown(), false, "no target: hidden")
end)

H.test("a dead friend who is rezzed gets the icon at the next tick", function()
	local w = BuffWorld()
	local dead = true
	w.env.UnitIsDeadOrGhost = function() return dead end
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(TargetBuffIcon(w):IsShown(), false, "dead: no icon")
	dead = false -- a rez fires no event the alerts hear
	w:runTickers()
	H.eq(TargetBuffIcon(w):IsShown(), true, "rezzed: the ticker shows it")
end)

H.test("the target buff icon comes back when the fight ends", function()
	local w = BuffWorld()
	local idle = Live(w)
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(Live(w), idle + 1, "the target buff ticker runs")
	w:fire("PLAYER_REGEN_DISABLED")
	w.combat = true
	w:runTimers()
	H.eq(TargetBuffIcon(w):IsShown(), false, "in the fight: hidden")
	H.eq(Live(w), idle, "and the ticker stops")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(TargetBuffIcon(w):IsShown(), true, "the fight ends: shown")
	H.eq(Live(w), idle + 1, "and the ticker runs again")
end)
