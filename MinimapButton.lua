--[[--------------------------------------------------------------------------
	HUDini - Minimap button and AddOns menu entry (D-009, TICK-0020)

	A button with the top-hat icon on the
	minimap edge, and the entry in the addons button on the minimap (the
	.toc's AddonCompartmentFunc fields, which call the globals at the end).
	Both: left-click opens the options, right-click runs HUDini setup. The
	button alone can be dragged around the minimap edge; HUDiniDB
	.minimapAngle keeps its place. HUDiniDB.minimapButton shows or hides it.

	Own code, not LibDBIcon: one button needs about a hundred lines, and a
	library brings LibStub, CallbackHandler and LibDataBroker with it.

	A plain button, a child of Minimap: no secure template, no protected
	frame, so it works in a fight. As a child of Minimap it hides and fades
	with it, so "Minimap only on mouseover" covers it too. The options
	refuse to open in a fight (ns.OpenOptions), and setup waits for the
	fight's end (ns.OpenSetup), so a click in a fight is safe.
----------------------------------------------------------------------------]]

local _, ns = ...

local ICON = "Interface\\AddOns\\HUDini\\Media\\icon"
local SIZE, ICON_SIZE = 31, 20
local GAP = 5    -- from the minimap's edge to the button's center, past the radius
local HINT = { 0.7, 0.7, 0.7 }

local cos, sin, rad, deg, atan2, sqrt = math.cos, math.sin, math.rad, math.deg, math.atan2, math.sqrt
local max, min = math.max, math.min

local button

-- Left opens the options, right runs setup: the button and the menu entry.
local function Click(which)
	if which == "RightButton" then
		ns.OpenSetup()
	else
		ns.OpenOptions()
	end
end

-- The tooltip lines, the drag line for the button only.
local function FillTooltip(tip, withDrag)
	tip:SetText("HUDini")
	tip:AddLine(ns.Text("minimap.left"), unpack(HINT))
	tip:AddLine(ns.Text("minimap.right"), unpack(HINT))
	if withDrag then tip:AddLine(ns.Text("minimap.drag"), unpack(HINT)) end
	tip:Show()
end

-- Put the button at its angle on the minimap edge. A square minimap
-- (GetMinimapShape, set by addons that square it) pushes it out to the
-- corners; every other shape is taken as round.
local function Place()
	local a = rad(HUDiniDB.minimapAngle or ns.defaults.minimapAngle)
	local x, y = cos(a), sin(a)
	local r = Minimap:GetWidth() / 2 + GAP
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		local d = sqrt(2) * r - 10
		x, y = max(-r, min(x * d, r)), max(-r, min(y * d, r))
	else
		x, y = x * r, y * r
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging: the angle from the minimap's center to the cursor.
local function Drag()
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	HUDiniDB.minimapAngle = deg(atan2(py / scale - my, px / scale - mx)) % 360
	Place()
end

local function StopDrag(self)
	self:SetScript("OnUpdate", nil)
	self.dragging = false
end

local function Build()
	button = CreateFrame("Button", "HUDiniMinimapButton", Minimap)
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	back:SetSize(24, 24)
	back:SetPoint("CENTER")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("CENTER")
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, which) Click(which) end)
	button:SetScript("OnEnter", function(self)
		if self.dragging then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		FillTooltip(GameTooltip, true)
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		self.dragging = true
		GameTooltip:Hide()
		self:SetScript("OnUpdate", Drag)
	end)
	button:SetScript("OnDragStop", StopDrag)
	-- "Minimap only on mouseover" hides the minimap, and the button with it,
	-- when a drag takes the mouse off it. A hidden button may not get
	-- OnDragStop at mouse-up; without this it would follow the cursor with
	-- no button held when the minimap shows again.
	button:SetScript("OnHide", StopDrag)
end

-- Login and HUDini:Apply: show the button at its place, or hide it.
function ns.ApplyMinimapButton()
	if not HUDiniDB then return end
	if HUDiniDB.minimapButton then
		if not button then Build() end
		Place()
		button:Show()
	elseif button then
		button:Hide()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	ns.ApplyMinimapButton()
end)

--------------------------------------------------------------------------------
-- The addons button on the minimap: the .toc's AddonCompartmentFunc fields
-- name these globals. Since 11.0 a click gets (addonName, buttonName);
-- enter and leave get (addonName, menuButtonFrame) (warcraft.wiki.gg,
-- Addon compartment).
--------------------------------------------------------------------------------

function HUDini_OnAddonCompartmentClick(_, which)
	Click(which)
end

function HUDini_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	FillTooltip(GameTooltip, false)
end

function HUDini_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
