--[[--------------------------------------------------------------------------
	HUDini - Druid

	Data only. See Classes.lua for what each field means.

	Levels and IDs: talentsforever.com/data.json (Forever beta client
	1.60.1.70755, 2026-11-18). Cap is 60.

	No keepUp: Mark of the Wild (level 1, 1 hour) and Thorns (level 6,
	10 min) are tracked buffs (trackBuff below), each with its own icon;
	one keepUp list would show an icon only when both are gone. Omen of Clarity
	(level 20) is a passive on Forever, not a buff. No purge: Soothe Animal
	is not one.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

ns.RegisterClass("DRUID", {
	-- Bear Form, level 14; a stun stops the cast. Out of Bear Form it cannot
	-- be cast, so there is no outline. Feral Charge (talent) also interrupts,
	-- but it needs 8 yards: in melee it would outline a spell you cannot cast.
	interrupt = "Bash",
	dispel    = { Curse  = "Remove Curse", -- level 24
	              Poison = "Cure Poison" },  -- level 14 (class quest); Abolish
	-- Poison (26) does not replace it, so Cure Poison stays known.
	-- Combo points count only in Cat Form, the one form with energy.
	resource  = { power = "ComboPoints", onlyWith = "ENERGY" },
	powers    = { "MANA", "RAGE", "ENERGY" },
	-- Cooldown ready alerts (TICK-0157): a row for each one you know.
	-- Rebirth (20, 30 min), Nature's Swiftness (30, talent, 3 min),
	-- Innervate (40, 6 min), Barkskin (44, 1 min), Tranquility (30, 5 min),
	-- Frenzied Regeneration (36, bear, 3 min), Challenging Roar (28, bear,
	-- 10 min), Dash (26, cat, 5 min). Enrage and Nature's Grasp (1 min)
	-- are left out: they would ring all the time.
	readyAlert = { "Rebirth", "Nature's Swiftness", "Innervate", "Barkskin",
	               "Tranquility", "Frenzied Regeneration", "Challenging Roar", "Dash" },
	-- These start as the bell (TICK-0183, for DK veto): a 30-min battle res
	-- players forget is back, and the mana of every long fight. The rest
	-- are short or for one role, so each starts off.
	readyAlertOn = { "Rebirth", "Innervate" },
	-- The buff sound starts on (TICK-0214, DK's veto of "no buff sound"): it
	-- plays when Mark of the Wild or Thorns ends in a fight. In Bear or Cat
	-- Form you cannot recast them; that quiet is TICK-0197.
	keepUpSoundOn = true,
	-- Tracked from the day you know them, cast or not (TICK-0204). Thorns
	-- counts out of a fight too until HUDini reads it on you once; then it
	-- counts only in a fight (D-033).
	trackBuff = { "Mark of the Wild", "Thorns" },
	-- Reagents (TICK-0183): talentsforever tooltips name the item, the IDs
	-- are Classic Era ones (Wowhead Classic), not yet proven on Forever.
	missingItem = {
		-- Rebirth fails with no seed. One seed per rank: Maple (20),
		-- Stranglethorn (30), Ashwood (40), Hornbeam (50), Ironwood (60).
		-- Any seed counts, so a low seed hides the icon even when your
		-- top rank needs another one. On: a res that fails costs a wipe.
		{ key = "rebirthSeed", needs = { "Rebirth" },
		  items = { 17034, 17035, 17036, 17037, 17038 }, on = true },
		-- Wild Berries (rank 1, 50), Wild Thornroot (rank 2, 60). Off: a
		-- group buff that a leveler seldom casts (for DK veto).
		{ key = "giftReagent", needs = { "Gift of the Wild" },
		  items = { 17021, 17026 } },
	},
	ids = {
		["Bash"]                  = 5211,
		["Remove Curse"]          = 2782,
		["Cure Poison"]           = 8946,
		["Rebirth"]               = 20484,
		["Nature's Swiftness"]    = 17116,
		["Innervate"]             = 29166,
		["Barkskin"]              = 22812,
		["Tranquility"]           = 740,
		["Frenzied Regeneration"] = 22842,
		["Challenging Roar"]      = 5209,
		["Dash"]                  = 1850,
		["Thorns"]                = 467,
	},
})
