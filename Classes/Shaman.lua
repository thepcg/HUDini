--[[--------------------------------------------------------------------------
	HUDini - Shaman

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- No keepUp: Lightning Shield lasts 10 minutes, so Auras.lua already learns
-- it as a buff to reapply. A totem's buff should not be learned either: the
-- totem casts it, not you. Not seen in the game yet (TICK-0014 step).
ns.RegisterClass("SHAMAN", {
	interrupt  = "Earth Shock",               -- level 4
	dispel     = { Poison  = "Cure Poison",   -- level 16
	               Disease = "Cure Disease" }, -- level 22
	purge      = "Purge",                     -- level 12
	-- Know any one of these, and each weapon in your hands needs one on it.
	weaponBuff = { "Rockbiter Weapon", "Flametongue Weapon",
		"Frostbrand Weapon", "Windfury Weapon" },
	auraMap    = {},
	powers     = { "MANA" },
})
