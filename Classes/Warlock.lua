--[[--------------------------------------------------------------------------
	HUDini - Warlock

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- Spell Lock and Devour Magic are your Felhunter's spells: they count only
-- while it is out. No dispel: Devour Magic can also clean you, but the
-- game's "you can dispel this" aura filter likely looks at your own spells
-- only. No resource: Soul Shards are items. No keepUp: Demon Armor lasts
-- 30 minutes, so Auras.lua already learns it as a buff to reapply.
--
-- Only one buff of each group can be on, so each counts as on while any
-- other of its group is. Without that, the armor you are not wearing is
-- always "missing", and the HUD never hides.
local GROUPS = {
	{ "Demon Skin", "Demon Armor" },
	{ "Detect Lesser Invisibility", "Detect Invisibility",
		"Detect Greater Invisibility" },
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

ns.RegisterClass("WARLOCK", {
	interrupt = "Spell Lock",   -- Felhunter
	purge     = "Devour Magic", -- Felhunter: eats a magic buff off a foe
	auraMap   = auraMap,
	powers    = { "MANA" },
})
