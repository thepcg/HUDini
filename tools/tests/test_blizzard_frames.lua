-- Core.lua (TICK-0002): which Blizzard frames HUDini hides, and when it gives
-- them back. Ported from the TICK-0002 scratch test, on the whole addon.

local FRAMES = { "PlayerFrame", "TargetFrame", "PlayerCastingBarFrame", "MainStatusTrackingBarContainer" }

-- The XP container as the template makes it: one child bar (w.repBar) and
-- its art, BarFrameTexture (w.xpArt).
local function XPParts(w)
	local box = w.env.MainStatusTrackingBarContainer
	w.repBar = w:Frame(nil, box)
	table.insert(box.__h.children, w.repBar)
	w.xpArt = w:Frame(nil, box)
	box.BarFrameTexture = w.xpArt
	return box
end

-- The cast bar's events, as CastingBarMixin:SetUnit("player") registers
-- them (CastingBarFrame.lua:224-253).
local CAST_EVENTS = {
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
}
local function CastEvents(bar)
	for _, e in ipairs(CAST_EVENTS) do bar:RegisterUnitEvent(e, "player") end
	bar:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- The events that start a cast bar (CastingBarMixin:OnEvent, CastingBar
-- Frame.lua:107-128), and the update events, which show a bar still in its
-- fade-out (:494-498, :524-525). Hide cast bar takes only these: the stop
-- events act only on a bar that shows, so a bar running at the hide ends as
-- Blizzard shows it.
local START_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
	"PLAYER_ENTERING_WORLD",
}

-- The four Blizzard frames. In the game the unit frames are protected
-- buttons that take the mouse; the cast bar and XP bar are not protected.
-- The player frame has the pet frame under it, protected too; the target
-- frame has target of target (TargetFrame.lua:688-693), a unit button.
local function MakeFrames(w)
	local PROTECTED = { PlayerFrame = true, TargetFrame = true }
	for _, name in ipairs(FRAMES) do
		w:Frame(name, nil, { protected = PROTECTED[name], mouse = PROTECTED[name] })
	end
	local player = w.env.PlayerFrame
	w.pet = w:Frame("PetFrame", player, { protected = true, mouse = true })
	table.insert(player.__h.children, w.pet)
	local target = w.env.TargetFrame
	w.tot = w:Frame("TargetFrameToT", target, { protected = true, mouse = true })
	table.insert(target.__h.children, w.tot)
	CastEvents(w.env.PlayerCastingBarFrame)
	XPParts(w)
end

-- A logged-in world with the four Blizzard frames.
local function BlizzWorld(saved)
	local w = H.world()
	MakeFrames(w)
	w.env.HUDiniDB = saved
	w:loadAddon()
	return w
end

-- True when a player cannot see the XP container: its own alpha is 0, or
-- its bar and its art both are.
local function XPInvisible(w)
	local box = w.env.MainStatusTrackingBarContainer
	return box.__h.alpha == 0 or (w.repBar.__h.alpha == 0 and w.xpArt.__h.alpha == 0)
end

-- True when HUDini hides the frame: alpha 0 for the unit frames, no spell
-- cast event for the cast bar, invisible parts for the XP container.
local HIDDEN = {
	PlayerFrame = function(w) return w.env.PlayerFrame.__h.alpha == 0 end,
	TargetFrame = function(w) return w.env.TargetFrame.__h.alpha == 0 end,
	PlayerCastingBarFrame = function(w)
		local bar = w.env.PlayerCastingBarFrame
		for _, e in ipairs(START_EVENTS) do
			if bar:IsEventRegistered(e) then return false end
		end
		return true
	end,
	MainStatusTrackingBarContainer = XPInvisible,
}

-- One letter per frame, in FRAMES order: H = hidden by HUDini, S = shown,
-- - = hidden by Blizzard (HUDini never shows or hides a frame).
local function State(w)
	local out = {}
	for _, name in ipairs(FRAMES) do
		out[#out + 1] = HIDDEN[name](w) and "H" or (w.env[name].__h.shown and "S" or "-")
	end
	return table.concat(out)
end

local function Apply(w)
	w.ns.HUDini:ApplyBlizzardFrames()
	return State(w)
end

local function HideAll(db)
	db.hideBlizzardPlayer, db.hideBlizzardTarget = true, true
	db.hideBlizzardCastBar, db.hideBlizzardXP = true, true
end

H.test("a new install hides no Blizzard frame", function()
	local w = BlizzWorld(nil)
	H.eq(State(w), "SSSS", "after login")
	H.eq(Apply(w), "SSSS")
end)

H.test("each frame comes back when its HUDini bar is off", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	HideAll(db)
	H.eq(Apply(w), "HHHH", "all four opted in, bars on")

	db.showTargetHealth, db.showPlayerCast = false, false
	H.eq(Apply(w), "HSSH", "target bar and cast bar off: both frames are back")

	w.hasTarget = true
	db.showTargetHealth = true
	H.eq(Apply(w), "HHSH", "target bar on again")

	db.showTargetHealth = false
	H.eq(Apply(w), "HSSH", "target bar off with a target: the target frame shows")

	db.showXP, db.showHealth = false, false
	H.eq(Apply(w), "SSSH", "health bar off: the player frame shows; the XP bar needs no HUDini bar")
end)

H.test("Hide XP bar hides the game's XP bar with HUDini's XP bar off (TICK-0080)", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	db.hideBlizzardXP, db.showXP = true, false
	H.eq(Apply(w), "SSSH", "HUDini's XP bar off, earning XP: the game's XP bar stays hidden")

	db.showXP = true
	H.eq(Apply(w), "SSSH", "HUDini's XP bar on again: still hidden")

	db.showXP = false
	w.level = w.maxLevel
	H.eq(Apply(w), "SSSS", "max level: the container comes back for the rep bar")

	w.level = 10
	H.eq(Apply(w), "SSSH", "leveling again")

	db.hideBlizzardXP = false
	H.eq(Apply(w), "SSSS", "Hide XP bar off: the game's XP bar shows")
end)

-- With showXP off the XP module is off and hears no event, so Core must
-- re-apply on the level and XP-gain events itself (TICK-0080 review).
H.test("with HUDini's XP bar off, the level and XP gain events still re-apply the XP hide", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	db.hideBlizzardXP, db.showXP = true, false
	w.ns.HUDini:Apply()
	H.eq(State(w), "SSSH", "earning XP: hidden")

	local disabled = false
	w.env.IsXPUserDisabled = function() return disabled end
	disabled = true
	w:fire("DISABLE_XP_GAIN")
	H.eq(State(w), "SSSS", "XP gain off at the NPC: the game's bar comes back")

	disabled = false
	w:fire("ENABLE_XP_GAIN")
	H.eq(State(w), "SSSH", "XP gain on again: hidden")

	w.level = w.maxLevel
	w:fire("PLAYER_LEVEL_UP", w.maxLevel)
	H.eq(State(w), "SSSS", "ding to max: the game's bar comes back for the rep bar")
end)

-- At PLAYER_LEVEL_UP, UnitLevel("player") can still give the old level, and
-- no source says IsXPUserDisabled is new at the XP gain events. Core checks
-- once more a moment later (TICK-0080 review).
H.test("the XP hide follows a ding or an XP gain change that the game reports late", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	db.hideBlizzardXP, db.showXP = true, false
	w.ns.HUDini:Apply()
	w:runTimers()
	H.eq(State(w), "SSSH", "earning XP: hidden")

	w:fire("PLAYER_LEVEL_UP", w.maxLevel)
	H.eq(State(w), "SSSH", "the event: UnitLevel still says the old level")
	w.level = w.maxLevel
	w:runTimers()
	H.eq(State(w), "SSSS", "a moment later: the game's bar is back for the rep bar")

	w.level = 10
	local disabled = true
	w.env.IsXPUserDisabled = function() return disabled end
	w.ns.HUDini:ApplyBlizzardFrames()
	H.eq(State(w), "SSSS", "XP gain off")
	w:fire("ENABLE_XP_GAIN")
	disabled = false
	w:runTimers()
	H.eq(State(w), "SSSH", "XP gain on, reported late: hidden a moment later")
end)

-- Alpha on frames nothing protects needs no wait for the fight to end.
H.test("with HUDini's XP bar off, a ding to max in a fight gives the XP bar back at once", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	db.hideBlizzardXP, db.showXP = true, false
	w.ns.HUDini:Apply()
	H.eq(State(w), "SSSH", "earning XP: hidden")

	w.combat = true
	w.level = w.maxLevel
	w:fire("PLAYER_LEVEL_UP", w.maxLevel)
	w:runTimers()
	H.eq(State(w), "SSSS", "in the fight: the game's bar is back")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(State(w), "SSSS", "after the fight")
end)

H.test("the XP container comes back at max level as Blizzard left it", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	HideAll(db)
	H.eq(Apply(w), "HHHH")

	w.level = w.maxLevel
	H.eq(Apply(w), "HHHS", "max level, a rep bar shown: the container shows")

	w.level = 10
	H.eq(Apply(w), "HHHH", "leveling again")

	-- Blizzard hides the container when no bar is in it. HUDini never shows it.
	w.env.MainStatusTrackingBarContainer.__h.shown = false
	w.level = w.maxLevel
	H.eq(Apply(w), "HHH-", "max level, the container empty: it stays hidden")
end)

-- The XP container is an Edit Mode system frame. A driver, Show() or Hide()
-- from HUDini runs Edit Mode's Lua in HUDini's call, and it writes
-- snappedToFrame on the frame tainted. Edit Mode reads that field at enter,
-- and the taint blocks ClearTarget and breaks the party frames (TICK-0087).
-- HUDini may set only the alpha of its parts, which runs no Lua. Its own
-- alpha stays Blizzard's: SetShownBar reads it (StatusTrackingManager.lua:183).
H.test("Hide XP bar never runs Edit Mode's code on the XP container (TICK-0087)", function()
	local w = H.world()
	MakeFrames(w)
	local box = w.env.MainStatusTrackingBarContainer

	local calls = {}
	for _, method in ipairs({ "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints",
			"SetAllPoints", "SetScale", "SetParent", "SetAttribute", "SetAlpha" }) do
		box[method] = function() calls[#calls + 1] = method end
	end
	for _, api in ipairs({ "RegisterAttributeDriver", "UnregisterAttributeDriver",
			"RegisterStateDriver", "UnregisterStateDriver" }) do
		local real = w.env[api]
		w.env[api] = function(f, ...)
			if f == box then calls[#calls + 1] = api end
			if real then return real(f, ...) end
		end
	end
	local keys = {}
	for k in pairs(box) do keys[k] = true end

	w.env.HUDiniDB = { hideBlizzardXP = true }
	w:loadAddon()
	local db = w.env.HUDiniDB
	H.eq(table.concat(calls, ", "), "", "calls on the XP container at login")
	H.eq(State(w), "SSSH", "after login: hidden")

	w.level = w.maxLevel
	w:fire("PLAYER_LEVEL_UP", w.maxLevel)
	w:runTimers()
	H.eq(State(w), "SSSS", "max level: back")
	w.level = 10
	w.ns.HUDini:Apply()
	H.eq(State(w), "SSSH", "leveling again")

	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	H.eq(State(w), "SSSS", "Edit Mode: shown, so it can be moved")
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	H.eq(State(w), "SSSH", "after Edit Mode: hidden again")

	db.hideBlizzardXP = false
	w.ns.HUDini:Apply()
	H.eq(State(w), "SSSS", "Hide XP bar off")

	H.eq(table.concat(calls, ", "), "", "calls on the XP container")
	local added = {}
	for k in pairs(box) do
		if not keys[k] then added[#added + 1] = tostring(k) end
	end
	H.eq(table.concat(added, ", "), "", "fields HUDini wrote on the XP container")
end)

-- At login, at /reload and at each change of the shown bar, Blizzard fades
-- the container in: FadeInAnimation ends at alpha 1 (setToFinalAlpha,
-- StatusTrackingBar.xml; StatusTrackingManager.lua:233-254). No HUDini apply
-- comes after it.
H.test("the XP bar stays hidden when Blizzard fades it in", function()
	local w = BlizzWorld({ hideBlizzardXP = true })
	local box = w.env.MainStatusTrackingBarContainer
	H.eq(State(w), "SSSH", "after login")
	box:SetAlpha(0)
	box:SetAlpha(1)
	H.eq(State(w), "SSSH", "after Blizzard's fade in, no apply")

	-- A divider from its pool, made after login, is hidden at the next apply.
	local divider = w:Frame(nil, box)
	table.insert(box.__h.children, divider)
	Apply(w)
	H.eq(divider.__h.alpha, 0, "a new divider")

	-- A bar swap: Blizzard hides the old bar and shows the new one
	-- (StatusTrackingManager.lua:197-220), with no HUDini apply after. A bar
	-- that is hidden at the hide is hidden by alpha too.
	local nextBar = w:Frame(nil, box, { shown = false })
	table.insert(box.__h.children, nextBar)
	Apply(w)
	w.repBar:Hide()
	nextBar:Show()
	H.eq(nextBar.__h.alpha, 0, "a bar shown after the hide")

	w.level = w.maxLevel
	H.eq(Apply(w), "SSSS", "max level: back")
	H.eq(divider.__h.alpha, 1, "the divider too")
	H.eq(nextBar.__h.alpha, 1, "the new bar too")
end)

-- At a first login the max level can be not final yet at
-- PLAYER_ENTERING_WORLD: Blizzard's bar manager checks the XP bar again at
-- UPDATE_EXPANSION_LEVEL and PLAYER_MAX_LEVEL_UPDATE (StatusTrackingManager
-- Overrides.lua:8, :18; CanShowExperienceBar, GameRulesUtil.lua:138-140).
-- HUDini's hide must check again at the same events, or the game's XP bar
-- shows until the next setting change (TICK-0117).
H.test("the XP hide follows a max level that comes after the login apply (TICK-0117)", function()
	for _, event in ipairs({ "PLAYER_MAX_LEVEL_UPDATE", "UPDATE_EXPANSION_LEVEL" }) do
		local w = H.world()
		MakeFrames(w)
		w.env.HUDiniDB = { hideBlizzardXP = true }
		local cap = w.maxLevel
		w.maxLevel = w.level                 -- not final at the login apply
		w:loadAddon()
		w:runTimers()
		H.eq(State(w), "SSSS", event .. ": at login the game says max level")
		H.eq(w.ns.GetBar("xp"):IsShown(), false, event .. ": no HUDini XP bar yet")
		w.maxLevel = cap
		w:fire(event)
		H.eq(State(w), "SSSH", event .. ": the game's XP bar is hidden, with no setting changed")
		H.eq(w.repBar.__h.alpha, 0, event .. ": the XP container's bar")
		H.eq(w.xpArt.__h.alpha, 0, event .. ": its art")
		H.eq(w.ns.GetBar("xp"):IsShown(), true, event .. ": HUDini's XP bar shows")
	end
end)

-- Each part gets back the alpha it had at the hide, not a fixed 1, and the
-- next hide saves it again.
H.test("the XP bar's parts get their own alpha back", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	w.repBar:SetAlpha(0.5)
	db.hideBlizzardXP = true
	H.eq(Apply(w), "SSSH", "hidden")
	H.eq(w.repBar.__h.alpha, 0, "the bar")

	w.level = w.maxLevel
	H.eq(Apply(w), "SSSS", "max level: back")
	H.eq(w.repBar.__h.alpha, 0.5, "the bar gets its alpha back")
	H.eq(w.xpArt.__h.alpha, 1, "the art too")

	w.repBar:SetAlpha(0.7)
	w.level = 10
	H.eq(Apply(w), "SSSH", "leveling again: hidden")
	w.level = w.maxLevel
	H.eq(Apply(w), "SSSS", "max level again")
	H.eq(w.repBar.__h.alpha, 0.7, "the alpha of the second hide, not the first")
end)

-- Edit Mode closes when a fight starts. The XP bar must not stay on screen
-- until the fight ends.
H.test("Edit Mode closed in a fight hides the XP bar at once", function()
	local w = BlizzWorld({ hideBlizzardXP = true })
	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	H.eq(State(w), "SSSS", "Edit Mode: shown")
	w.combat = true
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	H.eq(State(w), "SSSH", "Edit Mode closed in a fight")
end)

-- Alpha and events are not protected, so a change shows at once in a
-- fight. The mouse of a protected frame is: that part waits. The world
-- fails the test on a blocked call.
H.test("a change in combat shows at once; the mouse of a protected frame waits", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	HideAll(db)
	H.eq(Apply(w), "HHHH")
	H.eq(w.env.PlayerFrame.__h.mouse, false, "the hidden player frame takes no click")
	H.eq(w.pet.__h.mouse, true, "the pet frame under it shows, and keeps its click")

	w.combat = true
	db.hideBlizzardPlayer = false
	H.eq(Apply(w), "SHHH", "in combat: the player frame is back at once")
	H.eq(w.env.PlayerFrame.__h.mouse, false, "its mouse waits for the fight to end")
	H.eq(w.ns.HUDini.needBlizzFrames, true, "deferred flag")

	db.hideBlizzardCastBar = false
	H.eq(Apply(w), "SHSH", "the cast bar's events come back in a fight")

	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(State(w), "SHSH", "after the fight")
	H.eq(w.env.PlayerFrame.__h.mouse, true, "the player frame takes clicks again")
	H.eq(w.pet.__h.mouse, true, "and the pet frame")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "deferred flag cleared")

	-- A hide in a fight: alpha 0 at once, the mouse off after the fight.
	w.combat = true
	db.hideBlizzardPlayer = true
	H.eq(Apply(w), "HHSH", "hidden in a fight")
	H.eq(w.env.PlayerFrame.__h.mouse, true, "its mouse is locked until the fight ends")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(w.env.PlayerFrame.__h.mouse, false, "after the fight: no click")
end)

H.test("the power bar off gives back the player frame and the cast bar", function()
	local w = BlizzWorld(nil)
	local db = w.env.HUDiniDB
	HideAll(db)
	H.eq(Apply(w), "HHHH")

	db.showPower = false
	H.eq(Apply(w), "SHSH", "the player frame and the cast bar are back")

	db.showPower = true
	H.eq(Apply(w), "HHHH", "power on again")
end)

H.test("saved hides are kept; the others start off", function()
	local w = BlizzWorld({ hideBlizzardTarget = true, hideBlizzardCastBar = true, hideBlizzardXP = true })
	local db = w.env.HUDiniDB
	H.eq(db.hideBlizzardTarget, true, "target")
	H.eq(db.hideBlizzardCastBar, true, "cast bar")
	H.eq(db.hideBlizzardXP, true, "XP")
	H.eq(db.hideBlizzardPlayer, false, "player")
	H.eq(State(w), "SHHH", "after login")
end)

-- PlayerFrame, TargetFrame, PlayerCastingBarFrame and LootFrame are Edit
-- Mode system frames too, and the cast bar a managed frame. A driver,
-- Show() or Hide() from HUDini runs their Lua in HUDini's call; on the loot
-- window ClearAllPoints, SetPoint and SetScale are Edit Mode's Lua, which
-- keeps the C methods as ClearAllPointsBase, SetPointBase and SetScaleBase
-- (EditModeSystemTemplates.lua:3-29, :117-156). Any field HUDini writes is
-- read tainted by Edit Mode later (TICK-0089). HUDini may call only C
-- methods no Lua replaces: SetAlpha, EnableMouse, the event calls, and on
-- the loot window the Base methods and the mover's drag.
H.test("no hide setting or window drag runs Edit Mode's code on its frames (TICK-0089)", function()
	local w = H.world()
	MakeFrames(w)
	local loot = w:Frame("LootFrame")
	local realMethod = getmetatable(loot).__index
	loot:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	for _, base in ipairs({ "ClearAllPoints", "SetPoint", "SetScale" }) do
		loot[base .. "Base"] = realMethod(loot, base)
	end

	local NAMES = { "PlayerFrame", "TargetFrame", "PlayerCastingBarFrame", "LootFrame" }
	local spied, calls, keys = {}, {}, {}
	for _, name in ipairs(NAMES) do
		local f = w.env[name]
		spied[f] = name
		for _, method in ipairs({ "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints",
				"SetAllPoints", "SetScale", "SetParent", "SetAttribute" }) do
			f[method] = function() calls[#calls + 1] = name .. ":" .. method end
		end
		keys[f] = {}
		for k in pairs(f) do keys[f][k] = true end
	end
	for _, api in ipairs({ "RegisterAttributeDriver", "UnregisterAttributeDriver",
			"RegisterStateDriver", "UnregisterStateDriver" }) do
		local real = w.env[api]
		w.env[api] = function(f, ...)
			if spied[f] then calls[#calls + 1] = spied[f] .. ":" .. api end
			if real then return real(f, ...) end
		end
	end

	local saved = { moveWindows = true }
	HideAll(saved)
	w.env.HUDiniDB = saved
	w:loadAddon()
	local db = w.env.HUDiniDB
	H.eq(State(w), "HHHH", "after login: all four hidden")

	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	H.eq(State(w), "SSSS", "Edit Mode: all four shown")
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	w:runTimers()
	H.eq(State(w), "HHHH", "after Edit Mode")
	w:fire("EDIT_MODE_LAYOUTS_UPDATED")
	w:runTimers()
	H.eq(State(w), "HHHH", "after a layout load")

	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	db.hideBlizzardPlayer, db.hideBlizzardCastBar = false, false
	H.eq(Apply(w), "SHSH", "turned off in a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	HideAll(db)
	w.ns.HUDini:Apply()
	H.eq(State(w), "HHHH", "on again")
	db.hideBlizzardPlayer, db.hideBlizzardTarget = false, false
	db.hideBlizzardCastBar, db.hideBlizzardXP = false, false
	w.ns.HUDini:Apply()
	H.eq(State(w), "SSSS", "all off")

	-- Drag the loot window, scale it, snap it back, drag it, close it.
	w:Run(loot, "OnMouseDown", "LeftButton")
	w:Run(loot, "OnMouseUp", "LeftButton")
	H.eq(loot.__h.points[1][1], "CURSOR", "the loot window moves")
	w.keys.ctrl = true
	w:Run(loot, "OnMouseWheel", 1)
	w.keys.ctrl = false
	H.ok(math.abs(loot.__h.scale - 1.05) < 1e-9, "and scales")
	w.keys.shift = true
	w:Run(loot, "OnMouseDown", "RightButton")
	w.keys.shift = false
	H.eq(loot.__h.points[1][1], "CENTER", "Shift + right-click: back in its place")
	H.eq(loot.__h.scale, 1, "at its size")
	w:Run(loot, "OnMouseDown", "LeftButton")
	w:Run(loot, "OnMouseUp", "LeftButton")
	loot.__h.shown = false
	w:Run(loot, "OnHide")
	H.eq(loot.__h.points[1][1], "CENTER", "closed: back in its place")

	H.eq(table.concat(calls, ", "), "", "Edit Mode's code run by HUDini")
	local added = {}
	for f, name in pairs(spied) do
		for k in pairs(f) do
			if not keys[f][k] then added[#added + 1] = name .. "." .. tostring(k) end
		end
	end
	table.sort(added)
	H.eq(table.concat(added, ", "), "", "fields HUDini wrote on Edit Mode's frames")
end)

-- The cast bar's alpha is Blizzard's at each cast (ApplyAlpha), so HUDini
-- takes its events instead, and gives each one back for the unit it had.
H.test("Hide cast bar takes the cast bar's events and gives them back", function()
	local w = BlizzWorld({ hideBlizzardCastBar = true })
	local bar = w.env.PlayerCastingBarFrame
	H.eq(State(w), "SSHS", "after login: hidden")
	H.eq(bar.__h.shown, true, "never hidden by Hide()")
	for _, e in ipairs({ "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
			"UNIT_SPELLCAST_EMPOWER_UPDATE" }) do
		H.eq(bar:IsEventRegistered(e), false, e .. " is taken: a pushback shows no new cast")
	end
	for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
			"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP" }) do
		H.ok(bar:IsEventRegistered(e), e .. " stays: a bar running at the hide ends")
	end

	-- Blizzard's SetUnit registers them again: the next apply takes them.
	CastEvents(bar)
	H.eq(Apply(w), "SSHS", "registered again by Blizzard: taken again")

	w.env.HUDiniDB.hideBlizzardCastBar = false
	H.eq(Apply(w), "SSSS", "Hide cast bar off: back")
	for _, e in ipairs(CAST_EVENTS) do
		H.ok(bar.__h.units[e] and bar.__h.units[e].player, e .. " for the player only")
	end
	H.eq(bar.__h.units.PLAYER_ENTERING_WORLD, nil, "PLAYER_ENTERING_WORLD for no unit")

	-- The game says which units an event is for (IsEventRegistered).
	local isRegistered = getmetatable(bar).__index(bar, "IsEventRegistered")
	bar.IsEventRegistered = function(self, e)
		if isRegistered(self, e) and e:find("^UNIT_") then return true, "vehicle" end
		return isRegistered(self, e)
	end
	w.env.HUDiniDB.hideBlizzardCastBar = true
	H.eq(Apply(w), "SSHS", "hidden again")
	w.env.HUDiniDB.hideBlizzardCastBar = false
	H.eq(Apply(w), "SSSS", "back again")
	H.ok(bar.__h.units.UNIT_SPELLCAST_START.vehicle, "for the unit the game gave")
	H.eq(bar.__h.units.UNIT_SPELLCAST_START.player, nil, "and no other")
end)

-- Edit Mode's Opacity setting sets the unit frames' alpha at each layout
-- load (UpdateSystemSettingOpacity, EditModeSystemTemplates.lua:1586-1591),
-- and at Edit Mode's close, which reverts the layout before EditMode.Exit.
H.test("the unit frames stay hidden after Edit Mode sets their Opacity", function()
	local w = BlizzWorld({ hideBlizzardTarget = true })
	local target = w.env.TargetFrame
	H.eq(State(w), "SHSS", "after login")

	target:SetAlpha(0.8)
	w:fire("EDIT_MODE_LAYOUTS_UPDATED")
	w:runTimers()
	H.eq(target.__h.alpha, 0, "a layout load: hidden again")

	w.combat = true
	target:SetAlpha(0.8)
	w:fire("EDIT_MODE_LAYOUTS_UPDATED")
	w:runTimers()
	H.eq(target.__h.alpha, 0, "a layout load in a fight: hidden at once")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")

	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	H.eq(target.__h.alpha, 0.8, "Edit Mode: shown at its Opacity")
	H.eq(target.__h.mouse, true, "and takes the mouse")
	target:SetAlpha(0.9)
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	H.eq(target.__h.alpha, 0, "Edit Mode closed: hidden")

	w.env.HUDiniDB.hideBlizzardTarget = false
	Apply(w)
	H.eq(target.__h.alpha, 0.9, "Hide target frame off: the Opacity of the last layout")
end)

-- At alpha 0 a frame still takes clicks and shows tooltips, so HUDini turns
-- off the mouse under it too, and gives back only what it took.
H.test("a hidden unit frame takes no click, and gets back only the mouse HUDini took", function()
	local w = BlizzWorld(nil)
	local target = w.env.TargetFrame
	local art = w:Frame(nil, target)              -- Blizzard keeps its mouse off
	table.insert(target.__h.children, art)
	w.env.HUDiniDB.hideBlizzardTarget = true
	H.eq(Apply(w), "SHSS", "hidden")
	H.eq(target.__h.mouse, false, "the target frame takes no click")

	-- A part made later, in a fight (not protected, so at once), and one
	-- Blizzard turns on again: HUDini looks again at the next target.
	local debuff = w:Frame(nil, target)           -- off at the hide
	table.insert(target.__h.children, debuff)
	Apply(w)
	w.combat = true
	local part = w:Frame(nil, target, { mouse = true })
	table.insert(target.__h.children, part)
	debuff:EnableMouse(true)
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(part.__h.mouse, true, "not in Blizzard's handler for the event")
	w:runTimers()
	H.eq(part.__h.mouse, false, "the next target: a part made later shows no tooltip")
	H.eq(debuff.__h.mouse, false, "nor one Blizzard turned on since")
	w.combat = false

	w.env.HUDiniDB.hideBlizzardTarget = false
	H.eq(Apply(w), "SSSS", "back")
	H.eq(target.__h.mouse, true, "the target frame takes clicks")
	H.eq(part.__h.mouse, true, "the part its tooltip")
	H.eq(debuff.__h.mouse, true, "the part Blizzard turned on, its mouse")
	H.eq(art.__h.mouse, false, "and the art's mouse stays off")
end)

-- The target's auras live in the secure environment: their container and
-- buttons are forbidden to an addon (TargetFrameAuraContainer.xml:3,
-- :33-35; Blizzard_UnitFrame.toc:48-51). HUDini must not reach into them,
-- and nothing there may stop the other frames.
H.test("Hide target frame leaves the target's forbidden auras alone", function()
	local w = BlizzWorld(nil)
	local target = w.env.TargetFrame
	local touched = {}
	local function Throw(name)
		return function() touched[#touched + 1] = name; error("forbidden") end
	end
	-- The container: it says it is forbidden, and every other call throws.
	local auras = w:Frame(nil, target, { mouse = true })
	table.insert(target.__h.children, auras)
	auras.IsForbidden = function() return true end
	for _, m in ipairs({ "GetChildren", "IsMouseEnabled", "IsMouseClickEnabled",
			"IsMouseMotionEnabled", "EnableMouse", "SetMouseClickEnabled",
			"SetMouseMotionEnabled", "IsProtected" }) do
		auras[m] = Throw(m)
	end
	-- An object whose every field throws, even IsForbidden.
	table.insert(target.__h.children, setmetatable({}, {
		__index = function(_, k) touched[#touched + 1] = "index " .. tostring(k); error("forbidden") end,
	}))

	local db = w.env.HUDiniDB
	db.hideBlizzardTarget, db.hideBlizzardCastBar, db.hideBlizzardXP = true, true, true
	H.eq(Apply(w), "SHHH", "the target frame and the frames after it are hidden")
	H.eq(target.__h.mouse, false, "the target frame takes no click")
	H.eq(auras.__h.mouse, true, "the auras keep their mouse")
	w:fire("PLAYER_TARGET_CHANGED")
	w:runTimers()
	db.hideBlizzardTarget = false
	H.eq(Apply(w), "SSHH", "back")
	-- Only the IsForbidden read, inside a pcall, at each walk.
	local other = {}
	for _, t in ipairs(touched) do
		if t ~= "index IsForbidden" then other[#other + 1] = t end
	end
	H.ok(#touched > 0, "the walk reached the forbidden object")
	H.eq(table.concat(other, ", "), "", "calls into a forbidden object")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
end)

-- The target's aura container (TICK-0121), at TargetFrame.TargetFrameContent
-- .TargetFrameContentContextual.Auras (TargetFrame.lua:507-508). Its public
-- face has the container's own IsEnabled and SetEnabled (secure delegates,
-- TargetFrameAuraContainer.xml:30). Off, it clears its buttons, so none
-- shows a tooltip or takes a click where the hidden frame was.
-- secret: values issecretvalue flags while w.secretOn is true; set before
-- load, as the game does.
-- throwOn: SetEnabled with that value throws before it switches.
-- throwAfter: it switches, then throws. ignore: it returns and does not
-- switch, as a blocked action does.
local function AuraWorld(saved, enabled)
	local w = H.world()
	MakeFrames(w)
	w.secret, w.secretOn = {}, false
	w.env.issecretvalue = function(v) return w.secretOn and v ~= nil and w.secret[v] == true end
	local c = w:Frame(nil, nil)
	c.calls = {}
	c.enabled = enabled ~= false
	rawset(c, "IsEnabled", function() c.calls[#c.calls + 1] = "IsEnabled"; return c.enabled end)
	rawset(c, "SetEnabled", function(_, on)
		c.calls[#c.calls + 1] = "SetEnabled " .. tostring(on)
		if c.throwOn ~= nil and c.throwOn == on then error("blocked") end
		if c.ignore ~= nil and c.ignore == on then return end
		c.enabled = on
		if c.throwAfter ~= nil and c.throwAfter == on then error("after") end
	end)
	local target = w.env.TargetFrame
	rawset(target, "TargetFrameContent", { TargetFrameContentContextual = { Auras = c } })
	w.auras = c
	w.env.HUDiniDB = saved
	w:loadAddon()
	return w
end

local function Sets(c)
	local out = {}
	for _, call in ipairs(c.calls) do
		if call:find("^SetEnabled") then out[#out + 1] = call end
	end
	return table.concat(out, ", ")
end

H.test("Hide target frame switches the target's aura container off, and on again at the end", function()
	local w = AuraWorld(nil)
	local c, db = w.auras, w.env.HUDiniDB
	H.eq(Apply(w), "SSSS", "not hidden")
	H.eq(Sets(c), "", "a new install leaves it on")
	db.hideBlizzardTarget = true
	H.eq(Apply(w), "SHSS", "hidden")
	H.eq(c.enabled, false, "off: no button, no tooltip, no click")
	w:fire("PLAYER_TARGET_CHANGED")
	w:runTimers()
	H.eq(Sets(c), "SetEnabled false", "switched off once, not at each target")
	-- Turned on again since (another addon): off again at the next target.
	c.enabled = true
	w:fire("PLAYER_TARGET_CHANGED")
	w:runTimers()
	H.eq(c.enabled, false, "off again")
	db.hideBlizzardTarget = false
	H.eq(Apply(w), "SSSS", "back")
	H.eq(c.enabled, true, "on again: the game's target auras show")
	Apply(w)
	H.eq(Sets(c), "SetEnabled false, SetEnabled false, SetEnabled true", "on once, and nothing after")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
end)

H.test("an aura container that was off stays off: HUDini gives back only what it took", function()
	local w = AuraWorld({ hideBlizzardTarget = true }, false)
	local c, db = w.auras, w.env.HUDiniDB
	H.eq(Apply(w), "SHSS", "hidden")
	db.hideBlizzardTarget = false
	H.eq(Apply(w), "SSSS", "back")
	H.eq(Sets(c), "", "never switched")
	H.eq(c.enabled, false, "still off")
end)

H.test("a forbidden, secret or unreadable aura container is left alone", function()
	-- It says it is forbidden: only the IsForbidden ask, no other call.
	local w = AuraWorld(nil)
	local c = w.auras
	rawset(c, "IsForbidden", function() return true end)
	w.env.HUDiniDB.hideBlizzardTarget = true
	H.eq(Apply(w), "SHSS", "the target frame still hides")
	H.eq(table.concat(c.calls, ", "), "", "no call into it")
	H.eq(c.enabled, true, "it stays on")

	-- Its IsForbidden throws.
	w = AuraWorld(nil)
	rawset(w.auras, "IsForbidden", function() error("forbidden") end)
	w.env.HUDiniDB.hideBlizzardTarget = true
	H.eq(Apply(w), "SHSS", "the target frame still hides")
	H.eq(table.concat(w.auras.calls, ", "), "", "no call into one that throws")

	-- The container itself, then its IsEnabled answer: plain, it is switched
	-- off; the same value flagged secret, it is left alone.
	local function Secret(flag)
		local plain = AuraWorld({ hideBlizzardTarget = true })
		H.eq(plain.auras.enabled, false, "plain: off")
		local sw = AuraWorld(nil)
		sw.secret[flag(sw)] = true
		sw.secretOn = true
		sw.env.HUDiniDB.hideBlizzardTarget = true
		H.eq(Apply(sw), "SHSS", "the target frame still hides")
		sw.secretOn = false
		return sw
	end
	w = Secret(function(sw) return sw.auras end)
	H.eq(table.concat(w.auras.calls, ", "), "", "no call into a secret container")
	w = Secret(function() return true end)
	H.eq(Sets(w.auras), "", "no switch on a secret IsEnabled answer")
	H.eq(w.auras.enabled, true, "it stays on")

	-- A key on the way throws when read, or is missing: no error.
	w = AuraWorld(nil)
	rawset(w.env.TargetFrame, "TargetFrameContent", setmetatable({}, {
		__index = function() error("forbidden") end,
	}))
	w.env.HUDiniDB.hideBlizzardTarget = true
	w.env.HUDiniDB.hideBlizzardCastBar = true
	H.eq(Apply(w), "SHHS", "the target frame and the frames after it hide")
	rawset(w.env.TargetFrame, "TargetFrameContent", {})
	H.eq(Apply(w), "SHHS", "a missing key: the same")
	H.eq(Sets(w.auras), "", "nothing switched")
end)

H.test("the aura container is switched in a fight too, and on in Edit Mode", function()
	local w = AuraWorld(nil)
	local c, db = w.auras, w.env.HUDiniDB
	w.combat = true
	db.hideBlizzardTarget = true
	Apply(w)
	H.eq(c.enabled, false, "a fight: off at once")
	db.hideBlizzardTarget = false
	Apply(w)
	H.eq(c.enabled, true, "a fight: on at once")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()

	db.hideBlizzardTarget = true
	Apply(w)
	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	H.eq(c.enabled, true, "Edit Mode: on, so its preview shows")
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	H.eq(c.enabled, false, "Edit Mode closed: off")
end)

H.test("an aura container that will not come back on is tried again", function()
	local w = AuraWorld({ hideBlizzardTarget = true })
	local c, db = w.auras, w.env.HUDiniDB
	Apply(w)
	H.eq(c.enabled, false, "off")
	c.throwOn = true
	db.hideBlizzardTarget = false
	H.eq(Apply(w), "SSSS", "the target frame is back")
	H.eq(w.ns.HUDini.needBlizzFrames, true, "the container waits")
	c.throwOn = nil
	Apply(w)
	H.eq(c.enabled, true, "on at the next apply")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
	-- One that will not switch off: the target frame still hides, and the
	-- next apply tries again.
	c.throwOn = false
	db.hideBlizzardTarget = true
	H.eq(Apply(w), "SHSS", "hidden")
	H.eq(c.enabled, true, "still on")
	c.throwOn = nil
	Apply(w)
	H.eq(c.enabled, false, "off at the next apply")
	db.hideBlizzardTarget = false
	Apply(w)
	H.eq(c.enabled, true, "and on at the end")
end)

-- A blocked action returns with no error, and a call may switch and then
-- throw: HUDini asks the container again after each call (TICK-0121,
-- review finding 1).
H.test("the container's answer after the call tells what happened, not the call", function()
	-- On that does nothing: the record stays, and the next apply tries again.
	local w = AuraWorld({ hideBlizzardTarget = true })
	local c, db = w.auras, w.env.HUDiniDB
	Apply(w)
	H.eq(c.enabled, false, "off")
	c.ignore = true
	db.hideBlizzardTarget = false
	H.eq(Apply(w), "SSSS", "the target frame is back")
	H.eq(c.enabled, false, "still off")
	H.eq(w.ns.HUDini.needBlizzFrames, true, "the container waits")
	c.ignore = nil
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.eq(c.enabled, true, "on at the next try")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")

	-- Off that does nothing: not recorded, tried again, and the target
	-- frame still hides.
	c.ignore = false
	db.hideBlizzardTarget = true
	H.eq(Apply(w), "SHSS", "hidden")
	H.eq(c.enabled, true, "still on")
	H.eq(w.ns.HUDini.needBlizzFrames, true, "the container waits")
	c.ignore = nil
	Apply(w)
	H.eq(c.enabled, false, "off at the next try")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
	db.hideBlizzardTarget = false
	Apply(w)
	H.eq(c.enabled, true, "and on at the end")

	-- Off that switches and then throws: recorded, so it comes back on.
	w = AuraWorld({ hideBlizzardTarget = true })
	c, db = w.auras, w.env.HUDiniDB
	c.throwAfter = false
	Apply(w)
	H.eq(c.enabled, false, "off, and it threw")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
	c.throwAfter = nil
	db.hideBlizzardTarget = false
	Apply(w)
	H.eq(c.enabled, true, "on again at the end")

	-- On that switches and then throws: done, the record goes.
	db.hideBlizzardTarget = true
	Apply(w)
	c.throwAfter = true
	db.hideBlizzardTarget = false
	Apply(w)
	H.eq(c.enabled, true, "on, and it threw")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
	c.throwAfter = nil
	local before = #c.calls
	Apply(w)
	H.eq(#c.calls, before, "no call after: the record is gone")

	-- A secret answer after the off: recorded, so it comes back on.
	w = AuraWorld(nil)
	c, db = w.auras, w.env.HUDiniDB
	local set = c.SetEnabled
	rawset(c, "SetEnabled", function(self, on)
		set(self, on)
		w.secret[on] = true
		w.secretOn = true
	end)
	db.hideBlizzardTarget = true
	Apply(w)
	H.eq(c.enabled, false, "off, with a secret answer after")
	w.secretOn = false
	rawset(c, "SetEnabled", set)
	db.hideBlizzardTarget = false
	Apply(w)
	H.eq(c.enabled, true, "on again at the end")

	-- A secret answer after the on: the record stays until a plain on.
	db.hideBlizzardTarget = true
	Apply(w)
	db.hideBlizzardTarget = false
	w.secret[true] = true
	w.secretOn = true
	Apply(w)
	H.eq(w.ns.HUDini.needBlizzFrames, true, "the container waits")
	w.secretOn = false
	Apply(w)
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
	before = #c.calls
	Apply(w)
	H.eq(#c.calls, before, "the record is gone")
end)

-- A frame may take motion (a tooltip) and no click: the player frame's
-- health and mana bars (PlayerFrame.xml:166/196, :248/307). EnableMouse(true)
-- at the restore would turn their clicks on, and a click there would no
-- longer target you or open your menu.
H.test("the restore gives back clicks and motion each as they were", function()
	local w = BlizzWorld(nil)
	local player = w.env.PlayerFrame
	local health = w:Frame(nil, player, { mouse = false, motion = true })
	table.insert(player.__h.children, health)
	w.env.HUDiniDB.hideBlizzardPlayer = true
	H.eq(Apply(w), "HSSS", "hidden")
	H.eq(health:IsMouseMotionEnabled(), false, "the health bar shows no tooltip")
	H.eq(player:IsMouseClickEnabled(), false, "the player frame takes no click")
	H.eq(player:IsMouseMotionEnabled(), false, "nor motion")

	w.env.HUDiniDB.hideBlizzardPlayer = false
	H.eq(Apply(w), "SSSS", "back")
	H.eq(health:IsMouseMotionEnabled(), true, "the health bar shows its tooltip")
	H.eq(health:IsMouseClickEnabled(), false, "and still takes no click")
	H.eq(player:IsMouseClickEnabled(), true, "the player frame takes clicks")
	H.eq(player:IsMouseMotionEnabled(), true, "and motion")
end)

-- An event the game will not register now stays on HUDini's list, and the
-- next apply tries it again, so the cast bar is not dead until a reload.
H.test("a cast bar event that fails to come back is tried again", function()
	local w = BlizzWorld({ hideBlizzardCastBar = true })
	local bar = w.env.PlayerCastingBarFrame
	H.eq(State(w), "SSHS", "hidden")
	local register = getmetatable(bar).__index(bar, "RegisterUnitEvent")
	local fail = true
	bar.RegisterUnitEvent = function(self, e, ...)
		if fail and e == "UNIT_SPELLCAST_START" then error("not now") end
		return register(self, e, ...)
	end
	w.env.HUDiniDB.hideBlizzardCastBar = false
	Apply(w)
	H.eq(bar:IsEventRegistered("UNIT_SPELLCAST_START"), false, "not back yet")
	H.ok(bar:IsEventRegistered("UNIT_SPELLCAST_CHANNEL_START"), "the others are back")
	H.eq(w.ns.HUDini.needBlizzFrames, true, "it waits for the next apply")
	fail = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.ok(bar:IsEventRegistered("UNIT_SPELLCAST_START"), "the fight's end: back")
	H.ok(bar.__h.units.UNIT_SPELLCAST_START.player, "for the player")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
end)

-- A frame under a hidden frame whose GetChildren throws: the walk goes on
-- to the next frame, and no error comes out.
H.test("the mouse walk goes on past a frame whose children cannot be read", function()
	local w = BlizzWorld(nil)
	local errors = {}
	w.env.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
	local player = w.env.PlayerFrame
	local bad = w:Frame(nil, player, { mouse = true })
	table.insert(player.__h.children, bad)
	bad.GetChildren = function() error("no children") end
	local after = w:Frame(nil, player, { mouse = true })
	table.insert(player.__h.children, after)
	w.env.HUDiniDB.hideBlizzardPlayer = true
	H.eq(Apply(w), "HSSS", "hidden")
	H.eq(bad.__h.mouse, false, "the frame itself takes no click")
	H.eq(after.__h.mouse, false, "the frame after it takes no click")
	H.eq(table.concat(errors, " | "), "", "no error")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
end)

-- A frame's apply that throws: its error shows once, the other frames are
-- still hidden, it is tried again at the fight's end, and an error after an
-- apply that worked shows again.
H.test("an apply that throws is tried again, and a later error shows again", function()
	local w = BlizzWorld(nil)
	local errors = {}
	w.env.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
	local player = w.env.PlayerFrame
	local mt = getmetatable(player)
	local index = mt.__index
	local boom = "boom one"
	setmetatable(player, { __index = function(t, k)
		if k == "GetAlpha" and boom then error(boom) end
		if type(index) == "function" then return index(t, k) end
		return index[k]
	end })
	local db = w.env.HUDiniDB
	db.hideBlizzardPlayer, db.hideBlizzardTarget = true, true
	H.eq(Apply(w), "SHSS", "the player frame fails; the target frame is hidden")
	H.eq(#errors, 1, "the error shows")
	H.ok(errors[1]:find("boom one"), "the error is the apply's")
	H.eq(w.ns.HUDini.needBlizzFrames, true, "the failed frame waits for the next apply")
	Apply(w)
	H.eq(#errors, 1, "the same error shows once")

	boom = nil
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(State(w), "HHSS", "the fight's end: tried again, hidden")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")

	boom = "boom two"
	Apply(w)
	H.eq(#errors, 2, "an error after an apply that worked shows again")
	H.ok(errors[2]:find("boom two"))
end)

-- Blizzard makes the pet frame's parts (PetFrame.xml:11) and the totem
-- buttons (TotemFrame.xml:56) under PlayerFrame after login, with their
-- mouse on. A pet aura made later waits for the next apply: Auras.lua has
-- the one UNIT_AURA handler (TICK-0065). The pet frame is kept on screen
-- (TICK-0104), so its parts keep their mouse; this is the case where it
-- cannot be, and hides with the player frame.
H.test("Hide player frame turns off the mouse of a new pet's parts or a totem made later", function()
	local w = BlizzWorld({ hideBlizzardPlayer = true })
	rawset(w.pet, "SetIgnoreParentAlpha", function() error("not on this client") end)
	local hud = w.ns.HUDini
	local applies = 0
	local real = hud.ApplyBlizzardFrames
	hud.ApplyBlizzardFrames = function(self, ...)
		applies = applies + 1
		return real(self, ...)
	end
	local function Part(parent)
		local f = w:Frame(nil, parent, { mouse = true })
		table.insert(parent.__h.children, f)
		return f
	end

	local pet = Part(w.pet)
	w:fire("UNIT_PET", "player")
	H.eq(pet.__h.mouse, true, "not in Blizzard's handler for the event")
	w:runTimers()
	H.eq(pet.__h.mouse, false, "a new pet's part shows no tooltip")

	w.combat = true
	local totem = Part(w.env.PlayerFrame)
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	w:runTimers()
	H.eq(totem.__h.mouse, false, "a new totem button, in a fight")
	w.combat = false

	applies = 0
	w:fire("UNIT_PET", "target")
	w:runTimers()
	H.eq(applies, 0, "not for another unit's pet")

	w.env.HUDiniDB.hideBlizzardPlayer = false
	Apply(w)
	applies = 0
	w:fire("UNIT_PET", "player")
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	w:runTimers()
	H.eq(applies, 0, "with Hide player frame off, no apply")
end)

-- The hidden frame itself: only a plain "forbidden" leaves it alone. A
-- secret answer, or a call that throws, is "not done": a later apply asks
-- again (in the game IsForbidden may be secret, ObjectSecurity).
H.test("a hidden frame whose IsForbidden is secret or throws is asked again", function()
	local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
	local w = H.world()
	MakeFrames(w)
	w.env.issecretvalue = function(v) return v == SECRET end
	local player = w.env.PlayerFrame
	local answer = SECRET
	player.IsForbidden = function()
		if answer == "throw" then error("cannot ask") end
		return answer
	end
	w.env.HUDiniDB = { hideBlizzardPlayer = true }
	w:loadAddon()
	H.eq(State(w), "HSSS", "hidden by alpha")
	H.eq(player.__h.mouse, true, "a secret answer: the mouse is not turned off yet")
	H.eq(w.ns.HUDini.needBlizzFrames, true, "it waits for the next apply")

	answer = "throw"
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(player.__h.mouse, true, "a call that throws: not yet")
	H.eq(w.ns.HUDini.needBlizzFrames, true, "it still waits")

	answer = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(player.__h.mouse, false, "a plain false: the mouse is off")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")

	-- A plain true: left alone, and nothing waits.
	w.env.HUDiniDB.hideBlizzardPlayer = false
	Apply(w)
	answer = true
	w.env.HUDiniDB.hideBlizzardPlayer = true
	H.eq(Apply(w), "HSSS")
	H.eq(player.__h.mouse, true, "a forbidden frame keeps its mouse")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
end)

-- TICK-0104, TICK-0105: the pet frame and target of target stay on screen
-- while their parent is hidden. A frame's alpha on screen: its own, times
-- each parent's, up to the first that ignores its parent's alpha.
local function Seen(f)
	local a = f.__h.alpha
	while not f.__h.ignoreParentAlpha and f.__h.parent do
		f = f.__h.parent
		a = a * f.__h.alpha
	end
	return a
end

local KEPT = {
	{ setting = "hideBlizzardPlayer", parent = "PlayerFrame", kept = "pet", what = "the pet frame" },
	{ setting = "hideBlizzardTarget", parent = "TargetFrame", kept = "tot", what = "target of target" },
}

for _, k in ipairs(KEPT) do
	H.test(k.what .. " stays on screen, with its mouse, while " .. k.parent .. " is hidden", function()
		local w = BlizzWorld(nil)
		local parent, kept = w.env[k.parent], w[k.kept]
		local part = w:Frame(nil, kept, { mouse = true })
		table.insert(kept.__h.children, part)
		local other = w:Frame(nil, parent, { mouse = true })
		table.insert(parent.__h.children, other)
		H.eq(Seen(kept), 1, "shown before the hide")

		w.env.HUDiniDB[k.setting] = true
		Apply(w)
		H.eq(Seen(parent), 0, "the parent is hidden")
		H.eq(Seen(other), 0, "and the rest under it")
		H.eq(other.__h.mouse, false, "the rest takes no click")
		H.eq(Seen(kept), 1, k.what .. " shows")
		H.eq(Seen(part), 1, "and its parts")
		H.eq(kept.__h.mouse, true, k.what .. " keeps its click")
		H.eq(part.__h.mouse, true, "and its parts their mouse")

		w.env.HUDiniDB[k.setting] = false
		Apply(w)
		H.eq(kept.__h.ignoreParentAlpha, false, "back: it follows the parent again")
		H.eq(Seen(kept), 1, "and shows")
		H.eq(other.__h.mouse, true, "the rest takes clicks again")
	end)
end

H.test("a kept frame gets back the ignore it had, and Edit Mode gives it back too", function()
	local w = BlizzWorld({ hideBlizzardPlayer = true, hideBlizzardTarget = true })
	H.eq(w.pet.__h.ignoreParentAlpha, true, "hidden at login: the pet frame is kept")
	H.eq(w.tot.__h.ignoreParentAlpha, true, "and target of target")

	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	H.eq(w.pet.__h.ignoreParentAlpha, false, "in Edit Mode it follows the player frame's Opacity")
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	H.eq(w.pet.__h.ignoreParentAlpha, true, "kept again after Edit Mode")

	-- Something else had set it already: HUDini gives back that value.
	local w2 = BlizzWorld(nil)
	w2.tot:SetIgnoreParentAlpha(true)
	w2.env.HUDiniDB.hideBlizzardTarget = true
	Apply(w2)
	w2.env.HUDiniDB.hideBlizzardTarget = false
	Apply(w2)
	H.eq(w2.tot.__h.ignoreParentAlpha, true, "its own true stays")
end)

H.test("a kept frame's own value is read once, however often the hide is applied", function()
	-- A target change, a new pet or a totem applies the hide again while it
	-- is on. HUDini's own true must not be saved as the frame's value.
	local w = BlizzWorld(nil)
	w.pet:SetIgnoreParentAlpha(false)
	w.env.HUDiniDB.hideBlizzardPlayer = true
	Apply(w)
	Apply(w)
	w:fire("PLAYER_TARGET_CHANGED")
	w.env.HUDiniDB.hideBlizzardPlayer = false
	Apply(w)
	H.eq(w.pet.__h.ignoreParentAlpha, false, "back: its own false")

	-- After the hide is off, a new value is read at the next hide.
	w.pet:SetIgnoreParentAlpha(true)
	w.env.HUDiniDB.hideBlizzardPlayer = true
	Apply(w)
	w.env.HUDiniDB.hideBlizzardPlayer = false
	Apply(w)
	H.eq(w.pet.__h.ignoreParentAlpha, true, "back: the true it had at this hide")
end)

H.test("a secret ignore answer is not saved as true, and throws nothing", function()
	-- The true that would be saved, flagged secret for the one check after it.
	local w = H.world()
	MakeFrames(w)
	w.env.issecretvalue = function(v)
		if w.armed and v == true then w.armed = false return true end
		return false
	end
	w:loadAddon()
	w.pet:SetIgnoreParentAlpha(false)
	rawset(w.pet, "IsIgnoringParentAlpha", function() w.armed = true return true end)
	w.env.HUDiniDB.hideBlizzardPlayer = true
	Apply(w)
	H.eq(Seen(w.pet), 1, "the pet frame is kept")
	w.env.HUDiniDB.hideBlizzardPlayer = false
	Apply(w)
	H.eq(w.pet.__h.ignoreParentAlpha, false, "back: false, not the secret true")
end)

H.test("the pet frame is kept on screen in a fight too", function()
	-- SetIgnoreParentAlpha is not protected (SimpleRegionAPIDocumentation
	-- .lua:158). The world fails the test on a blocked call.
	local w = BlizzWorld(nil)
	w.combat = true
	w.env.HUDiniDB.hideBlizzardPlayer = true
	Apply(w)
	H.eq(Seen(w.env.PlayerFrame), 0, "the player frame hides at once")
	H.eq(Seen(w.pet), 1, "the pet frame shows at once")
end)

H.test("a kept frame that cannot be kept hides with its parent and loses its mouse", function()
	local w = BlizzWorld(nil)
	rawset(w.pet, "SetIgnoreParentAlpha", function() error("not on this client") end)
	w.env.HUDiniDB.hideBlizzardPlayer = true
	Apply(w)
	H.eq(Seen(w.pet), 0, "the pet frame hides with the player frame")
	H.eq(w.pet.__h.mouse, false, "and takes no click while it is not seen")
	w.env.HUDiniDB.hideBlizzardPlayer = false
	Apply(w)
	H.eq(w.pet.__h.mouse, true, "back: its click")

	-- A forbidden one: HUDini leaves it and all under it alone.
	local w2 = BlizzWorld(nil)
	rawset(w2.tot, "IsForbidden", function() return true end)
	w2.env.HUDiniDB.hideBlizzardTarget = true
	Apply(w2)
	H.eq(w2.tot.__h.ignoreParentAlpha, nil, "a forbidden target of target is not touched")
	H.eq(w2.tot.__h.mouse, true, "nor its mouse")
end)

H.test("no pet frame or target of target on the client: the hides still work", function()
	local w = H.world()
	for _, name in ipairs(FRAMES) do w:Frame(name, nil, { protected = true, mouse = true }) end
	XPParts(w)
	w.env.HUDiniDB = { hideBlizzardPlayer = true, hideBlizzardTarget = true }
	w:loadAddon()
	H.eq(Seen(w.env.PlayerFrame), 0, "the player frame hides")
	H.eq(Seen(w.env.TargetFrame), 0, "the target frame hides")
end)
