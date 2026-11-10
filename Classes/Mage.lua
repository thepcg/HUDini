--[[--------------------------------------------------------------------------
	HUDini - Mage

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- Only one buff of each group can be on, so each counts as on while any
-- other of its group is. Without that, the armor you are not wearing is
-- always "missing", and the HUD never hides. Arcane Intellect and Arcane
-- Brilliance are paired for every class in Classes.lua.
local GROUPS = {
	{ "Frost Armor", "Ice Armor", "Mage Armor" },
	{ "Amplify Magic", "Dampen Magic" },
}

local auraMap = {}
for _, group in ipairs(GROUPS) do
	for _, spell in ipairs(group) do
		auraMap[spell] = {}
		for _, other in ipairs(group) do
			if other ~= spell then tinsert(auraMap[spell], other) end
		end
	end
end

ns.RegisterClass("MAGE", {
	interrupt = "Counterspell",                   -- level 24 on Forever
	dispel    = { Curse = "Remove Lesser Curse" }, -- Forever's name, level 18
	purge     = { spell = "Spellsteal", stealable = true }, -- not in Forever's spellbook yet
	keepUp    = { "Ice Barrier", "Mana Shield" },  -- talent at 40, and level 20
	resource  = nil,                              -- Retail's Icicles is not on Forever
	auraMap   = auraMap,
	powers    = { "MANA" },
})
