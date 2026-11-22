--[[--------------------------------------------------------------------------
	HUDini - Rogue

	Data only. See Classes.lua for what each field means.

	Levels and IDs: the WoW Forever beta spell data (talentsforever.com
	export, build 1.60.1.70755, 2026-11-10), rank 1 (TICK-0176). The cap is
	level 60.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

ns.RegisterClass("ROGUE", {
	interrupt = "Kick",                     -- level 12; 10 sec cooldown
	resource  = { power = "ComboPoints" },  -- pips: the game's own maximum
	powers    = { "ENERGY" },
	-- The one buff a Rogue keeps up in every fight (level 10, 9-21 sec,
	-- +20% attack speed). Too short for HUDini to learn on its own (under
	-- 5 minutes), so it is named here. Its sound stays off: a fight always
	-- starts with it off, so the sound would ring at every pull.
	keepUp    = { "Slice and Dice" },
	-- Poisons: the Rogue learns a spell that makes each one (the "Poisons"
	-- spellbook tab, from level 20); the poison is an item put on a weapon
	-- for 30 minutes. Knowing a poison spell means each weapon needs one.
	weaponBuff = { "Instant Poison", "Deadly Poison", "Crippling Poison",
		"Mind-numbing Poison", "Wound Poison" },
	-- No keepUpSoundOn: the sound stays off (above).
	-- Cooldown ready alerts (TICK-0157): offered on the "Your class" page
	-- and the Rogue page in HUDini setup. Blade Flurry, Cold Blood and
	-- Preparation are talents: no row until you learn one.
	readyAlert = { "Evasion", "Vanish", "Sprint", "Adrenaline Rush",
		"Blade Flurry", "Cold Blood", "Preparation" },
	-- The two that save a Rogue's life start as the bell (D-047); the
	-- others start off. Your own choice wins once you save one.
	readyAlertOn = { "Evasion", "Vanish" },
	-- Missing items (TICK-0182): an icon by your health bar, out of a
	-- fight, when the bags hold no powder. Vanish fails with no Flash
	-- Powder, and it is the button that saves a Rogue's life, so that row
	-- starts on. Blind is used less, and a Rogue who never casts it would
	-- see the icon all day, so that row starts off. Both are "needs" rows:
	-- the powder is bought, not made, so they never wake the HUD.
	-- Item IDs: Classic Era (Flash Powder 5140, Blinding Powder 5530), not
	-- yet proven on Forever; /hud debug aura names each one with its count.
	missingItem = {
		{ key = "flashPowder",    needs = { "Vanish" }, items = { 5140 }, on = true },
		{ key = "blindingPowder", needs = { "Blind" },  items = { 5530 }, on = false },
	},
	-- Vanish and Blind are in ids for the rows above.
	-- locale: skip the game's spell names
	ids = {
		["Kick"]                = 1766,   -- ranks at 12/26/42/58
		["Slice and Dice"]      = 5171,   -- rank 2: 6774 at 42
		["Evasion"]             = 5277,   -- level 8, 5 min cooldown
		["Vanish"]              = 1856,   -- level 22, rank 2: 1857 at 42; needs Flash Powder
		["Blind"]               = 2094,   -- level 34, 5 min cooldown; needs Blinding Powder
		["Sprint"]              = 2983,   -- level 10, ranks at 10/34/58
		["Adrenaline Rush"]     = 13750,  -- Combat talent, level 40
		["Blade Flurry"]        = 13877,  -- Combat talent, level 30
		["Cold Blood"]          = 14177,  -- Assassination talent, level 25
		["Preparation"]         = 14185,  -- Subtlety talent, level 30
		["Instant Poison"]      = 8681,   -- level 20
		["Deadly Poison"]       = 2835,   -- level 30
		["Crippling Poison"]    = 3420,   -- level 20
		["Mind-numbing Poison"] = 5763,   -- level 24
		["Wound Poison"]        = 13220,  -- level 32
	},
	-- locale: end
})
