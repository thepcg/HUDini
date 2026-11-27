--[[--------------------------------------------------------------------------
	HUDini - Warlock

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- Forever facts (TICK-0178, D-047). Sources: [TF] talentsforever.com
-- export/warlock.json, beta build 1.60.1.70755 (2026-11-10); [FA] the
-- Forever client's own spell names, as ForeverAuras lists them (build
-- 70374). Forever stops at level 60, so Soulshatter (a level 66 spell
-- elsewhere) and Fel Armor are not in either source.
--
-- Spell Lock (36) and Devour Magic (30) are your Felhunter's spells [TF]:
-- they count only while it is out. No dispel: Devour Magic can also clean
-- you, but the game's "you can dispel this" aura filter likely looks at
-- your own spells only. No resource: Soul Shards are items, a reagent
-- [TF]. Shadow Ward (30 s) is an answer to shadow damage, not a buff to
-- keep up.
--
-- Detect Invisibility needs no group: all three ranks carry that one name
-- on Forever [FA], and Auras.lua counts it as a buff for one job.
--
-- Only one armor can be on, so each counts as on while the other is.
-- Without that, the armor you are not wearing is always "missing", and the
-- HUD never hides.
local GROUPS = {
	{ "Demon Skin", "Demon Armor" },
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
	-- Your armor, watched in a fight (TICK-0216, as the Mage's). Auras.lua
	-- learns it too, but only once it has seen it on you; this list works
	-- from the first fight. The first spell you know shows: Demon Armor
	-- from level 20, else Demon Skin. The auraMap pair counts either as on.
	keepUp    = { "Demon Armor", "Demon Skin" },
	-- The buff-missing sound starts on (D-047): armor that drops in a
	-- fight is easy to miss. The armor pair is one watch, so the game's own
	-- buff-end sound reaches it too (TICK-0194).
	keepUpSoundOn = true,
	-- The armor is also a tracked buff from the start (TICK-0204): its icon
	-- shows out of a fight too (30 minutes: D-033), before HUDini has seen
	-- it on you. Each name goes in when you know it; the pair counts as one.
	trackBuff = { "Demon Armor", "Demon Skin" },
	-- Cooldown ready alerts (TICK-0157): offered on the "Your class" page.
	-- Death Coil (42) is your escape and heal; Fel Domination (talent, 25)
	-- brings a demon back fast; Amplify Curse (talent, 20); Inferno (50,
	-- 1 hour) [TF].
	readyAlert = { "Death Coil", "Fel Domination", "Amplify Curse", "Inferno" },
	-- The ones that start as the bell (D-047): the two that save you or
	-- your demon in a fight.
	readyAlertOn = { "Death Coil", "Fel Domination" },
	-- An icon by your health bar, out of a fight, when your bags hold none
	-- (TICK-0182). The first row that is missing shows, so the Soul Shard
	-- comes first: with no shard you cannot make a stone. Summon Voidwalker
	-- (10) is the first spell that takes a shard [TF]. A Healthstone is your
	-- free heal; a Soulstone costs a shard each time, so it starts off.
	-- Item IDs are the Classic Era ones (any rank counts): not yet proven on
	-- Forever, /hud debug aura shows the game's name and count for each.
	-- Soul Shard few = 3 (TICK-0207, veto: the number): under 3 the icon
	-- shows with the count, so you can Drain Soul before you run out. Only
	-- none wakes the HUD (it is a needs row: it never does). While it shows
	-- a few left, it is the first row, so a missing Healthstone waits.
	missingItem = {
		{ key = "soulShard", needs = { "Summon Voidwalker" }, items = { 6265 },
			few = 3, on = true },
		{ key = "healthstone", make = "Create Healthstone",
			items = { 5512, 5511, 5509, 5510, 9421 }, on = true },
		{ key = "soulstone", make = "Create Soulstone",
			items = { 5232, 16892, 16893, 16895, 16896 },
			buff = "Soulstone Resurrection", on = false },
	},
	-- An icon by your health bar when no demon is out (TICK-0192): the demon
	-- you summoned last, else the first you know. Summon Imp (1), Voidwalker
	-- (10), Succubus and Incubus (20; Forever adds the Incubus), Felhunter
	-- (30) [TF]. Demonic Sacrifice (talent, 20) kills your demon for a buff
	-- of 2 hours on Forever [TF]: while one is on, no demon is your choice.
	-- The buff names are the Classic Era ones; neither source lists them on
	-- Forever, and [TF] says Forever swaps the Imp and Succubus effects. A
	-- swap inside these four names still counts. /hud debug aura shows what
	-- the alert reads. Soul Link (talent, 30, after Demonic Sacrifice) lasts
	-- as long as your demon [TF]: once HUDini has learned it, it counts as
	-- missing only while a live demon is out.
	pet = {
		call = { "Summon Imp", "Summon Voidwalker", "Summon Succubus",
			"Summon Incubus", "Summon Felhunter" },
		sacrifice = { "Burning Wish", "Fel Stamina", "Touch of Shadow", "Fel Energy" },
		buffs = { "Soul Link" },
	},
	-- Forever IDs, rank 1: [FA] for Demon Skin, Demon Armor, Death Coil,
	-- Inferno, Create Healthstone, Create Soulstone, Soulstone Resurrection,
	-- the five summons and Soul Link; [TF] for the rest. Create
	-- Healthstone, Create Soulstone and Summon Voidwalker (the first demon
	-- that takes a Soul Shard) are for the missing item rows (TICK-0182,
	-- TICK-0190); the summons and Soul Link for the pet line (TICK-0192).
	-- The sacrifice buffs get no ID: none is proven on Forever.
	ids = {
		["Spell Lock"] = 19244, ["Devour Magic"] = 19505,
		["Demon Skin"] = 687, ["Demon Armor"] = 706,
		["Death Coil"] = 6789, ["Fel Domination"] = 18708,
		["Amplify Curse"] = 18288, ["Inferno"] = 1122,
		["Create Healthstone"] = 6201, ["Create Soulstone"] = 693,
		["Summon Voidwalker"] = 697, ["Soulstone Resurrection"] = 20707,
		["Summon Imp"] = 688, ["Summon Succubus"] = 712,
		["Summon Incubus"] = 713, ["Summon Felhunter"] = 691,
		["Soul Link"] = 19028,
	},
})
