--[[--------------------------------------------------------------------------
	HUDini - Warrior

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

ns.RegisterClass("WARRIOR", {
	-- Pummel: Berserker Stance, level 38. Shield Bash: a shield, in Battle or
	-- Defensive Stance, level 12. The outline uses the one you can cast now.
	interrupt = { "Pummel", "Shield Bash" },
	-- Two minutes, so Auras.lua never learns it as a buff to reapply.
	keepUp    = { "Battle Shout" },
	powers    = { "RAGE" },
})
