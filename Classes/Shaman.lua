--[[--------------------------------------------------------------------------
	HUDini - Shaman

	Data only. See Classes.lua for what each field means.
	Levels and IDs are WoW Forever's (talentsforever.com data, 2026-11-18;
	TICK-0177). Forever's cap is 60.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- Lightning Shield (level 8) lasts 10 minutes with 3 charges, so it counts as
-- missing only in a fight (TICK-0144). It is learned as a buff only after you
-- cast it with the spell on your bars, so keepUp names it for every Shaman.
-- Water Shield (a Resto talent at 20) replaces it, one shield at a time; it
-- joins keepUp, with an auraMap pair, in TICK-0194.
-- A totem's buff is never learned: it has its own spell ID, which you do not
-- know, and the totem keeps it up.
-- Not on Forever: Heroism, Bloodlust, Wind Shear, Cleanse Spirit, Earth
-- Shield, Earthliving Weapon, Shamanistic Rage.
ns.RegisterClass("SHAMAN", {
	interrupt  = "Earth Shock",               -- level 4; 6 s cooldown
	dispel     = { Poison  = "Cure Poison",   -- level 16
	               Disease = "Cure Disease" }, -- level 22
	purge      = "Purge",                     -- levels 12 and 32
	keepUp     = { "Lightning Shield" },
	resource   = { aura = "Lightning Shield", max = 3 },
	-- Know any one of these, and each weapon in your hands needs one on it.
	-- Each lasts 60 minutes on Forever. Levels 1, 10, 20, 30.
	weaponBuff = { "Rockbiter Weapon", "Flametongue Weapon",
		"Frostbrand Weapon", "Windfury Weapon" },
	auraMap    = {},
	powers     = { "MANA" },
	-- A Lightning Shield used up in a fight is worth a sound (D-047,
	-- TICK-0189). It lasts 10 minutes, so it drops in a fight only when its
	-- 3 charges are used up.
	keepUpSoundOn = true,
	-- Cooldown ready alerts (TICK-0157): offered on the "Your class" page,
	-- a row only for a spell you know (TICK-0201).
	readyAlert = {
		"Nature's Swiftness",   -- Resto talent, level 30, 3 min
		"Lightning Mastery",    -- Elemental talent, level 40, 3 min
		"Rage of the Farseer",  -- Enhancement talent, level 40, 3 min
		"Mana Tide Totem",      -- Resto talent, level 25, 5 min
		"Reincarnation",        -- level 30, 1 hour; its Ankh is TICK-0182
	},
	-- The talent cooldowns you plan a fight around start as the bell
	-- (D-047). Not Reincarnation: it is ready again an hour after a death,
	-- which a bell adds little to; its row is there to turn on.
	readyAlertOn = { "Nature's Swiftness", "Lightning Mastery",
		"Rage of the Farseer", "Mana Tide Totem" },
	-- Reincarnation uses an Ankh. With none in your bags, you cannot come
	-- back where you died (TICK-0189). Never wakes the HUD. Item 17030 is
	-- Classic Era's; /hud debug aura proves it on Forever.
	missingItem = {
		{ key = "ankh", needs = { "Reincarnation" }, items = { 17030 }, on = true },
	},
	-- Rank 1 of each.
	ids = {
		["Earth Shock"]         = 8042,
		["Cure Poison"]         = 526,
		["Cure Disease"]        = 2870,
		["Purge"]               = 370,
		["Lightning Shield"]    = 324,
		["Rockbiter Weapon"]    = 8017,
		["Flametongue Weapon"]  = 8024,
		["Frostbrand Weapon"]   = 8033,
		["Windfury Weapon"]     = 8232,
		["Nature's Swiftness"]  = 16188,
		["Lightning Mastery"]   = 16166,
		["Rage of the Farseer"] = 425336,
		["Mana Tide Totem"]     = 16190,
		["Reincarnation"]       = 20608, -- needs an Ankh (TICK-0182)
		-- Every totem needs its tool item in your bags: know any one of a
		-- group, and you need that item. No missingItem row for them yet;
		-- /hud debug ids checks these. Mana Tide Totem is above.
		-- Earth Totem
		["Stoneskin Totem"]          = 8071,  -- level 4
		["Earthbind Totem"]          = 2484,  -- level 6
		["Stoneclaw Totem"]          = 5730,  -- level 8
		["Strength of Earth Totem"]  = 8075,  -- level 10
		["Tremor Totem"]             = 8143,  -- level 18
		-- Fire Totem
		["Searing Totem"]            = 3599,  -- level 10
		["Frost Resistance Totem"]   = 8181,  -- level 24
		["Magma Totem"]              = 8190,  -- level 26
		["Flametongue Totem"]        = 8227,  -- level 28
		-- Water Totem
		["Healing Stream Totem"]     = 5394,  -- level 20
		["Poison Cleansing Totem"]   = 8166,  -- level 22
		["Mana Spring Totem"]        = 5675,  -- level 26
		["Fire Resistance Totem"]    = 8184,  -- level 28
		["Disease Cleansing Totem"]  = 8170,  -- level 38
		-- Air Totem
		["Grounding Totem"]          = 8177,  -- level 30
		["Nature Resistance Totem"]  = 10595, -- level 30
		["Windfury Totem"]           = 8512,  -- level 32
		["Sentry Totem"]             = 6495,  -- level 34
		["Windwall Totem"]           = 15107, -- level 36
		["Grace of Air Totem"]       = 8835,  -- level 42
	},
})
