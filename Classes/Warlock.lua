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
-- [TF]. No keepUp: Demon Armor lasts 30 minutes, so Auras.lua already
-- learns it as a buff to reapply; Shadow Ward (30 s) is an answer to
-- shadow damage, not a buff to keep up.
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
	-- Cooldown ready alerts (TICK-0157): offered on the "Your class" page.
	-- Death Coil (42) is your escape and heal; Fel Domination (talent, 25)
	-- brings a demon back fast; Amplify Curse (talent, 20); Inferno (50,
	-- 1 hour) [TF].
	readyAlert = { "Death Coil", "Fel Domination", "Amplify Curse", "Inferno" },
	-- The ones that start as the bell (D-047): the two that save you or
	-- your demon in a fight. No keepUpSoundOn: armor lasts 30 minutes and
	-- drops out of a fight, so the icon is enough.
	readyAlertOn = { "Death Coil", "Fel Domination" },
	-- An icon by your health bar, out of a fight, when your bags hold none
	-- (TICK-0182). The first row that is missing shows, so the Soul Shard
	-- comes first: with no shard you cannot make a stone. Summon Voidwalker
	-- (10) is the first spell that takes a shard [TF]. A Healthstone is your
	-- free heal; a Soulstone costs a shard each time, so it starts off.
	-- Item IDs are the Classic Era ones (any rank counts): not yet proven on
	-- Forever, /hud debug aura shows the game's name and count for each.
	missingItem = {
		{ key = "soulShard", needs = { "Summon Voidwalker" }, items = { 6265 }, on = true },
		{ key = "healthstone", make = "Create Healthstone",
			items = { 5512, 5511, 5509, 5510, 9421 }, on = true },
		{ key = "soulstone", make = "Create Soulstone",
			items = { 5232, 16892, 16893, 16895, 16896 },
			buff = "Soulstone Resurrection", on = false },
	},
	-- Forever IDs, rank 1: [FA] for Demon Skin, Demon Armor, Death Coil,
	-- Inferno and the last four; [TF] for the rest. Create Healthstone,
	-- Create Soulstone and Summon Voidwalker (the first demon that takes a
	-- Soul Shard) are for the missing item rows (TICK-0182, TICK-0190).
	ids = {
		["Spell Lock"] = 19244, ["Devour Magic"] = 19505,
		["Demon Skin"] = 687, ["Demon Armor"] = 706,
		["Death Coil"] = 6789, ["Fel Domination"] = 18708,
		["Amplify Curse"] = 18288, ["Inferno"] = 1122,
		["Create Healthstone"] = 6201, ["Create Soulstone"] = 693,
		["Summon Voidwalker"] = 697, ["Soulstone Resurrection"] = 20707,
	},
})
