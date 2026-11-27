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
local ROW_PENDING = {
}

-- Saved values a proxy row writes for them.
local PROXY = { growRight = "growToward", growDown = "growToward", auraMap = "auraMap" }

local PAGES = { "HUDini", "Icons", "Bars", "Textures", "Colors", "Alerts", "Your class", "Feed", "Game frames" }

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
			-- The game's layout gives its list itself (TICK-0243); here
			-- the page's rows stand for it.
			-- w.noList: a layout that gives no list.
			GetInitializers = function() return not w.noList and rows or nil end,
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
		-- A slider keeps its range: { low, high, step } (S.CreateSliderOptions).
		if type(getOptions) == "table" and rawget(getOptions, "range") then r.range = rawget(getOptions, "range") end
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
	S.CreateSliderOptions = function(low, high, step)
		local options = H.Fake()
		rawset(options, "range", { low, high, step })
		return options
	end
	-- A Cooldowns grid row (TICK-0203): the page keeps its data. A spell row
	-- is a row whose variable is its ready glow's, with the variables of its
	-- three controls; the column head row is { gridHead = true }.
	S.CreateElementInitializer = function(template, data)
		local init = H.Fake()
		rawset(init, "template", template)
		if data.grid then
			data.row = true
			data.variable = rawget(data.grid.glow, "variable")
			data.columns = { glow = rawget(data.grid.glow, "variable"), bar = rawget(data.grid.bar, "variable"),
				sound = rawget(data.grid.sound, "variable") }
		end
		-- A sound picker row (TICK-0233): a row named by its label, with
		-- its picker's bind.
		if data.sound then data.row = true end
		rawset(init, "data", data)
		data.tags = {}
		-- A texture button row (TICK-0225) grays as the game's rows do, and
		-- keeps its initializer, so a test can draw it on a frame.
		data.regray, data.init = {}, init
		rawset(init, "AddModifyPredicate", function(_, fn) data.when = fn end)
		rawset(init, "AddEvaluateStateCVar", function(_, v) data.regray[#data.regray + 1] = v end)
		rawset(init, "AddSearchTags", function(_, ...)
			for _, tag in ipairs({ ... }) do data.tags[#data.tags + 1] = tag end
		end)
		return init
	end
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

local AMMO_CLASS = { HUNTER = true, WARRIOR = true, ROGUE = true }

local CLASS_ROWS = {
	"HUDini_class_interrupt", "HUDini_class_dispel_Curse", "HUDini_class_dispel_Poison",
	"HUDini_class_dispel_Disease", "HUDini_class_dispel_Magic", "HUDini_class_purge",
	"HUDini_class_keepUp", "Clear learned buffs", "Sound when a buff is missing", "HUDini_class_keepUpRepeat", "HUDini_class_ammo", "HUDini_class_resource",
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

-- The page's sound picker row with this label (TICK-0233).
local function SoundRow(w, label)
	for _, r in ipairs(w.pages["Your class"]) do
		if r.sound and r.name == label then return r end
	end
end

local function Labels(choices)
	local out = {}
	for _, c in ipairs(choices()) do out[#out + 1] = c[2] end
	return table.concat(out, ", ")
end

H.test("Your class: the class name, 12 rows on every class (13 with ammo, one more with a pet), Sound alerts and Cooldowns under Advanced", function()
	for _, class in ipairs(CLASSES) do
		local w = PanelWorld(class)
		local rows = w.pages["Your class"]
		H.eq(rows[1].header, w.className, class .. ": the header is the class name")
		H.eq(rows[1].tooltip, "Ability and resource choices are shared by characters of this class.", class .. ": the header tooltip")
		-- The character knows none of the class file's cooldown spells yet:
		-- no cooldown row and no Cooldowns header (TICK-0201).
		local want = {}
		-- Only a class that can use a bow, gun or crossbow gets the ammo
		-- row (TICK-0241); a class whose file has a pet field gets the Pet
		-- row after it (TICK-0192).
		local ammo = AMMO_CLASS[class]
		local hasPet = type(w.ns.PetAlertData()) == "table"
		-- A class whose file has weaponBuff gets its row after Repeat
		-- (TICK-0251), and its sound last under Sound alerts.
		local weapon = w.ns.HasWeaponBuffAlert()
		for _, v in ipairs(CLASS_ROWS) do
			if v ~= "HUDini_class_ammo" or ammo then want[#want + 1] = v end
			if v == "HUDini_class_ammo" and hasPet then want[#want + 1] = "HUDini_class_pet" end
			if v == "HUDini_class_keepUpRepeat" and weapon then want[#want + 1] = "HUDini_class_weaponBuffAlert" end
		end
		-- Under Advanced, a sound row for each alert the class has
		-- (TICK-0233 step 2); a class with none (the Hunter) gets no section.
		local sounds = w.ns.ClassAlertSounds()
		for _, a in ipairs(sounds) do
			want[#want + 1] = w.ns.TEXT[0]["opt.class.sound." .. (a.dispel or a.alert)]
		end
		if weapon then want[#want + 1] = w.ns.TEXT[0]["opt.class.sound.weaponBuff"] end
		local function Got()
			local got, headers = {}, {}
			for i, r in ipairs(rows) do
				if r.row then got[#got + 1] = r.variable or r.button or r.name end
				if r.header and i > 1 then headers[#headers + 1] = r.header end
			end
			return table.concat(got, ", "), table.concat(headers, ", ")
		end
		local T = w.ns.TEXT[0]
		local sections = { T["opt.head.interrupt"], T["opt.head.dispel"], T["opt.head.purge"],
			T["opt.head.buffs"], T["opt.head.ammo"], T["opt.head.resource"], T["opt.head.advanced"], T["opt.head.soundAlerts"] }
		if hasPet then table.insert(sections, 6, T["opt.head.pet"]) end
		if not ammo then table.remove(sections, 5) end
		if #sounds == 0 and not weapon then table.remove(sections) end
		local got, headers = Got()
		H.eq(got, table.concat(want, ", "), class .. ": the rows, none for an unknown spell")
		H.eq(headers, table.concat(sections, ", "), class .. ": the sections")
		-- Learn every spell of the class file and open the options: one
		-- grid row per spell, with a ready glow, a timer bar and a sound
		-- (TICK-0203), in the class file's order, under Cooldowns and its
		-- column heads.
		local all, classCount = w.ns.ReadyAlertSpells()
		H.ok(classCount > 0, class .. ": the class file offers a cooldown spell")
		w.ns.KnownSpell = function() return true end
		w.ns.AddMoreSpellRows()
		for i = 1, classCount do
			local base = "HUDini_class_cooldown_" .. all[i]:gsub("[^%w]", "")
			want[#want + 1] = base .. "_glow"
			for _, part in ipairs({ "_glow", "_bar", "_sound" }) do
				local v = w.vars[base .. part]
				H.ok(v and v.proxy, class .. ": " .. all[i] .. " has a proxy " .. part)
				H.eq(v and v.default, nil, class .. ": " .. all[i] .. part .. ": no default")
			end
		end
		sections[#sections + 1] = T["opt.head.cooldowns"]
		got, headers = Got()
		H.eq(got, table.concat(want, ", "), class .. ": the rows")
		H.eq(headers, table.concat(sections, ", "), class .. ": the sections")
		for i, r in ipairs(rows) do
			if r.header == T["opt.head.cooldowns"] then
				H.ok(rows[i + 1].gridHead, class .. ": the column heads come right after the header")
			end
		end
		for _, r in ipairs(rows) do
			if r.row then H.ok(r.tooltip and r.tooltip ~= "", class .. ": " .. (r.variable or r.button or r.name) .. " has a tooltip") end
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
		if v and name ~= "HUDini_class_resourceStacks" and name ~= "HUDini_class_keepUpSound"
			and name ~= "HUDini_class_ammo" and name ~= "HUDini_class_keepUpRepeat" then
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
			-- Resource also re-grays the class resource bar's texture button,
			-- which repaints no setting (TICK-0225).
			local want = name == "HUDini_class_resource" and 2 or 1
			H.eq(#w.callbacks[name], want, name .. ": one callback, the Apply")
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

H.test("Your class: Defaults gives Sound when a buff is missing back to the class's start", function()
	-- A Mage whose class file starts the sound on (keepUpSoundOn).
	local w = ClassWorld("MAGE", nil, function(w)
		local load = w.load
		w.load = function(self, ...)
			local ns = load(self, ...)
			local mage = H.copy(Classes.profiles.MAGE)
			mage.keepUpSoundOn = true
			ns.RegisterClass("MAGE", mage)
			return ns
		end
	end)
	local ns, v = w.ns, w.vars.HUDini_class_keepUpSound
	H.eq(v.default, ns.MISSING_SOUND_DEFAULT, "a class whose sound starts on: Raid warning is the default")
	ns.SetKeepUpSound({ key = "mapPing", volume = 50 })
	v.set(v.default)
	H.eq(ns.ClassDB().keepUpSound, true, "Defaults saves the start: the default sound at full volume")
	v.set("off")
	H.eq(ns.ClassDB().keepUpSound, false, "Off saves false")
	-- A class whose sound starts off: Off is the default (MageWorld's file).
	local _, mns = MageWorld()
	H.eq(mns.ClassDefault("keepUpSoundOn"), nil, "the fixture's Mage starts it off")
end)

H.test("Your class: Sound when a buff is missing, a sound picker, gray unless a buff reminder can show", function()
	local w, ns = MageWorld()
	local T = ns.TEXT[0]
	local row = SoundRow(w, T["opt.class.keepUpSound"])
	H.ok(row, "a sound picker row (TICK-0233)")
	H.eq(row.tooltip, T["opt.class.keepUpSound.tip"], "the row's tip")
	H.eq(type(row.tooltip), "string", "a plain string, as the settings search reads it")
	local bind = row.sound
	H.eq(bind.default, "raidWarning", "Raid warning is its default")
	H.eq(bind.withOff, true, "Off is in the list")
	H.eq(bind.label, T["opt.class.keepUpSound"], "the picker's tooltip title")
	H.eq(bind.tip, T["opt.class.keepUpSound.tip"], "and body")
	H.ok(row.when, "the label grays")
	H.eq(row.when, bind.enabled, "with the rule that grays the picker")
	H.eq(table.concat(row.regray, ","), "HUDini_showHealth,HUDini_warnOwnBuff,HUDini_warnKeepUp", "re-grays on health and both reminders")
	H.ok(row.tooltip:find("Only with Show your health on", 1, true), "the tip names what turns it on")

	-- A Shaman has no combat buff: Lightning Shield is a personal buff.
	for _, class in ipairs({ "SHAMAN", "MAGE" }) do
		local p = ClassWorld(class)
		local db = p.env.HUDiniDB
		local when = SoundRow(p, T["opt.class.keepUpSound"]).sound.enabled
		db.showHealth, db.warnOwnBuff, db.warnKeepUp = true, true, false
		H.eq(when(), true, class .. ": the personal buff reminder on: active")
		db.warnOwnBuff, db.warnKeepUp = false, true
		H.eq(when(), true, class .. ": the combat buff reminder on: active")
		db.warnKeepUp = false
		H.eq(when(), false, class .. ": both reminders off: gray")
		db.warnOwnBuff, db.showHealth = true, false
		H.eq(when(), false, class .. ": Show your health off: gray")
	end

	-- The picker repaints when a setting of its gray rule changes.
	local repaints = 0
	ns.RepaintSoundPickers = function() repaints = repaints + 1 end
	for _, key in ipairs({ "showHealth", "warnOwnBuff", "warnKeepUp" }) do
		local before = repaints
		for _, fn in ipairs(w.callbacks["HUDini_" .. key]) do fn() end
		H.eq(repaints, before + 1, key .. ": the picker repaints")
	end

	-- The picker reads and writes the saved choice through Alerts.lua.
	local saved = false
	ns.GetKeepUpSoundValue = function() return saved end
	ns.SetKeepUpSound = function(v) saved = v; return true end
	H.eq(bind.get(), false, "Off")
	local c = { key = "mapPing", volume = 50 }
	bind.set(c)
	H.eq(saved, c, "a pick saves the choice, with its volume")
	H.eq(bind.get(), c, "and reads it back")
	bind.set(nil)
	H.eq(saved, false, "Off saves false")

	-- The proxy setting stays, for Defaults and HUDini setup's repaint by
	-- name; a change repaints the picker.
	local v = w.vars.HUDini_class_keepUpSound
	H.ok(v, "the setting stays")
	ns.GetKeepUpSoundChoice = function() return "off" end
	H.eq(v.get(), "off", "reads Off")
	v.set("off")
	H.eq(saved, "off", "Defaults writes Off through ns.SetKeepUpSound")
	local before = repaints
	for _, fn in ipairs(w.callbacks.HUDini_class_keepUpSound) do fn() end
	H.eq(repaints, before + 1, "a change repaints the picker")

	-- With no keep-up API (an older Alerts.lua), Off, and no error.
	ns.GetKeepUpSoundValue, ns.SetKeepUpSound, ns.GetKeepUpSoundChoice = nil, nil, nil
	H.eq(bind.get(), false, "no API: Off")
	bind.set(c)
	H.eq(v.get(), "off", "no API: the setting reads Off")
	v.set("raidWarning")

	-- A flair change retexts the row and the picker's tooltip.
	w.env.HUDiniDB.flair = 2
	ns.RetextFlairTips()
	H.eq(row.tooltip, ns.TEXT[2]["opt.class.keepUpSound.tip"], "the row's tip at Full")
	H.eq(bind.tip, ns.TEXT[2]["opt.class.keepUpSound.tip"], "the picker's tip at Full")
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

H.test("Your class: no Bell sound row; each cooldown row picks its own sound (TICK-0203)", function()
	local m, mns = SoundWorld()
	H.eq(m.vars.HUDini_class_readySound, nil, "no Bell sound row")
	local saved = {}
	mns.GetCooldownSound = function(spell) return saved[spell] or "off" end
	mns.SetCooldownSound = function(spell, key)
		if key == mns.GetCooldownSound(spell) then return false end
		saved[spell] = key
		return true
	end
	mns.KnownSpell = function(spell) return spell == "Evocation" or spell == "Cold Snap" end
	mns.AddMoreSpellRows()
	local evo, snap = m.vars.HUDini_class_cooldown_Evocation_sound, m.vars.HUDini_class_cooldown_ColdSnap_sound
	H.ok(evo and snap, "a sound setting for each spell, for HUDini setup's repaint")
	H.eq(evo.get(), "off", "off at the start")
	evo.set("mapPing")
	H.eq(saved.Evocation, "mapPing", "it saves through ns.SetCooldownSound")
	H.eq(evo.get(), "mapPing", "and reads back")
	H.eq(snap.get(), "off", "the other spell keeps its own sound")
	-- With no sound API (an older Classes.lua), Off, and no error.
	mns.GetCooldownSound, mns.SetCooldownSound = nil, nil
	H.eq(snap.get(), "off", "no API: Off")
	snap.set("raidWarning")
end)

H.test("Your class: each cooldown row's Sound column is a sound picker (TICK-0233)", function()
	local w, ns = MageWorld()
	ns.KnownSpell = function(spell) return spell == "Evocation" end
	ns.AddMoreSpellRows()
	local row
	for _, r in ipairs(w.pages["Your class"]) do
		if r.grid and r.name == "Evocation" then row = r end
	end
	H.ok(row, "the Evocation row")
	H.eq(row.choices, nil, "no drop-down choices")
	local saved = false
	ns.GetCooldownSoundValue = function(spell) return spell == "Evocation" and saved or false end
	ns.SetCooldownSound = function(spell, pick) if spell == "Evocation" then saved = pick end return true end
	local frame = w:Frame(nil, w.env.UIParent)
	-- The game's list element and settings, as far as a draw reads them.
	local function Nop() end
	frame.Release, frame.Init, frame.Tooltip = Nop, Nop, w:Frame(nil, frame)
	frame.cbrHandles = { RegisterCallback = Nop, SetOnValueChangedCallback = Nop }
	for _, key in ipairs({ "glow", "bar", "sound" }) do
		local setting = row.grid[key]
		rawset(setting, "GetValue", function() return false end)
		rawset(setting, "GetVariable", function() return row.columns[key] end)
	end
	local oldCreate = w.env.CreateFrame
	w.env.CreateFrame = function(...)
		local f = oldCreate(...)
		if select(4, ...) == "SettingsCheckboxTemplate" then f.Init, f.Release = Nop, Nop end
		return f
	end
	row.init.InitFrame(row.init, frame)
	w.env.CreateFrame = oldCreate
	local p = frame.hudiniGrid and frame.hudiniGrid.sound
	H.ok(p and p.bind, "the row draws a bound picker")
	local T = ns.TEXT[0]
	H.eq(p.bind.default, "readyCheck", "Ready check is its default")
	H.eq(p.bind.withOff, true, "Off is in the list")
	H.eq(p.bind.label, T["opt.cd.sound"], "the column's name is its tooltip title")
	H.eq(p.bind.tip, T["opt.cd.sound.tip"], "and the column's tip its body")
	H.eq(p.bind.enabled, nil, "never gray")
	local c = { key = "mapPing", volume = 75 }
	p.bind.set(c)
	H.eq(saved, c, "a pick saves the choice, with its volume, for this spell")
	H.eq(p.bind.get(), c, "and reads it back")
	p.bind.set(nil)
	H.eq(saved, false, "Off saves false")
	-- A released row lets its picker go.
	row.init.Resetter(row.init, frame)
	H.eq(p.bind, nil, "the released picker has no bind")
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

H.test("Your class: a cooldown row's ready glow and timer bar each save on their own, for this class only", function()
	local w = ClassWorld("SHAMAN")
	local ns = w.ns
	ns.KnownSpell = function(spell) return spell == "Mana Tide Totem" end
	ns.AddMoreSpellRows()
	local glow, bar = w.vars.HUDini_class_cooldown_ManaTideTotem_glow, w.vars.HUDini_class_cooldown_ManaTideTotem_bar
	H.ok(glow and glow.proxy and bar and bar.proxy, "Mana Tide Totem has a glow and a bar")
	local GetGlow = ns.GetCooldownGlow or ns.GetReadyAlert
	H.eq(glow.get(), false, "no glow at the start")
	H.eq(bar.get(), false, "no bar at the start")
	glow.set(true)
	H.eq(GetGlow("Mana Tide Totem"), true, "Ready glow turns the glow on")
	H.eq(ns.GetTimerBar("Mana Tide Totem"), false, "and no timer bar")
	local mine = w.env.HUDiniDB.classes.SHAMAN
	H.eq((mine.readyGlow or mine.readyAlerts)["Mana Tide Totem"], true, "saved for the Shaman")
	H.eq(glow.get(), true, "the box reads it back")
	bar.set(true)
	H.eq(GetGlow("Mana Tide Totem") and ns.GetTimerBar("Mana Tide Totem"), true, "Timer bar adds the bar, the glow stays")
	H.eq(mine.timerBars["Mana Tide Totem"], true, "and saves the bar for the Shaman")
	glow.set(false)
	H.eq(GetGlow("Mana Tide Totem"), false, "the glow turns off")
	H.eq(ns.GetTimerBar("Mana Tide Totem"), true, "the bar stays")
	H.eq(bar.get(), true, "the bar box reads it back")
	bar.set(false)
	H.eq(GetGlow("Mana Tide Totem") or ns.GetTimerBar("Mana Tide Totem"), false, "both off")
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
	H.ok(at[T["opt.head.advanced"]] < at[T["opt.head.items"]], "under Advanced")
	H.eq(at.HUDini_class_item_ankh, at[T["opt.head.items"]] + 1, "the Ankh row under its header")
	H.ok(at[T["opt.head.cooldowns"]] and at.HUDini_class_item_ankh < at[T["opt.head.cooldowns"]], "then Cooldowns")
end)

-- TICK-0243: DK's Shaman showed Cooldowns, Missing items, then a second
-- Cooldowns: rows made at a later open went to the end of the page. Now
-- each goes to the end of its own group, under its one header.
H.test("Your class: rows learned at later opens join their own group, each header once (TICK-0243)", function()
	local w = ItemWorld("SHAMAN")
	local ns, rows, T = w.ns, w.pages["Your class"], w.ns.TEXT[0]
	local known = { ["Earth Shock"] = true }
	ns.KnownSpell = function(spell) return known[spell] or false end
	ns.CooldownSpells = function() return { "Earth Shock", "Flame Shock", "Stoneclaw Totem" }, 3 end
	ns.TimerBarSpells = function() return {} end
	ns.MissingItemRows = function() return { { key = "earth", make = "Earth Totem" } } end
	ns.MissingItemKnown = function(row) return known[row.make] and 1 or nil end
	ns.MissingItemName = function() return "Earth Totem" end
	local before = #rows
	ns.AddMoreSpellRows()
	-- The tail of the page as one line: headers by key, rows by name.
	local function Tail()
		local key, out = {}, {}
		for _, k in ipairs({ "opt.head.items", "opt.head.cooldowns", "opt.head.tankBuff" }) do key[T[k]] = k end
		for i = before + 1, #rows do
			local r = rows[i]
			out[#out + 1] = r.header and key[r.header] or r.gridHead and "head" or r.name or r.variable
		end
		return table.concat(out, ", ")
	end
	H.eq(Tail(), "opt.head.cooldowns, head, Earth Shock", "first open: Cooldowns")
	known["Earth Totem"] = true
	ns.AddMoreSpellRows()
	H.eq(Tail(), "opt.head.items, HUDini_class_item_earth, opt.head.cooldowns, head, Earth Shock",
		"a late item row goes before Cooldowns, under its header")
	known["Flame Shock"] = true
	ns.AddMoreSpellRows()
	H.eq(Tail(), "opt.head.items, HUDini_class_item_earth, opt.head.cooldowns, head, Earth Shock, Flame Shock",
		"a late cooldown row after a late item row joins Cooldowns")
	known["Stoneclaw Totem"] = true
	ns.AddMoreSpellRows()
	ns.AddMoreSpellRows()
	H.eq(Headers(rows, T, "opt.head.cooldowns"), 1, "one Cooldowns header")
	H.eq(Headers(rows, T, "opt.head.items"), 1, "one Missing items header")
	H.eq(rows[#rows].name, "Stoneclaw Totem", "the last row is the newest cooldown, and nothing is lost")
	H.eq(#rows, before + 7, "every row once")
end)

H.test("Your class: an error while a row is made loses no row and doubles none (TICK-0243)", function()
	local w = ItemWorld("SHAMAN")
	local ns, rows, T = w.ns, w.pages["Your class"], w.ns.TEXT[0]
	local known, fail = { ["Earth Shock"] = true }, false
	ns.KnownSpell = function(spell) return known[spell] or false end
	ns.CooldownSpells = function() return { "Earth Shock", "Flame Shock" }, 2 end
	ns.TimerBarSpells = function() return {} end
	ns.MissingItemRows = function() return { { key = "earth", make = "Earth Totem" } } end
	ns.MissingItemKnown = function(row) return known[row.make] and 1 or nil end
	ns.MissingItemName = function()
		if fail then error("no name") end
		return "Earth Totem"
	end
	local before = #rows
	ns.AddMoreSpellRows()
	known["Earth Totem"], fail = true, true
	H.ok(not pcall(ns.AddMoreSpellRows), "the error still shows")
	fail, known["Flame Shock"] = false, true
	ns.AddMoreSpellRows()
	local seen, header = {}, 0
	for i = before + 1, #rows do
		local r = rows[i]
		if r.name and r.name ~= "" then
			H.eq(seen[r.name], nil, r.name .. " shows once")
			seen[r.name] = true
		end
		if r.header == T["opt.head.items"] then header = i end
	end
	H.ok(seen["Earth Shock"] and seen["Flame Shock"], "both cooldown rows")
	H.ok(header > 0, "the Missing items header stays")
	H.eq(Headers(rows, T, "opt.head.cooldowns"), 1, "one Cooldowns header")
	H.eq(#rows, before + 5, "every row once")
end)

H.test("Your class: a layout with no list gets a header each time the group changes, as before (TICK-0243)", function()
	local w = ClassWorld("SHAMAN", nil, function(w) w.noList = true end)
	local ns, rows, T = w.ns, w.pages["Your class"], w.ns.TEXT[0]
	local known = { ["Earth Shock"] = true }
	ns.KnownSpell = function(spell) return known[spell] or false end
	ns.CooldownSpells = function() return { "Earth Shock", "Flame Shock" }, 2 end
	ns.TimerBarSpells = function() return {} end
	ns.MissingItemRows = function() return { { key = "earth", make = "Earth Totem" } } end
	ns.MissingItemKnown = function(row) return known[row.make] and 1 or nil end
	ns.MissingItemName = function() return "Earth Totem" end
	ns.AddMoreSpellRows()
	known["Earth Totem"] = true
	ns.AddMoreSpellRows()
	known["Flame Shock"] = true
	ns.AddMoreSpellRows()
	H.eq(rows[#rows].name, "Flame Shock", "a late row stays at the end")
	H.eq(Headers(rows, T, "opt.head.cooldowns"), 2, "under a Cooldowns header of its own, not under Missing items")
end)

-- The tank buff row (TICK-0208): made at the first open that knows the
-- class file's tankBuff, under its own header, bound to ns.GetTankBuff /
-- ns.SetTankBuff. The test class profiles have no tankBuff, so this one
-- gives the Paladin the shape of Classes.lua's header.
local function TankWorld()
	local w = ClassWorld("PALADIN")
	local ns = w.ns
	w.knowsTank = false
	local classDefault = ns.ClassDefault
	ns.ClassDefault = function(key, ...)
		if key == "tankBuff" then return { buff = "Righteous Fury", with = { "Seal of Fury" } } end
		return classDefault(key, ...)
	end
	ns.TankBuffSpell = function() return w.knowsTank and 25780 or nil end
	return w, ns
end

H.test("Your class: the tank buff row shows only once you know the buff, once", function()
	local w, ns = TankWorld()
	local rows, T = w.pages["Your class"], ns.TEXT[0]
	ns.AddMoreSpellRows()
	H.eq(w.vars.HUDini_class_tankBuff, nil, "Righteous Fury not known: no row")
	H.eq(Headers(rows, T, "opt.head.tankBuff"), 0, "and no header")
	local before = #rows
	w.knowsTank = true
	ns.AddMoreSpellRows()
	H.eq(rows[before + 1].header, T["opt.head.tankBuff"], "learned: the header, at the end")
	H.eq(rows[before + 2].variable, "HUDini_class_tankBuff", "then the row")
	H.eq(#rows, before + 2, "no other row")
	local v = w.vars.HUDini_class_tankBuff
	H.eq(v.label, "Remind me of Righteous Fury when I tank", "its label names the buff")
	H.eq(rows[before + 2].tooltip, "In a fight, show an icon by your health bar when Righteous Fury is off while Seal of Fury is on: the sign that you tank. Show your health must be on; Sound when a buff is missing plays with it.",
		"its tip names the buff and the seal")
	H.ok(v.proxy, "a proxy row")
	H.eq(v.default, nil, "no default: Defaults calls no setter")
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 2, "the next open adds nothing")
	H.eq(Headers(rows, T, "opt.head.tankBuff"), 1, "one header")
end)

H.test("Your class: the tank buff row turns the reminder off for this class, gray without the health bar", function()
	local w, ns = TankWorld()
	w.knowsTank = true
	ns.AddMoreSpellRows()
	local v, r = w.vars.HUDini_class_tankBuff, nil
	for _, row in ipairs(w.pages["Your class"]) do
		if row.variable == "HUDini_class_tankBuff" then r = row end
	end
	H.eq(v.get(), true, "nothing saved: on")
	v.set(false)
	H.eq(ns.GetTankBuff(), false, "a clear turns the reminder off")
	H.eq(ns.ClassDB().tankBuffOn, false, "saved for the Paladin as tankBuffOn")
	H.eq(type(ns.ClassValue("tankBuff")), "table", "the class file's tankBuff stays a table")
	H.eq(v.get(), false, "the box reads it back")
	v.set(true)
	H.eq(ns.GetTankBuff(), true, "a check turns it on again")
	H.eq(table.concat(r.regray, ","), "HUDini_showHealth", "re-grays on Show your health")
	w.env.HUDiniDB.showHealth = false
	H.eq(r.when(), false, "gray without the health bar")
	w.env.HUDiniDB.showHealth = true
	H.eq(r.when(), true, "live with it")
end)

H.test("Your class: the tank buff row names the buff as the client does", function()
	local w, ns = TankWorld()
	w.knowsTank = true
	w.env.C_Spell.GetSpellName = function(id) return id == 25780 and "Zorn der Gerechtigkeit" or nil end
	ns.AddMoreSpellRows()
	H.eq(w.vars.HUDini_class_tankBuff.label, "Remind me of Zorn der Gerechtigkeit when I tank", "the client's name")
end)

H.test("Your class: the tank buff row comes before Missing items at the same open", function()
	local w, ns = TankWorld()
	w.knowsTank = true
	local rows, T = w.pages["Your class"], ns.TEXT[0]
	ns.MissingItemRows = function() return { { key = "symbol", make = "Divine Intervention" } } end
	ns.MissingItemKnown = function() return 1 end
	ns.MissingItemName = function() return "Symbol of Divinity" end
	ns.AddMoreSpellRows()
	local at = {}
	for i, row in ipairs(rows) do
		if row.header then at[row.header] = i end
		if row.variable then at[row.variable] = i end
	end
	H.ok(at[T["opt.head.advanced"]] < at[T["opt.head.tankBuff"]], "under Advanced")
	H.ok(at.HUDini_class_tankBuff < at[T["opt.head.items"]], "then Missing items")
end)

H.test("Your class: a tank buff learned after Missing items still comes before them, each header once (TICK-0243)", function()
	local w, ns = TankWorld()
	local rows, T = w.pages["Your class"], ns.TEXT[0]
	ns.MissingItemRows = function() return { { key = "symbol", make = "Divine Intervention" } } end
	ns.MissingItemKnown = function() return 1 end
	ns.MissingItemName = function() return "Symbol of Divinity" end
	ns.AddMoreSpellRows()
	H.eq(Headers(rows, T, "opt.head.tankBuff"), 0, "not known yet: no Tank buff")
	w.knowsTank = true
	ns.AddMoreSpellRows()
	local at = {}
	for i, row in ipairs(rows) do
		if row.header then at[row.header] = i end
		if row.variable then at[row.variable] = i end
	end
	H.ok(at[T["opt.head.tankBuff"]] < at[T["opt.head.items"]], "the Tank buff header before Missing items")
	H.eq(at.HUDini_class_tankBuff, at[T["opt.head.tankBuff"]] + 1, "its row under it")
	H.eq(at.HUDini_class_item_symbol, at[T["opt.head.items"]] + 1, "the item row under its header")
	H.eq(Headers(rows, T, "opt.head.tankBuff"), 1, "one Tank buff header")
	H.eq(Headers(rows, T, "opt.head.items"), 1, "one Missing items header")
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
	-- Under Advanced, after the Sound alerts rows (TICK-0233 step 2).
	local adv
	for i, r in ipairs(rows) do
		if r.header == T["opt.head.advanced"] then adv = i end
	end
	H.ok(adv, "an Advanced header")
	H.eq(rows[adv + 1].header, T["opt.head.soundAlerts"], "Sound alerts first")
	for i = adv + 2, before do H.ok(rows[i].sound, "then only sound rows") end
	H.eq(rows[before + 1].header, T["opt.head.cooldowns"], "then Cooldowns")
	H.ok(rows[before + 2].gridHead, "then the column heads")
	H.eq(rows[before + 3].variable, "HUDini_class_cooldown_EarthShock_glow", "A to Z: Earth Shock")
	H.eq(rows[before + 4].variable, "HUDini_class_cooldown_FlameShock_glow", "then Flame Shock")
	H.eq(#rows, before + 4, "no other row")
	H.ok(not rows[before + 3].when, "a cooldown row is never gray")
	H.eq(rows[before + 3].columns.bar, "HUDini_class_cooldown_EarthShock_bar", "the row's timer bar")
	H.eq(rows[before + 3].columns.sound, "HUDini_class_cooldown_EarthShock_sound", "the row's sound")
	H.eq(table.concat(rows[before + 3].tags, ","), "Earth Shock", "a search for the spell finds its row")
	H.eq(table.concat(rows[before + 2].tags, ","), "Earth Shock,Flame Shock", "and the column heads above it")
	local glow, bar = w.vars.HUDini_class_cooldown_EarthShock_glow, w.vars.HUDini_class_cooldown_EarthShock_bar
	H.eq(glow.get() or bar.get(), false, "off at the start")
	glow.set(true)
	bar.set(true)
	H.eq((ns.GetCooldownGlow or ns.GetReadyAlert)("Earth Shock") and ns.GetTimerBar("Earth Shock"), true,
		"the boxes save the glow and the bar")
	-- The next open adds only a new spell, at the end, with no second header.
	learned = { "Earth Shock", "Flame Shock", "Frost Shock" }
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 5, "one new row")
	H.eq(rows[before + 5].variable, "HUDini_class_cooldown_FrostShock_glow", "the new spell at the end")
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 5, "an open with nothing new adds nothing")
	-- The game's path: the options open, and a spell learned since gets its row.
	learned[#learned + 1] = "Lava Lash"
	w:Run(w.env.SettingsPanel, "OnShow")
	H.eq(rows[#rows].variable, "HUDini_class_cooldown_LavaLash_glow", "opening the options adds the new spell")
	H.eq(#rows, before + 6, "and only that one")
	-- Names with no letters of a-z (a ruRU client), or the same letters,
	-- each get a setting of their own: the game throws on a second one.
	learned[#learned + 1] = "Удар бури"
	learned[#learned + 1] = "Ледяной шок"
	learned[#learned + 1] = "Lava-Lash"
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 9, "three more rows, no error")
	-- In a fight the panel adds no row.
	learned[#learned + 1] = "Stormstrike"
	w.env.InCombatLockdown = function() return true end
	ns.AddMoreSpellRows()
	H.eq(#rows, before + 9, "no row in a fight")
	-- A class file spell learned later joins the end of the group.
	w.env.InCombatLockdown = function() return false end
	ns.KnownSpell = function(spell) return spell == "Heroism" end
	ns.AddMoreSpellRows()
	H.eq(rows[#rows - 1].variable, "HUDini_class_cooldown_Heroism_glow", "Heroism, learned, at the end, class spells first")
	H.eq(rows[#rows].variable, "HUDini_class_cooldown_Stormstrike_glow", "then Stormstrike, learned in the fight")
	H.eq(#rows, before + 11, "two new rows")
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
	ns.CooldownSpells = ns.ReadyAlertSpells -- the name since TICK-0203
	ns.LearnedCooldownSpells = function() return {} end
	local known = { ["Inner Focus"] = true, ["Fear Ward"] = true, ["Psychic Scream"] = true }
	ns.KnownSpell = function(spell) return known[spell] or false end
	-- A glow saved for a spell you do not know keeps its row, so you can
	-- turn it off. readyAlerts until the TICK-0203 migration lands.
	w.env.HUDiniDB.classes.PRIEST = w.env.HUDiniDB.classes.PRIEST or {}
	w.env.HUDiniDB.classes.PRIEST.readyAlerts = { ["Starshards"] = true }
	w.env.HUDiniDB.classes.PRIEST.readyGlow = { ["Starshards"] = true }
	ns.AddMoreSpellRows()
	local above, under, advanced = 0, {}, false
	for _, r in ipairs(rows) do
		if r.header == ns.TEXT[0]["opt.head.advanced"] then advanced = true end
		if r.row and not advanced then above = above + 1 end
		if r.row and advanced then under[#under + 1] = r.variable end
	end
	H.ok(above <= 15, above .. " rows above Advanced")
	H.eq(table.concat(under, ", "), "HUDini_class_cooldown_InnerFocus_glow, "
		.. "HUDini_class_cooldown_FearWard_glow, HUDini_class_cooldown_Starshards_glow, HUDini_class_cooldown_PsychicScream_glow",
		"the known and saved spells in the class file's order")
end)

-- TICK-0242: a bar's texture button has the bar's colors, and they are the
-- Colors page's own: one saved value, two places.
H.test("a bar's color row and the Colors page row are one saved color", function()
	local w = PanelWorld("WARRIOR", nil, function(w)
		w.env.CreateColor = function(r, g, b)
			return { GenerateHexColor = function()
				return string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5),
					math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
			end }
		end
		w.env.CreateColorFromHexString = function(hex)
			local function N(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
			return { r = N(3), g = N(5), b = N(7) }
		end
	end)
	local ns, env, Text = w.ns, w.env, w.ns.Text
	-- The game's Settings.GetSetting: SetValue runs the proxy's setter, then
	-- the setting's callbacks.
	env.Settings.GetSetting = function(variable)
		local v = w.vars[variable]
		if not v then return nil end
		return { SetValue = function(_, value)
			v.set(value)
			for _, fn in ipairs(w.callbacks[variable] or {}) do fn(nil, value) end
		end }
	end
	local info, rgb = nil, { 1, 0, 0 }
	env.ColorPickerFrame = {
		SetupColorPickerAndShow = function(_, i) info = i end,
		GetColorRGB = function() return rgb[1], rgb[2], rgb[3] end,
	}
	local function Menu()
		local m = { entries = {} }
		local function Add(e)
			e.SetTooltip, e.SetEnabled = function() end, function() end
			m.entries[#m.entries + 1] = e
			return e
		end
		function m:CreateButton(text, click)
			local e = Add(Menu())
			e.text, e.click = text, click
			return e
		end
		function m:CreateRadio(text) return Add({ text = text }) end
		function m:CreateDivider() return Add({}) end
		return m
	end
	-- The color row of key in the texture button of bar id.
	local function Row(id, key)
		local root = Menu()
		local b = ns.BindLookButton(ns.CreateLookButton(env.UIParent, 180), { id = id, label = id })
		ns.LookMenu(b, root)
		local want = Text("opt.look.base", Text("opt.color." .. key))
		for _, e in ipairs(root.entries) do
			if e.text and e.text:find(want, 1, true) then return e end
		end
	end
	local function PageRow(key)
		for _, r in ipairs(w.pages.Colors) do
			if r.tooltip == Text("opt.color." .. key .. ".tip") then return r end
		end
	end
	local health = w.vars.HUDini_color_health

	-- The look window writes; the Colors page reads the same value.
	Row("health", "health").click()
	info.swatchFunc()
	H.eq(health.get(), "ffff0000", "the Colors page's setting reads the pick")
	H.eq(table.concat(env.HUDiniDB.colors.health, ","), "1,0,0", "one saved value")
	H.ok(PageRow("health").buttonText:find(":255:0:0|t", 1, true), "the Colors page row shows it")

	-- The Colors page writes; the look window shows it.
	w.vars.HUDini_color_hostile.set("ff00ff00")
	H.ok(Row("targethealth", "hostile").text:find(":0:255:0|t", 1, true), "the look window shows the page's pick")

	-- Defaults on the Colors page (SetValue of each default) resets a color
	-- picked in a look window.
	rgb = { 0, 0, 1 }
	Row("targethealth", "hostile").click()
	info.swatchFunc()
	H.eq(w.vars.HUDini_color_hostile.get(), "ff0000ff")
	for _, key in ipairs({ "health", "hostile" }) do
		local v = w.vars["HUDini_color_" .. key]
		v.set(v.default)
		H.eq(v.get(), v.default, key .. ": Defaults resets it")
		local d, c = ns.defaults.colors[key], ns.BarColor(key)
		for i = 1, 3 do H.ok(math.abs(c[i] - d[i]) <= 0.5 / 255, key .. ": the default color, " .. i) end
	end
end)

H.test("the timer bar look: text and color rows; the texture is in each spell's row", function()
	local w = ClassWorld("MAGE")
	H.eq(w.env.HUDiniDB.timerBarTexture, nil, "no Timer bar texture key (TICK-0225)")
	H.eq(w.env.HUDiniDB.timerBarTime, "seconds", "a new install shows the time left")
	H.ok(not w.vars.HUDini_timerBarTexture, "no Timer bar texture row")
	H.ok(w.vars.HUDini_timerBarTime, "Timer bar text has a row")
	local color = w.vars.HUDini_color_timer
	H.ok(color and color.proxy, "the timer bar color has a row")
	local refreshed, saved = 0, nil
	w.ns.RefreshTimerBars = function() refreshed = refreshed + 1 end
	w.ns.SetColorHex = function(key, hex) saved = key .. " " .. hex end
	color.set("ffff0000")
	H.eq(saved, "timer ffff0000", "a pick saves the color")
	H.eq(refreshed, 1, "and repaints the timer bars")
	-- A new text reaches a bar that shows now (TICK-0158 review).
	local function Pick(key, value)
		w.env.HUDiniDB[key] = value
		for _, fn in ipairs(w.callbacks["HUDini_" .. key]) do fn() end
	end
	Pick("timerBarTime", "percent")
	H.eq(refreshed, 2, "a text pick repaints the timer bars")
	-- The color sits under Advanced on the Colors page.
	local advanced
	for _, r in ipairs(w.pages.Colors) do
		if r.header == "Advanced" then advanced = true end
		if r.variable == "HUDini_color_timer" then H.ok(advanced, "under Advanced") end
	end
end)

H.test("Keep timer bars in view: page 1, right after Fade out, never gray, and a change moves the bars (TICK-0219)", function()
	local w = ClassWorld("MAGE")
	H.eq(w.env.HUDiniDB.timerBarsStay, false, "off on a new install")
	local rows, at = w.pages[w.pageOrder[1]], {}
	for i, r in ipairs(rows) do
		if r.variable then at[r.variable] = i end
	end
	H.ok(at.HUDini_timerBarsStay, "a row on page 1")
	H.eq(at.HUDini_timerBarsStay, at.HUDini_fadeOutTime + 1, "right after Fade out")
	local row = rows[at.HUDini_timerBarsStay]
	H.ok(not row.when, "never gray: the HUD also hides with Hide when idle off")
	H.eq(w.vars.HUDini_timerBarsStay.label, w.ns.TEXT[0]["opt.timerBarsStay"], "its label")
	local refreshed = 0
	w.ns.RefreshTimerBars = function() refreshed = refreshed + 1 end
	w.env.HUDiniDB.timerBarsStay = true
	for _, fn in ipairs(w.callbacks.HUDini_timerBarsStay) do fn() end
	H.eq(refreshed, 1, "a change moves the timer bars now")
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

--------------------------------------------------------------------------------
-- TICK-0225: the Textures page, the class resource bar's row, the timer
-- bar's texture button (docs/design/bar-textures.md)
--------------------------------------------------------------------------------

H.test("Textures: Bar texture, then a texture button for each bar, never gray", function()
	for _, class in ipairs(CLASSES) do
		local w = ClassWorld(class)
		local T = w.ns.TEXT[0]
		local rows = w.pages.Textures
		H.ok(rows, class .. ": a Textures page")
		H.eq(rows[1].variable, "HUDini_barTexture", class .. ": Bar texture first")
		H.eq(rows[1].tooltip, T["opt.barTexture.tip"], class .. ": its tip")
		H.eq(rows[2].header, T["opt.head.eachBar"], class .. ": then Each bar")
		local want = { "health", "power" }
		if w.ns.HasFormMana and w.ns.HasFormMana() then want[#want + 1] = "druidmana" end
		for _, id in ipairs({ "playercast", "xp", "targethealth", "targetpower", "targetcast" }) do
			want[#want + 1] = id
		end
		local got = {}
		for i = 3, #rows do
			local look = rows[i].look
			H.ok(look, class .. ": row " .. i .. " is a texture button")
			got[#got + 1] = look and look.id
			if look then
				H.eq(rows[i].name, T["opt.look." .. look.id], class .. ": " .. look.id .. "'s label")
				H.ok(not rows[i].when, class .. ": " .. look.id .. " is never gray")
				H.eq(w.vars["HUDini_look_" .. look.id .. "_texture"].default, "same",
					class .. ": " .. look.id .. "'s texture resets to Same as Bar texture")
			end
		end
		H.eq(table.concat(got, ","), table.concat(want, ","), class .. ": the bars, top to bottom")
		for _, r in ipairs(w.pages.Bars) do
			H.ok(r.variable ~= "HUDini_barTexture", class .. ": Bar texture left the Bars page")
		end
	end
end)

H.test("Textures: Mana in forms only for a druid", function()
	local w = ClassWorld("MAGE")
	for _, r in ipairs(w.pages.Textures) do
		H.ok(not (r.look and r.look.id == "druidmana"), "a mage has no Mana in forms row")
	end
end)

H.test("Your class: the class resource bar's texture row ends the Class resource section", function()
	local w, ns, mine = MageWorld()
	local T = ns.TEXT[0]
	local rows, at = w.pages["Your class"], nil
	for i, r in ipairs(rows) do
		if r.look and r.look.id == "resource" then at = i end
	end
	H.ok(at, "the row is there")
	H.eq(rows[at - 1].variable, "HUDini_class_resourceStacks", "right after Stacks to fill")
	H.eq(rows[at].name, T["opt.class.resourceLook"], "its label")
	H.eq(rows[at].tooltip, T["opt.class.resourceLook.tip"], "its tip")
	H.eq(rows[at].look.tip, T["opt.class.resourceLook.tip"], "the button's tip")
	H.eq(w.vars.HUDini_look_resource_gradient.default, "off", "Defaults resets its gradient")
	-- Gray with no resource, or with Show class resource off.
	H.eq(ns.ResourceLookOn(), ns.ClassResource() and true or false, "on with a resource the bar shows")
	mine.resource = { aura = "Arcane Missiles", max = 5 }
	H.eq(ns.ResourceLookOn(), true, "a picked resource: on")
	w.env.HUDiniDB.showResource = false
	H.eq(ns.ResourceLookOn(), false, "Show class resource off: gray")
	w.env.HUDiniDB.showResource = true
	mine.resource = false
	H.eq(ns.ResourceLookOn(), false, "None: gray")
	-- The game grays the label with the predicate, on each change of the
	-- two settings.
	local row = rows[at]
	H.eq(row.when, ns.ResourceLookOn, "the label grays with ResourceLookOn")
	H.eq(table.concat(row.regray, ","), "HUDini_class_resource,HUDini_showResource", "and re-grays on both")
	-- HUDini grays its own button: on each draw, and on each change.
	local function Fire(key) for _, fn in ipairs(w.callbacks["HUDini_" .. key]) do fn() end end
	mine.resource = { aura = "Arcane Missiles", max = 5 }
	local frame = w:Frame(nil, w.env.UIParent)
	row.init.InitFrame(row.init, frame)
	local b = frame.hudiniLook
	H.ok(b, "the row draws its button")
	H.eq(b:IsEnabled(), true, "on with a resource")
	w.env.HUDiniDB.showResource = false
	Fire("showResource")
	H.eq(b:IsEnabled(), false, "Show class resource off: the button grays")
	H.eq(b:GetAlpha(), 0.5, "and dims")
	w.env.HUDiniDB.showResource = true
	Fire("showResource")
	H.eq(b:IsEnabled(), true, "on again")
	mine.resource = false
	Fire("class_resource")
	H.eq(b:IsEnabled(), false, "None: the button grays")
	-- A frame given to another row is enabled again.
	row.init.Resetter(row.init, frame)
	H.eq(b:IsEnabled(), true, "a released frame is enabled")
	H.eq(b:GetAlpha(), 1, "and full")
	-- Lightning Shield's tip. The row's tooltip stays a string, as the
	-- settings search reads it; a resource pick writes it again.
	w.env.C_Spell = w.env.C_Spell or {}
	w.env.C_Spell.GetSpellName = function(id) return id == 324 and "Lightning Shield" or nil end
	mine.resource = { aura = "Lightning Shield", max = 3 }
	Fire("class_resource")
	H.eq(rawget(row, "tooltip"), T["opt.class.resourceLook.tipLightning"], "the lightning tip, as a string")
	H.eq(getmetatable(row), nil, "no metatable on the row's data")
	H.eq(row.look.tip, T["opt.class.resourceLook.tipLightning"], "on the button too")
	mine.resource = { aura = "Arcane Missiles", max = 5 }
	Fire("class_resource")
	H.eq(rawget(row, "tooltip"), T["opt.class.resourceLook.tip"], "back to the plain tip")
	-- A flair change writes it at the new level.
	ns.TEXT[0]["opt.class.resourceLook.tip"] = "plain at a new level"
	ns.RetextFlairTips()
	H.eq(rawget(row, "tooltip"), "plain at a new level", "a flair change retexts it")
end)

H.test("Your class: the resource texture row is gray for a Shaman who does not know Lightning Shield yet (TICK-0199)", function()
	local w, ns = ClassWorld("SHAMAN")
	-- The class file's resource (Classes/Shaman.lua); the test fixture has none.
	ns.RegisterClass("SHAMAN", { resource = { aura = "Lightning Shield", max = 3 } })
	w.env.HUDiniDB.showResource = true
	H.eq(ns.ResourceLookOn(), false, "Lightning Shield not known: gray, as the bar shows nothing")
	w.env.C_Spell.GetSpellInfo = function(name)
		if name == "Lightning Shield" then return { spellID = 324 } end
	end
	w.env.IsPlayerSpell = function(id) return id == 324 end
	H.eq(ns.ResourceLookOn(), true, "Lightning Shield known: on")
	w.env.HUDiniDB.showResource = false
	H.eq(ns.ResourceLookOn(), false, "Show class resource off: gray")
end)

H.test("Your class: each cooldown row has its timer bar's texture button", function()
	local w, ns = MageWorld()
	ns.KnownSpell = function() return true end
	ns.AddMoreSpellRows()
	local T = ns.TEXT[0]
	local n = 0
	for _, r in ipairs(w.pages["Your class"]) do
		if r.grid then
			n = n + 1
			local look = r.look
			H.ok(look, r.name .. ": a texture button")
			H.eq(look.id, ns.TimerLookId(r.name), r.name .. ": its timer bar")
			H.eq(look.label, r.name, r.name .. ": the spell's name")
			H.ok(look.allTimers, r.name .. ": Use on every timer bar")
			H.eq(look.tip, T["opt.cd.bar.tip"], r.name .. ": the Timer bar tip")
			local base = r.columns.glow:gsub("_glow$", "")
			H.eq(w.vars[base .. "_look_texture"].default, "same", r.name .. ": Defaults resets the texture")
		end
	end
	H.ok(n > 0, "the mage has cooldown rows")
end)

H.test("Your class: a released cooldown row lets its texture button go (TICK-0231)", function()
	local w, ns = MageWorld()
	ns.KnownSpell = function() return true end
	ns.AddMoreSpellRows()
	local row
	for _, r in ipairs(w.pages["Your class"]) do
		if r.grid then row = r break end
	end
	H.ok(row, "a cooldown row")
	local frame = w:Frame(nil, w.env.UIParent)
	local released = 0
	frame.Release = function() released = released + 1 end
	local b = ns.CreateLookButton(frame, 60)
	ns.BindLookButton(b, row.look)
	b:Show()
	local function Box() return { Release = function() released = released + 1 end } end
	local p = ns.CreateSoundPicker(frame, 230)
	frame.hudiniGrid = { glow = Box(), bar = Box(), look = b, sound = p }
	row.init.Resetter(row.init, frame)
	H.eq(released, 3, "the boxes and the frame are released")
	H.eq(b.look, nil, "the button has no look")
	H.eq(b:IsShown(), false, "and hides")
end)

H.test("the old Timer bar texture moves once into the timer bars that are on", function()
	local w = ClassWorld("MAGE", { timerBarTexture = "flat",
		classes = { MAGE = { timerBars = { Evocation = true, Blink = false } } } })
	local db = w.env.HUDiniDB
	H.eq(db.timerBarTexture, nil, "the key is gone")
	local looks = db.classes.MAGE.looks
	H.eq(looks and looks["timer:Evocation"] and looks["timer:Evocation"].texture, "flat", "a bar that is on keeps it")
	H.ok(not (looks and looks["timer:Blink"]), "a bar that is off gets nothing")
end)

--------------------------------------------------------------------------------
-- TICK-0237: the ammo alert's row on the Your class page
--------------------------------------------------------------------------------

H.test("Your class: the ammo row, before Class resource, for a Hunter, Warrior and Rogue only, on for a Hunter", function()
	for _, class in ipairs(CLASSES) do
		local w = ClassWorld(class)
		local ns, T = w.ns, w.ns.TEXT[0]
		local rows, at = w.pages["Your class"], nil
		for i, r in ipairs(rows) do
			if r.variable == "HUDini_class_ammo" then at = i end
			-- TICK-0241: a Shaman saw the ammo row.
			if not AMMO_CLASS[class] then
				H.ok(r.header ~= T["opt.head.ammo"], class .. ": no Ammo header")
			end
		end
		if not AMMO_CLASS[class] then
			H.eq(at, nil, class .. ": no bow, gun or crossbow: no ammo row")
			H.eq(w.vars.HUDini_class_ammo, nil, class .. ": and no setting")
		else
			H.ok(at, class .. ": the row is there")
			H.eq(rows[at - 1].header, T["opt.head.ammo"], class .. ": under Ammo")
			H.eq(rows[at + 1].header, T["opt.head.resource"], class .. ": then Class resource")
			H.eq(rows[at].tooltip, T["opt.class.ammo.tip"], class .. ": its tip")
			H.eq(table.concat(rows[at].regray, ","), "HUDini_showHealth", class .. ": re-grays on Show your health")
			local hunter = class == "HUNTER"
			H.eq(w.vars.HUDini_class_ammo.default, hunter, class .. ": Defaults gives back the class default")
			H.eq(ns.GetAmmoWarn(), hunter, class .. ": on for a Hunter only")
			H.eq(rows[at].when(), true, class .. ": on with Show your health")
			w.env.HUDiniDB.showHealth = false
			H.eq(rows[at].when(), false, class .. ": gray without it")
			w.env.HUDiniDB.showHealth = true
		end
	end
end)

H.test("Your class: the ammo row saves for this class", function()
	local w = ClassWorld("WARRIOR")
	local setting = w.vars.HUDini_class_ammo
	H.eq(setting.get(), false, "off for a Warrior")
	setting.set(true)
	H.eq(w.ns.GetAmmoWarn(), true, "a click turns it on")
	H.eq(w.env.HUDiniDB.classes.WARRIOR.warnAmmo, true, "saved for the Warrior")
	setting.set(false)
	H.eq(w.ns.GetAmmoWarn(), false, "and off again")
end)

-- The Alerts page's rows after its Sound alerts header (TICK-0233 step 3).
local function SoundAlertRows(w)
	local out, seen = {}, false
	for _, r in ipairs(w.pages.Alerts) do
		if r.header == w.ns.TEXT[0]["opt.head.soundAlerts"] then
			seen = true
		elseif seen and r.header then
			break
		elseif seen then
			out[#out + 1] = r
		end
	end
	return out, seen
end

H.test("Alerts: Sound alerts, five pickers that start Off, two line sliders gray until a pick (TICK-0233)", function()
	local w, ns = MageWorld()
	local T = ns.TEXT[0]
	local rows, seen = SoundAlertRows(w)
	H.ok(seen, "a Sound alerts header")
	local names = {}
	for _, r in ipairs(rows) do names[#names + 1] = r.sound and r.name or r.variable end
	H.eq(table.concat(names, ","), table.concat({ T["opt.sound.combatStart"], T["opt.sound.combatEnd"],
		T["opt.sound.lowHealth"], "HUDini_soundLowHealthAt", T["opt.sound.lowMana"], "HUDini_soundLowManaAt",
		T["opt.sound.honorKill"] }, ","), "the rows, in the design's order")
	for _, r in ipairs(rows) do
		H.eq(type(r.tooltip), "string", (r.name or r.variable) .. ": a plain string tip")
		if r.sound then
			H.eq(r.sound.get(), false, r.name .. ": starts Off")
			H.eq(r.sound.withOff, true, r.name .. ": has Off")
			H.eq(r.when, nil, r.name .. ": never gray")
		end
	end
	for _, s in ipairs({ "soundCombatStart", "soundCombatEnd", "soundLowHealth", "soundLowMana", "soundHonorKill" }) do
		H.eq(w.vars["HUDini_" .. s].default, "off", s .. ": Defaults gives Off")
	end
	H.eq(w.vars.HUDini_soundLowHealthAt.default, 30, "the line starts at 30%")

	-- A pick saves the choice, and the slider under it turns active.
	local health = rows[3]
	local line = rows[4]
	H.eq(line.when(), false, "no low health sound: the line is gray")
	H.eq(table.concat(line.regray, ","), "HUDini_soundLowHealth", "it re-grays on the low health sound")
	local before = w.notified.HUDini_soundLowHealth
	health.sound.set(ns.NewSoundChoice("mapPing", 50))
	H.eq(w.env.HUDiniDB.soundLowHealth.key, "mapPing", "the pick is saved for every character")
	H.eq(w.env.HUDiniDB.soundLowHealth.volume, 50, "with its volume")
	H.eq(w.notified.HUDini_soundLowHealth, before + 1, "the pick re-grays the line at once")
	H.eq(line.when(), true, "a picked sound: the line is active")
	H.eq(w.vars.HUDini_soundLowHealth.get(), "mapPing", "the proxy reads the pick")
	health.sound.set(ns.NewSoundChoice("mapPing", 50))
	H.eq(w.notified.HUDini_soundLowHealth, before + 1, "the same pick again: no repaint")

	-- The line snaps to a step; Defaults turns the sound Off again.
	w.vars.HUDini_soundLowHealthAt.set(42)
	H.eq(w.vars.HUDini_soundLowHealthAt.get(), ns.SoundAlertLine(42), "the line is saved as a whole step")
	w.vars.HUDini_soundLowHealth.set("off")
	H.eq(w.env.HUDiniDB.soundLowHealth, false, "Off saves false")
	H.eq(line.when(), false, "and the line is gray again")
	w.vars.HUDini_soundCombatStart.set("readyCheck")
	H.eq(rows[1].sound.get().key, "readyCheck", "a proxy pick is a picker pick")
	H.eq(rows[1].sound.get().volume, 100, "at full volume")
end)

H.test("Alerts: a class with no mana gets no Low mana rows, and Defaults still reaches them (TICK-0233)", function()
	local w = PanelWorld("WARRIOR")
	local T = w.ns.TEXT[0]
	local rows = SoundAlertRows(w)
	H.eq(#rows, 5, "a Warrior: five rows")
	for _, r in ipairs(rows) do
		H.ok(r.name ~= T["opt.sound.lowMana"] and r.variable ~= "HUDini_soundLowManaAt", "no Low mana row")
	end
	H.ok(w.vars.HUDini_soundLowMana and w.vars.HUDini_soundLowManaAt, "both settings are registered")
end)

H.test("Your class: the pet row, after Ammo, only for a class with a pet (TICK-0192)", function()
	-- The live Hunter and Warlock class files have a pet field; the
	-- fixture's profiles (ClassWorld) do not.
	local w = PanelWorld("HUNTER")
	local ns, T = w.ns, w.ns.TEXT[0]
	H.eq(type(PanelWorld("WARLOCK").vars.HUDini_class_pet), "table", "a Warlock has the row too")
	local rows, at = w.pages["Your class"], nil
	for i, r in ipairs(rows) do
		if r.variable == "HUDini_class_pet" then at = i end
	end
	H.ok(at, "a Hunter with a pet field: the row is there")
	H.eq(rows[at - 1].header, T["opt.head.pet"], "under Pet")
	H.eq(rows[at - 3].header, T["opt.head.ammo"], "after Ammo")
	H.eq(rows[at + 1].header, T["opt.head.resource"], "then Class resource")
	H.eq(rows[at].tooltip, T["opt.class.pet.tip"], "its tip")
	H.eq(type(rows[at].tooltip), "string", "a plain string tip")
	H.eq(table.concat(rows[at].regray, ","), "HUDini_showHealth", "re-grays on Show your health")
	local v = w.vars.HUDini_class_pet
	H.eq(v.default, true, "Defaults turns it on")
	H.eq(v.get(), true, "on at the start")
	v.set(false)
	H.eq(w.env.HUDiniDB.classes.HUNTER.petOn, false, "off is saved for the Hunter")
	H.eq(ns.GetPetAlert(), false, "and read back")
	v.set(v.default)
	H.eq(ns.GetPetAlert(), true, "Defaults gives it back")
	H.eq(rows[at].when(), true, "on with Show your health")
	w.env.HUDiniDB.showHealth = false
	H.eq(rows[at].when(), false, "gray without it")

	for _, class in ipairs(CLASSES) do
		local c = PanelWorld(class)
		local pet = class == "HUNTER" or class == "WARLOCK"
		H.eq(type(c.ns.PetAlertData()) == "table", pet, class .. ": a pet field only for a Hunter and a Warlock")
		if not pet then
			H.eq(c.vars.HUDini_class_pet, nil, class .. ": no pet field, no setting")
			for _, r in ipairs(c.pages["Your class"]) do
				H.ok(r.header ~= T["opt.head.pet"], class .. ": no Pet header")
			end
		end
	end
end)

H.test("Icons: Read visible action bars says a bar hidden in Edit Mode drops its actions, gray unless packed (TICK-0088)", function()
	local w = PanelWorld("MAGE")
	local row
	for _, r in ipairs(w.pages.Icons) do
		if r.variable == "HUDini_autoBars" then row = r end
	end
	H.ok(row, "the row is on the Icons page")
	local TEXT = w.ns.TEXT
	local T = TEXT[0]
	H.eq(row.tooltip, T["opt.autoBars.tip"], "the level 0 tip")
	H.ok(T["opt.autoBars.tip"]:find("a bar you hide in Edit Mode drops its actions from the HUD", 1, true),
		"level 0 has the fact")
	H.ok(T["opt.autoBars.tip"]:find("Only with Icon layout set to Packed: selected bars.", 1, true), "the gray-row ending")
	H.eq(TEXT[1]["opt.autoBars.tip"], nil, "level 1 falls back to level 0")
	H.eq(TEXT[2]["opt.autoBars.tip"]:sub(1, #T["opt.autoBars.tip"]), T["opt.autoBars.tip"],
		"level 2 is level 0 plus an aside")
	-- The setup end page sends a Rows player to the packed layout: it warns
	-- there too, at every level.
	for level = 0, 2 do
		H.ok(TEXT[level]["setup.p7.bars"]:find("a bar you hide in Edit Mode drops its actions from the HUD", 1, true),
			"the end page bars notice at level " .. level)
	end
	local db = w.env.HUDiniDB
	db.layoutMode = "bar"
	H.ok(not row.when(), "gray in Rows")
	db.layoutMode = "wrap"
	H.ok(row.when(), "on in Packed")
end)

-- The Your class Sound alerts rows, in page order (TICK-0233 step 2).
local function ClassSoundRows(w)
	local out, seen = {}, false
	for _, r in ipairs(w.pages["Your class"]) do
		if r.header == w.ns.TEXT[0]["opt.head.soundAlerts"] then
			seen = true
		elseif seen and r.header then
			break
		elseif seen and r.sound then
			out[#out + 1] = r
		end
	end
	return out, seen
end

H.test("Your class: Sound alerts, a picker for each class alert, saved per class, gray while the alert is off (TICK-0233)", function()
	local w = PanelWorld("SHAMAN")
	local ns, T, db = w.ns, w.ns.TEXT[0], w.env.HUDiniDB
	local rows, seen = ClassSoundRows(w)
	H.ok(seen, "a Sound alerts header under Advanced")
	local mine, want = ns.ClassAlertSounds(), {}
	for _, a in ipairs(mine) do want[#want + 1] = T["opt.class.sound." .. (a.dispel or a.alert)] end
	want[#want + 1] = T["opt.class.sound.weaponBuff"]
	local names = {}
	for _, r in ipairs(rows) do names[#names + 1] = r.name end
	H.eq(table.concat(names, ","), table.concat(want, ","), "one row for each alert the Shaman has, in list order, then the weapon buff sound")
	H.ok(#rows >= 2, "the Shaman has an interrupt and a dispel at least")
	for i, a in ipairs(mine) do
		local r = rows[i]
		H.eq(type(r.tooltip), "string", r.name .. ": a plain string tip")
		H.eq(r.sound.get(), false, r.name .. ": starts Off")
		H.eq(r.sound.withOff, true, r.name .. ": has Off")
		H.eq(r.sound.default, a.sound, r.name .. ": the alert's own sound is the default")
		H.ok(r.when, r.name .. ": can be gray")
	end
	-- Every class alert sound is registered, so Defaults reaches each one.
	for _, a in ipairs(ns.CLASS_ALERT_SOUNDS) do
		H.eq(w.vars["HUDini_class_" .. a.setting].default, "off", a.setting .. ": Defaults gives Off")
	end

	-- The interrupt row: gray with the alert off or the spell None.
	local kick = rows[1]
	H.eq(kick.name, T["opt.class.sound.interrupt"], "Interrupt sound first")
	H.eq(table.concat(kick.regray, ","), "HUDini_glowOnKickable,HUDini_class_interrupt", "the alert and the spell re-gray it")
	db.glowOnKickable = true
	H.eq(kick.when(), true, "the alert on, a spell: active")
	H.eq(kick.sound.enabled(), true, "the picker is active too")
	db.glowOnKickable = false
	H.eq(kick.when(), false, "the alert off: gray")
	db.glowOnKickable = true
	w.vars.HUDini_class_interrupt.set(ns.PICK_NONE)
	H.eq(kick.when(), false, "the spell None: gray")

	-- A dispel row reads its own type.
	local dispel
	for i, a in ipairs(mine) do if a.dispel then dispel = { row = rows[i], a = a } break end end
	H.ok(dispel, "a dispel row")
	db.warnDispel = true
	H.eq(dispel.row.when(), true, dispel.a.dispel .. ": active")
	H.eq(table.concat(dispel.row.regray, ","), "HUDini_warnDispel,HUDini_class_dispel_" .. dispel.a.dispel,
		"its alert and its own spell re-gray it")
	w.vars["HUDini_class_dispel_" .. dispel.a.dispel].set(ns.PICK_NONE)
	H.eq(dispel.row.when(), false, dispel.a.dispel .. ": None, gray")

	-- A pick saves for the Shaman, with its volume, and announces itself once.
	local n0 = w.notified.HUDini_class_soundInterrupt or 0
	kick.sound.set(ns.NewSoundChoice("readyCheck", 50))
	H.eq(db.classes.SHAMAN.soundInterrupt.key, "readyCheck", "saved for the Shaman")
	H.eq(db.classes.SHAMAN.soundInterrupt.volume, 50, "with its volume")
	H.eq(w.notified.HUDini_class_soundInterrupt, n0 + 1, "the pick announces itself")
	kick.sound.set(ns.NewSoundChoice("readyCheck", 50))
	H.eq(w.notified.HUDini_class_soundInterrupt, n0 + 1, "the same pick again: no repaint")
	H.eq(w.vars.HUDini_class_soundInterrupt.get(), "readyCheck", "the proxy reads the pick")
	w.vars.HUDini_class_soundInterrupt.set("off")
	H.eq(db.classes.SHAMAN.soundInterrupt, nil, "Off saves nothing")
end)

H.test("Your class: a class with no class alert gets no Sound alerts section; another class gets only its own rows (TICK-0233)", function()
	local _, seen = ClassSoundRows(PanelWorld("DEATHKNIGHT"))
	H.ok(not seen, "a class with no class file: no section")
	local w = PanelWorld("WARRIOR")
	local rows = ClassSoundRows(w)
	local want = {}
	for _, a in ipairs(w.ns.ClassAlertSounds()) do want[#want + 1] = w.ns.TEXT[0]["opt.class.sound." .. (a.dispel or a.alert)] end
	local names = {}
	for _, r in ipairs(rows) do names[#names + 1] = r.name end
	H.eq(table.concat(names, ","), table.concat(want, ","), "a Warrior: its own rows only")
	H.ok(w.vars.HUDini_class_soundMagic, "the other settings are still registered")
end)

-- The weapon buff alert rows (TICK-0251): the box after Repeat, its sound
-- last under Sound alerts, only for a class whose file has weaponBuff.
H.test("Your class: the weapon buff alert and its sound, for a Rogue or a Shaman only, each change at once (TICK-0251)", function()
	local w = PanelWorld("SHAMAN")
	local ns, T, db = w.ns, w.ns.TEXT[0], w.env.HUDiniDB
	local rows, at = w.pages["Your class"], {}
	for i, r in ipairs(rows) do if r.variable then at[r.variable] = i end end
	local i = at.HUDini_class_weaponBuffAlert
	H.ok(i, "a Shaman has the row")
	H.eq(i, at.HUDini_class_keepUpRepeat + 1, "right after Repeat, under Buffs")
	local box = rows[i]
	H.eq(w.vars.HUDini_class_weaponBuffAlert.label, T["opt.class.weaponBuffAlert"], "its label")
	H.eq(T["opt.class.weaponBuffAlert"], "Weapon buff alert", "named as the Pet alert and the Ammo alert")
	H.eq(box.tooltip, T["opt.class.weaponBuffAlert.tip"], "its tip, a plain string")
	H.eq(table.concat(box.regray, ","), "HUDini_showHealth,HUDini_warnOwnBuff", "the health bar and the personal buff reminder re-gray it")
	db.showHealth, db.warnOwnBuff = true, true
	H.eq(box.when(), true, "active with both on")
	db.warnOwnBuff = false
	H.eq(box.when(), false, "gray without the personal buff reminder")
	db.warnOwnBuff = true

	local v = w.vars.HUDini_class_weaponBuffAlert
	H.eq(v.default, true, "Defaults turns it on, a plain value")
	H.eq(v.get(), true, "on at the start")
	local refresh, repaint = 0, 0
	ns.RefreshWeaponBuffAlert = function() refresh = refresh + 1 end
	ns.RepaintSoundPickers = function() repaint = repaint + 1 end
	v.set(false)
	for _, fn in ipairs(w.callbacks.HUDini_class_weaponBuffAlert) do fn() end
	H.eq(db.classes.SHAMAN.weaponBuffAlert, false, "off is saved for the Shaman")
	H.eq(refresh, 1, "the icon and the HUD follow at once")
	H.eq(repaint, 1, "the sound row re-grays")

	-- The sound: last under Sound alerts, Off at the start, gray unless the
	-- alert can show.
	local sounds = ClassSoundRows(w)
	local s = sounds[#sounds]
	H.eq(s.name, T["opt.class.sound.weaponBuff"], "the weapon buff sound is the last sound row")
	H.eq(type(s.tooltip), "string", "a plain string tip")
	H.eq(s.sound.get(), false, "starts Off")
	H.eq(s.sound.default, ns.WEAPON_BUFF_SOUND.sound, "the alert's own sound is the default")
	H.eq(table.concat(s.regray, ","), "HUDini_showHealth,HUDini_warnOwnBuff,HUDini_class_weaponBuffAlert",
		"the alert and what it needs re-gray it")
	H.eq(s.when(), false, "gray with the alert off")
	v.set(true)
	H.eq(s.when(), true, "active with it on")
	H.eq(s.sound.enabled(), true, "the picker too")
	H.eq(w.vars.HUDini_class_soundWeaponBuff.default, "off", "Defaults gives Off")
	s.sound.set(ns.NewSoundChoice("readyCheck", 50))
	H.eq(db.classes.SHAMAN.soundWeaponBuff.key, "readyCheck", "a pick is saved for the Shaman")
	H.eq(w.vars.HUDini_class_soundWeaponBuff.get(), "readyCheck", "the proxy reads it")

	H.ok(PanelWorld("ROGUE").vars.HUDini_class_weaponBuffAlert, "a Rogue has the row too")
	local c = PanelWorld("WARRIOR")
	H.eq(c.vars.HUDini_class_weaponBuffAlert, nil, "a Warrior: no row")
	for _, r in ipairs(c.pages["Your class"]) do
		H.ok(r.name ~= T["opt.class.sound.weaponBuff"], "a Warrior: no weapon buff sound row")
	end
	H.ok(c.vars.HUDini_class_soundWeaponBuff, "its setting is still registered, as the other sounds")
end)

H.test("each weapon buff alert tooltip's first sentence is the same at every level, in two sentences at level 0", function()
	local ns = H.world():loadAddon()
	for _, key in ipairs({ "opt.class.weaponBuffAlert.tip", "opt.class.sound.weaponBuff.tip" }) do
		local zero = ns.TEXT[0][key]
		local first = zero:match("^.-%.")
		H.eq(select(2, zero:gsub("%. ", "")) + 1, 2, key .. ": two sentences at level 0")
		for level = 1, 2 do
			local text = ns.TEXT[level][key] or zero
			H.eq(text:sub(1, #first), first, key .. ": level " .. level)
		end
		H.ok(not zero:find("reminder shows", 1, true), key .. ": the alert is an alert")
	end
end)

H.test("Your class: the real Hunter file's purge is Tranquilizing Shot for an Enrage only, with its own sound row (TICK-0217)", function()
	local w = PanelWorld("HUNTER")
	local purge = w.ns.ClassDefault("purge")
	H.eq(type(purge), "table", "the purge is the table form")
	H.eq(purge.spell, "Tranquilizing Shot", "its spell")
	H.eq(purge.enrage, true, "an Enrage only, not every magic buff")
	H.eq(purge.stealable, nil, "not a stealable-only purge")
	local names = {}
	for _, r in ipairs(ClassSoundRows(w)) do names[#names + 1] = r.name end
	H.eq(table.concat(names, ","), w.ns.TEXT[0]["opt.class.sound.purge"], "a Hunter: the Purge sound row only")
end)

H.test("Your class: Repeat sits under the buff missing sound, gray until that sound can play (TICK-0233)", function()
	local w = PanelWorld("SHAMAN")
	local ns, db = w.ns, w.env.HUDiniDB
	local rows, at = w.pages["Your class"], nil
	for i, r in ipairs(rows) do
		if r.variable == "HUDini_class_keepUpRepeat" then at = i end
	end
	H.ok(at, "the Repeat row")
	H.ok(rows[at - 1].sound, "right under the buff missing sound picker")
	H.eq(rows[at].tooltip, ns.TEXT[0]["opt.class.keepUpRepeat.tip"], "its tip")
	H.eq(w.vars.HUDini_class_keepUpRepeat.default, false, "off by default")
	H.eq(table.concat(rows[at].regray, ","),
		"HUDini_showHealth,HUDini_warnOwnBuff,HUDini_warnKeepUp,HUDini_class_keepUpSound", "what re-grays it")
	db.showHealth, db.warnOwnBuff = true, true
	local keepUp = rows[at - 1]
	keepUp.sound.set(false)
	H.eq(rows[at].when(), false, "no buff missing sound: gray")
	local n0 = w.notified.HUDini_class_keepUpSound or 0
	keepUp.sound.set(ns.NewSoundChoice("readyCheck", 100))
	H.eq(w.notified.HUDini_class_keepUpSound, n0 + 1, "a pick re-grays Repeat at once")
	H.eq(rows[at].when(), true, "a sound: active")
	db.showHealth = false
	H.eq(rows[at].when(), false, "no health bar: gray")
	w.vars.HUDini_class_keepUpRepeat.set(true)
	H.eq(db.classes.SHAMAN.keepUpRepeat, true, "saved for the Shaman")
	H.eq(w.vars.HUDini_class_keepUpRepeat.get(), true, "read back")
end)

H.test("Your class: a dispel set to None grays its own sound row only (TICK-0233)", function()
	local w = PanelWorld("SHAMAN")
	local ns, T, db = w.ns, w.ns.TEXT[0], w.env.HUDiniDB
	db.warnDispel = true
	local poison, disease
	for _, r in ipairs(ClassSoundRows(w)) do
		if r.name == T["opt.class.sound.Poison"] then poison = r end
		if r.name == T["opt.class.sound.Disease"] then disease = r end
	end
	H.ok(poison and disease, "a Shaman has Poison and Disease sound rows")
	H.eq(poison.sound.enabled(), true, "the alert on, a Poison spell: active")
	w.vars.HUDini_class_dispel_Poison.set(ns.PICK_NONE)
	H.eq(poison.sound.enabled(), false, "Poison None: its picker is gray")
	H.eq(poison.when(), false, "and its row")
	H.eq(disease.sound.enabled(), true, "Disease keeps its spell: still active")
end)

H.test("Your class: a spell pick or an alert toggle repaints the sound pickers once (TICK-0233)", function()
	local w = PanelWorld("SHAMAN")
	local ns = w.ns
	local n = 0
	ns.RepaintSoundPickers = function() n = n + 1 end
	for _, name in ipairs({ "HUDini_class_interrupt", "HUDini_class_dispel_Poison", "HUDini_class_purge" }) do
		local before = n
		w.vars[name].set(ns.PICK_NONE)
		H.eq(n, before + 1, name .. ": the pick repaints the pickers once")
	end
	-- The Your class page's own callback on each alert toggle: the last one
	-- registered, as the Alerts page builds first.
	for _, k in ipairs({ "glowOnKickable", "warnDispel", "showPurgeable" }) do
		local list = w.callbacks["HUDini_" .. k]
		H.ok(list and #list > 0, k .. ": has a callback")
		local before = n
		list[#list]()
		H.eq(n, before + 1, k .. ": the toggle repaints the pickers once")
	end
end)

H.test("Your class: the purge tip names a magic buff and an Enrage, in the same first sentence at every level (TICK-0217)", function()
	local ns = PanelWorld("HUNTER").ns
	local first
	for level = 0, 2 do
		local tip = ns.TEXT[level]["opt.class.purge.tip"]
		H.ok(tip, level .. ": a purge tip")
		local s = tip:match("^(.-%.)%s")
		H.ok(s:find("magic buff", 1, true) and s:find("Enrage", 1, true), level .. ": names both kinds")
		first = first or s
		H.eq(s, first, level .. ": the same first sentence")
	end
end)

-- TICK-0248: one mute box per error voice line (TICK-0247), the last rows
-- of Game frames, under Advanced and Game sounds, in ErrorVoice.lua's order.
H.test("Game frames: a mute box per error voice line, under Advanced, and a change mutes that line at once", function()
	local w, ns = ClassWorld("MAGE")
	local rows, T = w.pages["Game frames"], ns.TEXT[0]
	local advanced, sounds
	for i, r in ipairs(rows) do
		if r.header == T["opt.head.advanced"] then advanced = i end
		if r.header == T["opt.head.sounds"] then sounds = i end
	end
	H.ok(advanced, "an Advanced header")
	H.ok(sounds > advanced, "Game sounds under Advanced")
	local want = { "muteVoiceCooldown", "muteVoiceRange", "muteVoiceMana", "muteVoiceRage",
		"muteVoiceEnergy", "muteVoiceAttack", "muteVoiceNotYet" }
	H.eq(#rows, sounds + #want, "the seven boxes are the last rows")
	for n, key in ipairs(want) do
		local row, v = rows[sounds + n], w.vars["HUDini_" .. key]
		H.eq(row.variable, "HUDini_" .. key, "row " .. n .. " is " .. key)
		H.eq(v.label, T["opt." .. key], key .. ": the label")
		H.eq(row.tooltip, T["opt." .. key .. ".tip"], key .. ": the tooltip")
		H.eq(v.key, key, key .. ": it saves " .. key)
		H.eq(v.tbl, w.env.HUDiniDB, key .. ": in HUDiniDB")
		H.eq(ns.defaults[key], false, key .. ": Defaults turns it off")
	end
	H.eq(rows[sounds + 1].tooltip, "Silence your character's spoken line when a spell, ability or item is still on cooldown. The error sound and red error text remain.",
		"the first tooltip")

	-- A change queues an Apply, and the Apply mutes that one line.
	local muted = {}
	w.env.MuteSoundFile = function(id) muted[id] = true end
	w.env.UnmuteSoundFile = function(id) muted[id] = nil end
	local applies = 0
	rawset(ns.HUDini, "QueueApply", function() applies = applies + 1 end)
	H.eq(#(w.callbacks.HUDini_muteVoiceRange or {}), 1, "one change callback")
	w.env.HUDiniDB.muteVoiceRange = true
	w.callbacks.HUDini_muteVoiceRange[1]()
	H.eq(applies, 1, "a change queues one apply")
	ns.HUDini:Apply()
	local range, cooldown = ns.ERROR_VOICE_LINES[2], ns.ERROR_VOICE_LINES[1]
	for _, id in ipairs(range.files) do H.ok(muted[id], "too far away: file " .. id .. " muted") end
	for _, id in ipairs(cooldown.files) do H.ok(not muted[id], "still recharging: file " .. id .. " not muted") end
	w.env.HUDiniDB.muteVoiceRange = false
	ns.HUDini:Apply()
	H.eq(next(muted), nil, "off again: nothing muted")
end)

H.test("Game frames: each mute tooltip's first sentence is the same at every level", function()
	local _, ns = ClassWorld("MAGE")
	for _, line in ipairs(ns.ERROR_VOICE_LINES) do
		local key = "opt." .. line.key .. ".tip"
		local first = ns.TEXT[0][key]:match("^[^.]*%.")
		for level = 1, 2 do
			local tip = ns.TEXT[level][key]
			if tip then H.eq(tip:match("^[^.]*%."), first, key .. " at level " .. level) end
		end
	end
end)

-- TICK-0246: the cursor ring's rows (D-052, TICK-0245) on Game frames. On,
-- shape and size above Advanced; the three opacity sliders under it. Each
-- row grays with the ring off, and a change redraws the ring at once.
H.test("Game frames: the cursor ring rows, on, shape and size above Advanced, opacity under it", function()
	local w, ns = ClassWorld("MAGE")
	local rows, T = w.pages["Game frames"], ns.TEXT[0]
	local at, advanced = {}, nil
	for i, r in ipairs(rows) do
		if r.header == T["opt.head.advanced"] then advanced = i end
		if r.header then at[r.header] = i end
		if r.variable then at[r.variable] = i end
	end
	local head, opacity = at[T["opt.head.cursorRing"]], at[T["opt.head.cursorRingOpacity"]]
	H.ok(head and head < advanced, "a Cursor ring header above Advanced")
	H.eq(at.HUDini_cursorRing, head + 1, "the on box first")
	H.eq(at.HUDini_cursorRingShape, head + 2, "then the shape")
	H.eq(at.HUDini_cursorRingSize, head + 3, "then the size")
	H.eq(advanced, head + 4, "then Advanced")
	H.eq(opacity, advanced + 1, "Cursor ring opacity right under Advanced")
	H.eq(at.HUDini_cursorRingAlpha, opacity + 1, "out of combat")
	H.eq(at.HUDini_cursorRingAlphaCombat, opacity + 2, "in combat, solo")
	H.eq(at.HUDini_cursorRingAlphaGroup, opacity + 3, "in combat, in a group")
	H.eq(at[T["opt.head.sounds"]], opacity + 4, "then Game sounds")

	local db = w.env.HUDiniDB
	for _, key in ipairs({ "cursorRing", "cursorRingShape", "cursorRingSize",
		"cursorRingAlpha", "cursorRingAlphaCombat", "cursorRingAlphaGroup" }) do
		local row, v = rows[at["HUDini_" .. key]], w.vars["HUDini_" .. key]
		H.eq(v.label, T["opt." .. key], key .. ": the label")
		H.eq(row.tooltip, T["opt." .. key .. ".tip"], key .. ": the tooltip")
		H.eq(v.key, key, key .. ": it saves " .. key)
		H.eq(v.tbl, db, key .. ": in HUDiniDB")
		if key ~= "cursorRing" then
			H.ok(row.when, key .. ": grayed while the ring is off")
			db.cursorRing = false
			H.eq(row.when(), false, key .. ": gray with the ring off")
			db.cursorRing = true
			H.eq(row.when(), true, key .. ": live with the ring on")
			H.eq(row.regray[1], "HUDini_cursorRing", key .. ": the on box re-grays it")
		end
	end
	H.eq(ns.defaults.cursorRing, false, "Defaults turns the ring off")
	H.eq(Values(rows[at.HUDini_cursorRingShape].choices), "ring, halo, arrows", "the shapes")
	-- The ranges match CursorRing.lua's clamps: size 50-600, opacity 0-1.
	local function Range(key) return table.concat(rows[at["HUDini_" .. key]].range or {}, " ") end
	H.eq(Range("cursorRingSize"), "50 600 10", "size: 50 to 600 px, in steps of 10")
	for _, key in ipairs({ "cursorRingAlpha", "cursorRingAlphaCombat", "cursorRingAlphaGroup" }) do
		H.eq(Range(key), "0 1 0.01", key .. ": 0 to 100%, in steps of 1%")
	end

	-- Each change queues an Apply and redraws the ring at once.
	local applies, refreshes = 0, 0
	rawset(ns.HUDini, "QueueApply", function() applies = applies + 1 end)
	ns.RefreshCursorRing = function() refreshes = refreshes + 1 end
	for n, key in ipairs({ "cursorRing", "cursorRingShape", "cursorRingSize",
		"cursorRingAlpha", "cursorRingAlphaCombat", "cursorRingAlphaGroup" }) do
		for _, fn in ipairs(w.callbacks["HUDini_" .. key]) do fn() end
		H.eq(applies, n, key .. ": a change queues one apply")
		H.eq(refreshes, n, key .. ": a change redraws the ring once")
	end
end)

H.test("Game frames: each cursor ring tooltip's first sentence is the same at every level", function()
	local _, ns = ClassWorld("MAGE")
	for _, key in ipairs({ "cursorRing", "cursorRingShape", "cursorRingSize",
		"cursorRingAlpha", "cursorRingAlphaCombat", "cursorRingAlphaGroup" }) do
		local tip = "opt." .. key .. ".tip"
		local first = ns.TEXT[0][tip]:match("^[^.]*%.")
		for level = 1, 2 do
			local text = ns.TEXT[level][tip]
			if text then H.eq(text:match("^[^.]*%."), first, tip .. " at level " .. level) end
		end
	end
end)

H.test("Game frames: Hide the game's objective list, right after the experience bar box (TICK-0257)", function()
	local w, ns = ClassWorld("MAGE")
	local rows, T = w.pages["Game frames"], ns.TEXT[0]
	local at = {}
	for i, r in ipairs(rows) do
		if r.variable then at[r.variable] = i end
	end
	local i = at.HUDini_hideBlizzardObjectives
	H.ok(i, "the box is on Game frames")
	H.eq(i, at.HUDini_hideBlizzardXP + 1, "right after Hide the game's experience bar")
	local v = w.vars.HUDini_hideBlizzardObjectives
	H.eq(v.label, "Hide the game's objective list", "its label")
	H.eq(rows[i].tooltip, T["opt.hideBlizzardObjectives.tip"], "its tooltip, a plain string")
	H.eq(v.key, "hideBlizzardObjectives", "it saves hideBlizzardObjectives")
	H.eq(v.tbl, w.env.HUDiniDB, "in HUDiniDB")
	local first = T["opt.hideBlizzardObjectives.tip"]:match("^[^.]*%.")
	H.eq(select(2, T["opt.hideBlizzardObjectives.tip"]:gsub("%.", "")), 2, "two sentences at level 0")
	for level = 1, 2 do
		local text = ns.TEXT[level]["opt.hideBlizzardObjectives.tip"]
		H.ok(text, "a tip at level " .. level)
		H.eq(text:match("^[^.]*%."), first, "the same first sentence at level " .. level)
	end
end)
