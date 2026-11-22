--[[--------------------------------------------------------------------------
	HUDini - Setup

	HUDini setup (D-007, TICK-0042): page 1
	says what HUDini is and asks the flair level, six steps set up the HUD
	and the feed (TICK-0096: what the HUD shows, hide when idle, size and
	place, the feed, the game's own frames, a quieter screen), step 7 gives
	the alerts for your class (TICK-0180, D-047), and page 9 says what is
	on. A class with nothing for step 7 skips it, and has six steps. Every pick writes its keys at once and the HUD under
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
local FIRST, LAST = 1, 9          -- page 1, steps 1-7 are pages 2-8, page 9
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
local HUD_PAGE, SIZE_PAGE, FEED_PAGE, CLASS_PAGE = 2, 4, 5, 8
-- Step 7's small boxes (TICK-0180): two columns, 26 px tall, 4 px apart.
local MINI_W, MINI_H, MINI_GAP = (INNER - 10) / 2, 26, 4

ns.setupOpen = false

local frame, parts
local page = FIRST
local isOpen = false        -- open, or hidden for a fight and coming back
local hiddenForFight = false
local wantOpen = false      -- asked for in a fight: open when it ends
local secondRun = false     -- setup had closed before this run opened
local own = {}              -- the values at open, for "Keep your own"
local feedMoving = false    -- Move the feed: the feed alone is unlocked
local lastSound             -- step 7: the buff sound a check puts back

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
	-- Step 7, the alerts for your class (TICK-0180): small boxes from the
	-- class file in place of the choices, then the alerts already on. Its
	-- texts name the class (classArg). Go skips it when it has nothing.
	[CLASS_PAGE] = {
		texts = "setup.class",
		intro = "setup.class.intro",
		classArg = true,
		rows = function() return {} end,
		minis = function() return ns.SetupClassBoxes() end,
		onLines = true,
		choices = function() return {} end,
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
-- Step 7: the alerts for your class (TICK-0180). Page 9: your picks, and
-- the bars HUDini does not read (page 9's texts keep their setup.p7.* keys)
--------------------------------------------------------------------------------

-- The alert keys in the order step 7's "Already on" lists them, with the
-- row that turns each one on.
local ALERTS = {
	{ key = "interrupt", row = "glowOnKickable", text = "setup.class.interrupt" },
	{ key = "dispel",    row = "warnDispel",     text = "setup.class.dispel" },
	{ key = "purge",     row = "showPurgeable",  text = "setup.class.purge" },
	{ key = "keepUp",    row = "warnKeepUp",     text = "setup.class.keepUp" },
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

-- Step 7's "Already on" block: "Already on:" and the lines, then "More
-- start as you learn their spells." when the class file names an alert
-- spell you do not know yet. nil when there is nothing to say.
local function OnBlock()
	local lines, unknown = ns.SetupAlertLines()
	local out = {}
	if #lines > 0 then
		out[1] = Text("setup.class.on")
		for _, line in ipairs(lines) do out[#out + 1] = line end
	end
	if unknown then out[#out + 1] = Text("setup.class.more") end
	return #out > 0 and table.concat(out, "\n") or nil
end

-- The Options row of a spell's cooldown, to repaint after a bell click.
-- Options.lua names it by the spell's letters; a name that clashes gets
-- another name there, which ns.CooldownSettingName gives when it exists.
local function CooldownRow(spell)
	if ns.CooldownSettingName then return ns.CooldownSettingName(spell) end
	return "class_cooldown_" .. (spell:gsub("[^%w]", ""))
end

-- A small box: label, note() (gray, after the label; nil for none),
-- checked(), enabled(), click() (write and apply one pick) and rows (the
-- Options rows to repaint). A gray box keeps its check and takes no click.
-- A bell box is only for a spell you know (TICK-0201), so it is never gray.
local function BellBox(name)
	return {
		spell = name,
		label = Text("setup.class.bell", name),
		checked = function() return ns.GetReadyAlert(name) end,
		enabled = function() return true end,
		-- The bell only: the timer bar part stays as it is.
		click = function() ns.SetReadyAlert(name, not ns.GetReadyAlert(name)) end,
		rows = { CooldownRow(name) },
	}
end

-- Sound when a buff is missing: gray as its Options row is, with no note.
-- A check puts back the sound picked before (at open, or before an
-- uncheck), else the default; an uncheck sets Off.
local function SoundBox()
	return {
		isSound = true,
		label = Text("opt.class.keepUpSound"),
		checked = function() return ns.GetKeepUpSoundChoice() ~= "off" end,
		enabled = function()
			local db = DB()
			return db.showHealth and (db.warnOwnBuff or db.warnKeepUp) and true or false
		end,
		click = function()
			local choice = ns.GetKeepUpSoundChoice()
			if choice ~= "off" then
				lastSound = choice
				ns.SetKeepUpSound("off")
			else
				ns.SetKeepUpSound(lastSound or ns.MISSING_SOUND_DEFAULT)
			end
		end,
		rows = { "class_keepUpSound" },
	}
end

-- A missing item (TICK-0182): only for a row whose spell you know. The label
-- names the item as the game does; an item the game has not loaded yet
-- takes its spell's name until it has (Alerts.lua asks at login). Gray
-- without the health bar, as the icon sits by it.
local function ItemBox(row)
	local spell = row.make or (type(row.needs) == "table" and row.needs[1]) or row.needs
	local name = ns.MissingItemName and ns.MissingItemName(row) or tostring(spell)
	return {
		isItem = true,
		item = name,
		label = Text("setup.class.item", name),
		checked = function() return ns.GetMissingItem(row.key) end,
		enabled = function() return DB().showHealth and true or false end,
		click = function() ns.SetMissingItem(row.key, not ns.GetMissingItem(row.key)) end,
		rows = { "class_item_" .. row.key }, -- locale: skip a setting name
	}
end

-- At most this many bell boxes; the other spells are in Options.
local MAX_BELLS = 4

-- The class file's spell names in a list field, once each, in order.
local function Names(key)
	local out, seen, list = {}, {}, ns.ClassDefault(key)
	if type(list) ~= "table" then return out, seen end
	for _, name in ipairs(list) do
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	return out, seen
end

-- Step 7's boxes, in order: up to four bells, then the buff sound when the
-- class file has keepUp or starts the sound on (keepUpSoundOn: a Priest has
-- no keepUp, and its sound is for a tracked buff), then a missing item for
-- each row whose spell you know (TICK-0182). A bell is only for a known
-- spell of the class file's readyAlert (TICK-0201): those in readyAlertOn
-- first, then the others, each part in readyAlert order. A field the class
-- file does not have gives no box.
function ns.SetupClassBoxes()
	local list = {}
	local spells = Names("readyAlert")
	local _, startsOn = Names("readyAlertOn")
	local known = {}
	for _, name in ipairs(spells) do
		if ns.KnownSpell(name) then known[#known + 1] = name end
	end
	for _, first in ipairs({ true, false }) do
		for _, name in ipairs(known) do
			if (startsOn[name] == true) == first and #list < MAX_BELLS then list[#list + 1] = BellBox(name) end
		end
	end
	if ns.ClassDefault("keepUp") ~= nil or ns.ClassDefault("keepUpSoundOn") == true then
		list[#list + 1] = SoundBox()
	end
	for _, row in ipairs(ns.MissingItemRows()) do
		if ns.MissingItemKnown and ns.MissingItemKnown(row) then list[#list + 1] = ItemBox(row) end
	end
	return list
end

-- Step 7 shows when it has a box or a line.
local function HasClassPage()
	return #ns.SetupClassBoxes() > 0 or OnBlock() ~= nil
end

-- The step count: 7 with step 7, else 6.
local function StepCount()
	return HasClassPage() and LAST - 2 or LAST - 3
end

-- Page 9's picks: "Your Mage alerts:", one line for each kind of box step
-- 7 showed, then the /hud test line. nil without step 7. Step 7 with only
-- its "Already on" lines gives the /hud test line alone: it is a whole
-- sentence, and a heading with no line under it reads wrong.
local function ClassPicks()
	if not HasClassPage() then return nil end
	local out, bells, items, hasBell, hasSound, hasItem = {}, {}, {}, false, false, false
	for _, box in ipairs(ns.SetupClassBoxes()) do
		if box.isSound then
			hasSound = true
		elseif box.isItem then
			hasItem = true
			if box.checked() then items[#items + 1] = box.item end
		else
			hasBell = true
			if box.checked() then bells[#bells + 1] = box.spell end
		end
	end
	if hasBell or hasSound or hasItem then out[1] = Text("setup.p7.classPicks", (UnitClass("player"))) end
	if hasBell then
		out[#out + 1] = #bells > 0 and Text("setup.p7.bells", table.concat(bells, ", ")) or Text("setup.p7.noBells")
	end
	if hasSound then
		local choice = ns.GetKeepUpSoundChoice()
		out[#out + 1] = Text("setup.p7.sound", choice == "off" and Text("opt.sound.off") or Text("sound." .. choice))
	end
	-- No line while no missing item is checked (the design's rule).
	if #items > 0 then out[#out + 1] = Text("setup.p7.items", table.concat(items, ", ")) end
	out[#out + 1] = Text("setup.p7.test")
	return table.concat(out, "\n")
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

-- Step 7's small box (TICK-0180): the game's check box, the label, and a
-- gray note after it; no line under it. A click runs the box's one pick,
-- repaints its Options rows and the page.
local function MiniBox(parent)
	local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
	r:SetSize(MINI_W, MINI_H)
	r:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	r:SetBackdropColor(0, 0, 0, 0.4)
	r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
	r.check:SetSize(22, 22)
	r.check:SetPoint("LEFT", 3, 0)
	r.name = Label(r, "GameFontNormal")
	r.name:SetWordWrap(false)
	r.name:SetPoint("LEFT", 28, 0)
	r.note = Label(r, "GameFontDisableSmall")
	r.note:SetWordWrap(false)
	r.note:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
	local function Click()
		local box = r.box
		if box and box.enabled() then
			box.click()
			RepaintOptions(box.rows)
		end
		Paint()
	end
	r:SetScript("OnClick", Click)
	r.check:SetScript("OnClick", Click)
	return r
end

local function FillMini(r, box)
	r.box = box
	r.name:SetText(box.label)
	local on, enabled = box.checked() and true or false, box.enabled()
	-- A gray box keeps its check, so the player sees what starts on.
	r.check:SetChecked(on)
	r.check:SetEnabled(enabled)
	r:SetEnabled(enabled)
	r.name:SetFontObject(enabled and "GameFontNormal" or "GameFontDisable")
	local note = not enabled and box.note and box.note() or nil
	r.note:SetText(note or "")
	r.note:SetShown(note ~= nil)
	local c = (on and enabled) and ROW_PICKED or ROW_BORDER
	r:SetBackdropBorderColor(c[1], c[2], c[3])
	r:Show()
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

	local p = { rows = {}, boxes = {}, minis = {} }
	p.icon = f:CreateTexture(nil, "ARTWORK")
	p.icon:SetTexture(ICON)
	p.icon:SetSize(40, 40)
	p.icon:SetPoint("TOPLEFT", PAD, -PAD)
	p.title = Label(f, "GameFontNormalLarge")
	p.title:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 10, -2)
	-- The version on the title line (TICK-0113): the step counter owns the
	-- line under the title on steps 1-6 only, so this one holds still.
	p.version = Label(f, "GameFontDisable")
	p.version:SetPoint("BOTTOMLEFT", p.title, "BOTTOMRIGHT", 8, 0)
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

	p.intro    = Label(f, "GameFontHighlight")     -- steps 1-7
	p.top      = Label(f, "GameFontHighlight")     -- page 1's pitch, or the second-run line
	p.question = Label(f, "GameFontNormal")
	p.body     = Label(f, "GameFontHighlight")     -- page 9
	p.alerts   = Label(f, "GameFontHighlight")     -- step 7's Already on, page 9's picks
	p.bars     = Label(f, "GameFontHighlight")     -- page 9
	p.under    = Label(f, "GameFontHighlight")
	p.lesson   = Label(f, "GameFontHighlight")     -- step 6
	p.gryphons = Label(f, "GameFontHighlight")     -- step 6
	p.steps    = Label(f, "GameFontHighlight")     -- page 1
	p.changes  = Label(f, "GameFontHighlightSmall")
	p.last     = Label(f, "GameFontHighlight")     -- page 9
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
	-- The same words as the About window's version line.
	p.version:SetText(ns.VERSION ~= "unknown" and Text("about.version", ns.VERSION) or Text("about.versionUnknown"))
	local isStep = n > FIRST and n < LAST
	p.counter:SetText(isStep and Text("setup.step", n - 1, StepCount()) or "")
	-- Step 7's texts name the class.
	local class = step and step.classArg and (UnitClass("player")) or nil
	local function T(key)
		if class then return Text(key, class) end
		return Text(key)
	end

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
	for _, r in ipairs(p.minis) do r:Hide() end
	p.moveHud:Hide()
	p.sizeLabel:Hide()
	for _, b in ipairs(p.sizes) do b:Hide() end
	p.moveFeed:Hide()

	local rowsAt
	if step then
		-- A step says what the part is before it asks (TICK-0076).
		if step.intro then Add(p.intro, T(step.intro)) end
		-- A second run says what Next does now, not what HUDini is (TICK-0083).
		if n == FIRST then Add(p.top, secondRun and Text("setup.p1.again") or Text("setup.p1.pitch")) end
		Add(p.question, T(step.question or step.texts .. ".question"))
		rowsAt = #stack
		-- Step 7: the alerts already on, under its boxes.
		local on = step.onLines and OnBlock()
		if on then Add(p.alerts, on) end
		if n == FIRST then
			Add(p.under, Text("setup.p1.under"))
			Add(p.steps, Text("setup.p1.steps"))
		else
			Add(p.under, T(step.under or step.texts .. ".under"))
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
		-- Step 7's picks, then /hud test (TICK-0096); none without step 7.
		local picks = ClassPicks()
		if picks then Add(p.alerts, picks) end
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
			-- Step 7's small boxes: left to right, then down.
			local minis = step.minis and step.minis() or {}
			for j, box in ipairs(minis) do
				local r = p.minis[j] or MiniBox(frame)
				p.minis[j] = r
				FillMini(r, box)
				local col = (j - 1) % 2
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * (MINI_W + 10), -y)
				if col == 1 or j == #minis then y = y + MINI_H + MINI_GAP end
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
	local back = n < page
	page = math.max(FIRST, math.min(LAST, n))
	-- A class with nothing for step 7 goes past it, either way.
	if page == CLASS_PAGE and not HasClassPage() then page = back and page - 1 or page + 1 end
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
	-- Step 7's sound box puts back the sound on at open.
	local sound = ns.GetKeepUpSoundChoice()
	if sound ~= "off" then lastSound = sound end
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
