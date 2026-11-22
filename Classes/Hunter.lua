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
-- Scatter Shot is a talent that only disorients. No purge: Tranquilizing
-- Shot is learned at level 60 and takes an Enrage only, not a magic buff
-- (Wowhead Forever, spell 19801). No keepUp: an aspect never ends, so
-- Auras.lua learns each one you use as a buff to reapply. No
-- keepUpSoundOn: an aspect does not drop in a fight.
--
-- Only one aspect is on at a time, so each aspect counts as on while any
-- other is. Without that, the aspect you are not in is always "missing",
-- and the HUD never hides. Forever has no Aspect of the Viper.
local ASPECTS = {
	"Aspect of the Monkey",  -- level 4
	"Aspect of the Hawk",    -- level 10
	"Aspect of the Cheetah", -- level 20
	"Aspect of the Beast",   -- level 30
	"Aspect of the Pack",    -- level 40
	"Aspect of the Wild",    -- level 46
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
	auraMap = auraMap,
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
	},
})
