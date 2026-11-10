--[[--------------------------------------------------------------------------
	HUDini - Druid

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

ns.RegisterClass("DRUID", {
	-- Bear Form, level 14; a stun stops the cast. Out of Bear Form it cannot
	-- be cast, so there is no outline. Feral Charge (talent) also interrupts,
	-- but it needs 8 yards: in melee it would outline a spell you cannot cast.
	interrupt = "Bash",
	dispel    = { Curse  = "Remove Curse", -- level 24
	              Poison = "Cure Poison" },  -- level 14
	-- Combo points count only in Cat Form, the one form with energy.
	resource  = { power = "ComboPoints", onlyWith = "ENERGY" },
	powers    = { "MANA", "RAGE", "ENERGY" },
})
