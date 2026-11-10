-- Mana in forms (TICK-0107). In Bear or Cat Form a druid's power bar shows
-- rage or energy, so a thin bar under it shows the mana. It shows only for
-- a class whose powers hold mana and the power it has now, with the switch
-- and the power bar on. The mana goes straight to the bar, secret or not. What it
-- looks like needs a test sitting.

local MANA, RAGE, ENERGY = 0, 1, 3
local FORM = { caster = { MANA, "MANA" }, bear = { RAGE, "RAGE" }, cat = { ENERGY, "ENERGY" } }

-- A logged-in world. w.form: "caster", "bear" or "cat". w.power: each power
-- type's value and maximum. w.secret: values the game hides; a secret test
-- flags the very value that WOULD show or fill the bar, so only the guard
-- keeps it right.
local function World(class, form)
	local w = H.world()
	local env = w.env
	w.class, w.className = class or "DRUID", "Druid"
	w.form = form or "bear"
	w.secret = {}
	w.power = { [MANA] = { 37, 140 }, [RAGE] = { 20, 100 }, [ENERGY] = { 60, 100 } }
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.UnitPowerType = function() return FORM[w.form][1], FORM[w.form][2] end
	-- With no power type the game answers for the power you have now.
	env.UnitPower = function(_, ptype) return w.power[ptype or FORM[w.form][1]][1] end
	env.UnitPowerMax = function(_, ptype) return w.power[ptype or FORM[w.form][1]][2] end
	local ns = w:loadAddon()
	return w, ns
end

local function Mana(ns) return ns.GetBar("druidmana") end
local function Shown(ns) return Mana(ns):IsShown() == true end

-- Shift: the game swaps the power and fires UNIT_DISPLAYPOWER.
local function Shift(w, form)
	w.form = form
	w:fire("UNIT_DISPLAYPOWER", "player")
end

-- The y of a bar's BOTTOMLEFT over the HUD's top: rows stack upward.
local function Y(ns, key)
	local point = { ns.GetBar(key):GetPoint(1) }
	return point[5]
end

H.test("the switch is on by default", function()
	local _, ns = World()
	H.eq(ns.defaults.showDruidMana, true)
end)

H.test("a druid in Bear Form or Cat Form sees the bar, filled with mana", function()
	for _, form in ipairs({ "bear", "cat" }) do
		local _, ns = World("DRUID", form)
		H.ok(Shown(ns), form .. ": shown")
		local h = Mana(ns).__h
		H.eq(h.max, 140, form .. ": the mana maximum")
		H.eq(h.value, 37, form .. ": the mana")
	end
end)

H.test("in caster form there is no bar, but its slot stays, so the stack never moves", function()
	local _, caster = World("DRUID", "caster")
	H.eq(Shown(caster), false, "no bar")
	local _, bear = World("DRUID", "bear")
	for _, key in ipairs({ "power", "health", "targethealth" }) do
		H.eq(Y(caster, key), Y(bear, key), key .. ": the same spot in caster form and in Bear Form")
	end
	local _, mage = World("MAGE", "caster")
	H.ok(Y(caster, "power") > Y(mage, "power"), "a mage has no slot")
end)

H.test("a shift in a fight moves no bar, so the click buttons stay on their bars", function()
	local w, ns = World("DRUID", "caster")
	local before = {}
	for _, key in ipairs({ "power", "health", "targethealth" }) do before[key] = Y(ns, key) end
	w.combat = true
	for _, form in ipairs({ "bear", "caster", "cat", "caster" }) do
		Shift(w, form)
		for _, key in ipairs({ "power", "health", "targethealth" }) do
			H.eq(Y(ns, key), before[key], form .. ": " .. key .. " did not move")
		end
	end
	H.eq(Shown(ns), false, "back in caster form: no bar")
end)

H.test("the switch off, or Power bar off, gives the slot back", function()
	local _, on = World("DRUID", "caster")
	local _, mage = World("MAGE", "caster")
	local w, off = World("DRUID", "caster")
	w.env.HUDiniDB.showDruidMana = false
	off.HUDini:Apply()
	H.eq(Y(off, "power"), Y(mage, "power"), "switch off: the power bar where a mage has it")
	H.ok(Y(on, "power") > Y(off, "power"), "switch on: one slot higher")
end)

H.test("the bar sits right under the power bar, half a bar tall", function()
	local w, ns = World("DRUID", "bear")
	local db = w.env.HUDiniDB
	local h = Mana(ns).__h
	H.eq(h.height, math.floor(db.barHeight / 2 + 0.5), "half a bar")
	H.eq(Y(ns, "druidmana") + h.height + db.barGap, Y(ns, "power"), "one gap under the power bar")
	H.ok(Y(ns, "druidmana") > Y(ns, "xp") or not ns.GetBar("xp"):IsShown(), "over the XP bar")
end)

H.test("a shift to a form shows the bar; a shift back hides it", function()
	local w, ns = World("DRUID", "caster")
	H.eq(Shown(ns), false, "caster")
	Shift(w, "bear")
	H.ok(Shown(ns), "bear")
	H.eq(Mana(ns).__h.value, 37, "bear: filled at the shift")
	Shift(w, "cat")
	H.ok(Shown(ns), "cat")
	Shift(w, "caster")
	H.eq(Shown(ns), false, "back to caster")
end)

H.test("a mana tick in a form fills the bar", function()
	local w, ns = World("DRUID", "cat")
	w.power[MANA][1] = 90
	w:fire("UNIT_POWER_FREQUENT", "player", "MANA")
	H.eq(Mana(ns).__h.value, 90)
end)

H.test("no bar for a class with no mana in its powers, in rage or energy", function()
	-- A hunter's file lists no powers at all.
	for _, case in ipairs({ { "WARRIOR", "bear" }, { "ROGUE", "cat" }, { "HUNTER", "cat" } }) do
		local _, ns = World(case[1], case[2])
		H.eq(Shown(ns), false, case[1])
	end
end)

H.test("no bar with the switch off, or with the power bar off", function()
	for _, key in ipairs({ "showDruidMana", "showPower" }) do
		local w, ns = World("DRUID", "bear")
		w.env.HUDiniDB[key] = false
		ns.HUDini:Apply()
		H.eq(Shown(ns), false, key .. " off")
		w.env.HUDiniDB[key] = true
		ns.HUDini:Apply()
		H.ok(Shown(ns), key .. " back on")
	end
end)

H.test("no bar in a form whose power is not one of the class's powers", function()
	-- A power the class file does not list (Moonkin's, on some clients).
	local w, ns = World("DRUID", "caster")
	FORM.moon = { 8, "LUNAR_POWER" }
	w.power[8] = { 10, 100 }
	Shift(w, "moon")
	FORM.moon = nil
	H.eq(Shown(ns), false)
end)

H.test("the bar wears the mana color", function()
	local _, ns = World("DRUID", "bear")
	H.eq(Mana(ns).colorKey, "mana")
end)

H.test("secret mana goes to the bar unchanged, and throws nothing", function()
	local w, ns = World("DRUID", "bear")
	w.secret[37], w.secret[140] = true, true
	w.power[MANA] = { 37, 140 }
	H.ok(pcall(w.fire, w, "UNIT_POWER_FREQUENT", "player", "MANA"), "no throw")
	local h = Mana(ns).__h
	H.eq(h.max, 140, "the secret maximum")
	H.eq(h.value, 37, "the secret mana")
end)

H.test("a secret power type draws no bar", function()
	-- Plain, rage shows the bar: the value that WOULD match.
	local w, ns = World("DRUID", "caster")
	Shift(w, "bear")
	H.ok(Shown(ns), "plain rage: shown")
	Shift(w, "caster")
	w.secret["RAGE"] = true
	H.ok(pcall(Shift, w, "bear"), "no throw")
	H.eq(Shown(ns), false, "secret rage: no bar")
end)

H.test("only a class with mana and another power has the bar, so its row is gray for the rest", function()
	-- A mage, paladin, priest, shaman or warlock lists MANA alone.
	for _, class in ipairs({ "MAGE", "PALADIN", "PRIEST", "SHAMAN", "WARLOCK", "WARRIOR", "HUNTER" }) do
		local _, ns = World(class, "caster")
		H.eq(ns.HasFormMana(), false, class)
	end
	local _, druid = World("DRUID", "caster")
	H.eq(druid.HasFormMana(), true, "DRUID")
end)
