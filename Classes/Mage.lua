--[[--------------------------------------------------------------------------
	HUDini - Mage

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- Only one buff of each group can be on (the Armor tooltips say so), so
-- each counts as on while any other of its group is. Without that, the
-- armor you are not wearing is always "missing", and the HUD never hides.
-- Arcane Intellect and Arcane Brilliance are paired for every class in
-- Classes.lua.
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

-- Levels and IDs are from Forever's own spell data (talentsforever.com
-- export of 2026-11-10, beta client 1.60.1.70755, trainer checked in
-- game; CC BY 4.0). Each ID is the first rank: a name covers every rank.
ns.RegisterClass("MAGE", {
	interrupt = "Counterspell",                   -- level 24
	-- Level 18. Forever has no Remove Curse.
	dispel    = { Curse = "Remove Lesser Curse" },
	-- No purge: Forever has no Spellsteal.
	-- The shield in a fight (TICK-0209, DK's ask): the first one you know
	-- shows. Ice Barrier is a Frost talent at 40 (1 min, 30 sec cooldown);
	-- Mana Shield (20) is every other Mage's, so a Mage of 20 to 39 and a
	-- Fire or Arcane Mage see Mana Shield. Arcane Intellect and your armor
	-- are learned buffs (Auras.lua), not this list: one of them up would
	-- hide the icon for the other.
	keepUp    = { "Ice Barrier", "Mana Shield" },
	-- Tracked from the start (TICK-0204, DK's ask), not only after HUDini
	-- sees them on you: Arcane Intellect (1, 1 hour; Arcane Brilliance
	-- counts too, Classes.lua) and your armor (Frost Armor 1, Ice Armor 30,
	-- Mage Armor 34; 30 min). Each goes in when you know it. The armors are
	-- a group (auraMap): one on counts for all, so you choose which to
	-- wear. With none on, the icon is the armor on your bars, else the
	-- first by name (Frost Armor). Forever has no fire armor.
	trackBuff = { "Arcane Intellect", "Frost Armor", "Ice Armor", "Mage Armor" },
	resource  = nil,                              -- Retail's Icicles is not on Forever
	auraMap   = auraMap,
	powers    = { "MANA" },
	-- Cooldown ready alerts (TICK-0157), offered on the "Your class" page:
	-- Evocation 20 (8 min), Ice Block 25, Cold Snap 30, Presence of Mind 30,
	-- Arcane Power 40, Combustion 40 (talents). Each off until you turn it
	-- on, except Evocation.
	readyAlert = {
		"Evocation", "Ice Block", "Cold Snap",
		"Presence of Mind", "Arcane Power", "Combustion",
	},
	-- Evocation starts as the bell (D-047, DK's ask): an 8 minute cooldown
	-- you forget is mana you lose. You hear it only once you learn it (20).
	readyAlertOn = { "Evocation" },
	-- The buff sound starts on (TICK-0209: DK vetoed "no Mage buff
	-- sound"). It plays when your shield, Arcane Intellect or armor icon
	-- turns on.
	keepUpSoundOn = true,
	-- No mana gem (TICK-0182): a gem is free mana in a fight, and conjured
	-- items vanish after 15 minutes logged out. One row, not one per gem:
	-- any gem in your bags counts, so a Mage who carries a Ruby hears
	-- nothing about the Agate. Conjure Mana Agate (28) is the first gem
	-- spell, and you keep it when you learn the next ones. Item IDs are
	-- Classic's (Mana Agate 5514, Jade 5513, Citrine 8007, Ruby 8008):
	-- /hud debug aura proves them on Forever.
	-- No water (TICK-0210): a Mage drinks after most fights, so water is
	-- the first row and the icon shows it before the gem. Conjure Water is
	-- level 4, Conjure Food 6; each has 7 ranks under one name, and any of
	-- the 7 items counts. Food is off until you turn it on: most Mages eat
	-- less than they drink. Item IDs are Classic's, Conjured Water to
	-- Conjured Crystal Water and Conjured Muffin to Conjured Cinnamon
	-- Roll: /hud debug aura proves them on Forever, with the gems.
	missingItem = {
		{ key = "water", make = "Conjure Water",
			items = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 }, on = true },
		{ key = "food", make = "Conjure Food",
			items = { 5349, 1113, 1114, 1487, 8075, 8076, 22895 }, on = false },
		{ key = "manaGem", make = "Conjure Mana Agate",
			items = { 5514, 5513, 8007, 8008 }, on = true },
	},
	ids = {
		["Counterspell"]        = 2139,
		["Remove Lesser Curse"] = 475,
		["Ice Barrier"]         = 11426,
		["Mana Shield"]         = 1463,
		["Frost Armor"]         = 168,
		["Ice Armor"]           = 7302,
		["Mage Armor"]          = 6117,
		["Amplify Magic"]       = 1008,
		["Dampen Magic"]        = 604,
		["Evocation"]           = 12051,
		["Ice Block"]           = 11958,
		["Cold Snap"]           = 12472,
		["Presence of Mind"]    = 12043,
		["Arcane Power"]        = 12042,
		["Combustion"]          = 11129,
		-- Mana gems, for the missing item alert (TICK-0182): levels 28,
		-- 38, 48, 58. Forever has no "Conjure Mana Gem".
		-- Water and food, for the missing item alert (TICK-0210).
		["Conjure Water"]        = 5504,
		["Conjure Food"]         = 587,
		["Conjure Mana Agate"]   = 759,
		["Conjure Mana Jade"]    = 3552,
		["Conjure Mana Citrine"] = 10053,
		["Conjure Mana Ruby"]    = 10054,
	},
})
