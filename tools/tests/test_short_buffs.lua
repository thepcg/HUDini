-- A buff under 30 minutes alerts only in a fight (D-033, TICK-0144).
-- Auras.lua saves each learned buff's full length (the aura's duration),
-- and a learned buff that lasts under 1800 s counts as missing only in a
-- fight: out of one it gives no icon and does not show the HUD. A buff of
-- 30 minutes or more, one with no end, and an old entry with no length
-- work as before.

-- A logged-in shaman with Lightning Shield (10 minutes) and a mage-style
-- long buff. w.auras[name]: the buff GetAuraDataBySpellName finds.
-- w.index[filter]: the auras by slot. w.secret: the values that are secret.
local function World()
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	function w:Hidden()
		local function Throw() error("a secret value was used") end
		local t = setmetatable({}, { __lt = Throw, __le = Throw, __concat = Throw,
			__index = Throw, __eq = Throw })
		self.secret[t] = true
		return t
	end
	w.names = { [324] = "Lightning Shield", [1459] = "Arcane Intellect" }
	w.byName = { ["Lightning Shield"] = 324, ["Arcane Intellect"] = 1459 }
	env.C_Spell.GetSpellName = function(id) return w.names[id] end
	env.C_Spell.GetSpellInfo = function(name)
		local id = w.byName[name]
		if id then return { spellID = id, name = name } end
	end
	env.IsPlayerSpell = function(id) return w.names[id] ~= nil end
	w.auras, w.index = {}, {}
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name) return w.auras[name] end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataByIndex = function(_, i, filter)
		local list = w.index[filter or ""]
		return list and list[i]
	end
	w.time = 100
	local ns = w:loadAddon()
	ns.HUDini.spells = {}
	return w, ns
end

local function Grid(ns, ...)
	for _, id in ipairs({ ... }) do
		ns.HUDini.spells[#ns.HUDini.spells + 1] = { spellID = id }
	end
end

local function Learned(ns)
	return ns.ClassDB().buffSpells or {}
end

local function Check(ns)
	ns.UpdateBuffMissing()
	return ns.missingBuffID, ns.buffMissing
end

-- The HUD's reason to show, as /hud why gives it.
local function Why(w, ns)
	local db = w.env.HUDiniDB
	db.locked, db.hideWhenIdle, db.showWhenBuffMissing = true, true, true
	local _, why = ns.HUDini:ShouldShow()
	return why
end

H.test("a short learned buff that is off: missing in a fight only", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	Grid(ns, 324)
	local id, missing = Check(ns)
	H.eq(id, nil, "out of a fight: no icon")
	H.eq(missing, false, "out of a fight: not missing")
	w.combat = true
	id, missing = Check(ns)
	H.eq(id, 324, "in a fight: the icon")
	H.eq(missing, true, "in a fight: missing")
end)

H.test("a buff of 30 minutes or more, or with no end, is missing in and out of a fight", function()
	for _, length in ipairs({ 1800, 3600, 0 }) do
		local w, ns = World()
		ns.ClassDB().buffSpells = { ["Arcane Intellect"] = length }
		Grid(ns, 1459)
		H.eq(Check(ns), 1459, length .. " s, out of a fight")
		w.combat = true
		H.eq(Check(ns), 1459, length .. " s, in a fight")
	end
end)

H.test("out of a fight the icon falls through to the next buff that counts", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600, ["Arcane Intellect"] = 3600 }
	Grid(ns, 324, 1459)
	H.eq(Check(ns), 1459, "out of a fight: the long one")
	w.combat = true
	H.eq(Check(ns), 324, "in a fight: the first in grid order")
end)

H.test("an old entry with no length counts as before, until the buff is seen", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = true }
	Grid(ns, 324)
	H.eq(Check(ns), 324, "no length known: missing out of a fight, as before")
	w.auras["Lightning Shield"] = { auraInstanceID = 901, duration = 600, expirationTime = 700 }
	H.eq(Check(ns), nil, "on: not missing")
	H.eq(Learned(ns)["Lightning Shield"], 600, "its length is saved")
	w.auras["Lightning Shield"] = nil
	H.eq(Check(ns), nil, "off again, out of a fight: not missing")
end)

H.test("learning saves the full length: from the grid, from your buffs, and no end as 0", function()
	local w2, ns2 = World()
	Grid(ns2, 324)
	w2.auras["Lightning Shield"] = { auraInstanceID = 901, duration = 600, expirationTime = 650 }
	Check(ns2)
	H.eq(Learned(ns2)["Lightning Shield"], 600, "the grid: the duration, not the time left")

	local w3, ns3 = World()
	w3.index["HELPFUL|PLAYER"] = { { name = "Arcane Intellect", spellId = 1459, duration = 3600,
		expirationTime = 3000, auraInstanceID = 902 } }
	Check(ns3)
	H.eq(Learned(ns3)["Arcane Intellect"], 3600, "your buffs: the duration")

	local w4, ns4 = World()
	Grid(ns4, 1459)
	w4.auras["Arcane Intellect"] = { auraInstanceID = 903, duration = 0, expirationTime = 0 }
	Check(ns4)
	H.eq(Learned(ns4)["Arcane Intellect"], 0, "no end: 0")
end)

H.test("a secret length is never compared, and never saved", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	Grid(ns, 324)
	w.combat = true
	w.auras["Lightning Shield"] = { auraInstanceID = 901, duration = w:Hidden(), expirationTime = 700 }
	w.index["HELPFUL|PLAYER"] = { { name = "Lightning Shield", spellId = 324, duration = w:Hidden(),
		expirationTime = 700, auraInstanceID = 901 } }
	Check(ns)
	H.eq(Learned(ns)["Lightning Shield"], 600, "the known length stays")

	local w2, ns2 = World()
	ns2.ClassDB().buffSpells = { ["Lightning Shield"] = true }
	Grid(ns2, 324)
	w2.auras["Lightning Shield"] = { auraInstanceID = 904, duration = w2:Hidden(), expirationTime = 700 }
	Check(ns2)
	H.eq(Learned(ns2)["Lightning Shield"], true, "no length read: the old entry stays")
end)

H.test("a saved length that is not a number counts as no length", function()
	local _, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = "600" }
	Grid(ns, 324)
	H.eq(Check(ns), 324, "counts as before")
end)

H.test("a fight's start and end check again at once: the icon and the HUD", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	Grid(ns, 324)
	Check(ns)
	H.ok(Why(w, ns) ~= ns.Text("why.buffOff"), "out of a fight: no HUD for it")
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(ns.missingBuffID, 324, "the fight starts: the icon")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(ns.missingBuffID, nil, "the fight ends: no icon")
	H.ok(Why(w, ns) ~= ns.Text("why.buffOff"), "and no HUD for it")
end)

H.test("the lockdown starts after PLAYER_REGEN_DISABLED: a check a frame later sees it", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	Grid(ns, 324)
	Check(ns)
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(ns.missingBuffID, nil, "no fight yet at the event")
	w.combat = true
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "the next frame: the icon")
end)

-- Review of TICK-0144: the paths the first tests did not reach.

H.test("a short learned buff off the grid: missing in a fight only", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	H.eq(Check(ns), nil, "out of a fight: no icon")
	w.combat = true
	H.eq(Check(ns), 324, "in a fight: the icon")
end)

H.test("a secret length that is a number is not read: Plain comes first", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	Grid(ns, 324)
	w.secret[4321] = true
	w.auras["Lightning Shield"] = { auraInstanceID = 901, duration = 4321, expirationTime = 700 }
	w.index["HELPFUL|PLAYER"] = { { name = "Lightning Shield", spellId = 324, duration = 4321,
		expirationTime = 700, auraInstanceID = 901 } }
	Check(ns)
	H.eq(Learned(ns)["Lightning Shield"], 600, "the secret length is not saved")
end)

H.test("a later plain read updates a saved length", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	Grid(ns, 324)
	w.auras["Lightning Shield"] = { auraInstanceID = 901, duration = 1800, expirationTime = 1900 }
	Check(ns)
	H.eq(Learned(ns)["Lightning Shield"], 1800, "the new length is saved")
	w.auras["Lightning Shield"] = nil
	H.eq(Check(ns), 324, "now 30 minutes: off out of a fight is missing")
end)

H.test("PLAYER_REGEN_DISABLED before the lockdown: the at-once check sees the fight", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	Grid(ns, 324)
	Check(ns)
	-- The game's order: UnitAffectingCombat says yes at the event, the
	-- lockdown starts after it.
	w.env.InCombatLockdown = function() return false end
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(ns.missingBuffID, 324, "the icon at the event, before the next frame")
end)
