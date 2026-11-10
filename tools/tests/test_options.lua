-- Options.lua (TICK-0017): every saved
-- setting has a row in the panel, or is one of the layout's "saved values
-- with no row"; no page has more than 15 rows above its Advanced header,
-- for any class; and the pages come in the layout's order. The harness
-- fakes already throw on AddShownPredicate and SetParentInitializer.

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- options-layout.md "Saved values with no row": changed by a drag or a
-- slash command, not in a list.
local NO_ROW = {
	point = true, relPoint = true, x = true, y = true, classes = true, xpSessions = true,
	feedPoint = true, feedRelPoint = true, feedX = true, feedY = true, feedIgnore = true,
	bars = { bar1 = true }, -- Action Bar 1 is always read
	minimapAngle = true,    -- the minimap button's place: a drag saves it
}

-- Saved values a proxy row writes for them.
local PROXY = { growRight = "growToward", growDown = "growToward", auraMap = "auraMap" }

local PAGES = { "HUDini", "Icons", "Bars", "Colors", "Alerts", "Your class", "Feed", "Game frames" }

-- A world logged in as class, with every setting and every row on each
-- page kept in order. db, if given, is the saved HUDiniDB at login.
local function PanelWorld(class, db)
	local w = H.world()
	if db then w.env.HUDiniDB = db end
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
					H.ok(w.vars["HUDini_color_" .. k], class .. ": color " .. k .. " is on the Colors page")
				end
			elseif type(v) == "table" and type(NO_ROW[key]) == "table" then
				for k in pairs(v) do
					H.ok(NO_ROW[key][k] or (w.vars["HUDini_" .. k] and w.vars["HUDini_" .. k].tbl == w.env.HUDiniDB[key]),
						class .. ": " .. key .. "." .. k .. " has a row")
				end
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
	local w = PanelWorld("MAGE")
	H.eq(table.concat(w.pageOrder, ", "), table.concat(PAGES, ", "), "page order")
end)

H.test("the Colors page builds the power rows of your class only", function()
	local function Rows(class)
		local w = PanelWorld(class)
		local n = 0
		for _, r in ipairs(w.pages.Colors) do
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
	local w = PanelWorld("MAGE")
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
	local w = PanelWorld("MAGE")
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
	local w = PanelWorld("MAGE")
	local first = w.pages.HUDini[1]
	H.eq(first.variable, "HUDini_style", "the first row")
	H.ok(first.choices, "it is a dropdown")
	H.ok(w.vars.HUDini_style.proxy, "a proxy")
	H.eq(w.env.HUDiniDB.style, nil, "no style name is saved")
end)

H.test("Style shows the matching style, or Custom, and lists Custom only then", function()
	local w = PanelWorld("MAGE")
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
	local w, ns = PanelWorld("MAGE")
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
	local w, ns = PanelWorld("MAGE")
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
	local w = PanelWorld("MAGE")
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
	local w, ns = PanelWorld("MAGE")
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
	local w = PanelWorld("MAGE")
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
	local w = PanelWorld("MAGE")
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
	local w = PanelWorld("MAGE")
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
	"HUDini_class_keepUp", "Clear learned buffs", "HUDini_class_resource",
	"HUDini_class_resourceStacks",
}

-- A Mage with these spells on its action bars. Counterspell is ID 2139.
local function MageWorld(bars)
	local w, ns = PanelWorld("MAGE")
	ns.ActionBarSpells = function() return bars or { "Arcane Missiles", "Counterspell", "Fireball" } end
	ns.KnownSpell = function() return false end
	w.env.C_Spell.GetSpellName = function(id) return id == 2139 and "Counterspell" or nil end
	return w, ns, w.env.HUDiniDB.classes.MAGE
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

H.test("Your class: the class name, then the same 10 rows on every class", function()
	for _, class in ipairs(CLASSES) do
		local w = PanelWorld(class)
		local rows = w.pages["Your class"]
		H.eq(rows[1].header, w.className, class .. ": the header is the class name")
		H.eq(rows[1].tooltip, "Ability and resource choices are shared by characters of this class.", class .. ": the header tooltip")
		local got, headers = {}, {}
		for i, r in ipairs(rows) do
			if r.row then got[#got + 1] = r.variable or r.button end
			if r.header and i > 1 then headers[#headers + 1] = r.header end
		end
		H.eq(table.concat(got, ", "), table.concat(CLASS_ROWS, ", "), class .. ": the rows")
		local T = w.ns.TEXT[0]
		H.eq(table.concat(headers, ", "), table.concat({ T["opt.head.interrupt"], T["opt.head.dispel"],
			T["opt.head.purge"], T["opt.head.buffs"], T["opt.head.resource"] }, ", "), class .. ": the sections")
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
	local w, ns = PanelWorld("WARRIOR")
	ns.ActionBarSpells = function() return { "Heroic Strike" } end
	local mine = w.env.HUDiniDB.classes.WARRIOR
	local interrupt = ClassRow(w, "HUDini_class_interrupt").choices
	H.eq(Labels(interrupt), "Class default: Pummel, Shield Bash, None, Heroic Strike", "the class file's list")
	mine.interrupt = { "Pummel", "Shield Bash" }
	H.eq(Labels(interrupt), "Class default: Pummel, Shield Bash, None, Heroic Strike, Pummel, Shield Bash", "a saved list, never a table")
	H.ok(not Labels(interrupt):find("table:"), "no raw table")

	local w2, ns2 = PanelWorld("ROGUE")
	ns2.ActionBarSpells = function() return {} end
	w2.env.COMBO_POINTS = "Combo Points"
	H.eq(Labels(ClassRow(w2, "HUDini_class_resource").choices), "Class default: Combo Points, None", "a Rogue's resource")
	local w3, ns3 = PanelWorld("HUNTER")
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
		if v and name ~= "HUDini_class_resourceStacks" then H.eq(v.default, ns.PICK_DEFAULT, name .. ": the default") end
	end
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
	local w, ns = PanelWorld("HUNTER")
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
	H.eq(Find(PanelWorld("ROGUE").pages.Bars, "HUDini_showResource").when(), true, "a rogue has combo points")
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
	local w, ns = PanelWorld("MAGE")
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
	local w, ns = PanelWorld("MAGE")
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
	local w, ns = PanelWorld("MAGE")
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
	local w = PanelWorld("DRUID")
	local row = Row(w)
	H.ok(row and row.when, "a druid: the row has a gray predicate")
	H.eq(table.concat(row.regray, ","), "HUDini_showPower", "Power bar re-grays it")
	H.eq(row.when(), true, "a druid with Power bar on: active")
	w.env.HUDiniDB.showPower = false
	H.eq(row.when(), false, "Power bar off: gray")
	-- A class whose powers are MANA alone has no form with another power.
	for _, class in ipairs({ "MAGE", "PALADIN", "PRIEST", "SHAMAN", "WARLOCK", "WARRIOR" }) do
		local other = Row(PanelWorld(class))
		H.eq(other.when(), false, class .. ": gray")
	end
end)

-- D-024, TICK-0089: HUDini does not hide the gryphons. The Game frames page
-- has no Hide gryphons row; a header says Edit Mode hides them, and its
-- tooltip names Edit Mode's box at the flair level now.
H.test("Game frames: no Hide gryphons row; a header teaches Edit Mode's box, at every flair level", function()
	local w, ns = PanelWorld("MAGE")
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
