--[[--------------------------------------------------------------------------
	HUDini - Warrior

	Data only. See Classes.lua for what each field means.

	Levels and times are WoW Forever's (TICK-0179): seemeta.com and
	warcrafttavern.com Forever pages, 2026-11-21. The spell IDs are Forever
	beta IDs (talentsforever.com data, as listed in ForeverAuras'
	SecretAuraRanks.lua); they match Classic Era's.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

ns.RegisterClass("WARRIOR", {
	-- Pummel, level 38. Shield Bash, level 12, needs a shield. Concussion
	-- Blow, a Protection talent, stuns, and a stun stops the cast. Classic
	-- puts Pummel in Berserker Stance and Shield Bash in Battle or
	-- Defensive Stance; no Forever source says so. The outline asks the
	-- game (C_Spell.IsSpellUsable) and uses the first one you can cast now.
	interrupt = { "Pummel", "Shield Bash", "Concussion Blow" },
	-- Level 1. Three minutes on Forever: under five, so Auras.lua never
	-- learns it as a buff to reapply. Not Shield Block: keepUp counts as on
	-- while any one of it is, so a tank's block would hide a missing shout.
	keepUp    = { "Battle Shout" },
	powers    = { "RAGE" },
	-- Cooldown ready alerts (TICK-0157): offered on the "Your class" page.
	-- Retaliation level 20, 15 min; Shield Wall level 28, 15 min;
	-- Recklessness level 50, 30 min. Death Wish, Last Stand, Bloodrage and
	-- Berserker Rage show under More spells once learned (TICK-0162).
	readyAlert = { "Recklessness", "Shield Wall", "Retaliation" },
	-- The bell starts on for all three (D-047, veto open): 15 and 30 minute
	-- cooldowns are the ones a player forgets, and they ring rarely.
	readyAlertOn  = { "Recklessness", "Shield Wall", "Retaliation" },
	-- The buff-missing sound starts on (D-047, veto open): a three minute
	-- shout ends mid-fight in a long pull, and the party loses its attack
	-- power with it.
	keepUpSoundOn = true,
	ids = {
		["Pummel"]          = 6552,
		["Shield Bash"]     = 72,
		["Concussion Blow"] = 12809,
		["Battle Shout"]    = 6673,
		["Recklessness"]    = 1719,
		["Shield Wall"]     = 871,
		["Retaliation"]     = 20230,
	},
})
