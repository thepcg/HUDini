--[[--------------------------------------------------------------------------
	HUDini - Hunter

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- No interrupt: Retail's Counter Shot is not a Forever spell, and Scatter
-- Shot is a talent that only stuns. No purge: Tranquilizing Shot takes an
-- enrage, not a magic buff. No keepUp: an aspect never ends, so Auras.lua
-- learns each one you use as a buff to reapply.
--
-- Only one aspect is on at a time, so each aspect counts as on while any
-- other is. Without that, the aspect you are not in is always "missing",
-- and the HUD never hides.
--
-- powers is left out until a test sitting shows Mana or Focus; the colour
-- picker then shows the power you have now.
local ASPECTS = {
	"Aspect of the Monkey", "Aspect of the Hawk", "Aspect of the Cheetah",
	"Aspect of the Pack", "Aspect of the Beast", "Aspect of the Wild",
}

local auraMap = {}
for _, aspect in ipairs(ASPECTS) do
	auraMap[aspect] = {}
	for _, other in ipairs(ASPECTS) do
		if other ~= aspect then tinsert(auraMap[aspect], other) end
	end
end

ns.RegisterClass("HUNTER", {
	auraMap = auraMap,
})
