--[[--------------------------------------------------------------------------
	HUDini - Cursor ring (TICK-0245, D-052)

	Opt-in, off at the start. With it on, a see-through picture sits
	centered on the mouse cursor, over everything, and takes no clicks. It
	comes from DK's own retail addon BetterTools (BetterTools_CursorRing.lua
	and ns.GetStateAlpha in BetterTools.lua), with its three pictures and its
	values.

	Settings (all new in TICK-0245, so no migration):
	  cursorRing             on or off (off)
	  cursorRingSize         across, in UI pixels, 50 to 600 (250)
	  cursorRingShape        "ring", "halo" or "arrows" (ring)
	  cursorRingAlpha        opacity out of a fight (0.04)
	  cursorRingAlphaCombat  opacity in a fight, alone (0.10)
	  cursorRingAlphaGroup   opacity in a fight, in a party or raid (0.17)

	The ring is white only, as in BetterTools. A fight starts with
	PLAYER_REGEN_DISABLED and ends with PLAYER_REGEN_ENABLED; at turn-on,
	UnitAffectingCombat says. A cinematic hides it until it ends.

	Off: the module has no events, and the ring frame (made the first time
	it goes on) is hidden with no OnUpdate script, so it does no per-frame
	work. It reads no secret value and makes no secure frame.

	Options rows call ns.RefreshCursorRing() after they change a setting.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local M = ns.NewModule("cursorRing", {
	label    = "Cursor ring", -- locale: skip a debug name (/hud debug modules)
	setting  = "cursorRing",
	defaults = {
		cursorRing            = false,
		cursorRingSize        = 250,
		cursorRingShape       = "ring",
		cursorRingAlpha       = 0.04,
		cursorRingAlphaCombat = 0.10,
		cursorRingAlphaGroup  = 0.17,
	},
})

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local FILES = {
	ring   = MEDIA .. "CursorRing",
	halo   = MEDIA .. "CursorHalo",
	arrows = MEDIA .. "CursorArrows",
}
local MIN_SIZE, MAX_SIZE = 50, 600

local ring, texture
local inFight, inCinematic = false, false
local lastX, lastY

-- A number from the saved settings, kept between lo and hi; else the default.
local function Number(key, lo, hi)
	local v = tonumber(HUDiniDB[key])
	if not v then v = ns.defaults[key] end
	if v < lo then v = lo elseif v > hi then v = hi end
	return v
end

-- The picture for a shape; an unknown shape is the ring.
local function FileFor(shape)
	return FILES[shape] or FILES.ring
end

local function InGroup()
	local group, raid = _G.IsInGroup, _G.IsInRaid
	return (group and ns.Plain(group()) == true) or (raid and ns.Plain(raid()) == true) or false
end

-- The opacity for now: out of a fight, in a fight alone, or in a fight in a
-- party or raid (BetterTools' GetStateAlpha).
local function StateAlpha()
	if not inFight then return Number("cursorRingAlpha", 0, 1) end
	if InGroup() then return Number("cursorRingAlphaGroup", 0, 1) end
	return Number("cursorRingAlphaCombat", 0, 1)
end

-- Each screen frame while on: center the ring on the cursor. The cursor is
-- in screen pixels; UIParent's scale turns it into UI units.
local function Follow(self)
	local x, y = GetCursorPosition()
	if x == lastX and y == lastY then return end
	lastX, lastY = x, y
	local s = UIParent:GetEffectiveScale()
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end

local function Refresh()
	if not ring then return end
	if not M.enabled or inCinematic then
		ring:Hide()
		return
	end
	local size = Number("cursorRingSize", MIN_SIZE, MAX_SIZE)
	ring:SetSize(size, size)
	M.file = FileFor(HUDiniDB.cursorRingShape)
	texture:SetTexture(M.file)
	M.alpha = StateAlpha()
	ring:SetAlpha(M.alpha)
	ring:Show()
end

local function Make()
	ring = M:CreateFrame("Frame", "HUDiniCursorRing", UIParent)
	ring:SetFrameStrata("TOOLTIP")
	ring:EnableMouse(false)
	ring:Hide()
	texture = ring:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	texture:SetVertexColor(1, 1, 1, 1)
	M.ring, M.texture = ring, texture
end

function M:OnEnable()
	if not ring then Make() end
	inFight = ns.Plain(UnitAffectingCombat("player")) == true
	inCinematic = false
	lastX, lastY = nil, nil
	ring:SetScript("OnUpdate", Follow)
	Refresh()
end

function M:OnDisable()
	if not ring then return end
	ring:SetScript("OnUpdate", nil)
	ring:Hide()
end

M:On("PLAYER_REGEN_DISABLED", function() inFight = true; Refresh() end)
M:On("PLAYER_REGEN_ENABLED", function() inFight = false; Refresh() end)
M:On("GROUP_ROSTER_UPDATE", Refresh)
M:On("CINEMATIC_START", function() inCinematic = true; Refresh() end)
M:On("CINEMATIC_STOP", function() inCinematic = false; Refresh() end)

-- For the options rows (TICK-0246): turn the ring on or off to match the
-- setting, then take its size, shape and opacity again.
function ns.RefreshCursorRing()
	ns.UpdateModules()
	Refresh()
end

ns.CURSOR_RING_FILES = FILES -- for the test harness
