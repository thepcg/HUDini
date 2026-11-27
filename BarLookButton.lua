--[[--------------------------------------------------------------------------
	HUDini - The texture button (TICK-0224, D-049)

	One control for every place that sets up a bar (design:
	docs/design/bar-textures.md, The texture button). Its face is a strip of
	the bar as it looks now; a click opens the game's menu: Texture, a
	color row for each color the bar takes (TICK-0242), Gradient, Gradient
	color, Custom file... and, on a timer bar's button, Use on every timer
	bar. The picks write the bar's look through ns.SetBarLook (BarLooks.lua),
	and only that bar's. A color row writes the Colors page's own color
	(ns.SetBarColorHex, Bars.lua): one saved value, shown in both places.
	A timer bar's color row is the bar's own color (TICK-0258): only that
	bar changes; with none, it wears the Colors page's Timer bar color.

	A host (a settings row, a grid row) does three things:

		local b = ns.CreateLookButton(rowFrame, 180)        -- once per frame
		ns.BindLookButton(b, {                               -- on each draw
			id = "health",                -- the bar id (BarLooks.lua)
			label = ...,                  -- the row's label: tooltip title,
			                              -- window title, search tag
			tip = nil,                    -- the tooltip's last line; nil:
			                              -- opt.look.row.tip
			allTimers = false,            -- show Use on every timer bar
			name = nil,                   -- AddLookRow: the settings' name
		})
		ns.BarLookSettings(category, "health")   -- once, when the page is built

	Or, for a row of its own on a settings page, one call does all three:

		ns.AddLookRow(category, layout, { id = "health", label = ... })

	A row's label is a search tag on it, so the settings search finds it
	(a row built with an element initializer is found only by its tags).

	BarLookSettings registers the bar's three looks as proxy settings with
	fixed defaults (a function default taints, Options.lua Proxy), so the
	page's Defaults resets them as it does a setting with no control
	(auraMap). The settings are not shown: the button is the control. A
	timer bar names its own settings (name), as the Cooldowns grid does.

	The Custom texture window (Custom file...): a text field for a path,
	a preview, the player's files (at most 10). A plain window, not secure:
	it opens in a fight too, and closes with the options panel.
----------------------------------------------------------------------------]]

local _, ns = ...
local Text = ns.Text

local FACE_H = 20
local ARROW = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local START = "Interface\\AddOns\\" -- the path field's start; locale: skip a path

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

local function TextureLabel(t)
	if t == "same" then return Text("opt.look.same") end
	if ns.IsTextureFile(t) then return Text("opt.look.custom", ns.TextureFileName(t)) end
	for _, e in ipairs(ns.BarTextureList()) do
		if e.key == t then return e.label end
	end
	return tostring(t)
end

local function GradientLabel(g)
	return Text("opt.look.gradient." .. g)
end

-- "Texture: Flat. Gradient: Darker." with this bar's picks.
function ns.LookPicksLine(id)
	return Text("opt.look.picks", TextureLabel(ns.BarLookField(id, "texture")),
		GradientLabel(ns.BarLookField(id, "gradient")))
end

-- A strip of a texture in a color, for a menu entry's text.
local function Strip(path, color)
	local rgb = ("%d:%d:%d"):format(color[1] * 255, color[2] * 255, color[3] * 255)
	return ("|T%s:14:90:0:0:8:8:0:8:0:8:%s|t"):format(path, rgb)
end

local function Square(color)
	local rgb = ("%d:%d:%d"):format(color[1] * 255, color[2] * 255, color[3] * 255)
	return ("|T%s:12:12:0:0:8:8:0:8:0:8:%s|t"):format(WHITE, rgb)
end

--------------------------------------------------------------------------------
-- Settings: Defaults reaches every look
--------------------------------------------------------------------------------

local function Hex(c)
	return CreateColor(c[1], c[2], c[3]):GenerateHexColor()
end

-- The bar's three looks as proxy settings in category, for Defaults.
-- name: the settings' name ("look_<id>" if nil). Returns the three, and
-- for a timer bar a fourth: its own color (TICK-0258), "" for none, so
-- Defaults clears it and the bar follows the Timer bar color again.
function ns.BarLookSettings(category, id, name)
	if not (Settings and Settings.RegisterProxySetting and ns.IsBarLookId(id)) then return end
	local base = "HUDini_" .. (name or ("look_" .. id)) -- locale: skip a setting name
	local S = Settings.VarType.String
	local texture = Settings.RegisterProxySetting(category, base .. "_texture", S, -- locale: skip a setting name
		Text("opt.look.texture"), ns.BarLookDefault(id, "texture"),
		function() return ns.BarLookField(id, "texture") end,
		function(v) ns.SetBarLook(id, "texture", v) end)
	local gradient = Settings.RegisterProxySetting(category, base .. "_gradient", S, -- locale: skip a setting name
		Text("opt.look.gradient"), ns.BarLookDefault(id, "gradient"),
		function() return ns.BarLookField(id, "gradient") end,
		function(v) ns.SetBarLook(id, "gradient", v) end)
	local default = ns.BarLookDefault(id, "color")
	local color = Settings.RegisterProxySetting(category, base .. "_color", S, -- locale: skip a setting name
		Text("opt.look.color"), Hex(default),
		function() return Hex(ns.BarLookField(id, "color")) end,
		function(hex)
			-- The default as it is, not as its hex reads back.
			if hex == Hex(default) then ns.SetBarLook(id, "color", default) return end
			local c = CreateColorFromHexString(hex)
			if c then ns.SetBarLook(id, "color", { c.r, c.g, c.b }) end
		end)
	if not id:find("^timer:") then return texture, gradient, color end
	local own = Settings.RegisterProxySetting(category, base .. "_base", S, -- locale: skip a setting name
		Text("opt.look.timerBase"), "",
		function()
			local c = ns.BarLookField(id, "base")
			return c and Hex(c) or ""
		end,
		function(hex)
			if hex == "" or hex == nil then ns.SetBarLook(id, "base", nil) return end
			local c = CreateColorFromHexString(hex)
			if c then ns.SetBarLook(id, "base", { c.r, c.g, c.b }) end
		end)
	return texture, gradient, color, own
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

local buttons = setmetatable({}, { __mode = "k" })

local function PaintFace(b)
	local id = b.look and b.look.id
	if not id then return end
	ns.LookBar(b.strip, id)
	ns.PaintBar(b.strip, ns.BarLookColor(id))
end

-- Every bound button shows its bar's look again (ns.RepaintLooks).
function ns.RepaintLookButtons()
	for b in pairs(buttons) do PaintFace(b) end
end

local function ShowTip(b)
	local look = b.look
	if not (look and GameTooltip) then return end
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	GameTooltip:SetText(look.label or "", 1, 1, 1)
	GameTooltip:AddLine(ns.LookPicksLine(look.id), nil, nil, nil, true)
	GameTooltip:AddLine(look.tip or Text("opt.look.row.tip"), nil, nil, nil, true)
	GameTooltip:Show()
end

-- A texture button, width wide. Made once per frame; BindLookButton gives
-- it a bar.
function ns.CreateLookButton(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 180, FACE_H)

	b.backdrop = b:CreateTexture(nil, "BACKGROUND")
	b.backdrop:SetAllPoints()
	b.backdrop:SetColorTexture(0, 0, 0, 0.85)

	b.strip = CreateFrame("StatusBar", nil, b)
	b.strip:SetPoint("TOPLEFT", 1, -1)
	b.strip:SetPoint("BOTTOMRIGHT", -(FACE_H - 2), 1)
	b.strip:SetMinMaxValues(0, 1)
	b.strip:SetValue(1)

	b.arrow = b:CreateTexture(nil, "ARTWORK")
	b.arrow:SetTexture(ARROW)
	b.arrow:SetSize(FACE_H - 2, FACE_H - 2)
	b.arrow:SetPoint("RIGHT", 0, 0)

	b.hover = b:CreateTexture(nil, "HIGHLIGHT")
	b.hover:SetAllPoints()
	b.hover:SetColorTexture(1, 1, 1, 0.15)

	b:SetScript("OnClick", function(self) ns.OpenLookMenu(self) end)
	b:SetScript("OnEnter", ShowTip)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	return b
end

-- Bind a button to a bar (see the header for look's fields) and paint it.
function ns.BindLookButton(b, look)
	b.look = look
	buttons[b] = true
	PaintFace(b)
	return b
end

--------------------------------------------------------------------------------
-- A row of its own
--------------------------------------------------------------------------------

local ROW_WIDTH = 180

-- The game's base row template runs no OnLoad of its own (only its Tooltip
-- child has one), so its frame lacks the callback list that the mixin's
-- OnLoad makes and its Init asserts on (Blizzard_SettingControls.xml:50-78,
-- .lua:305-307 and :331, wow-ui-source forever 9dc84f0). Make it once, as
-- that OnLoad does (TICK-0240). Init then runs as for the game's rows: with
-- no list it errors, rather than leave a pooled frame's last label.
local function ReadyRow(frame)
	if frame.cbrHandles == nil and frame.OnLoad then frame:OnLoad() end
end

-- The bare template has no size either, and the list takes a row's height
-- from its initializer's GetExtent, else from the template (0 here:
-- Blizzard_SettingsList.lua:68-71). The game's own rows are 26 high
-- (SettingsCheckboxControlTemplate and its kin, Blizzard_SettingControls.xml
-- :107-140). TICK-0240.
local ROW_HEIGHT = 26
local function RowExtent() return ROW_HEIGHT end

local function InitRow(init, frame)
	ReadyRow(frame)
	if frame.Init then frame:Init(init) end
	local b = frame.hudiniLook
	if not b then
		b = ns.CreateLookButton(frame, ROW_WIDTH)
		-- Where the game puts a dropdown on its rows.
		b:SetPoint("LEFT", frame, "CENTER", -80, 0)
		frame.hudiniLook = b
	end
	b:Show()
	ns.BindLookButton(b, init.data.look)
end

-- Let a button go: hidden, with no look, so a look change no longer
-- repaints it. For a pooled button made elsewhere (Options' grid) too.
function ns.UnbindLookButton(b)
	if not b then return end
	b:Hide()
	b.look = nil
	buttons[b] = nil
end

-- The game pools its row frames: a frame given to another row hides the
-- button.
local function ResetRow(_, frame)
	ns.UnbindLookButton(frame.hudiniLook)
	-- What the game's own resetter does (ScrollUtil.lua:1703-1707): free
	-- what Init signed up. A grayed row (GreyUnless) signs up one handle
	-- per setting it reads, and the next Init asserts the list is empty.
	if frame.Release then frame:Release() end
end

-- Give a row's initializer its label as a search tag.
function ns.TagLookRow(init, label)
	if init and init.AddSearchTags and label then init:AddSearchTags(label) end
	return init
end

-- A settings row with the label at the left and a texture button for one
-- bar, its three looks in the page's Defaults, and its label as a search
-- tag. look: as BindLookButton. Returns the row's initializer (nil without
-- the game's element initializer, as in the test harness; the settings are
-- registered all the same).
function ns.AddLookRow(category, layout, look)
	ns.BarLookSettings(category, look.id, look.name)
	if not (Settings and Settings.CreateElementInitializer) then return end
	local init = Settings.CreateElementInitializer("SettingsListElementTemplate",
		{ name = look.label, tooltip = look.tip or Text("opt.look.row.tip"), look = look })
	init.InitFrame, init.Resetter, init.GetExtent = InitRow, ResetRow, RowExtent
	layout:AddInitializer(init)
	return ns.TagLookRow(init, look.label)
end

--------------------------------------------------------------------------------
-- The menu
--------------------------------------------------------------------------------

local function Tip(entry, title, line)
	if not (entry and entry.SetTooltip) then return end
	entry:SetTooltip(function(tooltip)
		tooltip:SetText(title, 1, 1, 1)
		tooltip:AddLine(line, nil, nil, nil, true)
	end)
end

-- The game's color picker on one bar's gradient color. A drag recolors the
-- bar at once; Cancel puts the old color back.
local function PickColor(id)
	if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
	local old = ns.BarLookField(id, "color")
	-- Cancel puts back what was saved: nothing saved stays nothing, so a
	-- class file's default still wins.
	local saved = ns.SavedBarLookField(id, "color")
	ColorPickerFrame:SetupColorPickerAndShow({
		r = old[1], g = old[2], b = old[3],
		hasOpacity = false,
		swatchFunc = function()
			local r, g, bl = ColorPickerFrame:GetColorRGB()
			ns.SetBarLook(id, "color", { r, g, bl })
		end,
		cancelFunc = function() ns.SetBarLook(id, "color", saved) end,
	})
end

-- The game's color picker on one timer bar's own color (TICK-0258). A drag
-- recolors that bar at once; Cancel puts back what was saved (nothing
-- saved: the bar follows the Timer bar color again).
local function PickTimerColor(id)
	if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
	local old = ns.TimerBarColor(id)
	local saved = ns.SavedBarLookField(id, "base")
	ColorPickerFrame:SetupColorPickerAndShow({
		r = old[1], g = old[2], b = old[3],
		hasOpacity = false,
		swatchFunc = function()
			local r, g, bl = ColorPickerFrame:GetColorRGB()
			ns.SetBarLook(id, "base", { r, g, bl })
		end,
		cancelFunc = function() ns.SetBarLook(id, "base", saved) end,
	})
end

-- The game's color picker on one Colors page color (key: "health",
-- "hostile", ...). A drag recolors the bars at once; Cancel puts the old
-- color back, as the Colors page's own picker does.
local function PickBarColor(key)
	if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
	local c = ns.BarColor(key)
	local old = ns.ColorHex(key)
	ColorPickerFrame:SetupColorPickerAndShow({
		r = c[1], g = c[2], b = c[3],
		hasOpacity = false,
		swatchFunc = function()
			ns.SetBarColorHex(key, CreateColor(ColorPickerFrame:GetColorRGB()):GenerateHexColor())
		end,
		cancelFunc = function() ns.SetBarColorHex(key, old) end,
	})
end

-- Fill the menu of a bound button (root: the game's menu description). A
-- function of its own, so a test can fill a fake root.
function ns.LookMenu(owner, root)
	local look = owner.look
	if not look then return end
	local id = look.id
	local color = ns.BarLookColor(id)

	local function Radio(menu, label, field, value, tip)
		local entry = menu:CreateRadio(label,
			function() return ns.BarLookField(id, field) == value end,
			function() ns.SetBarLook(id, field, value) end, value)
		if tip then Tip(entry, label, tip) end
		return entry
	end

	local texture = root:CreateButton(Text("opt.look.texture"))
	Tip(texture, Text("opt.look.texture"), Text("opt.look.texture.tip"))
	Radio(texture, Text("opt.look.same"), "texture", "same", Text("opt.look.same.tip"))
	for _, e in ipairs(ns.BarTextureList()) do
		Radio(texture, Strip(ns.TexturePathFor(e.key), color) .. "  " .. e.label, "texture", e.key)
	end
	for _, path in ipairs(ns.CustomTextures()) do
		local name = Text("opt.look.custom", ns.TextureFileName(path))
		Radio(texture, Strip(path, color) .. "  " .. name, "texture", path,
			Text("opt.look.custom.tip", path))
	end

	-- The bar's colors, above Gradient: the one it fades from. A timer
	-- bar's is its own (TICK-0258).
	local timer = id:find("^timer:") ~= nil
	for _, key in ipairs(ns.BarColorKeys(id)) do
		local name = Text("opt.color." .. key)
		local now = timer and ns.TimerBarColor(id) or ns.BarColor(key)
		local label = timer and Text("opt.look.timerBase") or Text("opt.look.base", name)
		local row = root:CreateButton(Square(now) .. "  " .. label,
			function() if timer then PickTimerColor(id) else PickBarColor(key) end end)
		Tip(row, timer and label or name, timer and Text("opt.look.timerBase.tip") or Text("opt.look.base.tip", name))
	end

	local gradient = root:CreateButton(Text("opt.look.gradient"))
	Tip(gradient, Text("opt.look.gradient"), Text("opt.look.gradient.tip"))
	for _, g in ipairs(ns.LOOK_GRADIENTS) do
		Radio(gradient, GradientLabel(g), "gradient", g)
	end

	local pick = root:CreateButton(Square(ns.BarLookField(id, "color")) .. "  " .. Text("opt.look.color"),
		function() PickColor(id) end)
	if pick.SetEnabled then pick:SetEnabled(ns.BarLookField(id, "gradient") == "color") end
	Tip(pick, Text("opt.look.color"), Text("opt.look.color.tip"))

	root:CreateButton(Text("opt.look.customFile"), function() ns.OpenCustomTexture(id, look.label) end)

	if look.allTimers then
		root:CreateDivider()
		local all = root:CreateButton(Text("opt.look.allTimers"), function() ns.SetLookOnAllTimers(id) end)
		Tip(all, Text("opt.look.allTimers"), Text("opt.look.allTimers.tip"))
	end
end

function ns.OpenLookMenu(owner)
	if GameTooltip then GameTooltip:Hide() end
	local menu = _G.MenuUtil
	if menu and menu.CreateContextMenu then menu.CreateContextMenu(owner, ns.LookMenu) end
end

--------------------------------------------------------------------------------
-- The Custom texture window
--------------------------------------------------------------------------------

local PAD, GAP, WIDTH = 20, 8, 480
local ROWS = ns.MAX_CUSTOM_TEXTURES
local BACKDROP = {
	bgFile = WHITE,
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local win -- the window, made on first open

local function NewText(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	return fs
end

-- The typed path is in the list already (any case).
local function Listed(path)
	local low = path:lower()
	for _, p in ipairs(ns.CustomTextures()) do
		if p:lower() == low then return true end
	end
	return false
end

local Layout -- set below

-- The preview, the Use this file button and the red line, after a change.
local function Refresh()
	local p = win.parts
	local path = ns.CleanTexturePath(p.box:GetText())
	local file = ns.IsTextureFile(path)
	p.preview:SetShown(file)
	if file then
		local ok, done = pcall(p.preview.SetStatusBarTexture, p.preview, path)
		p.preview.loads = ok and done ~= false
		p.preview:SetStatusBarColor(unpack(ns.BarLookColor(win.id)))
	end
	local full = #ns.CustomTextures() >= ns.MAX_CUSTOM_TEXTURES and not (file and Listed(path))
	p.use:SetEnabled(not full)
end

local function Use()
	local p = win.parts
	local ok, result = ns.AddCustomTexture(p.box:GetText(), p.probe)
	if not ok then
		p.err:SetText(Text(result))
		Layout()
		return
	end
	ns.SetBarLook(win.id, "texture", result)
	win:Hide()
end

local function Build()
	local f = CreateFrame("Frame", "HUDiniCustomTexture", UIParent, "BackdropTemplate")
	f:SetWidth(WIDTH)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(0, 0, 0, 1)
	f:Hide()
	tinsert(UISpecialFrames, "HUDiniCustomTexture")

	local p = {}
	p.title = NewText(f, "GameFontNormalLarge")
	p.intro = NewText(f, "GameFontHighlight")
	p.example = NewText(f, "GameFontDisable")

	p.box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	p.box:SetAutoFocus(false)
	p.box:SetSize(WIDTH - 2 * PAD - 6, 22)
	p.box:SetScript("OnTextChanged", function()
		p.err:SetText("")
		Refresh()
	end)
	p.box:SetScript("OnEnterPressed", function() if p.use:IsEnabled() then Use() end end)
	p.box:SetScript("OnEscapePressed", function() f:Hide() end)

	p.preview = CreateFrame("StatusBar", nil, f)
	p.preview:SetMinMaxValues(0, 1)
	p.preview:SetValue(1)
	p.previewBack = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	p.previewBack:SetColorTexture(0, 0, 0, 0.85)
	p.hint = NewText(f, "GameFontDisableSmall")
	-- A texture that is never shown: AddCustomTexture tries the path on it.
	p.probe = f:CreateTexture(nil, "ARTWORK")
	p.probe:Hide()

	p.err = NewText(f, "GameFontHighlight")
	p.err:SetTextColor(1, 0.25, 0.25)

	p.use = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	p.use:SetSize(130, 22)
	p.use:SetMotionScriptsWhileDisabled(true)
	p.use:SetScript("OnClick", Use)
	p.use:SetScript("OnEnter", function(self)
		if self:IsEnabled() or not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Text("look.custom.full"), 1, 1, 1)
		GameTooltip:Show()
	end)
	p.use:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	p.list = NewText(f, "GameFontNormal")
	p.rows = {}
	for i = 1, ROWS do
		local row = {}
		row.name = NewText(f, "GameFontHighlight")
		row.name:SetWordWrap(false)
		row.path = NewText(f, "GameFontDisableSmall")
		row.path:SetWordWrap(false)
		row.x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		row.x:SetSize(22, 22)
		row.x:SetScript("OnClick", function()
			ns.RemoveCustomTexture(row.file)
			Refresh()
			Layout()
		end)
		row.x:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(Text("look.custom.remove"), 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row.x:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		p.rows[i] = row
	end

	p.folder = NewText(f, "GameFontHighlight")
	p.restart = NewText(f, "GameFontHighlight")
	p.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	p.close:SetSize(96, 22)
	p.close:SetScript("OnClick", function() f:Hide() end)

	-- It closes with the options panel. A look at the panel, not a hook on
	-- it: HUDini hooks no Blizzard frame here.
	f:SetScript("OnUpdate", function(self)
		if SettingsPanel and not SettingsPanel:IsShown() then self:Hide() end
	end)
	f:SetScript("OnHide", function() p.box:ClearFocus() end)

	f.parts = p -- for the tests
	win = f
end

-- Stack the parts top to bottom and fit the height.
function Layout()
	local f, p = win, win.parts
	local inner = WIDTH - 2 * PAD
	local y = PAD
	local function Put(part, h, x, gap)
		part:ClearAllPoints()
		part:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (x or 0), -y)
		y = y + h + (gap or GAP)
	end
	local function Line(fs, gap)
		fs:SetWidth(inner)
		if fs:GetText() == nil or fs:GetText() == "" then fs:Hide() return end
		fs:Show()
		Put(fs, fs:GetStringHeight(), 0, gap)
	end

	Line(p.title)
	Line(p.intro, 2)
	Line(p.example)
	Put(p.box, 22, 6, 4)

	local bar = ns.GetBar and ns.GetBar("health")
	local h = bar and bar:GetHeight() or 0
	if type(h) ~= "number" or h < 6 then h = 12 end
	p.preview:SetSize(inner, h)
	p.previewBack:ClearAllPoints()
	p.previewBack:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 1, -(y - 1))
	p.previewBack:SetSize(inner + 2, h + 2)
	Put(p.preview, h, 0, 4)
	Line(p.hint, 4)
	Line(p.err, 4)

	p.use:ClearAllPoints()
	p.use:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
	y = y + 22 + GAP

	Line(p.list, 4)
	local files = ns.CustomTextures()
	for i, row in ipairs(p.rows) do
		local file = files[i]
		row.file = file
		row.name:SetShown(file ~= nil)
		row.path:SetShown(file ~= nil)
		row.x:SetShown(file ~= nil)
		if file then
			row.name:SetText(ns.TextureFileName(file))
			row.name:SetWidth(110)
			row.path:SetText(file)
			row.path:SetWidth(inner - 110 - 30)
			row.name:ClearAllPoints()
			row.name:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 6, -(y + 4))
			row.path:ClearAllPoints()
			row.path:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 6 + 110, -(y + 5))
			row.x:ClearAllPoints()
			row.x:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD + 4, -y)
			y = y + 22
		end
	end
	y = y + GAP

	Line(p.folder)
	Line(p.restart)
	p.close:ClearAllPoints()
	p.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
	f:SetHeight(y + 22 + PAD)
end

-- Open the window for one bar. label: the row's label (for a timer bar,
-- the spell's name).
function ns.OpenCustomTexture(id, label)
	if not ns.IsBarLookId(id) then return end
	if not win then Build() end
	local p = win.parts
	win.id = id
	p.title:SetText(Text("look.custom.title", label or id))
	p.intro:SetText(Text("look.custom.intro"))
	p.example:SetText(Text("look.custom.example"))
	p.hint:SetText(Text("look.custom.previewHint"))
	p.use:SetText(Text("look.custom.use"))
	p.list:SetText(Text("look.custom.list"))
	p.folder:SetText(Text("look.custom.folder"))
	p.restart:SetText(Text("look.custom.restart"))
	p.close:SetText(Text("look.custom.close"))
	p.err:SetText("")
	p.box:SetText(START)
	Refresh()
	Layout()
	win:Show()
	return win
end
