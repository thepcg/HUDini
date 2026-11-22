--[[--------------------------------------------------------------------------
	Test class profiles (TICK-0173)

	Not a test: check.py runs only test_*.lua. A test file loads it with

		local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()
		Classes.Use(w)   -- before w:loadAddon()

	Then the world's class files are these profiles, not Classes\*.lua. A
	test that asserts a class file's data (Spellsteal, a keep-up list, an
	interrupt list) asserts these, so a class seat that fixes its own file
	(D-046) never has to change a test.

	A profile here is a snapshot of the class file on 2026-11-21, before
	the class seats changed them. Change it only for a test's sake; it does
	not follow the game. Tests that check every class file as it is (the
	panel's row count, each class logs in) keep the live files: they do not
	call Use.
----------------------------------------------------------------------------]]

local C = {}

-- auraMap for groups where one buff on counts for the others.
local function Groups(...)
	local map = {}
	for _, group in ipairs({ ... }) do
		for _, name in ipairs(group) do
			map[name] = {}
			for _, other in ipairs(group) do
				if other ~= name then table.insert(map[name], other) end
			end
		end
	end
	return map
end

local BLESSINGS = {}
for _, kind in ipairs({ "Might", "Wisdom", "Kings", "Salvation", "Light", "Sanctuary" }) do
	table.insert(BLESSINGS, "Blessing of " .. kind)
	table.insert(BLESSINGS, "Greater Blessing of " .. kind)
end

C.profiles = {
	-- A purge that takes stealable buffs only, and two combat buffs: a
	-- talent (Ice Barrier) first, a spell every Mage has (Mana Shield) next.
	MAGE = {
		interrupt  = "Counterspell",
		dispel     = { Curse = "Remove Lesser Curse" },
		purge      = { spell = "Spellsteal", stealable = true },
		keepUp     = { "Ice Barrier", "Mana Shield" },
		auraMap    = Groups({ "Frost Armor", "Ice Armor", "Mage Armor" },
			{ "Amplify Magic", "Dampen Magic" }),
		powers     = { "MANA" },
		readyAlert = { "Evocation", "Ice Block", "Cold Snap" },
		-- A row you make (TICK-0182): it can wake the HUD.
		missingItem = {
			{ key = "manaGem", make = "Conjure Mana Gem", items = { 5514, 5513 }, on = true },
		},
	},
	-- An interrupt list: the first one you can cast now counts. The one
	-- test class with ids: /hud debug ids must count a class file ID
	-- (test_spell_ids.lua). No other test class has ids, so a name with
	-- no ID stays a case too (the Mage's Counterspell).
	WARRIOR = {
		interrupt  = { "Pummel", "Shield Bash" },
		ids        = { ["Pummel"] = 6552 },
		keepUp     = { "Battle Shout" },
		powers     = { "RAGE" },
		readyAlert = { "Recklessness", "Shield Wall", "Retaliation" },
	},
	-- A power resource.
	ROGUE = {
		interrupt  = "Kick",
		resource   = { power = "ComboPoints" },
		powers     = { "ENERGY" },
		readyAlert = { "Vanish", "Evasion", "Adrenaline Rush", "Sprint" },
	},
	-- One spell for two dispel types, and six combat buffs.
	PALADIN = {
		interrupt  = "Hammer of Justice",
		dispel     = { Magic = "Cleanse", Poison = "Purify", Disease = "Purify" },
		keepUp     = { "Seal of Righteousness", "Seal of the Crusader",
			"Seal of Command", "Seal of Wisdom", "Seal of Light", "Seal of Justice" },
		auraMap    = Groups({ "Devotion Aura", "Retribution Aura", "Concentration Aura",
			"Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura",
			"Sanctity Aura" }, BLESSINGS),
		powers     = { "MANA" },
		readyAlert = { "Divine Shield", "Lay on Hands", "Blessing of Protection" },
	},
	-- No interrupt.
	HUNTER = {
		auraMap    = Groups({ "Aspect of the Monkey", "Aspect of the Hawk",
			"Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Beast",
			"Aspect of the Wild" }),
		readyAlert = { "Rapid Fire", "Bestial Wrath", "Deterrence" },
	},
	-- A purge that takes any magic buff.
	PRIEST = {
		interrupt  = "Silence",
		dispel     = { Magic = "Dispel Magic", Disease = "Cure Disease" },
		purge      = "Dispel Magic",
		powers     = { "MANA" },
		readyAlert = { "Power Infusion", "Inner Focus", "Fear Ward" },
	},
	-- Weapon buffs, and no combat buff.
	SHAMAN = {
		interrupt  = "Earth Shock",
		dispel     = { Poison = "Cure Poison", Disease = "Cure Disease" },
		purge      = "Purge",
		weaponBuff = { "Rockbiter Weapon", "Flametongue Weapon",
			"Frostbrand Weapon", "Windfury Weapon" },
		auraMap    = {},
		powers     = { "MANA" },
		readyAlert = { "Heroism", "Bloodlust", "Mana Tide Totem", "Reincarnation" },
		-- A row you need for a spell (TICK-0182): it never wakes the HUD.
		missingItem = {
			{ key = "ankh", needs = { "Reincarnation" }, items = { 17030 }, on = true },
		},
	},
	-- A pet's interrupt and purge.
	WARLOCK = {
		interrupt  = "Spell Lock",
		purge      = "Devour Magic",
		auraMap    = Groups({ "Demon Skin", "Demon Armor" },
			{ "Detect Lesser Invisibility", "Detect Invisibility",
				"Detect Greater Invisibility" }),
		powers     = { "MANA" },
		readyAlert = { "Soulshatter", "Death Coil", "Amplify Curse" },
		-- A row off until you turn it on, with a buff that counts as the
		-- item, then a reagent row (TICK-0182).
		missingItem = {
			{ key = "soulstone", make = "Create Soulstone", items = { 5232 },
				buff = "Soulstone Resurrection", on = false },
			{ key = "soulShard", needs = { "Summon Voidwalker" }, items = { 6265 }, on = true },
		},
	},
	-- Three powers, and a resource only with one of them.
	DRUID = {
		interrupt  = "Bash",
		dispel     = { Curse = "Remove Curse", Poison = "Cure Poison" },
		resource   = { power = "ComboPoints", onlyWith = "ENERGY" },
		powers     = { "MANA", "RAGE", "ENERGY" },
		readyAlert = { "Innervate", "Rebirth", "Barkskin" },
	},
}

-- After the world loads its files, these profiles replace what the class
-- files registered. Profiles are read when asked for, so login and every
-- later call see these. Each world gets its own copy, so a test that
-- changes one changes no other test.
function C.Use(w)
	local load = w.load
	w.load = function(self, ...)
		local ns = load(self, ...)
		if ns.RegisterClass then
			for token, profile in pairs(C.profiles) do ns.RegisterClass(token, H.copy(profile)) end
		end
		return ns
	end
	return w
end

return C
