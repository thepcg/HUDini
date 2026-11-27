-- HUDini setup (D-007, TICK-0042): when it
-- shows, what each page writes, a second run, every exit, fights, and
-- step 7 (the page for your class) and page 9's picks and bars notice. The window itself (how it looks,
-- Enter and Escape in the game) is for the test sitting.

-- Test class profiles, not the live class files (classes_fixture.lua).
local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

-- A new client whose class files are the test profiles.
local function NewWorld() return Classes.Use(H.world()) end

-- Everything printed from one slash command.
local function Said(w, line)
	local from = #w.printed
	w:slash(line)
	local out = {}
	for i = from + 1, #w.printed do out[#out + 1] = w.printed[i] end
	return table.concat(out, "\n")
end

local function Win(w) return w.env.HUDiniSetup end
local function Parts(w) return Win(w).parts end
local function IsOpen(w) return Win(w) ~= nil and Win(w):IsShown() end

-- The shown choice rows: { name, picked } in order.
local function Rows(w)
	local out = {}
	for _, r in ipairs(Parts(w).rows) do
		if r:IsShown() then out[#out + 1] = { name = r.name:GetText(), picked = r.dot:GetChecked(), row = r } end
	end
	return out
end

local function Picked(w)
	for _, r in ipairs(Rows(w)) do
		if r.picked then return r.name end
	end
end

-- Click the row whose name is this.
local function Pick(w, name)
	for _, r in ipairs(Rows(w)) do
		if r.name == name then
			w:Run(r.row, "OnClick")
			return
		end
	end
	error("no row " .. name)
end

-- Step 1's shown check boxes: { name, checked, enabled, row } in order.
local function Boxes(w)
	local out = {}
	for _, r in ipairs(Parts(w).boxes) do
		if r:IsShown() then
			out[#out + 1] = { name = r.name:GetText(), checked = r.check:GetChecked(),
				enabled = r.check:IsEnabled(), row = r }
		end
	end
	return out
end

-- The names of the checked boxes, joined: "Experience bar,Target power".
local function Checked(w)
	local out = {}
	for _, b in ipairs(Boxes(w)) do
		if b.checked then out[#out + 1] = b.name end
	end
	return table.concat(out, ",")
end

-- Click the box whose name is this: on the row, or on its check box.
local function Tick(w, name, onCheck)
	for _, b in ipairs(Boxes(w)) do
		if b.name == name then
			w:Run(onCheck and b.row.check or b.row, "OnClick")
			return
		end
	end
	error("no box " .. name)
end

-- Whether the module of this name is on now (Modules.lua).
local function ModuleOn(ns, name)
	for _, m in ipairs(ns.ModuleReport()) do
		if m.name == name then return m.on end
	end
end

local function Press(w, which) Parts(w)[which].fn() end
local function ButtonText(w, which)
	local b = Parts(w)[which]
	return b:IsShown() and b:GetText() or nil
end
local function Next(w) Press(w, "main") end
-- Click a button that runs its own OnClick (Move the HUD, the size buttons).
local function Click(w, b) w:Run(b, "OnClick") end
local function MoveHud(w) Click(w, Parts(w).moveHud) end
local function MoveFeed(w) Click(w, Parts(w).moveFeed) end

-- The feed's sample lines that show now (FeedWatch.lua ns.FeedSamples).
local function Samples(w) return #w.ns.Feed.Keyed("sample:") end
-- The feed's blue box: shown while the feed is unlocked.
local function FeedBox(w) return w.env.HUDiniFeed.bg:IsShown() end

-- A key pressed while setup is open, as the game sends it.
local function Key(w, key) w:Run(Win(w), "OnKeyDown", key) end
local function Escape(w) Key(w, "ESCAPE") end

-- The game's row for your debuffs on the target (TargetDebuffs.lua): a
-- fake AuraContainer that takes every call. Without it, the harness
-- client has no such frame type, as a client without the row.
local function GameRow(w)
	local make = w.env.CreateFrame
	w.env.CreateFrame = function(kind, ...)
		if kind ~= "AuraContainer" then return make(kind, ...) end
		local f = make("Frame", ...)
		for _, k in ipairs({ "SetEnabled", "AddAuraGroup", "SetEditModePreviewEnabled", "SetUnit",
				"UpdateAllAuras", "SetFlowLayoutAnchorPoint", "SetFlowLayoutMaximumLineSize" }) do
			rawset(f, k, function() return true end)
		end
		return f
	end
	return w
end

-- A new install, logged in, with setup open on page 1.
local function NewOpen()
	local w = GameRow(NewWorld())
	local ns = w:loadAddon()
	w:runTimers()
	return w, ns, w.env.HUDiniDB
end

-- An account that has closed setup once.
local function Seen()
	local w = GameRow(NewWorld())
	w.env.HUDiniDB = { schema = 99, welcomeSeen = true }
	local ns = w:loadAddon()
	w:runTimers()
	return w, ns, w.env.HUDiniDB
end

local function Visible(part) return part:IsShown() and part:GetText() or nil end

-- The y offset a part is placed at: more negative is lower.
local function Y(part) return select(5, part:GetPoint()) end

-- Make these spells known: name -> id.
local function Know(w, names)
	local ids, n = {}, 9000
	for _, name in ipairs(names) do
		n = n + 1
		ids[name], ids[n] = n, name
	end
	w.env.C_Spell.GetSpellInfo = function(name) return ids[name] and { spellID = ids[name] } or nil end
	w.env.C_Spell.GetSpellName = function(id) return ids[id] end
	w.env.IsPlayerSpell = function(id) return type(ids[id]) == "string" end
end

--------------------------------------------------------------------------------
-- When it shows
--------------------------------------------------------------------------------

H.test("a new install opens setup on page 1, about 2 s after the loading screen", function()
	local w = NewWorld()
	local ns = w:loadAddon()
	H.ok(not IsOpen(w), "not at once")
	H.eq(w.env.HUDiniDB.welcomeSeen, nil, "not seen yet")
	w:runTimers()
	H.ok(IsOpen(w), "open after the delay")
	H.eq(ns.setupOpen, true)
	H.eq(Visible(Parts(w).question), w.env.HUDiniDB and ns.TEXT[0]["setup.p1.question"])
	H.eq(#w.printed, 0, "the login says nothing")
end)

H.test("setup that never closed opens again at the next login; a later loading screen does not open it", function()
	local w = NewOpen()
	H.ok(IsOpen(w))
	-- A /reload before it closes: a new session with the same table.
	local saved = w.env.HUDiniDB
	local w2 = NewWorld()
	w2.env.HUDiniDB = saved
	w2:loadAddon()
	w2:runTimers()
	H.ok(IsOpen(w2), "opens again")
	Press(w2, "left1")   -- Skip setup
	w2:fire("PLAYER_ENTERING_WORLD", false, false)
	w2:runTimers()
	H.ok(not IsOpen(w2), "a zone change does not open it")
end)

H.test("in a fight at login, setup waits for the fight's end, quietly", function()
	local w = NewWorld()
	w:loadAddon()
	w.combat = true
	w:runTimers()
	H.ok(not IsOpen(w), "not in a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.ok(IsOpen(w), "opens after it")
	H.eq(#w.printed, 0, "no chat line")
end)

H.test("/hud setup opens page 1; in a fight it says when, then opens after", function()
	local w, ns = Seen()
	H.ok(not IsOpen(w))
	w:slash("/hud setup")
	H.ok(IsOpen(w))
	H.eq(Visible(Parts(w).top), ns.TEXT[0]["setup.p1.again"], "a second run: the second-run line")
	Press(w, "left1")
	w.combat = true
	H.eq(Said(w, "/hud setup"), "|cff33ccffHUDini|r: Setup will open after combat.")
	H.ok(not IsOpen(w))
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.ok(IsOpen(w), "opens when the fight ends")
end)

H.test("/hud welcome is a quiet alias; /hud help lists setup, not welcome", function()
	local w = Seen()
	w:slash("/hud welcome")
	H.ok(IsOpen(w))
	local help = Said(w, "/hud help")
	H.ok(help:find("setup", 1, true), "setup is listed")
	H.ok(Said(w, "/hud help setup"):find("/hud setup - Run the setup guide.", 1, true), "/hud help setup")
	H.eq(help:find("welcome", 1, true), nil, "welcome is not")
end)

H.test("an open options panel stays open under setup; each pick repaints its rows", function()
	local w = Seen()
	local notified = {}
	w.env.Settings.GetSetting = function(variable)
		return { NotifyUpdate = function() notified[#notified + 1] = variable end }
	end
	local function Took()
		local out = table.concat(notified, ",")
		notified = {}
		return out
	end
	w.env.SettingsPanel:Show()
	w:slash("/hud setup")
	H.ok(IsOpen(w))
	H.ok(w.env.SettingsPanel:IsShown(), "the panel stays open")
	Pick(w, "Modest")
	H.eq(Took(), "HUDini_flair", "page 1")
	Next(w)
	Tick(w, "Experience bar")
	H.eq(Took(), "HUDini_showXP", "step 1: one box, one row")
	Tick(w, "Target power")
	H.eq(Took(), "HUDini_showTargetPower", "step 1: Target power")
	Tick(w, "Your debuffs on the target")
	H.eq(Took(), "HUDini_showTargetDebuffs", "step 1: Your debuffs on the target")
	Next(w)
	Pick(w, "Always visible")
	H.eq(Took(), "HUDini_hideWhenIdle", "step 2")
	Next(w)
	Pick(w, "Large")
	H.eq(Took(), "HUDini_scale,HUDini_locked", "step 3")
	MoveHud(w)
	H.eq(Took(), "HUDini_locked", "step 3: Move the HUD")
	Next(w)
	H.eq(Took(), "HUDini_locked", "Next locks again")
	Pick(w, "Events and hints")
	H.eq(Took(), "HUDini_showFeed,HUDini_feedQuestProgress,HUDini_feedUpgrade,HUDini_feedFontSize,HUDini_feedWidth", "step 4")
	Click(w, Parts(w).sizes[3])
	H.eq(Took(), "HUDini_feedFontSize,HUDini_feedWidth", "step 4: a size button")
	Next(w)
	Pick(w, "Hide them")
	H.eq(Took(), "HUDini_hideBlizzardTarget,HUDini_hideBlizzardCastBar,HUDini_hideBlizzardXP", "step 5")
	Next(w)
	Pick(w, "Show on mouseover")
	H.eq(Took(), "HUDini_bagBarMouseover,HUDini_menuBarMouseover", "step 6")
	w.env.SettingsPanel:Hide()
	Pick(w, "Keep them visible")
	H.eq(Took(), "", "no panel, no repaint")
end)

H.test("a loading screen, a loss of control or Alt-Z does not close setup", function()
	local w, ns, db = NewOpen()
	Next(w)
	for _, name in ipairs(w.env.UISpecialFrames) do
		H.ok(name ~= "HUDiniSetup", "the game's close-all never hides setup")
	end
	-- Its only OnHide ends a drag (TICK-0079): run it, setup stays open.
	w:Run(Win(w), "OnHide")
	H.eq(ns.setupOpen, true, "no hide is an exit")
	w:fire("PLAYER_ENTERING_WORLD", false, false)
	w:runTimers()
	H.ok(IsOpen(w), "still open after a loading screen")
	H.eq(Parts(w).counter:GetText(), "Step 1 of 7", "on the same page")
	H.eq(db.welcomeSeen, nil)
	H.eq(ns.setupOpen, true)
end)

--------------------------------------------------------------------------------
-- The HUD while setup is open
--------------------------------------------------------------------------------

H.test("while setup is open the HUD stays in view and /hud why says so", function()
	local w, ns = NewOpen()
	H.ok(ns.HUDini:ShouldShow(), "shown")
	H.ok(Said(w, "/hud why"):find(ns.TEXT[0]["why.setup"], 1, true), "why.setup")
	Press(w, "left1")
	H.eq(ns.setupOpen, false)
	H.eq(Said(w, "/hud why"):find(ns.TEXT[0]["why.setup"], 1, true), nil, "not after it closes")
end)

--------------------------------------------------------------------------------
-- Every exit
--------------------------------------------------------------------------------

H.test("Skip setup on page 1 keeps every default, locks and marks setup seen", function()
	local w, ns, db = NewOpen()
	local before = {}
	for k, v in pairs(ns.defaults) do if type(v) ~= "table" then before[k] = v end end
	H.eq(ButtonText(w, "left1"), "Finish for now")
	H.eq(ButtonText(w, "main"), "Begin")
	H.eq(ButtonText(w, "left2"), nil, "page 1 has two buttons")
	Press(w, "left1")
	H.ok(not IsOpen(w))
	H.eq(db.welcomeSeen, true)
	H.eq(db.locked, true)
	for k, v in pairs(before) do H.eq(db[k], v, k) end
end)

H.test("Start, Next seven times and Done gives the defaults: a locked HUD that hides when idle", function()
	local w, ns, db = NewOpen()
	for _ = 1, 8 do Next(w) end
	H.eq(Visible(Parts(w).question), "Ready to explore")
	H.eq(ButtonText(w, "main"), "Finish")
	Press(w, "main")
	H.ok(not IsOpen(w))
	H.eq(db.welcomeSeen, true)
	H.eq(db.locked, true)
	H.eq(db.hideWhenIdle, true)
	H.eq(db.flair, 0)
	H.eq(db.scale, 1.0)
	H.eq(db.showXP, true); H.eq(db.showTargetPower, true)
	H.eq(db.showFeed, true); H.eq(db.feedQuestProgress, false); H.eq(db.feedUpgrade, false)
	H.eq(db.feedFontSize, 14); H.eq(db.feedWidth, 420)
	H.eq(Samples(w), 0, "no sample line after Done")
	for _, k in ipairs({ "hideBlizzardTarget", "hideBlizzardCastBar", "hideBlizzardXP" }) do H.eq(db[k], false, k) end
	for _, k in ipairs({ "bagBarMouseover", "menuBarMouseover" }) do H.eq(db[k], false, k) end
	H.eq(#w.printed, 0, "no chat line on Done")
end)

H.test("Escape and the close button close setup the same way as Skip setup", function()
	local w, _, db = NewOpen()
	Next(w)
	Escape(w)
	H.eq(db.welcomeSeen, true)
	H.eq(db.locked, true)
	w:slash("/hud setup")
	Next(w)
	Tick(w, "Experience bar")
	w:Run(Parts(w).x, "OnClick")
	H.ok(not IsOpen(w), "the close button")
	H.eq(db.showXP, false, "a pick stays after a skip")
end)

H.test("page 9's Options button closes setup, then opens the options", function()
	local w, ns, db = NewOpen()
	local opened = 0
	ns.OpenOptions = function() opened = opened + 1 end
	for _ = 1, 8 do Next(w) end
	H.eq(ButtonText(w, "left2"), "Open Options")
	Press(w, "left2")
	H.ok(not IsOpen(w))
	H.eq(db.welcomeSeen, true)
	H.eq(opened, 1)
end)

--------------------------------------------------------------------------------
-- What the pages write
--------------------------------------------------------------------------------

H.test("page 1: each flair pick writes the level and repaints the pitch and the line under the choice; the steps line has one text", function()
	local w, ns, db = NewOpen()
	local T = ns.TEXT
	H.eq(Picked(w), "Light")
	Pick(w, "Full")
	H.eq(db.flair, 2)
	H.eq(Picked(w), "Full")
	H.eq(Visible(Parts(w).top), T[2]["setup.p1.pitch"])
	H.eq(Visible(Parts(w).under), T[2]["setup.p1.under"])
	-- The copy of D-029 (TICK-0134) gives the steps line a text at each level.
	H.eq(Visible(Parts(w).steps), T[2]["setup.p1.steps"], "the steps line follows the level")
	Pick(w, "Modest")
	H.eq(Visible(Parts(w).top), T[1]["setup.p1.pitch"])
	H.eq(Visible(Parts(w).under), T[1]["setup.p1.under"])
	Pick(w, "Light")
	H.eq(Visible(Parts(w).under), T[0]["setup.p1.under"])
	Pick(w, "Modest")
	Next(w)
	H.eq(Visible(Parts(w).under), T[1]["setup.hud.extras.under"], "later pages read the level")
	H.eq(Visible(Parts(w).question), T[0]["setup.hud.extras.question"], "one text for the question")
end)

H.test("page 1: each flair choice shows the Flair row's own tip, as the options do", function()
	local w, ns = NewOpen()
	local rows = Rows(w)
	H.eq(#rows, 3)
	for level = 0, 2 do
		local tip = ns.TEXT[0]["flair." .. level .. ".tip"]
		H.ok(tip, "flair." .. level .. ".tip")
		H.eq(Visible(rows[level + 1].row.line), tip, "level " .. level)
	end
end)

H.test("step 1: each box writes only its own key; step 2 hide when idle; step 3 the scale", function()
	local w, ns, db = NewOpen()
	Next(w)
	H.eq(Parts(w).counter:GetText(), "Step 1 of 7")
	H.eq(#Rows(w), 0, "no choice rows")
	H.eq(Checked(w), "Experience bar,Target power,Your debuffs on the target", "a new install has all three")
	local KEYS = { "showXP", "showTargetPower", "showTargetDebuffs" }
	local function Snapshot()
		local out = {}
		for k, v in pairs(db) do out[k] = v end
		return out
	end
	for i, name in ipairs({ "Experience bar", "Target power", "Your debuffs on the target" }) do
		local before = Snapshot()
		-- The row for two of them, the check box itself for Target power.
		Tick(w, name, i == 2)
		for k, v in pairs(before) do
			if k == KEYS[i] then
				H.eq(db[k], not v, name .. " turns its key over")
			else
				H.eq(db[k], v, name .. " leaves " .. k)
			end
		end
		for k in pairs(db) do H.ok(before[k] ~= nil, name .. " adds no key " .. k) end
	end
	H.eq(Checked(w), "", "each box shows its key")
	H.eq(ModuleOn(ns, "targetdebuffs"), false, "the row's module follows at once")
	H.eq(ModuleOn(ns, "xp"), false, "the XP bar's module follows at once")
	Tick(w, "Target power")
	H.eq(db.showTargetPower, true); H.eq(db.showXP, false)
	Tick(w, "Experience bar"); Tick(w, "Your debuffs on the target")
	H.eq(Checked(w), "Experience bar,Target power,Your debuffs on the target")
	H.eq(ModuleOn(ns, "targetdebuffs"), true)
	Next(w)
	H.eq(Parts(w).counter:GetText(), "Step 2 of 7")
	Pick(w, "Always visible")
	H.eq(db.hideWhenIdle, false)
	Next(w)
	Pick(w, "Small")
	H.eq(db.scale, 0.85)
	Pick(w, "Large")
	H.eq(db.scale, 1.2)
	H.eq(#Rows(w), 3, "no Keep your own on a first run")
	Next(w); Next(w); Next(w); Next(w); Next(w)
	H.eq(Visible(Parts(w).body), ns.TEXT[0]["setup.p7.bodyAlways"], "page 9 follows step 2")
end)

H.test("step 1: without the game's debuff row, its box and its name go", function()
	local w = NewWorld()                  -- no AuraContainer on this client
	local ns = w:loadAddon()
	w:runTimers()
	H.eq(ns.TargetDebuffRow(), false, "the module found no row")
	Next(w)
	H.eq(Checked(w), "Experience bar,Target power", "two boxes")
	H.eq(Visible(Parts(w).changes), ns.TEXT[0]["setup.hud.extras.changes.noDebuffs"])
	H.eq(Visible(Parts(w).under), ns.TEXT[0]["setup.hud.extras.under"], "the other texts stay")
	local w2 = NewOpen()
	Next(w2)
	H.eq(Visible(Parts(w2).changes), w2.ns.TEXT[0]["setup.hud.extras.changes"], "with the row: its name")
end)

H.test("step 1: with Target health bar off, Target power and the debuff row are gray and take no click", function()
	local w, ns, db = Seen()
	db.showTargetHealth = false
	w:slash("/hud setup")
	Next(w)
	local boxes = Boxes(w)
	H.eq(#boxes, 3)
	H.eq(boxes[1].enabled, true, "Experience bar")
	H.eq(boxes[2].enabled, false, "Target power")
	H.eq(boxes[3].enabled, false, "Your debuffs on the target")
	H.eq(boxes[2].row.name:GetFontObject(), "GameFontDisable", "a gray name")
	H.eq(Visible(boxes[2].row.line), ns.TEXT[0]["setup.hud.targetPower.line"], "its line stays")
	Tick(w, "Target power")
	Tick(w, "Your debuffs on the target", true)
	H.eq(db.showTargetPower, true, "no click"); H.eq(db.showTargetDebuffs, true, "no click")
	H.eq(Checked(w), "Experience bar,Target power,Your debuffs on the target", "the box still shows its key")
end)

H.test("step 1: the lines under the boxes follow the flair level", function()
	local w, ns, db = NewOpen()
	local T = ns.TEXT
	Next(w)
	for level = 0, 2 do
		db.flair = level
		Press(w, "left1"); Next(w)
		local boxes = Boxes(w)
		for i, key in ipairs({ "setup.hud.xp", "setup.hud.targetPower", "setup.hud.debuffs" }) do
			H.eq(boxes[i].name, T[0][key], key .. ": one text for the label")
			H.eq(Visible(boxes[i].row.line), T[level][key .. ".line"] or T[0][key .. ".line"],
				key .. ".line at level " .. level)
		end
	end
end)

H.test("step 1: on a new install, Next and Skip setup write nothing new", function()
	local w, _, db = NewOpen()
	local before = {}
	for k, v in pairs(db) do before[k] = v end
	Next(w); Next(w)
	H.eq(Parts(w).counter:GetText(), "Step 2 of 7")
	for k, v in pairs(before) do
		if k ~= "locked" then H.eq(db[k], v, "Next leaves " .. k) end
	end
	Press(w, "left1")
	Press(w, "left2")                    -- Skip setup
	H.ok(not IsOpen(w))
	H.eq(db.showXP, true); H.eq(db.showTargetPower, true); H.eq(db.showTargetDebuffs, true)
end)

-- The sample target (TestMode.lua): its name on the target bar, with no
-- real target. The bar writes no name without a target.
local function SampleName(w)
	local bar = w.ns.GetBar("targethealth")
	return bar:IsShown() and bar.name:GetText() == w.ns.TEXT[0]["test.sampleName"]
end

H.test("step 1 shows the sample target alone; every way out of step 1 ends it", function()
	local w, ns, db = NewOpen()
	H.eq(SampleName(w), false, "page 1: none")
	Next(w)
	H.eq(SampleName(w), true, "step 1: the sample target")
	H.eq(ns.testing, false, "not test mode")
	H.eq(Samples(w), 0, "no feed line")
	H.eq(ns.casts.targetcast.holder:IsShown(), false, "no cast sample")
	local power = ns.GetBar("targetpower")
	H.eq(power:IsShown(), true, "its power shows")
	Tick(w, "Target power")
	H.eq(power:IsShown(), false, "a Target power click shows at once")
	Tick(w, "Target power")
	H.eq(power:IsShown(), true)
	-- Next, then Back.
	Next(w)
	H.eq(SampleName(w), false, "Next ends it")
	Press(w, "left1")
	H.eq(SampleName(w), true, "Back to step 1 starts it")
	Press(w, "left1")
	H.eq(SampleName(w), false, "Back ends it")
	Next(w)
	-- A fight ends it, and it comes back with setup.
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(SampleName(w), false, "a fight ends it")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.ok(IsOpen(w), "setup comes back")
	H.eq(SampleName(w), true, "back on step 1")
	-- Skip setup ends it.
	Press(w, "left2")
	H.eq(SampleName(w), false, "Skip setup ends it")
	-- The close button and Escape.
	w:slash("/hud setup"); Next(w)
	H.eq(SampleName(w), true)
	w:Run(Parts(w).x, "OnClick")
	H.eq(SampleName(w), false, "the close button ends it")
	w:slash("/hud setup"); Next(w)
	Escape(w)
	H.eq(SampleName(w), false, "Escape ends it")
	H.eq(db.showTargetPower, true)
end)

H.test("the sample target never starts in a fight", function()
	local w, ns = NewOpen()
	w.combat = true
	ns.SampleTargetOnly(true)
	H.eq(SampleName(w), false, "in a fight: no sample")
	w.combat = false
	ns.SampleTargetOnly(true)
	H.eq(SampleName(w), true, "out of the fight: the sample")
	ns.SampleTargetOnly(false)
end)

H.test("step 1: a real target wins over the sample, and ending the sample leaves test mode's", function()
	local w, ns = NewOpen()
	Next(w)
	w.hasTarget = true
	w.env.UnitName = function(unit) return unit == "target" and "Kobold" or "Tester" end
	ns.RefreshBars()
	H.ok(ns.GetBar("targethealth").name:GetText() ~= ns.TEXT[0]["test.sampleName"], "a real target: its own bar")
	w.hasTarget = false
	ns.RefreshBars()
	H.eq(SampleName(w), true, "no target: the sample again")
	ns.FeedTest = function() end         -- the harness has no item API for it
	w:slash("/hud test")
	H.eq(ns.testing, true)
	Next(w)
	H.eq(SampleName(w), true, "test mode keeps its own sample")
	w:slash("/hud test")
	H.eq(SampleName(w), false, "test mode off: none")
end)

H.test("step 3: Move the HUD unlocks and says Lock; a second click, Next or Back locks again", function()
	local w, _, db = NewOpen()
	for _ = 1, 3 do Next(w) end
	local p = Parts(w)
	H.eq(p.counter:GetText(), "Step 3 of 7")
	H.eq(#Rows(w), 3, "the three sizes, no place choice")
	H.eq(ButtonText(w, "moveHud"), "Move the HUD")
	H.ok(Y(p.moveHud) < Y(Rows(w)[3].row) and Y(p.moveHud) > Y(p.under), "on its own row under the choices")
	MoveHud(w)
	H.eq(db.locked, false)
	H.eq(ButtonText(w, "moveHud"), "Lock in place", "the button says Lock")
	MoveHud(w)
	H.eq(db.locked, true)
	H.eq(ButtonText(w, "moveHud"), "Move the HUD")
	MoveHud(w)
	Next(w)
	H.eq(db.locked, true, "Next locks")
	H.eq(ButtonText(w, "moveHud"), nil, "only step 3 has it")
	Press(w, "left1")
	MoveHud(w)
	Press(w, "left1")
	H.eq(db.locked, true, "Back locks")
end)

H.test("step 5 writes the three Blizzard frame keys together", function()
	local w, _, db = NewOpen()
	for _ = 1, 5 do Next(w) end
	H.eq(Picked(w), "Keep them")
	Pick(w, "Hide them")
	for _, k in ipairs({ "hideBlizzardTarget", "hideBlizzardCastBar", "hideBlizzardXP" }) do H.eq(db[k], true, k) end
	Pick(w, "Keep them")
	for _, k in ipairs({ "hideBlizzardTarget", "hideBlizzardCastBar", "hideBlizzardXP" }) do H.eq(db[k], false, k) end
end)

H.test("every choice with a default is tagged (default), one per page, and a new install has it picked", function()
	local w = NewOpen()
	-- Name each step's default (pages 2-7).
	local named = {
		[3] = "When needed",
		[4] = "Medium", [5] = "Events", [6] = "Keep them", [7] = "Keep them visible",
	}
	for page = 1, 7 do
		local tagged = {}
		for _, r in ipairs(Parts(w).rows) do
			if r:IsShown() and r.tag:GetText() == "(default)" then tagged[#tagged + 1] = r.name:GetText() end
		end
		if page == 2 then
			-- Step 1's check boxes have no (default) tag (TICK-0115).
			H.eq(#tagged, 0, "page 2: no tag")
		else
			H.eq(#tagged, 1, "page " .. page)
			H.eq(tagged[1], Picked(w), "page " .. page .. ": the tagged row is the one a new install has")
			if named[page] then H.eq(tagged[1], named[page], "page " .. page) end
		end
		Next(w)
	end
end)

--------------------------------------------------------------------------------
-- A second run
--------------------------------------------------------------------------------

H.test("a second run starts at the current values, and Next keeps them", function()
	local w, ns, db = Seen()
	db.flair, db.hideWhenIdle, db.scale = 1, false, 1.2
	db.showXP, db.showTargetPower = false, false
	db.showFeed, db.feedQuestProgress, db.feedUpgrade = true, true, true
	db.hideBlizzardTarget, db.hideBlizzardCastBar, db.hideBlizzardXP = true, true, true
	db.bagBarMouseover, db.menuBarMouseover = true, true
	w:slash("/hud setup")
	H.eq(Picked(w), "Modest"); Next(w)
	H.eq(Checked(w), "Your debuffs on the target", "step 1: each box as it is now"); Next(w)
	H.eq(Picked(w), "Always visible"); Next(w)
	H.eq(Picked(w), "Large"); Next(w)
	H.eq(Picked(w), "Events and hints"); Next(w)
	H.eq(Picked(w), "Hide them"); Next(w)
	H.eq(Picked(w), "Show on mouseover"); Next(w)
	Press(w, "main")
	H.eq(db.flair, 1); H.eq(db.hideWhenIdle, false); H.eq(db.scale, 1.2)
	H.eq(db.showXP, false); H.eq(db.showTargetPower, false); H.eq(db.showTargetDebuffs, true)
	H.eq(db.showFeed, true); H.eq(db.feedQuestProgress, true); H.eq(db.feedUpgrade, true)
	H.eq(db.hideBlizzardXP, true)
	H.eq(db.bagBarMouseover, true); H.eq(db.menuBarMouseover, true)
end)

H.test("values no choice matches get Keep your own, which puts them back", function()
	local w, ns, db = Seen()
	db.scale = 1.1
	db.showXP, db.showTargetPower = true, false                          -- step 1: a mix
	db.showFeed, db.feedQuestProgress, db.feedUpgrade = false, true, false -- step 4: off, with a hint on
	db.hideBlizzardTarget, db.hideBlizzardCastBar, db.hideBlizzardXP = true, false, true
	db.bagBarMouseover, db.menuBarMouseover = true, false
	w:slash("/hud setup")
	Next(w)
	-- Step 1 has check boxes: a mix needs no name (TICK-0115).
	H.eq(#Rows(w), 0, "step 1: no Keep your own")
	H.eq(Checked(w), "Experience bar,Your debuffs on the target", "step 1: the mix as it is")
	Next(w)
	H.eq(db.showXP, true, "Next keeps it"); H.eq(db.showTargetPower, false, "Next keeps it")
	Next(w)
	H.eq(Picked(w), "Keep my current choice (110%)", "step 3 names the value")
	Pick(w, "Medium")
	H.eq(db.scale, 1.0)
	Pick(w, "Keep my current choice (110%)")
	H.eq(db.scale, 1.1)
	Next(w)
	H.eq(Picked(w), "Keep my current choices", "step 4: the feed off with a hint on")
	H.eq(#Rows(w), 4)
	Pick(w, "Events")
	H.eq(db.showFeed, true); H.eq(db.feedQuestProgress, false)
	H.eq(Samples(w), 5, "the feed on: its samples")
	Pick(w, "Keep my current choices")
	H.eq(db.showFeed, false, "put back"); H.eq(db.feedQuestProgress, true, "put back")
	H.eq(Samples(w), 0, "the feed off: no samples")
	Next(w)
	H.eq(Picked(w), "Keep my current choices", "step 5: a mix")
	Pick(w, "Hide them")
	Pick(w, "Keep my current choices")
	H.eq(db.hideBlizzardCastBar, false); H.eq(db.hideBlizzardXP, true)
	Next(w)
	H.eq(Picked(w), "Keep my current choices", "step 6: a mix")
	H.eq(#Rows(w), 3)
	Pick(w, "Show on mouseover")
	H.eq(db.bagBarMouseover, true); H.eq(db.menuBarMouseover, true)
	Pick(w, "Keep my current choices")
	H.eq(db.bagBarMouseover, true); H.eq(db.menuBarMouseover, false)
	Pick(w, "Keep them visible")
	H.eq(db.bagBarMouseover, false)
end)

H.test("a scale near a choice matches it", function()
	local w, _, db = Seen()
	db.scale = 0.8500001
	w:slash("/hud setup")
	for _ = 1, 3 do Next(w) end
	H.eq(Picked(w), "Small")
	H.eq(#Rows(w), 3)
end)

--------------------------------------------------------------------------------
-- Fights
--------------------------------------------------------------------------------

H.test("a fight hides setup and locks the HUD; setup comes back on the same page", function()
	local w, ns, db = NewOpen()
	for _ = 1, 3 do Next(w) end
	MoveHud(w)
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.ok(not IsOpen(w), "hidden")
	H.eq(db.locked, true, "locked")
	H.eq(db.welcomeSeen, nil, "not a close")
	H.eq(ns.setupOpen, false)
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.ok(IsOpen(w), "back")
	H.eq(Parts(w).counter:GetText(), "Step 3 of 7", "same page")
	H.eq(ButtonText(w, "moveHud"), "Move the HUD", "locked")
	H.eq(ns.setupOpen, true)
end)

H.test("after a fight, Escape closes setup, and the next fight hides it again", function()
	local w, ns, db = NewOpen()
	Next(w)
	for _ = 1, 2 do
		w.combat = true
		w:fire("PLAYER_REGEN_DISABLED")
		H.ok(not IsOpen(w), "hidden for the fight")
		H.eq(ns.setupOpen, false)
		w.combat = false
		w:fire("PLAYER_REGEN_ENABLED")
		H.ok(IsOpen(w), "back after the fight")
	end
	Escape(w)
	H.ok(not IsOpen(w), "Escape closes it")
	H.eq(ns.setupOpen, false, "the HUD can hide again")
	H.eq(db.welcomeSeen, true)
end)

H.test("only Escape is a key: Enter and the other keys go on to the game", function()
	local w, ns, db = NewOpen()
	local win = Win(w)
	H.ok(win:IsKeyboardEnabled())
	Next(w)
	for _, key in ipairs({ "ENTER", "W", "SLASH" }) do
		Key(w, key)
		H.ok(win:GetPropagateKeyboardInput(), key .. " goes on to the game")
		H.eq(Parts(w).counter:GetText(), "Step 1 of 7", key .. " changes no page")
		H.ok(IsOpen(w), key .. " does not close setup")
	end
	for _ = 1, 6 do Next(w) end
	Key(w, "ENTER")
	H.ok(IsOpen(w), "Enter on page 8 is not Done")
	-- In combat lockdown the keys are not touched (the call is blocked there).
	w.combat = true
	Escape(w)
	H.eq(#w:takeBlocked(), 0, "no blocked call")
	H.ok(IsOpen(w), "nothing happens")
	w.combat = false
	Escape(w)
	H.ok(not win:GetPropagateKeyboardInput(), "Escape stays with setup")
	H.ok(not IsOpen(w), "Escape is Skip setup")
	H.eq(db.welcomeSeen, true)
	H.eq(db.locked, true)
	H.eq(ns.setupOpen, false)
	w:slash("/hud setup")
	H.ok(win:GetPropagateKeyboardInput(), "opened again: the keys go on to the game")
end)

--------------------------------------------------------------------------------
-- Step 7: the page for your class (TICK-0180)
--------------------------------------------------------------------------------

-- Next from page 1 to step 7 (the default Mage has it).
local function ClassPage(w)
	for _ = 1, 7 do Next(w) end
	return Visible(Parts(w).alerts)
end

-- Page 9: its picks block and its bars notice.
local function Page9(w)
	for _ = 1, 8 do Next(w) end
	return Visible(Parts(w).alerts), Visible(Parts(w).bars)
end

-- Step 7's shown small boxes: { name, checked, enabled, note, row }.
local function Minis(w)
	local out = {}
	for _, r in ipairs(Parts(w).minis) do
		if r:IsShown() then
			out[#out + 1] = { name = r.name:GetText(), checked = r.check:GetChecked(),
				enabled = r.check:IsEnabled(), note = Visible(r.note), row = r }
		end
	end
	return out
end

local function MiniNames(w)
	local out = {}
	for i, b in ipairs(Minis(w)) do out[i] = b.name end
	return table.concat(out, ",")
end

-- Click the small box of this name: on the box, or on its check box.
local function TickMini(w, name, onCheck)
	for _, b in ipairs(Minis(w)) do
		if b.name == name then
			w:Run(onCheck and b.row.check or b.row, "OnClick")
			return
		end
	end
	error("no small box " .. name)
end

-- A world with these spells known, the class file changed by edit(profile),
-- and setup open on page 1. before(ns), when set, runs before setup opens.
local function ClassWorld(known, edit, before)
	local w = GameRow(NewWorld())
	if known then Know(w, known) end
	local ns = w:loadAddon()
	if edit then edit(ns.ClassProfiles().MAGE) end
	if before then before(ns) end
	w:runTimers()
	return w, ns, w.env.HUDiniDB
end

local SOUND = "Sound when a buff is missing"

H.test("step 7: the known bells in class file order, then the buff sound, in two columns", function()
	local w, ns = ClassWorld({ "Evocation", "Cold Snap" })
	ClassPage(w)
	local T, p = ns.TEXT[0], Parts(w)
	H.eq(p.counter:GetText(), "Step 7 of 7")
	H.eq(Visible(p.question), T["setup.class.question"]:format("Mage"))
	H.eq(Visible(p.under), T["setup.class.under"])
	H.eq(Visible(p.changes), T["setup.class.changes"])
	H.eq(MiniNames(w), "Ready alert: Evocation,Ready alert: Cold Snap," .. SOUND, "Ice Block is not known: no box")
	local m = Minis(w)
	H.eq(select(4, m[1].row:GetPoint()), select(4, m[3].row:GetPoint()), "the third box starts the second row")
	H.ok(select(4, m[2].row:GetPoint()) > select(4, m[1].row:GetPoint()), "the second box is right of the first")
	H.ok(select(5, m[3].row:GetPoint()) < select(5, m[1].row:GetPoint()), "the third box is under the first")
	H.ok(Y(p.question) > select(5, m[1].row:GetPoint()), "the boxes are under the question")
	H.ok(select(5, m[3].row:GetPoint()) > Y(p.under), "and over the line under them")
	for _, b in ipairs(m) do H.eq(b.note, nil, b.name .. ": no note") end
	H.eq(#Rows(w), 0, "no choice rows")
	H.eq(ButtonText(w, "main"), "Next")
	Press(w, "left1")
	H.eq(p.counter:GetText(), "Step 6 of 7", "Back goes to step 6")
end)

H.test("step 7: at most four bells, those that start on first, then the others, each known", function()
	local w = ClassWorld({ "Evocation", "Ice Block", "Blink", "Frost Nova", "Polymorph" }, function(profile)
		profile.readyAlert = { "Evocation", "Ice Block", "Cold Snap", "Blink", "Frost Nova", "Polymorph" }
		profile.readyAlertOn = { "Frost Nova", "Ice Block", "Cold Snap" }
	end)
	ClassPage(w)
	H.eq(MiniNames(w), "Ready alert: Ice Block,Ready alert: Frost Nova,Ready alert: Evocation,Ready alert: Blink," .. SOUND)
end)

H.test("step 7: no readyAlert gives no bell box, no keepUp no sound box; with nothing, setup skips it", function()
	local w = ClassWorld({ "Evocation" }, function(profile) profile.readyAlert = nil end)
	ClassPage(w)
	H.eq(MiniNames(w), SOUND, "no readyAlert: no bell")
	w = ClassWorld({ "Evocation" }, function(profile) profile.keepUp = nil end)
	ClassPage(w)
	H.eq(MiniNames(w), "Ready alert: Evocation", "no keepUp: no sound box")
	-- No box and no Already on line: six steps, and step 6 leads to page 9.
	w = ClassWorld({ "Counterspell" }, function(profile)
		profile.readyAlert, profile.keepUp = nil, nil
		profile.interrupt, profile.dispel, profile.purge = nil, nil, nil
	end)
	for _ = 1, 6 do Next(w) end
	H.eq(Parts(w).counter:GetText(), "Step 6 of 6")
	Next(w)
	H.eq(ButtonText(w, "main"), "Finish", "past step 7 to page 9")
	H.eq(Visible(Parts(w).alerts), nil, "page 9: no picks")
	Press(w, "left1")
	H.eq(Parts(w).counter:GetText(), "Step 6 of 6", "Back goes past it too")
end)

-- A Priest has no keepUp; its sound is for a tracked buff (Inner Fire), so
-- keepUpSoundOn alone gives the sound box.
H.test("step 7: keepUpSoundOn with no keepUp gives the sound box", function()
	local w = ClassWorld({ "Evocation" }, function(profile)
		profile.keepUp, profile.keepUpSoundOn = nil, true
	end)
	ClassPage(w)
	H.eq(MiniNames(w), "Ready alert: Evocation," .. SOUND, "the sound box")
	w = ClassWorld({ "Evocation" }, function(profile)
		profile.keepUp, profile.keepUpSoundOn = nil, false
	end)
	ClassPage(w)
	H.eq(MiniNames(w), "Ready alert: Evocation", "keepUpSoundOn false: no sound box")
end)

-- TICK-0182: one box for each missing item row whose spell you know.
local GEM = "Missing item: Mana Agate"

-- ClassWorld, with the game naming the gem.
local function ItemWorld(known)
	local w = GameRow(NewWorld())
	Know(w, known)
	w.env.C_Item.GetItemNameByID = function(id) if id == 5514 then return "Mana Agate" end end
	local ns = w:loadAddon()
	w:runTimers()
	return w, ns, w.env.HUDiniDB
end

H.test("step 7: a known missing item gives a box after the sound box, named as the game names it", function()
	local w = ItemWorld({ "Evocation", "Conjure Mana Gem" })
	ClassPage(w)
	H.eq(MiniNames(w), "Ready alert: Evocation," .. SOUND .. "," .. GEM)
	w = ItemWorld({ "Evocation" })
	ClassPage(w)
	H.eq(MiniNames(w), "Ready alert: Evocation," .. SOUND, "the spell not known: no box")
	-- The game has not loaded the item yet: the spell's name.
	w = ClassWorld({ "Conjure Mana Gem" })
	ClassPage(w)
	H.eq(MiniNames(w), SOUND .. ",Missing item: Conjure Mana Gem", "no item name yet")
end)

H.test("step 7: the item box shows the row's choice, a click turns it, page 9 lists it", function()
	local w, ns, db = ItemWorld({ "Conjure Mana Gem" })
	local T = ns.TEXT[0]
	ClassPage(w)
	H.eq(Minis(w)[2].checked, true, "on from the class file")
	H.eq(Minis(w)[2].enabled, true, "the health bar is on")
	Next(w)
	H.eq(Visible(Parts(w).alerts), table.concat({
		T["setup.p7.classPicks"]:format("Mage"),
		T["setup.p7.sound"]:format(T["opt.sound.off"]),
		T["setup.p7.items"]:format("Mana Agate"),
		T["setup.p7.test"],
	}, "\n"))
	Press(w, "left1")
	TickMini(w, GEM)
	H.eq(ns.GetMissingItem("manaGem"), false, "the click turns it off")
	H.eq(db.classes.MAGE.missingItem.manaGem, false, "saved for the Mage")
	Next(w)
	H.eq(Visible(Parts(w).alerts), table.concat({
		T["setup.p7.classPicks"]:format("Mage"),
		T["setup.p7.sound"]:format(T["opt.sound.off"]),
		T["setup.p7.test"],
	}, "\n"), "nothing checked: no items line")
	db.showHealth = false
	Press(w, "left1")
	H.eq(Minis(w)[2].enabled, false, "gray with no health bar")
end)

H.test("step 7 with only Already on lines: page 9 gives the /hud test line alone", function()
	local w, ns = ClassWorld({ "Counterspell" }, function(profile) profile.readyAlert, profile.keepUp = nil, nil end)
	local T = ns.TEXT[0]
	H.eq(ClassPage(w), table.concat({ T["setup.class.on"], T["setup.class.interrupt"]:format("Counterspell"),
		T["setup.class.more"] }, "\n"))
	H.eq(MiniNames(w), "", "no box")
	Next(w)
	H.eq(Visible(Parts(w).alerts), T["setup.p7.test"])
end)

H.test("step 7: a KnownSpell that says false is not known", function()
	local w = ClassWorld({ "Evocation" }, nil, function(ns)
		local known = ns.KnownSpell
		ns.KnownSpell = function(name) return known(name) or false end
	end)
	ClassPage(w)
	H.eq(MiniNames(w), "Ready alert: Evocation," .. SOUND)
end)

H.test("step 7: each box shows its value now, and Next writes nothing", function()
	local w, ns, db = ClassWorld({ "Evocation", "Cold Snap" }, nil, function(ns)
		ns.SetReadyAlert("Cold Snap", true)
	end)
	local before = H.dump and H.dump(db.classes) or nil
	ClassPage(w)
	local m = Minis(w)
	H.eq(m[1].checked, false, "Evocation as saved: off")
	H.eq(m[2].checked, true, "Cold Snap as saved: on")
	H.eq(m[3].checked, false, "the sound as saved: off")
	Next(w)
	H.eq(ns.GetReadyAlert("Evocation"), false)
	H.eq(ns.GetReadyAlert("Cold Snap"), true)
	H.eq(ns.GetKeepUpSoundChoice(), "off")
	H.eq(db.classes.MAGE.keepUpSound, nil, "Next writes no sound")
	H.eq((db.classes.MAGE.readyGlow or {}).Evocation, nil, "Next writes no glow")
	H.eq((db.classes.MAGE.readySounds or {}).Evocation, nil, "and no sound")
	if before then H.eq(H.dump(db.classes), before) end
end)

H.test("step 7: a ready alert click leaves the timer bar; the Options row repaints", function()
	local w, ns = ClassWorld({ "Evocation" }, nil, function(ns) ns.SetTimerBar("Evocation", true) end)
	local notified = {}
	w.env.Settings.GetSetting = function(variable)
		return { NotifyUpdate = function() notified[#notified + 1] = variable end }
	end
	w.env.SettingsPanel:Show()
	ClassPage(w)
	notified = {}
	TickMini(w, "Ready alert: Evocation")
	H.eq(ns.GetReadyAlert("Evocation"), true)
	H.eq(ns.GetTimerBar("Evocation"), true, "the bar stays")
	H.eq(table.concat(notified, ","), "HUDini_class_cooldown_Evocation_glow", "the glow repaints the whole grid row")
	H.eq(Minis(w)[1].checked, true)
	TickMini(w, "Ready alert: Evocation", true)
	H.eq(ns.GetReadyAlert("Evocation"), false, "on the check box too")
	H.eq(ns.GetTimerBar("Evocation"), true, "the bar still stays")
	H.eq(Minis(w)[1].checked, false)
end)

H.test("step 7: the sound box puts back the sound at its volume", function()
	local w, ns = ClassWorld({ "Evocation" }, nil, function(ns)
		ns.SetKeepUpSound({ key = "voiceKick", volume = 25 })
	end)
	ClassPage(w)
	TickMini(w, SOUND)
	H.eq(ns.GetKeepUpSoundValue(), false, "off")
	TickMini(w, SOUND)
	local c = ns.GetKeepUpSoundValue()
	H.eq(c and (c.key .. "@" .. c.volume), "voiceKick@25", "on again: the same sound and volume")
end)

H.test("step 7: the sound box puts back the last sound, else the default", function()
	local w, ns = ClassWorld({ "Evocation" }, nil, function(ns) ns.SetKeepUpSound("alarmClock") end)
	ClassPage(w)
	H.eq(Minis(w)[2].checked, true, "on at open")
	TickMini(w, SOUND)
	H.eq(ns.GetKeepUpSoundChoice(), "off")
	TickMini(w, SOUND)
	H.eq(ns.GetKeepUpSoundChoice(), "alarmClock", "the sound on at open")
	ns.SetKeepUpSound("coins")
	TickMini(w, SOUND)
	TickMini(w, SOUND)
	H.eq(ns.GetKeepUpSoundChoice(), "coins", "the sound on before the uncheck")
	local w2, ns2 = ClassWorld({ "Evocation" })
	ClassPage(w2)
	TickMini(w2, SOUND)
	H.eq(ns2.GetKeepUpSoundChoice(), ns2.MISSING_SOUND_DEFAULT, "never picked: the default")
end)

H.test("step 7: a gray box keeps its check and takes no click", function()
	local w, ns, db = ClassWorld({ "Evocation" }, nil, function(ns) ns.SetKeepUpSound("alarmClock") end)
	db.warnKeepUp, db.warnOwnBuff = false, false
	ClassPage(w)
	local sound = Minis(w)[2]
	H.eq(sound.enabled, false, "gray as its Options row: both buff reminders off")
	H.eq(sound.checked, true, "it still shows its check")
	H.eq(sound.note, nil, "no note")
	TickMini(w, SOUND)
	TickMini(w, SOUND, true)
	H.eq(ns.GetKeepUpSoundChoice(), "alarmClock", "no click")
	db.warnKeepUp = true
	Press(w, "left1"); Next(w)
	H.eq(Minis(w)[2].enabled, true, "a buff reminder on: it takes a click")
end)

H.test("step 7: a Mage who knows no alert spell gets the More line alone", function()
	local w = NewOpen()
	H.eq(ClassPage(w), w.ns.TEXT[0]["setup.class.more"])
end)

H.test("step 7: Already on lists the known spells' lines, then More", function()
	local w = ClassWorld({ "Counterspell", "Mana Shield" })
	local T = w.ns.TEXT[0]
	H.eq(ClassPage(w), table.concat({
		T["setup.class.on"],
		T["setup.class.interrupt"]:format("Counterspell"),
		T["setup.class.keepUp"]:format("Mana Shield"),
		T["setup.class.more"],
	}, "\n"))
	local p = Parts(w)
	H.ok(select(5, Minis(w)[1].row:GetPoint()) > Y(p.alerts), "under the boxes")
	H.ok(Y(p.alerts) > Y(p.under), "over the line under them")
end)

H.test("step 7: every alert spell known gives no More; a row turned off drops its line", function()
	local w = NewWorld()
	Know(w, { "Counterspell", "Remove Lesser Curse", "Spellsteal", "Ice Barrier", "Mana Shield" })
	local ns = w:loadAddon()
	w:runTimers()
	w.env.HUDiniDB.warnKeepUp = false
	local T = ns.TEXT[0]
	H.eq(ClassPage(w), table.concat({
		T["setup.class.on"],
		T["setup.class.interrupt"]:format("Counterspell"),
		T["setup.class.dispel"]:format("Remove Lesser Curse"),
		T["setup.class.purge"]:format("Spellsteal"),
	}, "\n"))
	H.eq(select(2, ns.SetupAlertLines()), false, "nothing left to learn")
end)

H.test("page 9: the picks of step 7, then /hud test", function()
	local w, ns = ClassWorld({ "Evocation", "Cold Snap" }, nil, function(ns) ns.SetKeepUpSound("alarmClock") end)
	local T = ns.TEXT[0]
	ClassPage(w)
	TickMini(w, "Ready alert: Evocation")
	TickMini(w, "Ready alert: Cold Snap")
	Next(w)
	H.eq(Visible(Parts(w).alerts), table.concat({
		T["setup.p7.classPicks"]:format("Mage"),
		T["setup.p7.bells"]:format("Evocation, Cold Snap"),
		T["setup.p7.sound"]:format(T["sound.alarmClock"]),
		T["setup.p7.test"],
	}, "\n"))
	Press(w, "left1")
	TickMini(w, "Ready alert: Evocation")
	TickMini(w, "Ready alert: Cold Snap")
	TickMini(w, SOUND)
	Next(w)
	H.eq(Visible(Parts(w).alerts), table.concat({
		T["setup.p7.classPicks"]:format("Mage"),
		T["setup.p7.noBells"],
		T["setup.p7.sound"]:format(T["opt.sound.off"]),
		T["setup.p7.test"],
	}, "\n"))
	-- No known bell: no bells line.
	local w2, ns2 = ClassWorld()
	H.eq((Page9(w2)), table.concat({
		T["setup.p7.classPicks"]:format("Mage"),
		T["setup.p7.sound"]:format(T["opt.sound.off"]),
		T["setup.p7.test"],
	}, "\n"))
end)

H.test("step 7: the interrupt line names every known interrupt", function()
	local w = NewWorld()
	Know(w, { "Pummel", "Shield Bash" })
	local ns = w:loadAddon()
	ns.ClassValue = function(key) if key == "interrupt" then return { "Pummel", "Shield Bash" } end end
	local lines, unknown = ns.SetupAlertLines()
	H.eq(lines[1], ns.TEXT[0]["setup.class.interrupt"]:format("Pummel, Shield Bash"))
	H.eq(unknown, false)
end)

H.test("step 7: dispel and keep-up name the first known spell only", function()
	local w = NewWorld()
	Know(w, { "Ice Barrier", "Mana Shield", "Cure", "Purify" })
	local ns = w:loadAddon()
	local lines = ns.SetupAlertLines()
	H.eq(lines[#lines], ns.TEXT[0]["setup.class.keepUp"]:format("Ice Barrier"), "keep-up: the Mage's first")
	ns.ClassValue = function(key) if key == "dispel" then return { Poison = "Purify", Magic = "Cure" } end end
	lines = ns.SetupAlertLines()
	H.eq(lines[1], ns.TEXT[0]["setup.class.dispel"]:format("Cure"), "dispel: by type, Magic first")
	H.eq(#lines, 1)
end)

-- The test Mage with trackBuff (TICK-0209): Arcane Intellect and the armor
-- group of the fixture's auraMap. keepUp, if given, replaces its own.
local function TrackWorld(known, class, track, keepUp)
	local w = NewWorld()
	if class then w.class, w.className = class, class:sub(1, 1) .. class:sub(2):lower() end
	Know(w, known)
	local ns = w:loadAddon()
	local real = ns.ClassValue
	ns.ClassValue = function(key)
		if key == "trackBuff" then return track or { "Arcane Intellect", "Frost Armor", "Ice Armor", "Mage Armor" } end
		if key == "keepUp" and keepUp then return keepUp end
		return real(key)
	end
	return w, ns
end

H.test("step 7: the tracked buff line names each known buff, one name per group (TICK-0209)", function()
	local w, ns = TrackWorld({ "Arcane Intellect", "Frost Armor", "Ice Armor", "Mage Armor" })
	local lines, unknown = ns.SetupAlertLines()
	H.eq(lines[#lines], ns.TEXT[0]["setup.class.trackBuff"]:format("Arcane Intellect, Frost Armor"),
		"the armors are one group: the first known says it")
	H.eq(unknown, true, "Ice Barrier and the others are still to learn")
	-- A Mage who knows only Ice Armor of the group: it names that one.
	w, ns = TrackWorld({ "Arcane Intellect", "Ice Armor" })
	lines = ns.SetupAlertLines()
	H.eq(lines[#lines], ns.TEXT[0]["setup.class.trackBuff"]:format("Arcane Intellect, Ice Armor"))
end)

H.test("step 7: the tracked buff line follows its alert row and known spells (TICK-0209)", function()
	local w, ns = TrackWorld({})
	local lines, unknown = ns.SetupAlertLines()
	H.eq(#lines, 0, "a level 1 Mage who knows none: no line")
	H.eq(unknown, true, "and More start as you learn their spells")
	w, ns = TrackWorld({ "Arcane Intellect" })
	H.eq(ns.SetupAlertLines()[1], ns.TEXT[0]["setup.class.trackBuff"]:format("Arcane Intellect"))
	w.env.HUDiniDB.warnOwnBuff = false
	H.eq(#ns.SetupAlertLines(), 0, "Tracked buff is off unchecked: no line")
end)

H.test("step 7: a tracked buff the combat buff line names is said once (TICK-0209 review)", function()
	-- A Warlock's armor is in keepUp and in trackBuff (one auraMap group).
	local armor = { "Demon Armor", "Demon Skin" }
	local w, ns = TrackWorld({ "Demon Skin" }, "WARLOCK", armor, armor)
	local lines = ns.SetupAlertLines()
	local T = ns.TEXT[0]
	H.eq(lines[#lines], T["setup.class.keepUp"]:format("Demon Skin"), "the combat buff line says it")
	for _, line in ipairs(lines) do
		H.ok(not line:find(T["setup.class.trackBuff"]:format(""), 1, true), "no tracked buff line for the same armor")
	end
	-- With the combat buff row off, the tracked buff line says the armor.
	w.env.HUDiniDB.warnKeepUp = false
	lines = ns.SetupAlertLines()
	H.eq(lines[#lines], T["setup.class.trackBuff"]:format("Demon Skin"))
	-- Another buff of trackBuff still shows next to the covered armor.
	w, ns = TrackWorld({ "Demon Skin", "Unending Breath" }, "WARLOCK", { "Unending Breath", "Demon Armor" }, armor)
	lines = ns.SetupAlertLines()
	H.eq(lines[#lines], T["setup.class.trackBuff"]:format("Unending Breath"))
end)

H.test("step 7: a spell saved by ID shows its name", function()
	local w = NewWorld()
	Know(w, { "Kick" })
	local ns = w:loadAddon()
	local id = w.env.C_Spell.GetSpellInfo("Kick").spellID
	ns.ClassValue = function(key) if key == "interrupt" then return id end end
	H.eq(ns.SetupAlertLines()[1], ns.TEXT[0]["setup.class.interrupt"]:format("Kick"))
end)

H.test("step 7: a class with no alert spells says nothing about alerts", function()
	local w, ns = NewOpen()
	ns.ClassValue = function() return nil end
	local alerts = ClassPage(w)
	H.eq(alerts, nil)
end)

H.test("page 9: the bars notice names the shown bars 4-8 that hold an action, in bar row mode", function()
	local w = NewWorld()
	w:Frame("MainMenuBar")            -- Bar 1, read: never named
	w:Frame("MultiBarBottomLeft")     -- Bar 2, read: never named
	w:Frame("MultiBarBottomRight")    -- Bar 3, read: never named
	w:Frame("MultiBarRight"):Hide()   -- Bar 4, hidden
	w:Frame("MultiBarLeft")           -- Bar 5, shown
	w:Frame("MultiBar5")              -- Bar 6, shown
	w:Frame("MultiBar6")              -- Bar 7, shown but empty
	w.env.GetActionInfo = function(slot)
		if slot == 1 or slot == 61 or slot == 49 or slot == 25 or slot == 40 or slot == 150 then return "spell", 100 end
	end
	local ns = w:loadAddon()
	w:runTimers()
	local _, bars = Page9(w)
	H.eq(bars, ns.TEXT[0]["setup.p7.bars"]:format("Action Bars 5 and 6"))
	w.env.MultiBarRight:Show()
	H.eq(table.concat(ns.SetupUnreadBars(), ","), "4,5,6")
	w.env.HUDiniDB.layoutMode = "wrap"
	H.eq(#ns.SetupUnreadBars(), 0, "Pack and wrap reads them")
end)

H.test("page 9: one bar is named alone, and no bar gives no notice", function()
	local w = NewWorld()
	w:Frame("MultiBar7")
	w.env.GetActionInfo = function(slot) if slot == 170 then return "spell", 100 end end
	w:loadAddon()
	w:runTimers()
	local _, bars = Page9(w)
	H.eq(bars, w.ns.TEXT[0]["setup.p7.bars"]:format("Action Bar 8"))
	local w2 = NewOpen()
	local _, none = Page9(w2)
	H.eq(none, nil)
end)

--------------------------------------------------------------------------------
-- The texts
--------------------------------------------------------------------------------

H.test("each setup and About text that follows the level has a level 1 and a level 2 text", function()
	local w = NewWorld()
	local ns = w:loadAddon()
	local T = ns.TEXT
	-- The About host line (TICK-0083): the copy of D-029 (TICK-0134) gives
	-- it a text at every level, so it shows at every level.
	for level = 0, 2 do
		H.ok(T[level]["about.host"] and T[level]["about.host"] ~= "", "about.host at level " .. level)
	end
	for _, key in ipairs({ "setup.p1.pitch", "setup.p1.again", "setup.p1.under",
			"setup.hud.extras.under", "setup.s2.under",
			"setup.size.under", "setup.feed.under", "setup.s5.under", "setup.p7.body",
			"setup.p7.bodyAlways", "setup.p7.last", "setup.hud.essentials", "setup.s2.intro",
			"setup.hud.xp.line", "setup.hud.targetPower.line", "setup.hud.debuffs.line",
			"setup.size.intro", "setup.feed.intro", "setup.s5.intro", "setup.s6.intro",
			"setup.s6.under", "setup.s6.lesson", "setup.s5.lesson", "setup.class.intro",
			"setup.class.under" }) do
		H.ok(T[0][key], key .. " at level 0")
		H.ok(T[1][key] and T[1][key] ~= T[0][key], key .. " at level 1")
		H.ok(T[2][key] and T[2][key] ~= T[1][key], key .. " at level 2")
	end
	for level = 1, 2 do
		for key in pairs(T[level]) do
			if key:find("^setup%.") then
				H.ok(T[0][key], key)
			end
		end
	end
end)

H.test("each step shows its intro between the step counter and the question, at the level now", function()
	local w, ns, db = NewOpen()
	local T = ns.TEXT
	H.eq(Visible(Parts(w).intro), nil, "page 1 has no intro")
	Pick(w, "Full")
	local INTRO = { "setup.hud.essentials", "setup.s2.intro", "setup.size.intro", "setup.feed.intro",
		"setup.s5.intro", "setup.s6.intro" }
	for n = 1, 6 do
		Next(w)
		H.eq(Parts(w).counter:GetText(), "Step " .. n .. " of 7")
		local p = Parts(w)
		H.eq(Visible(p.intro), T[2][INTRO[n]], "step " .. n .. " at level 2")
		H.ok(Y(p.intro) > Y(p.question), "step " .. n .. ": the intro is above the question")
		H.ok(Y(p.intro) < -(20 + 40), "step " .. n .. ": the intro is under the counter")
	end
	db.flair = 0
	Press(w, "left1") -- Back to step 5: the repaint reads the level now
	H.eq(Visible(Parts(w).intro), T[0]["setup.s5.intro"], "level 0 after the level changes")
	Next(w); Next(w)
	H.eq(Visible(Parts(w).intro), T[0]["setup.class.intro"]:format("Mage"), "step 7 names the class")
	H.ok(Y(Parts(w).intro) > Y(Parts(w).question), "step 7: the intro is above the question")
	Next(w)
	H.eq(ButtonText(w, "main"), "Finish")
	H.eq(Visible(Parts(w).intro), nil, "page 9 has no intro")
end)

H.test("every step gives every choice a line", function()
	local w, ns = NewOpen()
	local T = ns.TEXT[0]
	local want = {
		[1] = {},
		[2] = { "setup.s2.smart", "setup.s2.always" },
		[3] = { "setup.s3.small", "setup.s3.medium", "setup.s3.large" },
		[4] = { "setup.feed.off", "setup.feed.on", "setup.feed.hints" },
		[5] = { "setup.s5.no", "setup.s5.yes" },
		[6] = { "setup.s6.no", "setup.s6.yes" },
	}
	for n = 1, 6 do
		Next(w)
		do
			local rows = Rows(w)
			H.eq(#rows, #want[n], "step " .. n .. " rows")
			for i, key in ipairs(want[n]) do
				H.eq(rows[i].name, T[key], key)
				H.ok(T[key .. ".line"], key .. ".line has a text")
				H.eq(Visible(rows[i].row.line), T[key .. ".line"], key .. " shows its line")
			end
		end
		if n == 1 then
			-- Step 1: a line under each check box (TICK-0115).
			local boxes = Boxes(w)
			H.eq(#boxes, 3, "step 1 boxes")
			for i, key in ipairs({ "setup.hud.xp", "setup.hud.targetPower", "setup.hud.debuffs" }) do
				H.eq(boxes[i].name, T[key], key)
				H.ok(T[key .. ".line"], key .. ".line has a text")
				H.eq(Visible(boxes[i].row.line), T[key .. ".line"], key .. " shows its line")
			end
		end
	end
end)

H.test("the setup window is 600 px wide", function()
	local w = NewOpen()
	H.eq(Win(w):GetWidth(), 600)
end)

H.test("every setup.* key Setup.lua reads by a whole name has a level 0 text", function()
	local w = NewWorld()
	local ns = w:loadAddon()
	local src = H.readFile("Setup.lua")
	local n = 0
	for key in src:gmatch("Text%(\"(setup%.[^\"]+)\"[,)]") do
		n = n + 1
		H.ok(ns.TEXT[0][key], key)
	end
	H.ok(n >= 20, "Setup.lua reads its texts through ns.Text")
end)

--------------------------------------------------------------------------------
-- Drag and a solid background (TICK-0079)
--------------------------------------------------------------------------------

H.test("the setup window is solid, drags with the left button, and stays on the screen", function()
	local w = NewOpen()
	local f = Win(w)
	H.eq(select(4, f:GetBackdropColor()), 1, "backdrop alpha")
	H.eq(f.__h.backdrop.bgFile, "Interface\\Buttons\\WHITE8X8", "a solid fill, not the see-through dialog background")
	H.eq(f.__h.backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Border", "the dialog border stays")
	H.eq(f:IsMovable(), true, "movable")
	H.eq(f:IsClampedToScreen(), true, "clamped to the screen")
	H.ok(#f.__h.drag == 1 and f.__h.drag[1] == "LeftButton", "the left button only")
	local point, to, rel, x, y = f:GetPoint()
	H.ok(point == "CENTER" and to == w.env.UIParent and rel == "CENTER" and x == 0 and y == 140, "the default place")
	H.eq(f:GetFrameStrata(), "DIALOG", "the strata is the same")
end)

H.test("a drag on Step 3 moves only setup; the place holds until a reload", function()
	local w, ns, db = NewOpen()
	for _ = 1, 3 do Next(w) end
	MoveHud(w)
	H.eq(db.locked, false)
	local hud = {}
	for i, pt in ipairs(ns.HUDini.__h.points) do hud[i] = { unpack(pt) } end
	local box = ns.HUDini.mover:IsShown()
	H.ok(box and #hud >= 1, "the Move the HUD box shows and the HUD has a place")
	local f = Win(w)
	w:Run(f, "OnDragStart")
	w:Run(f, "OnDragStop")
	H.eq(f:GetPoint(), "CURSOR", "setup is where the mouse let go")
	H.eq(f:IsUserPlaced(), false, "the game does not save the place")
	H.eq(#ns.HUDini.__h.points, #hud, "the HUD did not move")
	for i, pt in ipairs(hud) do
		for k = 1, 5 do H.eq(ns.HUDini.__h.points[i][k], pt[k], "the HUD did not move") end
	end
	H.eq(ns.HUDini.mover:IsShown(), box, "the Move the HUD box is as it was")
	H.eq(db.locked, false, "still unlocked")
	H.eq(Parts(w).counter:GetText(), "Step 3 of 7")
	Escape(w)
	H.ok(not IsOpen(w), "closed")
	w:slash("/hud setup")
	H.ok(IsOpen(w), "open again")
	H.eq(f:GetPoint(), "CURSOR", "the same place in the same session")

	local w2 = NewOpen()
	H.eq(Win(w2):GetPoint(), "CENTER", "after a reload: the default place")
end)

H.test("a hide in the middle of a drag ends the drag", function()
	local w = NewOpen()
	local f = Win(w)
	w:Run(f, "OnDragStart")
	H.eq(f.__h.moving, true)
	f:Hide()
	w:Run(f, "OnHide")
	H.eq(f.__h.moving, false, "not moving")
	H.eq(f:IsUserPlaced(), false)
end)

--------------------------------------------------------------------------------
-- Page 1 on a second run (TICK-0083)
--------------------------------------------------------------------------------

H.test("a second run: page 1 shows the second-run line at the level now, never the pitch", function()
	local w, ns = Seen()
	local T = ns.TEXT
	w:slash("/hud setup")
	H.ok(IsOpen(w))
	H.eq(Visible(Parts(w).top), T[0]["setup.p1.again"], "level 0")
	Pick(w, "Full")
	H.eq(Visible(Parts(w).top), T[2]["setup.p1.again"], "level 2 after the pick")
	H.eq(Visible(Parts(w).under), T[2]["setup.p1.under"])
	Pick(w, "Modest")
	H.eq(Visible(Parts(w).top), T[1]["setup.p1.again"], "level 1 after the pick")
	Next(w)
	Press(w, "left1")
	H.eq(Visible(Parts(w).top), T[1]["setup.p1.again"], "Back to page 1: still the second-run line")
	for level = 0, 2 do
		H.ok(T[level]["setup.p1.pitch"] ~= Visible(Parts(w).top), "not the pitch")
	end
end)

--------------------------------------------------------------------------------
-- Step 6: a quieter screen (TICK-0086, D-018)
--------------------------------------------------------------------------------

-- A new install with Action Bar 1's end art, the bag bar and the menu
-- buttons, logged in, setup open on step 6. The mouse is over neither bar.
local function QuietOpen(layoutMode)
	local w = NewWorld()
	local bar = w:Frame("MainActionBar", nil, { protected = true })
	bar.EndCaps = w:Frame(nil, bar)
	local bags, menu = w:Frame("BagsBar"), w:Frame("MicroMenuContainer")
	for _, f in ipairs({ bags, menu }) do f.IsMouseOver = function() return false end end
	local ns = w:loadAddon()
	w:runTimers()
	local db = w.env.HUDiniDB
	if layoutMode then db.layoutMode = layoutMode end
	for _ = 1, 6 do Next(w) end
	return w, ns, db, { caps = bar.EndCaps, bags = bags, menu = menu }
end

local function Alphas(f)
	return ("%s %s %s"):format(f.caps:GetAlpha(), f.bags:GetAlpha(), f.menu:GetAlpha())
end

H.test("step 6: Yes fades the two bars at once and No brings them back; the gryphons stay as they are", function()
	local w, ns, db, f = QuietOpen()
	H.eq(Parts(w).counter:GetText(), "Step 6 of 7")
	H.eq(Visible(Parts(w).question), ns.TEXT[0]["setup.s6.question"])
	H.eq(Visible(Parts(w).changes), ns.TEXT[0]["setup.s6.changes"])
	H.eq(Picked(w), "Keep them visible", "No is the default")
	H.eq(Alphas(f), "1 1 1")
	Pick(w, "Show on mouseover")
	for _, k in ipairs({ "bagBarMouseover", "menuBarMouseover" }) do H.eq(db[k], true, k) end
	H.eq(Alphas(f), "1 0 0", "at once, with no reload and no Next; the gryphons untouched (D-024)")
	H.eq(f.caps:IsShown(), true, "the gryphons stay shown")
	Pick(w, "Keep them visible")
	for _, k in ipairs({ "bagBarMouseover", "menuBarMouseover" }) do H.eq(db[k], false, k) end
	H.eq(Alphas(f), "1 1 1", "both come back at once")
	H.eq(#w:takeBlocked(), 0, "no blocked call")
	Next(w)
	H.eq(Parts(w).counter:GetText(), "Step 7 of 7", "the page for your class follows step 6")
	Next(w)
	H.eq(ButtonText(w, "main"), "Finish", "the end page follows step 7")
end)

H.test("step 6: in Row mode bar the lesson shows at the level now, after the line under the choices and before Changes", function()
	local w, ns, db = QuietOpen()
	local T, p = ns.TEXT, Parts(w)
	H.eq(db.layoutMode, "bar", "a new install is in Row mode bar")
	H.eq(Visible(p.lesson), T[0]["setup.s6.lesson"])
	H.ok(Y(p.under) > Y(p.lesson), "under the line under the choices")
	H.ok(Y(p.lesson) > Y(p.changes), "above the Changes line")
	db.flair = 2
	Press(w, "left1"); Next(w)
	H.eq(Visible(p.lesson), T[2]["setup.s6.lesson"], "it follows the level")
	for n = 1, 5 do
		Press(w, "left1")
		local page = 7 - n
		if page == 6 then
			H.eq(Visible(p.lesson), T[2]["setup.s5.lesson"], "step 5 has the chat lesson, the feed on")
		else
			H.eq(Visible(p.lesson), nil, "no lesson on page " .. page)
		end
	end
end)

H.test("step 6: in Pack and wrap the lesson is hidden and leaves no gap", function()
	local w, _, _, _ = QuietOpen("bar")
	local p = Parts(w)
	local barHeight = Win(w):GetHeight()
	local w2 = QuietOpen("wrap")
	local p2 = Parts(w2)
	H.eq(Visible(p2.lesson), nil, "no lesson in Pack and wrap")
	H.eq(Y(p2.gryphons), Y(p2.under) - p2.under:GetStringHeight() - 10, "the gryphons line sits right under the line under the choices")
	H.eq(Y(p2.under), Y(p.under), "the parts above stay where they are")
	H.eq(Win(w2):GetHeight(), barHeight - p.lesson:GetStringHeight() - 10, "the window is shorter by the lesson and its gap")
end)

-- D-024, TICK-0089: HUDini does not hide the gryphons; step 6 says how Edit
-- Mode does, with the box named in the game's own words.
H.test("step 6: the gryphons line shows at every level and Row mode, after the lesson and before Changes", function()
	for _, mode in ipairs({ "bar", "wrap" }) do
		for level = 0, 2 do
			local w, ns, db = QuietOpen(mode)
			w.env.HUD_EDIT_MODE_SETTING_END_CAP_HIDDEN = "Hide Gryphon"
			db.flair = level
			Press(w, "left1"); Next(w)
			local p, T = Parts(w), ns.TEXT
			local want = (T[level]["setup.s6.gryphons"] or T[0]["setup.s6.gryphons"]):format("Hide Gryphon")
			local at = mode .. ", level " .. level
			H.eq(Visible(p.gryphons), want, at)
			H.ok(Visible(p.gryphons):find("Hide Gryphon", 1, true), at .. ": names the box")
			H.ok(Y(p.gryphons) > Y(p.changes), at .. ": above Changes")
			if mode == "bar" then H.ok(Y(p.lesson) > Y(p.gryphons), at .. ": under the lesson") end
			Press(w, "left1")
			H.eq(Visible(p.gryphons), nil, at .. ": step 5 has no gryphons line")
		end
	end
end)

--------------------------------------------------------------------------------
-- Step 4: the feed (TICK-0096)
--------------------------------------------------------------------------------

-- A new install, setup open on step 4.
local function FeedOpen()
	local w, ns, db = NewOpen()
	for _ = 1, 4 do Next(w) end
	return w, ns, db
end

H.test("step 4: each choice writes the three feed keys; the tools row shows only while the feed is on", function()
	local w, ns, db = FeedOpen()
	local p = Parts(w)
	H.eq(p.counter:GetText(), "Step 4 of 7")
	H.eq(Visible(p.question), ns.TEXT[0]["setup.feed.question"])
	H.eq(Picked(w), "Events", "Events is the default")
	H.eq(Visible(p.sizeLabel), "Size:")
	H.ok(Y(p.sizeLabel) < Y(Rows(w)[3].row) and Y(p.sizeLabel) > Y(p.under), "the tools row is under the choices")
	local onHeight = Win(w):GetHeight()
	Pick(w, "Events and hints")
	H.eq(db.showFeed, true); H.eq(db.feedQuestProgress, true); H.eq(db.feedUpgrade, true)
	Pick(w, "Off")
	H.eq(db.showFeed, false); H.eq(db.feedQuestProgress, false); H.eq(db.feedUpgrade, false)
	H.eq(Visible(p.sizeLabel), nil, "no tools row with the feed off")
	for _, b in ipairs(p.sizes) do H.ok(not b:IsShown(), "no size button") end
	H.eq(ButtonText(w, "moveFeed"), nil, "no Move the feed")
	H.eq(Win(w):GetHeight(), onHeight - 22 - 10, "and no gap")
	Pick(w, "Events")
	H.eq(db.showFeed, true); H.eq(db.feedQuestProgress, false); H.eq(db.feedUpgrade, false)
	H.eq(Visible(p.sizeLabel), "Size:", "the row is back")
end)

H.test("step 4: a size button writes the text size and the width, and shows as picked", function()
	local w, ns, db = FeedOpen()
	local p = Parts(w)
	local names = {}
	for i, b in ipairs(p.sizes) do names[i] = b:GetText() end
	H.eq(table.concat(names, ","), "Small,Medium (default),Large")
	local function PickedSizes()
		local out = {}
		for _, b in ipairs(p.sizes) do if b.picked then out[#out + 1] = b:GetText() end end
		return table.concat(out, ",")
	end
	H.eq(PickedSizes(), "Medium (default)", "a new install has Medium")
	local applied = 0
	local apply = ns.ApplyFeed
	ns.ApplyFeed = function() applied = applied + 1; return apply() end
	for i, want in ipairs({ { 12, 360, "Small" }, { 14, 420, "Medium (default)" }, { 17, 500, "Large" } }) do
		Click(w, p.sizes[i])
		H.eq(db.feedFontSize, want[1], want[3] .. " text size")
		H.eq(db.feedWidth, want[2], want[3] .. " width")
		H.eq(PickedSizes(), want[3], want[3] .. " is picked")
	end
	H.eq(applied, 3, "each click applies the feed at once")
	db.feedFontSize = 15
	Press(w, "left1"); Next(w)
	H.eq(PickedSizes(), "", "a size set by hand: no button is picked")
	H.eq(db.feedFontSize, 15, "and Next and Back write nothing")
	H.eq(#w:takeBlocked(), 0, "no blocked call")
end)

H.test("step 4: Move the feed unlocks the feed alone; every way off the step locks it", function()
	local w, ns, db = FeedOpen()
	H.eq(ButtonText(w, "moveFeed"), "Move the feed")
	H.eq(FeedBox(w), false, "locked: no blue box")
	MoveFeed(w)
	H.eq(FeedBox(w), true, "the feed's blue box")
	H.eq(db.locked, true, "the HUD stays locked")
	H.eq(ns.HUDini.mover:IsShown(), false, "no HUD box")
	H.eq(ButtonText(w, "moveFeed"), "Lock in place", "the button says Lock")
	MoveFeed(w)
	H.eq(FeedBox(w), false, "a second click locks it")
	H.eq(ButtonText(w, "moveFeed"), "Move the feed")
	-- Next, Back, Off, a fight and Escape each lock it.
	MoveFeed(w); Next(w)
	H.eq(FeedBox(w), false, "Next")
	Press(w, "left1")
	MoveFeed(w); Press(w, "left1")
	H.eq(FeedBox(w), false, "Back")
	Next(w)
	MoveFeed(w); Pick(w, "Off")
	Pick(w, "Events")
	H.eq(FeedBox(w), false, "Off, then On again")
	H.eq(ButtonText(w, "moveFeed"), "Move the feed")
	MoveFeed(w)
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(FeedBox(w), false, "a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(ButtonText(w, "moveFeed"), "Move the feed", "back after the fight, locked")
	MoveFeed(w)
	Escape(w)
	H.eq(FeedBox(w), false, "Escape")
	H.eq(db.locked, true)
end)

H.test("step 4: five sample lines show while the step is open, and go by every route off it", function()
	local w, ns, db = NewOpen()
	for _ = 1, 3 do Next(w) end
	H.eq(Samples(w), 0, "none before the step")
	Next(w)
	H.eq(Samples(w), 5, "loot, money, XP, a quest and reputation")
	local kinds = {}
	for _, L in ipairs(ns.Feed.Keyed("sample:")) do kinds[#kinds + 1] = L.key end
	table.sort(kinds)
	H.eq(table.concat(kinds, ","), "sample:loot,sample:money,sample:quest,sample:rep,sample:xp")
	Pick(w, "Events")
	H.eq(Samples(w), 5, "a pick of the same choice adds none")
	Next(w)
	H.eq(Samples(w), 0, "Next")
	Press(w, "left1")
	H.eq(Samples(w), 5, "Back onto the step")
	Press(w, "left1")
	H.eq(Samples(w), 0, "Back off it")
	Next(w)
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(Samples(w), 0, "a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Samples(w), 5, "back after the fight")
	Escape(w)
	H.eq(Samples(w), 0, "Escape")
	H.eq(#w.printed, 0, "no chat line")
end)

-- A sample line's text, as the feed draws it.
local function SampleText(ns, key)
	for _, L in ipairs(ns.Feed.Keyed("sample:")) do
		if L.key == key then
			local text = L.text
			if type(text) == "function" then text = text(L) end
			return text
		end
	end
end

H.test("step 4: the leveling hints add their two samples at once, and On takes them away", function()
	local w, ns, db = NewOpen()
	for _ = 1, 4 do Next(w) end
	H.eq(Samples(w), 5, "On: five")
	H.eq(SampleText(ns, "sample:goal"), nil, "On: no quest goal line")
	H.eq(SampleText(ns, "sample:upgrade"), nil, "On: no upgrade line")
	Pick(w, "Events and hints")
	H.eq(db.feedQuestProgress, true)
	H.eq(db.feedUpgrade, true)
	H.eq(Samples(w), 7, "the hints: seven, at once")
	H.eq(SampleText(ns, "sample:goal"), "Sample objective: 3/8", "the quest goal line, as the real one: the goal text only")
	local up = SampleText(ns, "sample:upgrade")
	H.ok(up and up:find("[Sample Leather Armor]", 1, true), "the upgrade line names its item: " .. tostring(up))
	H.eq(up and up:match("|cff40ff40%+(%d+) ilvl|r"), "4", "with the green upgrade flag, as the real one")
	Pick(w, "Events and hints")
	H.eq(Samples(w), 7, "the same pick again adds none")
	Pick(w, "Events")
	H.eq(Samples(w), 5, "On again: the two go")
	H.eq(SampleText(ns, "sample:goal"), nil, "no quest goal line")
	H.eq(SampleText(ns, "sample:upgrade"), nil, "no upgrade line")
	Pick(w, "Off")
	H.eq(Samples(w), 0, "Off: none")
	Pick(w, "Events and hints")
	H.eq(Samples(w), 7, "from Off to the hints: seven")
	Next(w)
	H.eq(Samples(w), 0, "Next: none")
	H.eq(#w.printed, 0, "no chat line")
end)

H.test("feed samples: each hint shows only while it is on, and the upgrade needs Loot", function()
	local w = NewWorld()
	w.env.HUDiniDB = { schema = 99, welcomeSeen = true, feedQuestProgress = true, feedUpgrade = false }
	local ns = w:loadAddon()
	w:runTimers()
	ns.FeedSamples(true)
	H.eq(Samples(w), 6, "quest progress on, upgrade off")
	H.ok(SampleText(ns, "sample:goal"), "the quest goal line")
	H.eq(SampleText(ns, "sample:upgrade"), nil, "no upgrade line")
	w.env.HUDiniDB.feedQuestProgress, w.env.HUDiniDB.feedUpgrade = false, true
	ns.FeedSamples(true)
	H.eq(SampleText(ns, "sample:goal"), nil, "quest progress off: its line goes")
	H.ok(SampleText(ns, "sample:upgrade"), "upgrade on: its line shows")
	w.env.HUDiniDB.feedLoot = false
	ns.FeedSamples(true)
	H.eq(SampleText(ns, "sample:upgrade"), nil, "Loot off: no upgrade line, as no loot line shows")
	H.eq(SampleText(ns, "sample:loot"), nil, "and no loot line")
	ns.FeedSamples(false)
	H.eq(Samples(w), 0, "off: all go")
end)

H.test("step 4: a sample line follows the kind picks, and none shows with the feed off", function()
	local w = NewWorld()
	w.env.HUDiniDB = { schema = 99, welcomeSeen = true, feedMoney = false }
	w:loadAddon()
	w:runTimers()
	w:slash("/hud setup")
	for _ = 1, 4 do Next(w) end
	local keys = {}
	for _, L in ipairs(w.ns.Feed.Keyed("sample:")) do keys[L.key] = true end
	H.eq(keys["sample:money"], nil, "Money off: no money sample")
	H.eq(Samples(w), 4)
	Pick(w, "Off")
	H.eq(Samples(w), 0)
	Press(w, "left1"); Next(w)
	H.eq(Samples(w), 0, "the step with the feed off shows none")
end)

H.test("step 5: the chat lesson shows only with the feed on", function()
	local w, ns, db = NewOpen()
	for _ = 1, 5 do Next(w) end
	local p = Parts(w)
	H.eq(p.counter:GetText(), "Step 5 of 7")
	H.eq(Visible(p.lesson), ns.TEXT[0]["setup.s5.lesson"], "the feed on")
	H.ok(Y(p.under) > Y(p.lesson) and Y(p.lesson) > Y(p.changes), "after the line under the choices, before Changes")
	Press(w, "left1")
	Pick(w, "Off")
	Next(w)
	H.eq(Visible(p.lesson), nil, "the feed off")
end)

H.test("step 4: picks while the feed is on add no sample lines, with stacking off too", function()
	local w = NewWorld()
	w.env.HUDiniDB = { schema = 99, welcomeSeen = true, feedStack = false }
	w:loadAddon()
	w:runTimers()
	w:slash("/hud setup")
	for _ = 1, 4 do Next(w) end
	H.eq(Samples(w), 5)
	Pick(w, "Events and hints")
	Pick(w, "Events")
	H.eq(Samples(w), 5, "no repeat: stacking off does not join a second set")
end)

H.test("the version shows on the title line on every page; unknown says unavailable", function()
	local w, ns = NewOpen()
	ns.VERSION = "0.31.0"
	local seen = {}
	for page = 1, 9 do
		if page > 1 then Next(w) else Pick(w, Picked(w)) end
		seen[page] = Visible(Parts(w).version)
	end
	for page = 1, 9 do H.eq(seen[page], "Version 0.31.0", "page " .. page) end
	local _, to, rel = Parts(w).version:GetPoint(1)
	H.eq(to, Parts(w).title, "on the title")
	H.eq(rel, "BOTTOMRIGHT", "right of the title")
	local w2, ns2 = NewOpen()
	ns2.VERSION = "unknown"
	Next(w2)
	H.eq(Visible(Parts(w2).version), "Version unavailable")
end)
