-- Paladin class file (TICK-0023): only one of your auras is on at a time, and
-- only one of your blessings, so the one you are not using is never missing.

local NAMES = {
	[1] = "Devotion Aura", [2] = "Retribution Aura",          -- no end
	[3] = "Blessing of Might", [4] = "Blessing of Wisdom",    -- 5 minutes
}
local DURATION = { [1] = 0, [2] = 0, [3] = 300, [4] = 300 }

local function Paladin()
	local w = H.world()
	w.class, w.className = "PALADIN", "Paladin"
	local env = w.env
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id } end
		end
	end
	env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end
	local on = {}
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		for id, n in pairs(NAMES) do
			if n == name and on[id] then
				local d = DURATION[id]
				return { auraInstanceID = id, duration = d, expirationTime = d > 0 and 2000 or 0 }
			end
		end
	end
	local ns = w:loadAddon()
	ns.HUDini.spells = {}
	for id in pairs(NAMES) do ns.HUDini.spells[#ns.HUDini.spells + 1] = { spellID = id, row = 0, col = id } end
	return ns, on
end

-- Use each buff once, so all four are learned, then put on only the ones given.
local function After(ns, on, ...)
	for id in pairs(NAMES) do on[id] = true end
	ns.UpdateBuffMissing()
	for id in pairs(NAMES) do on[id] = nil end
	for i = 1, select("#", ...) do on[select(i, ...)] = true end
	ns.UpdateBuffMissing()
	return ns.buffMissing, ns.ClassDB().buffSpells or {}
end

H.test("a paladin learns its auras and blessings as buffs to reapply", function()
	local ns, on = Paladin()
	local _, learned = After(ns, on, 1, 3)
	for _, name in pairs(NAMES) do H.ok(learned[name], name .. " learned") end
end)

H.test("a paladin in one aura with one blessing misses nothing", function()
	local ns, on = Paladin()
	H.eq((After(ns, on, 2, 4)), false, "Retribution and Wisdom on")
	ns, on = Paladin()
	H.eq((After(ns, on, 1, 3)), false, "Devotion and Might on")
end)

H.test("a paladin with no aura, or no blessing, misses one", function()
	local ns, on = Paladin()
	H.eq((After(ns, on, 4)), true, "no aura")
	ns, on = Paladin()
	H.eq((After(ns, on, 2)), true, "no blessing")
end)
