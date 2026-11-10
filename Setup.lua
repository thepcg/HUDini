--[[--------------------------------------------------------------------------
	HUDini - Setup

	HUDini setup (D-007, TICK-0042): page 1
	says what HUDini is and asks the flair level, six steps set up the HUD
	and the feed (TICK-0096: what the HUD shows, hide when idle, size and
	place, the feed, the game's own frames, a quieter screen), and page 8
	says what is on. Every pick writes its keys at once and the HUD under
	the window shows the result. Each page has a default, so a player who
	only clicks Next ends with the defaults.

	A plain window: no secure template, no protected frame. It writes
	settings only, through the same keys as the options panel. It shows at
	login until it has closed once (welcomeSeen, saved per account), and on
	/hud setup.

	Every exit (Done, Skip setup, the close button, Escape, Options) runs
	one Finish: the HUD and the feed lock, the feed's sample lines go, and
	setup counts as seen. Nothing else is an exit. A fight hides it without
	a Finish: the HUD and the feed lock, the samples go (the feed's and
	step 1's sample target), and setup comes back on the same page when
	the fight ends. A loading screen, a loss of
	control or Alt-Z does not close it: setup is not in UISpecialFrames.

	Only Escape is a key: Enter and every other key go on to the game, so
	the player can open chat and type the /hud commands the pages name.

	The options panel can be open under setup (Options > Run setup, or
	/hud config): setup draws over it, and each pick repaints its rows.
----------------------------------------------------------------------------]]

local _, ns = ...

local Text = ns.Text

local WIDTH, PAD, GAP = 600, 20, 10
local INNER = WIDTH - 2 * PAD
local ICON = "Interface\\AddOns\\HUDini\\Media\\icon.tga"
local FIRST, LAST = 1, 8          -- page 1, steps 1-6 are pages 2-7, page 8
local LOGIN_DELAY = 2             -- seconds after the loading screen
local SCALE_EPSILON = 0.005

-- The keys setup writes, so a second run can put back "Keep your own".
local BLIZZARD_KEYS = { "hideBlizzardTarget", "hideBlizzardCastBar", "hideBlizzardXP" }
-- Step 6, a quieter screen (D-018, TICK-0086): the two mouse-over rows.
-- Each keeps its own Options row on Game frames. The gryphons are not
-- HUDini's to hide (D-024): the step teaches Edit Mode's box instead.
local QUIET_KEYS = { "bagBarMouseover", "menuBarMouseover" }
-- Step 1, what the HUD shows (TICK-0115): a check box for each extra, each
-- its own Bars row. No "Keep your own": a box shows its key as it is now.
local HUD_KEYS = { "showXP", "showTargetPower", "showTargetDebuffs" }
-- Step 4, the feed (TICK-0096). Its size buttons write FEED_SIZE_KEYS.
local FEED_KEYS = { "showFeed", "feedQuestProgress", "feedUpgrade" }
local FEED_SIZE_KEYS = { "feedFontSize", "feedWidth" }
local FEED_SIZES = {
	{ text = "setup.feed.small",  font = 12, width = 360 },
	{ text = "setup.feed.medium", font = 14, width = 420, isDefault = true },
	{ text = "setup.feed.large",  font = 17, width = 500 },
}
local HUD_PAGE, SIZE_PAGE, FEED_PAGE = 2, 4, 5

ns.setupOpen = false

local frame, parts
local page = FIRST
local isOpen = false        -- open, or hidden for a fight and coming back
local hiddenForFight = false
local wantOpen = false      -- asked for in a fight: open when it ends
local secondRun = false     -- setup had closed before this run opened
local own = {}              -- the values at open, for "Keep your own"
local feedMoving = false    -- Move the feed: the feed alone is unlocked

local function DB() return HUDiniDB end

local function Apply()
	ns.HUDini:Apply()
end

-- The options panel's rows for these keys read their values again, if the
-- panel is open (Options.lua registers each key as "HUDini_" .. key).
local function RepaintOptions(keys)
	if not (SettingsPanel and SettingsPanel:IsShown() and Settings.GetSetting) then return end
	for _, key in ipairs(keys) do
		local setting = Settings.GetSetting("HUDini_" .. key)
		if setting and setting.NotifyUpdate then setting:NotifyUpdate() end
	end
end

-- Lock the feed (Move the feed) and the HUD (Move the HUD).
local function Lock()
	if feedMoving then
		feedMoving = false
		ns.FeedUnlock(false)
	end
	local db = DB()
	if db.locked then return end
	db.locked = true
	ns.HUDini:ApplyLock()
	RepaintOptions({ "locked" })
end

-- The feed's sample lines (FeedWatch.lua): on while the feed step shows.
local function Samples(on)
	if ns.FeedSamples then ns.FeedSamples(on) end
end

-- Test mode's sample target alone (TestMode.lua): on while step 1 shows,
-- so a Target power click shows at once. A real target wins.
local function SampleTarget(on)
	if ns.SampleTargetOnly then ns.SampleTargetOnly(on) end
end

--------------------------------------------------------------------------------
-- The pages
--
-- A choice: label, line (the explanation under it, or nil), isDefault,
-- picked() (it matches the saved values now) and pick() (write and apply).
-- own[page] holds the values at open when no choice matched them: the
-- page then lists "Keep your own", which puts those values back.
--------------------------------------------------------------------------------

local function Choice(label, line, isDefault, picked, pick)
	return { label = label, line = line, isDefault = isDefault, picked = picked, pick = pick }
end

local function FlairChoice(level)
	return Choice(Text("flair." .. level), Text("flair." .. level .. ".tip"), level == 0,
		function() return ns.FlairLevel() == level end,
		function() DB().flair = level; Apply() end)
end

local function IdleChoice(key, value)
	return Choice(Text("setup.s2." .. key), Text("setup.s2." .. key .. ".line"), value,
		function() return DB().hideWhenIdle == value end,
		function() DB().hideWhenIdle = value; Apply() end)
end

local function SameScale(a, b)
	return type(a) == "number" and math.abs(a - b) < SCALE_EPSILON
end

local function ScaleChoice(key, value)
	return Choice(Text("setup.s3." .. key), Text("setup.s3." .. key .. ".line"), value == 1.0,
		function() return SameScale(DB().scale, value) end,
		function() DB().scale = value; Apply() end)
end

-- One choice sets each of keys to its value in values (a list in the
-- same order, or one value for all), and is picked when all of them have
-- it. texts is the step's text prefix. The pick goes through HUDini:Apply,
-- as the Options rows do, so the faded bars change at once.
local function AllChoice(texts, keys, key, values, isDefault)
	local function Want(i)
		if type(values) == "table" then return values[i] end
		return values
	end
	return Choice(Text(texts .. "." .. key), Text(texts .. "." .. key .. ".line"), isDefault,
		function()
			for i, k in ipairs(keys) do
				if (DB()[k] and true or false) ~= Want(i) then return false end
			end
			return true
		end,
		function()
			for i, k in ipairs(keys) do DB()[k] = Want(i) end
			Apply()
		end)
end

-- A check box of step 1: one key, its label and its line. A box that needs
-- Target health bar is gray while that is off, as its Options row is.
local function Box(key, texts, needsTarget)
	return {
		key = key, label = Text(texts), line = Text(texts .. ".line"),
		enabled = function() return not needsTarget or DB().showTargetHealth and true or false end,
	}
end

-- The game has no row for your debuffs on the target: the TargetDebuffs
-- module tried to make it and could not (TargetDebuffs.lua Build).
local function NoDebuffRow()
	return ns.TargetDebuffRow ~= nil and ns.TargetDebuffRow() == false
end

-- The values a page writes, copied out of the saved table.
local function Copy(keys)
	local out, db = {}, DB()
	for _, k in ipairs(keys) do out[k] = db[k] end
	return out
end

local function PutBack(values)
	local db = DB()
	for k, v in pairs(values) do db[k] = v end
	Apply()
end

-- The steps, by page number. Each gives its choices, the keys a "Keep
-- your own" puts back, the options rows a pick repaints, and its own
-- texts' keys. Steps 1-6 name their intro's key in full (TICK-0076);
-- question, under and changes, when set, name theirs too (changes may be
-- a function). lesson(), when there, says if the step's lesson shows now.
-- after(), when there, runs after a pick on the step. boxes(), when there,
-- gives check boxes in place of the choices (step 1, TICK-0115).
local STEPS = {
	[1] = {
		texts = "setup.p1",
		rows = function() return { "flair" } end,
		choices = function() return { FlairChoice(0), FlairChoice(1), FlairChoice(2) } end,
	},
	[HUD_PAGE] = {
		texts = "setup.hud",
		intro = "setup.hud.essentials",
		question = "setup.hud.extras.question",
		under = "setup.hud.extras.under",
		-- Without the debuff row, its box and its name go.
		changes = function()
			return NoDebuffRow() and "setup.hud.extras.changes.noDebuffs" or "setup.hud.extras.changes"
		end,
		rows = function() return HUD_KEYS end,
		boxes = function()
			local list = {
				Box("showXP", "setup.hud.xp"),
				Box("showTargetPower", "setup.hud.targetPower", true),
			}
			if not NoDebuffRow() then list[3] = Box("showTargetDebuffs", "setup.hud.debuffs", true) end
			return list
		end,
		choices = function() return {} end,
	},
	[3] = {
		texts = "setup.s2",
		intro = "setup.s2.intro",
		rows = function() return { "hideWhenIdle" } end,
		choices = function() return { IdleChoice("smart", true), IdleChoice("always", false) } end,
	},
	[SIZE_PAGE] = {
		-- The question and the choices keep their setup.s3 keys.
		texts = "setup.s3",
		intro = "setup.size.intro",
		under = "setup.size.under",
		changes = "setup.size.changes",
		keys = function() return { "scale" } end,
		rows = function() return { "scale", "locked" } end,
		ownValue = function(values)
			local scale = values.scale
			if type(scale) ~= "number" then return nil end
			return ("%d%%"):format(math.floor(scale * 100 + 0.5))
		end,
		choices = function()
			return { ScaleChoice("small", 0.85), ScaleChoice("medium", 1.0), ScaleChoice("large", 1.2) }
		end,
	},
	[FEED_PAGE] = {
		texts = "setup.feed",
		intro = "setup.feed.intro",
		keys = function() return FEED_KEYS end,
		rows = function()
			local list = { unpack(FEED_KEYS) }
			for _, k in ipairs(FEED_SIZE_KEYS) do list[#list + 1] = k end
			return list
		end,
		-- The feed on: its samples show (they follow the kinds that are
		-- on). Off: the feed locks, as no box is left to drag.
		after = function()
			if DB().showFeed then
				Samples(true)
			elseif feedMoving then
				feedMoving = false
				ns.FeedUnlock(false)
			end
		end,
		choices = function()
			return {
				AllChoice("setup.feed", FEED_KEYS, "off", { false, false, false }, false),
				AllChoice("setup.feed", FEED_KEYS, "on", { true, false, false }, true),
				AllChoice("setup.feed", FEED_KEYS, "hints", { true, true, true }, false),
			}
		end,
	},
	[6] = {
		texts = "setup.s5",
		intro = "setup.s5.intro",
		keys = function() return BLIZZARD_KEYS end,
		rows = function() return BLIZZARD_KEYS end,
		-- The chat lesson: the feed shows loot, money and XP (TICK-0096).
		lesson = function() return DB().showFeed and true or false end,
		choices = function()
			return {
				AllChoice("setup.s5", BLIZZARD_KEYS, "no", false, true),
				AllChoice("setup.s5", BLIZZARD_KEYS, "yes", true, false),
			}
		end,
	},
	[7] = {
		texts = "setup.s6",
		intro = "setup.s6.intro",
		keys = function() return QUIET_KEYS end,
		rows = function() return QUIET_KEYS end,
		-- The lesson says a hidden Action Bar 2 or 3 stays on the HUD. That
		-- is true only in Row mode "bar", which reads Action Bars 1-3 by
		-- slot, shown or not. Pack and wrap with Auto pick bars reads only
		-- the bars on screen (Core.lua:401-403), so there it shows no
		-- lesson (TICK-0085; TICK-0088 owns that case).
		lesson = function() return DB().layoutMode == "bar" end,
		-- Edit Mode hides the gryphons (D-024, TICK-0089): shown always.
		gryphons = function() return Text("setup.s6.gryphons", ns.GryphonBoxName()) end,
		choices = function()
			return {
				AllChoice("setup.s6", QUIET_KEYS, "no", false, true),
				AllChoice("setup.s6", QUIET_KEYS, "yes", true, false),
			}
		end,
	},
}

local function AnyPicked(choices)
	for _, c in ipairs(choices) do
		if c.picked() then return true end
	end
	return false
end

-- At open: for each page whose saved values match no choice, keep a copy,
-- so the page can offer "Keep your own".
local function TakeOwn()
	own = {}
	for n, step in pairs(STEPS) do
		if step.keys and not AnyPicked(step.choices()) then own[n] = Copy(step.keys()) end
	end
end

-- The page's choices now, with "Keep your own" last when it applies.
local function Choices(n)
	local step = STEPS[n]
	local list = step.choices()
	local values = own[n]
	if values then
		local value = step.ownValue and step.ownValue(values)
		local label = value and Text("setup.keepOwnValue", value) or Text("setup.keepOwn")
		local others = { unpack(list) }
		list[#list + 1] = Choice(label, nil, false,
			function() return not AnyPicked(others) end,
			function() PutBack(values) end)
	end
	return list
end

--------------------------------------------------------------------------------
-- Page 8: the alerts that are on, and the bars HUDini does not read
-- (its texts keep their setup.p7.* keys)
--------------------------------------------------------------------------------

-- The alert keys in the order page 8 lists them, with the row that turns
-- each one on.
local ALERTS = {
	{ key = "interrupt", row = "glowOnKickable", text = "setup.p7.interrupt" },
	{ key = "dispel",    row = "warnDispel",     text = "setup.p7.dispel" },
	{ key = "purge",     row = "showPurgeable",  text = "setup.p7.purge" },
	{ key = "keepUp",    row = "warnKeepUp",     text = "setup.p7.keepUp" },
}

-- The spells a class value names, in a fixed order: a name, a list, a
-- dispel table by type (sorted by type), or a purge table with .spell.
local function Spells(key, value)
	if type(value) ~= "table" then return { value } end
	if key == "purge" and value.spell ~= nil then return { value.spell } end
	if key == "dispel" then
		local types = {}
		for t in pairs(value) do types[#types + 1] = t end
		table.sort(types)
		local list = {}
		for i, t in ipairs(types) do list[i] = value[t] end
		return list
	end
	return value
end

-- A spell as the player reads it: its name. A spell ID (a pick saved by
-- ID) reads its name from the game. Anything else (false is "None") is nil.
local function SpellName(spell)
	if type(spell) == "string" then return spell ~= "" and spell or nil end
	if type(spell) == "number" then
		return (C_Spell.GetSpellName and C_Spell.GetSpellName(spell)) or tostring(spell)
	end
	return nil
end

-- The alert lines for the class now, out of combat. Returns the lines (a
-- list of texts, maybe empty) and whether the class file names an alert
-- spell the player does not know yet. A row that is off counts as no alert.
function ns.SetupAlertLines()
	local db, lines, unknown, named = DB(), {}, false, false
	for _, alert in ipairs(ALERTS) do
		local value = db[alert.row] and ns.ClassValue(alert.key)
		local spells = value and Spells(alert.key, value) or {}
		local known = {}
		for _, spell in ipairs(spells) do
			local name = SpellName(spell)
			if name then
				named = true
				if ns.KnownSpell(spell) then
					known[#known + 1] = name
				else
					unknown = true
				end
			end
		end
		if #known > 0 then
			-- The interrupt line names every known spell; the others the first.
			local name = alert.key == "interrupt" and table.concat(known, ", ") or known[1]
			lines[#lines + 1] = Text(alert.text, name)
		end
	end
	return lines, unknown, named
end

-- Action Bars 4-8 that are on screen and hold an action, while Row mode
-- is "a row each for Bars 1-3". Returns the bar numbers.
function ns.SetupUnreadBars()
	local db, out = DB(), {}
	if db.layoutMode ~= "bar" then return out end
	for _, bar in ipairs(ns.BAR_LAYOUT) do
		local f = bar.order >= 4 and _G[bar.frame]
		if f and f:IsShown() then
			for slot = bar.first, bar.first + 11 do
				if ns.SlotAction(slot) then
					out[#out + 1] = bar.order
					break
				end
			end
		end
	end
	return out
end

-- "Action Bar 5", "Action Bars 5 and 6", "Action Bars 4, 5 and 6".
local function BarNames(list)
	if #list == 1 then return Text("setup.p7.bar", list[1]) end
	local head = {}
	for i = 1, #list - 1 do head[i] = tostring(list[i]) end
	return Text("setup.p7.barsList", table.concat(head, ", "), tostring(list[#list]))
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

-- A solid background (TICK-0079): the dialog background is see-through,
-- and the options panel's text showed through it. The dialog border stays.
local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- Drag the window with the left button from any part that takes no click
-- of its own (TICK-0079); buttons, choices and the text box keep theirs.
-- It stays on the screen. SetUserPlaced(false) after each drag: the game
-- then does not save the place, so the window keeps it until a /reload or
-- a new login, and opens at its default place after that. A hide in the
-- middle of a drag ends the drag.
local function Drop(self)
	self:StopMovingOrSizing()
	self:SetUserPlaced(false)
end

local function Movable(f)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", Drop)
end

local function Label(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	return fs
end

local function Button(parent, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 110, 22)
	return b
end

local ROW_BORDER = { 0.45, 0.45, 0.45 }
local ROW_PICKED = { 1, 0.82, 0 }

local Paint, Go, Finish

-- The text parts, top to bottom. Each page shows some of them.
local PARTS = { "intro", "top", "question", "body", "alerts", "bars", "under", "lesson", "gryphons", "steps", "changes",
	"last" }

-- A choice row: a radio dot, the name, "(default)" and the line under it.
-- The picked row has a filled dot and a gold border.
local function Row(parent)
	local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
	r:SetWidth(INNER)
	r:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	r:SetBackdropColor(0, 0, 0, 0.4)
	r.dot = CreateFrame("CheckButton", nil, r, "UIRadioButtonTemplate")
	r.dot:SetPoint("TOPLEFT", 8, -7)
	r.name = Label(r, "GameFontNormal")
	r.name:SetWordWrap(false)
	r.name:SetPoint("TOPLEFT", 30, -8)
	r.tag = Label(r, "GameFontHighlightSmall")
	r.tag:SetWordWrap(false)
	r.tag:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
	r.line = Label(r, "GameFontHighlight")
	r.line:SetWidth(INNER - 40)
	r.line:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
	local function Click()
		if r.choice then
			local step = STEPS[page]
			r.choice.pick()
			if step.after then step.after() end
			RepaintOptions(step.rows())
			Paint()
		end
	end
	r:SetScript("OnClick", Click)
	r.dot:SetScript("OnClick", Click)
	return r
end

local function FillRow(r, choice)
	r.choice = choice
	r.name:SetText(choice.label)
	r.tag:SetText(choice.isDefault and Text("setup.default") or "")
	r.line:SetText(choice.line or "")
	r.line:SetShown(choice.line ~= nil)
	local picked = choice.picked()
	r.dot:SetChecked(picked)
	local c = picked and ROW_PICKED or ROW_BORDER
	r:SetBackdropBorderColor(c[1], c[2], c[3])
	local h = 16 + 12 + (choice.line and (4 + r.line:GetStringHeight()) or 0)
	r:SetHeight(h)
	r:Show()
	return h
end

-- A check box row (step 1, TICK-0115): a choice row with the game's check
-- box in the place of the radio dot. A click writes that one key at once
-- and applies it, as its Options row does; no other key changes.
local function BoxRow(parent)
	local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
	r:SetWidth(INNER)
	r:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	r:SetBackdropColor(0, 0, 0, 0.4)
	r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
	r.check:SetSize(22, 22)
	r.check:SetPoint("TOPLEFT", 5, -4)
	r.name = Label(r, "GameFontNormal")
	r.name:SetWordWrap(false)
	r.name:SetPoint("TOPLEFT", 30, -8)
	r.line = Label(r, "GameFontHighlight")
	r.line:SetWidth(INNER - 40)
	r.line:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
	local function Click()
		local box = r.box
		if not (box and box.enabled()) then
			Paint()
			return
		end
		local db = DB()
		db[box.key] = not db[box.key]
		Apply()
		RepaintOptions({ box.key })
		Paint()
	end
	r:SetScript("OnClick", Click)
	r.check:SetScript("OnClick", Click)
	return r
end

local function FillBox(r, box)
	r.box = box
	r.name:SetText(box.label)
	r.line:SetText(box.line)
	local on = DB()[box.key] and true or false
	local enabled = box.enabled()
	r.check:SetChecked(on)
	r.check:SetEnabled(enabled)
	r:SetEnabled(enabled)
	-- Gray, as the Options row is; the line stays.
	r.name:SetFontObject(enabled and "GameFontNormal" or "GameFontDisable")
	local c = (on and enabled) and ROW_PICKED or ROW_BORDER
	r:SetBackdropBorderColor(c[1], c[2], c[3])
	local h = 16 + 12 + 4 + r.line:GetStringHeight()
	r:SetHeight(h)
	r:Show()
	return h
end

local function Build()
	local f = CreateFrame("Frame", "HUDiniSetup", UIParent, "BackdropTemplate")
	f:SetWidth(WIDTH)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(0, 0, 0, 1)
	Movable(f)
	f:Hide()

	local p = { rows = {}, boxes = {} }
	p.icon = f:CreateTexture(nil, "ARTWORK")
	p.icon:SetTexture(ICON)
	p.icon:SetSize(40, 40)
	p.icon:SetPoint("TOPLEFT", PAD, -PAD)
	p.title = Label(f, "GameFontNormalLarge")
	p.title:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 10, -2)
	p.counter = Label(f, "GameFontDisable")
	p.counter:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)

	p.x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	p.x:SetPoint("TOPRIGHT", -6, -6)
	p.x:SetScript("OnClick", function() Finish() end)
	p.x:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Text("setup.skip"))
		GameTooltip:Show()
	end)
	p.x:SetScript("OnLeave", function() GameTooltip:Hide() end)

	p.intro    = Label(f, "GameFontHighlight")     -- steps 1-6
	p.top      = Label(f, "GameFontHighlight")     -- page 1's pitch, or the second-run line
	p.question = Label(f, "GameFontNormal")
	p.body     = Label(f, "GameFontHighlight")     -- page 8
	p.alerts   = Label(f, "GameFontHighlight")     -- page 8
	p.bars     = Label(f, "GameFontHighlight")     -- page 8
	p.under    = Label(f, "GameFontHighlight")
	p.lesson   = Label(f, "GameFontHighlight")     -- step 6
	p.gryphons = Label(f, "GameFontHighlight")     -- step 6
	p.steps    = Label(f, "GameFontHighlight")     -- page 1
	p.changes  = Label(f, "GameFontHighlightSmall")
	p.last     = Label(f, "GameFontHighlight")     -- page 8
	for _, key in ipairs(PARTS) do
		p[key]:SetWidth(INNER)
	end

	-- Step 3: Move the HUD, a toggle that says Lock while the HUD is
	-- unlocked (TICK-0096).
	p.moveHud = Button(f, 130)
	p.moveHud:SetScript("OnClick", function()
		if DB().locked then
			DB().locked = false
			ns.HUDini:ApplyLock()
			RepaintOptions({ "locked" })
		else
			Lock()
		end
		ns.HUDini:UpdateVisibility()
		Paint()
	end)

	-- Step 4, the tools row while the feed is on: "Size:", three size
	-- buttons, and Move the feed, a toggle that unlocks the feed alone.
	p.sizeLabel = Label(f, "GameFontNormal")
	p.sizeLabel:SetWordWrap(false)
	p.sizeLabel:SetWidth(50)
	p.sizes = {}
	for i, size in ipairs(FEED_SIZES) do
		local b = Button(f, size.isDefault and 140 or 80)
		b.size = size
		b:SetScript("OnClick", function()
			local db = DB()
			db.feedFontSize, db.feedWidth = size.font, size.width
			ns.ApplyFeed()
			RepaintOptions(FEED_SIZE_KEYS)
			Paint()
		end)
		p.sizes[i] = b
	end
	p.moveFeed = Button(f, 130)
	p.moveFeed:SetScript("OnClick", function()
		if feedMoving then
			feedMoving = false
			ns.FeedUnlock(false)
		else
			feedMoving = true
			ns.FeedUnlock(true)
		end
		Paint()
	end)

	-- The buttons: two on the left, the main one on the right.
	p.left1 = Button(f)
	p.left2 = Button(f)
	p.main  = Button(f)

	-- Escape is Skip setup; every other key, Enter too, goes on to the game
	-- (designer, TICK-0042). Setup takes Escape itself and is not in
	-- UISpecialFrames: the game hides those at every loading screen, on a
	-- loss of control and on Alt-Z, and none of those is an exit. No
	-- OnHide closes setup for the same reason. SetPropagateKeyboardInput
	-- is blocked in combat; setup is hidden in a fight, and the guard
	-- keeps it that way.
	-- The only OnHide ends a drag (Movable); it never closes setup.
	f:SetScript("OnHide", Drop)
	f:EnableKeyboard(true)
	f:SetPropagateKeyboardInput(true)
	f:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then return end
		local escape = key == "ESCAPE"
		self:SetPropagateKeyboardInput(not escape)
		if escape then Finish() end
	end)
	-- The tests click the rows and buttons through it (tools/tests).
	f.parts = p
	frame, parts = f, p
end

local function SetButton(b, key, fn)
	if not key then
		b:Hide()
		return
	end
	b:SetText(Text(key))
	b.fn = fn
	b:SetScript("OnClick", fn)
	b:Show()
end

-- Fill in the page at the flair level now and stack its parts.
function Paint()
	if not frame then return end
	local p, n, step = parts, page, STEPS[page]
	local db = DB()
	p.title:SetText(Text("setup.title"))
	local isStep = n > FIRST and n < LAST
	p.counter:SetText(isStep and Text("setup.step", n - 1, LAST - 2) or "")

	local stack = {}
	local function Add(part, text)
		part:SetText(text)
		part:Show()
		stack[#stack + 1] = part
	end
	for _, key in ipairs(PARTS) do
		p[key]:Hide()
	end
	for _, r in ipairs(p.rows) do r:Hide() end
	for _, r in ipairs(p.boxes) do r:Hide() end
	p.moveHud:Hide()
	p.sizeLabel:Hide()
	for _, b in ipairs(p.sizes) do b:Hide() end
	p.moveFeed:Hide()

	local rowsAt
	if step then
		-- A step says what the part is before it asks (TICK-0076).
		if step.intro then Add(p.intro, Text(step.intro)) end
		-- A second run says what Next does now, not what HUDini is (TICK-0083).
		if n == FIRST then Add(p.top, secondRun and Text("setup.p1.again") or Text("setup.p1.pitch")) end
		Add(p.question, Text(step.question or step.texts .. ".question"))
		rowsAt = #stack
		if n == FIRST then
			Add(p.under, Text("setup.p1.under"))
			Add(p.steps, Text("setup.p1.steps"))
		else
			Add(p.under, Text(step.under or step.texts .. ".under"))
			-- Read after the pick and before Next; off, it takes no space.
			if step.lesson and step.lesson() then Add(p.lesson, Text(step.texts .. ".lesson")) end
			if step.gryphons then Add(p.gryphons, step.gryphons()) end
		end
		local changes = step.changes
		if type(changes) == "function" then changes = changes() end
		Add(p.changes, Text(changes or step.texts .. ".changes"))
	else
		Add(p.question, Text("setup.p7.question"))
		Add(p.body, db.hideWhenIdle and Text("setup.p7.body") or Text("setup.p7.bodyAlways"))
		local lines, unknown, named = ns.SetupAlertLines()
		local class = UnitClass("player")
		if #lines > 0 then
			local text = Text("setup.p7.alerts", class) .. "\n" .. table.concat(lines, "\n")
			if unknown then text = text .. "\n" .. Text("setup.p7.more") end
			-- /hud test plays them (TICK-0096); only when some are on.
			Add(p.alerts, text .. "\n" .. Text("setup.p7.test"))
		elseif named then
			Add(p.alerts, Text("setup.p7.noAlerts", class))
		end
		local bars = ns.SetupUnreadBars()
		if #bars > 0 then Add(p.bars, Text("setup.p7.bars", BarNames(bars))) end
		Add(p.last, Text("setup.p7.last"))
	end

	-- Stack the parts under the title; the rows go after the question.
	local y = PAD + 40 + GAP
	local function Place(part, h, x)
		part:ClearAllPoints()
		part:SetPoint("TOPLEFT", frame, "TOPLEFT", x or PAD, -y)
		y = y + h + GAP
	end
	for i, part in ipairs(stack) do
		Place(part, part:GetStringHeight())
		if i == rowsAt then
			for j, choice in ipairs(Choices(n)) do
				local r = p.rows[j] or Row(frame)
				p.rows[j] = r
				Place(r, FillRow(r, choice) - GAP + 4)
			end
			for j, box in ipairs(step.boxes and step.boxes() or {}) do
				local r = p.boxes[j] or BoxRow(frame)
				p.boxes[j] = r
				Place(r, FillBox(r, box) - GAP + 4)
			end
			y = y + GAP - 4
			if n == SIZE_PAGE then
				p.moveHud:SetText(Text(db.locked and "setup.size.move" or "setup.lock"))
				p.moveHud:Show()
				Place(p.moveHud, 22, PAD + 30)
			elseif n == FEED_PAGE and db.showFeed then
				-- No row at all while the feed is off.
				local x = PAD + 30
				p.sizeLabel:SetText(Text("setup.feed.size"))
				p.sizeLabel:ClearAllPoints()
				p.sizeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(y + 4))
				p.sizeLabel:Show()
				x = x + 50
				for _, b in ipairs(p.sizes) do
					local size = b.size
					local label = Text(size.text)
					if size.isDefault then label = label .. " " .. Text("setup.default") end
					b:SetText(label)
					-- Picked when both values match.
					b.picked = db.feedFontSize == size.font and db.feedWidth == size.width
					if b.picked then b:LockHighlight() else b:UnlockHighlight() end
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
					b:Show()
					x = x + b:GetWidth() + 8
				end
				p.moveFeed:SetText(Text(feedMoving and "setup.lock" or "setup.feed.move"))
				p.moveFeed:ClearAllPoints()
				p.moveFeed:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 8, -y)
				p.moveFeed:Show()
				y = y + 22 + GAP
			end
		end
	end

	-- The buttons.
	y = y + GAP
	if n == FIRST then
		SetButton(p.left1, "setup.skip", function() Finish() end)
		SetButton(p.left2, nil)
		SetButton(p.main, "setup.start", function() Go(n + 1) end)
	elseif n == LAST then
		SetButton(p.left1, "setup.back", function() Go(n - 1) end)
		SetButton(p.left2, "setup.options", function()
			Finish()
			ns.OpenOptions()
		end)
		SetButton(p.main, "setup.done", function() Finish() end)
	else
		SetButton(p.left1, "setup.back", function() Go(n - 1) end)
		SetButton(p.left2, "setup.skip", function() Finish() end)
		SetButton(p.main, "setup.next", function() Go(n + 1) end)
	end
	p.left1:ClearAllPoints()
	p.left1:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	p.left2:ClearAllPoints()
	p.left2:SetPoint("LEFT", p.left1, "RIGHT", 8, 0)
	p.main:ClearAllPoints()
	p.main:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
	frame:SetHeight(y + 22 + PAD)
end

-- Leaving a page by any route locks the HUD and the feed (Move the HUD,
-- Move the feed), and takes the samples away: the feed step shows the
-- feed's, step 1 the sample target.
function Go(n)
	Lock()
	Samples(false)
	SampleTarget(false)
	page = math.max(FIRST, math.min(LAST, n))
	if page == FEED_PAGE then Samples(true) end
	if page == HUD_PAGE then SampleTarget(true) end
	ns.HUDini:UpdateVisibility()
	Paint()
end

-- The one way setup closes. Safe to call twice.
function Finish()
	if not isOpen then return end
	isOpen, hiddenForFight, wantOpen = false, false, false
	ns.setupOpen = false
	local db = DB()
	db.welcomeSeen = true
	Lock()
	Samples(false)
	SampleTarget(false)
	if frame and frame:IsShown() then frame:Hide() end
	ns.HUDini:UpdateVisibility()
end

local function Show()
	if not frame then Build() end
	ns.setupOpen = true
	if page == FEED_PAGE then Samples(true) end
	if page == HUD_PAGE then SampleTarget(true) end
	Paint()
	-- Escape left the keys with setup; give them back to the game.
	if not InCombatLockdown() then frame:SetPropagateKeyboardInput(true) end
	frame:Show()
	ns.HUDini:UpdateVisibility()
end

-- Open setup on page 1. In a fight it waits for the fight's end; quiet is
-- for the login, which says nothing (TICK-0005).
local function Open(quiet)
	if isOpen and not hiddenForFight then return end
	if ns.InCombat() then
		wantOpen = true
		if not quiet then ns.Say(Text("setup.inCombat")) end
		return
	end
	-- An open options panel stays open (a Blizzard setting changed there
	-- and not applied yet is kept): setup draws over it, at DIALOG.
	secondRun = DB().welcomeSeen == true
	isOpen, hiddenForFight, wantOpen = true, false, false
	page = FIRST
	TakeOwn()
	Show()
end

-- /hud setup, and Options > HUDini > Run setup.
function ns.OpenSetup()
	Open(false)
end

--------------------------------------------------------------------------------
-- Login and fights
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		-- Only the first loading screen of the session.
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		if DB().welcomeSeen == true then return end
		C_Timer.After(LOGIN_DELAY, function()
			if DB().welcomeSeen ~= true then Open(true) end
		end)

	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Before combat lockdown starts: hide, lock, and come back after.
		if isOpen and not hiddenForFight then
			hiddenForFight = true
			ns.setupOpen = false
			if frame then frame:Hide() end
			Lock()
			Samples(false)
			SampleTarget(false)
			ns.HUDini:UpdateVisibility()
		end

	elseif event == "PLAYER_REGEN_ENABLED" then
		if isOpen and hiddenForFight then
			hiddenForFight = false
			Show()
		elseif wantOpen then
			Open(true)
		end
	end
end)
