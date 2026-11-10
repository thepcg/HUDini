--[[--------------------------------------------------------------------------
	HUDini - Core

	The heart of the addon. It builds one grid of icons from the spells and
	items on your action bars, and makes each icon act like the real button
	behind it:

		* the cooldown sweep, including the global cooldown
		* the proc glow, when Blizzard lights an ability up
		* the Assisted Combat highlight, the "press this next" hint
		* dim when you cannot pay for it, red when out of range

	It also owns the saved settings, decides when the HUD shows
	(HUDini:ShouldShow), hides the Blizzard frames HUDini replaces, and runs
	the /hud commands. The other files hang off the shared ns table:

		Classes.lua  per-class data: interrupt, dispels, keep-up buffs
		Bars.lua     health, power, cast and resource bars above the grid
		XP.lua       the XP bar
		Alerts.lua   kick outline, keep-up icon, dispel tint, purgeable buffs
		Auras.lua    buff time on icons, buffs to reapply, weapon buffs
		Clicks.lua   click the health bars to target, right-click for the menu
		Feed.lua     the feed box: fading lines, the highlight, the session
		FeedLoot.lua feed lines from chat: loot, currency, crafts, rep, skills
		FeedGains.lua feed lines for XP, money, quests, levels, discoveries
		FeedWatch.lua feed lines for bags, gear, spells, collections, progress
		Mover.lua    drag and scale Blizzard's windows
		Options.lua  the Options -> AddOns panel

	Sections, in order: defaults, secret value guard, action slots and
	keybinds, the frame, reading the action bars, icon frames, layout, live
	state, rebuild and when to show, Blizzard frames, mouseover, position,
	events, slash commands.

	Secrets: 12.x hides combat data (health, cooldowns, auras) behind "secret
	values" that throw an error when compared. Nothing here reads one.
	Cooldowns travel as DurationObjects straight from C_ActionBar into the
	Cooldown widget, and anything that might come back secret goes through
	Plain() first.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- The version is typed in one place only: ## Version in HUDini.toc.
-- /hud version prints it. The game reads the TOC only when it starts, so
-- after a new build is copied in, /reload still shows the old version:
-- restart the game to see the new one.
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetMetadata and GetMetadata(ADDON, "Version") or "unknown"

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local tinsert, tsort, wipe = table.insert, table.sort, wipe

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------

-- Every setting and its default. HUDiniDB starts as a copy, filled in key by
-- key at login (FillDefaults), so a new setting gets its default without
-- touching the ones you changed. The look (fonts, colours, layout) is
-- account-wide; the grid position and spell choices are kept per class in
-- HUDiniDB.classes (Classes.lua). A part that can be switched off adds its
-- own settings when it loads (ns.NewModule, Modules.lua): the feed in
-- Feed.lua, the XP bar in XP.lua, the window mover in Mover.lua.
ns.defaults = {
	-- Position. Each class keeps its own spot; this is where a new one starts.
	locked   = true,   -- a new install starts locked, so it hides when idle (/hud unlock to move it)
	point    = "CENTER",
	relPoint = "CENTER",
	x        = 0,
	y        = -180,
	scale    = 1.0,

	-- When to show (HUDini:ShouldShow). With hideWhenIdle off it never hides.
	hideWhenIdle        = true,  -- hide the grid until something needs you
	showInCombat        = true,  -- ... show it while you are in combat
	showOnHostile       = true,  -- ... while you target something you can attack
	showWhenHurt        = true,  -- ... while your health is below full
	showWhenPower       = true,  -- ... while your power is not at rest (full, or empty rage)
	showWhenBuffMissing = true,  -- ... while a buff you keep up is off
	fadeOutTime         = 3,     -- seconds to fade out once idle; showing is instant

	-- The icon grid.
	layoutMode = "bar",      -- "bar": a row each for Bars 1-3; "wrap": pack and wrap
	sortMode   = "keybind",  -- "keybind" or "actionbar"
	maxIcons   = 12,         -- wrap mode: the most icons to show
	perRow     = 6,          -- wrap mode: icons before a new row
	minIcons   = 6,          -- the grid is never narrower than this many icons
	iconSize   = 40,
	spacing    = 4,
	growRight  = true,
	growDown   = true,
	autoBars   = true,       -- wrap mode: only read bars that are shown on screen
	bars       = {           -- wrap mode with autoBars off: the bars to read
		bar1 = true, bar2 = true, bar3 = true, bar4 = true,
		bar5 = false, bar6 = false, bar7 = false, bar8 = false,
	},

	-- What each icon shows.
	showKeybind  = true,
	showTooltips = true,     -- an icon's tooltip on hover
	showCooldown = true,
	showProcGlow = true,
	showAssist   = true,     -- the Assisted Combat "press this next" ring
	showUsable   = true,     -- dim what you cannot pay for
	showRange    = true,     -- red when out of range
	showBuffTime = true,     -- buff time left on the icon that gives the buff
	auraMap      = {},       -- your own extra buff names, see Auras.lua

	-- Your bars (Bars.lua, XP.lua).
	showHealth     = true,
	damageTrail    = true,   -- a hit leaves the lost chunk showing, then drains
	showPower      = true,   -- mana, rage or energy, whichever you use now
	showPlayerCast = true,   -- your cast bar, see-through on top of the power bar
	castAlpha      = 0.55,
	showResource   = true,   -- the class resource, when the class file has one

	-- Your target's bars.
	showTargetHealth = true,
	showTargetPower  = true, -- its mana, rage or energy, on its own bar under its health (TICK-0126)
	showTargetCast   = true, -- the target's cast, on the target's power bar (TICK-0126)
	showRankMark     = true, -- "Elite", "Rare", "Rare Elite" or "Boss" after the target's level
	colorTargetLevel = true, -- the target's level in the game's difficulty color (Bars.lua)
	showDeadState    = true, -- Dead, Ghost or Offline on a gray health bar (Bars.lua)
	barNumbers       = "percent", -- "off", "percent", "number" or "both" on the health and power bars (Bars.lua)
	showPvPMark      = true, -- a faction mark on your bar and a player target's, while flagged

	-- Left-click a health bar to target, right-click for the unit's menu (Clicks.lua).
	clickBars        = true,

	-- How the bars look.
	barTexture   = "blizzard",
	barFont      = "default",
	fontSize     = 12,
	healthHeight = 30,       -- the two health bars, in pixels
	barHeight    = 10,       -- every other bar, the two power bars too
	barGap       = 2,
	colors       = {          -- every bar colour, { r, g, b }, set with a picker
		health     = { 0.16, 0.72, 0.22 },
		trail      = { 1.00, 0.45, 0.35 },  -- the damage trail under your health
		mana       = { 0.20, 0.45, 0.95 },
		rage       = { 0.85, 0.20, 0.20 },
		energy     = { 1.00, 0.85, 0.25 },
		resource   = { 0.45, 0.86, 1.00 },
		playercast = { 1.00, 1.00, 1.00 },
		xp         = { 0.58, 0.20, 0.78 },
		rested     = { 0.20, 0.45, 0.90 },
		hostile    = { 0.78, 0.22, 0.20 },  -- target health follows disposition
		neutral    = { 0.85, 0.72, 0.18 },
		friendly   = { 0.16, 0.72, 0.22 },
		tapped     = { 0.92, 0.92, 0.92 },  -- a mob someone else has tagged
		interrupt  = { 1.00, 0.82, 0.00 },  -- target cast you can kick
		shielded   = { 0.52, 0.52, 0.52 },  -- target cast you cannot
	},

	-- How much flair HUDini's words have (D-011, TICK-0055): 0 Light,
	-- 1 Modest, 2 Full. ns.Text reads it for each line.
	flair = 0,

	-- Alerts (Alerts.lua). The spells behind them come from the class file.
	glowOnKickable = true,   -- pulsing outline on a target cast you can kick
	warnKeepUp     = true,   -- icon by the health bar in a fight with no keep-up buff
	warnDispel     = true,   -- power bar takes the colour of a debuff you can dispel
	showPurgeable  = true,   -- the target's buffs you can purge, on its health bar
	warnNoBait     = true,   -- "No bait" by the health bar: a fishing pole with nothing on it
	warnTargetBuff = true,   -- a long buff of yours a friendly target lacks, by its health bar
	warnOwnBuff    = true,   -- a long buff you keep up that is off, by your health bar
	warnRacial     = true,   -- your race's ability glows while it can help (Stoneform)

	-- Blizzard's own UI. Each hide is opt-in. The frame hides work only while
	-- HUDini's matching bars are on; the XP bar hide works on its own
	-- (BLIZZ_FRAMES).
	hideBlizzardPlayer   = false, -- your own frame, with the pet frame; needs showHealth and showPower
	hideBlizzardTarget   = false, -- the target frame and its cast bar; needs showTargetHealth
	hideBlizzardCastBar  = false, -- your cast bar; needs showPlayerCast and showPower
	hideBlizzardXP       = false, -- the XP bar, only while you earn XP; showXP not needed (TICK-0080)
	bagBarMouseover      = false, -- the bag bar shows only under the mouse
	menuBarMouseover     = false, -- ... and the menu buttons
	minimapMouseover     = false, -- ... and the minimap

	-- The minimap button (MinimapButton.lua): shown, and its place on the
	-- minimap edge in degrees (0 = right, 90 = top).
	minimapButton = true,
	minimapAngle  = 225,
}

-- Fill in every missing setting from ns.defaults. A table setting is filled
-- key by key, so a colour you picked survives a new default colour.
local function FillDefaults(db)
	for k, v in pairs(ns.defaults) do
		if type(v) == "table" then
			db[k] = db[k] or {}
			for k2, v2 in pairs(v) do
				if db[k][k2] == nil then db[k][k2] = v2 end
			end
		elseif db[k] == nil then
			db[k] = v
		end
	end
end

--------------------------------------------------------------------------------
-- Secret value guard: Plain() hands back nil instead of a secret, so every
-- test below can fail safe. It lives in Util.lua.
--------------------------------------------------------------------------------

local Plain, IsSecret = ns.Plain, ns.IsSecret
local Text = ns.Text

--------------------------------------------------------------------------------
-- Action slot -> binding name map
--
-- Each of the eight bars owns a block of twelve slots (its frame's action
-- page in Blizzard's MultiActionBars.xml), a frame, and a matching binding
-- name: Bars 1-5 are slots 1-72, Bars 6-8 are slots 145-180 (pages 13-15).
-- Slots 73-120 are the bonus bars (Druid forms, Rogue stealth): only Bar 1
-- reads them, when it turns its page (Bar1Page).
--------------------------------------------------------------------------------

local BAR_LAYOUT = {
	{ order = 1, first =   1, name = Text("core.actionBar", 1), frame = "MainMenuBar",          binding = "ACTIONBUTTON%d"          },
	{ order = 2, first =  61, name = Text("core.actionBar", 2), frame = "MultiBarBottomLeft",  binding = "MULTIACTIONBAR1BUTTON%d" },
	{ order = 3, first =  49, name = Text("core.actionBar", 3), frame = "MultiBarBottomRight", binding = "MULTIACTIONBAR2BUTTON%d" },
	{ order = 4, first =  25, name = Text("core.actionBar", 4), frame = "MultiBarRight",       binding = "MULTIACTIONBAR3BUTTON%d" },
	{ order = 5, first =  37, name = Text("core.actionBar", 5), frame = "MultiBarLeft",        binding = "MULTIACTIONBAR4BUTTON%d" },
	{ order = 6, first = 145, name = Text("core.actionBar", 6), frame = "MultiBar5",           binding = "MULTIACTIONBAR5BUTTON%d" },
	{ order = 7, first = 157, name = Text("core.actionBar", 7), frame = "MultiBar6",           binding = "MULTIACTIONBAR6BUTTON%d" },
	{ order = 8, first = 169, name = Text("core.actionBar", 8), frame = "MultiBar7",           binding = "MULTIACTIONBAR7BUTTON%d" },
}
-- Setup reads it for the bars notice on page 7 (Setup.lua).
ns.BAR_LAYOUT = BAR_LAYOUT

-- Bar 1 turns its page (TICK-0071). It shows page 1 unless you turn it
-- with Shift and a number or the arrows (pages 2-6). A Druid form or a
-- Rogue's Stealth gives it a bonus bar: while it is on page 1, bonus bar 1-4
-- turns it to page 7-10 (slots 73-120), as Blizzard's main bar does. Not
-- read: a vehicle, override or temporary shapeshift bar, and bonus bar 5
-- (Skyriding). An API missing, a secret, or any answer that is not a page
-- counts as page 1.
local function ActionAPI(name)
	return (C_ActionBar and C_ActionBar[name]) or _G[name]
end

local function WholeIn(v, lo, hi)
	v = Plain(v)
	if type(v) == "number" and v == floor(v) and v >= lo and v <= hi then return v end
	return nil
end

local function Ask(name)
	local fn = ActionAPI(name)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn)
	if ok then return v end
	return nil
end

local function Bar1Page()
	local page = WholeIn(Ask("GetActionBarPage"), 1, 6) or 1
	if page == 1 then
		local offset = WholeIn(Ask("GetBonusBarOffset"), 1, 4)
		if offset then page = 6 + offset end
	end
	return page
end

ns.Bar1Page = Bar1Page

-- The first of the twelve slots a bar reads now. Bar 1's turns with its page.
local function BarFirst(bar, page)
	if bar.order == 1 then return (page - 1) * 12 + 1 end
	return bar.first
end

--------------------------------------------------------------------------------
-- Keybind ranking
--
-- Turns "ALT-SHIFT-4" into a number so the icons can be sorted the way the
-- keys sit under your hand: no modifier first, then Shift, Ctrl, Alt.
--------------------------------------------------------------------------------

local MOD_RANK = {
	[""]                = 0,
	["SHIFT-"]          = 1,
	["CTRL-"]           = 2,
	["CTRL-SHIFT-"]     = 3,
	["ALT-"]            = 4,
	["ALT-SHIFT-"]      = 5,
	["ALT-CTRL-"]       = 6,
	["ALT-CTRL-SHIFT-"] = 7,
}

local BASE_RANK = {
	["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
	["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9, ["0"] = 10,
	["-"] = 11, ["="] = 12,
}

local function SplitBinding(key)
	local mods, rest = "", key
	while true do
		local m = rest:match("^(ALT%-)") or rest:match("^(CTRL%-)") or rest:match("^(SHIFT%-)")
		if not m then break end
		mods = mods .. m
		rest = rest:sub(#m + 1)
	end
	return mods, rest
end

local function BaseRank(base)
	if BASE_RANK[base] then return BASE_RANK[base] end
	local fn = base:match("^F(%d+)$")
	if fn then return 100 + tonumber(fn) end
	local mb = base:match("^BUTTON(%d+)$")
	if mb then return 200 + tonumber(mb) end
	if base == "MOUSEWHEELUP"   then return 300 end
	if base == "MOUSEWHEELDOWN" then return 301 end
	if #base == 1 then return 400 + base:byte() end
	return 900
end

local function BindingRank(key)
	if not key or key == "" then return 999999 end
	local mods, base = SplitBinding(key)
	return (MOD_RANK[mods] or 9) * 10000 + BaseRank(base)
end

local SHORT_MOD = { ["ALT%-"] = "a", ["CTRL%-"] = "c", ["SHIFT%-"] = "s" }

local function ShortKey(key)
	if not key or key == "" then return "" end
	local out = key
	for pattern, letter in pairs(SHORT_MOD) do
		out = out:gsub(pattern, letter)
	end
	out = out:gsub("BUTTON", "m")
	out = out:gsub("MOUSEWHEELUP", "mu")
	out = out:gsub("MOUSEWHEELDOWN", "md")
	out = out:gsub("NUMPAD", "n")
	return out
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local HUDini = CreateFrame("Frame", "HUDiniAnchor", UIParent)
ns.HUDini = HUDini

HUDini.icons   = {}
HUDini.spells  = {}
HUDini.glowing = {}  -- [spellID] = true while Blizzard says it is procced
HUDini.alertGlow = {} -- [source] = the spellID an alert lights (Alerts.lua)
HUDini:SetMovable(true)
HUDini:SetClampedToScreen(true)
HUDini:Show()

-- The anchor frame never hides. The body does. That keeps the target bars on
-- screen whenever you have a target, even out of combat.
HUDini.body = CreateFrame("Frame", "HUDiniBody", HUDini)
HUDini.body:SetAllPoints(HUDini)

-- The blue box /hud unlock shows. It is a frame of its own, above the icons
-- and the bars and over all of them (HUDini:Layout sizes it), so there is
-- always something to see and grab. A texture under the icons was hidden
-- when every slot was full (TICK-0053). Locked, it hides and takes no mouse.
HUDini.mover = CreateFrame("Frame", "HUDiniMoveBox", HUDini)
HUDini.mover:SetFrameLevel(HUDini:GetFrameLevel() + 50)
HUDini.mover:EnableMouse(true)
HUDini.mover:RegisterForDrag("LeftButton")
HUDini.mover:Hide()

HUDini.bg = HUDini.mover:CreateTexture(nil, "BACKGROUND")
HUDini.bg:SetAllPoints()
HUDini.bg:SetColorTexture(0, 0.6, 1, 0.15)

HUDini.mover:SetScript("OnDragStart", function()
	if not HUDiniDB.locked then HUDini:StartMoving() end
end)

HUDini.mover:SetScript("OnDragStop", function()
	HUDini:StopMovingOrSizing()
	-- Each class keeps its own spot.
	local point, _, relPoint, x, y = HUDini:GetPoint()
	local mine = ns.ClassDB()
	mine.point, mine.relPoint = point, relPoint
	mine.x, mine.y = x, y
end)

--------------------------------------------------------------------------------
-- Reading the action bars
--------------------------------------------------------------------------------

-- Decides whether a bar counts.
--   autoBars on  : read the bar only when it is actually on screen.
--   autoBars off : read the bar only when its checkbox is ticked.
-- Bar 1 always counts. It cannot be turned off in the game.
local function BarEnabled(bar)
	local db = HUDiniDB
	if bar.order == 1 then return true end

	if db.autoBars then
		local f = _G[bar.frame]
		return (f and f:IsShown()) and true or false
	end

	return db.bars["bar" .. bar.order] and true or false -- locale: skip a setting key
end

ns.BarEnabled = BarEnabled

-- Returns "spell", spellID or "item", itemID. nil when the slot holds nothing
-- we can draw. A macro counts as whatever it casts or uses.
local function SlotAction(slot)
	local actionType, id = GetActionInfo(slot)
	if not actionType or not id then return nil end

	if actionType == "spell" then
		if id > 0 then return "spell", id end
	elseif actionType == "item" then
		return "item", id
	elseif actionType == "macro" then
		local spellID = GetMacroSpell(id)
		if spellID then return "spell", spellID end
		local _, link = GetMacroItem(id)
		local itemID = link and tonumber(link:match("item:(%d+)"))
		if itemID then return "item", itemID end
	end
	return nil
end

ns.SlotAction = SlotAction

-- Every spell on the eight action bars, by name, A to Z, each name once:
-- the "Your class" page's choices (TICK-0069). Every bar counts, on screen
-- or not. A macro counts as the spell it casts. In a fight a slot or a name
-- may be secret; that one is left out, and the list still comes back.
function ns.ActionBarSpells()
	local names, seen = {}, {}
	for _, bar in ipairs(BAR_LAYOUT) do
		for i = 1, 12 do
			local ok, kind, id = pcall(SlotAction, bar.first + i - 1)
			if ok and kind == "spell" and not ns.IsSecret(id) then
				local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
				if not ns.IsSecret(name) and type(name) == "string" and name ~= "" and not seen[name] then
					seen[name] = true
					names[#names + 1] = name
				end
			end
		end
	end
	table.sort(names)
	return names
end

-- "bar" row mode mirrors these bars, one row each: Bar 1 is row 1, Bar 2 is
-- row 2, Bar 3 is row 3. Nothing else is read.
local ROW_BARS = 3

-- Walks every enabled slot and returns a de-duplicated, sorted spell list.
function HUDini:Scan()
	local db = HUDiniDB
	local byBar = (db.layoutMode == "bar")
	local found = {}
	local seen  = {}
	local page  = Bar1Page()
	self.bar1Page = page

	-- Walk the bars in bar order so a spell placed on two bars always keeps
	-- the copy on the lower bar. In "bar" row mode each row mirrors its bar,
	-- so a spell on two bars shows on both rows.
	for _, bar in ipairs(BAR_LAYOUT) do
		local wanted
		if byBar then
			wanted = bar.order <= ROW_BARS
			seen = {}
		else
			wanted = BarEnabled(bar)
		end
		if wanted then
			local first = BarFirst(bar, page)
			for i = 1, 12 do
				local slot = first + i - 1
				local kind, id = SlotAction(slot)
				local seenKey = kind and (kind .. id)
				if kind and not seen[seenKey] then
					-- The key is the button's, on any page: Cat Form's slot 73
					-- is still Bar 1's button 1.
					local key = GetBindingKey(bar.binding:format(i))
					seen[seenKey] = true
					tinsert(found, {
						spellID   = (kind == "spell") and id or nil,
						itemID    = (kind == "item")  and id or nil,
						slot      = slot,
						barOrder  = bar.order,
						barName   = bar.name,
						key       = key,
						keyRank   = BindingRank(key),
						slotRank  = bar.order * 100 + i,
						button    = i,
					})
				end
			end
		end
	end

	-- In "bar" row mode the bar wins first, so Bar 2 always follows Bar 1.
	-- Inside a bar the chosen sort mode decides the order.
	local byKey = (db.sortMode ~= "actionbar")

	tsort(found, function(a, b)
		if byBar and a.barOrder ~= b.barOrder then return a.barOrder < b.barOrder end
		if byKey and a.keyRank ~= b.keyRank then return a.keyRank < b.keyRank end
		if a.slotRank ~= b.slotRank then return a.slotRank < b.slotRank end
		return a.slot < b.slot
	end)

	-- The icon cap only applies to "wrap". A mirrored bar is never cut short.
	wipe(self.spells)
	for i = 1, byBar and #found or min(#found, db.maxIcons) do
		self.spells[i] = found[i]
	end

	self:Place()
	return self.spells
end

-- Gives every entry a row and a column.
--   "wrap" packs the icons into one stream and breaks every perRow icons.
--   "bar"  puts Bar N on row N, always. A bar never wraps, and an empty bar
--          keeps its row, so Bar 3 never slides up into Bar 2's place.
function HUDini:Place()
	local db     = HUDiniDB
	local perRow = max(1, db.perRow)

	if db.layoutMode ~= "bar" then
		for i, e in ipairs(self.spells) do
			e.col = (i - 1) % perRow
			e.row = floor((i - 1) / perRow)
		end
		return
	end

	local col = {}
	for _, e in ipairs(self.spells) do
		e.row = e.barOrder - 1
		e.col = col[e.barOrder] or 0
		col[e.barOrder] = e.col + 1
	end
end

--------------------------------------------------------------------------------
-- Icon frames
--
-- Each icon is a CheckButton so it can be handed to
-- C_ActionBar.RegisterActionUIButton. That registration is what lets the game
-- drive the checked state and count the icon as a visible action for the
-- Assisted Combat highlight.
--------------------------------------------------------------------------------

local GLOW_TEXTURE = "Interface\\SpellActivationOverlay\\IconAlert"
local GLOW_COORDS  = { 0.00781250, 0.50781250, 0.27734375, 0.52734375 }

local function CreateIcon(parent, index)
	local f = CreateFrame("CheckButton", "HUDiniIcon" .. index, parent)
	-- Hover only: the tooltip shows, but clicks pass straight through, so an
	-- icon never casts and never blocks a camera drag.
	if f.SetMouseMotionEnabled and f.SetMouseClickEnabled then
		f:SetMouseMotionEnabled(true)
		f:SetMouseClickEnabled(false)
	else
		f:EnableMouse(true)
		f:RegisterForClicks()
	end
	f:SetScript("OnEnter", function(self)
		if not (HUDiniDB.showTooltips and self.slot) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetAction(self.slot)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)

	f.backdrop = f:CreateTexture(nil, "BACKGROUND")
	f.backdrop:SetPoint("TOPLEFT", -1, 1)
	f.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
	f.backdrop:SetColorTexture(0, 0, 0, 0.9)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	f.cd:SetHideCountdownNumbers(false)

	local checked = f:CreateTexture(nil, "OVERLAY")
	checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	checked:SetBlendMode("ADD")
	checked:SetAllPoints()
	f:SetCheckedTexture(checked)

	-- Assisted Combat highlight: "this is the button to press".
	f.assist = f:CreateTexture(nil, "OVERLAY", nil, 1)
	f.assist:SetPoint("TOPLEFT", -4, 4)
	f.assist:SetPoint("BOTTOMRIGHT", 4, -4)
	f.assist:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	f.assist:SetBlendMode("ADD")
	f.assist:SetVertexColor(0.15, 0.85, 1.0)
	f.assist:Hide()

	-- Proc glow: the yellow ants Blizzard draws on a procced ability.
	f.glow = CreateFrame("Frame", nil, f)
	f.glow:SetPoint("TOPLEFT", -6, 6)
	f.glow:SetPoint("BOTTOMRIGHT", 6, -6)
	f.glow:SetFrameLevel(f:GetFrameLevel() + 4)

	f.glow.tex = f.glow:CreateTexture(nil, "OVERLAY")
	f.glow.tex:SetAllPoints()
	f.glow.tex:SetTexture(GLOW_TEXTURE)
	f.glow.tex:SetTexCoord(unpack(GLOW_COORDS))
	f.glow.tex:SetBlendMode("ADD")

	local ag = f.glow:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local pulse = ag:CreateAnimation("Alpha")
	pulse:SetFromAlpha(1.0)
	pulse:SetToAlpha(0.35)
	pulse:SetDuration(0.45)
	f.glow.anim = ag
	f.glow:Hide()

	f.key = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	f.key:SetPoint("TOPRIGHT", 0, -1)
	f.key:SetJustifyH("RIGHT")

	-- Buff time left, for a spell or item that buffs you. Its own Cooldown so it
	-- never fights the spell's cooldown: no swipe, just the numbers, bottom left.
	f.buff = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.buff:SetAllPoints()
	f.buff:SetDrawSwipe(false)
	f.buff:SetDrawEdge(false)
	if f.buff.SetDrawBling then f.buff:SetDrawBling(false) end
	f.buff:SetHideCountdownNumbers(false)
	f.buff:SetFrameLevel(f.cd:GetFrameLevel() + 2)
	if f.buff.SetCountdownFont then pcall(f.buff.SetCountdownFont, f.buff, "NumberFontNormal") end
	local buffText = f.buff.GetCountdownFontString and f.buff:GetCountdownFontString()
	if buffText then
		buffText:ClearAllPoints()
		buffText:SetPoint("BOTTOMLEFT", 1, 2)
		buffText:SetTextColor(0.45, 1, 0.45)
	end
	f.buff:Hide()

	-- Stack count, for items like food and water.
	f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	f.count:SetPoint("BOTTOMRIGHT", -1, 2)
	f.count:SetJustifyH("RIGHT")

	f:Hide()
	return f
end

function HUDini:GetIcon(index)
	local f = self.icons[index]
	if not f then
		f = CreateIcon(self.body, index)
		self.icons[index] = f
	end
	return f
end

--------------------------------------------------------------------------------
-- Layout and paint
--------------------------------------------------------------------------------

function HUDini:Layout()
	local db    = HUDiniDB
	local size  = db.iconSize
	local gap   = db.spacing
	local count = #self.spells

	local dx = db.growRight and 1 or -1
	local dy = db.growDown  and -1 or 1

	local maxCol, maxRow = 0, 0
	-- What the blue box must cover, from the anchor's top left. It starts
	-- at the first icon's spot, so an empty grid still has a box.
	local left, right, top, bottom = 0, size, 0, -size

	for i = 1, count do
		local e = self.spells[i]
		local f = self:GetIcon(i)
		local x = (size / 2) + dx * e.col * (size + gap)
		local y = (-size / 2) + dy * e.row * (size + gap)

		f:SetSize(size, size)
		f:ClearAllPoints()
		f:SetPoint("CENTER", self, "TOPLEFT", x, y)
		f:Show()

		left, right = min(left, x - size / 2), max(right, x + size / 2)
		top, bottom = max(top, y + size / 2), min(bottom, y - size / 2)

		if e.col > maxCol then maxCol = e.col end
		if e.row > maxRow then maxRow = e.row end
	end

	for i = count + 1, #self.icons do
		self.icons[i]:Hide()
	end

	-- A short grid still spans minIcons, so the bars above keep their width.
	local cols  = max(maxCol + 1, db.minIcons or 1)
	local width = cols * (size + gap) - gap
	self:SetSize(width, (maxRow + 1) * (size + gap) - gap)
	self:SetScale(db.scale)

	-- The stacked bars sit above the topmost row of icons, over the grid:
	-- from the first column's left edge when it grows right, back from its
	-- right edge when it grows left (TICK-0054).
	local barLeft = db.growRight and 0 or (size - width)
	left, right = min(left, barLeft), max(right, barLeft + width)
	if ns.LayoutBars then
		top = max(top, ns.LayoutBars(db.growDown and 0 or maxRow * (size + gap), width, barLeft))
	end

	self.mover:ClearAllPoints()
	self.mover:SetPoint("TOPLEFT", self, "TOPLEFT", left, top)
	self.mover:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", right, bottom)
end

-- One icon's picture, key and cooldown frame. Returns the icon, and the
-- slot's own picture (nil when the slot has none, or it is secret).
function HUDini:PaintIcon(i, entry)
	local db = HUDiniDB
	local f = self:GetIcon(i)
	f.spellID = entry.spellID
	f.slot    = entry.slot

	local texture = Plain(C_ActionBar.GetActionTexture and C_ActionBar.GetActionTexture(entry.slot))
	local fallback = entry.spellID and C_Spell.GetSpellTexture(entry.spellID)
		or entry.itemID and C_Item.GetItemIconByID(entry.itemID)
	f.icon:SetTexture(texture or fallback or 134400)

	if db.showKeybind then
		f.key:SetText(ShortKey(entry.key))
		f.key:Show()
	else
		f.key:Hide()
	end

	f.cd:SetShown(db.showCooldown)
	return f, texture
end

function HUDini:Paint()
	for i, entry in ipairs(self.spells) do
		self:PaintIcon(i, entry)
	end

	self:RegisterButtons()
	if ns.RefreshBars then ns.RefreshBars() end
	if ns.RefreshAlerts then ns.RefreshAlerts() end
	self:UpdateAll()
end

--------------------------------------------------------------------------------
-- Handing our buttons to the game
--------------------------------------------------------------------------------

function HUDini:RegisterButtons()
	if not (C_ActionBar and C_ActionBar.RegisterActionUIButton) then return end

	if InCombatLockdown() then
		self.needRegister = true
		return
	end

	for i, f in ipairs(self.icons) do
		local e = self.spells[i]
		if e then
			if f.boundSlot ~= e.slot then
				pcall(C_ActionBar.RegisterActionUIButton, f, e.slot, f.cd)
				f.boundSlot = e.slot
			end
		elseif f.boundSlot then
			pcall(C_ActionBar.UnregisterActionUIButton, f)
			f.boundSlot = nil
		end
	end

	self.needRegister = false
end

--------------------------------------------------------------------------------
-- Live state: cooldown, usable, range, assist, proc glow
--------------------------------------------------------------------------------

-- Cooldown times are secret in combat. A DurationObject is the sealed box the
-- game hands out instead, and SetCooldownFromDurationObject is the only door
-- it fits through. Never read a number out of it.
function HUDini:UpdateCooldowns()
	if not HUDiniDB.showCooldown then return end
	if not (C_ActionBar and C_ActionBar.GetActionCooldownDuration) then return end

	for i = 1, #self.spells do
		local f = self.icons[i]
		local e = self.spells[i]
		if f and e and f.cd.SetCooldownFromDurationObject then
			local duration = C_ActionBar.GetActionCooldownDuration(e.slot)
			if duration then
				pcall(f.cd.SetCooldownFromDurationObject, f.cd, duration)
			elseif f.cd.Clear then
				f.cd:Clear()
			end
		end
	end
end

-- How many of an item you carry, straight from the action slot.
function HUDini:UpdateCounts()
	for i = 1, #self.spells do
		local f = self.icons[i]
		local e = self.spells[i]
		if f and e then
			local text
			if e.itemID and C_ActionBar.GetActionDisplayCount then
				text = Plain(C_ActionBar.GetActionDisplayCount(e.slot))
			end
			f.count:SetText(text or "")
		end
	end
end

function HUDini:UpdateUsable()
	local db = HUDiniDB
	if not (db.showUsable or db.showRange) then return end
	if not C_ActionBar then return end

	for i = 1, #self.spells do
		local f = self.icons[i]
		local e = self.spells[i]
		if f and e then
			-- Not "a and b or nil": that turns a false answer into nil, and
			-- false is the one answer that matters here.
			local usable, inRange
			if db.showUsable and C_ActionBar.IsUsableAction then
				usable = Plain(C_ActionBar.IsUsableAction(e.slot))
			end
			if db.showRange and C_ActionBar.IsActionInRange then
				inRange = Plain(C_ActionBar.IsActionInRange(e.slot))
			end

			-- A faded icon fades its black backdrop too, or the backdrop shows
			-- through and the icon just looks darker.
			local alpha = 1
			if inRange == false then
				f.icon:SetVertexColor(0.9, 0.25, 0.25)
				f.icon:SetDesaturated(false)
			elseif usable == false then
				f.icon:SetVertexColor(0.45, 0.45, 0.45)
				f.icon:SetDesaturated(true)
				alpha = 0.5
			else
				f.icon:SetVertexColor(1, 1, 1)
				f.icon:SetDesaturated(false)
			end
			f.icon:SetAlpha(alpha)
			f.backdrop:SetAlpha(alpha)
		end
	end
end

-- The "best button to press" hint. GetNextCastSpell hands back a plain spell
-- ID, so a simple equality test is legal here.
function HUDini:UpdateAssist()
	local db = HUDiniDB

	local nextSpell
	if db.showAssist and C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
		local ok, result = pcall(C_AssistedCombat.GetNextCastSpell)
		if ok then nextSpell = Plain(result) end
	end

	for i = 1, #self.spells do
		local f = self.icons[i]
		local e = self.spells[i]
		if f and e then
			f.assist:SetShown(nextSpell ~= nil and e.spellID == nextSpell)
		end
	end
end

-- An alert's glow (alertGlow) has its own switch, so it shows with the
-- proc glow off too.
local function AlertLit(alerts, spellID)
	if spellID == nil then return false end
	for _, id in pairs(alerts) do
		if id == spellID then return true end
	end
	return false
end

function HUDini:ApplyGlow()
	local show = HUDiniDB.showProcGlow

	for i = 1, #self.spells do
		local f = self.icons[i]
		local e = self.spells[i]
		if f and e then
			local on = (show and self.glowing[e.spellID]) or AlertLit(self.alertGlow, e.spellID)
			on = on and true or false
			if on and not f.glow:IsShown() then
				f.glow:Show()
				f.glow.anim:Play()
			elseif not on and f.glow:IsShown() then
				f.glow.anim:Stop()
				f.glow:Hide()
			end
		end
	end
end

function HUDini:SetGlow(spellID, on)
	if not spellID then return end
	self.glowing[spellID] = on or nil
	self:ApplyGlow()
end

-- An alert lights one spell's icon, or none (spellID nil). source names the
-- alert ("racial"), so two alerts never clear each other.
function HUDini:SetAlertGlow(source, spellID)
	if self.alertGlow[source] == spellID then return end
	self.alertGlow[source] = spellID
	self:ApplyGlow()
	-- A lit alert wakes a hidden HUD (ShouldShow).
	self:UpdateVisibility()
end

function HUDini:UpdateAll()
	self:UpdateCooldowns()
	self:UpdateCounts()
	self:UpdateUsable()
	self:UpdateAssist()
	self:ApplyGlow()
	if ns.UpdateIconAuras then ns.UpdateIconAuras() end
end

--------------------------------------------------------------------------------
-- Rebuild, and when to show
--------------------------------------------------------------------------------

-- Bar 1 turned its page in a fight: a Druid form, Stealth, a Shift page
-- (TICK-0071). A fight allows no new layout, so each Bar 1 icon keeps its
-- spot and shows what the same button holds on the new page: the same key,
-- a new spell. An icon hides when its button is empty on the new page, or
-- when its spell is on the grid already (the copy on the lower bar stays,
-- as in Scan). A spell with no icon to take, a Bar 1 button that was empty
-- or a copy Scan left out, waits until the fight ends and the grid is built
-- again (needRefresh). So does registration, as in RegisterButtons; until
-- then the cooldown, usable, glow and buff updates read the new slot.
function HUDini:SwapBar1()
	local page = Bar1Page()
	if page == self.bar1Page then return end
	self.bar1Page = page

	local first = (page - 1) * 12 + 1
	local swapped = false
	for i, e in ipairs(self.spells) do
		if e.barOrder == 1 and e.button then
			local slot = first + e.button - 1
			local ok, kind, id = pcall(SlotAction, slot)
			local hidden = not ok or IsSecret(id) -- the game hides what it holds
			if hidden then kind, id = nil, nil end
			e.slot    = slot
			e.spellID = (kind == "spell") and id or nil
			e.itemID  = (kind == "item")  and id or nil
			e.auraNames = nil -- the buff names were the old spell's
			local f, texture = self:PaintIcon(i, e)
			-- A secret action still has its slot's picture. A slot with a
			-- picture but no spell or item (a plain macro, a flyout, a mount)
			-- hides, as Scan leaves it out.
			e.empty = (kind == nil) and not (hidden and texture ~= nil)
			if f.buff then
				if f.buff.Clear then f.buff:Clear() end
				f.buff:Hide()
			end
			swapped = true
		end
	end
	if not swapped then return end

	-- Which icons show: in bar order, each spell once (once per row in
	-- "bar" row mode), as Scan keeps them.
	local order = {}
	for i = 1, #self.spells do order[i] = i end
	tsort(order, function(a, b) return self.spells[a].slotRank < self.spells[b].slotRank end)
	local byBar = (HUDiniDB.layoutMode == "bar")
	local seen, row = {}, nil
	for _, i in ipairs(order) do
		local e = self.spells[i]
		if byBar and e.barOrder ~= row then seen, row = {}, e.barOrder end
		local id = e.spellID and ("spell" .. e.spellID) or e.itemID and ("item" .. e.itemID) -- locale: skip a table key
		local show = not e.empty
		if show and id then
			if seen[id] then show = false end
			seen[id] = true
		end
		self:GetIcon(i):SetShown(show)
	end

	self:UpdateAll()
end

function HUDini:Refresh()
	-- No layout or registration during a fight: wait for it to end so they
	-- never fight the combat lockdown. Only a Bar 1 page turn shows at once.
	if InCombatLockdown() then
		self.needRefresh = true
		self:SwapBar1()
		return
	end

	self.needRefresh = false
	self:Scan()
	self:Layout()
	self:Paint()
	self:ApplyPosition()
	self:ApplyLock()
	self:ApplyBlizzardFrames()
	self:UpdateVisibility()
end

-- Powers that sit at zero while nothing happens. Every other power rests full.
local EMPTY_AT_REST = { RAGE = true, RUNIC_POWER = true }

-- Forever hands back your own health and power as secrets even out of
-- combat, and a secret cannot be compared. Their events still fire, though,
-- and a bar at rest is a quiet bar: regen stops at full, rage stops at zero,
-- and no more changes come. So "no change for SETTLE seconds" stands in for
-- "at rest". Mana regen pauses for five seconds after a cast (the five
-- second rule), so SETTLE must be longer than that.
local SETTLE = 6
local lastChange = { health = 0, power = 0 }

local SETTLE_EVENTS = {
	UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health",
	UNIT_POWER_FREQUENT = "power", UNIT_POWER_UPDATE = "power",
	UNIT_MAXPOWER = "power", UNIT_DISPLAYPOWER = "power",
}

local settleEvents = CreateFrame("Frame")
for event in pairs(SETTLE_EVENTS) do
	pcall(settleEvents.RegisterUnitEvent, settleEvents, event, "player")
end
settleEvents:SetScript("OnEvent", function(self, event)
	lastChange[SETTLE_EVENTS[event]] = GetTime()
end)

local function Settling(key)
	return GetTime() - lastChange[key] < SETTLE
end

-- Decides whether the grid belongs on screen right now. The second value
-- says why, for /hud why.
-- An unlocked grid always shows, otherwise you could never drag it.
function HUDini:ShouldShow()
	local db = HUDiniDB

	if not db.locked then return true, Text("why.unlocked") end
	-- The options panel is open: show everything, so a change is visible.
	if ns.previewing then return true, Text("why.options") end
	if ns.testing then return true, Text("why.testMode") end
	-- HUDini setup is open: each pick shows on the HUD under it.
	if ns.setupOpen then return true, Text("why.setup") end
	if #self.spells == 0 then return false, Text("why.noSpells") end
	if not db.hideWhenIdle then return true, Text("why.alwaysShow") end

	if db.showInCombat then
		if InCombatLockdown() then return true, Text("why.combat") end
		if Plain(UnitAffectingCombat("player")) then return true, Text("why.combat") end
	end

	if db.showOnHostile and UnitExists("target") then
		local canAttack = Plain(UnitCanAttack("player", "target"))
		local dead      = Plain(UnitIsDead("target"))
		if canAttack and not dead then return true, Text("why.hostile") end
	end

	-- Health below full. A plain number is compared; a secret one falls
	-- back to "still changing" (see Settling above).
	if db.showWhenHurt then
		local hp, most = Plain(UnitHealth("player")), Plain(UnitHealthMax("player"))
		if hp and most then
			if hp < most then return true, Text("why.health", hp, most) end
		elseif Settling("health") then
			return true, Text("why.healthSettling")
		end
	end

	-- Power at rest is full, except for powers that drain to zero out of a
	-- fight, like rage. Same fallback as health when the number is secret.
	if db.showWhenPower then
		local ptype, token = ns.DisplayPower()
		local cur, most = Plain(UnitPower("player", ptype)), Plain(UnitPowerMax("player", ptype))
		if cur and most then
			local why = Text("why.power", token:lower(), cur, most)
			if EMPTY_AT_REST[token] then
				if cur > 0 then return true, why end
			elseif cur < most then
				return true, why
			end
		elseif Settling("power") then
			return true, Text("why.powerSettling", token:lower())
		end
	end

	-- A long buff you keep up is off, or a weapon buff (Auras.lua).
	if db.showWhenBuffMissing then
		if ns.buffMissing then return true, Text("why.buffOff") end
		if ns.WeaponBuffMissing and ns.WeaponBuffMissing() then
			return true, Text("why.weaponBuff")
		end
	end

	-- A fishing pole with no bait: show, so the alert can call it out.
	if db.warnNoBait and ns.BaitMissing and ns.BaitMissing() then
		return true, Text("why.noBait")
	end

	-- Your race's ability can help now (Alerts.lua): show, so its lit icon
	-- is seen (TICK-0099).
	if self.alertGlow.racial then return true, Text("why.racial") end

	return false, Text("why.idle")
end

-- Showing is instant: when something needs you, it needs you now. Hiding
-- fades out over fadeOutTime. Anything that wants the HUD back mid-fade
-- cancels the fade at once.
local body = HUDini.body

-- A C_Timer ticker that runs only while it has work. Set(true) starts it,
-- Set(false) stops it; calling either again does nothing.
function ns.Ticker(period, fn)
	local t = {}
	function t:Set(on)
		if on and not self.handle then
			self.handle = C_Timer.NewTicker(period, fn)
		elseif not on and self.handle then
			self.handle:Cancel()
			self.handle = nil
		end
	end
	return t
end

-- Hide when idle can act on its own. Some reasons to show come with no
-- event (a weapon buff or bait wears off, a secret health value settles),
-- so while it can, a poll keeps checking.
local function CanHide()
	local db = HUDiniDB
	return (db and db.locked and db.hideWhenIdle and not ns.previewing and not ns.testing
		and not ns.setupOpen and #HUDini.spells > 0) and true or false
end

-- Something the poll draws is on screen: the grid with your bars, or a
-- target bar, which stays up while the grid is hidden.
local function Drawn()
	if body:IsShown() then return true end
	local db = HUDiniDB
	return (db and (db.showTargetHealth or db.showTargetCast)
		and UnitExists("target")) and true or false
end

-- The Assisted Combat pick and the range check have no event of their own,
-- so they are polled a few times a second while the grid is on screen. The
-- show check runs on the same beat. While the HUD is hidden, a tick does only
-- the show check; with nothing to show and nothing that can bring the HUD
-- back by itself, the ticker stops until UpdateVisibility runs again.
-- The alerts follow their own events (Alerts.lua, TICK-0065): the poll
-- does not run them.
local function Tick()
	HUDini:UpdateVisibility()
	if not Drawn() then return end
	if ns.UpdateBars then ns.UpdateBars() end
	if ns.UpdateCastBars then ns.UpdateCastBars() end
	if not body:IsShown() then return end
	HUDini:UpdateAssist()
	HUDini:UpdateUsable()
end

local hudTicker = ns.Ticker(0.15, Tick)

body:SetScript("OnUpdate", function(self, elapsed)
	if not self.fadeLeft then return end
	self.fadeLeft = self.fadeLeft - elapsed
	if self.fadeLeft <= 0 then
		self.fadeLeft = nil
		self:Hide()
		self:SetAlpha(1)
	else
		self:SetAlpha(self.fadeLeft / self.fadeTotal)
	end
end)

function HUDini:UpdateVisibility()
	if self:ShouldShow() then
		body.fadeLeft = nil
		body:SetAlpha(1)
		body:Show()
	elseif body:IsShown() and not body.fadeLeft then
		local total = HUDiniDB.fadeOutTime or 0
		if total > 0 then
			body.fadeLeft, body.fadeTotal = total, total
		else
			body:Hide()
		end
	end
	if ns.UpdateBarVisibility then ns.UpdateBarVisibility() end
	hudTicker:Set(CanHide() or Drawn())
end

-- Rebuild, then re-check visibility. Refresh alone defers during combat.
function HUDini:Apply()
	-- Switch the modules (the feed, the XP bar, the window mover) on or off
	-- first, so an error further down cannot leave one on but not started.
	if ns.UpdateModules then ns.UpdateModules() end
	self:Refresh()
	self:UpdateVisibility()
	-- Refresh waits out a fight, and the alerts with it: an alert setting
	-- changed in a fight takes effect now.
	if ns.UpdateAlerts then ns.UpdateAlerts() end
	if ns.UpdateMouseover then ns.UpdateMouseover() end
	-- Refresh waits out a fight; the feed need not.
	if ns.ApplyFeed then ns.ApplyFeed() end
	if ns.ApplyMinimapButton then ns.ApplyMinimapButton() end
	-- The options' flair tooltips (Options.lua) follow a flair change from
	-- HUDini setup or /hud reset.
	if ns.RetextFlairTips then ns.RetextFlairTips() end
end

-- A slider calls back at every step of a drag, often more than once a frame.
-- Gather the steps into one Apply on the next frame, so the drag stays smooth.
local applyQueued = false

function HUDini:QueueApply()
	if applyQueued then return end
	applyQueued = true
	C_Timer.After(0, function()
		applyQueued = false
		HUDini:Apply()
	end)
end

--------------------------------------------------------------------------------
-- The default Blizzard frames
--
-- HUDini draws the target's health, name, level and cast, your own cast bar
-- rides on the power bar, and it has its own XP bar. Blizzard's versions are
-- then redundant, so you may hide them. Never by default: each hide is
-- opt-in, and holds only while HUDini's matching bars are on. Turn one off
-- and Blizzard's frame comes back at once, in a fight too.
--
-- All four frames are Edit Mode system frames (EditModeSystemTemplates.lua),
-- and the cast bar is a managed frame too (ManagedFrameSystem.lua). So is
-- the pet frame under the player frame (PetFrame.xml:11), which gets only
-- the mouse calls. HUDini never runs their Lua in its own call, and never
-- writes a field on them: a field written in a tainted run is read tainted
-- by Edit Mode later, and that taint blocks ClearTarget and breaks the
-- party frames (TICK-0087, TICK-0089). So HUDini calls on them only C
-- methods that no Lua replaces and that start no script: SetAlpha, the
-- mouse calls, and the event calls. One exception, the target's aura
-- container (TICK-0121, below): its SetEnabled is a secure delegate.
-- Never a driver, Show(), Hide() or SetShown():
-- - RegisterAttributeDriver resolves at once, inside HUDini's call, and then
--   every 0.2 s, by frame:Hide() and frame:Show() (SecureStateDriver.lua
--   :96-118, :146-164). Hide() is Edit Mode's HideOverride (Edit Mode
--   SystemTemplates.lua:158-164), and OnHide runs OnSystemHide and
--   ManagedFrameMixin.OnHide (:38-46; ManagedFrameSystem.lua:17-23).
-- - The cast bar's Show() runs its OnShow, which adds it to the managed
--   frames and lays out the bottom bars (CastingBarFrame.lua:1385-1390).
--
-- Hiding TargetFrame takes the target cast bar with it. That bar is a child of
-- the target frame, not a frame of its own. The combo points go too: on
-- this client they hang on the target frame (ComboFrame.lua:16, SetParent
-- (TargetFrame)). Hiding PlayerFrame takes its
-- children too: the pet frame, any class resource Blizzard hangs on it, and
-- your cast bar when Edit Mode locks it to the player frame.
--------------------------------------------------------------------------------

-- setting is the opt-in; bars are HUDini's matching bars, which must all be
-- on too. Your cast bar rides on the power bar and has no place of its own,
-- so it needs both. The player frame shows your health and your mana, so it
-- needs both too. The XP bar needs no HUDini bar: a player who hides it
-- keeps it hidden with HUDini's XP bar off too (TICK-0080).
-- when, if given, must also be true. The XP bar lives in the
-- main status tracking container, which a tracked reputation moves into at
-- max level (or with XP gain off), so the container comes back then.
--
-- how is the way HUDini hides the frame:
-- - "alpha": alpha 0 on the frame, and its mouse and its children's off, so
--   it takes no click and shows no tooltip. Not the target's auras: their
--   container and buttons live in the secure environment, forbidden to an
--   addon (TargetFrameAuraContainer.xml:3, :33-35; TargetFrameAuraButton
--   .xml:4, :73; Blizzard_UnitFrame.toc:48-51), so the mouse walk skips
--   them and all under them.
--   auras: the keys from the frame to that container (TargetFrameMixin:
--   GetAuraContainer, TargetFrame.lua:507-508). Its public face has the
--   container's own methods (targetPartition public, secureDelegates,
--   TargetFrameAuraContainer.xml:30), so HUDini switches it off while the
--   hide holds: SetEnabled(false) clears its buttons (UpdateAllAuras marks
--   a full rebuild, ManagedAuraContainer.lua:63-65; the reset releases
--   every button, :591-596; the parse finds none while off, :518-525).
--   No button, no tooltip and no click where the frame was. A secure
--   delegate runs in the secure environment and writes only the forbidden
--   partition, so HUDini's call taints nothing Blizzard reads. No Blizzard
--   Lua calls SetEnabled on it (ConfigureAuraContainer, TargetFrame.lua
--   :511-539, sets only sizes and filters), so HUDini switches back on
--   only a container it switched off. A container that says it is
--   forbidden is left alone, and then its hidden buttons still show a
--   tooltip.
--   HUDini looks again at each target change, for a part Blizzard made or
--   turned on since. Blizzard still shows and hides
--   the frame as it needs (the target frame at each target), and the alpha
--   holds through that. No Blizzard Lua sets the alpha of these two frames
--   but Edit Mode's Opacity setting (UpdateSystemSettingOpacity, Edit Mode
--   SystemTemplates.lua:1586-1591), at each layout load: HUDini sets it
--   again after EDIT_MODE_LAYOUTS_UPDATED and after Edit Mode closes. Alpha
--   is not protected; the mouse of a protected frame is, so in a fight that
--   part waits for the fight to end.
--   keep: frames under it that stay on screen (TICK-0104, TICK-0105): the
--   pet frame under the player frame, target of target under the target
--   frame. Each gets SetIgnoreParentAlpha(true), so the parent's alpha 0
--   does not reach it, and keeps its mouse. SetIgnoreParentAlpha is not
--   protected (SimpleRegionAPIDocumentation.lua:158; SetIgnoreParentScale
--   is) and no Blizzard Lua calls it, so its old value is given back at the
--   end. Blizzard still shows and hides a kept frame as it needs: no pet,
--   no pet frame; target of target off in the game's options, none. A kept
--   frame ignores the parent's Edit Mode Opacity while the hide is on.
-- - "events": the cast bar's start events off (START, CHANNEL_START,
--   EMPOWER_START, and PLAYER_ENTERING_WORLD, which starts a bar for a cast
--   already running), so it never starts a bar. The others stay: they act
--   only on a bar that shows (CastingBarFrame.lua:107-157, :443-600),
--   so a bar running at the hide still ends, is interrupted or fails as
--   Blizzard shows it. Its alpha is no use: ApplyAlpha sets it at each
--   cast (:660-667), and its parts have alpha animations of their own
--   (CastingBarFrame.xml, setToFinalAlpha).
-- - "fade": alpha 0 on the frame's children and its art. The frame's own
--   alpha stays Blizzard's: its FadeInAnimation ends at alpha 1
--   (StatusTrackingBar.xml, setToFinalAlpha), and SetShownBar picks fade in
--   or out from GetAlpha() (StatusTrackingManager.lua:174-195). Blizzard
--   still shows and hides the frame itself, and keeps its place. It still
--   takes the mouse: alpha 0 leaves a bar's tooltip on.
--
-- In Edit Mode every frame is visible, so it can be seen and moved.
local BLIZZ_FRAMES = {
	{ global = "PlayerFrame",            setting = "hideBlizzardPlayer",
	  bars = { "showHealth", "showPower" }, how = "alpha", keep = { "PetFrame" } },
	-- TargetFrameToT: TargetFrameMixin:CreateTargetofTarget (TargetFrame
	-- .lua:688-693), parent TargetFrame.
	{ global = "TargetFrame",            setting = "hideBlizzardTarget",
	  bars = { "showTargetHealth" }, how = "alpha", keep = { "TargetFrameToT" },
	  auras = { "TargetFrameContent", "TargetFrameContentContextual", "Auras" } }, -- locale: skip frame keys
	{ global = "PlayerCastingBarFrame",  setting = "hideBlizzardCastBar",
	  bars = { "showPlayerCast", "showPower" }, how = "events" },
	{ global = "MainStatusTrackingBarContainer", setting = "hideBlizzardXP",
	  bars = {}, when = function() return ns.EarningXP and ns.EarningXP() end,
	  how = "fade" },
}

-- True between EditMode.Enter and EditMode.Exit.
local inEditMode = false

-- True while this Blizzard frame should be hidden.
local function WantHidden(entry)
	local db = HUDiniDB
	if not db[entry.setting] then return false end
	for _, key in ipairs(entry.bars) do
		if not db[key] then return false end
	end
	if entry.when and not entry.when() then return false end
	if inEditMode then return false end
	return true
end

-- HUDini's state for each frame, in its own tables keyed by the frame,
-- never in a field on a Blizzard frame. Weak keys: a frame is never freed,
-- but a part made and dropped by a pool may be.
local function Weak() return setmetatable({}, { __mode = "k" }) end

local blizzHidden = {}

-- The alpha each frame or part had before HUDini set it to 0, to give it back.
local partAlpha = Weak()

-- mouseOff[frame][f]: HUDini turned off the mouse of f, a frame under it.
local mouseOff = Weak()

-- keptIgnore[f]: the IsIgnoringParentAlpha a kept frame had before HUDini
-- set it, to give it back.
local keptIgnore = Weak()

-- castEvents[frame][event] = { units }: the events HUDini took off the
-- cast bar, and the units each one was for.
local castEvents = Weak()

-- The events that start a cast bar (CastingBarMixin:OnEvent, CastingBar
-- Frame.lua:107-128; SetUnit registers them, :224-253), and the event
-- PLAYER_ENTERING_WORLD, at which it starts a bar for a cast already
-- running (:111-122). Also the update events: each checks only that the
-- bar shows (HandleCastDelayed :494-498, HandleChannelUpdateDelayed
-- :524-525), so on a bar still in its fade-out a pushback would show a new
-- cast. A bar running at the hide ends without its pushback update.
local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
	"PLAYER_ENTERING_WORLD",
}

-- The parts of a fade frame: its child frames (the bars, the dividers, Edit
-- Mode's Selection, and any frame another addon parents to it) and its art
-- (BarFrameTexture, the only texture of the template).
local function FadeParts(frame)
	local parts = { frame:GetChildren() }
	if frame.BarFrameTexture then parts[#parts + 1] = frame.BarFrameTexture end
	return parts
end

local function ApplyFade(entry, frame)
	local want = WantHidden(entry)
	if not want and not blizzHidden[entry.global] then return end
	-- Every time, not only at a change: a part made later (a divider from
	-- its pool) starts at alpha 1.
	for _, part in ipairs(FadeParts(frame)) do
		if want then
			if partAlpha[part] == nil then
				local ok, a = pcall(part.GetAlpha, part)
				partAlpha[part] = ok and a or 1
			end
			pcall(part.SetAlpha, part, 0)
		elseif partAlpha[part] ~= nil then
			pcall(part.SetAlpha, part, partAlpha[part])
			partAlpha[part] = nil
		end
	end
	blizzHidden[entry.global] = want or nil
end

-- f:method(...), for pcall: the index of f is inside the pcall too.
local function Call(f, method, ...) return f[method](f, ...) end
local function Children(f) return { f:GetChildren() } end

-- True when HUDini must leave f and all under it alone: a forbidden object
-- (the target's auras, above), a secret one, or one it cannot ask.
local function Untouchable(f)
	if IsSecret(f) then return true end
	local ok, forbidden = pcall(Call, f, "IsForbidden")
	return not ok or Plain(forbidden) ~= false
end

-- True when HUDini may change the mouse of f now: the mouse of a protected
-- frame is locked in a fight.
local function MouseFree(f)
	if not InCombatLockdown() then return true end
	local ok, protected = pcall(Call, f, "IsProtected")
	return ok and Plain(protected) == false
end

-- The two halves of the mouse, each kept and given back on its own: a
-- frame may take motion (a tooltip) and no click. The player frame's health
-- and mana bars do (PlayerFrame.xml:166/196, :248/307), and its clicks
-- target you and open your menu. EnableMouse(true) would turn on both.
local MOUSE = {
	{ is = "IsMouseClickEnabled", set = "SetMouseClickEnabled" },
	{ is = "IsMouseMotionEnabled", set = "SetMouseMotionEnabled" },
}

-- Turn off the mouse of the frame and every frame under it.
-- off[f][set] = true: HUDini turned that half off. False when a protected
-- one must wait for the fight to end. top: the hidden frame itself. Only a
-- plain "forbidden" leaves it alone; a secret answer or one that throws
-- means "not done", so a later apply asks again.
local function MouseOff(f, off, top, skip)
	if skip and skip[f] then return true end
	if top then
		if IsSecret(f) then return false end
		local ok, forbidden = pcall(Call, f, "IsForbidden")
		if not ok then return false end
		forbidden = Plain(forbidden)
		if forbidden == true then return true end
		if forbidden ~= false then return false end
	elseif Untouchable(f) then
		return true
	end
	local done = true
	for _, half in ipairs(MOUSE) do
		local ok, on = pcall(Call, f, half.is)
		-- Again for a frame Blizzard turned back on.
		if ok and Plain(on) == true then
			if not MouseFree(f) then
				done = false
			elseif pcall(Call, f, half.set, false) then
				off[f] = off[f] or {}
				off[f][half.set] = true
			end
		end
	end
	local ok, children = pcall(Children, f)
	if ok then
		for _, child in ipairs(children) do
			if not MouseOff(child, off, nil, skip) then done = false end
		end
	end
	return done
end

-- Give back the mouse HUDini took. False when a protected frame must wait.
local function MouseOn(off)
	local done = true
	for f, halves in pairs(off) do
		if MouseFree(f) then
			for set in pairs(halves) do pcall(Call, f, set, true) end
			off[f] = nil
		else
			done = false
		end
	end
	return done
end

-- The kept frames of an entry that exist now, as a set. A secret or
-- forbidden one is left out: HUDini leaves it alone, and it hides with
-- the parent.
local function KeptFrames(entry)
	local set = {}
	for _, name in ipairs(entry.keep or {}) do
		local f = _G[name]
		if f and not Untouchable(f) then set[f] = true end
	end
	return set
end

-- Keep each frame on screen under its hidden parent, and return the set
-- that is: one whose SetIgnoreParentAlpha throws hides with the parent, so
-- its mouse goes off too, and the next apply tries again. Off: give back
-- the value each had.
local function KeepOnScreen(kept, on)
	local shown = {}
	if on then
		for f in pairs(kept) do
			if keptIgnore[f] == nil then
				local ok, was = pcall(Call, f, "IsIgnoringParentAlpha")
				keptIgnore[f] = ok and Plain(was) == true
			end
			if pcall(Call, f, "SetIgnoreParentAlpha", true) then shown[f] = true end
		end
		return shown
	end
	for f, was in pairs(keptIgnore) do
		if kept[f] and pcall(Call, f, "SetIgnoreParentAlpha", was) then keptIgnore[f] = nil end
	end
	return shown
end

-- auraOff[frame]: the aura container HUDini switched off under the hidden
-- frame, to switch it on again.
local auraOff = Weak()

local function Field(f, key) return f[key] end

-- The aura container under the frame (entry.auras), or nil. Reads only. A
-- key that is not a frame throws at the next read, or at the IsForbidden
-- ask after.
local function AuraContainer(entry, frame)
	if not entry.auras then return nil end
	local f = frame
	for _, key in ipairs(entry.auras) do
		local ok, v = pcall(Field, f, key)
		if not ok then return nil end
		f = v
	end
	return f
end

-- True when the container says, plainly, that it is on. A secret answer
-- is not; a throw gives its message, never true.
local function On(c)
	local _, on = pcall(Call, c, "IsEnabled")
	return Plain(on) == true
end

-- Switch the aura container off while the frame is hidden: only one that
-- is on, and again at each apply, for one turned on since. A container
-- HUDini cannot reach, or whose answer it cannot read, stays as it is: the
-- next target change asks again. The answer after the call tells what
-- happened, not the call: a blocked action returns with no error, and a
-- call may switch and then throw. Recorded unless it still says on, so a
-- container HUDini may have switched off is always switched back on. False
-- when it is still on: the next apply tries again.
local function AurasOff(entry, frame)
	local c = AuraContainer(entry, frame)
	if not c or Untouchable(c) then return true end
	if not On(c) then return true end
	pcall(Call, c, "SetEnabled", false)
	if On(c) then return false end
	auraOff[frame] = c
	return true
end

-- Switch back on the container HUDini switched off. The record goes only
-- when it says on again; until then this is false and the next apply
-- tries again.
local function AurasOn(frame)
	local c = auraOff[frame]
	if not c then return true end
	pcall(Call, c, "SetEnabled", true)
	if not On(c) then return false end
	auraOff[frame] = nil
	return true
end

-- False when a part must wait for the fight to end.
local function ApplyAlpha(entry, frame)
	local want = WantHidden(entry)
	local off = mouseOff[frame]
	local kept = KeepOnScreen(KeptFrames(entry), want)
	if want then
		local aurasOff = AurasOff(entry, frame)
		-- Every time, not only at a change: Edit Mode's Opacity sets the
		-- alpha again at a layout load. Keep the alpha Blizzard set last.
		local ok, a = pcall(frame.GetAlpha, frame)
		a = ok and Plain(a)
		if type(a) == "number" and a ~= 0 then partAlpha[frame] = a end
		if partAlpha[frame] == nil then partAlpha[frame] = 1 end
		pcall(frame.SetAlpha, frame, 0)
		if not off then
			off = Weak()
			mouseOff[frame] = off
		end
		blizzHidden[entry.global] = true
		-- A part made later starts with its mouse on.
		local mouseDone = MouseOff(frame, off, true, kept)
		return mouseDone and aurasOff
	end
	if partAlpha[frame] ~= nil then
		pcall(frame.SetAlpha, frame, partAlpha[frame])
		partAlpha[frame] = nil
	end
	blizzHidden[entry.global] = nil
	local aurasBack = AurasOn(frame)
	return (not off or MouseOn(off)) and aurasBack
end

-- False when an event could not be given back: the next apply tries again.
local function ApplyEvents(entry, frame)
	local want = WantHidden(entry)
	local taken = castEvents[frame]
	if want then
		taken = taken or {}
		castEvents[frame] = taken
		-- Every time: Blizzard's SetUnit may register them again.
		for _, event in ipairs(CAST_EVENTS) do
			local ok, on, unit1, unit2 = pcall(frame.IsEventRegistered, frame, event)
			if ok and on and pcall(frame.UnregisterEvent, frame, event) then
				taken[event] = { unit1, unit2 }
			end
		end
		blizzHidden[entry.global] = true
	elseif taken then
		for event, units in pairs(taken) do
			local ok
			if units[2] then
				ok = pcall(frame.RegisterUnitEvent, frame, event, units[1], units[2])
			elseif units[1] then
				ok = pcall(frame.RegisterUnitEvent, frame, event, units[1])
			elseif event:find("^UNIT_") then
				-- No unit given back: the cast bar's own unit.
				ok = pcall(frame.RegisterUnitEvent, frame, event, "player")
			else
				ok = pcall(frame.RegisterEvent, frame, event)
			end
			-- Kept until it is back.
			if ok then taken[event] = nil end
		end
		blizzHidden[entry.global] = nil
		if next(taken) then return false end
		castEvents[frame] = nil
	end
	return true
end

local APPLY = { alpha = ApplyAlpha, events = ApplyEvents, fade = ApplyFade }

-- An entry whose apply failed: its error is shown once, not at each apply,
-- until an apply of it works.
local applyFailed = {}

-- None of it is protected but the mouse of a protected frame, so it runs in
-- a fight too; that part waits for the fight to end (needBlizzFrames). One
-- frame's error stops neither the other frames nor the show check after.
function HUDini:ApplyBlizzardFrames()
	local done = true
	for _, entry in ipairs(BLIZZ_FRAMES) do
		local frame = _G[entry.global]
		if frame then
			local ok, result = pcall(APPLY[entry.how], entry, frame)
			if not ok then
				-- Tried again at the next apply, as a part that must wait.
				done = false
				if not applyFailed[entry] then
					applyFailed[entry] = true
					local handler = geterrorhandler and geterrorhandler()
					if handler then handler(result) end
				end
			else
				-- A later error on this entry shows again.
				applyFailed[entry] = nil
				if result == false then done = false end
			end
		end
	end
	self.needBlizzFrames = not done
end

-- One apply on the next frame, after Blizzard's own handler for the event,
-- however many events ask for it.
local blizzQueued = false
local function QueueBlizzardFrames()
	if blizzQueued then return end
	blizzQueued = true
	C_Timer.After(0, function()
		blizzQueued = false
		HUDini:ApplyBlizzardFrames()
	end)
end

-- Blizzard makes frames under PlayerFrame after login, each with its mouse
-- on: the pet frame's parts (PetFrame.xml:11 parent="PlayerFrame") and the
-- totem buttons (TotemFrame.xml:56 parent="PlayerFrame", at
-- PLAYER_TOTEM_UPDATE). While Hide player frame is on, one apply after a
-- new pet or a totem change. The pet frame is kept on screen with its
-- mouse (keep, above); the apply after a new pet is for the times it
-- cannot be, when its parts must lose the mouse. Not after the pet's UNIT_AURA: Auras.lua has
-- the one UNIT_AURA handler (TICK-0065), so a pet aura button made later
-- (PetFrame.lua:13) waits for the next apply.
local playerParts = CreateFrame("Frame")
pcall(playerParts.RegisterUnitEvent, playerParts, "UNIT_PET", "player")
pcall(playerParts.RegisterEvent, playerParts, "PLAYER_TOTEM_UPDATE")
playerParts:SetScript("OnEvent", function()
	if blizzHidden.PlayerFrame then QueueBlizzardFrames() end
end)

-- Edit Mode shows every frame, so it can be moved. EventRegistry runs each
-- callback through securecallfunction (CallbackRegistry.lua:210), so
-- HUDini's taint stays in it. ExitEditMode reverts the layout, and so sets
-- the Opacity, before EditMode.Exit (EditModeManager.lua:116-126).
local function EditModeChanged(on)
	inEditMode = on
	HUDini:ApplyBlizzardFrames()
end

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("EditMode.Enter", function() EditModeChanged(true) end, BLIZZ_FRAMES)
	EventRegistry:RegisterCallback("EditMode.Exit", function() EditModeChanged(false) end, BLIZZ_FRAMES)
end

--------------------------------------------------------------------------------
-- Bag bar, menu and minimap on mouseover
--
-- The backpack and bag slots, the menu buttons and the minimap stay
-- invisible until the mouse is over them. A group's hides() frames are
-- hidden outright instead of faded. 12.x forbids script handlers on
-- protected frames, so a ticker asks IsMouseOver instead of hooking
-- OnEnter. Alpha is not protected, so it works in combat too, and an
-- invisible button still takes a click.
--------------------------------------------------------------------------------

-- The named list of buttons, for layouts before 10.0 had a container.
local function Buttons(names)
	local list = {}
	for _, name in ipairs(names or {}) do
		if _G[name] then list[#list + 1] = _G[name] end
	end
	return list
end

local MOUSEOVER = {
	{ setting = "bagBarMouseover", frames = function()
		if BagsBar then return { BagsBar } end
		return Buttons({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
			"CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot", "BagBarExpandToggle" })
	end },
	{ setting = "menuBarMouseover", frames = function()
		local box = MicroMenuContainer or MicroMenu
		if box then return { box } end
		return Buttons(MICRO_BUTTONS)
	end },
	-- The cluster holds the map, zone text, clock and the addon buttons on it.
	-- The map engine draws your arrow and the quest blips past any alpha, so
	-- the map itself is hidden outright; the cluster stays to catch the mouse.
	{ setting = "minimapMouseover", frames = function()
		return Buttons({ "MinimapCluster" })
	end, hides = function()
		return Buttons({ "Minimap" }) -- locale: skip a frame name
	end },
}

-- The ticker runs only while a group is set to fade, or still has to come
-- back after one was turned off.
local mouseoverTicker

local function UpdateMouseover()
	local busy = false
	for _, group in ipairs(MOUSEOVER) do
		local fade = HUDiniDB and HUDiniDB[group.setting] or false
		-- Off and already restored: nothing to do.
		if fade or group.faded then
			local frames, over = group.frames(), false
			if fade then
				for _, f in ipairs(frames) do
					if f:IsVisible() and f:IsMouseOver() then over = true break end
				end
			end
			local alpha = (fade and not over) and 0 or 1
			for _, f in ipairs(frames) do pcall(f.SetAlpha, f, alpha) end
			for _, f in ipairs(group.hides and group.hides() or {}) do
				if alpha == 0 and f:IsShown() then
					pcall(f.Hide, f)
				elseif alpha == 1 and not f:IsShown() then
					pcall(f.Show, f)
				end
			end
			group.faded = fade
		end
		busy = busy or (fade and true or false)
	end
	mouseoverTicker:Set(busy)
end

mouseoverTicker = ns.Ticker(0.1, UpdateMouseover)
-- HUDini:Apply and login call it, to start or stop the ticker.
ns.UpdateMouseover = UpdateMouseover

--------------------------------------------------------------------------------
-- The gryphons at both ends of Action Bar 1 (D-024, TICK-0089)
--
-- HUDini never touches them. On WoW Forever each gryphon is an Edit Mode
-- system frame (Blizzard_ActionBar/Camelot/MainMenuBarEndCaps.xml), and
-- HUDini's old Hide gryphons (an alpha on MainActionBar.EndCaps) made Edit
-- Mode throw a taint error. Edit Mode hides each one with its own check
-- box. HUDini only names that box, in the game's own words, in the Game
-- frames page and in setup step 6. An old save's hideGryphons is not read.
--------------------------------------------------------------------------------

-- The name of Edit Mode's Hide box on a gryphon, as the game shows it.
function ns.GryphonBoxName()
	local name = _G.HUD_EDIT_MODE_SETTING_END_CAP_HIDDEN
	if type(name) == "string" and name ~= "" then return name end
	return ns.Text("gryphons.box")
end

--------------------------------------------------------------------------------
-- Position and lock
--------------------------------------------------------------------------------

function HUDini:ApplyPosition()
	-- The class's own spot, else the account-wide default.
	local db, mine = HUDiniDB, ns.ClassDB()
	self:ClearAllPoints()
	self:SetPoint(mine.point or db.point, UIParent, mine.relPoint or db.relPoint,
		mine.x or db.x, mine.y or db.y)
end

function HUDini:ApplyLock()
	local locked = HUDiniDB.locked
	self:SetMovable(not locked)
	self.mover:SetShown(not locked)
	-- The click buttons step aside while you drag.
	if ns.SyncClicks then ns.SyncClicks() end
	-- The feed has its own blue box.
	if ns.ApplyFeed then ns.ApplyFeed() end
end

-- Many events can arrive in one burst (a talent swap changes every slot).
-- Gather them into one rebuild a tenth of a second later.
local pending = false

function HUDini:QueueRefresh()
	if pending then return end
	pending = true
	C_Timer.After(0.1, function()
		pending = false
		HUDini:Refresh()
	end)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local REBUILD = {
	ACTIONBAR_SLOT_CHANGED        = true,
	ACTIONBAR_PAGE_CHANGED        = true,
	UPDATE_BINDINGS               = true,
	UPDATE_MACROS                 = true,
	PLAYER_SPECIALIZATION_CHANGED = true,
	EDIT_MODE_LAYOUTS_UPDATED     = true,
	UPDATE_SHAPESHIFT_FORM        = true,
	UPDATE_BONUS_ACTIONBAR        = true,
}

--------------------------------------------------------------------------------
-- Saved settings: numbered migrations (TICK-0011)
--------------------------------------------------------------------------------

-- Each step changes a saved table from one schema number to the next, and
-- runs once: HUDiniDB.schema keeps the number of the last step it got. They
-- run before FillDefaults, so a step sees only what was saved: a renamed key
-- keeps its value and is not shadowed by the new key's default. Add a step
-- at the end; never change or remove a step that has shipped. A step that
-- throws runs again at the next login, so it must be safe to run on a table
-- it changed part way.
--
-- Saved tables start at schema FIRST_SCHEMA, so the first step here is step
-- FIRST_SCHEMA + 1. A table with no number, or a lower one, counts as
-- FIRST_SCHEMA.
local FIRST_SCHEMA = 3
local MIGRATIONS = {}
ns.migrations = MIGRATIONS  -- the tests add steps of their own
ns.FIRST_SCHEMA = FIRST_SCHEMA

-- Bring a saved table up to the last step. A new install skips every step.
-- A number above it (a newer HUDini wrote it) is left alone. A step that
-- throws is reported and stops the steps after it; the number stays at the
-- step before, so the login goes on with the defaults filled in, and the
-- next login tries that step again without running the earlier ones twice.
function ns.Migrate(db, isNew)
	local last = FIRST_SCHEMA + #MIGRATIONS
	if isNew then
		db.schema = last
		return
	end
	local from = type(db.schema) == "number" and db.schema or FIRST_SCHEMA
	if from < FIRST_SCHEMA then from = FIRST_SCHEMA end
	db.schema = from
	for i = from + 1, last do
		local ok, err = pcall(MIGRATIONS[i - FIRST_SCHEMA], db)
		if not ok then
			local handler = geterrorhandler and geterrorhandler()
			if handler then handler(err) end
			return
		end
		db.schema = i
	end
end

local events = CreateFrame("Frame")

local function Listen(event)
	local ok = pcall(events.RegisterEvent, events, event)
	if not ok then
		ns.Say(Text("core.noEvent", event))
	end
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		-- No saved table at all: a new install, with nothing old to change.
		local isNew = HUDiniDB == nil
		HUDiniDB = HUDiniDB or {}
		ns.Migrate(HUDiniDB, isNew)
		FillDefaults(HUDiniDB)
		ns.FillClassSettings()
		if ns.BuildOptions then ns.BuildOptions() end

	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent("ADDON_LOADED")

		for e in pairs(REBUILD) do Listen(e) end

		Listen("ACTIONBAR_UPDATE_COOLDOWN")
		Listen("ACTIONBAR_UPDATE_USABLE")
		Listen("ACTIONBAR_UPDATE_STATE")
		Listen("SPELL_UPDATE_COOLDOWN")
		Listen("SPELL_UPDATE_CHARGES")
		Listen("SPELL_UPDATE_USABLE")
		Listen("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
		Listen("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
		Listen("PLAYER_TARGET_CHANGED")
		Listen("PLAYER_REGEN_ENABLED")
		Listen("PLAYER_REGEN_DISABLED")
		Listen("PLAYER_SOFT_ENEMY_CHANGED")
		Listen("BAG_UPDATE_DELAYED")
		-- The XP bar hide needs no HUDini XP bar (TICK-0080), so Core hears
		-- these itself: with showXP off, the XP module hears nothing.
		Listen("PLAYER_LEVEL_UP")
		Listen("ENABLE_XP_GAIN")
		Listen("DISABLE_XP_GAIN")
		-- At a first login the max level can be not final yet at this
		-- PLAYER_ENTERING_WORLD, so "you earn XP" can say no and the hide
		-- does not take. Blizzard's bar manager checks the XP bar again at
		-- these two (StatusTrackingManagerOverrides.lua:8, :18;
		-- CanShowExperienceBar, GameRulesUtil.lua:138-140) and shows it;
		-- the hide must check again at the same time (TICK-0117).
		Listen("PLAYER_MAX_LEVEL_UPDATE")
		Listen("UPDATE_EXPANSION_LEVEL")

		HUDini:Refresh()
		-- Refresh skips the show check in a fight (a /reload mid-fight), and
		-- the show check is what starts the poll.
		HUDini:UpdateVisibility()
		UpdateMouseover()

	elseif event == "PLAYER_REGEN_ENABLED" then
		if HUDini.needRefresh then
			HUDini:Refresh()
		elseif HUDini.needRegister then
			HUDini:RegisterButtons()
		end
		if HUDini.needBlizzFrames then
			HUDini:ApplyBlizzardFrames()
		end
		HUDini:UpdateVisibility()

	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_SOFT_ENEMY_CHANGED" then
		HUDini:UpdateVisibility()

	elseif event == "PLAYER_LEVEL_UP" or event == "ENABLE_XP_GAIN" or event == "DISABLE_XP_GAIN"
		or event == "PLAYER_MAX_LEVEL_UPDATE" or event == "UPDATE_EXPANSION_LEVEL" then
		-- Max level, or XP gain off, gives the game's XP bar back to show
		-- the reputation you watch. A max level that comes after the login
		-- hides it (TICK-0117). In a fight this waits for its end.
		-- UnitLevel("player") can still give the old level at
		-- PLAYER_LEVEL_UP, and IsXPUserDisabled may lag the same way, so
		-- check once more a moment later.
		HUDini:ApplyBlizzardFrames()
		C_Timer.After(1, function() HUDini:ApplyBlizzardFrames() end)

	elseif event == "BAG_UPDATE_DELAYED" then
		HUDini:UpdateCounts()
		HUDini:UpdateUsable()

	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
		HUDini:SetGlow(Plain(arg1), true)

	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
		HUDini:SetGlow(Plain(arg1), false)

	elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN"
		or event == "SPELL_UPDATE_CHARGES" then
		HUDini:UpdateCooldowns()
		-- Your racial comes off cooldown, or goes on it, with the debuff
		-- still on you.
		if ns.UpdateRacialGlow then ns.UpdateRacialGlow() end

	elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "SPELL_UPDATE_USABLE"
		or event == "ACTIONBAR_UPDATE_STATE" or event == "PLAYER_TARGET_CHANGED" then
		-- A new target: the target frame may have a part made or turned on
		-- since the last apply, with its mouse on.
		if event == "PLAYER_TARGET_CHANGED" then QueueBlizzardFrames() end
		HUDini:UpdateVisibility()
		HUDini:UpdateUsable()

	elseif REBUILD[event] then
		-- A layout load sets Edit Mode's Opacity on the unit frames again
		-- (EditModeManager.lua:193-202). The refresh waits out a fight; the
		-- hide must not, and it must come after Blizzard's handler.
		if event == "EDIT_MODE_LAYOUTS_UPDATED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
			QueueBlizzardFrames()
		end
		HUDini:QueueRefresh()
	end
end)

--------------------------------------------------------------------------------
-- Slash commands
--
-- /hud (or /hudini) alone opens the options panel. The few commands left
-- (TICK-0019) are in one table, COMMANDS: the word you type, what it takes,
-- one line about it, and the code it runs. /hud help is built from that
-- same table, so it can never fall out of date. Every setting is a row in
-- the options; a command is only for what has no row: setup, why, the lock,
-- test mode, the lists you build, and the tools for a bug report.
--------------------------------------------------------------------------------

local Say, Detail = ns.Say, ns.Detail

--------------------------------------------------------------------------------
-- The longer commands
--------------------------------------------------------------------------------

-- /hud xp reset: a new XP per hour session. The XP bar is a row on the
-- Bars page.
local function XPCommand(rest)
	if rest:lower() == "reset" then
		if ns.ResetXPSession then ns.ResetXPSession() end
		Say(Text("xp.reset"))
	else
		Say(Text("command.xp"))
	end
end

-- Why the HUD is up or down right now: one line. What the game says about
-- weapon buffs is /hud debug weapon.
local function WhyCommand()
	local _, why = HUDini:ShouldShow()
	Say(why)
end

-- What the game says about your weapons and their buffs, line by line, for
-- a bug report. It was part of /hud why.
local function WeaponCommand()
	if not ns.WeaponBuffDetail then return end
	Say(Text("debug.weaponTitle"))
	for _, line in ipairs(ns.WeaponBuffDetail()) do Detail("  " .. line) end
end

-- Every icon on the grid, with its row, column, slot and key.
-- locale: skip a debug report (/hud debug list), in English
local function ListCommand()
	local active = {}
	for _, bar in ipairs(BAR_LAYOUT) do
		if BarEnabled(bar) then tinsert(active, tostring(bar.order)) end
	end
	Say(("show=%s combat=%s hostile=%s visible=%s"):format(
		HUDiniDB.hideWhenIdle and "idle" or "always",
		HUDiniDB.showInCombat and "on" or "off",
		HUDiniDB.showOnHostile and "on" or "off",
		HUDini.body:IsShown() and "yes" or "no"))
	Say(("%d actions, rows=%s, sort=%s, wrap=%d, bars=%s (%s)"):format(
		#HUDini.spells, HUDiniDB.layoutMode, HUDiniDB.sortMode, HUDiniDB.perRow,
		table.concat(active, ","), HUDiniDB.autoBars and "auto" or "manual"))
	for i, e in ipairs(HUDini.spells) do
		local name
		if e.spellID then
			name = C_Spell.GetSpellName(e.spellID) or ("spell " .. e.spellID)
		else
			name = C_Item.GetItemNameByID(e.itemID) or ("item " .. e.itemID)
		end
		Detail(("  %2d. r%d c%-2d %s slot %3d  %-26s %s"):format(
			i, e.row + 1, e.col + 1, e.barName, e.slot, name,
			e.key ~= "" and e.key or "(no bind)"))
	end
end
-- locale: end

-- Which of the 12.x calls HUDini leans on this client has.
local function APICommand()
	local function Mark(v) return v and "|cff33ff33yes|r" or "|cffff3333no|r" end
	local function Has(t, k) return Mark(t and t[k]) end
	Say(Text("debug.apiTitle"))
	Detail("  C_ActionBar.RegisterActionUIButton   " .. Has(C_ActionBar, "RegisterActionUIButton"))
	Detail("  C_ActionBar.GetActionCooldownDuration " .. Has(C_ActionBar, "GetActionCooldownDuration"))
	Detail("  C_ActionBar.IsUsableAction            " .. Has(C_ActionBar, "IsUsableAction"))
	Detail("  C_ActionBar.IsActionInRange           " .. Has(C_ActionBar, "IsActionInRange"))
	Detail("  C_AssistedCombat.GetNextCastSpell     " .. Has(C_AssistedCombat, "GetNextCastSpell"))
	if ns.ReportBars then ns.ReportBars(Detail) end
	if ns.ReportAlerts then ns.ReportAlerts(Detail) end
	Detail("  Cooldown:SetCooldownFromDurationObject " ..
		Mark(HUDini.icons[1] and HUDini.icons[1].cd.SetCooldownFromDurationObject))
end

-- The resource bar diagnosis, printed and saved into HUDiniDB.lastReport so
-- it can be read from the SavedVariables file after a /reload.
local function AuraCommand()
	if not ns.ReportAura then return end
	ns.ReportAura(Detail, Say)
	if ns.SaveReport then
		ns.SaveReport()
		Say(Text("debug.saved"))
	end
end

-- /hud debug <word>: tools for a bug report, not settings. They sit under
-- one word so the command list stays about what players set.
local DEBUG = {
	{ "list", "debug.list", ListCommand },
	{ "api",  "debug.api", APICommand },
	{ "aura", "debug.aura", AuraCommand },
	{ "ids", "debug.ids", function()
		ns.CheckSpellIDs(Say, Detail)
	end },
	{ "weapon", "debug.weapon", WeaponCommand },
	{ "modules", "debug.modules", function()
		-- "1 event", "2 events".
		local function Count(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end
		Say(Text("debug.modulesTitle"))
		for _, m in ipairs(ns.ModuleReport()) do
			Detail(("  %s: %s, %s, %s, %s, %s"):format(m.label, m.on and "on" or "off",
				Count(m.events, "event"), Count(m.tickers, "ticker"), Count(m.timers, "timer"),
				Count(m.frames, "frame")))
			if m.note then Detail("    " .. Text(m.note)) end
			if m.report then Detail("    " .. m.report()) end
		end
	end },
}

local function DebugCommand(rest)
	local word = (rest:match("^(%S*)") or ""):lower()
	for _, d in ipairs(DEBUG) do
		if d[1] == word then return d[3]() end
	end
	if word ~= "" then Say(Text("debug.noTool", word)) end
	Say(Text("debug.tools"))
	for _, d in ipairs(DEBUG) do
		Detail(Text("debug.helpLine", d[1], Text(d[2])))
	end
end

local function VersionCommand()
	Say(ns.VersionLine())
end

local function LockCommand(locked)
	return function()
		HUDiniDB.locked = locked
		Say(locked and Text("lock.on") or Text("lock.off"))
		HUDini:ApplyLock()
	end
end

-- /hud reset asks first. "settings" or "class" names what goes and starts a
-- 30 second window; "yes" inside it does the reset, "no" drops it. One page
-- of the options resets with that page's Defaults button instead.
--
-- Both resets work in place: they empty the saved tables and fill them again,
-- never swap them for new ones. The options panel holds on to these tables
-- (the Read Bar rows are bound to HUDiniDB.bars), and a swapped table would
-- leave those rows writing into one that is no longer saved.
local RESET_WINDOW = 30
local pendingReset  -- { what = "settings" | "class", at = GetTime() }

local function ClassName()
	return UnitClass("player") or Text("reset.class")
end

-- Every key in ns.defaults back to its default. Data that is not a setting
-- stays: each class's position, spell choices and tracked buffs (classes),
-- the XP and feed history, and the last /hud debug aura report. So do two
-- lists the player built by hand, which live in ns.defaults only so they
-- start empty.
local KEEP_ON_RESET = {
	auraMap    = true,  -- your buff pairs, /hud auramap
	feedIgnore = true,  -- items the feed never shows, /hud feedignore
}

local function ResetSettings()
	local db = HUDiniDB
	for k, v in pairs(ns.defaults) do
		if KEEP_ON_RESET[k] then
			-- leave it
		elseif type(v) == "table" then
			-- Never empty ns.defaults itself.
			if type(db[k]) ~= "table" or db[k] == v then db[k] = {} end
			wipe(db[k])
		else
			db[k] = nil
		end
	end
	FillDefaults(db)
end

-- Your class's position, spell choices, tracked buffs (buffSpells, Auras.lua)
-- and the buffs seen to stack (stackBuffs, Auras.lua), for this class only.
local function ResetClass()
	wipe(ns.ClassDB())
end

local RESETS = {
	settings = {
		run  = ResetSettings,
		ask  = function() return Text("reset.askSettings") end,
		done = function() return Text("reset.doneSettings") end,
	},
	class = {
		run  = ResetClass,
		ask  = function() return Text("reset.askClass", ClassName()) end,
		done = function() return Text("reset.doneClass", ClassName()) end,
	},
}

local function ResetCommand(rest)
	local word = rest:lower():match("^%s*(.-)%s*$")
	local reset = RESETS[word]
	if reset then
		pendingReset = { what = word, at = GetTime() }
		Say(reset.ask())
		Say(Text("reset.confirm", RESET_WINDOW))
	elseif word == "yes" then
		local pending = pendingReset
		pendingReset = nil
		if not pending or GetTime() - pending.at > RESET_WINDOW then
			Say(Text("reset.nothing"))
			return
		end
		reset = RESETS[pending.what]
		reset.run()
		Say(reset.done())
		HUDini:Apply()
		if ns.RefreshBars then ns.RefreshBars() end
	elseif word == "no" then
		pendingReset = nil
		Say(Text("reset.canceled"))
	else
		if pendingReset then Say(Text("reset.canceled")) end
		pendingReset = nil
		Say(Text("reset.helpSettings"))
		Say(Text("reset.helpClass", ClassName()))
		Say(Text("reset.helpPage"))
	end
end

--------------------------------------------------------------------------------
-- The command table
--
-- { word, what it takes, what it does, function(rest, n) }
-- rest is the text after the word; n is that text as a number, or nil.
-- A { section = "..." } row starts a group in /hud help. The section and
-- what it does are keys in Locales/enUS.lua, read when /hud help prints, so
-- they follow the flair level.
--------------------------------------------------------------------------------

local HelpCommand  -- below, it reads the table

-- Options > HUDini. /hud config, setup's Options button and a left-click
-- on the minimap button. HUDini's own rule: not in a fight
-- (D-009). Blizzard's panel has no combat check.
-- True when the options opened.
function ns.OpenOptions()
	if InCombatLockdown() then
		Say(ns.Text("options.inCombat"))
		return false
	end
	if not ns.category then return false end
	Settings.OpenToCategory(ns.category:GetID())
	return true
end

local COMMANDS = {
	{ section = "help.section.hud" },
	{ "options", "",                       "help.options", function() return ns.OpenOptions() end, alias = "config" },
	-- /hud welcome was the welcome card's command: a quiet alias for old notes.
	{ "setup",   "",                       "help.setup", function() ns.OpenSetup() end, alias = "welcome" },
	{ "why",     "",                       "help.why", WhyCommand },
	{ "lock",    "",                       "help.lock", LockCommand(true) },
	{ "unlock",  "",                       "help.unlock", LockCommand(false) },
	{ "test",    "",                       "help.test", function() ns.TestMode() end },

	{ section = "help.section.lists" },
	{ "buffs",   "[forget Name|clear]",    "help.buffs", function(rest) -- locale: skip command syntax
		if ns.BuffsCommand then ns.BuffsCommand(rest, Say) end
	end },
	{ "auramap", "[Spell = Buff]",         "help.auramap", function(rest) -- locale: skip command syntax
		if ns.AuraMapCommand then ns.AuraMapCommand(rest, Say) end
	end },
	{ "feedignore", "[item|clear]",        "help.feedignore", function(rest) ns.FeedIgnore(rest) end }, -- locale: skip command syntax
	{ "feedsession", "[reset]",            "help.feedsession", function(rest) ns.FeedSession(rest) end },
	{ "xp",      "reset",                  "help.xp", XPCommand },

	{ section = "help.section.help" },
	{ "help",    "[command]",              "help.help", function(rest) HelpCommand(rest) end },
	{ "version", "",                       "help.version", VersionCommand },
	{ "debug",   "list|api|aura|modules|ids|weapon", "help.debug", DebugCommand }, -- locale: skip command syntax
	{ "reset",   "settings|class|yes|no",  "help.reset", ResetCommand }, -- locale: skip command syntax
}

-- word -> command row, aliases included.
local BY_WORD = {}
for _, c in ipairs(COMMANDS) do
	if c[1] then
		BY_WORD[c[1]] = c
		if c.alias then BY_WORD[c.alias] = c end
	end
end

-- "count N", or just "glow" for a command that takes nothing.
local function Usage(c)
	return c[2] ~= "" and (c[1] .. " " .. c[2]) or c[1]
end

-- /hud help prints one line per section; /hud help <word> explains one.
function HelpCommand(rest)
	local word = rest:lower()
	local c = BY_WORD[word]
	if c then
		Say(("/hud %s - %s"):format(Usage(c), Text(c[3])))
		return
	end
	if word ~= "" then Say(Text("command.unknown", word)) end
	Say(Text("help.intro"))
	local section, words
	local function Flush()
		if section then Detail(("  |cffffd200%s:|r %s"):format(section, table.concat(words, ", "))) end
	end
	for _, row in ipairs(COMMANDS) do
		if row.section then
			Flush()
			section, words = Text(row.section), {}
		else
			words[#words + 1] = Usage(row)
		end
	end
	Flush()
	if ns.ownsReload then
		Detail(("  |cffffd200%s:|r %s"):format(Text("help.section.shortcut"), Text("help.rl")))
	end
end

SLASH_HUDINI1 = "/hudini"
SLASH_HUDINI2 = "/hud"

-- /rl, short for /reload (TICK-0048). Many addons register /rl too, and two
-- owners of one slash command means the game picks one at random. So HUDini
-- takes /rl only if no other addon has it: at PLAYER_LOGIN every addon that
-- loads with the game has run its main chunk, so its SLASH_ globals exist.
local function SomeoneHasReload()
	for k, v in pairs(_G) do
		if type(k) == "string" and type(v) == "string" and k:find("^SLASH_")
				and v:lower() == "/rl" then
			return true
		end
	end
	return false
end

local reloadClaim = CreateFrame("Frame")
reloadClaim:RegisterEvent("PLAYER_LOGIN")
reloadClaim:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	if SomeoneHasReload() then return end
	SLASH_HUDINIRELOAD1 = "/rl"
	SlashCmdList.HUDINIRELOAD = function() ReloadUI() end
	ns.ownsReload = true
end)

SlashCmdList.HUDINI = function(input)
	local word, rest = input:match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()

	if word == "" then
		-- The options open, or say why not; then the way to the commands.
		if not BY_WORD.options[4]() then Say(Text("help.helpHint")) end
		return
	end

	local c = BY_WORD[word]
	if not c then
		Say(Text("command.unknownHint", word))
		return
	end
	c[4](rest, tonumber(rest))
end
