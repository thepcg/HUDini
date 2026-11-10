-- Buffs where only one of a group can be on (a Mage's armors, a Warlock's
-- Demon Skin and Demon Armor). Auras.lua learns each one you cast, so
-- without the class file's auraMap the one you are not wearing is always
-- missing, and the HUD never hides.

-- token, class name, then a buff and another of its group.
local CASES = {
	{ "MAGE",    "Mage",    "Frost Armor",         "Ice Armor" },
	{ "MAGE",    "Mage",    "Mage Armor",          "Frost Armor" },
	{ "MAGE",    "Mage",    "Dampen Magic",        "Amplify Magic" },
	{ "WARLOCK", "Warlock", "Demon Armor",         "Demon Skin" },
	-- The Detect Invisibility group is never learned at all (TICK-0064):
	-- tools/tests/test_one_job.lua.
}

for _, case in ipairs(CASES) do
	local token, className, a, b = case[1], case[2], case[3], case[4]
	H.test(className .. ": in " .. a .. ", " .. b .. " is not missing", function()
		local NAMES = { [1] = a, [2] = b }
		local w = H.world()
		w.class, w.className = token, className
		local env = w.env
		env.C_Spell.GetSpellName = function(id) return NAMES[id] end
		env.C_Spell.GetSpellInfo = function(name)
			for id, n in pairs(NAMES) do
				if n == name then return { spellID = id } end
			end
		end
		env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end
		local auras = { [a] = 1800, [b] = 1800 }
		env.C_UnitAuras.GetAuraDuration = function() return nil end
		env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
			local d = auras[name]
			if d then return { auraInstanceID = 7, duration = d, expirationTime = 0 } end
		end
		local ns = w:loadAddon()
		ns.HUDini.spells = { { spellID = 1, row = 0, col = 0 }, { spellID = 2, row = 0, col = 1 } }

		ns.UpdateBuffMissing()
		local learned = ns.ClassDB().buffSpells or {}
		H.ok(learned[a] and learned[b], "both learned")

		auras[b] = nil
		ns.UpdateBuffMissing()
		H.eq(ns.buffMissing, false, a .. " on, " .. b .. " off")

		auras[a], auras[b] = nil, 1800
		ns.UpdateBuffMissing()
		H.eq(ns.buffMissing, false, b .. " on, " .. a .. " off")

		auras[b] = nil
		ns.UpdateBuffMissing()
		H.eq(ns.buffMissing, true, "none on")
	end)
end
