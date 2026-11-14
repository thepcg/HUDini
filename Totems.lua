--[[--------------------------------------------------------------------------
	HUDini - Totems (TICK-0108)

	A shaman's totems, each with its time left, in a row under the left end
	of the HUD. Hide player frame hides the game's own totem bar with the
	player frame; this row shows the totems instead.

	One spot per totem slot, in the order the game's own totem bar uses:
	earth, fire, water, air. Each spot keeps its place, so a totem is always
	where you last saw it. A spot shows while its slot has a totem, with the
	totem's icon and a Cooldown that counts its time down. It goes when the
	totem ends or you recall it. The row is part of the HUD: its spots are
	children of HUDini.body, so they hide and fade when the HUD does
	(TICK-0143), and take its scale. They are placed against the blue box.

	A slot has a totem only on a plain sign that one is down (TICK-0143):
	the game says so, its duration object is not zero (an empty slot gives
	none), or, with no object, its plain length is above 0. And it needs an
	icon the texture takes. A slot the game calls "have" with no time or no
	icon showed as an empty black square; now it shows nothing.

	Secret values (environment.md): in a fight a totem slot can be secret.
	Its time left goes to the Cooldown as the game's duration object, as it
	is. A secret "a totem is down" sets the spot's alpha through
	SetAlphaFromBoolean. A secret length, icon or duration object counts as
	"maybe down": it never hides a spot, and the "have" decides. HUDini never
	compares or tests a secret value; only a plain answer shows or hides a
	spot.

	The spots take no clicks: a right-click on the game's own totem bar
	recalls a totem, and that bar is the game's.

	It is a module (Modules.lua): on while showTotems is on and you play a
	shaman. On any other class it has no events and made no frames.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local HUDini   = ns.HUDini
local Plain    = ns.Plain
local IsSecret = ns.IsSecret

local M = ns.NewModule("totems", {
	label = "Totem timers", -- locale: skip a debug name (/hud debug modules)
	isOn = function()
		return HUDiniDB and HUDiniDB.showTotems and ns.ClassToken() == "SHAMAN"
	end,
	defaults = {
		showTotems = true, -- a shaman's totems and their time left, under the HUD
	},
})

local SIZE = 0.75 -- a spot's size, as a part of an icon's
local GAP  = 3    -- pixels between spots, and between the HUD and the row

local spots = {}

-- The slots, left to right: the game's own order for a shaman, or 1 to 4.
local function Slots()
	local order = _G.SHAMAN_TOTEM_PRIORITIES
	if type(order) == "table" and #order > 0 then return order end
	order = {}
	for i = 1, (tonumber(_G.MAX_TOTEMS) or 4) do order[i] = i end
	return order
end

-- Ask the game. ok is false when it throws or the API is missing; the
-- answers come back as they are, secret or not.
local function Ask(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

local function Spot(i)
	local f = spots[i]
	if f then return f end
	-- The body, not the anchor: only the body hides when idle (Core.lua).
	f = M:CreateFrame("Frame", nil, HUDini.body)
	f:EnableMouse(false)

	f.backdrop = f:CreateTexture(nil, "BACKGROUND")
	f.backdrop:SetPoint("TOPLEFT", -1, 1)
	f.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
	f.backdrop:SetColorTexture(0, 0, 0, 0.9)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- The time left: the swipe and the game's own countdown numbers.
	f.cd = M:CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	if f.cd.SetDrawBling then f.cd:SetDrawBling(false) end
	f.cd:SetHideCountdownNumbers(false)

	f:Hide()
	spots[i] = f
	return f
end

-- Under the HUD's left end: the blue box covers the whole HUD, so its
-- bottom left is the HUD's, however the icons grow.
local function Place()
	local size = math.floor((HUDiniDB.iconSize or 40) * SIZE + 0.5)
	for i, f in ipairs(spots) do
		f:SetSize(size, size)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", HUDini.mover, "BOTTOMLEFT", 1 + (i - 1) * (size + GAP), -GAP)
	end
end

local function Clear(f)
	if f.cd.Clear then f.cd:Clear() end
	f:Hide()
end

-- The slot's duration object, or nil: none, a throw, or no such API.
local function Object(slot)
	local ok, object = Ask(_G.GetTotemDuration, slot)
	if ok then return object end
end

-- A sign that a totem is down. A duration object: down unless it says,
-- plainly, that it is zero; a secret one, or one that cannot say, counts
-- as down. No object: down when the plain length is above 0, or when the
-- length is secret. "Down" here only lets a spot show: the "have" and the
-- icon must agree.
local function Down(object, duration)
	if object ~= nil then
		if IsSecret(object) then return true end
		local ok, zero = pcall(function() return object:IsZero() end)
		return not (ok and Plain(zero) == true)
	end
	if IsSecret(duration) then return true end
	return type(duration) == "number" and duration > 0
end

-- Set the icon. False when there is none to set (nil, 0 or "", as an empty
-- slot gives), or the texture does not take it: a spot with no icon is an
-- empty black square. A secret icon goes to the texture as it is.
local function Icon(f, icon)
	if not IsSecret(icon) then
		local kind = type(icon)
		if not ((kind == "number" and icon > 0) or (kind == "string" and icon ~= "")) then
			return false
		end
	end
	local ok, set = pcall(f.icon.SetTexture, f.icon, icon)
	return ok and Plain(set) ~= false
end

-- The time left. The duration object goes to the Cooldown as it is, secret
-- or not. Without one, the plain start and length do, when the game gave them.
local function Time(f, object, start, duration)
	local cd = f.cd
	if object ~= nil
		and pcall(cd.SetCooldownFromDurationObject, cd, object) then
		return
	end
	start, duration = Plain(start), Plain(duration)
	if type(start) == "number" and type(duration) == "number" and duration > 0
		and pcall(cd.SetCooldown, cd, start, duration) then
		return
	end
	if cd.Clear then cd:Clear() end
end

local function Paint(f, slot)
	local ok, have, _, start, duration, icon = Ask(_G.GetTotemInfo, slot)
	local secret = ok and IsSecret(have)
	-- A throw, or a plain "no totem": the spot goes.
	if not ok or (not secret and not have) then return Clear(f) end
	-- A plain sign the slot is empty, or no icon to show: the spot goes.
	local object = Object(slot)
	if not Down(object, duration) or not Icon(f, icon) then return Clear(f) end

	Time(f, object, start, duration)
	if secret then
		-- The game shows or hides it. 255 and 0 are safe under either alpha
		-- scale (Alerts.lua). Where it cannot, the spot stays hidden.
		if not pcall(f.SetAlphaFromBoolean, f, have, 255, 0) then
			return Clear(f)
		end
	else
		f:SetAlpha(1)
	end
	f:Show()
end

local function Update()
	for i, slot in ipairs(Slots()) do Paint(Spot(i), slot) end
end

-- A new icon size, scale or layout moves the row with the HUD.
hooksecurefunc(HUDini, "Layout", Place) -- locale: skip a method name

M:On({ "PLAYER_TOTEM_UPDATE", "PLAYER_ENTERING_WORLD" }, Update)

function M:OnEnable()
	Update()
	Place()
end

function M:OnDisable()
	for _, f in ipairs(spots) do Clear(f) end
end

-- For the tests: the spot for the i-th slot, left to right.
function ns.TotemSpot(i) return spots[i] end
