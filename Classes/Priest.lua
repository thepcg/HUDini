--[[--------------------------------------------------------------------------
	HUDini - Priest

	Data only. See Classes.lua for what each field means.
	Levels and IDs are WoW Forever's (talentsforever.com data, 2026-11-18).
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- Power Word: Shield is no combat buff: Weakened Soul blocks a recast for
-- 15 sec, so it would always be "missing" in a fight.
ns.RegisterClass("PRIEST", {
	interrupt = "Silence",                -- Shadow talent, level 30; interrupts 3 sec on Forever
	-- Cure Disease, not Abolish Disease: one spell per type, and Cure Disease
	-- works from level 14 (Abolish Disease comes at 32).
	dispel    = { Magic = "Dispel Magic", -- level 18
	              Disease = "Cure Disease" }, -- level 14
	purge     = "Dispel Magic",           -- cast on a foe, it takes a magic buff
	powers    = { "MANA" },
	-- Inner Fire is in keepUp, so a fight shows it missing from level 12,
	-- even before HUDini has seen it on you once (TICK-0211). It shares one
	-- watch with the tracked buff Auras.lua learns: no second icon.
	keepUp    = { "Inner Fire" },             -- level 12, 10 min or 20 charges
	-- Tracked buffs from the start (TICK-0204): each shows missing even
	-- before HUDini has seen it on you once. Fortitude and Divine Spirit last
	-- 1 hour, so they count in and out of a fight; Prayer of Fortitude and
	-- Prayer of Spirit count for them (Classes.lua). Shadowguard lasts 10 min:
	-- in a fight only, once HUDini has read its length on you (D-033).
	-- Not Touch of Weakness: it ends at the first melee hit.
	trackBuff = {
		"Power Word: Fortitude", -- level 1, 1 hour
		"Divine Spirit",         -- level 30, 1 hour
		"Shadowguard",           -- Troll, level 20, 10 min or 3 charges
	},
	-- Cooldown ready alerts (TICK-0157), offered first in the Cooldowns
	-- group. A row shows only for a spell you know (TICK-0201), so each
	-- race's own spells can be here: two per race, at levels 10 and 20.
	readyAlert = {
		"Power Infusion",    -- Discipline talent, level 40, 3 min
		"Inner Focus",       -- Discipline talent, level 20, 3 min
		"Fear Ward",         -- every Priest, level 20, 3 min
		"Psychic Scream",    -- every Priest, level 14, 30 sec
		"Desperate Prayer",  -- Dwarf, 10 min
		"Chastise",          -- Dwarf, 2 min (a root)
		"Divine Grace",      -- Human, 10 min
		"Feedback",          -- Human, 3 min
		"Elune's Grace",     -- Night Elf, 5 min
		"Contingency Plan",  -- Gnome, 10 min
		"Confounding Flash", -- Gnome, 2 min (a confuse)
		"Dark Sacrifice",    -- Undead, 10 min
	},
	-- These start as the bell until you save a choice (D-047): the two big
	-- talents, and each race's 10-minute spell, are easy to forget.
	readyAlertOn = {
		"Power Infusion", "Inner Focus",
		"Desperate Prayer", "Divine Grace", "Contingency Plan", "Dark Sacrifice",
	},
	-- The buff-missing sound starts on: Inner Fire loses a charge to each
	-- hit, so it drops in a melee fight (D-047, TICK-0194).
	keepUpSoundOn = true,
	-- An icon by your health bar, out of a fight, when the bags hold none of
	-- a row's items (TICK-0182). Only the first missing row shows. The item
	-- IDs are Classic Era's; `/hud debug aura` proves them on Forever.
	missingItem = {
		-- Prayer of Fortitude takes a Holy Candle (rank 1, level 48) or a
		-- Sacred Candle (rank 2, level 60); either lets you cast a rank.
		{ key = "holyCandle", needs = { "Prayer of Fortitude" },
		  items = { 17028, 17029 }, on = true },  -- Holy Candle, Sacred Candle
		-- Prayer of Spirit (60) and Prayer of Shadow Protection (56) take
		-- only a Sacred Candle.
		{ key = "sacredCandle", needs = { "Prayer of Spirit", "Prayer of Shadow Protection" },
		  items = { 17029 }, on = true },         -- Sacred Candle
		-- Off: Levitate (level 34) is a travel spell, not one for a group.
		{ key = "lightFeather", needs = { "Levitate" },
		  items = { 17056 }, on = false },        -- Light Feather
	},
	-- Forever spell IDs (rank 1), for non-English clients.
	-- locale: skip the game's spell names
	ids = {
		["Inner Fire"] = 588, ["Silence"] = 15487, ["Dispel Magic"] = 527, ["Cure Disease"] = 528,
		["Power Infusion"] = 10060, ["Inner Focus"] = 14751, ["Fear Ward"] = 6346,
		["Psychic Scream"] = 8122, ["Desperate Prayer"] = 13908, ["Chastise"] = 1277331,
		["Divine Grace"] = 1277370, ["Feedback"] = 13896, ["Elune's Grace"] = 2651,
		["Contingency Plan"] = 1277462, ["Confounding Flash"] = 1277455,
		["Dark Sacrifice"] = 1277324, ["Shadowguard"] = 18137,
		["Prayer of Fortitude"] = 21562, ["Prayer of Spirit"] = 27681,
		["Prayer of Shadow Protection"] = 27683, ["Levitate"] = 1706,
	},
	-- locale: end
})
