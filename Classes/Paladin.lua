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
local AURAS = {
	"Devotion Aura", "Retribution Aura", "Concentration Aura",
	"Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura",
	"Sanctity Aura",
}

local BLESSINGS = {}
for _, kind in ipairs({ "Might", "Wisdom", "Kings", "Salvation", "Light", "Sanctuary" }) do
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

ns.RegisterClass("PALADIN", {
	interrupt = "Hammer of Justice",      -- level 8; a stun stops the cast
	dispel    = { Magic   = "Cleanse",    -- level 42
	              Poison  = "Purify",     -- level 8
	              Disease = "Purify" },
	keepUp    = { "Seal of Righteousness", "Seal of the Crusader",
		"Seal of Command", "Seal of Wisdom", "Seal of Light", "Seal of Justice" },
	auraMap   = auraMap,
	powers    = { "MANA" },
})
