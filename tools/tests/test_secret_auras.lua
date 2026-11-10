-- Auras.lua when the game hides an answer (TICK-0112). Each test first runs
-- the value that WOULD change what HUDini does, plain, and checks that it
-- does. Then it flags that same value secret and checks that HUDini does
-- what it does for no answer, and throws nothing. So a missing Plain() or
-- IsSecret() fails the test (the method of TICK-0110).

-- A logged-in Mage. w.secret: the values issecretvalue calls secret.
-- w:Once(v) gives a stub that returns v and flags the very next check
-- secret if it asks about v (see test_secret_core.lua). w:Hidden() is a
-- secret that throws when compared or joined, as a real one does.
-- w.names[id]: a spell's name, or a stub that gives it. w.auras[name]: the
-- buff GetAuraDataBySpellName finds. w.index[filter]: the auras by slot.
local function World(setup)
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v)
		if v == nil then return false end
		if w.secret[v] then return true end
		if w.arming then
			w.arming = false
			return v == w.armValue
		end
		return false
	end
	function w:Once(v)
		return function()
			self.arming, self.armValue = true, v
			return v
		end
	end
	function w:Hidden()
		local function Throw() error("a secret value was used") end
		local t = setmetatable({}, { __lt = Throw, __le = Throw, __concat = Throw, __index = Throw })
		self.secret[t] = true
		return t
	end

	w.names = { [1459] = "Arcane Intellect" }
	w.byName = { ["Arcane Intellect"] = 1459 }
	env.C_Spell.GetSpellName = function(id)
		local n = w.names[id]
		if type(n) == "function" then return n() end
		return n
	end
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
	if setup then setup(w, env) end
	local ns = w:loadAddon()
	ns.HUDini.spells = {}
	return w, ns
end

local function Learned(ns)
	return ns.ClassDB().buffSpells or {}
end

-- Arcane Intellect, learned, with these spell IDs on the grid.
local function Keep(ns, grid)
	ns.ClassDB().buffSpells = { ["Arcane Intellect"] = true }
	for _, id in ipairs(grid or {}) do
		ns.HUDini.spells[#ns.HUDini.spells + 1] = { spellID = id }
	end
end

--------------------------------------------------------------------------------
-- The buff names of an icon, and reading a buff
--------------------------------------------------------------------------------

H.test("a secret spell name gives an icon no buff names, and is not kept", function()
	local w, ns = World()
	w.names[1462], w.names[1463] = "Frost Armor", "Ice Armor"
	H.eq(ns.AuraNames({ spellID = 1462 })[1], "Frost Armor", "plain: its own name")
	w.secret["Ice Armor"] = true
	local entry = { spellID = 1463 }
	H.eq(#ns.AuraNames(entry), 0, "secret: no names")
	H.eq(entry.auraNames, nil, "and none kept")
end)

H.test("a secret aura instance ID does not count as on", function()
	local w, ns = World()
	Keep(ns, { 1459 })
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 1459, "no buff: missing")
	w.auras["Arcane Intellect"] = { auraInstanceID = 901 }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "plain ID: on")
	w.auras["Arcane Intellect"] = nil
	ns.UpdateBuffMissing()
	w.secret[902] = true
	w.auras["Arcane Intellect"] = { auraInstanceID = 902 }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 1459, "secret ID: the last answer, off, stays")
end)

--------------------------------------------------------------------------------
-- States: the form you are in, a mount
--------------------------------------------------------------------------------

H.test("a secret form index or form name is no form", function()
	local w, ns = World(function(w, env)
		w.names[4501], w.byName["Tree Shape"] = "Tree Shape", 4501
		env.GetShapeshiftFormID = function() return 5 end
		env.GetShapeshiftForm = function() return 7 end
		env.GetShapeshiftFormInfo = function(i)
			if i == 7 then return 136116, true, true, 4501 end
		end
	end)
	H.eq(ns.IsStateBuff("Tree Shape"), true, "plain: in the form")
	w.secret[7] = true
	H.eq(ns.IsStateBuff("Tree Shape"), false, "secret index: no form")
	w.secret[7] = nil
	w.names[4501] = w:Once("Tree Shape")
	H.eq(ns.IsStateBuff("Tree Shape"), false, "secret name: no form")
end)

H.test("a secret mount answer is no mount", function()
	local w, ns = World(function(w, env)
		env.C_MountJournal = { GetMountFromSpell = function(id)
			if id == 4600 then return w.mount end
		end }
	end)
	w.mount = 77
	H.eq(ns.IsStateBuff("Swift Moth", 4600), true, "plain: a mount")
	w.secret[77] = true
	H.eq(ns.IsStateBuff("Swift Moth", 4600), false, "secret: no mount")
end)

--------------------------------------------------------------------------------
-- Learning a buff to keep up
--------------------------------------------------------------------------------

H.test("a secret duration of a buff from the grid teaches nothing", function()
	local w, ns = World()
	ns.HUDini.spells = { { spellID = 1459 } }
	w.auras["Arcane Intellect"] = { auraInstanceID = 7, duration = 1800 }
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Arcane Intellect"], true, "plain: learned")
	ns.ClassDB().buffSpells = {}
	w.auras["Arcane Intellect"] = { auraInstanceID = 7, duration = w:Hidden() }
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Arcane Intellect"], nil, "secret: not learned")
end)

H.test("a secret name, spell ID or duration of your own buff teaches nothing", function()
	local w, ns = World()
	w.names[1470], w.byName["Moon Ward"] = "Moon Ward", 1470
	local function LearnsFrom(aura)
		ns.ClassDB().buffSpells = {}
		w.index["HELPFUL|PLAYER"] = { aura }
		ns.UpdateBuffMissing()
		return Learned(ns)["Moon Ward"] == true
	end
	H.eq(LearnsFrom({ name = "Moon Ward", spellId = 1470, duration = 1800 }), true, "plain: learned")
	w.secret["Moon Ward"] = true
	H.eq(LearnsFrom({ name = "Moon Ward", spellId = 1470, duration = 1800 }), false, "secret name")
	w.secret["Moon Ward"], w.secret[1470] = nil, true
	H.eq(LearnsFrom({ name = "Moon Ward", spellId = 1470, duration = 1800 }), false, "secret spell ID")
	w.secret[1470] = nil
	H.eq(LearnsFrom({ name = "Moon Ward", spellId = 1470, duration = w:Hidden() }), false, "secret duration")
end)

--------------------------------------------------------------------------------
-- The last answer, aged by the end time
--------------------------------------------------------------------------------

H.test("a secret end time is not kept: the last answer is not aged", function()
	local w, ns = World()
	Keep(ns, { 1459 })
	local function InAFightAfter(ends)
		w.combat = false
		w.auras["Arcane Intellect"] = { auraInstanceID = 7, expirationTime = ends }
		ns.UpdateBuffMissing()
		w.combat = true
		w.auras["Arcane Intellect"] = nil
		ns.UpdateBuffMissing()
		return ns.missingBuffID
	end
	H.eq(InAFightAfter(50), 1459, "plain end time, past: off")
	H.eq(InAFightAfter(w:Hidden()), nil, "secret: the last answer, on, stays")
end)

--------------------------------------------------------------------------------
-- Auras hidden with no fight flag (TICK-0125)
--
-- The game hides your auras under its addon restriction, which has its own
-- state (ADDON_RESTRICTION_STATE_CHANGED), apart from InCombatLockdown and
-- UnitAffectingCombat. A hidden aura is not found by name
-- (RequiresNonSecretAura). Found off in that gap, Arcane Intellect stayed
-- "off" the whole next fight while it was on.
--------------------------------------------------------------------------------

-- w.hidden: what C_Secrets.ShouldAurasBeSecret answers (a function: call it).
local function Restricted(w, env)
	w.hidden = false
	env.C_Secrets = { ShouldAurasBeSecret = function()
		if type(w.hidden) == "function" then return w.hidden() end
		return w.hidden
	end }
end

-- On and read, then not found while the game says hidden, then the fight.
local function HiddenThenFight(w, ns, hidden)
	w.combat, w.hidden = false, false
	w.auras["Arcane Intellect"] = { auraInstanceID = 7, expirationTime = 3700 }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "read: on")
	w.hidden = hidden
	w.auras["Arcane Intellect"] = nil
	ns.UpdateBuffMissing()
	local gap = ns.missingBuffID
	w.combat = true
	ns.UpdateBuffMissing()
	local fight = ns.missingBuffID
	w.combat, w.hidden = false, false
	return gap, fight
end

H.test("auras hidden with no fight flag: not found is not off, then or in the fight", function()
	local w, ns = World(Restricted)
	Keep(ns, { 1459 })
	local gap, fight = HiddenThenFight(w, ns, false)
	H.eq(gap, 1459, "readable and not found: off")
	H.eq(fight, 1459, "and the fight keeps that answer")
	gap, fight = HiddenThenFight(w, ns, true)
	H.eq(gap, nil, "hidden: the last answer, on")
	H.eq(fight, nil, "and on through the fight")
	-- Readable again, and truly gone: off.
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 1459, "readable again, not found: off")
end)

H.test("auras hidden: a buff never seen is not missing", function()
	local w, ns = World(Restricted)
	w.hidden = true
	Keep(ns, { 1459 })
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "hidden, never seen: not missing")
	w.hidden = false
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 1459, "readable: off")
end)

H.test("a secret, failed or missing answer to ShouldAurasBeSecret", function()
	local w, ns = World(Restricted)
	Keep(ns, { 1459 })
	local _, fight = HiddenThenFight(w, ns, function() return w:Hidden() end)
	H.eq(fight, nil, "secret answer: hidden")
	_, fight = HiddenThenFight(w, ns, function() error("no answer") end)
	H.eq(fight, nil, "an error: hidden")
	_, fight = HiddenThenFight(w, ns, function() return nil end)
	H.eq(fight, nil, "no answer: hidden")
	-- A client without the question: a lookup out of a fight is trusted.
	w.env.C_Secrets = nil
	_, fight = HiddenThenFight(w, ns, true)
	H.eq(fight, 1459, "no C_Secrets: not found out of a fight is off")
end)

H.test("the restriction's end reads your buffs again", function()
	local w, ns = World(Restricted)
	Keep(ns, { 1459 })
	w.auras["Arcane Intellect"] = { auraInstanceID = 7, expirationTime = 3700 }
	ns.UpdateBuffMissing()
	w.hidden = true
	w.auras["Arcane Intellect"] = nil   -- gone while hidden
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "hidden: on")
	w.hidden = false
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
	H.eq(ns.missingBuffID, 1459, "the event, readable: off")
end)

H.test("auras hidden: the buff time on the icon is left as it is", function()
	local w, ns = World(Restricted)
	local cleared = 0
	local buff = {
		Clear = function() end, Show = function() end,
		Hide = function() cleared = cleared + 1 end,
		SetCooldownFromDurationObject = function() end,
	}
	ns.HUDini.spells[1] = { spellID = 1459 }
	ns.HUDini.icons[1] = { buff = buff }
	w.hidden = true
	ns.UpdateIconAuras()
	H.eq(cleared, 0, "hidden: not cleared")
	w.hidden = false
	ns.UpdateIconAuras()
	H.eq(cleared, 1, "readable, not found: cleared")
end)

--------------------------------------------------------------------------------
-- The grid, and a cast that counts as on
--------------------------------------------------------------------------------

H.test("a secret spell name on the grid is skipped", function()
	local w, ns = World()
	w.names[1460] = "Arcane Intellect"   -- a second rank
	Keep(ns, { 1460 })
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 1460, "plain: the grid's icon")
	w.names[1460] = w:Once("Arcane Intellect")
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 1459, "secret: found by name, off the grid")
end)

H.test("a secret cast, or a secret name of it, counts as no cast", function()
	local w, ns = World()
	w.names[1461] = "Arcane Intellect"   -- a second rank
	Keep(ns)
	local function CastInAFight()
		w.combat = false
		ns.UpdateBuffMissing()
		w.combat = true
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1461)
		ns.UpdateBuffMissing()
		return ns.missingBuffID
	end
	H.eq(CastInAFight(), nil, "plain: on")
	w.secret[1461] = true
	H.eq(CastInAFight(), 1459, "secret spell: still off")
	w.secret[1461] = nil
	w.names[1461] = w:Once("Arcane Intellect")
	H.eq(CastInAFight(), 1459, "secret name: still off")
end)

--------------------------------------------------------------------------------
-- Weapon buffs and bait
--------------------------------------------------------------------------------

local function Tooltip(w, lines)
	local rows = {}
	for i, text in ipairs(lines) do rows[i] = { leftText = text } end
	w.env.C_TooltipInfo = { GetInventoryItem = function() return { lines = rows } end }
end

H.test("a secret tooltip line cannot say the pole has no bait", function()
	local w, ns = World()
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	Tooltip(w, { "Fishing Pole", "Odd line" })
	H.eq(ns.BaitMissing(), true, "plain: no bait")
	w.secret["Odd line"] = true
	H.eq(ns.BaitMissing(), false, "secret: cannot say")
end)

H.test("a secret enchant answer on the pole is not taken as bait", function()
	local w, ns = World(function(w, env)
		env.GetWeaponEnchantInfo = function() return w.lure end
	end)
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	Tooltip(w, { "Fishing Pole" })
	w.lure = "lure"
	H.eq(ns.BaitMissing(), false, "plain: bait")
	w.secret.lure = true
	H.eq(ns.BaitMissing(), true, "secret: the tooltip says no bait")
end)

-- A shaman who knows Rockbiter Weapon, with a sword in the main hand.
local function WeaponWorld(setup)
	local w, ns = World(function(w, env)
		w.class, w.className = "TESTER", "Tester"
		w.names[8017], w.byName["Rockbiter Weapon"] = "Rockbiter Weapon", 8017
		env.GetWeaponEnchantInfo = function() return w.enchant() end
		if setup then setup(w, env) end
	end)
	ns.RegisterClass("TESTER", { weaponBuff = { "Rockbiter Weapon" } })
	w:holdItem(16, 2000, 2, 7, "Sword")
	Tooltip(w, { "Sword" })
	return w, ns
end

H.test("a secret no-enchant answer cannot say the weapon has no buff", function()
	local w, ns = WeaponWorld()
	w.enchant = function() return false end
	H.eq(ns.WeaponBuffMissing(), true, "plain: missing")
	w.enchant = w:Once(false)
	H.eq(ns.WeaponBuffMissing(), false, "secret: cannot say")
end)

H.test("auras hidden: the weapon buff cannot be called missing (TICK-0125)", function()
	local w, ns = WeaponWorld(Restricted)
	w.enchant = function() return false end
	H.eq(ns.WeaponBuffMissing(), true, "readable, no buff: missing")
	w.hidden = true
	H.eq(ns.WeaponBuffMissing(), false, "hidden: cannot say")
end)

H.test("/hud debug weapon writes secret for a secret answer, and throws nothing", function()
	local w, ns = WeaponWorld()
	w.enchant = function() return 3600001 end
	local function Line(start)
		for _, line in ipairs(ns.WeaponBuffDetail()) do
			if line:sub(1, #start) == start then return line end
		end
	end
	H.ok(Line("GetWeaponEnchantInfo"):find("3600001", 1, true), "plain: the answer")
	w.secret[3600001] = true
	H.eq(Line("GetWeaponEnchantInfo"), "GetWeaponEnchantInfo: true, secret", "secret: secret")

	w.index["HELPFUL"] = { { name = "Lightning Shield", spellId = 324 } }
	H.eq(Line("Buffs on you"), "Buffs on you: Lightning Shield (324)", "plain: the buff")
	w.secret[324] = true
	H.eq(Line("Buffs on you"), "Buffs on you: Lightning Shield (nil)", "secret spell ID: nil")
	w.secret[324], w.secret["Lightning Shield"] = nil, true
	H.eq(Line("Buffs on you"), "Buffs on you: secret", "secret name: secret")
end)
