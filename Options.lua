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
}

-- The button text of a fallback row: a square of the color, then the words.
local function PickText(key)
	local c = ns.BarColor(key)
	local function Byte(v) return math.floor(v * 255 + 0.5) end
	return ("|TInterface\\Buttons\\WHITE8X8:12:12:0:0:8:8:0:8:0:8:%d:%d:%d|t  %s"):format(
		Byte(c[1]), Byte(c[2]), Byte(c[3]), Text("opt.color.pick"))
end

local function RegisterColors(category)
	for _, entry in ipairs(ns.COLOR_KEYS) do
		local key = entry.key
		local d = ns.defaults.colors[key]
		colorSettings[key] = Proxy(category, "color_" .. key, Settings.VarType.String, -- locale: skip a setting name
			COLOR_LABEL[key] and Text(COLOR_LABEL[key]) or entry.label, CreateColor(d[1], d[2], d[3]):GenerateHexColor(),
			function() return ns.ColorHex(key) end,
			function(hex) ns.SetColorHex(key, hex) end,
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

	Header(layout, Text("opt.head.appearance"))
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
end

--------------------------------------------------------------------------------
-- 4. Colors: every bar color, one row each
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
end

--------------------------------------------------------------------------------
-- 5. Alerts: the ones your class has spells for, then the rest
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
end

--------------------------------------------------------------------------------
-- 6. Your class: which spell each alert uses, saved for this class only
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

	Header(layout, Text("opt.head.interrupt"))
	Pick("interrupt", Text("opt.class.interrupt"),
		Text("opt.class.interrupt.tip"))

	Header(layout, Text("opt.head.dispel"))
	for _, dispelType in ipairs(ns.DISPEL_TYPES) do
		local _, row = Pick("dispel", dispelType, Text("opt.class.dispel.tip", dispelType, dispelType, dispelType), dispelType)
		-- Its tooltip joins in the kind, so its key is not found from its text.
		Remember(row, nil, "opt.class.dispel.tip", dispelType, dispelType, dispelType)
	end

	Header(layout, Text("opt.head.purge"))
	Pick("purge", Text("opt.class.purge"),
		Text("opt.class.purge.tip"))

	Header(layout, Text("opt.head.buffs"))
	Pick("keepUp", Text("opt.class.keepUp"),
		Text("opt.class.keepUp.tip"))
	-- The Settings dropdown holds no check marks, so this is the design's
	-- fallback. /hud buffs still lists them and forgets one.
	Button(layout, Text("opt.trackedBuffs"), Text("opt.trackedBuffs.button"),
		function() ns.BuffsCommand("clear", function() end) end, Text("opt.trackedBuffs.tip"))

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
end

--------------------------------------------------------------------------------
-- 7. Feed: the feed, what shows, then the box, each kind and the details
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
-- 8. Blizzard frames: opt-in, and not to grow
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

	Header(layout, Text("opt.head.windows"))
	Checkbox(category, "moveWindows", Text("opt.moveWindows"),
		Text("opt.moveWindows.tip"))

	-- The game's sounds (D-028, TICK-0133): mutes two error voice lines.
	Header(layout, Text("opt.head.sounds"))
	Checkbox(category, "muteErrorVoice", Text("opt.muteErrorVoice"),
		Text("opt.muteErrorVoice.tip"))
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function ns.BuildOptions()
	if ns.category then return end

	local category, layout = Settings.RegisterVerticalLayoutCategory("HUDini")
	ns.category = category
	BuildGeneral(category, layout)

	-- Each page's name is a page.* text.
	local pages = {
		{ "page.icons",      BuildIcons },
		{ "page.bars",       BuildBars },
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
			ns.previewing = true
			ns.HUDini:UpdateVisibility()
		end)
		SettingsPanel:HookScript("OnHide", function()
			ns.previewing = false
			ns.HUDini:UpdateVisibility()
		end)
	end
end
