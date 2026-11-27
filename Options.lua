--[[--------------------------------------------------------------------------
	HUDini - Options

	Options -> AddOns -> HUDini, in eight pages:

		HUDini           where the HUD is, and when it shows
		Icons            the grid: layout, what each icon shows, which bars
		Bars             your bars, your target's, how they look, their sizes
		Colors           every bar color, one row each
		Alerts           the alerts your class has spells for, and the rest
		Your class       which spell each alert uses, saved for this class only
		Feed             the feed, its kinds and its details
		Blizzard frames  the opt-in hides, fades and the window mover

	Each page opens with the rows a new player changes. Rows people change
	once, or never, sit under a plain "Advanced" header at the bottom of the
	page. Nothing folds or hides.

	Every control writes straight into HUDiniDB and repaints the HUD. The
	building blocks below (Checkbox, Slider, Dropdown, Proxy, Under) wrap the
	12.x Settings API and work in any addon that keeps its settings in one
	saved table; copy them along with Register.

	Every word the panel shows is a Text() key in Locales/enUS.lua
	(TICK-0025): opt.<setting> for a row, opt.<setting>.tip for its tooltip.
	Every tooltip follows the Flair setting at once (RetextFlairTips).

	A row your class cannot use is never built: the class resource bar, a
	power color. Its setting is still registered, so Defaults resets it.
	The class alerts and the class resource bar are always built: the Your
	class page can give any class the spell. They are gray while your class
	has none. A row that applies only some of the
	time (the bar picker only while packing, a nested setting only while its
	parent is on) is grayed out the rest of the time, not hidden. Hiding
	needs AddShownPredicate and SetParentInitializer, and Blizzard's settings
	search calls those from its own code: one addon predicate there taints
	the search, and Blizzard rows found by it (the Discord ones) then trip
	"blocked from an action". Graying runs only inside each row's own setup,
	where the taint stays put.

	Style, the feed groups, colors, "Grow toward", your buff pairs and the
	Your class rows are proxy settings: the panel
	sees one value (a hex color, "DR", a flag) while HUDiniDB keeps its own
	shape. Being registered settings, each page's Defaults button resets
	them with everything else on that page. A setting's variable name
	(HUDini_<key>) never depends on its page, so moving a row to another
	page needs no migration.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Text = ns.Text

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------

local function Changed()
	ns.HUDini:QueueApply()
end

-- The Style dropdown (page 1), and the settings of the five rows a style
-- sets (Styles.lua), wherever those rows are.
local styleSetting
local styleRows = {}

-- One saved value. tbl is where it lives: HUDiniDB unless given.
local function Register(category, key, varType, label, tbl, default)
	local variable = "HUDini_" .. key
	local setting = Settings.RegisterAddOnSetting(category, variable, key,
		tbl or HUDiniDB, varType, label, default == nil and ns.defaults[key] or default)
	Settings.SetOnValueChangedCallback(variable, Changed)
	-- A row a style sets repaints the Style dropdown, and the chain ends
	-- there: the dropdown's own callback only queues an Apply.
	if not tbl and tContains(ns.STYLE_KEYS or {}, key) then
		styleRows[key] = setting
		Settings.SetOnValueChangedCallback(variable, function()
			if styleSetting and styleSetting.NotifyUpdate then styleSetting:NotifyUpdate() end
		end)
	end
	return setting
end

-- Every row whose tooltip is a text in Locales/enUS.lua, with that text's
-- key (TICK-0082: most tooltips have a Modest and a Full text). The Flair
-- setter writes the key's text at the new level into each row. A tooltip
-- stays a string, never a function, as Blizzard's settings search reads
-- tooltips too.
local flairRows = {}
-- A row whose tooltip is not one fixed key gives a function that writes
-- its string again; the Flair setter calls each (TICK-0225 review).
local flairFns = {}

-- The key whose text is tooltip, at the level the panel is built at. Two
-- keys with the same text give no key: a row could not know which it is.
local tipKeys
local function TipKey(tooltip)
	if not tipKeys then
		tipKeys = {}
		for key in pairs(ns.TEXT[0]) do
			local s = Text(key)
			tipKeys[s] = tipKeys[s] == nil and key or false
		end
	end
	return tipKeys[tooltip] or nil
end

-- Keep a row to retext. tipKey and its values are for a tooltip that
-- joins in values; any other tooltip's key is found from its text.
local function Remember(initializer, tooltip, tipKey, ...)
	tipKey = tipKey or (type(tooltip) == "string" and TipKey(tooltip)) or nil
	if initializer and tipKey then
		flairRows[#flairRows + 1] = { initializer, tipKey, select("#", ...), ... }
	end
	return initializer
end

-- The game keeps a row's tooltip in initializer.data and reads it on each
-- mouseover, so a new text shows on the next one. HUDini:Apply calls it too,
-- so a flair change from HUDini setup or /hud reset reaches the tooltips.
function ns.RetextFlairTips()
	for _, row in ipairs(flairRows) do
		local data = row[1].data
		if data and type(data.tooltip) == "string" then
			data.tooltip = Text(row[2], unpack(row, 4, 3 + row[3]))
		end
	end
	for _, fn in ipairs(flairFns) do fn() end
end

-- The tooltip shows on mouseover of the header's text.
local function Header(layout, text, tooltip)
	local initializer = Remember(CreateSettingsListSectionHeaderInitializer(text, tooltip), tooltip)
	layout:AddInitializer(initializer)
	return initializer
end

-- The header every page puts its set-once rows under.
local function Advanced(layout) return Header(layout, Text("opt.head.advanced")) end

-- A button on a row of its own.
local function Button(layout, label, buttonText, click, tooltip)
	local initializer = Remember(CreateSettingsButtonInitializer(label, buttonText, click, tooltip, true), tooltip)
	layout:AddInitializer(initializer)
	return initializer
end

local function Checkbox(category, key, label, tooltip)
	return Remember(Settings.CreateCheckbox(category,
		Register(category, key, Settings.VarType.Boolean, label), tooltip), tooltip)
end

-- fmt turns the value into the label beside the slider: "40 px".
local function SliderFor(category, setting, tooltip, low, high, step, fmt)
	local options = Settings.CreateSliderOptions(low, high, step)
	if fmt and options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
	end
	return Remember(Settings.CreateSlider(category, setting, options, tooltip), tooltip)
end

local function Slider(category, key, label, tooltip, low, high, step, fmt)
	return SliderFor(category, Register(category, key, Settings.VarType.Number, label),
		tooltip, low, high, step, fmt)
end

-- choices is a function returning { {value, label, tooltip}, ... }; the
-- tooltip is optional. It runs each time the menu opens.
local function DropdownFor(category, setting, tooltip, choices)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for _, c in ipairs(choices()) do container:Add(c[1], c[2], c[3]) end
		return container:GetData()
	end
	return Remember(Settings.CreateDropdown(category, setting, GetOptions, tooltip), tooltip)
end

local function Dropdown(category, key, label, tooltip, choices)
	return DropdownFor(category, Register(category, key, Settings.VarType.String, label),
		tooltip, choices)
end

-- A value the panel sees one way and HUDiniDB keeps another.
--
-- Neither default nor label is ever a function (TICK-0089). The game
-- calls a function default or name once at registration, inside its own
-- secure handler and not through securecallfunction: ProxySettingMixin:Init
-- -> ErrorIfInvalidSettingArguments -> GetDefaultValueType ->
-- defaultValue(), and GetNameType -> name() (Blizzard_Setting.lua:1-17,
-- :31-47, :337-340, from
-- Blizzard_SettingsInbound.lua:213-217; wow-ui-source `forever`
-- 9dc84f0). HUDini's function then taints the rest of that handler: the
-- setting and SettingsPanel:RegisterSetting. The Style dropdown's
-- function default (9f9cfb2) is what a bisect named for the Edit Mode
-- taint. nil is the safe "no default": SetValueToDefault then returns
-- false and calls no setter (Blizzard_Setting.lua:139-147).
local function Proxy(category, name, varType, label, default, get, set, onChange)
	local variable = "HUDini_" .. name
	local setting = Settings.RegisterProxySetting(category, variable, varType, label,
		default, get, set)
	Settings.SetOnValueChangedCallback(variable, onChange or Changed)
	return setting
end

-- Gray a row out while when() is false. The keys are the settings when()
-- reads: changing any of them re-grays the row on the spot. The row's
-- tooltip ends by naming them: "Only with Health bar on." (TICK-0045).
local function GreyUnless(initializer, when, ...)
	if initializer and initializer.AddModifyPredicate then
		initializer:AddModifyPredicate(when)
		for i = 1, select("#", ...) do
			initializer:AddEvaluateStateCVar("HUDini_" .. select(i, ...))
		end
	end
	return initializer
end

local function On(key) return function() return HUDiniDB[key] and true or false end end

-- Indent a row under the setting it hangs off, grayed while that is off.
-- when is that setting's key, or a function followed by the keys it reads.
local function Under(child, when, ...)
	if child and child.Indent then child:Indent() end
	if type(when) == "string" then return GreyUnless(child, On(when), when) end
	return GreyUnless(child, when, ...)
end

-- Label formatters.
local function Px(v)      return Text("opt.unit.px", v) end
local function Icons(v)   return Text("opt.unit.icons", v) end
local function Count(v)   return ("%d"):format(v) end
local function Percent(v) return ("%d%%"):format(v * 100 + 0.5) end
local function Seconds(v) return Text("opt.unit.seconds", v) end

-- Settings that only mean something in one mode.
local function Wrapping() return HUDiniDB.layoutMode ~= "bar" end

-- Does your class have this: from the class file, or a spell picked on the
-- Your class page? A saved None (false, or an empty list) does not count.
-- Read live, so a row grayed by it changes with a pick.
local function ClassHas(key)
	local value = ns.ClassValue(key)
	if type(value) == "table" then return next(value) ~= nil end
	return value ~= nil and value ~= false
end

--------------------------------------------------------------------------------
-- Colors
--
-- Each color is a proxy setting holding a hex string. The setter goes
-- through ns.SetColorHex, which repaints the bars, so a change needs no
-- extra work. They all live on the Colors page, so its Defaults resets
-- every color and nothing else.
--------------------------------------------------------------------------------

local colorSettings = {}
-- The fallback rows by color key, to repaint the square in their button.
local colorRows = {}

-- The Colors page's own labels: the page says what each one paints.
local COLOR_LABEL = {
	health = "opt.color.health",
	trail = "opt.color.trail",
	mana = "opt.color.mana",
	rage = "opt.color.rage",
	energy = "opt.color.energy",
	resource = "opt.color.resource",
	playercast = "opt.color.playercast",
	xp = "opt.color.xp",
	rested = "opt.color.rested",
	hostile = "opt.color.hostile",
	neutral = "opt.color.neutral",
	friendly = "opt.color.friendly",
	tapped = "opt.color.tapped",
	interrupt = "opt.color.interrupt",
	shielded = "opt.color.shielded",
	timer = "opt.color.timer",
}

-- The button text of a fallback row: a square of the color, then the words.
local function PickText(key)
	local c = ns.BarColor(key)
	local function Byte(v) return math.floor(v * 255 + 0.5) end
	return ("|TInterface\\Buttons\\WHITE8X8:12:12:0:0:8:8:0:8:0:8:%d:%d:%d|t  %s"):format(
		Byte(c[1]), Byte(c[2]), Byte(c[3]), Text("opt.color.pick"))
end

-- The bar colors, then the timer bar's (TICK-0158): its bars live in
-- TimerBars.lua, so its setter also repaints them.
local function ColorKeys()
	local out = {}
	for _, entry in ipairs(ns.COLOR_KEYS) do out[#out + 1] = entry end
	if ns.defaults.colors.timer then out[#out + 1] = { key = "timer" } end
	return out
end

local function RegisterColors(category)
	for _, entry in ipairs(ColorKeys()) do
		local key = entry.key
		local d = ns.defaults.colors[key]
		colorSettings[key] = Proxy(category, "color_" .. key, Settings.VarType.String, -- locale: skip a setting name
			COLOR_LABEL[key] and Text(COLOR_LABEL[key]) or entry.label, CreateColor(d[1], d[2], d[3]):GenerateHexColor(),
			function() return ns.ColorHex(key) end,
			function(hex)
				ns.SetColorHex(key, hex)
				if key == "timer" and ns.RefreshTimerBars then ns.RefreshTimerBars() end
			end,
			-- The bars repaint in the setter. A fallback row keeps its new
			-- text for the next time the panel draws it (after Defaults).
			function()
				local row = colorRows[key]
				if row and row.data then row.data.buttonText = PickText(key) end
			end)
	end
end

-- The game's color picker, writing into one color setting. Dragging
-- recolors live; Cancel puts the old color back.
--
-- button is the fallback row's button that was clicked, if any: its square
-- is repainted on the spot.
local function PickInto(key, button)
	local setting = colorSettings[key]
	if not (setting and ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
	local old = setting:GetValue()
	local c = CreateColorFromHexString(old)

	local function Apply(hex)
		setting:SetValue(hex)
		if button and button.SetText then button:SetText(PickText(key)) end
	end

	ColorPickerFrame:SetupColorPickerAndShow({
		r = c.r, g = c.g, b = c.b,
		hasOpacity = false,
		swatchFunc = function()
			Apply(CreateColor(ColorPickerFrame:GetColorRGB()):GenerateHexColor())
		end,
		cancelFunc = function() Apply(old) end,
	})
end

-- A color on a row of its own. A tooltip with joined-in values names its
-- text key and the values, so RetextFlairTips can build it again.
local function Swatch(category, layout, key, tooltip, tipKey, ...)
	if Settings.CreateColorSwatch then
		return Remember(Settings.CreateColorSwatch(category, colorSettings[key], tooltip), tooltip, tipKey, ...)
	end
	-- The game calls the row's click with the button as self.
	local initializer = CreateSettingsButtonInitializer(Text(COLOR_LABEL[key]),
		PickText(key),
		function(button) PickInto(key, button) end, tooltip, true)
	Remember(initializer, tooltip, tipKey, ...)
	layout:AddInitializer(initializer)
	colorRows[key] = initializer
	return initializer
end

--------------------------------------------------------------------------------
-- 1. HUDini: where the HUD is, and when it shows
--------------------------------------------------------------------------------

-- The Preset choices: the label and tooltip key of each.
local STYLE_CHOICES = {
	minimal = { "opt.style.minimal", "opt.style.minimal.tip" },
	standard = { "opt.style.standard", "opt.style.standard.tip" },
	leveling = { "opt.style.leveling", "opt.style.leveling.tip" },
}

local function StyleNow() return ns.MatchStyle() or "custom" end

-- No style name is saved: the dropdown reads the five settings each time.
local function StyleRow(category)
	-- No default, so Defaults (this page's, or "All Settings" in the
	-- popup) finds nothing to change and calls no setter. A fixed
	-- "standard" would apply Standard from the HUDini page. Not StyleNow
	-- either: a function default taints the game's settings code (Proxy).
	styleSetting = Proxy(category, "style", Settings.VarType.String, Text("opt.style"), nil, StyleNow,
		-- The setter fans out: ApplyStyle writes the five and applies once,
		-- then each of the five rows repaints. "custom" changes nothing.
		function(name)
			if not ns.ApplyStyle(name) then return end
			for _, key in ipairs(ns.STYLE_KEYS) do
				local s = styleRows[key]
				if s and s.NotifyUpdate then s:NotifyUpdate() end
			end
		end)
	DropdownFor(category, styleSetting, Text("opt.style.tip"),
		function()
			local out = {}
			for _, name in ipairs(ns.STYLE_ORDER) do
				local c = STYLE_CHOICES[name]
				if c then out[#out + 1] = { name, Text(c[1]), Text(c[2]) } end
			end
			-- Custom is listed only while no style matches.
			if not ns.MatchStyle() then
				out[#out + 1] = { "custom", Text("opt.style.custom"), Text("opt.style.custom.tip") }
			end
			return out
		end)
end

local function BuildGeneral(category, layout)
	-- First, with no header: it changes rows on the other pages.
	StyleRow(category)

	-- HUDini setup from page 1 (TICK-0042). The panel stays open: setup
	-- draws over it and repaints its rows. In a fight ns.OpenSetup says
	-- so and opens setup when the fight ends.
	Button(layout, Text("opt.runSetup"), Text("opt.runSetup"),
		function() ns.OpenSetup() end, Text("opt.runSetup.tip"))
	-- The minimap button (TICK-0020). Apply shows or hides it.
	Checkbox(category, "minimapButton", Text("opt.minimapButton"),
		Text("opt.minimapButton.tip"))
	Button(layout, Text("opt.about"), Text("opt.about"),
		function() ns.OpenAbout() end, Text("opt.about.tip"))

	Header(layout, Text("opt.head.position"))
	Checkbox(category, "locked", Text("opt.locked"),
		Text("opt.locked.tip"))
	Slider(category, "scale", Text("opt.scale"), Text("opt.scale.tip"),
		0.5, 2.0, 0.05, Percent)

	Header(layout, Text("opt.head.whenToShow"))
	Checkbox(category, "hideWhenIdle", Text("opt.hideWhenIdle"),
		Text("opt.hideWhenIdle.tip"))
	Under(Checkbox(category, "showInCombat", Text("opt.showInCombat"),
		Text("opt.showInCombat.tip")), "hideWhenIdle")
	Under(Checkbox(category, "showOnHostile", Text("opt.showOnHostile"),
		Text("opt.showOnHostile.tip")), "hideWhenIdle")
	Under(Checkbox(category, "showWhenHurt", Text("opt.showWhenHurt"),
		Text("opt.showWhenHurt.tip")), "hideWhenIdle")
	Under(Checkbox(category, "showWhenPower", Text("opt.showWhenPower"),
		Text("opt.showWhenPower.tip")),
		"hideWhenIdle")
	Under(Checkbox(category, "showWhenBuffMissing", Text("opt.showWhenBuffMissing"),
		Text("opt.showWhenBuffMissing.tip")),
		"hideWhenIdle")
	Under(Slider(category, "fadeOutTime", Text("opt.fadeOutTime"),
		Text("opt.fadeOutTime.tip"),
		0, 10, 0.5, Seconds), "hideWhenIdle")
	-- TICK-0219: a running timer bar stays in view while the HUD hides or
	-- fades (TimerBars.lua moves its holder). The HUD also hides with Hide
	-- when idle off (no spells on the grid), so the row is never gray.
	-- Account wide, as the rows around it.
	Checkbox(category, "timerBarsStay", Text("opt.timerBarsStay"),
		Text("opt.timerBarsStay.tip"))
	Settings.SetOnValueChangedCallback("HUDini_timerBarsStay", function()
		if ns.RefreshTimerBars then ns.RefreshTimerBars() end
	end)
	-- Flair (D-011, TICK-0055): set once, so under Advanced. A proxy, so a
	-- saved value that is not 0, 1 or 2 shows as Light, the level it reads
	-- as. A change shows in the next line HUDini prints: nothing to apply.
	Advanced(layout)
	DropdownFor(category,
		Proxy(category, "flair", Settings.VarType.Number, Text("opt.flair"), 0, ns.FlairLevel,
			function(level) HUDiniDB.flair = level; ns.RetextFlairTips() end, function() end),
		Text("opt.flair.tip"),
		function()
			local out = {}
			for level = 0, 2 do
				out[#out + 1] = { level, ns.Text("flair." .. level), ns.Text("opt.flair." .. level .. ".tip") }
			end
			return out
		end)
end

--------------------------------------------------------------------------------
-- 2. Icons: layout, what each icon shows, which bars
--------------------------------------------------------------------------------

local function BuildIcons(category, layout)
	Header(layout, Text("opt.head.layout"))
	Dropdown(category, "layoutMode", Text("opt.layoutMode"),
		Text("opt.layoutMode.tip"),
		function() return { { "bar", Text("opt.layoutMode.bar") }, { "wrap", Text("opt.layoutMode.wrap") } } end)
	Dropdown(category, "sortMode", Text("opt.sortMode"), Text("opt.sortMode.tip"),
		function() return { { "keybind", Text("opt.sortMode.keybind") }, { "actionbar", Text("opt.sortMode.actionbar") } } end)
	Slider(category, "iconSize", Text("opt.iconSize"), Text("opt.iconSize.tip"), 16, 96, 1, Px)
	Slider(category, "spacing", Text("opt.spacing"), Text("opt.spacing.tip"), 0, 24, 1, Px)
	-- The default Row mode grays these.
	GreyUnless(Slider(category, "maxIcons", Text("opt.maxIcons"),
		Text("opt.maxIcons.tip"),
		1, 48, 1, Icons), Wrapping, "layoutMode")
	GreyUnless(Slider(category, "perRow", Text("opt.perRow"),
		Text("opt.perRow.tip"),
		1, 24, 1, Count), Wrapping, "layoutMode")

	Header(layout, Text("opt.head.onEachIcon"))
	Checkbox(category, "showKeybind", Text("opt.showKeybind"), Text("opt.showKeybind.tip"))
	Checkbox(category, "showTooltips", Text("opt.showTooltips"),
		Text("opt.showTooltips.tip"))
	Checkbox(category, "showCooldown", Text("opt.showCooldown"),
		Text("opt.showCooldown.tip"))
	Checkbox(category, "showProcGlow", Text("opt.showProcGlow"),
		Text("opt.showProcGlow.tip"))
	Checkbox(category, "showAssist", Text("opt.showAssist"), Text("opt.showAssist.tip"))
	Checkbox(category, "showUsable", Text("opt.showUsable"), Text("opt.showUsable.tip"))
	Checkbox(category, "showRange", Text("opt.showRange"), Text("opt.showRange.tip"))
	Checkbox(category, "showBuffTime", Text("opt.showBuffTime"),
		Text("opt.showBuffTime.tip"))

	Advanced(layout)
	Slider(category, "minIcons", Text("opt.minIcons"),
		Text("opt.minIcons.tip"),
		1, 24, 1, Icons)
	-- One choice with four answers, kept as the two flags Core.lua reads.
	DropdownFor(category,
		Proxy(category, "growToward", Settings.VarType.String, Text("opt.growToward"), "DR",
			function() return (HUDiniDB.growDown and "D" or "U") .. (HUDiniDB.growRight and "R" or "L") end,
			function(v)
				HUDiniDB.growDown  = v:sub(1, 1) == "D"
				HUDiniDB.growRight = v:sub(2, 2) == "R"
			end),
		Text("opt.growToward.tip"),
		function()
			return {
				{ "DR", Text("opt.growToward.DR") }, { "DL", Text("opt.growToward.DL") },
				{ "UR", Text("opt.growToward.UR") },   { "UL", Text("opt.growToward.UL") },
			}
		end)

	-- "One row per action bar" always reads Bars 1-3, so the picker only
	-- matters while packing.
	GreyUnless(Checkbox(category, "autoBars", Text("opt.autoBars"),
		Text("opt.autoBars.tip")),
		Wrapping, "layoutMode")
	for i = 2, 8 do
		local key = "bar" .. i -- locale: skip a setting name
		local setting = Register(category, key, Settings.VarType.Boolean,
			Text("opt.barN", i), HUDiniDB.bars, ns.defaults.bars[key])
		Under(Remember(Settings.CreateCheckbox(category, setting, Text("opt.barN.tip", i)), nil, "opt.barN.tip", i),
			function() return Wrapping() and not HUDiniDB.autoBars end, "layoutMode", "autoBars")
	end

	-- No control: this only lets the Defaults button clear your own pairs.
	Proxy(category, "auraMap", Settings.VarType.Boolean, Text("opt.auraMap"), false,
		function() return next(HUDiniDB.auraMap or {}) ~= nil end,
		function(any)
			if not any and HUDiniDB.auraMap then
				wipe(HUDiniDB.auraMap)
				ns.ForgetAuraNames()
			end
		end)
end

--------------------------------------------------------------------------------
-- 3. Bars: what shows, then how it looks, then the sizes
--------------------------------------------------------------------------------

local function BuildBars(category, layout)
	Header(layout, Text("opt.head.yourBars"))
	Checkbox(category, "showHealth", Text("opt.showHealth"), Text("opt.showHealth.tip"))
	Under(Checkbox(category, "damageTrail", Text("opt.damageTrail"),
		Text("opt.damageTrail.tip")),
		"showHealth")
	Checkbox(category, "showPower", Text("opt.showPower"),
		Text("opt.showPower.tip"))
	Under(Checkbox(category, "showPlayerCast", Text("opt.showPlayerCast"),
		Text("opt.showPlayerCast.tip")), "showPower")
	GreyUnless(Checkbox(category, "showResource", Text("opt.showResource"),
		Text("opt.showResource.tip")),
		function() return ClassHas("resource") end, "class_resource")
	Checkbox(category, "showXP", Text("opt.showXP"),
		Text("opt.showXP.tip"))
	Under(Checkbox(category, "showXPRate", Text("opt.showXPRate"),
		Text("opt.showXPRate.tip")),
		"showXP")

	Header(layout, Text("opt.head.targetBars"))
	Checkbox(category, "showTargetHealth", Text("opt.showTargetHealth"),
		Text("opt.showTargetHealth.tip"))
	Under(Checkbox(category, "showTargetPower", Text("opt.showTargetPower"),
		Text("opt.showTargetPower.tip")),
		"showTargetHealth")
	-- TICK-0097: the rank after the target's level (Bars.lua).
	Under(Checkbox(category, "showRankMark", Text("opt.showRankMark"),
		Text("opt.showRankMark.tip")),
		"showTargetHealth")
	Checkbox(category, "showTargetCast", Text("opt.showTargetCast"),
		Text("opt.showTargetCast.tip"))

	Header(layout, Text("opt.head.clicks"))
	Checkbox(category, "clickBars", Text("opt.clickBars"),
		Text("opt.clickBars.tip"))

	-- Bar texture is on the Textures page (TICK-0225).
	Header(layout, Text("opt.head.appearance"))
	-- Each font's name is drawn in that font. Menu text refuses SetFont (the
	-- menu compositor blocks it), but takes a font object, so each font gets
	-- one of its own. Pooled menu text goes back to GameFontHighlight on its
	-- own when the frame is reused, so nothing leaks into other dropdowns.
	local fontObjects = {}
	local function FontObject(key)
		if not fontObjects[key] then
			local object = CreateFont("HUDiniFontPreview_" .. key:gsub("%W", ""))
			object:CopyFontObject(GameFontHighlight)
			object:SetFont(ns.FontPathFor(key), 14, "")
			fontObjects[key] = object
		end
		return fontObjects[key]
	end

	local font = Dropdown(category, "barFont", Text("opt.barFont"),
		Text("opt.barFont.tip"),
		function()
			local out = {}
			for _, e in ipairs(ns.BarFontList()) do out[#out + 1] = { e.key, e.label } end
			return out
		end)
	font.customOptionHandler = function(rootDescription)
		if not rootDescription.EnumerateElementDescriptions then return end
		for _, description in rootDescription:EnumerateElementDescriptions() do
			local data = description.GetData and description:GetData()
			if data and data.value then
				local key = data.value
				description:AddInitializer(function(button)
					local fs = button.Text or button.fontString
					if fs and fs.SetFontObject then fs:SetFontObject(FontObject(key)) end
				end)
			end
		end
	end

	Slider(category, "fontSize", Text("opt.fontSize"), Text("opt.fontSize.tip"), 6, 24, 1, Px)

	-- Under Advanced the sizes no longer sit below their bar, so each says
	-- whose it is.
	Advanced(layout)
	Slider(category, "healthHeight", Text("opt.healthHeight"), Text("opt.healthHeight.tip"),
		8, 80, 1, Px)
	Slider(category, "barHeight", Text("opt.barHeight"), Text("opt.barHeight.tip"), 2, 40, 1, Px)
	GreyUnless(Slider(category, "xpHeight", Text("opt.xpHeight"), Text("opt.xpHeight.tip"), 6, 30, 1, Px),
		On("showXP"), "showXP")
	Slider(category, "barGap", Text("opt.barGap"), Text("opt.barGap.tip"), 0, 12, 1, Px)
	GreyUnless(Slider(category, "castAlpha", Text("opt.castAlpha"),
		Text("opt.castAlpha.tip"), 0.05, 1.0, 0.05, Percent),
		-- TICK-0126: the target's cast rides on its power bar at this opacity too.
		function()
			local db = HUDiniDB
			return (db.showPower and db.showPlayerCast) or db.showTargetCast
		end,
		"showPower", "showPlayerCast", "showTargetCast")
	-- TICK-0097: the PvP mark is on your bar and a player target's, so it
	-- sits with neither group; here it keeps the page at 15 rows above.
	GreyUnless(Checkbox(category, "showPvPMark", Text("opt.showPvPMark"),
		Text("opt.showPvPMark.tip")),
		function() return HUDiniDB.showHealth or HUDiniDB.showTargetHealth end,
		"showHealth", "showTargetHealth")
	-- TICK-0101: the target's level in the game's difficulty color (Bars.lua).
	GreyUnless(Checkbox(category, "colorTargetLevel", Text("opt.colorTargetLevel"),
		Text("opt.colorTargetLevel.tip")),
		On("showTargetHealth"), "showTargetHealth")
	-- TICK-0103: your debuffs on the target, in a row above the HUD
	-- (TargetDebuffs.lua).
	GreyUnless(Checkbox(category, "showTargetDebuffs", Text("opt.showTargetDebuffs"),
		Text("opt.showTargetDebuffs.tip")),
		On("showTargetHealth"), "showTargetHealth")
	-- TICK-0118: the target's buffs, in a row above the debuffs
	-- (TargetDebuffs.lua).
	GreyUnless(Checkbox(category, "showTargetBuffs", Text("opt.showTargetBuffs"),
		Text("opt.showTargetBuffs.tip")),
		On("showTargetHealth"), "showTargetHealth")
	-- TICK-0128: every debuff on you, in a row right of your health bar
	-- (TargetDebuffs.lua).
	GreyUnless(Checkbox(category, "showPlayerDebuffs", Text("opt.showPlayerDebuffs"),
		Text("opt.showPlayerDebuffs.tip")),
		On("showHealth"), "showHealth")
	-- TICK-0106: Dead, Ghost or Offline on your bar and your target's.
	GreyUnless(Checkbox(category, "showDeadState", Text("opt.showDeadState"),
		Text("opt.showDeadState.tip")),
		function() return HUDiniDB.showHealth or HUDiniDB.showTargetHealth end,
		"showHealth", "showTargetHealth")
	-- TICK-0102: health and power numbers. No gray: each number shows only
	-- on a bar that is on (the designer's call).
	Dropdown(category, "barNumbers", Text("opt.barNumbers"), Text("opt.barNumbers.tip"),
		function() return {
			{ "off", Text("opt.barNumbers.off"), Text("opt.barNumbers.off.tip") },
			{ "percent", Text("opt.barNumbers.percent"), Text("opt.barNumbers.percent.tip") },
			{ "number", Text("opt.barNumbers.number"), Text("opt.barNumbers.number.tip") },
			{ "both", Text("opt.barNumbers.both"), Text("opt.barNumbers.both.tip") },
		} end)
	-- TICK-0107: a druid's mana under the power bar in Bear and Cat Form
	-- (Bars.lua). Gray unless the power bar is on and your class can show
	-- mana in a form (its powers list: the druid).
	GreyUnless(Checkbox(category, "showDruidMana", Text("opt.showDruidMana"),
		Text("opt.showDruidMana.tip")),
		function() return HUDiniDB.showPower and ns.HasFormMana() end, "showPower")
	-- TICK-0108: a shaman's totems and their time left (Totems.lua). Your
	-- class never changes while the panel is open, so no key re-grays it.
	GreyUnless(Checkbox(category, "showTotems", Text("opt.showTotems"),
		Text("opt.showTotems.tip")),
		function() return ns.ClassToken() == "SHAMAN" end)
	-- TICK-0158: how a timer bar tells its time. Which spells get one is on
	-- the Your class page; no gray, as that choice is per class. Each timer
	-- bar's texture is in its spell's row there (TICK-0225).
	Dropdown(category, "timerBarTime", Text("opt.timerBarTime"), Text("opt.timerBarTime.tip"),
		function() return {
			{ "seconds", Text("opt.timerBarTime.seconds"), Text("opt.timerBarTime.seconds.tip") },
			{ "percent", Text("opt.timerBarTime.percent"), Text("opt.timerBarTime.percent.tip") },
		} end)
	-- A new time format reaches a timer bar that shows now, in a fight too:
	-- the Apply that Changed queues waits for the fight to end (TICK-0158
	-- review).
	Settings.SetOnValueChangedCallback("HUDini_timerBarTime", function()
		if ns.RefreshTimerBars then ns.RefreshTimerBars() end
	end)
	-- TICK-0169: the timer bars have a place of their own, saved per
	-- class; they move with the HUD lock (a second blue box). This puts
	-- them back under the HUD. In a fight it does nothing (the tip says so).
	Button(layout, Text("opt.timerBarPlace"), Text("opt.timerBarPlace.button"),
		function() if ns.ResetTimerBarsPlace then ns.ResetTimerBarsPlace() end end,
		Text("opt.timerBarPlace.tip"))
end

--------------------------------------------------------------------------------
-- 4. Textures: Bar texture, then a texture button for each bar (TICK-0225)
--
-- Design: docs/design/bar-textures.md. Every row but the first is
-- TICK-0224's texture button (BarLookButton.lua), which paints nothing of
-- its own here. The rows follow the HUD from top to bottom. The class
-- resource bar and the timer bars are saved per class, so they are on the
-- Your class page (one place for each setting). A bar that is off keeps
-- its row, never gray: a texture can be picked first.
--------------------------------------------------------------------------------

-- Each bar on this page: its bar id and its label.
local TEXTURE_ROWS = {
	{ "health",       "opt.look.health" },
	{ "power",        "opt.look.power" },
	{ "druidmana",    "opt.look.druidmana" },
	{ "playercast",   "opt.look.playercast" },
	{ "xp",           "opt.look.xp" },
	{ "targethealth", "opt.look.targethealth" },
	{ "targetpower",  "opt.look.targetpower" },
	{ "targetcast",   "opt.look.targetcast" },
}

local function BuildTextures(category, layout)
	-- Each texture shows a strip of itself, tinted like a health bar, before its
	-- name: "|Tpath:height:width:x:y:texW:texH:left:right:top:bottom:r:g:b|t".
	Dropdown(category, "barTexture", Text("opt.barTexture"),
		Text("opt.barTexture.tip"),
		function()
			local out = {}
			for _, e in ipairs(ns.BarTextureList()) do
				local strip = ("|T%s:14:90:0:0:8:8:0:8:0:8:41:184:56|t"):format(ns.TexturePathFor(e.key))
				out[#out + 1] = { e.key, strip .. "  " .. e.label }
			end
			return out
		end)
	-- A button set to Same as Bar texture shows the new texture at once.
	Settings.SetOnValueChangedCallback("HUDini_barTexture", function()
		if ns.RepaintLookButtons then ns.RepaintLookButtons() end
	end)

	Header(layout, Text("opt.head.eachBar"), Text("opt.head.eachBar.tip"))
	for _, row in ipairs(TEXTURE_ROWS) do
		-- Mana in forms only for a class that has it (options-layout.md
		-- rule 5): your class never changes while the game runs.
		if row[1] ~= "druidmana" or (ns.HasFormMana and ns.HasFormMana()) then
			Remember(ns.AddLookRow(category, layout, { id = row[1], label = Text(row[2]) }),
				Text("opt.look.row.tip"))
		end
	end
end

--------------------------------------------------------------------------------
-- 5. Colors: every bar color, one row each
--------------------------------------------------------------------------------

local function BuildColors(category, layout)
	RegisterColors(category)

	-- A power your class does not use gets no row; its setting is still
	-- registered above, so Defaults resets it.
	local powers = ns.ClassPowerKeys()

	Header(layout, Text("opt.head.yourBars"))
	Swatch(category, layout, "health", Text("opt.color.health.tip"))
	Swatch(category, layout, "trail", Text("opt.color.trail.tip"))
	for _, key in ipairs({ "mana", "rage", "energy" }) do
		if tContains(powers, key) then
			local label = Text(COLOR_LABEL[key])
			Swatch(category, layout, key, Text("opt.color.power.tip", label), "opt.color.power.tip", label)
		end
	end
	if ClassHas("resource") then
		Swatch(category, layout, "resource", Text("opt.color.resource.tip"))
	end
	Swatch(category, layout, "playercast", Text("opt.color.playercast.tip"))
	Swatch(category, layout, "xp", Text("opt.color.xp.tip"))
	Swatch(category, layout, "rested", Text("opt.color.rested.tip"))

	Header(layout, Text("opt.head.targetHealth"))
	Swatch(category, layout, "hostile", Text("opt.color.hostile.tip"))
	Swatch(category, layout, "neutral", Text("opt.color.neutral.tip"))
	Swatch(category, layout, "friendly", Text("opt.color.friendly.tip"))
	Swatch(category, layout, "tapped",
		Text("opt.color.tapped.tip"))

	Header(layout, Text("opt.head.targetCast"))
	Swatch(category, layout, "interrupt", Text("opt.color.interrupt.tip"))
	Swatch(category, layout, "shielded", Text("opt.color.shielded.tip"))

	-- TICK-0158: a druid already has 15 rows above, so the timer bar's
	-- color sits under Advanced.
	if colorSettings.timer then
		Advanced(layout)
		Swatch(category, layout, "timer", Text("opt.color.timer.tip"))
	end
end

--------------------------------------------------------------------------------
-- 6. Alerts: the ones your class has spells for, then the rest
--------------------------------------------------------------------------------

local function BuildAlerts(category, layout)
	-- { class file key, setting, the Your class rows that set it }. The
	-- label and tooltip are opt.<setting> and opt.<setting>.tip.
	local alerts = {
		{ "interrupt", "glowOnKickable", { "class_interrupt" } },
		{ "keepUp", "warnKeepUp", { "class_keepUp" } },
		{ "dispel", "warnDispel", { "class_dispel_Curse", "class_dispel_Poison", "class_dispel_Disease", "class_dispel_Magic" } },
		{ "purge", "showPurgeable", { "class_purge" } },
	}
	-- Built on every class, as the Your class page can give any class the
	-- spell. Gray while it has none; a pick there re-grays the row at once.
	Header(layout, Text("opt.head.alertsForYourClass"))
	for _, a in ipairs(alerts) do
		GreyUnless(Checkbox(category, a[2], Text("opt." .. a[2]), Text("opt." .. a[2] .. ".tip")),
			function() return ClassHas(a[1]) end, unpack(a[3]))
	end

	Header(layout, Text("opt.head.alertsForEveryClass"))
	Checkbox(category, "warnNoBait", Text("opt.warnNoBait"),
		Text("opt.warnNoBait.tip"))
	Checkbox(category, "warnRacial", Text("opt.warnRacial"), Text("opt.warnRacial.tip"))
	Checkbox(category, "warnOwnBuff", Text("opt.warnOwnBuff"),
		Text("opt.warnOwnBuff.tip"))
	Checkbox(category, "warnTargetBuff", Text("opt.warnTargetBuff"),
		Text("opt.warnTargetBuff.tip"))

	-- Sound alerts (TICK-0233 step 3, docs/design/sound-picker.md section 3):
	-- TICK-0235's five sounds, saved for every character, each a picker
	-- that starts Off. Low health and Low mana each have a line slider
	-- under them, gray until their sound has a pick. A class with no mana
	-- gets no Low mana rows; their settings are still registered, so
	-- Defaults resets them.
	if not ns.SOUND_ALERTS then return end
	Advanced(layout)
	Header(layout, Text("opt.head.soundAlerts"), Text("opt.head.soundAlerts.tip"))
	local hasMana = tContains(ns.ClassPowerKeys(), "mana")
	local LABEL = {
		soundCombatStart = "opt.sound.combatStart", soundCombatEnd = "opt.sound.combatEnd",
		soundLowHealth = "opt.sound.lowHealth", soundLowMana = "opt.sound.lowMana",
		soundHonorKill = "opt.sound.honorKill",
		soundLowHealthAt = "opt.sound.lowHealthAt", soundLowManaAt = "opt.sound.lowManaAt",
	}
	local function Pct(v) return ("%d%%"):format(v) end
	for _, a in ipairs(ns.SOUND_ALERTS) do
		local key = LABEL[a.setting]
		local function Choice() return HUDiniDB and ns.SoundChoice(HUDiniDB[a.setting], a.sound) or nil end
		-- The proxy has no control of its own: Defaults writes Off through
		-- it, and the line under it re-grays on its change. A pick in the
		-- picker announces itself through it (NotifyUpdate).
		local setting = Proxy(category, a.setting, Settings.VarType.String, Text(key), "off",
			function() local c = Choice(); return c and c.key or "off" end,
			function(pick)
				ns.SetSoundAlert(a.setting, pick ~= "off" and ns.NewSoundChoice(pick, 100) or false)
			end,
			function() if ns.RepaintSoundPickers then ns.RepaintSoundPickers() end end)
		local line
		if a.line then
			local L = ns.SOUND_ALERT_LINE
			line = Proxy(category, a.line, Settings.VarType.Number, Text(LABEL[a.line]), L.default,
				function() return ns.SoundAlertLine(HUDiniDB[a.line]) end,
				function(v) ns.SetSoundAlertLine(a.line, v) end)
		end
		if a.setting ~= "soundLowMana" or hasMana then
			local tip = Text(key .. ".tip")
			local bind = {
				get = function() return Choice() or false end,
				set = function(choice)
					if ns.SetSoundAlert(a.setting, choice or false) and setting.NotifyUpdate then
						setting:NotifyUpdate()
					end
				end,
				default = a.sound, withOff = true, label = Text(key), tip = tip,
			}
			Remember(ns.AddSoundRow and ns.AddSoundRow(category, layout, bind), tip)
			flairFns[#flairFns + 1] = function() bind.tip = Text(key .. ".tip"); bind.label = Text(key) end
			if line then
				local L = ns.SOUND_ALERT_LINE
				Under(SliderFor(category, line, Text(LABEL[a.line] .. ".tip"), L.min, L.max, L.step, Pct),
					function() return Choice() ~= nil end, a.setting)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The class resource bar's texture button (TICK-0225)
--------------------------------------------------------------------------------

-- The row's tooltip: it names the lightning art (TICK-0221), which no
-- texture changes, while that is the resource. Bars.lua's
-- ns.ResourceIsLightning gives the art's own answer (TICK-0231).
function ns.ResourceLookTip()
	local lightning = ns.ResourceIsLightning and ns.ResourceIsLightning()
	return Text(lightning and "opt.class.resourceLook.tipLightning" or "opt.class.resourceLook.tip")
end

-- Gray with no class resource the bar can show, or with Show class
-- resource off. ns.ClassResource is the bar's own answer (TICK-0199): a
-- class file's buff counts only once it is on you or you know its spell,
-- so a Shaman below level 8 (no Lightning Shield yet) sees the row gray.
local function ResourceLookOn()
	return HUDiniDB ~= nil and HUDiniDB.showResource and ns.ClassResource and ns.ClassResource()
		and true or false
end
ns.ResourceLookOn = ResourceLookOn

-- The row: TICK-0224's, with two changes. Its tooltip names the lightning
-- art while that is the resource: the button reads look.tip on each
-- mouseover (HUDini's own code only), and the row's tooltip stays a string
-- that a resource pick or a flair change writes again, as Blizzard's
-- settings search reads it too. The game grays no part of this row: on
-- its bare template, EvaluateState only shows or hides it
-- (Blizzard_SettingControls.lua:416-419, wow-ui-source forever 9dc84f0;
-- TICK-0240), so GreyUnless leaves the label as it is. The row grays the
-- button itself, on each draw and on each change of the two settings; a
-- frame given to another row is enabled again.
function ns.AddResourceLookRow(category, layout)
	local look = setmetatable({ id = "resource", label = Text("opt.class.resourceLook") },
		{ __index = function(_, k) if k == "tip" then return ns.ResourceLookTip() end end })
	local init = ns.AddLookRow(category, layout, look)
	if not init then return end
	local function Retext() init.data.tooltip = ns.ResourceLookTip() end
	Retext()
	flairFns[#flairFns + 1] = Retext
	local draw, reset, shown = init.InitFrame, init.Resetter, nil
	local function Paint(frame, on)
		local b = frame and frame.hudiniLook
		if not b then return end
		b:SetEnabled(on)
		b:SetAlpha(on and 1 or 0.5)
	end
	init.InitFrame = function(i, frame)
		draw(i, frame)
		shown = frame
		Paint(frame, ResourceLookOn())
	end
	init.Resetter = function(i, frame)
		if shown == frame then shown = nil end
		Paint(frame, true)
		reset(i, frame)
	end
	for _, key in ipairs({ "class_resource", "showResource" }) do
		Settings.SetOnValueChangedCallback("HUDini_" .. key, function()
			Retext()
			Paint(shown, ResourceLookOn())
		end)
	end
	return GreyUnless(init, ResourceLookOn, "class_resource", "showResource")
end

--------------------------------------------------------------------------------
-- 7. Your class: which spell each alert uses, saved for this class only
--
-- Every row is built on every class, so a
-- player can add the spell a class file lacks. Each spell row is a proxy
-- over ns.GetClassPick / ns.SetClassPick (Classes.lua); the setter only
-- saves, and the row's callback applies. Its default is Class default, so
-- this page's Defaults resets the class you are playing, and no other.
--------------------------------------------------------------------------------

-- A pick the action bars do not list: an ID typed with the old command shows
-- as "2139 (Counterspell)", a list as typed. A secret name shows the ID.
local function PickLabel(pick)
	local id = tonumber(pick)
	if not id then return pick end
	local ok, name = pcall(C_Spell.GetSpellName, id)
	if ok and not ns.IsSecret(name) and type(name) == "string" then
		return id .. " (" .. name .. ")"
	end
	return pick
end

-- Class default, None, the spells on your action bars, or for Resource the
-- buffs HUDini saw stack (A to Z, each once: ns.ClassPickSpells), then your
-- pick if none of those.
local function PickChoices(key, dispelType)
	return function()
		local name, noneKnown = ns.ClassDefaultName(key, dispelType)
		local first = name and Text("opt.class.default", name)
			or noneKnown and Text("opt.class.defaultUnknown")
			or Text("opt.class.defaultNone")
		local out = { { ns.PICK_DEFAULT, first }, { ns.PICK_NONE, Text("opt.class.none") } }
		local listed = { [ns.PICK_DEFAULT] = true, [ns.PICK_NONE] = true }
		for _, spell in ipairs(ns.ClassPickSpells(key)) do
			if not listed[spell] then
				out[#out + 1] = { spell, spell }
				listed[spell] = true
			end
		end
		local pick = ns.GetClassPick(key, dispelType)
		if pick and not listed[pick] then out[#out + 1] = { pick, PickLabel(pick) } end
		return out
	end
end

local function BuildYourClass(category, layout)
	-- One spell row. onSet runs after the pick is saved, inside the setter
	-- (rule 1, TICK-0068 Notes).
	local function Pick(key, label, tooltip, dispelType, onSet)
		local name = "class_" .. key .. (dispelType and ("_" .. dispelType) or "") -- locale: skip a setting name
		local setting = Proxy(category, name, Settings.VarType.String, label, ns.PICK_DEFAULT,
			function() return ns.GetClassPick(key, dispelType) or ns.PICK_DEFAULT end,
			function(pick)
				ns.SetClassPick(key, pick, dispelType)
				if onSet then onSet() end
			end)
		return setting, DropdownFor(category, setting, tooltip, PickChoices(key, dispelType))
	end

	Header(layout, (UnitClass("player")) or Text("page.class"), Text("opt.head.class.tip"))

	-- A spell pick of None grays its Sound alerts picker (below, TICK-0233).
	local function RepaintPickers()
		if ns.RepaintSoundPickers then ns.RepaintSoundPickers() end
	end

	Header(layout, Text("opt.head.interrupt"))
	Pick("interrupt", Text("opt.class.interrupt"),
		Text("opt.class.interrupt.tip"), nil, RepaintPickers)

	Header(layout, Text("opt.head.dispel"))
	for _, dispelType in ipairs(ns.DISPEL_TYPES) do
		local _, row = Pick("dispel", dispelType, Text("opt.class.dispel.tip", dispelType, dispelType, dispelType), dispelType,
			RepaintPickers)
		-- Its tooltip joins in the kind, so its key is not found from its text.
		Remember(row, nil, "opt.class.dispel.tip", dispelType, dispelType, dispelType)
	end

	Header(layout, Text("opt.head.purge"))
	Pick("purge", Text("opt.class.purge"),
		Text("opt.class.purge.tip"), nil, RepaintPickers)

	Header(layout, Text("opt.head.buffs"))
	Pick("keepUp", Text("opt.class.keepUp"),
		Text("opt.class.keepUp.tip"))
	-- The Settings dropdown holds no check marks, so this is the design's
	-- fallback. /hud buffs still lists them and forgets one.
	Button(layout, Text("opt.trackedBuffs"), Text("opt.trackedBuffs.button"),
		function() ns.BuffsCommand("clear", function() end) end, Text("opt.trackedBuffs.tip"))
	-- A sound when either red icon left of the health bar turns on in a
	-- fight: the personal buff (Lightning Shield) or the combat buff. Saved
	-- per class (TICK-0163), with its volume (TICK-0232). Off, or the sound
	-- to play: one row, the sound picker (D-051, TICK-0233), whose Off
	-- turns it off. It stays above Advanced: it starts on for seven
	-- classes, so the new player is the one who turns it off
	-- (docs/design/sound-picker.md). Gray unless one of the two icons can
	-- show.
	--
	-- The proxy setting stays, with no control of its own: Defaults resets
	-- it, and HUDini setup's sound box repaints the row by its name. The
	-- picker reads and writes the saved choice itself. Its default is the
	-- class's start, a plain value known at build: Raid warning for a class
	-- whose sound starts on (keepUpSoundOn), else Off. Defaults writes that
	-- start at full volume, which saves as the start does (true).
	local function KeepUpSoundOn()
		return HUDiniDB.showHealth and (HUDiniDB.warnOwnBuff or HUDiniDB.warnKeepUp) and true or false
	end
	local keepUpSetting = Proxy(category, "class_keepUpSound", Settings.VarType.String,
		Text("opt.class.keepUpSound"),
		ns.ClassDefault and ns.ClassDefault("keepUpSoundOn") == true and ns.MISSING_SOUND_DEFAULT or "off",
		function() return ns.GetKeepUpSoundChoice and ns.GetKeepUpSoundChoice() or "off" end,
		function(pick)
			if not ns.SetKeepUpSound then return end
			if pick == "off" then ns.SetKeepUpSound("off") else ns.SetKeepUpSound({ key = pick, volume = 100 }) end
		end,
		function() if ns.RepaintSoundPickers then ns.RepaintSoundPickers() end end)
	local keepUpTip = Text("opt.class.keepUpSound.tip")
	local keepUpBind = {
		get = function() return ns.GetKeepUpSoundValue and ns.GetKeepUpSoundValue() or false end,
		-- A pick announces itself through the proxy, so Repeat re-grays.
		set = function(choice)
			if ns.SetKeepUpSound and ns.SetKeepUpSound(choice or false) and keepUpSetting.NotifyUpdate then
				keepUpSetting:NotifyUpdate()
			end
		end,
		default = ns.MISSING_SOUND_DEFAULT,
		withOff = true,
		label = Text("opt.class.keepUpSound"),
		tip = keepUpTip,
		enabled = KeepUpSoundOn,
	}
	local keepUpRow = ns.AddSoundRow and ns.AddSoundRow(category, layout, keepUpBind)
	GreyUnless(Remember(keepUpRow, keepUpTip), KeepUpSoundOn, "showHealth", "warnOwnBuff", "warnKeepUp")
	-- The picker's own tooltip follows a flair change, as the row's does.
	flairFns[#flairFns + 1] = function()
		keepUpBind.tip = Text("opt.class.keepUpSound.tip")
		keepUpBind.label = Text("opt.class.keepUpSound")
	end
	-- Repeat (TICK-0234): the sound again every few seconds while a red
	-- icon shows in a fight. Saved per class, off until you turn it on.
	-- Gray unless the row above can play: not gray, with a sound picked.
	if ns.GetKeepUpRepeat and ns.SetKeepUpRepeat then
		local again = Proxy(category, "class_keepUpRepeat", Settings.VarType.Boolean, Text("opt.class.keepUpRepeat"), -- locale: skip a setting name
			false, function() return ns.GetKeepUpRepeat() end, function(on) ns.SetKeepUpRepeat(on) end)
		local againTip = Text("opt.class.keepUpRepeat.tip")
		Under(Remember(Settings.CreateCheckbox(category, again, againTip), againTip),
			function()
				return KeepUpSoundOn() and ns.GetKeepUpSoundValue ~= nil
					and ns.SoundChoice(ns.GetKeepUpSoundValue(), ns.MISSING_SOUND_DEFAULT) ~= nil
			end, "showHealth", "warnOwnBuff", "warnKeepUp", "class_keepUpSound")
	end
	-- The weapon buff alert (TICK-0250, TICK-0251): out of a fight, a weapon
	-- you hold with no weapon buff shows in the own-buff icon by the health
	-- bar. Only a class whose file has weaponBuff gets the row (the Rogue and
	-- the Shaman), as the pet row. Saved per class, on until you turn it off,
	-- so its default is a plain true. Gray unless that icon can show: the
	-- health bar and the personal buff reminder (General). A change shows
	-- at once (ns.RefreshWeaponBuffAlert), and its sound row re-grays.
	local function WeaponBuffOn()
		return HUDiniDB.showHealth and HUDiniDB.warnOwnBuff and true or false
	end
	if ns.HasWeaponBuffAlert and ns.HasWeaponBuffAlert() then
		local weapon = Proxy(category, "class_weaponBuffAlert", Settings.VarType.Boolean, -- locale: skip a setting name
			Text("opt.class.weaponBuffAlert"), true,
			function() return ns.GetWeaponBuffAlert() end,
			function(on) ns.SetWeaponBuffAlert(on) end,
			function()
				if ns.RefreshWeaponBuffAlert then ns.RefreshWeaponBuffAlert() end
				if ns.RepaintSoundPickers then ns.RepaintSoundPickers() end
			end)
		local weaponTip = Text("opt.class.weaponBuffAlert.tip")
		GreyUnless(Remember(Settings.CreateCheckbox(category, weapon, weaponTip), weaponTip),
			WeaponBuffOn, "showHealth", "warnOwnBuff")
	end
	-- The game grays the label; the picker reads enabled on a repaint.
	for _, key in ipairs({ "showHealth", "warnOwnBuff", "warnKeepUp" }) do
		Settings.SetOnValueChangedCallback("HUDini_" .. key, function()
			if ns.RepaintSoundPickers then ns.RepaintSoundPickers() end
		end)
	end

	-- The ammo alert (TICK-0193, TICK-0237): "Low ammo" or "No ammo" left
	-- of the health bar, with a bow, gun or crossbow. Saved per class, on
	-- for a Hunter only until you pick. Its default is that class default,
	-- a plain value known at build, so Defaults gives it back. Gray without
	-- the health bar: the icon sits by it. Only a class that can use a bow,
	-- gun or crossbow gets the row (TICK-0241: a Shaman saw it).
	local token = ns.ClassToken and ns.ClassToken()
	if token == "HUNTER" or token == "WARRIOR" or token == "ROGUE" then
		Header(layout, Text("opt.head.ammo"))
		local ammo = Proxy(category, "class_ammo", Settings.VarType.Boolean, Text("opt.class.ammo"), -- locale: skip a setting name
			token == "HUNTER",
			function() return ns.GetAmmoWarn() end,
			function(on) ns.SetAmmoWarn(on) end)
		local ammoTip = Text("opt.class.ammo.tip")
		GreyUnless(Remember(Settings.CreateCheckbox(category, ammo, ammoTip), ammoTip),
			On("showHealth"), "showHealth")
	end

	-- The pet alert (TICK-0192): the spell your pet needs, left of the
	-- health bar. Only a class whose file has a pet field gets the row (and
	-- its setting); saved per class, on until you turn it off, so its
	-- default is a plain true. Gray without the health bar, as the ammo.
	if ns.PetAlertData and type(ns.PetAlertData()) == "table" then
		Header(layout, Text("opt.head.pet"))
		local pet = Proxy(category, "class_pet", Settings.VarType.Boolean, Text("opt.class.pet"), -- locale: skip a setting name
			true,
			function() return ns.GetPetAlert() end,
			function(on) ns.SetPetAlert(on) end)
		local petTip = Text("opt.class.pet.tip")
		GreyUnless(Remember(Settings.CreateCheckbox(category, pet, petTip), petTip),
			On("showHealth"), "showHealth")
	end

	Header(layout, Text("opt.head.resource"))
	-- A new resource pick changes the stacks, and whether they mean anything.
	local stacks
	Pick("resource", Text("opt.class.resource"),
		Text("opt.class.resource.tip"),
		nil, function() if stacks and stacks.NotifyUpdate then stacks:NotifyUpdate() end end)
	-- No default: the Resource row's reset is what clears the stacks, so
	-- Defaults calls no setter here. Not a function default: it taints the
	-- game's settings code (Proxy, TICK-0089).
	local function Stacks() return ns.ResourceStacks() or 5 end
	stacks = Proxy(category, "class_resourceStacks", Settings.VarType.Number, Text("opt.class.resourceStacks"),
		nil, Stacks, function(n) ns.SetResourceStacks(n) end)
	GreyUnless(SliderFor(category, stacks,
		Text("opt.class.resourceStacks.tip"), 1, 20, 1, Count),
		function() return ns.ResourceStacks() ~= nil end, "class_resource")

	-- The class resource bar's texture button (TICK-0225, bar-textures.md):
	-- it is saved per class, so it ends this section, not the Textures page.
	ns.AddResourceLookRow(category, layout)

	-- Cooldowns (D-041, D-048): one row per spell, with three controls side
	-- by side: Ready glow, Timer bar and Sound. None grays another, so any
	-- mix works. The row's label is the spell's own name. A game row holds
	-- one control, and the game's check box with a dropdown grays the
	-- dropdown while the box is off, so this row is HUDini's own: the
	-- template in OptionsGrid.xml is the game's list element (label, label
	-- tooltip, hover, search), and the controls are the game's check box
	-- and dropdown, made once per frame and bound on each draw. A row of
	-- column heads comes first in each Cooldowns group.
	--
	-- Each spell keeps three settings, <name>_glow, _bar and _sound, so the
	-- setup boxes and a repaint work as on any row. None has a default:
	-- Defaults leaves them as they are (Proxy). <name> is the spell's
	-- letters. Two names with the same letters, or a name with
	-- none (a ruRU, koKR or zhCN client), get a number from the name's
	-- bytes: the game throws on a name it already has (TICK-0162 review).
	local hasRow, usedName, rowName = {}, {}, {}
	local function SettingName(spell)
		local base = "class_cooldown_" .. spell:gsub("[^%w]", "") -- locale: skip a setting name
		if base ~= "class_cooldown_" and not usedName[base] then return base end
		local h = 5381
		for i = 1, #spell do h = (h * 33 + spell:byte(i)) % 4294967296 end
		local name, n = base .. "_" .. h, 1
		while usedName[name] do name, n = base .. "_" .. h .. "_" .. n, n + 1 end
		return name
	end
	-- HUDini setup repaints a spell's controls by name (Setup.lua). A spell
	-- with no row yet gets the name its row would get; the panel finds no
	-- setting by it, and repaints nothing.
	local function Base(spell)
		return rowName[spell] or "class_cooldown_" .. (spell:gsub("[^%w]", "")) -- locale: skip a setting name
	end
	function ns.CooldownSettingNames(spell)
		local base = Base(spell)
		return { base .. "_glow", base .. "_bar", base .. "_sound" } -- locale: skip setting names
	end
	-- The ready glow's setting: the setup box's ready alert turns it on.
	function ns.CooldownSettingName(spell) return Base(spell) .. "_glow" end -- locale: skip a setting name

	-- The developer's API (D-048), with today's names until it lands.
	local function GetGlow(spell)
		local get = ns.GetCooldownGlow or ns.GetReadyAlert
		return get and get(spell) and true or false
	end
	local function SetGlow(spell, on)
		local set = ns.SetCooldownGlow or ns.SetReadyAlert
		if set then set(spell, on) end
	end
	local function GetBar(spell) return ns.GetTimerBar and ns.GetTimerBar(spell) and true or false end
	local function SetBar(spell, on) if ns.SetTimerBar then ns.SetTimerBar(spell, on) end end
	local function GetSound(spell) return ns.GetCooldownSound and ns.GetCooldownSound(spell) or "off" end
	local function SetSound(spell, key) if ns.SetCooldownSound then ns.SetCooldownSound(spell, key) end end
	-- The Sound column's picker (D-051, TICK-0233), bound on each draw, so
	-- its tooltip follows a flair change. It reads and writes the choice
	-- itself (key and volume); the _sound setting stays for HUDini setup's
	-- repaint by name.
	local function SoundBind(spell)
		return {
			get = function() return ns.GetCooldownSoundValue and ns.GetCooldownSoundValue(spell) or false end,
			set = function(choice) SetSound(spell, choice or false) end,
			default = ns.READY_SOUND_DEFAULT,
			withOff = true,
			label = Text("opt.cd.sound"),
			tip = Text("opt.cd.sound.tip"),
		}
	end

	-- The game's objects HUDini reads and never writes.
	local G = _G
	local COLUMNS = { "glow", "bar", "sound" }
	-- A control's tooltip and its column head's are one text, read on each
	-- mouseover, so a flair change shows on the next one.
	local function ColumnTip(key)
		return function() Settings.InitTooltip(Text("opt.cd." .. key), Text("opt.cd." .. key .. ".tip")) end
	end
	-- The controls, once per frame: the frames of this template are pooled
	-- and drawn again for other rows.
	local function Build(frame)
		if frame.hudiniGrid then return frame.hudiniGrid end
		local g, mixin = { heads = {} }, G.DefaultTooltipMixin
		g.glow = CreateFrame("CheckButton", nil, frame, "SettingsCheckboxTemplate")
		g.glow:SetPoint("LEFT", frame, "CENTER", -120, 0)
		g.bar = CreateFrame("CheckButton", nil, frame, "SettingsCheckboxTemplate")
		g.bar:SetPoint("LEFT", frame, "CENTER", -50, 0)
		-- The timer bar's texture button (TICK-0225), next to its box: the
		-- two make one column, Timer bar.
		g.look = ns.CreateLookButton(frame, 60)
		g.look:SetPoint("LEFT", frame, "CENTER", -16, 0)
		-- The sound picker (TICK-0233): its list 150 px, its volume slider
		-- the rest. The columns sit 40 px further left than before it, so
		-- it fits the row (docs/design/sound-picker.md).
		g.sound = ns.CreateSoundPicker(frame, 230)
		g.sound:SetPoint("LEFT", frame, "CENTER", 52, 0)
		-- The heads sit over the controls' centers: a box is 30 px wide. The
		-- Timer bar head spans its box and its texture button.
		local at = { glow = { -105, 70 }, bar = { -3, 94 }, sound = { 167, 230 } }
		for _, key in ipairs(COLUMNS) do
			local head = CreateFrame("Frame", nil, frame)
			head:SetSize(at[key][2], 22)
			head:SetPoint("CENTER", frame, "CENTER", at[key][1], 0)
			head.Text = head:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
			head.Text:SetPoint("CENTER")
			head:EnableMouse(true)
			if mixin then
				G.Mixin(head, mixin)
				mixin.OnLoad(head)
				head:SetTooltipFunc(ColumnTip(key))
			end
			g.heads[key] = head
		end
		frame.hudiniGrid = g
		return g
	end
	-- Draw one row: the game's part first (it asks for no callback yet),
	-- then the controls, each bound to its setting both ways.
	local function InitGrid(init, frame)
		local g, data = Build(frame), init.data
		frame:Init(init)
		local head = data.gridHead == true
		frame.Tooltip:SetShown(not head)
		for _, key in ipairs(COLUMNS) do
			g.heads[key]:SetShown(head)
			g.heads[key].Text:SetText(Text("opt.cd." .. key))
			g[key]:SetShown(not head)
		end
		g.look:SetShown(not head)
		if head then return end
		ns.BindLookButton(g.look, data.look)
		local glow, bar, pick = data.grid.glow, data.grid.bar, data.grid.sound
		local event = G.SettingsCheckboxMixin and G.SettingsCheckboxMixin.Event.OnValueChanged
		for _, pair in ipairs({ { g.glow, glow, "glow" }, { g.bar, bar, "bar" } }) do
			local box, setting = pair[1], pair[2]
			box:Init(setting:GetValue(), ColumnTip(pair[3]))
			frame.cbrHandles:RegisterCallback(box, event, function(_, checked) setting:SetValue(checked) end, frame)
		end
		ns.BindSoundPicker(g.sound, SoundBind(data.name))
		-- A change to any of the three repaints all three: HUDini setup's
		-- ready alert box (ns.SetReadyAlert) turns the glow and the sound on
		-- together, and repaints only the glow's setting (Setup.lua).
		local function Repaint()
			g.glow:SetChecked(glow:GetValue())
			g.bar:SetChecked(bar:GetValue())
			ns.RepaintSoundPickers()
		end
		for _, setting in ipairs({ glow, bar, pick }) do
			frame.cbrHandles:SetOnValueChangedCallback(setting:GetVariable(), Repaint, frame)
		end
	end
	local function ResetGrid(_, frame)
		local g = frame.hudiniGrid
		if g then
			g.glow:Release()
			g.bar:Release()
			-- The pooled frame goes to another row: let its texture button
			-- go, so a look change no longer repaints it (TICK-0231).
			ns.UnbindLookButton(g.look)
			ns.UnbindSoundPicker(g.sound)
		end
		frame:Release()
	end
	-- A grid row's initializer: the game's list element, drawn by InitGrid.
	-- Without the game's element initializer (the test harness) the row is
	-- not added; its settings still are.
	local function GridRow(data)
		if not Settings.CreateElementInitializer then return end
		local init = Settings.CreateElementInitializer("HUDiniCooldownRowTemplate", data)
		init.InitFrame, init.Resetter = InitGrid, ResetGrid
		layout:AddInitializer(init)
		return init
	end
	-- The column heads, as high as a spell row (the template's 26). Each
	-- spell's name is a search tag on it too, so a search for a spell
	-- shows the heads above its row.
	local headInit
	local function HeadRow()
		headInit = GridRow({ name = "", gridHead = true })
	end
	local function Row(spell, tooltip)
		hasRow[spell] = true
		local base = SettingName(spell)
		usedName[base], rowName[spell] = true, base
		local glow = Proxy(category, base .. "_glow", Settings.VarType.Boolean, spell, nil, -- locale: skip a setting name
			function() return GetGlow(spell) end, function(on) SetGlow(spell, on) end)
		local bar = Proxy(category, base .. "_bar", Settings.VarType.Boolean, spell, nil, -- locale: skip a setting name
			function() return GetBar(spell) end, function(on) SetBar(spell, on) end)
		local pick = Proxy(category, base .. "_sound", Settings.VarType.String, spell, nil, -- locale: skip a setting name
			function() return GetSound(spell) end, function(key) SetSound(spell, key) end)
		-- The timer bar's look (TICK-0225): three settings with fixed
		-- defaults, so Defaults resets them. Never gray: a texture can be
		-- picked before the bar is on. The tooltip is read on each mouseover.
		local look = setmetatable({ id = ns.TimerLookId(spell), label = spell, allTimers = true },
			{ __index = function(_, k) if k == "tip" then return Text("opt.cd.bar.tip") end end })
		ns.BarLookSettings(category, look.id, base .. "_look") -- locale: skip a setting name
		local init = GridRow({ name = spell, tooltip = tooltip,
			grid = { glow = glow, bar = bar, sound = pick }, look = look })
		if init and init.AddSearchTags then init:AddSearchTags(spell) end
		if headInit and headInit.AddSearchTags then headInit:AddSearchTags(spell) end
		return Remember(init, tooltip)
	end

	Advanced(layout)

	-- Sound alerts (TICK-0233 step 2, TICK-0234, docs/design/sound-picker.md
	-- section 2): a sound for each class alert, saved per class, each a
	-- picker that starts Off. Only the alerts your class has get a row
	-- (ns.ClassAlertSounds, the rule of the ammo row); all six settings are
	-- registered, so Defaults resets them. A row is gray while its alert is
	-- off or its spell is None. They come right after the Advanced header,
	-- before the rows made at the first open.
	if ns.CLASS_ALERT_SOUNDS and ns.ClassAlertSounds then
		local ALERT = { interrupt = "glowOnKickable", dispel = "warnDispel", purge = "showPurgeable" }
		local mine = {}
		for _, a in ipairs(ns.ClassAlertSounds()) do mine[a.setting] = true end
		local built
		for _, a in ipairs(ns.CLASS_ALERT_SOUNDS) do
			local key = "opt.class.sound." .. (a.dispel or a.alert) -- locale: skip a key prefix
			local pickName = "class_" .. a.alert .. (a.dispel and ("_" .. a.dispel) or "") -- locale: skip a setting name
			local function Choice() return ns.SoundChoice(ns.GetClassAlertSound(a.setting), a.sound) end
			local function Usable()
				if not HUDiniDB[ALERT[a.alert]] then return false end
				if a.dispel then
					local dispel = ns.ClassValue("dispel")
					return type(dispel) == "table" and dispel[a.dispel] ~= nil
				end
				return ClassHas(a.alert)
			end
			-- No control of its own: Defaults writes Off through it, and a
			-- pick in the picker announces itself through it.
			local setting = Proxy(category, "class_" .. a.setting, Settings.VarType.String, Text(key), "off", -- locale: skip a setting name
				function() local c = Choice(); return c and c.key or "off" end,
				function(pick)
					ns.SetClassAlertSound(a.setting, pick ~= "off" and ns.NewSoundChoice(pick, 100) or false)
				end,
				function() if ns.RepaintSoundPickers then ns.RepaintSoundPickers() end end)
			if mine[a.setting] then
				if not built then
					Header(layout, Text("opt.head.soundAlerts"), Text("opt.head.classSoundAlerts.tip"))
					built = true
				end
				local tip = Text(key .. ".tip")
				local bind = {
					get = function() return ns.GetClassAlertSound(a.setting) end,
					set = function(choice)
						if ns.SetClassAlertSound(a.setting, choice or false) and setting.NotifyUpdate then
							setting:NotifyUpdate()
						end
					end,
					default = a.sound, withOff = true, label = Text(key), tip = tip, enabled = Usable,
				}
				GreyUnless(Remember(ns.AddSoundRow and ns.AddSoundRow(category, layout, bind), tip),
					Usable, ALERT[a.alert], pickName)
				flairFns[#flairFns + 1] = function() bind.tip = Text(key .. ".tip"); bind.label = Text(key) end
			end
		end
		-- The weapon buff sound (TICK-0251): its setting is beside the list
		-- (Alerts.lua ns.WEAPON_BUFF_SOUND), so it gets its row here, last,
		-- for a class with the weapon buff alert. Starts Off, as the others.
		-- Gray unless its alert can show: the alert on, the health bar and
		-- the personal buff reminder (the alert's own repaint, above).
		local wb = ns.WEAPON_BUFF_SOUND
		if wb and ns.GetWeaponBuffAlert then
			local key = "opt.class.sound." .. wb.alert -- locale: skip a key prefix
			local function Choice() return ns.SoundChoice(ns.GetClassAlertSound(wb.setting), wb.sound) end
			local function Usable()
				return HUDiniDB.showHealth and HUDiniDB.warnOwnBuff and ns.GetWeaponBuffAlert() and true or false
			end
			local setting = Proxy(category, "class_" .. wb.setting, Settings.VarType.String, Text(key), "off", -- locale: skip a setting name
				function() local c = Choice(); return c and c.key or "off" end,
				function(pick)
					ns.SetClassAlertSound(wb.setting, pick ~= "off" and ns.NewSoundChoice(pick, 100) or false)
				end,
				function() if ns.RepaintSoundPickers then ns.RepaintSoundPickers() end end)
			if ns.HasWeaponBuffAlert and ns.HasWeaponBuffAlert() then
				if not built then
					Header(layout, Text("opt.head.soundAlerts"), Text("opt.head.classSoundAlerts.tip"))
				end
				local tip = Text(key .. ".tip")
				local bind = {
					get = function() return ns.GetClassAlertSound(wb.setting) end,
					set = function(choice)
						if ns.SetClassAlertSound(wb.setting, choice or false) and setting.NotifyUpdate then
							setting:NotifyUpdate()
						end
					end,
					default = wb.sound, withOff = true, label = Text(key), tip = tip, enabled = Usable,
				}
				GreyUnless(Remember(ns.AddSoundRow and ns.AddSoundRow(category, layout, bind), tip),
					Usable, "showHealth", "warnOwnBuff", "class_weaponBuffAlert")
				flairFns[#flairFns + 1] = function() bind.tip = Text(key .. ".tip"); bind.label = Text(key) end
			end
		end
		-- The game grays the label; the picker reads enabled on a repaint. A
		-- spell pick repaints through its own onSet (Pick, above).
		for _, k in ipairs({ "glowOnKickable", "warnDispel", "showPurgeable" }) do
			Settings.SetOnValueChangedCallback("HUDini_" .. k, function()
				if ns.RepaintSoundPickers then ns.RepaintSoundPickers() end
			end)
		end
	end

	-- Then the Cooldowns group (TICK-0201): a row for each spell you know,
	-- the class file's first in its order, then every other spell you
	-- learned with a cooldown (TICK-0162, D-042), A to Z. A spell you do
	-- not know gets no row, unless you saved a bell or a bar for it, so you
	-- can turn it off. A class file may name 13 spells (all races'
	-- racials), and a gray row for each would bury the page; so the group
	-- sits at the end, under Advanced, and the top of the page stays inside
	-- 15 rows. The game's settings window only adds rows at the end, and
	-- the book is read only out of a fight (at load it may not be read
	-- yet), so the panel adds the rows of new spells each time it opens out
	-- of a fight; those go at the end of their group (TICK-0243: see
	-- Place, below). A row is never removed.
	local function Known(spell)
		return not ns.KnownSpell or ns.KnownSpell(spell) and true or false
	end
	-- The saved choice only, not a class default (TICK-0181): a default
	-- bell for another race's racial gives no row.
	local function SavedOn(spell)
		return HUDiniDB ~= nil and ns.CooldownSaved ~= nil and ns.CooldownSaved(spell)
	end
	-- Missing items (TICK-0182): a check box for each row of the class file
	-- whose spell you know (make, or one of needs), or whose pick you saved;
	-- the rule of the cooldown rows and of HUDini setup's boxes. They come
	-- before the cooldown rows; a row for a spell learned later goes at the
	-- end of this group (TICK-0243), under its one header. The label is
	-- the item's name from the game, or its spell's name while the game
	-- has not loaded the item. Gray without the
	-- health bar: the icon sits by it. HUDini setup's boxes repaint these by
	-- name ("class_item_" .. key).
	local hasItemRow, hasHeader, lastGroup = {}, {}, nil
	-- A group writes its header once (TICK-0243). Place, below, moves a
	-- late row up into its group; a layout with no list to move in (none
	-- the game has today) gets a header each time the group changes, as
	-- before.
	local rowList = layout.GetInitializers and layout:GetInitializers()
	if type(rowList) ~= "table" then rowList = nil end
	local function NeedHeader(group)
		local need = not hasHeader[group] or (not rowList and lastGroup ~= group)
		hasHeader[group], lastGroup = true, group
		return need
	end
	local function SavedItem(key)
		local mine = HUDiniDB and ns.ClassDB and ns.ClassDB()
		return type(mine) == "table" and type(mine.missingItem) == "table" and mine.missingItem[key] ~= nil
	end
	local function ItemKnown(row)
		if ns.MissingItemKnown then return ns.MissingItemKnown(row) ~= nil end
		return Known(row.make or (type(row.needs) == "table" and row.needs[1]) or row.needs)
	end
	local function AddItemRows()
		local add = {}
		for _, row in ipairs(ns.MissingItemRows and ns.MissingItemRows() or {}) do
			if not hasItemRow[row.key] and (ItemKnown(row) or SavedItem(row.key)) then add[#add + 1] = row end
		end
		if #add == 0 then return end
		if NeedHeader("items") then
			Header(layout, Text("opt.head.items"), Text("opt.head.items.tip"))
		end
		for _, row in ipairs(add) do
			local key = row.key
			hasItemRow[key] = true
			local spell = row.make or (type(row.needs) == "table" and row.needs[1]) or row.needs
			local label = ns.MissingItemName and ns.MissingItemName(row) or tostring(spell)
			local setting = Proxy(category, "class_item_" .. key, Settings.VarType.Boolean, label, nil, -- locale: skip a setting name
				function() return ns.GetMissingItem(key) end,
				function(on) ns.SetMissingItem(key, on) end)
			local tip = Text("opt.class.item.tip")
			GreyUnless(Remember(Settings.CreateCheckbox(category, setting, tip), tip),
				On("showHealth"), "showHealth")
		end
	end
	-- The tank buff (TICK-0208): one check box, made the first time
	-- ns.TankBuffSpell() says you know the class file's tankBuff (a
	-- Paladin's Righteous Fury). At load the spellbook may not be read
	-- yet, so it comes at an open, as the missing item rows do, and first
	-- of them: under Advanced, before Missing items when the buff is known
	-- at the first open; a buff learned later (Righteous Fury, level 10)
	-- still goes before Missing items (TICK-0243). Saved per class as
	-- tankBuffOn; starts on (nothing saved), so no default: Defaults on this
	-- page calls no setter for it. Gray without the health bar: the icon
	-- sits by it.
	local hasTankRow = false
	local function AddTankRow()
		if hasTankRow or not (ns.TankBuffSpell and ns.TankBuffSpell()) then return end
		local tank = ns.ClassDefault and ns.ClassDefault("tankBuff")
		if type(tank) ~= "table" or type(tank.buff) ~= "string" then return end
		hasTankRow = true
		local with = type(tank.with) == "table" and tank.with[1] or tank.with
		with = type(with) == "string" and with or tank.buff
		-- The label names the buff as the client does, from its ID, as the
		-- engine reads it; the class file's name if the game gives none.
		local buff = tank.buff
		local ok, name = pcall(C_Spell.GetSpellName, ns.TankBuffSpell())
		if ok and not ns.IsSecret(name) and type(name) == "string" and name ~= "" then buff = name end
		if NeedHeader("tank") then Header(layout, Text("opt.head.tankBuff")) end
		local setting = Proxy(category, "class_tankBuff", Settings.VarType.Boolean, -- locale: skip a setting name
			Text("opt.class.tankBuff", buff), nil,
			function() return ns.GetTankBuff() end,
			function(on) ns.SetTankBuff(on) end)
		local tip = Text("opt.class.tankBuff.tip", buff, with)
		GreyUnless(Remember(Settings.CreateCheckbox(category, setting, tip), nil, "opt.class.tankBuff.tip", buff, with),
			On("showHealth"), "showHealth")
	end
	-- The game's settings window adds a row only at the end of the page's
	-- list, so a row made at a later open first lands after Cooldowns: a
	-- Missing items row learned at level 4 split Cooldowns in two
	-- (TICK-0243). Place keeps each group's rows, as the list holds them,
	-- and writes the page's tail again in the groups' order: Tank buff,
	-- Missing items, Cooldowns, each under its one header. It moves only
	-- rows this page made, out of a fight; the panel draws the list again
	-- when it shows the page. Nothing else is added after them.
	local tailStart = rowList and #rowList + 1
	local GROUPS = { "tank", "items", "cooldowns" }
	local grouped = { tank = {}, items = {}, cooldowns = {} }
	-- An error in Add still keeps the rows it added in their group, so
	-- Place never drops a row or writes one twice; then the error goes on.
	local function Collect(group, Add)
		local n = rowList and #rowList
		local ok, err = pcall(Add)
		if rowList then
			for i = n + 1, #rowList do
				local g = grouped[group]
				g[#g + 1] = rowList[i]
			end
		end
		if not ok then error(err, 0) end
	end
	local function Place()
		if not rowList then return end
		local i = tailStart
		for _, group in ipairs(GROUPS) do
			for _, init in ipairs(grouped[group]) do
				rowList[i], i = init, i + 1
			end
		end
	end
	local function AddCooldownRows()
		local all, count = {}, 0
		local spells = ns.CooldownSpells or ns.ReadyAlertSpells
		if spells then
			all, count = spells()
			count = count or #all
		end
		local class, more, seen = {}, {}, {}
		local function Take(list, spell, mustKnow)
			if type(spell) ~= "string" or hasRow[spell] or seen[spell] then return end
			if mustKnow and not Known(spell) and not SavedOn(spell) then return end
			seen[spell], list[#list + 1] = true, spell
		end
		for i = 1, count do Take(class, all[i], true) end
		-- The rest are spells you learned or saved on already.
		for i = count + 1, #all do Take(more, all[i], false) end
		for _, spell in ipairs(ns.TimerBarSpells and ns.TimerBarSpells() or {}) do
			Take(more, spell, true)
		end
		if #class + #more == 0 then return end
		table.sort(more)
		if NeedHeader("cooldowns") then
			Header(layout, Text("opt.head.cooldowns"), Text("opt.head.cooldowns.tip"))
			HeadRow()
		end
		for _, spell in ipairs(class) do Row(spell, Text("opt.class.cooldown.tip")) end
		for _, spell in ipairs(more) do Row(spell, Text("opt.class.cooldown.tip")) end
	end
	function ns.AddMoreSpellRows()
		if InCombatLockdown and InCombatLockdown() then return end
		Collect("tank", AddTankRow)
		Collect("items", AddItemRows)
		Collect("cooldowns", AddCooldownRows)
		Place()
	end
	ns.AddMoreSpellRows()
end

--------------------------------------------------------------------------------
-- 8. Feed: the feed, what shows, then the box, each kind and the details
--
-- Built even while the feed is off (D-002), so a player can turn it on.
--------------------------------------------------------------------------------

-- The 14 kinds in 5 groups. A group is a proxy, not a saved value: checked
-- when every kind in it is on, and a click turns every kind on or off.
-- Each group's label and tooltip are opt.<group> and opt.<group>.tip.
local FEED_GROUPS = {
	{ "feedGroupItems", { "feedLoot", "feedMoney", "feedCraft" } },
	{ "feedGroupXP", { "feedXP", "feedLevelSummary", "feedQuests", "feedResting" } },
	{ "feedGroupRep", { "feedRep", "feedSkill" } },
	{ "feedGroupNew", { "feedDiscovery", "feedSpells", "feedCollections" } },
	{ "feedGroupWarn", { "feedBags", "feedGear" } },
}

local function BuildFeed(category, layout)
	local function Both(a, b) return function() return HUDiniDB[a] and HUDiniDB[b] and true or false end end

	-- The kinds' settings, and the group setting of each kind. A group is
	-- registered first, its kinds later under Advanced; its setter runs
	-- only on a click, when both are there.
	local kindSettings, groupOf = {}, {}

	-- A kind row repaints its group, and the chain ends there: the group's
	-- own callback only queues an Apply. Rows of no group are plain.
	-- list holds setting keys: each row's label and tooltip are opt.<key>
	-- and opt.<key>.tip.
	local function Rows(list)
		for _, key in ipairs(list) do
			local setting = Register(category, key, Settings.VarType.Boolean, Text("opt." .. key))
			kindSettings[key] = setting
			Under(Remember(Settings.CreateCheckbox(category, setting, Text("opt." .. key .. ".tip")), nil, "opt." .. key .. ".tip"), "showFeed")
			local group = groupOf[key]
			if group then
				Settings.SetOnValueChangedCallback("HUDini_" .. key, function()
					if group.NotifyUpdate then group:NotifyUpdate() end
				end)
			end
		end
	end

	-- A group writes through each kind's own setting, so the kind rows
	-- repaint at once. QueueApply joins the kinds' changes into one Apply.
	local function Group(g)
		local kinds = g[2]
		local setting = Proxy(category, g[1], Settings.VarType.Boolean, Text("opt." .. g[1]), true,
			function()
				for _, kind in ipairs(kinds) do
					if not HUDiniDB[kind] then return false end
				end
				return true
			end,
			function(on)
				for _, kind in ipairs(kinds) do
					local s = kindSettings[kind]
					if s and (HUDiniDB[kind] and true or false) ~= on then s:SetValue(on) end
				end
			end)
		for _, kind in ipairs(kinds) do groupOf[kind] = setting end
		Under(Remember(Settings.CreateCheckbox(category, setting, Text("opt." .. g[1] .. ".tip")), nil, "opt." .. g[1] .. ".tip"), "showFeed")
	end

	Header(layout, Text("opt.head.theFeed"))
	Checkbox(category, "showFeed", Text("opt.showFeed"),
		Text("opt.showFeed.tip"))
	Under(Slider(category, "feedTime", Text("opt.feedTime"),
		Text("opt.feedTime.tip"), 3, 60, 1, Seconds), "showFeed")
	Under(Slider(category, "feedFontSize", Text("opt.feedFontSize"), Text("opt.feedFontSize.tip"), 8, 32, 1, Count),
		"showFeed")
	Under(Slider(category, "feedLines", Text("opt.feedLines"), Text("opt.feedLines.tip"),
		3, 20, 1, Count), "showFeed")

	Header(layout, Text("opt.head.whatShows"))
	for _, g in ipairs(FEED_GROUPS) do Group(g) end

	Header(layout, Text("opt.head.highlights"))
	Rows({ "feedHighlight" })
	Under(Checkbox(category, "feedHighlightSound", Text("opt.feedHighlightSound"), Text("opt.feedHighlightSound.tip")),
		Both("showFeed", "feedHighlight"), "showFeed", "feedHighlight")

	Header(layout, Text("opt.head.hints"))
	Rows({ "feedQuestProgress", "feedUpgrade" })

	Advanced(layout)
	Header(layout, Text("opt.head.theBox"))
	Under(Slider(category, "feedWidth", Text("opt.feedWidth"), Text("opt.feedWidth.tip"), 200, 800, 10, Px),
		"showFeed")
	Under(Dropdown(category, "feedAlign", Text("opt.feedAlign"),
		Text("opt.feedAlign.tip"),
		function() return { { "auto", Text("opt.feedAlign.auto") }, { "LEFT", Text("opt.feedAlign.LEFT") }, { "RIGHT", Text("opt.feedAlign.RIGHT") } } end), "showFeed")
	Rows({
		"feedThickOutline", "feedBackdrop", "feedAnimate", "feedHoldInCombat",
	})

	Header(layout, Text("opt.head.eachKind"))
	Rows({
		"feedLoot", "feedMoney", "feedCraft", "feedXP", "feedLevelSummary", "feedQuests", "feedResting",
		"feedRep", "feedSkill", "feedDiscovery", "feedSpells", "feedCollections",
		"feedBags", "feedGear",
	})

	Header(layout, Text("opt.head.details"))
	Rows({
		"feedStack", "feedBagCount", "feedValue", "feedNewLook", "feedXPDetail",
		"feedRepDetail", "feedHideGray", "feedHideBuys", "feedHideBank",
	})
end

--------------------------------------------------------------------------------
-- 9. Blizzard frames: opt-in, and not to grow
--------------------------------------------------------------------------------

local function BuildBlizzard(category, layout)
	-- The frames HUDini draws its own version of.
	-- Each label says "Hide": a search lists a row without its header, and
	-- the Bars page has an "XP bar" row that shows one.
	Header(layout, Text("opt.head.framesHudiniReplaces"))
	Checkbox(category, "hideBlizzardPlayer", Text("opt.hideBlizzardPlayer"),
		Text("opt.hideBlizzardPlayer.tip"))
	Checkbox(category, "hideBlizzardTarget", Text("opt.hideBlizzardTarget"),
		Text("opt.hideBlizzardTarget.tip"))
	Checkbox(category, "hideBlizzardCastBar", Text("opt.hideBlizzardCastBar"),
		Text("opt.hideBlizzardCastBar.tip"))
	Checkbox(category, "hideBlizzardXP", Text("opt.hideBlizzardXP"),
		Text("opt.hideBlizzardXP.tip"))
	-- The objective list (D-053, TICK-0256): HUDini draws no copy of it, but
	-- it is a Hide box like these, so it sits with them. Its Apply hides it.
	Checkbox(category, "hideBlizzardObjectives", Text("opt.hideBlizzardObjectives"),
		Text("opt.hideBlizzardObjectives.tip"))

	-- The gryphons hide only in Edit Mode (D-024, TICK-0089): HUDini never
	-- touches them. The panel has no plain text row, so a header teaches it,
	-- with the steps in its tooltip and the box named in the game's words.
	local box = ns.GryphonBoxName()
	local gryphons = CreateSettingsListSectionHeaderInitializer(Text("opt.head.gryphons"),
		Text("opt.head.gryphons.tip", box))
	layout:AddInitializer(Remember(gryphons, nil, "opt.head.gryphons.tip", box))

	Header(layout, Text("opt.head.showOnlyOnMouseover"))
	Checkbox(category, "bagBarMouseover", Text("opt.bagBarMouseover"),
		Text("opt.bagBarMouseover.tip"))
	Checkbox(category, "menuBarMouseover", Text("opt.menuBarMouseover"),
		Text("opt.menuBarMouseover.tip"))
	Checkbox(category, "minimapMouseover", Text("opt.minimapMouseover"),
		Text("opt.minimapMouseover.tip"))

	-- Bag upgrade numbers (D-034, TICK-0145): the one growth of the bag part.
	Header(layout, Text("opt.head.bags"))
	Checkbox(category, "showBagUpgrades", Text("opt.showBagUpgrades"),
		Text("opt.showBagUpgrades.tip"))

	Header(layout, Text("opt.head.windows"))
	Checkbox(category, "moveWindows", Text("opt.moveWindows"),
		Text("opt.moveWindows.tip"))

	-- Date and time on chat lines (D-038, TICK-0154).
	Header(layout, Text("opt.head.chat"))
	Checkbox(category, "chatStamps", Text("opt.chatStamps"),
		Text("opt.chatStamps.tip"))
	-- The stamp's shape (D-039, TICK-0155): each choice shows its example.
	Under(Dropdown(category, "chatStampShape", Text("opt.chatStampShape"),
		Text("opt.chatStampShape.tip"),
		function() return {
			{ "long", Text("opt.chatStampShape.long") },
			{ "short", Text("opt.chatStampShape.short") },
			{ "dated", Text("opt.chatStampShape.dated") },
		} end), "chatStamps")

	-- The cursor ring (D-052, TICK-0246). On, shape and size sit above
	-- Advanced; its three opacity sliders sit under it, as their defaults
	-- suit most players and six rows above it would pass the page's 15.
	-- An Apply only turns the module on or off, so each row also calls
	-- ns.RefreshCursorRing (CursorRing.lua), which redraws the ring at once.
	local function RingRow(row, key)
		Settings.SetOnValueChangedCallback("HUDini_" .. key, function()
			if ns.RefreshCursorRing then ns.RefreshCursorRing() end
		end)
		return row
	end
	Header(layout, Text("opt.head.cursorRing"))
	RingRow(Checkbox(category, "cursorRing", Text("opt.cursorRing"), Text("opt.cursorRing.tip")), "cursorRing")
	Under(RingRow(Dropdown(category, "cursorRingShape", Text("opt.cursorRingShape"),
		Text("opt.cursorRingShape.tip"),
		function() return {
			{ "ring", Text("opt.cursorRingShape.ring") },
			{ "halo", Text("opt.cursorRingShape.halo") },
			{ "arrows", Text("opt.cursorRingShape.arrows") },
		} end), "cursorRingShape"), "cursorRing")
	Under(RingRow(Slider(category, "cursorRingSize", Text("opt.cursorRingSize"),
		Text("opt.cursorRingSize.tip"), 50, 600, 10, Px), "cursorRingSize"), "cursorRing")

	Advanced(layout)
	Header(layout, Text("opt.head.cursorRingOpacity"))
	for _, key in ipairs({ "cursorRingAlpha", "cursorRingAlphaCombat", "cursorRingAlphaGroup" }) do
		Under(RingRow(Slider(category, key, Text("opt." .. key), Text("opt." .. key .. ".tip"),
			0, 1, 0.01, Percent), key), "cursorRing")
	end

	-- The game's sounds (D-028, TICK-0248): one mute box per error voice
	-- line, in ErrorVoice.lua's order. A player sets them once, and seven
	-- more rows above Advanced would pass the page's 15, so they sit under
	-- it. A change queues an Apply, which mutes or unmutes that line at once.
	Header(layout, Text("opt.head.sounds"))
	for _, line in ipairs(ns.ERROR_VOICE_LINES or {}) do
		Checkbox(category, line.key, Text("opt." .. line.key), Text("opt." .. line.key .. ".tip"))
	end
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function ns.BuildOptions()
	if ns.category then return end

	-- The old Timer bar texture row is gone (TICK-0225): its pick moves
	-- once into the spells whose timer bar is on (BarLooks.lua). It is
	-- safe to run at every load: with no pick left it only clears the key.
	if ns.MoveTimerBarTexture then ns.MoveTimerBarTexture(HUDiniDB) end

	local category, layout = Settings.RegisterVerticalLayoutCategory("HUDini")
	ns.category = category
	BuildGeneral(category, layout)

	-- Each page's name is a page.* text.
	local pages = {
		{ "page.icons",      BuildIcons },
		{ "page.bars",       BuildBars },
		{ "page.textures",   BuildTextures },
		{ "page.colors",     BuildColors },
		{ "page.alerts",     BuildAlerts },
		{ "page.class",      BuildYourClass },
		{ "page.feed",       BuildFeed },
		{ "page.blizzard",   BuildBlizzard },
	}
	for _, page in ipairs(pages) do
		local sub, subLayout = Settings.RegisterVerticalLayoutSubcategory(category, Text(page[1]))
		page[2](sub, subLayout)
	end

	Settings.RegisterAddOnCategory(category)

	-- Show the whole HUD while the options panel is open, so every change is
	-- visible even out of combat.
	if SettingsPanel and SettingsPanel.HookScript then
		SettingsPanel:HookScript("OnShow", function()
			-- Spells learned since the last open get their rows (TICK-0162).
			if ns.AddMoreSpellRows then ns.AddMoreSpellRows() end
			ns.previewing = true
			ns.HUDini:UpdateVisibility()
		end)
		SettingsPanel:HookScript("OnHide", function()
			ns.previewing = false
			ns.HUDini:UpdateVisibility()
		end)
	end
end
