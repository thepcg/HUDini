--[[--------------------------------------------------------------------------
	HUDini - Paladin

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- No aura in keepUp: an aura never ends, so Auras.lua learns each one you
-- use as a buff to reapply. A seal lasts 30 seconds, so it is the one to
-- keep up in a fight. On Forever, Judgement does not spend the seal (spell
-- 20271, client build 1.60.1.70862: "Does not consume the Seal."), so a
-- seal ends only when its 30 seconds run out (TICK-0131).
--
-- Only one of your auras is on at a time, and only one of your blessings on
-- a target: a new one replaces the old. So within each group, every buff
-- counts as on while any other is. Without that, the one you are not using
-- is always "missing", and the HUD never hides. The cost: another paladin's
-- blessing on you also counts as yours.
--
-- Forever took out Sanctity Aura and the Blessings (and Greater Blessings)
-- of Light, Salvation and Sanctuary (TICK-0174), so they are not here.
local AURAS = {
	"Devotion Aura", "Retribution Aura", "Concentration Aura",
	"Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura",
}

local BLESSINGS = {}
for _, kind in ipairs({ "Might", "Wisdom", "Kings" }) do
	tinsert(BLESSINGS, "Blessing of " .. kind)
	tinsert(BLESSINGS, "Greater Blessing of " .. kind)
end

local auraMap = {}
for _, group in ipairs({ AURAS, BLESSINGS }) do
	for _, name in ipairs(group) do
		auraMap[name] = {}
		for _, other in ipairs(group) do
			if other ~= name then tinsert(auraMap[name], other) end
		end
	end
end

-- Forever spell IDs, rank 1, for every name in this file (TICK-0174,
-- TICK-0072), from the Forever beta client 1.60.1.70755 spell data.
-- The level is when the spell is learned.
local ids = {
	-- Seals (30 seconds each)
	["Seal of Righteousness"] = 20154,    -- level 1
	["Seal of the Crusader"]  = 21082,    -- level 6
	["Seal of Fury"]          = 1311649,  -- level 10, new on Forever (tank)
	["Seal of Command"]       = 20375,    -- level 20, talent
	["Seal of Justice"]       = 20164,    -- level 22
	["Seal of Light"]         = 20165,    -- level 30
	["Seal of Wisdom"]        = 20166,    -- level 38
	-- Auras
	["Devotion Aura"]          = 465,     -- level 1
	["Retribution Aura"]       = 7294,    -- level 16
	["Concentration Aura"]     = 19746,   -- level 22
	["Shadow Resistance Aura"] = 19876,   -- level 28
	["Frost Resistance Aura"]  = 19888,   -- level 32
	["Fire Resistance Aura"]   = 19891,   -- level 36
	-- Blessings (1 hour each on Forever)
	["Blessing of Might"]          = 19740,  -- level 4
	["Blessing of Wisdom"]         = 19742,  -- level 14
	["Blessing of Kings"]          = 20217,  -- level 20
	["Greater Blessing of Might"]  = 25782,  -- level 52
	["Greater Blessing of Wisdom"] = 25894,  -- level 54
	["Greater Blessing of Kings"]  = 25898,  -- level 60
	-- Stun, dispels and cooldowns
	["Hammer of Justice"]      = 853,     -- level 8
	["Purify"]                 = 1152,    -- level 8
	["Cleanse"]                = 4987,    -- level 42
	["Divine Protection"]      = 498,     -- level 6
	["Lay on Hands"]           = 633,     -- level 10
	["Blessing of Protection"] = 1022,    -- level 10
	["Divine Shield"]          = 642,     -- level 34
	["Divine Intervention"]    = 19752,   -- level 30
	-- Tank buff (30 minutes)
	["Righteous Fury"]         = 25780,   -- level 10
}

-- Reagents (TICK-0182, TICK-0186). Item IDs are the Classic Era ones, not
-- yet proven on Forever: /hud debug aura names each with its bag count.
-- Symbol of Kings: every Greater Blessing uses one, and a Paladin of 52+
-- who runs out finds out mid-buff. Starts on.
-- Symbol of Divinity: only Divine Intervention (1 hour cooldown) uses it,
-- so the warning starts off; turn it on if you carry one for a raid.
local missingItem = {
	{ key = "symbolOfKings", items = { 21177 }, on = true,
	  needs = { "Greater Blessing of Might", "Greater Blessing of Wisdom",
	            "Greater Blessing of Kings" } },
	{ key = "symbolOfDivinity", items = { 17033 },
	  needs = { "Divine Intervention" } },
}

ns.RegisterClass("PALADIN", {
	interrupt = "Hammer of Justice",      -- level 8; a stun stops the cast
	dispel    = { Magic   = "Cleanse",    -- level 42
	              Poison  = "Purify",     -- level 8
	              Disease = "Purify" },
	-- Any seal on counts (Auras.lua, KeepUpState), so a tank in Seal of Fury
	-- gets no icon.
	keepUp    = { "Seal of Righteousness", "Seal of Fury", "Seal of the Crusader",
		"Seal of Command", "Seal of Wisdom", "Seal of Light", "Seal of Justice" },
	-- The buff-missing sound starts on (D-047): a seal ends every 30
	-- seconds, so the sound tells you to look. It plays when the seal
	-- reminder shows; a sound the moment the last seal ends is TICK-0194.
	keepUpSoundOn = true,
	-- Seal of Fury is the tank seal (Forever only: its Judgement taunts),
	-- so with it on, a missing Righteous Fury gets an icon in a fight
	-- (TICK-0208). Other seals get none: a Paladin who does not tank
	-- keeps Righteous Fury off.
	tankBuff  = { buff = "Righteous Fury", with = { "Seal of Fury" } },
	auraMap   = auraMap,
	powers    = { "MANA" },
	-- Cooldown ready alerts (TICK-0157): offered on the "Your class" page.
	-- Divine Protection is the save from level 6 until Divine Shield at 34.
	readyAlert = { "Lay on Hands", "Divine Shield", "Divine Protection",
		"Blessing of Protection" },
	-- Starts as the bell (D-047): a 20 minute cooldown is easy to forget,
	-- and it is the big save. The others are 5 minutes: too often for a
	-- bell you did not ask for.
	readyAlertOn = { "Lay on Hands" },
	missingItem = missingItem,
	ids = ids,
})
