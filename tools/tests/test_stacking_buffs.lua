-- Buffs that stack (TICK-0094, D-019): HUDini learns a buff of yours that
-- it sees with 2 stacks or more, out of a fight, and the Resource row offers
-- only those. No spell on the action bars says if its buff can stack.

-- A world for one class, logged in with no buff on. buffs: your own buffs
-- from then on, in order, each { name = , applications = }. Only the
-- HELPFUL|PLAYER scan sees them. o.secret: the game's issecretvalue.
-- o.atLogin: the buffs are on at login.
local function World(buffs, o)
	o = o or {}
	local w = H.world()
	w.class, w.className = o.class or "PALADIN", o.className or "Paladin"
	w.env.issecretvalue = o.secret
	w.reads = 0
	w.env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		if unit ~= "player" or filter ~= "HELPFUL|PLAYER" then return nil end
		w.reads = w.reads + 1
		return w.buffs[i]
	end
	w.buffs = o.atLogin and buffs or {}
	local ns = w:loadAddon()
	w:runTimers()
	w.buffs = buffs
	return ns, w
end

local function Offered(ns)
	return table.concat(ns.ClassPickSpells("resource"), "|")
end

-- A value the game hides: any compare or join throws, as in the game.
local SECRET = setmetatable({}, {
	__lt = function() error("compared a secret value") end,
	__le = function() error("compared a secret value") end,
	__eq = function() error("compared a secret value") end,
	__concat = function() error("joined a secret value") end,
})
local function IsSecret(v) return rawequal(v, SECRET) end

H.test("a buff seen with 2 stacks is offered; one with 1 stack, or none, is not", function()
	local buffs = {
		{ name = "Seal of Righteousness", applications = 0 },
		{ name = "Devotion Aura", applications = 1 },
		{ name = "Vengeance", applications = 2 },
		{ name = "Holy Shield", applications = 4 },
	}
	local ns, w = World(buffs)
	H.eq(Offered(ns), "", "nothing seen yet")
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "Holy Shield|Vengeance", "only the buffs seen with 2 or more, A to Z")
	H.eq(ns.ClassDB().stackBuffs["Devotion Aura"], nil, "one stack is not saved")
	-- The list only grows: Vengeance drops off, and is still offered.
	table.remove(buffs, 3)
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "Holy Shield|Vengeance", "a buff that stacked once stays")
end)

H.test("a stacking buff that is up at login is learned then", function()
	local ns = World({ { name = "Vengeance", applications = 3 } }, { atLogin = true })
	H.eq(Offered(ns), "Vengeance")
end)

H.test("the other rows still offer the spells on your action bars", function()
	local ns = World({ { name = "Vengeance", applications = 3 } })
	ns.ActionBarSpells = function() return { "Seal of Righteousness", "Sense Undead" } end
	ns.LearnStackingBuffs()
	for _, key in ipairs({ "interrupt", "dispel", "purge", "keepUp" }) do
		H.eq(table.concat(ns.ClassPickSpells(key), "|"), "Seal of Righteousness|Sense Undead", key)
	end
	H.eq(Offered(ns), "Vengeance", "Resource: no action-bar spell")
end)

H.test("in a fight nothing is read; after it, a buff still up is learned", function()
	local ns, w = World({ { name = "Vengeance", applications = 3 } })
	w.combat = true
	local before = w.reads
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "", "nothing learned in a fight")
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(Offered(ns), "")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Offered(ns), "Vengeance", "learned once the fight ends")
	H.ok(w.reads > before, "and read then")
end)

H.test("a secret name or stack count learns nothing, with no error", function()
	local buffs = {
		{ name = SECRET, applications = 3 },
		{ name = "Vengeance", applications = SECRET },
		{ name = "Holy Shield", applications = 2 },
	}
	local ns, w = World(buffs, { secret = IsSecret })
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "Holy Shield", "only the plain one")
	H.eq(ns.ClassDB().stackBuffs.Vengeance, nil, "a secret count is not saved")
end)

-- In the game a secret can look like a plain string or number: only
-- issecretvalue tells. So Plain, not the type checks, must drop it.
H.test("a secret that looks like a plain string or number learns nothing", function()
	local hidden = { ["Hidden Shield"] = true, [7] = true }
	local buffs = {
		{ name = "Hidden Shield", applications = 3 },
		{ name = "Vengeance", applications = 7 },
		{ name = "Holy Shield", applications = 2 },
	}
	local ns, w = World(buffs, { secret = function(v) return hidden[v] == true end })
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "Holy Shield", "only the plain one")
end)

H.test("many buffs are offered A to Z, each once", function()
	local names = { "Zeal", "Arcane Charge", "Maelstrom Weapon", "Bloodlust Stack", "Wild Growth",
		"Combo Point", "Holy Power", "Tidal Wave", "Enrage", "Ravenous", "Kindling", "Quick Draw" }
	local buffs = {}
	for i, name in ipairs(names) do buffs[i] = { name = name, applications = 2 + i } end
	local ns, w = World(buffs)
	w:fire("UNIT_AURA", "player")
	w:fire("UNIT_AURA", "player")
	table.sort(names)
	H.eq(Offered(ns), table.concat(names, "|"), "A to Z, each once")
end)

H.test("a buff that refuses to be read is skipped, and the scan goes on", function()
	local refused = setmetatable({}, { __index = function() error("refused") end })
	local ns, w = World({ refused, { name = "", applications = 5 }, { name = "Vengeance", applications = "3" },
		{ name = "Holy Shield", applications = 2 } })
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "Holy Shield", "a refused read, an empty name and a count that is not a number are skipped")
end)

H.test("the target's auras teach nothing", function()
	local ns, w = World({ { name = "Vengeance", applications = 3 } })
	local before = w.reads
	w:fire("UNIT_AURA", "target")
	H.eq(w.reads, before, "no read of your buffs for the target")
	H.eq(Offered(ns), "")
end)

H.test("each class keeps its own list", function()
	local ns, w = World({ { name = "Vengeance", applications = 3 } })
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "Vengeance", "the paladin's")
	local db = w.env.HUDiniDB
	w.class, w.className = "WARRIOR", "Warrior"
	H.eq(Offered(ns), "", "a warrior has seen none")
	H.eq(db.classes.PALADIN.stackBuffs.Vengeance, 3, "saved for the paladin")
	H.eq(db.classes.WARRIOR and db.classes.WARRIOR.stackBuffs, nil, "and not for the warrior")
end)

H.test("a saved list that is not a table is replaced, and a bad entry is not offered", function()
	local ns, w = World({ { name = "Vengeance", applications = 3 } })
	ns.ClassDB().stackBuffs = "broken"
	H.eq(Offered(ns), "", "a broken list offers nothing")
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "Vengeance", "and is replaced")
	ns.ClassDB().stackBuffs[7] = 3
	ns.ClassDB().stackBuffs["Holy Shield"] = "yes"
	ns.ClassDB().stackBuffs["Devotion Aura"] = 1
	ns.ClassDB().stackBuffs["Old Mark"] = true
	H.eq(Offered(ns), "Vengeance", "only name = count of 2 or more")
	-- A count that is not a number is replaced when the buff is seen again.
	ns.ClassDB().stackBuffs.Vengeance = "x"
	w:fire("UNIT_AURA", "player")
	H.eq(ns.ClassDB().stackBuffs.Vengeance, 3, "replaced")
end)

-- Review TICK-0094 #2: a pick filled toward 5, so a buff that tops out at 3
-- never filled the bar.
H.test("the most stacks seen are kept, and a first pick fills at that count", function()
	local buffs = { { name = "Vengeance", applications = 3 } }
	local ns, w = World(buffs)
	w:fire("UNIT_AURA", "player")
	buffs[1].applications = 2
	w:fire("UNIT_AURA", "player")
	H.eq(ns.ClassDB().stackBuffs.Vengeance, 3, "a lower count does not lower it")
	H.ok(ns.SetClassPick("resource", "Vengeance"), "picked")
	H.eq(ns.ClassDB().resource.max, 3, "fills at 3 stacks")
	buffs[1].applications = 4
	w:fire("UNIT_AURA", "player")
	H.eq(ns.ClassDB().stackBuffs.Vengeance, 4, "a higher count raises it")
	-- A count past the bar's top is cut to it.
	ns.ClassDB().stackBuffs["Holy Shield"] = 99
	H.ok(ns.SetClassPick("resource", "Holy Shield"))
	H.eq(ns.ClassDB().resource.max, 20, "at most 20")
	-- A pick that HUDini never saw stack keeps the old count, as before.
	ns.ClassDB().resource.max = 7
	H.ok(ns.SetClassPick("resource", "Fireball"))
	H.eq(ns.ClassDB().resource.max, 7, "the old count")
end)

-- Review TICK-0094 #4.
H.test("the scan stops at the first empty slot", function()
	local buffs = { { name = "Vengeance", applications = 3 } }
	buffs[3] = { name = "Holy Shield", applications = 3 }
	local ns, w = World(buffs)
	local before = w.reads
	w:fire("UNIT_AURA", "player")
	H.eq(w.reads - before, 2, "slot 1, then the empty slot 2")
	H.eq(Offered(ns), "Vengeance")
end)

H.test("flagged in combat with no lockdown is a fight too", function()
	local ns, w = World({ { name = "Vengeance", applications = 3 } })
	w.env.UnitAffectingCombat = function() return true end
	w:fire("UNIT_AURA", "player")
	H.eq(Offered(ns), "", "nothing learned")
end)

H.test("no saved variables yet: nothing is read or saved", function()
	local ns, w = World({ { name = "Vengeance", applications = 3 } })
	local db = w.env.HUDiniDB
	w.env.HUDiniDB = nil
	local before = w.reads
	ns.LearnStackingBuffs()
	H.eq(w.reads, before, "no read")
	H.eq(w.env.HUDiniDB, nil, "none made")
	w.env.HUDiniDB = db
end)
