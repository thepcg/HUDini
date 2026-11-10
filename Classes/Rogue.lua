--[[--------------------------------------------------------------------------
	HUDini - Rogue

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

ns.RegisterClass("ROGUE", {
	interrupt = "Kick",                     -- level 12
	resource  = { power = "ComboPoints" },  -- pips: the game's own maximum
	-- Poisons are items, not spells, so weaponBuff has nothing to know.
	powers    = { "ENERGY" },
})
