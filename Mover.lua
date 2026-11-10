--[[--------------------------------------------------------------------------
	HUDini - Mover

	Move Blizzard's windows without another addon.

		drag                 left-drag any empty part of a window
		Ctrl + mouse wheel   make it bigger or smaller
		Shift + right-click  snap it back to its normal place and size

	A moved window stays put only while it is open. Closing it puts it back,
	so it opens in its usual place next time and HUDini never fights
	Blizzard's window manager or saves anything.

	Which windows: everything in Blizzard's UIPanelWindows list (character,
	spellbook, quest log, vendors, trainers, mail, bank, gossip, quests...),
	plus EXTRA_FRAMES below. Windows that load later are picked up as their
	addon loads, and any window opened through ShowUIPanel as it opens.

	Only hooks are added (HookScript, hooksecurefunc): Blizzard's own
	scripts stay untouched. A window the game protects in combat is left
	alone until the fight ends.

	HUDini writes no field on a window: what it keeps is in its own tables,
	keyed by the window. Some windows are Edit Mode system frames (the loot
	window, EditModeLootFrameSystemTemplate), and Edit Mode reads its fields
	tainted after an addon wrote them (TICK-0089). On those, ClearAllPoints,
	SetPoint and SetScale are Edit Mode's Lua (EditModeSystemTemplates.lua
	:117-156): it saves the C methods as ClearAllPointsBase, SetPointBase
	and SetScaleBase (:3-29), and HUDini calls those, so no Edit Mode Lua
	runs in HUDini's call.

	Off by default (moveWindows), and while off HUDini touches no window:
	no hook, no event, no flag set. It is a module (Modules.lua): the hooks
	go in the first time the setting is on, at login or when you turn it on.
	A hook cannot be taken out again, so turning it off later only makes
	every hook do nothing and drops its events; after a /reload with it
	off, none are added.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- Windows that are not in UIPanelWindows.
local EXTRA_FRAMES = {
	"GameMenuFrame", "SettingsPanel", "AddonList", "LootFrame",
	"ColorPickerFrame", "ReadyCheckFrame", "ItemTextFrame",
	"StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
	"ContainerFrameCombinedBags",
}
for i = 1, 13 do EXTRA_FRAMES[#EXTRA_FRAMES + 1] = "ContainerFrame" .. i end

local M = ns.NewModule("mover", {
	label = "Move game windows", -- locale: skip a debug name (/hud debug modules)
	setting = "moveWindows",
	-- Drag, scale and reset Blizzard's windows; opt-in, no hooks while off.
	defaults = { moveWindows = false },
})
ns.mover = M -- for the tests

local SCALE_STEP = 0.05
local SCALE_MIN, SCALE_MAX = 0.5, 2.0

local hooked  = {}   -- [frame] = true once it can move
local pending = {}   -- [frame] = true, protected, waiting for combat to end
local stuck   = {}   -- [frame] = true, let go of in a fight, still following the mouse
local later   = {}   -- [frame] = true, closed in a fight, goes back to its place after it

-- Weak keys: a window from an addon that is gone may be freed.
local function Weak() return setmetatable({}, { __mode = "k" }) end
local home       = Weak()  -- [frame] = { points, scale } before the first drag or scale
local wasMovable = Weak()  -- [frame] = IsMovable() before the drag
local moving     = Weak()  -- [frame] = true while HUDini drags it

local function Enabled()
	return HUDiniDB and HUDiniDB.moveWindows
end

-- A protected frame may not be moved, scaled or re-anchored in combat.
local function Locked(frame)
	return InCombatLockdown() and frame:IsProtected()
end

-- The C method, not Edit Mode's Lua that takes its name on a system frame.
local function ClearAllPoints(frame)
	return (frame.ClearAllPointsBase or frame.ClearAllPoints)(frame)
end

local function SetPoint(frame, ...)
	return (frame.SetPointBase or frame.SetPoint)(frame, ...)
end

local function SetScale(frame, scale)
	return (frame.SetScaleBase or frame.SetScale)(frame, scale)
end

-- True while HUDini drags the window.
function M.IsMoving(frame) return moving[frame] == true end

-- True when the window has a place and size to go back to.
function M.HasHome(frame) return home[frame] ~= nil end

--------------------------------------------------------------------------------
-- Where the window was before you touched it
--------------------------------------------------------------------------------

-- The first drag or scale since the window opened records its anchors and
-- scale; closing it, or Shift + right-click, puts them back.
local function Remember(frame)
	if home[frame] then return end
	local points = {}
	for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
	home[frame] = { points = points, scale = frame:GetScale() }
end

local function GoHome(frame)
	if Locked(frame) then return end
	later[frame] = nil
	local was = home[frame]
	if not was then return end
	home[frame] = nil
	ClearAllPoints(frame)
	for _, p in ipairs(was.points) do SetPoint(frame, unpack(p)) end
	SetScale(frame, was.scale)
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local function OnMouseDown(frame, button)
	if not Enabled() or Locked(frame) then return end

	if button == "RightButton" and IsShiftKeyDown() then
		GoHome(frame)
		return
	end
	if button ~= "LeftButton" then return end

	Remember(frame)
	wasMovable[frame] = frame:IsMovable()
	frame:SetMovable(true)
	frame:StartMoving()
	moving[frame] = true
end

local function OnMouseUp(frame)
	if not moving[frame] then return end
	-- Let go of a protected window in a fight: StopMovingOrSizing is blocked
	-- then, so the window follows the mouse until the fight ends, and the
	-- drag ends there (TICK-0063). The fight's start ends most drags first
	-- (PLAYER_REGEN_DISABLED); this catches the rest.
	if Locked(frame) then
		stuck[frame] = true
		return
	end
	stuck[frame] = nil
	moving[frame] = nil
	frame:StopMovingOrSizing()
	-- Keep the game from saving the spot into its layout cache: the window
	-- should open in its normal place next time.
	if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
	frame:SetMovable(wasMovable[frame] and true or false)
	wasMovable[frame] = nil
end

local function OnMouseWheel(frame, delta)
	if not (Enabled() and IsControlKeyDown()) or Locked(frame) then return end
	Remember(frame)
	local scale = frame:GetScale() + delta * SCALE_STEP
	SetScale(frame, math.max(SCALE_MIN, math.min(SCALE_MAX, scale)))
end

local function OnHide(frame)
	if moving[frame] then OnMouseUp(frame) end
	-- GoHome cannot move a protected window in a fight; it waits for the end.
	if Locked(frame) then
		later[frame] = true
		return
	end
	GoHome(frame)
end

--------------------------------------------------------------------------------
-- Hooking a window
--------------------------------------------------------------------------------

local function Hook(frame)
	if not frame or hooked[frame] or type(frame) ~= "table" then return end
	if not frame.HookScript or (frame.IsForbidden and frame:IsForbidden()) then return end

	-- A protected window waits for the fight to end.
	if Locked(frame) then
		pending[frame] = true
		return
	end

	pending[frame] = nil
	pcall(function()
		frame:SetClampedToScreen(true)
		if not frame:IsMouseEnabled() then frame:EnableMouse(true) end
		frame:EnableMouseWheel(true)
		frame:HookScript("OnMouseDown", OnMouseDown)
		-- Marked as soon as OnMouseDown is in, as it can start a drag: if a
		-- later HookScript throws, the fight's start must still see this
		-- window, and the next Sweep must not hook it a second time. A throw
		-- before it leaves the window unmarked, so the next Sweep tries again.
		hooked[frame] = true
		frame:HookScript("OnMouseUp", OnMouseUp)
		frame:HookScript("OnMouseWheel", OnMouseWheel)
		frame:HookScript("OnHide", OnHide)
	end)
end

-- Every window HUDini knows by name, if it exists yet.
local function Sweep()
	if UIPanelWindows then
		for name in pairs(UIPanelWindows) do Hook(_G[name]) end
	end
	for _, name in ipairs(EXTRA_FRAMES) do Hook(_G[name]) end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local started = false

-- Add the hooks, once, and only with the setting on. Turned on again later,
-- catch up on what was skipped while it was off: windows that loaded or
-- opened meanwhile, and protected ones a fight left waiting.
local function Start()
	if not Enabled() then return end
	if started then
		for frame in pairs(pending) do Hook(frame) end
		Sweep()
		return
	end
	started = true

	-- A window opened through the panel manager gets hooked as it opens,
	-- whatever addon it came from.
	if ShowUIPanel then
		hooksecurefunc("ShowUIPanel", function(frame)
			if Enabled() then Hook(frame) end
		end)
	end
	Sweep()
end

-- Modules.lua calls this at login with the setting on, and each time
-- HUDini:Apply finds it turned on.
function M:OnEnable()
	Start()
end

-- Blizzard's load-on-demand windows (talents, auction house, trainers)
-- only exist once their addon loads.
M:On("ADDON_LOADED", function()
	if Enabled() then Sweep() end
end)

-- The fight is about to start, and the lock is not on yet: end each drag of
-- a protected window now, where it is, or it would follow the mouse and take
-- its clicks for the whole fight.
M:On("PLAYER_REGEN_DISABLED", function()
	for frame in pairs(hooked) do
		if moving[frame] and frame:IsProtected() then OnMouseUp(frame) end
	end
end)

M:On("PLAYER_REGEN_ENABLED", function()
	-- A drag let go of in the fight ends now, and a window closed in the
	-- fight goes back to its place, as closing it could not do that then.
	-- The drag ends first, so the window does not stop where the mouse is
	-- after it went home.
	for frame in pairs(stuck) do OnMouseUp(frame) end
	for frame in pairs(later) do
		if not frame:IsShown() then GoHome(frame) end
	end
	if Enabled() then
		for frame in pairs(pending) do Hook(frame) end
	end
end)
