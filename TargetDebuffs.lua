local _, ns = ...

--[[
	Three rows of auras, one maker. Two are the target's, above the HUD:
	- Your debuffs on the target (TICK-0103): each debuff you put on your
	  target. Other players' debuffs do not show.
	- The target's buffs (TICK-0118, D-026): every buff on your target.
	One is yours, beside your health bar (TICK-0128, D-027):
	- Debuffs on you: every debuff on you, right of your health bar.
	Each icon has its time left and its stacks, and shows the game's tooltip
	for its aura on mouse-over (TICK-0121). Hide target frame hides the
	game's own target auras; these rows show them instead. The game's own
	debuffs on you, at the top right, stay. The file keeps its old name: a
	renamed file in the .toc needs a full game restart.

	The game draws each row. It is an AuraContainer frame (the game's
	Blizzard_AuraContainer) with one aura group and its filter. The
	container reads the target's auras, picks, sorts, lays out and times
	the icons itself, and HUDini never reads an aura: no C_UnitAuras, no
	UnitAura, no field of an aura or of an icon. Auras are secret in a
	fight (environment.md), so this is the only way to show them then.
	HUDini gives each icon only its parts: a texture, a Cooldown and a
	stack text, handed to the icon's own setters.

	Facts about the container, from the 12.x API and from how Shadowed
	Unit Frames uses it (read for facts only, no code copied, D-021):
	- It may be missing. A pcall'd CreateFrame tells, once. Missing, the
	  row draws nothing and throws nothing, and /hud debug modules says so.
	- It starts on and listening for every unit. It is switched off before
	  its group goes in, then given its unit ("target", or "player") and
	  switched on.
	- SetUnit does nothing for the same unit, so a new target asks it to
	  read again (UpdateAllAuras).
	- It is made, placed, shown and hidden only out of a fight: under a
	  protected parent those calls are blocked in one, and a frame type
	  this new may count as protected itself. Switching it on or off
	  (SetEnabled) works in a fight.

	Each row is a child of the HUD's anchor, like the target bars, so it is
	on screen whenever you have a target, even while the rest of the HUD
	hides. With no target there is nothing to draw.

	The row of debuffs on you is a child of the anchor too, not of the HUD's
	body: the body hides and shows in a fight (hide when idle), and a
	protected child would block that. So the row follows the body itself:
	it is switched on while the body shows and off while it is hidden
	(SetEnabled, which works in a fight; off clears its icons), and it takes
	the body's alpha as the body fades. It is placed on the anchor at your
	health bar's own place, not on the bar: the anchor already holds the
	target rows, so no new frame is tied to a protected one.

	The target rows stack up from the top left of the HUD, in the order made
	here: your debuffs first, nearest the bars. Each row sits on the top of
	the row under it, and the game sizes each row to its icons (TICK-0124),
	so a row with no icon gives its line to the next one, in a fight too. A
	row that is off does the same. HUDini reads no size and counts no icon.
	The row of debuffs on you is beside the bars, out of that stack.

	Each row is a module (Modules.lua): on while its setting and its health
	bar (the target's, or yours) are on.
]]

local HUDini = ns.HUDini

local MAX = 8 -- icons in a row
local GAP = 3 -- pixels between icons, between rows, and between the HUD and the first row
-- The height the game gives a row with no icon: its layout is never less
-- than 1 high (AnchorUtil.ApplyFlowLayout, AnchorUtil.lua:746; HUDini sets
-- no padding).
local EMPTY = 1

local rows = {} -- each row's state, in the order made: its line, bottom up

-- Call a container method that may not exist on this client.
local function Try(f, method, ...)
	local fn = f[method]
	if type(fn) ~= "function" then return false end
	return pcall(fn, f, ...)
end

-- The first of two names this client has (the flow layout setters were
-- renamed during 12.x).
local function TryEither(f, a, b, ...)
	if type(f[a]) == "function" then return Try(f, a, ...) end
	return Try(f, b, ...)
end

-- An icon is the height of a health bar.
local function Size()
	return math.max(1, math.floor((HUDiniDB.healthHeight or 30) + 0.5))
end

-- The container makes each icon when it first needs it, and gives it here.
-- HUDini only adds the parts and hands each one to the icon's own setter.
local function DressNow(icon)
	local size = Size()
	icon:SetSize(size, size)
	-- Mouse over an icon shows the game's own tooltip for its aura
	-- (TICK-0121). The icon's own OnEnter shows it, from the secure side
	-- (AuraButton.lua:80-84, ShowTooltip :185-199), in a fight too
	-- (tooltipHideInCombat false, AuraButton.xml:14). Its OnLeave takes it
	-- away (:86-88), and the tooltip is a GameTooltip owned by the icon
	-- (SetOwner, :191), so it goes when the icon hides. HUDini reads no aura
	-- and sets no script. The icon takes no click: a click passes to the
	-- world behind, as with the rest of the HUD, and never cancels a buff.
	Try(icon, "SetMouseMotionEnabled", true)
	Try(icon, "SetMouseClickEnabled", false)

	local art = icon:CreateTexture(nil, "ARTWORK")
	art:SetAllPoints(icon)
	art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	Try(icon, "SetIcon", art)

	-- The time left: the swipe and the game's own countdown numbers.
	local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	cd:SetDrawEdge(false)
	if cd.SetDrawBling then cd:SetDrawBling(false) end
	cd:SetHideCountdownNumbers(false)
	Try(icon, "SetDurationCooldown", cd)

	-- The stacks, in the lower right corner. No formatter: it would get
	-- the count, and the count can be secret.
	local count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)
	Try(icon, "SetApplicationCount", count, {})
end

-- How the game lays out a row's icons. Each icon takes the height of an
-- icon, a gap and the 1 an empty row keeps, with the icon at the bottom:
-- the gap to the next row is part of this row, so an empty row (1 high)
-- takes none of it.
local function GroupLayout()
	return { elementSpacing = GAP, lineSpacing = GAP, elementHeight = Size() + GAP + EMPTY }
end

-- A row is on screen: built, and its module on.
local function Showing(r)
	return r.row and r.M.enabled
end

-- The row on screen just under r, or nil: r sits on the HUD.
local function Below(r)
	local below
	for _, other in ipairs(rows) do
		if other == r then return below end
		if Showing(other) then below = other end
	end
end

-- The row's line when it cannot sit on the row under it: one for each
-- earlier row on screen, full or not (the old way, TICK-0118).
local function Line(r)
	local n = 0
	for _, other in ipairs(rows) do
		if other == r then break end
		if Showing(other) then n = n + 1 end
	end
	return n
end

-- Above the top of the HUD stack, at its left end, growing right: the
-- first row on the HUD, each other row on the top of the row under it,
-- less the 1 an empty row keeps. The blue box covers the whole HUD, so its
-- top left is the stack's. The game sizes each row (OnLayoutComplete,
-- CustomAuraContainer.lua:799-801), in a fight too, and the rows above
-- move with it: no Lua runs. A row may sit on another: each has the
-- layout aspect the game asks for (AddAuraGroup, :317-324). If the game
-- still says no, the row takes a fixed line, as before.
local function PlaceStacked(r, size)
	local row = r.row
	row:ClearAllPoints()
	local below = Below(r)
	if not below or not pcall(row.SetPoint, row, "BOTTOMLEFT", below.row, "TOPLEFT", 0, -EMPTY) then
		row:SetPoint("BOTTOMLEFT", HUDini.mover, "TOPLEFT", 1, GAP + Line(r) * (size + GAP))
	end
end

-- Right of your health bar, a gap from its right end, growing right, the
-- icons' bottoms on the bar's bottom (an icon is the bar's height). The
-- bar's place is HUDini's own: LayoutBars puts its BOTTOMLEFT on the
-- anchor's TOPLEFT and sizes it, out of a fight. Its point and width are
-- those numbers. The row goes on the anchor at the same place: anchored
-- to the bar, it would tie the bar to a frame that may be protected, and
-- the bar shows and hides in a fight. No bar place yet: the row waits for
-- the next layout.
local function PlaceSide(r)
	local bar = ns.GetBar and ns.GetBar("health")
	if not bar then return end
	local point, rel, relPoint, x, y = bar:GetPoint(1)
	if point ~= "BOTTOMLEFT" or rel ~= HUDini or relPoint ~= "TOPLEFT" then return end
	r.row:ClearAllPoints()
	r.row:SetPoint("BOTTOMLEFT", HUDini, "TOPLEFT", x + bar:GetWidth() + GAP, y)
end

local function Place(r)
	if not Showing(r) then return end
	if InCombatLockdown() then
		r.waiting = true
		return
	end
	local row, size = r.row, Size()
	if r.side then PlaceSide(r) else PlaceStacked(r, size) end
	Try(row, "SetAuraGroupLayout", r.group, GroupLayout())
	TryEither(row, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", "BOTTOMLEFT")
	local flow = AnchorUtil and AnchorUtil.FlowDirection
	if flow then
		TryEither(row, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection", flow.Right, flow.Up)
	end
	TryEither(row, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", MAX * (size + GAP))
	for _, icon in ipairs(r.icons) do pcall(icon.SetSize, icon, size, size) end
end

local function PlaceAll()
	for _, r in ipairs(rows) do Place(r) end
end

-- A new icon size, health bar height or layout moves the rows with the HUD.
hooksecurefunc(HUDini, "Layout", PlaceAll) -- locale: skip a method name

-- A row turned off in a fight stays shown until the fight ends. Its module
-- is off then, so it hears no event: this frame waits for the end of the
-- fight instead, hides each such row and gives its line to the next. It
-- listens only while a hide waits.
local afterFight = CreateFrame("Frame")
afterFight:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for _, r in ipairs(rows) do
		if r.hideWaiting then
			r.hideWaiting = nil
			if r.row and not r.M.enabled then r.row:Hide() end
		end
	end
	PlaceAll()
end)

-- The row of debuffs on you follows the HUD's body (see the top). Only the
-- body's own show, hide and alpha move it; each call here works in a
-- fight. A row that is off, or not built, is left alone.
local body = HUDini.body

-- The row draws: its module is on and, beside your bars, the body shows.
local function Live(r)
	return r.M.enabled and (not r.side or body:IsShown())
end

local function FollowBody(on)
	for _, r in ipairs(rows) do
		if r.side and r.row and r.M.enabled then
			Try(r.row, "SetEnabled", on)
			if on then Try(r.row, "UpdateAllAuras") end
		end
	end
end

body:HookScript("OnShow", function() FollowBody(true) end)
body:HookScript("OnHide", function() FollowBody(false) end)
hooksecurefunc(body, "SetAlpha", function(_, alpha) -- locale: skip a method name
	for _, r in ipairs(rows) do
		if r.side and r.row then Try(r.row, "SetAlpha", alpha) end
	end
end)

-- Make one row: its module, its filter, its unit, its note when the client
-- has no container, and its test hook.
local function AuraRow(spec)
	local needs = spec.needs or "showTargetHealth" -- locale: skip a setting key
	local M = ns.NewModule(spec.name, {
		label = spec.label,
		isOn = function()
			return HUDiniDB and HUDiniDB[spec.setting] and HUDiniDB[needs]
		end,
		defaults = { [spec.setting] = true },
	})
	-- row: the AuraContainer, made once; false once it proved missing.
	-- icons: the icons the container made, to size them again.
	-- waiting: a start or a move waits out the fight.
	-- hideWaiting: an off in a fight; the hide waits for its end.
	-- side: beside your bars, out of the stack, following the body.
	local r = { M = M, icons = {}, group = spec.group, side = spec.side }
	rows[#rows + 1] = r

	-- The game's own code calls this, maybe in a fight: an error here
	-- would be a Lua error from the game's row. A part that fails is left
	-- off.
	local function Dress(icon)
		r.icons[#r.icons + 1] = icon
		pcall(DressNow, icon)
	end

	local function Missing(f)
		if f then
			Try(f, "SetEnabled", false)
			f:Hide()
		end
		r.row = false
		M.note = spec.note
		return false
	end

	-- Make the container once. False when this client has none.
	local function Build()
		if r.row ~= nil then return r.row ~= false end
		if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
			pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") -- locale: skip an addon name
		end
		local ok, f = pcall(CreateFrame, "AuraContainer", nil, HUDini, "CustomAuraContainerTemplate")
		if not ok or not f or type(f.AddAuraGroup) ~= "function" then
			return Missing(ok and f)
		end
		-- Off before the group goes in: on, it would listen for every unit.
		Try(f, "SetEnabled", false)
		-- The template can show sample auras in Edit Mode; HUDini has its
		-- own test mode.
		Try(f, "SetEditModePreviewEnabled", false)
		if not Try(f, "AddAuraGroup", spec.group, spec.filter, {
			maxFrameCount = MAX,
			initializeFrame = Dress,
			layout = GroupLayout(),
		}) then
			return Missing(f)
		end
		r.row = f
		return true
	end

	-- Ask the container to read the target again: SetUnit alone does
	-- nothing when only the unit behind "target" changed.
	local function Follow()
		if r.row then Try(r.row, "UpdateAllAuras") end
	end

	local function Start()
		if r.row == nil and InCombatLockdown() then
			r.waiting = true
			return
		end
		if not Build() then return end
		r.hideWaiting = nil
		Try(r.row, "SetUnit", spec.unit)
		Try(r.row, "SetEnabled", Live(r))
		if r.side then Try(r.row, "SetAlpha", body:GetAlpha()) end
		if InCombatLockdown() then
			r.waiting = true
		else
			r.row:Show()
		end
		-- This row takes a line, so the rows above it move up.
		PlaceAll()
		if Live(r) then Follow() end
	end

	-- "player" never changes its unit: only the target needs this.
	if spec.unit == "target" then M:On("PLAYER_TARGET_CHANGED", Follow) end
	M:On("PLAYER_REGEN_ENABLED", function()
		if not r.waiting then return end
		r.waiting = nil
		Start()
	end)

	function M:OnEnable()
		Start()
	end

	function M:OnDisable()
		r.waiting = nil
		if not r.row then return end
		-- Off drops its events and clears its icons, in a fight too. In a
		-- fight the frame stays shown until the fight ends.
		Try(r.row, "SetEnabled", false)
		if InCombatLockdown() then
			r.hideWaiting = true
			afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			r.row:Hide()
		end
		-- Its line goes to the rows above it.
		PlaceAll()
	end

	-- For the tests: the container, or false when missing, or nil before.
	return function() return r.row end
end

-- Nearest the bars: your own debuffs, the ones you watch.
ns.TargetDebuffRow = AuraRow({
	name = "targetdebuffs", -- locale: skip a module name
	label = "Your debuffs on the target", -- locale: skip a debug name (/hud debug modules)
	setting = "showTargetDebuffs", -- your debuffs on the target, in a row above the HUD
	unit = "target", -- locale: skip a unit
	group = "mine", -- locale: skip a group name
	filter = "HARMFUL|PLAYER", -- harmful auras that you cast; locale: skip an aura filter
	note = "debug.targetDebuffs.missing",
})

-- Above it: every buff on the target (D-026).
ns.TargetBuffRow = AuraRow({
	name = "targetbuffs", -- locale: skip a module name
	label = "Target buffs", -- locale: skip a debug name (/hud debug modules)
	setting = "showTargetBuffs", -- the target's buffs, in a row above the HUD
	unit = "target", -- locale: skip a unit
	group = "buffs", -- locale: skip a group name
	filter = "HELPFUL", -- every helpful aura on the target; locale: skip an aura filter
	note = "debug.targetBuffs.missing",
})

-- Right of your health bar: every debuff on you (TICK-0128, D-027). Made
-- last: a target row looks only at the rows made before it (Below, Line),
-- so it never stacks on this one.
ns.PlayerDebuffRow = AuraRow({
	name = "playerdebuffs", -- locale: skip a module name
	label = "Debuffs on you", -- locale: skip a debug name (/hud debug modules)
	setting = "showPlayerDebuffs", -- every debuff on you, in a row right of your health bar
	needs = "showHealth", -- locale: skip a setting key
	unit = "player", -- locale: skip a unit
	side = true,
	group = "onyou", -- locale: skip a group name
	filter = "HARMFUL", -- every harmful aura on you; locale: skip an aura filter
	note = "debug.playerDebuffs.missing",
})
