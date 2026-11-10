--[[--------------------------------------------------------------------------
	HUDini - Priest

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- No keepUp: Inner Fire lasts 10 minutes, so Auras.lua already learns it as
-- a buff to reapply.
ns.RegisterClass("PRIEST", {
	interrupt = "Silence",                -- Shadow talent
	dispel    = { Magic = "Dispel Magic", -- level 18
	              Disease = "Cure Disease" }, -- level 14
	purge     = "Dispel Magic",           -- cast on a foe, it takes a magic buff
	powers    = { "MANA" },
})
