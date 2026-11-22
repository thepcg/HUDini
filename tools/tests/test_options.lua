-- Options.lua (TICK-0017): every saved
-- setting has a row in the panel, or is one of the layout's "saved values
-- with no row"; no page has more than 15 rows above its Advanced header,
-- for any class; and the pages come in the layout's order. The harness
-- fakes already throw on AddShownPredicate and SetParentInitializer.

-- Test class profiles, not the live class files (classes_fixture.lua).
local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- options-layout.md "Saved values with no row": changed by a drag or a
-- slash command, not in a list.
local NO_ROW = {
	point = true, relPoint = true, x = true, y = true, classes = true, xpSessions = true,
	feedPoint = true, feedRelPoint = true, feedX = true, feedY = true, feedIgnore = true,
	bars = { bar1 = true }, -- Action Bar 1 is always read
	minimapAngle = true,    -- the minimap button's place: a drag saves it
}

-- Settings whose row a later branch adds. The test fails once the row is
-- there, so the line goes with the row. A color: "colors.<key>".
local ROW_PENDING = {}

-- Saved values a proxy row writes for them.
local PROXY = { growRight = "growToward", growDown = "growToward", auraMap = "auraMap" }

local PAGES = { "HUDini", "Icons", "Bars", "Colors", "Alerts", "Your class", "Feed", "Game frames" }

-- A world logged in as class, with every setting and every row on each
-- page kept in order. db, if given, is the saved HUDiniDB at login.
local function PanelWorld(class, db, before)
	local w = H.world()
	if db then w.env.HUDiniDB = db end
	if before then before(w) end
	w.class, w.className = class, class:sub(1, 1) .. class:sub(2):lower()
	w.vars, w.pageOrder, w.pages = {}, {}, {}
	local S = w.env.Settings
	local current

	local function Page(name)
		local rows = {}
		w.pages[name], w.pageOrder[#w.pageOrder + 1] = rows, name
		local category = { page = name }
		local layout = {
			-- The game keeps a header's or a button's tooltip in
			-- initializer.data (GetTooltip returns self.data.tooltip), so
			-- the page keeps that table: a retext shows on the row.
			AddInitializer = function(_, init)
				rows[#rows + 1] = rawget(init, "data")
			end,
		}
		current = rows
		return category, layout
	end
	-- A row keeps its setting's variable, a dropdown its choices, and a
	-- grayed row its predicate and the settings that re-gray it.
	local function Row(category, setting, getOptions, tooltip)
		local rows = w.pages[category.page]
		-- A checkbox gets its tooltip 3rd; a slider and a dropdown 4th.
		if type(getOptions) == "string" then tooltip = getOptions end
		local r = { row = true, variable = rawget(setting, "variable"), tooltip = tooltip,
			choices = type(getOptions) == "function" and getOptions or nil, regray = {} }
		rows[#rows + 1] = r
		local init = H.Fake()
		-- The game keeps the row's tooltip in initializer.data.
		rawset(init, "data", r)
		rawset(init, "AddModifyPredicate", function(_, fn) r.when = fn end)
		rawset(init, "AddEvaluateStateCVar", function(_, v) r.regray[#r.regray + 1] = v end)
		return init
	end
	-- A dropdown's choices as { value, label, tooltip } lists.
	S.CreateControlTextContainer = function()
		local list = {}
		return {
			Add = function(_, value, label, tooltip) list[#list + 1] = { value, label, tooltip } end,
			GetData = function() return list end,
		}
	end

	S.RegisterVerticalLayoutCategory = function(name) return Page(name) end
	S.RegisterVerticalLayoutSubcategory = function(_, name) return Page(name) end
	-- A setting's SetValue writes its saved value and lists the write in
	-- w.writes; a proxy keeps its getter and setter, and counts its repaints.
	w.callbacks, w.notified, w.writes = {}, {}, {}
	local function Counted(variable)
		w.notified[variable] = 0
		local setting = H.Fake()
		rawset(setting, "variable", variable)
		rawset(setting, "NotifyUpdate", function() w.notified[variable] = w.notified[variable] + 1 end)
		return setting
	end
	S.RegisterAddOnSetting = function(_, variable, key, tbl, _, label)
		w.vars[variable] = { key = key, tbl = tbl, label = label }
		local setting = Counted(variable)
		rawset(setting, "SetValue", function(_, v)
			tbl[key] = v
			w.writes[#w.writes + 1] = { variable = variable, value = v }
		end)
		return setting
	end
	S.RegisterProxySetting = function(_, variable, _, label, default, get, set)
		-- The game throws on a name it already has (Blizzard_SettingsPanel.lua:757).
		if w.vars[variable] then error("Setting variable '" .. variable .. "' was previously registered.") end
		w.vars[variable] = { proxy = true, default = default, get = get, set = set, label = label }
		return Counted(variable)
	end
	S.SetOnValueChangedCallback = function(variable, fn)
		local list = w.callbacks[variable] or {}
		list[#list + 1] = fn
		w.callbacks[variable] = list
	end
	S.CreateCheckbox, S.CreateSlider, S.CreateDropdown = Row, Row, Row
	w.env.CreateSettingsListSectionHeaderInitializer = function(text, tooltip)
		return { data = { header = text, tooltip = tooltip } }
	end
	w.env.CreateSettingsButtonInitializer = function(_, buttonText, click, tooltip)
		local init = H.Fake()
		rawset(init, "data", { row = true, button = buttonText, click = click, tooltip = tooltip })
		return init
	end
	w:loadAddon()
	H.ok(current ~= nil, class .. ": the panel was built")
	return w, w.ns
end

-- PanelWorld with the test class profiles: for a test that asserts one
-- class file's data. A test over every class keeps the live files.
local function ClassWorld(class, db, before)
	return PanelWorld(class, db, function(w)
		Classes.Use(w)
		if before then before(w) end
	end)
end

-- TICK-0019 cut the commands to 15; a tooltip must not name one that is
-- gone. /hud help <word> answers with "/hud <word>" only for a command.
local NOT_COMMANDS = { ["or"] = true, ["and"] = true, ["to"] = true, ["for"] = true, afterward = true }

H.test("every /hud command a row or header tooltip names is a command", function()
	for _, class in ipairs(CLASSES) do
		local w = PanelWorld(class)
		local seen = {}
		for _, page in ipairs(w.pageOrder) do
			for _, row in ipairs(w.pages[page]) do
				for word in tostring(row.tooltip or ""):gmatch("/hud (%a+)") do
					-- The copy of D-029 (TICK-0134) says "/hud or /hud setup":
					-- a word of the sentence after /hud is not a command.
					if not NOT_COMMANDS[word] and not seen[word] then
						seen[word] = true
						w.printed = {}
						w:slash("/hud help " .. word)
						H.ok(H.printed(w, "/hud " .. word .. " "), class .. ", " .. page .. ": /hud " .. word .. " is a command")
					end
				end
			end
		end
		-- The copy of D-029 (TICK-0134) names only /hud setup in a tooltip.
		H.ok(seen.setup, class .. ": the tooltips that name commands were read")
	end
end)

H.test("every saved setting has a row, or is a saved value with no row", function()
	for _, class in ipairs(CLASSES) do
		local w, ns = PanelWorld(class)
		for key, v in pairs(ns.defaults) do
			if type(v) == "table" and key == "colors" then
				for k in pairs(v) do
					if ROW_PENDING["colors." .. k] then
						H.ok(not w.vars["HUDini_color_" .. k],
							class .. ": color " .. k .. " has its row now: take it out of ROW_PENDING")
					else
						H.ok(w.vars["HUDini_color_" .. k], class .. ": color " .. k .. " is on the Colors page")
					end
				end
			elseif type(v) == "table" and type(NO_ROW[key]) == "table" then
				for k in pairs(v) do
					H.ok(NO_ROW[key][k] or (w.vars["HUDini_" .. k] and w.vars["HUDini_" .. k].tbl == w.env.HUDiniDB[key]),
						class .. ": " .. key .. "." .. k .. " has a row")
				end
			elseif ROW_PENDING[key] then
				H.ok(not w.vars["HUDini_" .. key], class .. ": " .. key .. " has its row now: take it out of ROW_PENDING")
			elseif not NO_ROW[key] then
				local name = "HUDini_" .. (PROXY[key] or key)
				H.ok(w.vars[name], class .. ": " .. key .. " has a row")
			end
		end
	end
end)

H.test("no page has more than 15 rows above Advanced", function()
	for _, class in ipairs(CLASSES) do
		local w = PanelWorld(class)
		for name, rows in pairs(w.pages) do
			local n = 0
			for _, r in ipairs(rows) do
				if r.header == "Advanced" then break end
				if r.row then n = n + 1 end
			end
			H.ok(n <= 15, class .. ": " .. name .. " has " .. n .. " rows above Advanced")
		end
	end
end)

H.test("the pages come in the layout's order", function()
	local w = ClassWorld("MAGE")
	H.eq(table.concat(w.pageOrder, ", "), table.concat(PAGES, ", "), "page order")
end)

H.test("the Colors page builds the power rows of your class only", function()
	local function Rows(class)
		local w = PanelWorld(class)
		local n = 0
		for _, r in ipairs(w.pages.Colors) do
			if r.header == "Advanced" then break end
			if r.row then n = n + 1 end
		end
		return n
	end
	H.eq(Rows("DRUID"), 15, "a druid: mana, rage, energy and combo points, the most of any class")
	H.eq(Rows("WARRIOR"), 12, "a warrior: rage only")
end)

-- options-layout.md "The five groups".
local GROUPS = {
	feedGroupItems = { "feedLoot", "feedMoney", "feedCraft" },
	feedGroupXP    = { "feedXP", "feedLevelSummary", "feedQuests", "feedResting" },
	feedGroupRep   = { "feedRep", "feedSkill" },
	feedGroupNew   = { "feedDiscovery", "feedSpells", "feedCollections" },
	feedGroupWarn  = { "feedBags", "feedGear" },
}

H.test("a feed group is checked only when every kind in it is on, and a click sets them all", function()
	local w = ClassWorld("MAGE")
	local db = w.env.HUDiniDB
	local seen = 0
	for name, kinds in pairs(GROUPS) do
		local g = w.vars["HUDini_" .. name]
		H.ok(g and g.proxy, name .. " is a proxy, not a saved value")
		H.eq(db[name], nil, name .. " saves nothing")
		H.eq(g.get(), true, name .. ": every kind is on by default")

		-- A click writes through each kind's own setting, so the kind's row
		-- repaints and its callback queues the Apply. A kind already right
		-- gets no write.
		local function Written()
			local out = {}
			for _, wr in ipairs(w.writes) do out[#out + 1] = wr.variable .. "=" .. tostring(wr.value) end
			w.writes = {}
			return table.concat(out, ", ")
		end
		db[kinds[1]] = false
		H.eq(g.get(), false, name .. ": one kind off shows it unchecked")
		w.writes = {}
		g.set(true)
		for _, k in ipairs(kinds) do H.eq(db[k], true, name .. " on turns " .. k .. " on") end
		H.eq(Written(), "HUDini_" .. kinds[1] .. "=true", name .. " on writes only the kind that was off")
		g.set(false)
		for _, k in ipairs(kinds) do H.eq(db[k], false, name .. " off turns " .. k .. " off") end
		local want = {}
		for i, k in ipairs(kinds) do want[i] = "HUDini_" .. k .. "=false" end
		H.eq(Written(), table.concat(want, ", "), name .. " off writes each kind through its setting")
		seen = seen + #kinds
	end
	H.eq(seen, 14, "the five groups hold the 14 kinds")
end)

H.test("a kind row repaints its group, and the group's own change repaints nothing", function()
	local w = ClassWorld("MAGE")
	for name, kinds in pairs(GROUPS) do
		for _, k in ipairs(kinds) do
			local before = w.notified["HUDini_" .. name]
			for _, fn in ipairs(w.callbacks["HUDini_" .. k]) do fn() end
			H.eq(w.notified["HUDini_" .. name], before + 1, k .. " repaints " .. name)
		end
		local total = 0
		for _, n in pairs(w.notified) do total = total + n end
		for _, fn in ipairs(w.callbacks["HUDini_" .. name]) do fn() end
		local after = 0
		for _, n in pairs(w.notified) do after = after + n end
		H.eq(after, total, name .. "'s own callback repaints no other row")
	end
end)

--------------------------------------------------------------------------------
-- The Style dropdown (TICK-0016)
--------------------------------------------------------------------------------

local FIVE = { "showXP", "showTargetPower", "showFeed", "feedQuestProgress", "feedUpgrade" }

local function Values(choices)
	local out = {}
	for _, c in ipairs(choices()) do out[#out + 1] = c[1] end
	return table.concat(out, ", ")
end

H.test("Style is the first row of the HUDini page, a proxy that saves nothing", function()
	local w = ClassWorld("MAGE")
	local first = w.pages.HUDini[1]
	H.eq(first.variable, "HUDini_style", "the first row")
	H.ok(first.choices, "it is a dropdown")
	H.ok(w.vars.HUDini_style.proxy, "a proxy")
	H.eq(w.env.HUDiniDB.style, nil, "no style name is saved")
end)

H.test("Style shows the matching style, or Custom, and lists Custom only then", function()
	local w = ClassWorld("MAGE")
	local db, style = w.env.HUDiniDB, w.vars.HUDini_style
	local choices = w.pages.HUDini[1].choices
	H.eq(style.get(), "standard", "a new install is Standard")
	H.eq(Values(choices), "minimal, standard, leveling", "no Custom while a style matches")
	for _, c in ipairs(choices()) do H.ok(c[3] and c[3] ~= "", c[1] .. " has a choice tooltip") end
	db.showXP = false
	H.eq(style.get(), "custom", "one of the five changed by hand")
	H.eq(Values(choices), "minimal, standard, leveling, custom", "Custom is listed while it is true")
end)

H.test("Run setup: the row under Style, a button that opens setup and nothing more", function()
	local w, ns = ClassWorld("MAGE")
	local row = w.pages.HUDini[2]
	H.eq(row.button, "Run setup", "the second row is the Run setup button")
	H.eq(row.tooltip, "Open setup from the beginning, keeping your current choices.", "the tooltip")
	local opened, applies = 0, 0
	ns.OpenSetup = function(...)
		opened = opened + 1
		H.eq(select("#", ...), 0, "setup opens on page 1: no argument")
	end
	rawset(ns.HUDini, "QueueApply", function() applies = applies + 1 end)
	local before = #w.writes
	row.click()
	H.eq(opened, 1, "a click opens setup once")
	H.eq(#w.writes, before, "a click saves nothing")
	H.eq(applies, 0, "a click queues no apply")
end)

H.test("Show minimap button: the row under Run setup, on by default, and a change applies", function()
	local w, ns = ClassWorld("MAGE")
	local row, v = w.pages.HUDini[3], w.vars.HUDini_minimapButton
	H.eq(row.variable, "HUDini_minimapButton", "the third row is the minimap button checkbox")
	H.eq(v.label, "Show minimap button", "the label")
	H.eq(row.tooltip, "Show HUDini's minimap button. Left-click for Options; right-click for setup. You can also use /hud or /hud setup.", "the tooltip, as in copy-sheet.md")
	H.eq(v.key, "minimapButton", "it saves minimapButton")
	H.eq(v.tbl, w.env.HUDiniDB, "in HUDiniDB")
	H.eq(ns.defaults.minimapButton, true, "Defaults turns it on")
	H.eq(w.pages.HUDini[4].button, "About HUDini", "About HUDini stays under it")
	local applies = 0
	rawset(ns.HUDini, "QueueApply", function() applies = applies + 1 end)
	H.eq(#(w.callbacks.HUDini_minimapButton or {}), 1, "one change callback")
	w.callbacks.HUDini_minimapButton[1]()
	H.eq(applies, 1, "a change queues an apply, which shows or hides the button")
end)

H.test("Flair: the last row of the HUDini page, under Advanced, Light, Modest and Full", function()
	local w = ClassWorld("MAGE")
	local rows, flair, advanced = w.pages.HUDini, nil, nil
	for i, r in ipairs(rows) do
		if r.header == "Advanced" then advanced = i end
		if r.variable == "HUDini_flair" then flair = i end
	end
	H.eq(flair, #rows, "Flair is the last row")
	H.eq(advanced, #rows - 1, "right under the Advanced header")
	local row, f = rows[flair], w.vars.HUDini_flair
	H.eq(f.label, "Guide's flair", "the label")
	H.eq(row.tooltip, "Choose brief, conversational, or more theatrical explanations. Features behave the same at every level.", "the tooltip")
	H.eq(Values(row.choices), "0, 1, 2", "the values")
	local names, tips = {}, {}
	for _, c in ipairs(row.choices()) do names[#names + 1], tips[#tips + 1] = c[2], c[3] end
	H.eq(table.concat(names, ", "), "Light, Modest, Full", "the names")
	local T = w.ns.TEXT[0]
	H.eq(table.concat(tips, " / "), table.concat({ T["opt.flair.0.tip"], T["opt.flair.1.tip"], T["opt.flair.2.tip"] }, " / "),
		"the tooltips: what each level does")
	for level = 0, 2 do
		H.ok(tips[level + 1] ~= T["flair." .. level .. ".tip"], "not setup's page 1 line at level " .. level)
	end
	H.eq(f.default, 0, "Defaults sets Light")
end)

H.test("Flair: shows the level HUDini reads, and a pick saves it and prints at that level", function()
	local w, ns = ClassWorld("MAGE")
	local db, f = w.env.HUDiniDB, w.vars.HUDini_flair
	H.eq(f.get(), 0, "a new install: Light")
	f.set(2)
	H.eq(db.flair, 2, "Full is saved")
	H.eq(ns.Text("why.unlocked"), ns.TEXT[2]["why.unlocked"], "the next line is at Full")
	f.set(1)
	H.eq(f.get(), 1, "Modest")
	for _, bad in ipairs({ 5, -1, "2", 1.5 }) do
		db.flair = bad
		H.eq(f.get(), 0, "a saved " .. tostring(bad) .. " shows as Light")
	end
	H.eq(#(w.callbacks.HUDini_flair or {}), 1, "one change callback")
	local applies = 0
	rawset(ns.HUDini, "QueueApply", function() applies = applies + 1 end)
	w.callbacks.HUDini_flair[1]()
	H.eq(applies, 0, "a change queues no apply")
end)

-- The game calls a function default or name inside its own secure
-- settings handler, not through securecallfunction (Blizzard_Setting.lua
-- :1-17, :31-47, :337-340). HUDini's code there tainted Edit Mode: a
-- bisect named the Style dropdown's function default, 9f9cfb2 (TICK-0089).
H.test("no proxy setting has a function default or a label that is not text (TICK-0089)", function()
	for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
		"SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
		local w = PanelWorld(class)
		local bad, n = {}, 0
		for name, v in pairs(w.vars) do
			if v.proxy then
				n = n + 1
				if type(v.default) == "function" then bad[#bad + 1] = name .. " default" end
				if type(v.label) ~= "string" then bad[#bad + 1] = name .. " label" end
			end
		end
		table.sort(bad)
		H.eq(n > 10, true, class .. ": the proxy settings were registered")
		H.eq(table.concat(bad, ", "), "", class .. ": proxy settings with a function default or a label not text")
	end
end)

H.test("the Style row has no default, so Defaults applies no style", function()
	local w = ClassWorld("MAGE")
	local db, style = w.env.HUDiniDB, w.vars.HUDini_style
	H.eq(style.default, nil, "no default: SetValueToDefault returns false")
	for _, name in ipairs({ "minimal", "leveling", "standard" }) do
		style.set(name)
		H.eq(style.get(), name, name .. ": the row shows the style")
	end
	db.feedUpgrade = true
	H.eq(style.get(), "custom", "Custom")
end)

H.test("picking a style writes its five settings and repaints their rows", function()
	local w = ClassWorld("MAGE")
	local db, ns, style = w.env.HUDiniDB, w.ns, w.vars.HUDini_style
	for _, name in ipairs({ "minimal", "leveling", "standard" }) do
		local before = {}
		for _, k in ipairs(FIVE) do before[k] = w.notified["HUDini_" .. k] end
		style.set(name)
		H.eq(style.get(), name, name .. " shows as picked")
		for _, k in ipairs(FIVE) do
			H.eq(db[k], ns.styles[name][k], name .. " sets " .. k)
			H.eq(w.notified["HUDini_" .. k], before[k] + 1, name .. " repaints the " .. k .. " row")
		end
	end
	local scale, notified = db.scale, w.notified.HUDini_showXP
	db.showXP = false
	style.set("custom")
	H.eq(db.showXP, false, "Custom changes nothing")
	H.eq(w.notified.HUDini_showXP, notified, "Custom repaints nothing")
	H.eq(db.scale, scale, "a style leaves the scale alone")
end)

H.test("a row a style sets repaints Style, and Style's own change repaints nothing", function()
	local w = ClassWorld("MAGE")
	for _, k in ipairs(FIVE) do
		local before = w.notified.HUDini_style
		for _, fn in ipairs(w.callbacks["HUDini_" .. k]) do fn() end
		H.eq(w.notified.HUDini_style, before + 1, k .. " repaints Style")
	end
	local before = w.notified.HUDini_style
	for _, fn in ipairs(w.callbacks.HUDini_scale) do fn() end
	H.eq(w.notified.HUDini_style, before, "Scale is not a style row")
	local total = 0
	for _, n in pairs(w.notified) do total = total + n end
	for _, fn in ipairs(w.callbacks.HUDini_style) do fn() end
	local after = 0
	for _, n in pairs(w.notified) do after = after + n end
	H.eq(after, total, "Style's own callback repaints no row")
end)

H.test("every gray row has a row that grays it again", function()
	for _, class in ipairs(CLASSES) do
		local w = PanelWorld(class)
		local gray = 0
		for _, page in ipairs(PAGES) do
			for _, r in ipairs(w.pages[page]) do
				if r.when then
					gray = gray + 1
					local name = class .. ": " .. page .. ": " .. tostring(r.variable)
					local tip = r.tooltip or ""
					local last = tip:match("^.*%. (.-)$") or tip
					-- A row for one class only names the class, and no row re-grays
					-- it: your class never changes while the panel is open (TICK-0108).
					-- The copy of D-029 (TICK-0134) drops the "Only with <row>."
					-- last sentence, so only the structure is checked: a row
					-- re-grays it, unless it is a row for one class only.
					local classOnly = #r.regray == 0 and r.variable == "HUDini_showTotems"
					H.ok(classOnly or #r.regray > 0, name .. ": a row re-grays it (" .. last .. ")")
				end
			end
		end
		H.ok(gray >= 40, class .. ": " .. gray .. " gray rows checked")
	end
end)

--------------------------------------------------------------------------------
-- The Your class page (TICK-0018)
--------------------------------------------------------------------------------

local CLASS_ROWS = {
	"HUDini_class_interrupt", "HUDini_class_dispel_Curse", "HUDini_class_dispel_Poison",
	"HUDini_class_dispel_Disease", "HUDini_class_dispel_Magic", "HUDini_class_purge",
	"HUDini_class_keepUp", "Clear learned buffs", "HUDini_class_keepUpSound", "HUDini_class_resource",
	"HUDini_class_resourceStacks",
}

-- A Mage with these spells on its action bars. Counterspell is ID 2139.
local function MageWorld(bars)
	local w, ns = ClassWorld("MAGE")
	ns.ActionBarSpells = function() return bars or { "Arcane Missiles", "Counterspell", "Fireball" } end
	ns.KnownSpell = function() return false end
	w.env.C_Spell.GetSpellName = function(id) return id == 2139 and "Counterspell" or nil end
	return w, ns, w.env.HUDiniDB.classes.MAGE
end

-- A Mage with the sound API's list and defaults (TICK-0167), stubbed
-- before the panel is built; w.played lists each sound played.
local function SoundWorld()
	-- The defaults are read when the page is built, so they go in first;
	-- the addon's own list and player, if any, load over the stubs, so
	-- those go in again after.
	local played = {}
	local function Stub(w)
		w.ns.AlertSounds = function() return { "readyCheck", "raidWarning", "mapPing" } end
		w.ns.READY_SOUND_DEFAULT, w.ns.MISSING_SOUND_DEFAULT = "readyCheck", "raidWarning"
		w.ns.PlayAlertSound = function(k) played[#played + 1] = k; return 1 end
	end
	local p, ns = ClassWorld("MAGE", nil, Stub)
	Stub(p)
	p.played = played
	return p, ns
end

-- The page's row of one setting.
local function ClassRow(w, variable)
	for _, r in ipairs(w.pages["Your class"]) do
		if r.variable == variable then return r end
	end
end

local function Labels(choices)
	local out = {}
	for _, c in ipairs(choices()) do out[#out + 1] = c[2] end
	return table.concat(out, ", ")
end

H.test("Your class: the class name, the same 11 rows on every class, then Bell sound and Cooldowns under Advanced", function()
	for _, class in ipairs(CLASSES) do
		local w = PanelWorld(class)
		local rows = w.pages["Your class"]
		H.eq(rows[1].header, w.className, class .. ": the header is the class name")
		H.eq(rows[1].tooltip, "Ability and resource choices are shared by characters of this class.", class .. ": the header tooltip")
		-- The character knows none of the class file's cooldown spells yet:
		-- no cooldown row and no Cooldowns header (TICK-0201).
		local want = {}
		for _, v in ipairs(CLASS_ROWS) do want[#want + 1] = v end
		want[#want + 1] = "HUDini_class_readySound"
		local function Got()
			local got, headers = {}, {}
			for i, r in ipairs(rows) do
				if r.row then got[#got + 1] = r.variable or r.button end
				if r.header and i > 1 then headers[#headers + 1] = r.header end
			end
			return table.concat(got, ", "), table.concat(headers, ", ")
		end
		local T = w.ns.TEXT[0]
		local sections = { T["opt.head.interrupt"], T["opt.head.dispel"], T["opt.head.purge"],
			T["opt.head.buffs"], T["opt.head.resource"], T["opt.head.advanced"] }
		local got, headers = Got()
		H.eq(got, table.concat(want, ", "), class .. ": the rows, none for an unknown spell")
		H.eq(headers, table.concat(sections, ", "), class .. ": the sections")
		-- Learn every spell of the class file and open the options: one
		-- dropdown per spell (TICK-0157, TICK-0158), in the class file's
		-- order, under Cooldowns, after Bell sound (TICK-0167).
		local all, classCount = w.ns.ReadyAlertSpells()
		H.ok(classCount > 0, class .. ": the class file offers a cooldown spell")
		w.ns.KnownSpell = function() return true end
		w.ns.AddMoreSpellRows()
		for i = 1, classCount do
			want[#want + 1] = "HUDini_class_cooldown_" .. all[i]:gsub("[^%w]", "")
			local v = w.vars[want[#want]]
			H.ok(v and v.proxy, class .. ": " .. all[i] .. " is a proxy row")
		end
		sections[#sections + 1] = T["opt.head.cooldowns"]
		got, headers = Got()
		H.eq(got, table.concat(want, ", "), class .. ": the rows")
		H.eq(headers, table.concat(sections, ", "), class .. ": the sections")
		for _, r in ipairs(rows) do
			if r.row then H.ok(r.tooltip and r.tooltip ~= "", class .. ": " .. (r.variable or r.button) .. " has a tooltip") end
		end
		local v = w.vars.HUDini_class_interrupt
		H.ok(v and v.proxy, class .. ": a proxy row")
	end
end)

H.test("Your class: a spell row lists Class default, None, the action-bar spells, then your pick", function()
	local w, ns, mine = MageWorld()
	local D, N = ns.PICK_DEFAULT, ns.PICK_NONE
	local interrupt = ClassRow(w, "HUDini_class_interrupt").choices
	H.eq(Values(interrupt), D .. ", " .. N .. ", Arcane Missiles, Counterspell, Fireball", "the interrupt choices")
	H.eq(Labels(interrupt), "Class default: Counterspell, None, Arcane Missiles, Counterspell, Fireball", "their labels")
	H.eq(Labels(ClassRow(w, "HUDini_class_dispel_Curse").choices):match("^[^,]*"), "Class default: Remove Lesser Curse", "Curse")
	H.eq(Labels(ClassRow(w, "HUDini_class_dispel_Poison").choices):match("^[^,]*"), "Class default: none", "Poison: none in the class file")
	H.eq(Labels(ClassRow(w, "HUDini_class_purge").choices):match("^[^,]*"), "Class default: Spellsteal", "Enemy buffs you can remove")
	H.eq(Labels(ClassRow(w, "HUDini_class_keepUp").choices):match("^[^,]*"), "Class default: not yet learned", "Combat buff, none known")
	ns.KnownSpell = function(spell) return spell == "Mana Shield" end
	H.eq(Labels(ClassRow(w, "HUDini_class_keepUp").choices):match("^[^,]*"), "Class default: Mana Shield", "Combat buff, the first known")
	H.eq(Labels(ClassRow(w, "HUDini_class_resource").choices):match("^[^,]*"), "Class default: none", "Resource: a mage has none")

	-- A pick saves the name; one off the bars stays listed, an ID with its name.
	w.vars.HUDini_class_interrupt.set("Fireball")
	H.eq(mine.interrupt, "Fireball", "a pick saves the name")
	H.eq(w.vars.HUDini_class_interrupt.get(), "Fireball", "and shows as picked")
	mine.interrupt = 2139
	H.eq(Labels(interrupt), "Class default: Counterspell, None, Arcane Missiles, Counterspell, Fireball, 2139 (Counterspell)", "an ID")
	mine.interrupt = "Frostbolt"
	H.eq(Labels(interrupt):match("[^,]*$"), " Frostbolt", "a spell taken off the bars")
	w.vars.HUDini_class_interrupt.set(N)
	H.eq(mine.interrupt, false, "None")
	H.eq(Values(interrupt), D .. ", " .. N .. ", Arcane Missiles, Counterspell, Fireball", "None is not listed twice")
	w.vars.HUDini_class_interrupt.set(D)
	H.eq(mine.interrupt, nil, "Class default clears the pick")
end)

-- TICK-0094 (D-019): an action-bar spell says nothing about its buff's
-- stacks, so Resource lists only the buffs HUDini saw stack on you.
H.test("Your class: Resource lists no action-bar spell, only the buffs seen to stack, then your pick", function()
	local w, ns, mine = MageWorld()
	local D, N = ns.PICK_DEFAULT, ns.PICK_NONE
	local resource = ClassRow(w, "HUDini_class_resource").choices
	H.eq(Values(resource), D .. ", " .. N, "none seen yet: Class default and None only")
	mine.stackBuffs = { ["Clearcasting"] = 2, ["Arcane Blast"] = 4, ["Zeal"] = 3,
		["Kindling"] = 5, ["Enrage"] = 2, ["Tidal Wave"] = 2, ["Bloodlust Stack"] = 10 }
	H.eq(Values(resource), D .. ", " .. N .. ", Arcane Blast, Bloodlust Stack, Clearcasting, Enrage, Kindling, Tidal Wave, Zeal",
		"the buffs seen to stack, A to Z")
	mine.stackBuffs = { ["Clearcasting"] = 2, ["Arcane Blast"] = 4 }
	H.eq(Values(ClassRow(w, "HUDini_class_interrupt").choices), D .. ", " .. N .. ", Arcane Missiles, Counterspell, Fireball",
		"the other rows still list the action-bar spells")
	-- A pick from before stays listed, so it is not lost without a word.
	mine.resource = { aura = "Fireball", max = 5 }
	H.eq(Values(resource), D .. ", " .. N .. ", Arcane Blast, Clearcasting, Fireball", "an old pick comes last")
end)

H.test("Your class: a saved spell ID shows as typed when its name is secret or the game throws", function()
	local w, ns, mine = MageWorld()
	local interrupt = ClassRow(w, "HUDini_class_interrupt").choices
	mine.interrupt = 2139
	w.env.C_Spell.GetSpellName = function() return "SecretName" end
	ns.IsSecret = function(v) return v == "SecretName" end
	local ok, labels = pcall(Labels, interrupt)
	H.ok(ok, "a secret name: no error")
	H.eq(ok and labels:match("[^,]*$"), " 2139", "a secret name: the ID only")
	w.env.C_Spell.GetSpellName = function() error("not now") end
	ok, labels = pcall(Labels, interrupt)
	H.ok(ok, "the game throws: no error")
	H.eq(ok and labels:match("[^,]*$"), " 2139", "the game throws: the ID only")
end)

H.test("Your class: a list shows as typed, and a power as the game names it", function()
	local w, ns = ClassWorld("WARRIOR")
	ns.ActionBarSpells = function() return { "Heroic Strike" } end
	local mine = w.env.HUDiniDB.classes.WARRIOR
	local interrupt = ClassRow(w, "HUDini_class_interrupt").choices
	H.eq(Labels(interrupt), "Class default: Pummel, Shield Bash, None, Heroic Strike", "the class file's list")
	mine.interrupt = { "Pummel", "Shield Bash" }
	H.eq(Labels(interrupt), "Class default: Pummel, Shield Bash, None, Heroic Strike, Pummel, Shield Bash", "a saved list, never a table")
	H.ok(not Labels(interrupt):find("table:"), "no raw table")

	local w2, ns2 = ClassWorld("ROGUE")
	ns2.ActionBarSpells = function() return {} end
	w2.env.COMBO_POINTS = "Combo Points"
	H.eq(Labels(ClassRow(w2, "HUDini_class_resource").choices), "Class default: Combo Points, None", "a Rogue's resource")
	local w3, ns3 = ClassWorld("HUNTER")
	ns3.ActionBarSpells = function() return {} end
	H.eq(Labels(ClassRow(w3, "HUDini_class_interrupt").choices), "Class default: none, None", "no interrupt in the class file")
end)

H.test("Your class: each row's default is Class default, so Defaults resets this class only", function()
	local w, ns, mine = MageWorld()
	local db = w.env.HUDiniDB
	db.classes.WARRIOR = { interrupt = "Pummel" }
	for _, v in ipairs({ "interrupt", "purge", "keepUp", "resource", "dispel_Curse", "dispel_Magic" }) do
		w.vars["HUDini_class_" .. v].set("Fireball")
	end
	w.vars.HUDini_class_resourceStacks.set(8)
	H.eq(mine.resource.max, 8, "stacks saved")
	-- What a page's Defaults does: the setter, for each row off its default.
	for _, name in ipairs(CLASS_ROWS) do
		local v = w.vars[name]
		if v then
			-- A nil default: SetValueToDefault returns false, no setter.
			if v.default ~= nil and v.get() ~= v.default then v.set(v.default) end
		end
	end
	for _, v in ipairs({ "interrupt", "purge", "keepUp", "resource", "dispel" }) do
		H.eq(mine[v], nil, v .. " back to Class default")
	end
	H.eq(db.classes.WARRIOR.interrupt, "Pummel", "another class keeps its pick")
	for _, name in ipairs(CLASS_ROWS) do
		local v = w.vars[name]
		if v and name ~= "HUDini_class_resourceStacks" and name ~= "HUDini_class_keepUpSound" then
			H.eq(v.default, ns.PICK_DEFAULT, name .. ": the default")
		end
	end
	H.eq(w.vars.HUDini_class_keepUpSound.default, "off", "Sound when a buff is missing: Off by default")
	local stacks = w.vars.HUDini_class_resourceStacks
	H.eq(stacks.default, nil, "Stacks to fill: no default, so Defaults calls no setter")
	mine.resource = { aura = "Fireball", max = 7 }
	H.eq(stacks.get(), 7, "it keeps its value")
end)

H.test("Your class: Stacks to fill is gray unless Resource is a spell you picked", function()
	local w, ns, mine = MageWorld()
	local row = ClassRow(w, "HUDini_class_resourceStacks")
	local stacks, resource = w.vars.HUDini_class_resourceStacks, w.vars.HUDini_class_resource
	H.ok(row.when, "it has a gray predicate")
	H.eq(table.concat(row.regray, ","), "HUDini_class_resource", "Resource re-grays it")
	H.eq(row.when(), false, "Class default: gray")
	H.eq(stacks.get(), 5, "it shows 5")
	local before = w.notified.HUDini_class_resourceStacks
	resource.set("Arcane Missiles")
	H.eq(row.when(), true, "a picked spell: active")
	H.eq(w.notified.HUDini_class_resourceStacks, before + 1, "the pick repaints Stacks to fill")
	stacks.set(12)
	H.eq(mine.resource.max, 12, "the stacks are saved")
	stacks.set(30)
	H.eq(mine.resource.max, 20, "at most 20")
	resource.set(ns.PICK_NONE)
	H.eq(row.when(), false, "None: gray")
	H.eq(w.notified.HUDini_class_resourceStacks, before + 2, "None repaints it too")
end)

H.test("Your class: a pick applies once, and repaints no other row", function()
	local w = MageWorld()
	for _, name in ipairs(CLASS_ROWS) do
		if w.vars[name] then
			H.eq(#w.callbacks[name], 1, name .. ": one callback, the Apply")
		end
	end
	local total = 0
	for _, n in pairs(w.notified) do total = total + n end
	w.vars.HUDini_class_interrupt.set("Fireball")
	w.vars.HUDini_class_dispel_Curse.set("Fireball")
	for _, fn in ipairs(w.callbacks.HUDini_class_interrupt) do fn() end
	local after = 0
	for _, n in pairs(w.notified) do after = after + n end
	H.eq(after, total, "no row repainted")
end)

H.test("Your class: Forget tracked buffs clears this class's tracked buffs only", function()
	local w = MageWorld()
	local db = w.env.HUDiniDB
	db.classes.MAGE.buffSpells = { ["Arcane Intellect"] = true, ["Frost Armor"] = true }
	db.classes.PRIEST = { buffSpells = { ["Inner Fire"] = true } }
	local button
	for _, r in ipairs(w.pages["Your class"]) do
		if r.button == "Clear learned buffs" then button = r end
	end
	H.ok(button and button.click, "the button is there")
	local said = 0
	w.ns.Say = function() said = said + 1 end
	w.env.print = function() said = said + 1 end
	button.click()
	H.eq(next(db.classes.MAGE.buffSpells), nil, "the mage's are gone")
	H.ok(db.classes.PRIEST.buffSpells["Inner Fire"], "the priest's stay")
	H.eq(said, 0, "no chat line")
end)

H.test("the class alerts and the class resource bar: on every class, gray while it has none", function()
	local ALERTS = {
		{ "HUDini_glowOnKickable", "HUDini_class_interrupt" },
		{ "HUDini_warnKeepUp", "HUDini_class_keepUp" },
		{ "HUDini_warnDispel", "HUDini_class_dispel_Curse,HUDini_class_dispel_Poison,HUDini_class_dispel_Disease,HUDini_class_dispel_Magic" },
		{ "HUDini_showPurgeable", "HUDini_class_purge" },
	}
	local function Find(rows, variable)
		for _, r in ipairs(rows) do
			if r.variable == variable then return r end
		end
	end
	for _, class in ipairs(CLASSES) do
		local w = PanelWorld(class)
		for _, a in ipairs(ALERTS) do
			local r = Find(w.pages.Alerts, a[1])
			H.ok(r and r.when, class .. ": " .. a[1] .. " is built, with a gray predicate")
			H.eq(table.concat(r.regray, ","), a[2], class .. ": " .. a[1] .. " re-grays on its Your class rows")
		end
		local r = Find(w.pages.Bars, "HUDini_showResource")
		H.ok(r and r.when, class .. ": Class resource bar is built, with a gray predicate")
		H.eq(table.concat(r.regray, ","), "HUDini_class_resource", class .. ": Resource re-grays it")
		for _, h in ipairs(w.pages.Alerts) do
			H.ok(not (h.header or ""):find("knows no alert"), class .. ": no empty-class header")
		end
	end

	-- A pick on the Your class page changes the gray at once, with no /reload.
	local w, ns = ClassWorld("HUNTER")
	local kick = Find(w.pages.Alerts, "HUDini_glowOnKickable")
	H.eq(kick.when(), false, "a hunter has no interrupt: gray")
	w.vars.HUDini_class_interrupt.set("Scatter Shot")
	H.eq(kick.when(), true, "a picked spell: active")
	w.vars.HUDini_class_interrupt.set(ns.PICK_NONE)
	H.eq(kick.when(), false, "None: gray")

	local m, mns = MageWorld()
	local function When(page, variable) return Find(m.pages[page], variable).when() end
	H.eq(When("Alerts", "HUDini_glowOnKickable"), true, "a mage has the interrupt alert")
	m.vars.HUDini_class_interrupt.set(mns.PICK_NONE)
	H.eq(When("Alerts", "HUDini_glowOnKickable"), false, "a saved None: gray")
	m.vars.HUDini_class_keepUp.set(mns.PICK_NONE)
	H.eq(When("Alerts", "HUDini_warnKeepUp"), false, "a combat buff None: gray")
	H.eq(When("Alerts", "HUDini_warnDispel"), true, "a mage removes curses")
	m.vars.HUDini_class_dispel_Curse.set(mns.PICK_NONE)
	H.eq(When("Alerts", "HUDini_warnDispel"), false, "every dispel type None: gray")
	m.vars.HUDini_class_dispel_Magic.set("Fireball")
	H.eq(When("Alerts", "HUDini_warnDispel"), true, "one dispel type picked: active")
	H.eq(When("Bars", "HUDini_showResource"), false, "a mage has no resource: gray")
	m.vars.HUDini_class_resource.set("Arcane Missiles")
	H.eq(When("Bars", "HUDini_showResource"), true, "a picked resource: active")
	H.eq(Find(ClassWorld("ROGUE").pages.Bars, "HUDini_showResource").when(), true, "a rogue has combo points")
end)

H.test("Your class: Sound when a buff is missing, gray unless a buff reminder can show", function()
	-- With no ns.GetKeepUpSoundChoice (the developer's part), the row reads Off
	-- and a pick does nothing, with no error.
	local w = MageWorld()
	local row = ClassRow(w, "HUDini_class_keepUpSound")
	H.ok(row and row.when, "built, with a gray predicate")
	H.eq(table.concat(row.regray, ","), "HUDini_showHealth,HUDini_warnOwnBuff,HUDini_warnKeepUp", "re-grays on health and both reminders")
	w.ns.GetKeepUpSoundChoice, w.ns.SetKeepUpSound, w.ns.AlertSounds, w.ns.PlayAlertSound = nil, nil, nil, nil
	H.eq(w.vars.HUDini_class_keepUpSound.get(), "off", "no API yet: off")
	w.vars.HUDini_class_keepUpSound.set("raidWarning")
	H.eq(Labels(row.choices), "Off", "no API yet: only Off")

	-- A Shaman has no combat buff: Lightning Shield is a personal buff.
	for _, class in ipairs({ "SHAMAN", "MAGE" }) do
		local p = ClassWorld(class)
		local db = p.env.HUDiniDB
		local when = ClassRow(p, "HUDini_class_keepUpSound").when
		db.showHealth, db.warnOwnBuff, db.warnKeepUp = true, true, false
		H.eq(when(), true, class .. ": the personal buff reminder on: active")
		db.warnOwnBuff, db.warnKeepUp = false, true
		H.eq(when(), true, class .. ": the combat buff reminder on: active")
		db.warnKeepUp = false
		H.eq(when(), false, class .. ": both reminders off: gray")
		db.warnOwnBuff, db.showHealth = true, false
		H.eq(when(), false, class .. ": Show your health off: gray")
	end

	local m, mns = SoundWorld()
	local saved = "off"
	mns.GetKeepUpSoundChoice = function() return saved end
	mns.SetKeepUpSound = function(v)
		if v == saved then return false end
		saved = v
		return true
	end
	local v = m.vars.HUDini_class_keepUpSound
	H.eq(v.get(), "off", "off by default")
	H.eq(Labels(ClassRow(m, "HUDini_class_keepUpSound").choices),
		"Off, Ready check, Raid warning (default), Map ping", "Off, then each sound; the buff default is marked")
	v.set("mapPing")
	H.eq(saved, "mapPing", "a pick saves through ns.SetKeepUpSound")
	H.eq(v.get(), "mapPing", "and reads back through ns.GetKeepUpSoundChoice")
	H.eq(table.concat(m.played, ","), "mapPing", "a pick plays its sound once")
	v.set("mapPing")
	H.eq(#m.played, 1, "no change: no sound")
	v.set("off")
	H.eq(#m.played, 1, "Off plays nothing")
end)

H.test("every sound has a name at every flair level, not a raw key", function()
	-- The names are built at run time ("sound." .. key), so the locale
	-- check cannot see them. The eight keys of TICK-0167, and the list the
	-- code offers once it exists.
	local w = ClassWorld("MAGE")
	local keys = { "readyCheck", "raidWarning", "mapPing", "whisper", "bossEmote", "alarmClock", "pvpQueue", "coins" }
	for _, k in ipairs(w.ns.AlertSounds and w.ns.AlertSounds() or {}) do keys[#keys + 1] = k end
	for level = 0, 2 do
		w.env.HUDiniDB.flair = level
		for _, k in ipairs(keys) do
			local name = w.ns.Text("sound." .. k)
			H.ok(name ~= "sound." .. k and name ~= "", "level " .. level .. ": " .. k .. " has a name")
		end
	end
end)

H.test("Your class: Bell sound, under Advanced, picks one sound for every bell", function()
	-- With no ns.GetReadySound (the developer's part), the row shows no
	-- sound and a pick does nothing, with no error.
	local w = MageWorld()
	local row = ClassRow(w, "HUDini_class_readySound")
	H.ok(row and not row.when, "built, never gray")
	local default = w.ns.READY_SOUND_DEFAULT
	w.ns.GetReadySound, w.ns.SetReadySound, w.ns.PlayAlertSound = nil, nil, nil
	H.eq(w.vars.HUDini_class_readySound.get(), default, "no API yet: the default, if any")
	w.vars.HUDini_class_readySound.set("mapPing")

	local m, mns = SoundWorld()
	local saved
	mns.GetReadySound = function() return saved or mns.READY_SOUND_DEFAULT end
	mns.SetReadySound = function(k)
		if k == mns.GetReadySound() then return false end
		saved = k
		return true
	end
	local v = m.vars.HUDini_class_readySound
	H.eq(v.default, "readyCheck", "Defaults goes back to the bell default")
	H.ok(v.default ~= m.vars.HUDini_class_keepUpSound.default, "the two defaults differ")
	H.eq(v.get(), "readyCheck", "the default at the start")
	H.eq(Labels(ClassRow(m, "HUDini_class_readySound").choices),
		"Ready check (default), Raid warning, Map ping", "each sound, no Off; the bell default is marked")
	v.set("mapPing")
	H.eq(saved, "mapPing", "a pick saves through ns.SetReadySound")
	H.eq(v.get(), "mapPing", "and reads back")
	H.eq(table.concat(m.played, ","), "mapPing", "a pick plays its sound once")
	v.set("mapPing")
	H.eq(#m.played, 1, "no change: no sound")
end)

-- TICK-0025: every word in the panel comes from Locales/enUS.lua. A key
-- with no text comes back as the key, so a raw key on screen is a gap.
local function LooksLikeKey(s)
	return type(s) == "string" and s:match("^%l%w*%.[%w._]+$") ~= nil
end

H.test("no page, row, header, button or choice shows a raw key, at any flair level", function()
	for _, class in ipairs(CLASSES) do
		for level = 0, 2 do
			local w = PanelWorld(class)
			w.env.HUDiniDB.flair = level
			local where = class .. " flair " .. level .. ": "
			local n = 0
			local function Check(s, what)
				n = n + 1
				H.ok(not LooksLikeKey(s), where .. what .. " shows the key " .. tostring(s))
			end
			for _, page in ipairs(w.pageOrder) do
				Check(page, "a page name")
				for _, row in ipairs(w.pages[page]) do
					Check(row.header, page .. " header")
					Check(row.button, page .. " button")
					Check(row.tooltip, page .. " " .. tostring(row.variable or row.header or row.button))
					if row.choices then
						for _, c in ipairs(row.choices()) do
							Check(c[2], page .. " " .. tostring(row.variable) .. " choice")
							Check(c[3], page .. " " .. tostring(row.variable) .. " choice tooltip")
						end
					end
				end
			end
			for variable, v in pairs(w.vars) do Check(v.label, variable .. " label") end
			H.ok(n > 300, where .. n .. " texts read")
		end
	end
end)

-- TICK-0082: most tooltips have a Modest and a Full text. The Flair setter
-- writes the text at the new level into every row whose tooltip is a text
-- key, at once, also the dispel rows, whose tooltip joins in the kind.
H.test("every tooltip follows the Flair setting at once", function()
	local w, ns = ClassWorld("MAGE")
	local function At(level, key, ...)
		for l = level, 0, -1 do
			local s = ns.TEXT[l][key]
			if s then
				if select("#", ...) > 0 then return s:format(...) end
				return s
			end
		end
	end
	local function Tip(page, key)
		for _, r in ipairs(w.pages[page]) do
			if r.variable == "HUDini_" .. key then return r.tooltip end
		end
	end
	H.eq(Tip("HUDini", "hideWhenIdle"), At(0, "opt.hideWhenIdle.tip"), "level 0 words")
	for _, level in ipairs({ 1, 2, 0 }) do
		w.vars.HUDini_flair.set(level)
		H.eq(w.env.HUDiniDB.flair, level, "the setter saves level " .. level)
		local checked, flair = 0, 0
		for _, page in ipairs(w.pageOrder) do
			for _, r in ipairs(w.pages[page]) do
				local key = r.variable and r.variable:match("^HUDini_(.+)$")
				local tipKey = key and "opt." .. key .. ".tip"
				if tipKey and ns.TEXT[0][tipKey] then
					checked = checked + 1
					H.eq(r.tooltip, At(level, tipKey), page .. " " .. key .. " at level " .. level)
					if At(level, tipKey) ~= ns.TEXT[0][tipKey] then flair = flair + 1 end
				end
			end
		end
		H.ok(checked >= 60, checked .. " rows checked at level " .. level)
		if level == 2 then H.ok(flair >= 40, flair .. " rows with a Full text") end
		H.eq(Tip("Your class", "class_dispel_Curse"), At(level, "opt.class.dispel.tip", "Curse", "Curse", "Curse"),
			"the Curse row at level " .. level)
		if level == 2 then
			H.ok(Tip("HUDini", "hideWhenIdle") ~= At(0, "opt.hideWhenIdle.tip"), "level 2 words")
		end
	end
end)

-- A row that keeps its level 0 tooltip after a flair change is caught
-- here, whatever its kind (header, button, swatch, a joined-in value):
-- the panel switched to a level must read as the panel built at it.
H.test("every row's tooltip after a flair change matches a panel built at that level", function()
	for _, class in ipairs({ "MAGE", "ROGUE", "PRIEST" }) do
		local w, light = PanelWorld(class), PanelWorld(class)
		for _, level in ipairs({ 2, 1, 0 }) do
			w.vars.HUDini_flair.set(level)
			local built = PanelWorld(class, { flair = level })
			-- The kinds of row whose text changed, so the test is known to
			-- reach them: buttons, headers, swatches, setting rows.
			local kinds = {}
			for _, page in ipairs(w.pageOrder) do
				local a, b, z = w.pages[page], built.pages[page], light.pages[page]
				H.eq(#a, #b, class .. " " .. page .. ": rows at level " .. level)
				for i = 1, #a do
					local name = a[i].header or a[i].button or a[i].variable or tostring(i)
					H.eq(a[i].tooltip, b[i].tooltip, class .. " " .. page .. " " .. name .. " at level " .. level)
					if b[i].tooltip ~= z[i].tooltip then
						-- A color row is a button in this world (no CreateColorSwatch).
						local tip = tostring(z[i].tooltip)
						local kind = tip:find("^Choose .-color") and "swatch" or a[i].header and "header"
							or a[i].button and "button" or "setting"
						kinds[kind] = true
					end
				end
			end
			if level == 2 then
				for _, kind in ipairs({ "button", "swatch", "setting" }) do
					H.ok(kinds[kind], class .. ": a " .. kind .. " row has a Full text")
				end
			end
		end
	end
end)

-- The Hide when idle tooltip on the HUDini page.
local function IdleTip(w)
	for _, r in ipairs(w.pages.HUDini) do
		if r.variable == "HUDini_hideWhenIdle" then return r.tooltip end
	end
end

H.test("a flair pick in HUDini setup reaches the options' flair tooltips", function()
	local w, ns = ClassWorld("MAGE")
	w:runTimers()
	local win = w.env.HUDiniSetup
	H.ok(win and win:IsShown(), "setup opens for a new player")
	H.eq(IdleTip(w), ns.TEXT[0]["opt.hideWhenIdle.tip"], "level 0 before the pick")
	local full
	for _, r in ipairs(win.parts.rows) do
		if r:IsShown() and r.name:GetText() == ns.TEXT[0]["flair.2"] then full = r end
	end
	H.ok(full, "page 1 has the Full row")
	w:Run(full, "OnClick")
	H.eq(w.env.HUDiniDB.flair, 2, "the pick saves level 2")
	H.eq(IdleTip(w), ns.TEXT[2]["opt.hideWhenIdle.tip"], "level 2 with no /reload")
end)

H.test("/hud reset settings brings the flair tooltips back to level 0", function()
	local w, ns = ClassWorld("MAGE")
	w.vars.HUDini_flair.set(2)
	H.eq(IdleTip(w), ns.TEXT[2]["opt.hideWhenIdle.tip"], "level 2 after the setter")
	w:slash("/hud reset settings")
	w:slash("/hud reset yes")
	H.eq(ns.FlairLevel(), 0, "the reset sets flair to 0")
	H.eq(IdleTip(w), ns.TEXT[0]["opt.hideWhenIdle.tip"], "level 0 after the reset")
end)

H.test("Bars: Druid mana in forms is gray unless Power bar is on, and gray on any class but a druid", function()
	local function Row(w)
		for _, r in ipairs(w.pages.Bars) do
			if r.variable == "HUDini_showDruidMana" then return r end
		end
	end
	local w = ClassWorld("DRUID")
	local row = Row(w)
	H.ok(row and row.when, "a druid: the row has a gray predicate")
	H.eq(table.concat(row.regray, ","), "HUDini_showPower", "Power bar re-grays it")
	H.eq(row.when(), true, "a druid with Power bar on: active")
	w.env.HUDiniDB.showPower = false
	H.eq(row.when(), false, "Power bar off: gray")
	-- A class whose powers are MANA alone has no form with another power.
	for _, class in ipairs({ "MAGE", "PALADIN", "PRIEST", "SHAMAN", "WARLOCK", "WARRIOR" }) do
		local other = Row(ClassWorld(class))
		H.eq(other.when(), false, class .. ": gray")
	end
end)

-- D-024, TICK-0089: HUDini does not hide the gryphons. The Game frames page
-- has no Hide gryphons row; a header says Edit Mode hides them, and its
-- tooltip names Edit Mode's box at the flair level now.
H.test("Game frames: no Hide gryphons row; a header teaches Edit Mode's box, at every flair level", function()
	local w, ns = ClassWorld("MAGE")
	local T, box = ns.TEXT, ns.GryphonBoxName()
	local header
	for _, page in ipairs(w.pageOrder) do
		for _, row in ipairs(w.pages[page]) do
			H.ok(row.variable ~= "HUDini_hideGryphons", page .. ": no Hide gryphons row")
			if row.header == T[0]["opt.head.gryphons"] then header = row end
		end
	end
	H.ok(header, "the header is there")
	H.eq(header.tooltip, T[0]["opt.head.gryphons.tip"]:format(box))
	H.ok(header.tooltip:find(box, 1, true), "names the box")
	for level = 1, 2 do
		w.env.HUDiniDB.flair = level
		ns.RetextFlairTips()
		H.eq(header.tooltip, T[level]["opt.head.gryphons.tip"]:format(box), "level " .. level)
	end
end)

H.test("Your class: a cooldown row saves a bell, a timer bar or both for this class only", function()
	local w = ClassWorld("SHAMAN")
	local ns = w.ns
	ns.KnownSpell = function(spell) return spell == "Mana Tide Totem" end
	ns.AddMoreSpellRows()
	local row = w.vars.HUDini_class_cooldown_ManaTideTotem
	H.ok(row and row.proxy, "Mana Tide Totem has a row")
	H.eq(row.get(), "off", "off at the start")
	row.set("bell")
	H.eq(ns.GetReadyAlert("Mana Tide Totem"), true, "Bell turns the bell on")
	H.eq(ns.GetTimerBar("Mana Tide Totem"), false, "and no timer bar")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyAlerts["Mana Tide Totem"], true, "saved for the Shaman")
	H.eq(row.get(), "bell", "the row reads it back")
	row.set("bar")
	H.eq(ns.GetReadyAlert("Mana Tide Totem"), false, "Timer bar turns the bell off")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBars["Mana Tide Totem"], true, "and saves the bar for the Shaman")
	H.eq(row.get(), "bar", "the row reads the bar back")
	row.set("both")
	H.eq(ns.GetReadyAlert("Mana Tide Totem") and ns.GetTimerBar("Mana Tide Totem"), true, "Bell and timer bar turns both on")
	H.eq(row.get(), "both", "the row reads both back")
	row.set("off")
	H.eq(ns.GetReadyAlert("Mana Tide Totem") or ns.GetTimerBar("Mana Tide Totem"), false, "Off turns both off")
end)

-- Missing items (TICK-0182): a row only for a known spell (make, or one of
-- needs) or a saved pick, as the cooldown rows (TICK-0201). w.known[name]
-- makes a spell known; it can change after the panel is built.
local function ItemWorld(class, db)
	return ClassWorld(class, db, function(w)
		w.known = {}
		local ids, n = {}, 7000
		w.env.C_Spell.GetSpellInfo = function(name)
			if not ids[name] then n = n + 1; ids[name], ids[n] = n, name end
			return { spellID = ids[name] }
		end
		w.env.IsPlayerSpell = function(id) return w.known[ids[id]] == true end
	end)
end

local function Headers(rows, T, key)
	local n = 0
	for _, r in ipairs(rows) do
		if r.header == T[key] then n = n + 1 end
	end
	return n
end

H.test("Your class: no missing item row or header for an unknown spell; a learned one adds both at the next open", function()
	local w = ItemWorld("WARLOCK")
	local ns, rows, T = w.ns, w.pages["Your class"], w.ns.TEXT[0]
	H.eq(w.vars.HUDini_class_item_soulstone, nil, "Create Soulstone not known: no row")
	H.eq(w.vars.HUDini_class_item_soulShard, nil, "Summon Voidwalker not known: no row")
	H.eq(Headers(rows, T, "opt.head.items"), 0, "no Missing items header")
	local before = #rows
	w.known["Summon Voidwalker"] = true
	ns.AddMoreSpellRows()
	H.eq(rows[before + 1].header, T["opt.head.items"], "then the header, at the end")
	H.eq(rows[before + 2].variable, "HUDini_class_item_soulShard", "and the shard row")
	H.eq(#rows, before + 2, "no other row")
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 2, "the next open adds nothing")
	w.known["Create Soulstone"] = true
	ns.AddMoreSpellRows()
	H.eq(rows[before + 3].variable, "HUDini_class_item_soulstone", "a second learned row joins the group")
	H.eq(Headers(rows, T, "opt.head.items"), 1, "with no second header")
end)

H.test("Your class: a missing item known at the first open sits before Cooldowns", function()
	local w = ClassWorld("SHAMAN", nil, function(w)
		w.env.C_Spell.GetSpellInfo = function(name) return { spellID = name == "Reincarnation" and 20608 or 1 } end
		w.env.IsPlayerSpell = function(id) return id == 20608 end
	end)
	local ns, rows, T = w.ns, w.pages["Your class"], w.ns.TEXT[0]
	ns.KnownSpell = function() return true end
	ns.AddMoreSpellRows()
	local at = {}
	for i, r in ipairs(rows) do
		if r.header then at[r.header] = i end
		if r.variable then at[r.variable] = i end
	end
	H.ok(at.HUDini_class_readySound < at[T["opt.head.items"]], "after Bell sound")
	H.eq(at.HUDini_class_item_ankh, at[T["opt.head.items"]] + 1, "the Ankh row under its header")
	H.ok(at[T["opt.head.cooldowns"]] and at.HUDini_class_item_ankh < at[T["opt.head.cooldowns"]], "then Cooldowns")
end)

H.test("Your class: a saved missing item pick shows its row for an unknown spell", function()
	local w = ItemWorld("WARLOCK", { classes = { WARLOCK = { missingItem = { soulstone = true } } } })
	H.ok(w.vars.HUDini_class_item_soulstone ~= nil, "saved on: the row")
	H.eq(w.vars.HUDini_class_item_soulShard, nil, "not saved, not known: no row")
end)

H.test("Your class: a missing item row reads and saves the row's choice, gray with no health bar", function()
	local w = ItemWorld("SHAMAN")
	w.known.Reincarnation = true
	w.ns.AddMoreSpellRows()
	local ns = w.ns
	local row = w.vars.HUDini_class_item_ankh
	H.ok(row ~= nil, "the Ankh row")
	H.eq(row.get(), true, "on from the class file")
	row.set(false)
	H.eq(ns.GetMissingItem("ankh"), false, "the row turns it off")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.missingItem.ankh, false, "saved for the Shaman")
	H.eq(row.get(), false, "the row reads it back")
	local init
	for _, r in ipairs(w.pages["Your class"]) do
		if r.variable == "HUDini_class_item_ankh" then init = r end
	end
	H.ok(init and init.when, "gray unless")
	w.env.HUDiniDB.showHealth = false
	H.eq(init.when(), false, "gray with no health bar")
end)

H.test("Your class: Cooldowns, under Advanced, adds each new learned spell once", function()
	local w = ClassWorld("SHAMAN")
	local ns = w.ns
	local rows = w.pages["Your class"]
	local before = #rows
	local learned = { "Flame Shock", "Earth Shock" }
	ns.LearnedCooldownSpells = function() return learned end
	ns.KnownSpell = function() return false end
	ns.AddMoreSpellRows()
	local T = ns.TEXT[0]
	H.eq(rows[before - 1].header, T["opt.head.advanced"], "under Advanced")
	H.eq(rows[before].variable, "HUDini_class_readySound", "after Bell sound")
	H.eq(rows[before + 1].header, T["opt.head.cooldowns"], "then Cooldowns")
	H.eq(rows[before + 2].variable, "HUDini_class_cooldown_EarthShock", "A to Z: Earth Shock")
	H.eq(rows[before + 3].variable, "HUDini_class_cooldown_FlameShock", "then Flame Shock")
	H.eq(#rows, before + 3, "no other row")
	H.ok(not rows[before + 2].when, "a cooldown row is never gray")
	local row = w.vars.HUDini_class_cooldown_EarthShock
	H.eq(row.get(), "off", "off at the start")
	row.set("both")
	H.eq(ns.GetReadyAlert("Earth Shock") and ns.GetTimerBar("Earth Shock"), true, "a pick saves the bell and the bar")
	-- The next open adds only a new spell, at the end, with no second header.
	learned = { "Earth Shock", "Flame Shock", "Frost Shock" }
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 4, "one new row")
	H.eq(rows[before + 4].variable, "HUDini_class_cooldown_FrostShock", "the new spell at the end")
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 4, "an open with nothing new adds nothing")
	-- The game's path: the options open, and a spell learned since gets its row.
	learned[#learned + 1] = "Lava Lash"
	w:Run(w.env.SettingsPanel, "OnShow")
	H.eq(rows[#rows].variable, "HUDini_class_cooldown_LavaLash", "opening the options adds the new spell")
	H.eq(#rows, before + 5, "and only that one")
	-- Names with no letters of a-z (a ruRU client), or the same letters,
	-- each get a setting of their own: the game throws on a second one.
	learned[#learned + 1] = "Удар бури"
	learned[#learned + 1] = "Ледяной шок"
	learned[#learned + 1] = "Lava-Lash"
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 8, "three more rows, no error")
	-- In a fight the panel adds no row.
	learned[#learned + 1] = "Stormstrike"
	w.env.InCombatLockdown = function() return true end
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 8, "no row in a fight")
	-- A class file spell learned later joins the end of the group.
	w.env.InCombatLockdown = function() return false end
	ns.KnownSpell = function(spell) return spell == "Heroism" end
	ns.AddMoreSpellRows()
	H.eq(rows[#rows - 1].variable, "HUDini_class_cooldown_Heroism", "Heroism, learned, at the end, class spells first")
	H.eq(rows[#rows].variable, "HUDini_class_cooldown_Stormstrike", "then Stormstrike, learned in the fight")
	H.eq(#rows, before + 10, "two new rows")
end)

H.test("Your class: a class file with 13 cooldown spells keeps the top of the page inside 15 rows", function()
	-- A Priest's file names its own cooldowns and every race's racials
	-- (TICK-0175). Only the spells you know get a row, and those sit under
	-- Advanced (TICK-0201).
	local names = { "Power Infusion", "Inner Focus", "Fear Ward", "Desperate Prayer", "Elune's Grace",
		"Feedback", "Shadowguard", "Starshards", "Touch of Weakness", "Hex of Weakness",
		"Devouring Plague", "Psychic Scream", "Shadowfiend" }
	local w = ClassWorld("PRIEST")
	local ns = w.ns
	local rows = w.pages["Your class"]
	ns.ReadyAlertSpells = function()
		local out = {}
		for i, n in ipairs(names) do out[i] = n end
		return out, #names
	end
	ns.LearnedCooldownSpells = function() return {} end
	local known = { ["Inner Focus"] = true, ["Fear Ward"] = true, ["Psychic Scream"] = true }
	ns.KnownSpell = function(spell) return known[spell] or false end
	-- A bell saved for a spell you do not know keeps its row, so you can
	-- turn it off.
	w.env.HUDiniDB.classes.PRIEST = w.env.HUDiniDB.classes.PRIEST or {}
	w.env.HUDiniDB.classes.PRIEST.readyAlerts = { ["Starshards"] = true }
	ns.AddMoreSpellRows()
	local above, under, advanced = 0, {}, false
	for _, r in ipairs(rows) do
		if r.header == ns.TEXT[0]["opt.head.advanced"] then advanced = true end
		if r.row and not advanced then above = above + 1 end
		if r.row and advanced then under[#under + 1] = r.variable end
	end
	H.ok(above <= 15, above .. " rows above Advanced")
	H.eq(table.concat(under, ", "), "HUDini_class_readySound, HUDini_class_cooldown_InnerFocus, "
		.. "HUDini_class_cooldown_FearWard, HUDini_class_cooldown_Starshards, HUDini_class_cooldown_PsychicScream",
		"Bell sound, then the known and saved spells in the class file's order")
end)

H.test("the timer bar look: texture, text and color rows", function()
	local w = ClassWorld("MAGE")
	H.eq(w.env.HUDiniDB.timerBarTexture, "hud", "a new install follows the HUD's texture")
	H.eq(w.env.HUDiniDB.timerBarTime, "seconds", "a new install shows the time left")
	H.ok(w.vars.HUDini_timerBarTexture, "Timer bar texture has a row")
	H.ok(w.vars.HUDini_timerBarTime, "Timer bar text has a row")
	local color = w.vars.HUDini_color_timer
	H.ok(color and color.proxy, "the timer bar color has a row")
	local refreshed, saved = 0, nil
	w.ns.RefreshTimerBars = function() refreshed = refreshed + 1 end
	w.ns.SetColorHex = function(key, hex) saved = key .. " " .. hex end
	color.set("ffff0000")
	H.eq(saved, "timer ffff0000", "a pick saves the color")
	H.eq(refreshed, 1, "and repaints the timer bars")
	-- A new texture or text reaches a bar that shows now (TICK-0158 review).
	local function Pick(key, value)
		w.env.HUDiniDB[key] = value
		for _, fn in ipairs(w.callbacks["HUDini_" .. key]) do fn() end
	end
	Pick("timerBarTexture", "hud")
	H.eq(refreshed, 2, "a texture pick repaints the timer bars")
	Pick("timerBarTime", "percent")
	H.eq(refreshed, 3, "a text pick repaints the timer bars")
	-- The color sits under Advanced on the Colors page.
	local advanced
	for _, r in ipairs(w.pages.Colors) do
		if r.header == "Advanced" then advanced = true end
		if r.variable == "HUDini_color_timer" then H.ok(advanced, "under Advanced") end
	end
end)

H.test("Timer bar place: a button right after Timer bar text puts the bars back under the HUD", function()
	local w = ClassWorld("MAGE")
	local rows, at = w.pages.Bars, nil
	for i, r in ipairs(rows) do
		if r.variable == "HUDini_timerBarTime" then at = i end
	end
	local T = w.ns.TEXT[0]
	local row = rows[at + 1]
	H.eq(row.button, T["opt.timerBarPlace.button"], "the button, right after Timer bar text")
	H.ok(row.tooltip and row.tooltip:find("/hud unlock", 1, true), "the tip says how to move the bars")
	-- With no ns.ResetTimerBarsPlace, a click does nothing, with no error.
	w.ns.ResetTimerBarsPlace = nil
	row.click()
	local calls = 0
	w.ns.ResetTimerBarsPlace = function() calls = calls + 1; return true end
	row.click()
	H.eq(calls, 1, "a click puts the bars back")
end)
