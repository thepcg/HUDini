-- Class file trackBuff (TICK-0204, D-047): a buff the class file names
-- counts as tracked from the start, as if HUDini had seen it on you, once
-- you know its spell. One you clear stays cleared.

local FORT, SPIRIT, FROST, ICE, BREATH = 1243, 14752, 168, 7302, 5697
local NAMES = {
	[FORT] = "Power Word: Fortitude", [SPIRIT] = "Divine Spirit",
	[FROST] = "Frost Armor", [ICE] = "Ice Armor", [BREATH] = "Unending Breath",
}

-- A Priest who knows the spells in `known`, with the buffs in `on`
-- (id -> duration). No grid icons: every tracked buff is off the grid.
local function Priest(profile, known)
	local w = H.world()
	w.class, w.className = "PRIEST", "Priest"
	local env = w.env
	w.known = known or { [FORT] = true }
	w.on = {}
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id, name = n } end
		end
	end
	env.IsPlayerSpell = function(id) return w.known[id] == true end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		for id, n in pairs(NAMES) do
			local d = w.on[id]
			if n == name and d then
				return { auraInstanceID = id, name = n, spellId = id, duration = d,
					expirationTime = d > 0 and 5000 or 0 }
			end
		end
	end
	-- Your buffs by index, for LearnFromYourBuffs.
	env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
		local list = {}
		for id in pairs(w.on) do list[#list + 1] = id end
		table.sort(list)
		local id = list[i]
		if id then return env.C_UnitAuras.GetAuraDataBySpellName("player", NAMES[id]) end
	end
	local ns = w:loadAddon()
	ns.HUDini.spells = {}
	ns.RegisterClass("PRIEST", profile or { trackBuff = { "Power Word: Fortitude" } })
	-- The load ran with the real Priest file, which has its own trackBuff:
	-- start from no saved class choices, as a new character does.
	w.env.HUDiniDB.classes = nil
	return ns, w
end

local function Learned(ns) return ns.ClassDB().buffSpells or {} end

H.test("trackBuff: a buff never cast counts as tracked, and missing out of a fight", function()
	local ns, w = Priest()
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Power Word: Fortitude"], true, "tracked, no length known")
	H.eq(ns.buffMissing, true, "missing, out of a fight")
	H.eq(ns.missingBuffID, FORT, "the Fortitude icon")
	w.on[FORT] = 1800
	ns.UpdateBuffMissing()
	H.eq(ns.buffMissing, false, "cast: the icon goes")
end)

H.test("trackBuff: a cleared buff is not put back; seen on you again, it is learned as before", function()
	local ns, w = Priest()
	ns.UpdateBuffMissing()
	ns.BuffsCommand("clear", function() end)
	H.eq(Learned(ns)["Power Word: Fortitude"], nil, "cleared")
	ns.UpdateBuffMissing()
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Power Word: Fortitude"], nil, "still cleared")
	H.eq(ns.buffMissing, false, "no icon")

	-- A /reload: the saved file stays, the addon loads again.
	local saved = w.env.HUDiniDB
	local ns2, w2 = Priest()
	w2.env.HUDiniDB = saved
	ns2.UpdateBuffMissing()
	H.eq(Learned(ns2)["Power Word: Fortitude"], nil, "after a reload: still cleared")
	H.eq(ns2.buffMissing, false, "no icon after a reload")

	ns.BuffsCommand("", function() end)
	w.on[FORT] = 1800
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Power Word: Fortitude"], 1800, "seen on you: learned with its length")
end)

H.test("trackBuff: /hud buffs forget one stays forgotten", function()
	local ns = Priest()
	ns.UpdateBuffMissing()
	ns.BuffsCommand("forget Power Word: Fortitude", function() end)
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Power Word: Fortitude"], nil, "forgotten")
end)

H.test("trackBuff: a spell you do not know is not tracked; learned later, it is", function()
	local ns, w = Priest({ trackBuff = { "Power Word: Fortitude", "Divine Spirit" } })
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Divine Spirit"], nil, "not known: not tracked")
	w.on[FORT] = 1800
	w.known[SPIRIT] = true
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Divine Spirit"], true, "learned: tracked")
	H.eq(ns.missingBuffID, SPIRIT, "and missing")
end)

H.test("trackBuff: a saved length stays, and D-033 follows it", function()
	local ns, w = Priest({ trackBuff = { "Frost Armor" } }, { [FROST] = true })
	ns.ClassDB().buffSpells = { ["Frost Armor"] = 600 }
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Frost Armor"], 600, "the length HUDini read stays")
	H.eq(ns.buffMissing, false, "a 10-minute buff: not missing out of a fight")
	w.on[FROST] = 600
	ns.UpdateBuffMissing()
	w.on[FROST] = nil
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Frost Armor"], 600)
end)

H.test("trackBuff: a group in auraMap counts as one", function()
	local ns, w = Priest({
		trackBuff = { "Frost Armor", "Ice Armor" },
		auraMap = { ["Frost Armor"] = { "Ice Armor" }, ["Ice Armor"] = { "Frost Armor" } },
	}, { [FROST] = true, [ICE] = true })
	w.on[ICE] = 1800
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Frost Armor"], true, "both tracked")
	H.eq(Learned(ns)["Ice Armor"], 1800, "the one on you, with the length read")
	H.eq(ns.buffMissing, false, "one of the group on: nothing missing")
	w.on[ICE] = nil
	ns.UpdateBuffMissing()
	H.eq(ns.buffMissing, true, "none on: missing")
end)

H.test("trackBuff: a buff for one job is never tracked; no field tracks nothing", function()
	local ns = Priest({ trackBuff = { "Unending Breath" } }, { [BREATH] = true })
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Unending Breath"], nil, "one job (TICK-0064)")
	H.eq((ns.ClassDB().buffSeeded or {})["Unending Breath"], nil, "not even put in once")
	local ns2 = Priest({}, { [FORT] = true })
	ns2.UpdateBuffMissing()
	H.eq(next(Learned(ns2)), nil, "no trackBuff: as before")
	H.eq(ns2.buffMissing, false)
end)
