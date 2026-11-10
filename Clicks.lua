--[[--------------------------------------------------------------------------
	HUDini - Clicks

	Your health bar and your target's health bar take clicks, like Blizzard's
	unit frames:

		left-click    target that unit
		right-click   its menu (inspect, trade, invite, set focus, raid marks...)

	Only a secure button may target a unit or open its menu, so each bar gets
	an invisible SecureUnitButtonTemplate laid over it. Blizzard runs the
	click itself: "type1 = target", "type2 = togglemenu".

	A secure button is protected in combat: it cannot be moved, shown or
	hidden. Worse, the lock spreads. A protected frame makes its parent, and
	any frame it is anchored to, protected as well, and HUDini moves its bars
	in combat (a new target re-runs the layout). So the buttons stay out of
	HUDini's tree. Each one hangs off UIParent at the spot its bar has on
	screen, worked out out of combat. Nothing in HUDini ever gets locked.

	Showing and hiding in combat goes through a state driver, a macro
	condition the game evaluates for us, with no addon code involved:

		target   "[@target,exists] show; hide"
		yours    "[combat] <show in combat?>; <body shown now?>"

	Out of combat the driver strings are rebuilt whenever the HUD changes
	(ns.SyncClicks). A change during a fight waits for the fight to end. The
	layout keeps every row in its slot mid fight, so a button stays on its bar.

	An unlocked HUD drops both buttons, so they never cover the blue box you
	drag. Options > Bars turns the whole thing off.

	Clique and other click-cast addons find the buttons in ClickCastFrames.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local HUDini = ns.HUDini

-- { bar key, unit }
local BUTTONS = {
	{ key = "health",       unit = "player" },
	{ key = "targethealth", unit = "target" },
}

local buttons = {}

local function CreateButton(entry)
	local b = CreateFrame("Button", "HUDiniClick_" .. entry.key, UIParent, "SecureUnitButtonTemplate")
	b:SetAttribute("unit", entry.unit)
	b:SetAttribute("*type1", "target")
	b:SetAttribute("*type2", "togglemenu")
	b:RegisterForClicks("AnyUp")
	b:Hide()
	b.key, b.unit = entry.key, entry.unit

	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[b] = true

	buttons[entry.key] = b
	return b
end

for _, entry in ipairs(BUTTONS) do CreateButton(entry) end

--------------------------------------------------------------------------------
-- Placing a button over its bar
--------------------------------------------------------------------------------

-- LayoutBars puts each bar's BOTTOMLEFT on the anchor's TOPLEFT, offset by
-- (x, y), in the anchor's scale. The anchor never hides, so its corner is
-- always known, even while the bar itself is hidden (no target yet).
local function Place(b, bar)
	local point, rel, relPoint, x, y = bar:GetPoint(1)
	if point ~= "BOTTOMLEFT" or rel ~= HUDini or relPoint ~= "TOPLEFT" then return false end

	local left, top = HUDini:GetLeft(), HUDini:GetTop()
	if not (left and top) then return false end

	-- From the anchor's scale to UIParent's.
	local ratio = HUDini:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local w, h = bar:GetSize()

	b:SetFrameStrata(HUDini:GetFrameStrata())
	b:SetFrameLevel(HUDini:GetFrameLevel() + 20)
	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (left + x) * ratio, (top + y) * ratio)
	b:SetSize(w * ratio, h * ratio)
	return true
end

--------------------------------------------------------------------------------
-- When each button is there
--------------------------------------------------------------------------------

-- A driver string per button. Registered again only when it changes.
local driven = {}

local function Drive(b, state)
	if driven[b] == state then return end
	driven[b] = state
	RegisterStateDriver(b, "visibility", state)
end

local function YourDriver(db)
	if not db.showHealth then return "hide" end
	-- In a fight the body shows when "Show in combat" is on, or always when
	-- hiding is off. Out of one, it is up right now or it is not.
	local inFight = ((not db.hideWhenIdle) or db.showInCombat) and "show" or "hide"
	local now     = HUDini.body:IsShown() and "show" or "hide"
	return ("[combat] %s; %s"):format(inFight, now)
end

local function TargetDriver(db)
	if not db.showTargetHealth then return "hide" end
	return "[@target,exists] show; hide" -- locale: skip a secure state driver
end

local function Apply()
	local db = HUDiniDB
	if not db then return end

	local on = db.clickBars and db.locked

	for key, b in pairs(buttons) do
		local bar = ns.GetBar and ns.GetBar(key)
		local placed = on and bar and Place(b, bar)

		if not placed then
			Drive(b, "hide")
		elseif b.unit == "player" then
			Drive(b, YourDriver(db))
		else
			Drive(b, TargetDriver(db))
		end
	end
end

--------------------------------------------------------------------------------
-- Keeping up with the HUD
--
-- Many things call SyncClicks in one burst (a layout, then its visibility
-- pass). They fold into one Apply on the next frame, after the layout has
-- settled. In combat it waits for the fight to end.
--------------------------------------------------------------------------------

local queued, waiting = false, false

function ns.SyncClicks()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = false
		if InCombatLockdown() then
			waiting = true
			return
		end
		waiting = false
		Apply()
	end)
end

-- The body fading out, or coming back, changes your button's driver.
HUDini.body:HookScript("OnShow", ns.SyncClicks)
HUDini.body:HookScript("OnHide", ns.SyncClicks)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")

events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_ENABLED" and not waiting then return end
	ns.SyncClicks()
end)
