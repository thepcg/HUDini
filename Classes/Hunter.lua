--[[--------------------------------------------------------------------------
	HUDini - Hunter

	Data only. See Classes.lua for what each field means.

	Forever's Hunter is the Classic Era Hunter with a new talent tree, level
	1 to 60 (TICK-0172). It uses Mana; its pet uses Focus. It has no Aspect
	of the Viper, Kill Command, Readiness, Misdirection, Silencing Shot or
	Counter Shot.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- No interrupt: Counter Shot and Silencing Shot are not Forever spells, and
-- Scatter Shot is a talent that only disorients.
--
-- purge is Tranquilizing Shot, enrage only (TICK-0217): learned at level
-- 60, it takes an Enrage, not a magic buff (Wowhead Forever, spell 19801).
-- Level 60 bosses and some mobs ask for it. Alone, Alerts.lua shows it for
-- any buff the game lists as yours to remove, in a fight too (then with
-- Tranquilizing Shot's icon). In a group it shows only for an aura it can
-- read as an Enrage, so in a fight it stays quiet there.
--
-- keepUp is the aspects (TICK-0213): you die, take a rez and pull with no
-- aspect on. Any one counts, so a travel aspect on in a fight hides it too;
-- notInFight then shows the red icon of your last fight aspect instead
-- (TICK-0196): Cheetah and Pack daze you when you are hit. The icon is the
-- first one you know in this order: Monkey until level 10, then Hawk, the
-- one to put on. keepUp does not need Auras.lua to learn an aspect, so it
-- works if the client gives aspects a form ID (then they count as states
-- and are never learned).
-- No keepUpSoundOn: an aspect does not drop in a fight.
--
-- Only one aspect is on at a time, so each aspect counts as on while any
-- other is. Without that, the aspect you are not in is always "missing",
-- and the HUD never hides. Forever has no Aspect of the Viper.
local ASPECTS = {
	"Aspect of the Hawk",    -- level 10
	"Aspect of the Monkey",  -- level 4
	"Aspect of the Beast",   -- level 30
	"Aspect of the Wild",    -- level 46
	"Aspect of the Cheetah", -- level 20
	"Aspect of the Pack",    -- level 40
}

local auraMap = {}
for _, aspect in ipairs(ASPECTS) do
	auraMap[aspect] = {}
	for _, other in ipairs(ASPECTS) do
		if other ~= aspect then tinsert(auraMap[aspect], other) end
	end
end

ns.RegisterClass("HUNTER", {
	powers  = { "MANA" },
	purge   = { spell = "Tranquilizing Shot", enrage = true },
	keepUp  = ASPECTS,
	notInFight = { "Aspect of the Cheetah", "Aspect of the Pack" },
	auraMap = auraMap,
	-- Your pet needs you (TICK-0192): out of a fight, Revive Pet for a dead
	-- pet and Feed Pet for an unhappy one (an unhappy pet does less damage
	-- and can run away); Call Pet when none is out. All from level 10, after
	-- the pet quests.
	pet = { revive = "Revive Pet", call = { "Call Pet" }, feed = "Feed Pet" },
	-- Cooldown ready alerts (TICK-0157), offered first on the "Your class"
	-- page and on the Hunter page in HUDini setup (TICK-0184).
	readyAlert = {
		"Rapid Fire",    -- level 26, 5 min
		"Bestial Wrath", -- Beast Mastery talent, level 40, 2 min
		"Deterrence",    -- talent, level 20, 5 min
		"Intimidation",  -- talent, level 30, 1 min (a pet stun)
		"Scatter Shot",  -- talent, about level 30, 30 s
	},
	-- These start as the bell (TICK-0181, D-047; veto open): the two big
	-- damage cooldowns, easy to forget while leveling. The others are used
	-- when a fight asks for them, not on cooldown, so they start off.
	readyAlertOn = { "Rapid Fire", "Bestial Wrath" },
	-- Tracked from the start, as if HUDini had seen it on you (TICK-0204):
	-- Marksmanship talent, level 25, 30 min, gone when you die. At 30 min it
	-- counts as missing in and out of a fight (D-033).
	trackBuff = { "Trueshot Aura" },
	-- Forever client IDs, rank 1 (ForeverAuras' scan of the client's spell
	-- data, and Wowhead Forever).
	ids = {
		["Aspect of the Monkey"]  = 13163,
		["Aspect of the Hawk"]    = 13165,
		["Aspect of the Cheetah"] = 5118,
		["Aspect of the Beast"]   = 13161,
		["Aspect of the Pack"]    = 13159,
		["Aspect of the Wild"]    = 20043,
		["Rapid Fire"]            = 3045,
		["Bestial Wrath"]         = 19574,
		["Deterrence"]            = 19263,
		["Intimidation"]          = 19577,
		["Scatter Shot"]          = 19503,
		["Trueshot Aura"]         = 19506,
		["Tranquilizing Shot"]    = 19801,
		["Call Pet"]              = 883,
		["Revive Pet"]            = 982,
		["Feed Pet"]              = 6991,
	},
})
