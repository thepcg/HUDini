-- The class resource: a list, and only a spell you know (TICK-0199, D-047).
-- A class file's resource is one buff or an ordered list of buffs; the bar
-- shows the first one on you, else the first whose spell you know, else no
-- bar: a low-level character sees no empty row. In a fight, while your
-- auras are hidden, the pick stays. A buff you picked on the Your class
-- page needs no known spell. What the player sees needs DK's play.

local IDS = { ["Maelstrom Weapon"] = 51530, ["Water Shield"] = 52127, ["Lightning Shield"] = 324 }
local LIST = {
	{ aura = "Maelstrom Weapon", max = 5 },
	{ aura = "Water Shield", max = 3 },
	{ aura = "Lightning Shield", max = 3 },
}

-- A Shaman with this resource in the class file. w.known[name]: you know
-- the spell; w.auras[name]: the buff on you; w.hide: your auras are hidden
-- (a fight), so no read finds them.
local function World(resource, known)
	local w = H.world()
	local env = w.env
	w.class, w.className = "SHAMAN", "Shaman"
	w.known, w.auras = known or {}, {}
	env.C_Spell.GetSpellInfo = function(name)
		if IDS[name] then return { spellID = IDS[name] } end
	end
	env.IsPlayerSpell = function(id)
		for name, n in pairs(IDS) do
			if n == id then return w.known[name] == true end
		end
		return false
	end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.hide == true end }
	local ns = w:loadAddon()
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.hide then return nil end
		return w.auras[name]
	end
	ns.RegisterClass("SHAMAN", { resource = resource })
	ns.HUDini.body:Show()
	ns.UpdateResource()
	return w, ns
end

local function Bar(ns) return ns.GetBar("resource") end
local function Shown(ns) return Bar(ns):IsShown() end
local function Pips(ns) return select(2, Bar(ns):GetMinMaxValues()) end
local function On(w, name, n)
	w.auras[name] = n and { spellId = IDS[name], applications = n } or nil
	w:fire("UNIT_AURA", "player")
	w.ns.UpdateResource()
end

H.test("a spell you do not know yet: no resource bar", function()
	local _, ns = World({ aura = "Lightning Shield", max = 3 })
	H.eq(ns.ClassResource(), nil, "no resource")
	H.eq(Shown(ns), false, "no row")
end)

H.test("a spell you learn brings the bar in, at the next spell change", function()
	local w, ns = World({ aura = "Lightning Shield", max = 3 })
	H.eq(Shown(ns), false, "not yet")
	w.known["Lightning Shield"] = true
	w:fire("SPELLS_CHANGED")
	H.eq(Shown(ns), true, "learned: the row shows, empty")
	H.eq(Pips(ns), 3)
	H.eq(Bar(ns):GetValue(), 0)
end)

H.test("a buff on you counts with no known spell", function()
	local w, ns = World({ aura = "Lightning Shield", max = 3 })
	On(w, "Lightning Shield", 2)
	H.eq(Shown(ns), true, "on you: shown")
	H.eq(Bar(ns):GetValue(), 2)
	On(w, "Lightning Shield", nil)
	H.eq(Shown(ns), false, "gone, not known: no row again")
end)

H.test("a list: the first buff on you, else the first you know", function()
	local w, ns = World(LIST, { ["Water Shield"] = true, ["Lightning Shield"] = true })
	H.eq(ns.ClassResource().aura, "Water Shield", "none on you: the first you know")
	H.eq(Pips(ns), 3)
	On(w, "Lightning Shield", 3)
	H.eq(ns.ClassResource().aura, "Lightning Shield", "the one on you")
	H.eq(Bar(ns):GetValue(), 3)
	On(w, "Maelstrom Weapon", 4)
	H.eq(ns.ClassResource().aura, "Maelstrom Weapon", "first in the list wins")
	H.eq(Pips(ns), 5, "its own pips, laid out again")
	H.eq(Bar(ns):GetValue(), 4)
	On(w, "Maelstrom Weapon", nil)
	H.eq(ns.ClassResource().aura, "Lightning Shield")
	H.eq(Pips(ns), 3)
end)

H.test("a list you know none of: no bar", function()
	local _, ns = World(LIST)
	H.eq(ns.ClassResource(), nil)
	H.eq(Shown(ns), false)
end)

H.test("in a fight the pick stays while your auras are hidden", function()
	local w, ns = World(LIST, { ["Water Shield"] = true, ["Lightning Shield"] = true })
	On(w, "Lightning Shield", 3)
	w.combat, w.hide = true, true
	w:fire("PLAYER_REGEN_DISABLED")
	w:runTimers()
	H.eq(ns.ClassResource().aura, "Lightning Shield", "not back to Water Shield")
	H.eq(Shown(ns), true)
	w.combat, w.hide = false, false
	w.auras["Lightning Shield"] = nil
	w:fire("PLAYER_REGEN_ENABLED")
	ns.UpdateResource()
	H.eq(ns.ClassResource().aura, "Water Shield", "read again after the fight")
end)

H.test("your own pick needs no known spell", function()
	local _, ns = World(LIST)
	ns.SetClassPick("resource", "Arcane Blast")
	ns.UpdateResource()
	H.eq(ns.ClassResource().aura, "Arcane Blast", "the pick, as saved")
	H.eq(Shown(ns), true)
end)

H.test("a power resource needs no spell", function()
	local w, ns = World({ { power = "Mana" } })
	w.env.Enum.PowerType.Mana = w.env.Enum.PowerType.Mana or 0
	H.eq(ns.ClassResource().power, "Mana", "a list with a power entry")
end)

H.test("Class default names the buff the bar would show, or not yet learned", function()
	local w, ns = World(LIST)
	local name, unknown = ns.ClassDefaultName("resource")
	H.eq(name, nil)
	H.eq(unknown, true, "you know none yet")
	w.known["Lightning Shield"] = true
	H.eq(ns.ClassDefaultName("resource"), "Lightning Shield")
	On(w, "Maelstrom Weapon", 2)
	H.eq(ns.ClassDefaultName("resource"), "Maelstrom Weapon", "on you")
	ns.SetClassPick("resource", "Arcane Blast")
	H.eq(ns.ClassDefaultName("resource"), "Maelstrom Weapon", "your own pick does not change it")
end)

H.test("/hud debug aura: the list, and why there is no bar", function()
	local _, ns = World(LIST)
	local lines = {}
	ns.ProbeAura(function(line) lines[#lines + 1] = line end)
	local text = table.concat(lines, "\n")
	H.ok(text:find("Maelstrom Weapon, Water Shield, Lightning Shield", 1, true), "the names")
	H.ok(text:find("you know none of their spells yet", 1, true), "the reason")
end)

-- Review finding (TICK-0199): a spell learned at a level-up mid fight must
-- not add the row then: the rows would move while the secure click buttons
-- stay in their slots until the fight ends.
H.test("a spell learned in a fight brings the bar in at the fight's end, not before", function()
	local w, ns = World({ aura = "Lightning Shield", max = 3 })
	local layouts = 0
	local layout = ns.HUDini.Layout
	ns.HUDini.Layout = function(...)
		layouts = layouts + 1
		return layout(...)
	end
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	w:runTimers()
	w.known["Lightning Shield"] = true
	w:fire("SPELLS_CHANGED")
	H.eq(ns.ClassResource(), nil, "held in the fight")
	H.eq(Shown(ns), false, "no row yet")
	H.eq(layouts, 0, "no layout in the fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(ns.ClassResource().aura, "Lightning Shield", "the fight is over")
	H.eq(Shown(ns), true, "the row now")
	H.ok(layouts >= 1, "laid out after the fight")
end)

H.test("in a fight the list's pick stays though a buff of another entry comes on", function()
	local w, ns = World(LIST, { ["Lightning Shield"] = true })
	H.eq(Pips(ns), 3)
	w.combat = true
	On(w, "Maelstrom Weapon", 2)
	H.eq(ns.ClassResource().aura, "Lightning Shield", "held: no new pips in the fight")
	H.eq(Pips(ns), 3)
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(ns.ClassResource().aura, "Maelstrom Weapon", "after the fight")
	H.eq(Pips(ns), 5)
end)
