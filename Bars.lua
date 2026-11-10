--[[--------------------------------------------------------------------------
	HUDini - Bars

	The stack above the icon grid. Reading down the screen:

		target cast bar   (spell name, yellow if you can interrupt, grey if not)
		target health
		your health
		your power        (mana, rage or energy; your cast bar rides on it)
		class resource    (an aura stack from the class profile, if it has one)
		experience        (XP, rested, 5% ticks, XP/hr: XP.lua)
		the icon grid

	Everything here obeys one rule: never look inside a secret value. Health,
	power, cast times, spell names and the interruptible flag can all come back
	secret in combat. Each one has an "opaque pipeline", a widget call built to
	swallow a secret and draw it. We hand the value over and never read it.

		numbers  -> StatusBar:SetValue / SetMinMaxValues
		durations-> StatusBar:SetTimerDuration
		strings  -> FontString:SetText
		booleans -> Region:SetAlphaFromBoolean

	We never test whether a cast is running either. We try to start the timer
	inside a pcall. If the call takes, there is a cast. If it throws, there is
	not. That is a plain true or false, safe to branch on.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local Text = ns.Text

local HUDini = ns.HUDini
local Plain    = ns.Plain
local IsSecret = ns.IsSecret

local bars = {}

HUDini.bars = bars

--------------------------------------------------------------------------------
-- Texture picker
--
-- A short built-in list, plus every statusbar texture LibSharedMedia knows
-- about when another addon has loaded it.
--------------------------------------------------------------------------------

local BUILTIN_TEXTURES = {
	{ key = "blizzard", label = Text("bars.texture.blizzard"), path = "Interface\\TargetingFrame\\UI-StatusBar" },
	{ key = "flat",     label = Text("bars.texture.flat"),               path = "Interface\\Buttons\\WHITE8X8" },
	{ key = "solid",    label = Text("bars.texture.solid"),              path = "Interface\\ChatFrame\\ChatFrameBackground" },
	{ key = "smooth",   label = Text("bars.texture.smooth"),             path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ key = "banded",   label = Text("bars.texture.banded"),             path = "Interface\\PVPFrame\\UI-PVP-Progress-Bar" },
}

local BUILTIN_BY_KEY = {}
for _, t in ipairs(BUILTIN_TEXTURES) do BUILTIN_BY_KEY[t.key] = t end

local DEFAULT_TEXTURE = BUILTIN_BY_KEY.blizzard.path

local function SharedMedia()
	if not LibStub then return nil end
	local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
	if ok then return lib end
	return nil
end

-- A texture key (built-in or LibSharedMedia) to its path.
function ns.TexturePathFor(key)

	local builtin = BUILTIN_BY_KEY[key]
	if builtin then return builtin.path end

	local lsm = SharedMedia()
	if lsm then
		local ok, path = pcall(lsm.Fetch, lsm, "statusbar", key, true)
		if ok and path then return path end
	end

	return DEFAULT_TEXTURE
end

-- The saved setting's texture path.
function ns.BarTexturePath()
	return ns.TexturePathFor(HUDiniDB and HUDiniDB.barTexture or "blizzard")
end

-- {key, label} pairs for the options dropdown.
function ns.BarTextureList()
	local list = {}
	for _, t in ipairs(BUILTIN_TEXTURES) do
		list[#list + 1] = { key = t.key, label = t.label }
	end

	local lsm = SharedMedia()
	if lsm then
		local ok, names = pcall(lsm.List, lsm, "statusbar")
		if ok and names then
			for _, name in ipairs(names) do
				if not BUILTIN_BY_KEY[name] then
					list[#list + 1] = { key = name, label = name }
				end
			end
		end
	end

	return list
end

function ns.TextureNames()
	local out = {}
	for _, t in ipairs(ns.BarTextureList()) do out[#out + 1] = t.key end
	return table.concat(out, ", ")
end

--------------------------------------------------------------------------------
-- Font picker
--
-- Same shape as the texture picker: a few fonts every client ships, the Fira
-- family shipped in Fonts/ (SIL Open Font License, see Fonts/OFL-*.txt), and
-- every font LibSharedMedia knows about.
--------------------------------------------------------------------------------

local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local FONT_DIR = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"

local BUILTIN_FONTS = {
	{ key = "default",    label = Text("bars.font.default"),   path = DEFAULT_FONT },
	-- locale: skip font names
	{ key = "arialn",     label = "Arial Narrow",           path = "Fonts\\ARIALN.TTF" },
	{ key = "morpheus",   label = "Morpheus",               path = "Fonts\\MORPHEUS.TTF" },
	{ key = "skurri",     label = "Skurri",                 path = "Fonts\\SKURRI.TTF" },
	{ key = "firasans",   label = "Fira Sans",              path = FONT_DIR .. "FiraSans-Regular.ttf" },
	{ key = "firasanssb", label = "Fira Sans SemiBold",     path = FONT_DIR .. "FiraSans-SemiBold.ttf" },
	{ key = "firacond",   label = "Fira Sans Condensed",    path = FONT_DIR .. "FiraSansCondensed-Regular.ttf" },
	{ key = "firacondsb", label = "Fira Sans Condensed SemiBold", path = FONT_DIR .. "FiraSansCondensed-SemiBold.ttf" },
	{ key = "firacode",   label = "Fira Code",              path = FONT_DIR .. "FiraCode-Regular.ttf" },
	-- locale: end
}

local FONT_BY_KEY = {}
for _, f in ipairs(BUILTIN_FONTS) do FONT_BY_KEY[f.key] = f end

-- A font key (built-in or LibSharedMedia) to its path.
function ns.FontPathFor(key)

	local builtin = FONT_BY_KEY[key]
	if builtin then return builtin.path end

	local lsm = SharedMedia()
	if lsm then
		local ok, path = pcall(lsm.Fetch, lsm, "font", key, true)
		if ok and path then return path end
	end

	return DEFAULT_FONT
end

-- The saved setting's font path.
function ns.BarFontPath()
	return ns.FontPathFor(HUDiniDB and HUDiniDB.barFont or "default")
end

-- {key, label} pairs for the options dropdown.
function ns.BarFontList()
	local list = {}
	for _, f in ipairs(BUILTIN_FONTS) do
		list[#list + 1] = { key = f.key, label = f.label }
	end

	local lsm = SharedMedia()
	if lsm then
		local ok, names = pcall(lsm.List, lsm, "font")
		if ok and names then
			for _, name in ipairs(names) do
				if not FONT_BY_KEY[name] then
					list[#list + 1] = { key = name, label = name }
				end
			end
		end
	end

	return list
end

function ns.FontNames()
	local out = {}
	for _, f in ipairs(ns.BarFontList()) do out[#out + 1] = f.key end
	return table.concat(out, ", ")
end

local texts = {}   -- every bar FontString we own, so the font can be swapped

local function TrackText(fs)
	texts[#texts + 1] = fs
	return fs
end

ns.TrackText = TrackText

function ns.ApplyFont()
	local path = ns.BarFontPath()
	local size = HUDiniDB and HUDiniDB.fontSize or 12
	for _, fs in ipairs(texts) do
		-- SetFont answers false for a path the client cannot load.
		if fs:SetFont(path, size, "") == false then
			fs:SetFont(DEFAULT_FONT, size, "")
		end
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 1)
	end
end

--------------------------------------------------------------------------------
-- Bar colours
--
-- All of them live in HUDiniDB.colors. A pick always stores a fresh table,
-- so the shared default tables are never written to.
--------------------------------------------------------------------------------

local COLOR_KEYS = {
	{ key = "health",     label = Text("bars.color.health") },
	{ key = "trail",      label = Text("bars.color.trail") },
	{ key = "mana",       label = Text("bars.color.mana") },
	{ key = "rage",       label = Text("bars.color.rage") },
	{ key = "energy",     label = Text("bars.color.energy") },
	{ key = "resource",   label = Text("bars.color.resource") },
	{ key = "playercast", label = Text("bars.color.playercast") },
	{ key = "xp",         label = Text("bars.color.xp") },
	{ key = "rested",     label = Text("bars.color.rested") },
	{ key = "hostile",    label = Text("bars.color.hostile") },
	{ key = "neutral",    label = Text("bars.color.neutral") },
	{ key = "friendly",   label = Text("bars.color.friendly") },
	{ key = "tapped",     label = Text("bars.color.tapped") },
	{ key = "interrupt",  label = Text("bars.color.interrupt") },
	{ key = "shielded",   label = Text("bars.color.shielded") },
}

ns.COLOR_KEYS = COLOR_KEYS

local function Color(key)
	local saved = HUDiniDB and HUDiniDB.colors and HUDiniDB.colors[key]
	return saved or ns.defaults.colors[key]
end

ns.BarColor = Color

-- The power you have right now: mana, or rage in bear form, energy in cat
-- form. Returns the Enum.PowerType number and its token ("MANA").
local function DisplayPower()
	local ptype, token = UnitPowerType("player")
	return Plain(ptype) or 0, Plain(token) or "MANA"
end

ns.DisplayPower = DisplayPower

-- Mana, rage and energy have pickers. Anything else a class might use falls
-- back to Blizzard's own power colour, cached so it is one table per token.
local POWER_COLOR_KEY = { MANA = "mana", RAGE = "rage", ENERGY = "energy" }
local blizzPowerColor = {}

-- The colour key of the power you have right now, or nil.
function ns.PowerColorKey()
	local _, token = DisplayPower()
	return POWER_COLOR_KEY[token]
end

-- The colour keys of every power your class uses (the class file's
-- "powers"), else just the one you have now.
function ns.ClassPowerKeys()
	local tokens = ns.ClassValue("powers")
	if type(tokens) ~= "table" then
		local _, token = DisplayPower()
		tokens = { token }
	end
	local out = {}
	for _, token in ipairs(tokens) do
		if POWER_COLOR_KEY[token] then out[#out + 1] = POWER_COLOR_KEY[token] end
	end
	return out
end

-- The colour for a power token ("MANA"): your picker's, else Blizzard's.
local function PowerColorFor(token)
	local key = POWER_COLOR_KEY[token]
	if key then return Color(key) end

	if blizzPowerColor[token] == nil then
		local c = PowerBarColor and PowerBarColor[token]
		blizzPowerColor[token] = c and { c.r, c.g, c.b } or false
	end
	return blizzPowerColor[token] or Color("mana")
end

function ns.PowerColor()
	local _, token = DisplayPower()
	return PowerColorFor(token)
end

local function SetColor(key, r, g, b)
	HUDiniDB.colors[key] = { r, g, b }
	ns.RefreshBars()
end

-- The options panel speaks hex ("ffrrggbb"); HUDiniDB keeps { r, g, b }.
function ns.ColorHex(key)
	local c = Color(key)
	return CreateColor(c[1], c[2], c[3]):GenerateHexColor()
end

function ns.SetColorHex(key, hex)
	local c = CreateColorFromHexString(hex)
	if c then SetColor(key, c.r, c.g, c.b) end
end

--------------------------------------------------------------------------------
-- Plain bars
--------------------------------------------------------------------------------

local styled = {}   -- every StatusBar we own, so the texture can be swapped

-- colorKey names an entry in HUDiniDB.colors. Target health passes nil:
-- its colour follows the target, see TargetReactionColor. The bar remembers
-- its key and the colour it shows (shownColor), because a texture swap
-- resets the colour and ApplyTexture has to put it back.
local function StyleBar(b, colorKey, reverse)
	b.colorKey = colorKey
	b.shownColor = Color(colorKey or "hostile")
	b:SetStatusBarTexture(ns.BarTexturePath())
	b:SetStatusBarColor(unpack(b.shownColor))
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	if reverse then b:SetReverseFill(true) end
	styled[#styled + 1] = b
	return b
end

ns.StyleBar = StyleBar

-- Setting the texture resets the colour, so always put the colour back.
-- A picked colour lands here too.
-- The shield and heal parts follow a new texture and the bar's width
-- (TICK-0120); set below.
local AnchorPredict, SizePredict

function ns.ApplyTexture()
	local path = ns.BarTexturePath()
	for _, b in ipairs(styled) do
		b:SetStatusBarTexture(path)
		if b.colorKey and not b.stateShown then b.shownColor = Color(b.colorKey) end
		if b.shownColor then b:SetStatusBarColor(unpack(b.shownColor)) end
	end
	if AnchorPredict then AnchorPredict() end
end

-- Player bars live in the body so they hide with the icons. Target bars hang
-- off the anchor, which never hides, so they stay up whenever you have a target.
local TARGET_BARS = { targethealth = true, targetpower = true, targetcast = true }

-- Room between bar text and the bar's ends, in pixels.
local TEXT_PAD = 6

-- The health and power numbers (TICK-0102): barNumbers is "off",
-- "percent", "number" or "both"; anything else shows nothing.
local NUMBER_MODES = { percent = true, number = true, both = true }

local function NumbersOn()
	return NUMBER_MODES[HUDiniDB.barNumbers] == true
end


-- Two lines hug the bar's middle, one just above it and one just below, so
-- they sit close together whatever the bar height. The name line always
-- keeps its place, even when the second line is empty, so it never jumps
-- between targets.
--
-- Line 1 is [PvP mark] level [rank] name (TICK-0097). A mark that is off
-- takes no room: the level starts at the bar's end, and the name right
-- after the level. The anchors change only when a mark comes or goes.
local function PlaceTargetText(b)
	local state = (b.pvpShown and "p" or "-") .. (b.rankShown and "r" or "-")
		.. (b.stateShown and "s" or "-") .. (NumbersOn() and "n" or "-")
	if b.textPlaced == state then return end
	b.textPlaced = state

	b.level:ClearAllPoints()
	if b.pvpShown then
		b.level:SetPoint("BOTTOMLEFT", b.pvp, "RIGHT", 2, 1)
	else
		b.level:SetPoint("BOTTOMLEFT", b, "LEFT", TEXT_PAD, 1)
	end
	local before = b.level
	if b.rankShown then
		b.rank:ClearAllPoints()
		b.rank:SetPoint("BOTTOMLEFT", b.level, "BOTTOMRIGHT", 4, 0)
		before = b.rank
	end
	b.name:ClearAllPoints()
	b.name:SetPoint("BOTTOMLEFT", before, "BOTTOMRIGHT", 5, 0)
	if b.stateShown then
		-- Dead, Ghost or Offline at the line's right end (TICK-0106); the
		-- name stops short of it.
		b.name:SetPoint("BOTTOMRIGHT", b.state, "BOTTOMLEFT", -5, 0)
	elseif NumbersOn() then
		-- The health number has that place (TICK-0102).
		b.name:SetPoint("BOTTOMRIGHT", b.numbers, "BOTTOMLEFT", -5, 0)
	else
		b.name:SetPoint("BOTTOMRIGHT", b, "RIGHT", -TEXT_PAD, 1)
	end
	-- Under the name, not the level, so both lines start in one column. It
	-- runs to the bar's end: the target's power number is on its own bar
	-- (TICK-0126).
	b.info:ClearAllPoints()
	b.info:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
	b.info:SetPoint("TOPRIGHT", b, "RIGHT", -TEXT_PAD, -1)
end

local function CreateBar(key)
	local parent = TARGET_BARS[key] and HUDini or HUDini.body
	local b = CreateFrame("StatusBar", "HUDiniBar_" .. key, parent)
	-- Power and the target bars change colour as you play, see UpdateBars.
	local dynamic = (key == "targethealth" or key == "power" or key == "targetpower")
	-- Mana in forms (TICK-0107) wears the mana color, picker and all.
	local colorKey = (key == "druidmana") and "mana" or key
	StyleBar(b, (not dynamic) and colorKey or nil)

	b.backdrop = b:CreateTexture(nil, "BACKGROUND")
	b.backdrop:SetPoint("TOPLEFT", -1, 1)
	b.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
	b.backdrop:SetColorTexture(0, 0, 0, 0.85)

	if key == "health" then
		-- The damage trail: a sibling one frame level down, so the health fill
		-- draws over it. It carries the backdrop, since the health bar's own
		-- would cover it. It shows and hides with the health bar.
		local trail = CreateFrame("StatusBar", "HUDiniBar_trail", parent)
		StyleBar(trail, "trail")
		trail:SetAllPoints(b)
		b:SetFrameLevel(trail:GetFrameLevel() + 1)

		trail.backdrop = trail:CreateTexture(nil, "BACKGROUND")
		trail.backdrop:SetPoint("TOPLEFT", -1, 1)
		trail.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
		trail.backdrop:SetColorTexture(0, 0, 0, 0.85)
		b.backdrop:Hide()

		b:HookScript("OnShow", function() trail:Show() end)
		b:HookScript("OnHide", function() trail:Hide() end)
		trail:Hide()
		b.trail = trail

		-- Your PvP mark, inside the bar's left end (outside it is the
		-- bait icon, Alerts.lua). Over the fill.
		b.pvp = b:CreateTexture(nil, "OVERLAY")
		b.pvp:SetPoint("LEFT", b, "LEFT", 3, 0)
		b.pvp:Hide()

		-- Dead or Ghost in the bar's middle (TICK-0106), on a frame above
		-- the fill. UpdateBars sets it. Level + 1 and + 2 are the shield
		-- and heal parts (TICK-0120).
		b.textLayer = CreateFrame("Frame", nil, b)
		b.textLayer:SetAllPoints()
		b.textLayer:SetFrameLevel(b:GetFrameLevel() + 3)
		b.state = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.state:SetPoint("CENTER", b, "CENTER", 0, 0)

		-- Your health number in the same place (TICK-0102): the word, when
		-- there is one, takes its place.
		b.numbers = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.numbers:SetPoint("CENTER", b, "CENTER", 0, 0)
	end

	if key == "power" or key == "targetpower" then
		-- The power number at the middle (TICK-0102), above the fill. The
		-- cast bar rides on top (LayoutBars), and hides the number while it
		-- shows (UpdatePowerNumbers). The target's power bar is built the
		-- same way, for the target's power and cast (TICK-0126).
		-- The target's layer hangs off the anchor, not the bar: with Target
		-- power off the bar is hidden, but its slot still shows the
		-- target's cast, and the cast's words must draw. The number stays
		-- empty then (powerShown), and the words show only with the cast.
		b.textLayer = CreateFrame("Frame", nil, key == "targetpower" and parent or b)
		b.textLayer:SetAllPoints(b)
		b.textLayer:SetFrameLevel(b:GetFrameLevel() + 1)
		b.numbers = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.numbers:SetPoint("CENTER", b, "CENTER", 0, 0)

		-- The cast's words (TICK-0122): the spell name at the left, the
		-- time left at the right, and Failed or Interrupted at the middle
		-- when your cast does not finish. They are here, not on the cast
		-- bar: the cast bar is see-through, and on this layer, which
		-- LayoutBars puts above it, they read at full strength. They show
		-- only while the cast bar shows (ShowCastWords).
		b.castTime = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.castTime:SetPoint("RIGHT", b, "RIGHT", -TEXT_PAD, 0)
		b.castTime:SetJustifyH("RIGHT")
		b.castTime:SetTextColor(0.85, 0.85, 0.85)
		b.castName = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.castName:SetPoint("LEFT", b, "LEFT", TEXT_PAD, 0)
		b.castName:SetPoint("RIGHT", b.castTime, "LEFT", -5, 0)
		b.castName:SetJustifyH("LEFT")
		b.castName:SetWordWrap(false)
		b.castWord = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.castWord:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.castTime:Hide()
		b.castName:Hide()
		b.castWord:Hide()
	end

	if key == "targethealth" then
		-- Health only (TICK-0126): the target's power has its own bar under
		-- this one ("targetpower"), as yours does.
		-- The text rides a frame above the fill. Level + 1 and + 2 are the
		-- shield and heal parts (TICK-0120).
		b.textLayer = CreateFrame("Frame", nil, b)
		b.textLayer:SetAllPoints()
		b.textLayer:SetFrameLevel(b:GetFrameLevel() + 3)

		-- Top line: level, then the name. Bottom line: <Guild> Class for a
		-- player, <Title> and creature type for an NPC. PlaceTargetText sets
		-- the anchors.
		b.level = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.level:SetJustifyH("LEFT")
		b.level:SetTextColor(1, 0.82, 0)

		-- After the level: Elite, Rare, Rare Elite or Boss (TICK-0097).
		-- Before it, the target's PvP mark. UpdateTargetMarks sets both.
		b.rank = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.rank:SetJustifyH("LEFT")
		b.pvp = b.textLayer:CreateTexture(nil, "OVERLAY")
		b.pvp:SetPoint("LEFT", b, "LEFT", TEXT_PAD - 2, 0)
		b.pvp:Hide()

		b.name = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.name:SetJustifyH("LEFT")
		b.name:SetWordWrap(false)

		b.info = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.info:SetJustifyH("LEFT")
		b.info:SetWordWrap(false)
		b.info:SetTextColor(0.85, 0.85, 0.85)

		-- Dead, Ghost or Offline at the right end of the top line (TICK-0106).
		b.state = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.state:SetJustifyH("RIGHT")
		b.state:SetPoint("BOTTOMRIGHT", b, "RIGHT", -TEXT_PAD, 1)

		-- The target's health number in the same place (TICK-0102). Its
		-- power number is at the middle of its power bar, as yours is.
		b.numbers = TrackText(b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		b.numbers:SetJustifyH("RIGHT")
		b.numbers:SetPoint("BOTTOMRIGHT", b, "RIGHT", -TEXT_PAD, 1)
	end

	b:Hide()
	return b
end

local function GetBar(key)
	if not bars[key] then bars[key] = CreateBar(key) end
	return bars[key]
end

ns.GetBar = GetBar

-- Tick marks that split the resource bar into one segment per pip.
local resourceTicks = {}

local function LayoutResourceTicks(bar, width, height, count)
	for i = 1, count - 1 do
		local tick = resourceTicks[i]
		if not tick then
			tick = bar:CreateTexture(nil, "OVERLAY")
			tick:SetColorTexture(0, 0, 0, 0.85)
			resourceTicks[i] = tick
		end
		tick:ClearAllPoints()
		tick:SetSize(1, height)
		tick:SetPoint("LEFT", bar, "LEFT", math.floor(width * i / count + 0.5), 0)
		tick:Show()
	end

	for i = count, #resourceTicks do
		resourceTicks[i]:Hide()
	end
end

-- UnitReaction is 1-3 hostile, 4 neutral, 5-8 friendly. It can come back
-- secret when the unit's identity is hidden, so it goes through Plain first.
-- When it does, UnitCanAttack still answers the only question that matters.
local function TargetReactionColor()
	-- Tagged by someone else: no XP or loot for you from this one.
	if UnitIsTapDenied and Plain(UnitIsTapDenied("target")) then return Color("tapped") end

	local reaction = Plain(UnitReaction("player", "target"))
	if reaction then
		if reaction <= 3 then return Color("hostile") end
		if reaction == 4 then return Color("neutral") end
		return Color("friendly")
	end

	local canAttack = Plain(UnitCanAttack("player", "target"))
	if canAttack == true  then return Color("hostile") end
	if canAttack == false then return Color("friendly") end

	return Color("hostile")
end

-- Passthrough fill. Never read cur or maxValue.
local function Fill(bar, cur, maxValue)
	if not pcall(bar.SetMinMaxValues, bar, 0, maxValue) then return false end
	return pcall(bar.SetValue, bar, cur)
end

--------------------------------------------------------------------------------
-- Health and power numbers (TICK-0102)
--
-- Health and power are secret in a fight, so HUDini does no maths on them
-- and never reads them. The game does it all: UnitHealthPercent and
-- UnitPowerPercent give the percent, scaled to 0-100 by the game's own
-- curve; AbbreviateNumbers makes the short number (12.3k). Each answer goes
-- straight to SetText or SetFormattedText, which draw a secret. Every call
-- is in a pcall and only its plain ok is read: a throw or a missing API
-- draws no text. The percent is cut down by the format's %d, so 100% means
-- full. Both shows what the game did give when one half fails: an old
-- AbbreviateNumbers compares the number, which throws on a secret, and
-- the percent alone beats no text. NumbersOn (above PlaceTargetText) reads
-- the setting.
--------------------------------------------------------------------------------

-- ok, the percent of unit's health, or of its power ptype when given.
-- Without the game's curve there is no percent: scaling it here is maths.
local function Percent(unit, ptype)
	local curve = _G.CurveConstants and _G.CurveConstants.ScaleTo100
	if not curve then return false end
	if ptype then
		if type(_G.UnitPowerPercent) ~= "function" then return false end
		return pcall(_G.UnitPowerPercent, unit, ptype, false, curve)
	end
	if type(_G.UnitHealthPercent) ~= "function" then return false end
	return pcall(_G.UnitHealthPercent, unit, true, curve)
end

-- ok, the short number (12.3k) of unit's health, or of its power ptype.
local function Short(unit, ptype)
	if type(_G.AbbreviateNumbers) ~= "function" then return false end
	local value
	if ptype then value = UnitPower(unit, ptype) else value = UnitHealth(unit) end
	return pcall(_G.AbbreviateNumbers, value)
end

-- Write unit's numbers on fs: its health, or its power ptype when given.
-- show false (a state word, a bar with no place) empties it.
local function SetNumbers(fs, unit, ptype, show)
	local mode = show and HUDiniDB.barNumbers
	local drawn = false
	if mode == "percent" then
		local ok, pct = Percent(unit, ptype)
		drawn = ok and pcall(fs.SetFormattedText, fs, Text("bars.numbers.percent"), pct)
	elseif mode == "number" then
		local ok, short = Short(unit, ptype)
		drawn = ok and pcall(fs.SetText, fs, short)
	elseif mode == "both" then
		local okShort, short = Short(unit, ptype)
		local okPct, pct = Percent(unit, ptype)
		drawn = okShort and okPct
			and pcall(fs.SetFormattedText, fs, Text("bars.numbers.both"), short, pct)
		if not drawn and okPct then
			drawn = pcall(fs.SetFormattedText, fs, Text("bars.numbers.percent"), pct)
		end
		if not drawn and okShort then drawn = pcall(fs.SetText, fs, short) end
	end
	if not drawn then fs:SetText("") end
end

--------------------------------------------------------------------------------
-- Cast bars
--
-- A cast bar set is a holder frame plus one or two StatusBars. The target set
-- uses two: a grey one underneath and a yellow one on top. The interruptible
-- flag is a secret boolean, so we cannot pick a colour with an "if". Instead
-- SetAlphaFromBoolean fades one in and the other out, inside the game.
--------------------------------------------------------------------------------

local casts = {}
ns.casts = casts

local function CreateCastSet(key, unit, twoTone, reverse)
	local parent = TARGET_BARS[key] and HUDini or HUDini.body
	local holder = CreateFrame("Frame", "HUDiniCast_" .. key, parent)

	local base = StyleBar(CreateFrame("StatusBar", nil, holder),
		twoTone and "shielded" or "playercast", reverse)
	base:SetAllPoints(holder)

	local backdrop = holder:CreateTexture(nil, "BACKGROUND")
	backdrop:SetPoint("TOPLEFT", -1, 1)
	backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
	backdrop:SetColorTexture(0, 0, 0, 0.85)

	local set = {
		key      = key,
		unit     = unit,
		holder   = holder,
		base     = base,
		backdrop = backdrop,
	}

	if twoTone then
		set.hot = StyleBar(CreateFrame("StatusBar", nil, holder), "interrupt", reverse)
		set.hot:SetAllPoints(holder)
		set.hot:SetFrameLevel(base:GetFrameLevel() + 1)
	end

	holder:Hide()
	casts[key] = set
	return set
end

local function CastShown(key)
	local set = casts[key]
	return set ~= nil and set.holder:IsShown()
end

-- Your power number, unless your cast bar covers it: the two texts would
-- clash at the bar's middle (TICK-0102).
local function UpdatePowerNumbers()
	local bar = bars.power
	if not (bar and bar.numbers) then return end
	SetNumbers(bar.numbers, "player", DisplayPower(), HUDiniDB.showPower and not CastShown("playercast"))
end

-- The target's power number, the same way on its power bar (TICK-0126):
-- only while the bar has a fill (powerShown, ns.UpdateTargetPower), not
-- under the target's cast, and not with Dead, Ghost or Offline on its
-- health bar (TICK-0106). Never with no target: the number's layer hangs
-- off the HUD, not the bar, so a hidden bar does not hide it (TICK-0132).
local function UpdateTargetPowerNumbers()
	local bar = bars.targetpower
	if not (bar and bar.numbers) then return end
	local health = bars.targethealth
	local show = bar.powerShown and UnitExists("target") and not CastShown("targetcast")
		and not (health and health.stateShown)
	SetNumbers(bar.numbers, "target", bar.ptype, show and true or false)
end

-- The words of a cast bar (TICK-0122), on the text layer of the power bar
-- it rides on: yours, or the target's (TICK-0126).
local WORDS_BAR = { playercast = "power", targetcast = "targetpower" }

local function CastWords(set)
	local p = bars[WORDS_BAR[set.key]]
	if p and p.castName then return p end
end

-- mode "cast": the name and the time left. "flash": Failed or
-- Interrupted, alone. nil: no words.
local function ShowCastWords(set, mode)
	local p = CastWords(set)
	if not p then return end
	p.castName:SetShown(mode == "cast")
	p.castTime:SetShown(mode == "cast")
	p.castWord:SetShown(mode == "flash")
end

local function CastAlpha()
	return HUDiniDB and HUDiniDB.castAlpha or 1
end

-- Put the bar's own look back after Failed or Interrupted: its colour, its
-- see-through, and a word at full strength for the next time.
local function EndFlash(set)
	if not set.flash then return end
	set.flash = nil
	local base = set.base
	base.stateShown = nil
	base.shownColor = Color(base.colorKey)
	base:SetStatusBarColor(unpack(base.shownColor))
	set.holder:SetAlpha(CastAlpha())
	local p = CastWords(set)
	if p then p.castWord:SetAlpha(1) end
end

local function SetCastShown(set, shown)
	if not shown then
		EndFlash(set)
		ShowCastWords(set, nil)
		set.duration = nil
	end
	set.holder:SetShown(shown)
	if set.key == "playercast" then
		UpdatePowerNumbers()
	else
		UpdateTargetPowerNumbers()
	end
end

-- How a timer bar moves: jump straight to each new value, and fill up for a
-- cast but drain for a channel, the way Blizzard's cast bar does.
local INTERP    = (Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate) or 0
local DIR_CAST  = (Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime) or 0
local DIR_CHAN  = (Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime) or 1

-- Try to drive the bar from a DurationObject. A pcall result is a plain
-- boolean, which is the only safe thing to branch on here.
local function TryTimer(set, duration, direction)
	if not set.base.SetTimerDuration then return false end
	if not pcall(set.base.SetTimerDuration, set.base, duration, INTERP, direction) then
		return false
	end
	if set.hot then
		pcall(set.hot.SetTimerDuration, set.hot, duration, INTERP, direction)
	end
	return true
end

--------------------------------------------------------------------------------
-- The time left on your cast bar (TICK-0122)
--
-- The game's duration object gives the seconds left. In a fight they can
-- be secret: a secret number is never compared or joined, only handed to
-- SetFormattedText, which formats it inside the game (the way Shadowed
-- Unit Frames shows it on 12.x; read for facts only, D-021). HUDini picks
-- the short form ("12" from 10 s up) only when the game says the cast is
-- not secret and the number itself is plain.
--------------------------------------------------------------------------------

local function SecondsLeft(duration) return duration:GetRemainingDuration() end

local TENTHS = "%.1f" -- one decimal: "1.4"
local WHOLE  = "%d"   -- whole seconds: "12"

-- True only when the game says this unit's casting is not secret now. No
-- answer, an error or a secret answer count as secret. A client without
-- the question leaves it to the number itself (ns.IsSecret).
local function PlainCasting(unit)
	local secrets = _G.C_Secrets
	local ask = secrets and secrets.ShouldUnitSpellCastingBeSecret
	if type(ask) ~= "function" then return true end
	local ok, secret = pcall(ask, unit)
	return ok and not IsSecret(secret) and secret == false
end

local function ShowTimeLeft(set)
	local p = CastWords(set)
	local duration = set.duration
	if not (p and duration) then return end
	local fs = p.castTime
	local ok, left = pcall(SecondsLeft, duration)
	if not ok then
		fs:SetText("")
	elseif not IsSecret(left) and type(left) ~= "number" then
		fs:SetText("")
	elseif set.plainTime and not IsSecret(left) then
		-- One decimal under 10 s, whole seconds from 10 s up. 9.95 and up
		-- would round to "10.0", so it shows "10" for that moment.
		if left < 9.95 then
			fs:SetFormattedText(TENTHS, math.max(left, 0))
		else
			fs:SetFormattedText(WHOLE, math.max(math.floor(left), 10))
		end
	elseif not pcall(fs.SetFormattedText, fs, TENTHS, left) then
		fs:SetText("")
	end
end

--------------------------------------------------------------------------------
-- Failed and Interrupted (TICK-0122)
--
-- When your cast does not finish, the bar fills, goes red and says Failed
-- or Interrupted at its middle for 1 second, then fades out over half a
-- second. A new cast ends it at once (RefreshCast).
--------------------------------------------------------------------------------

local FLASH_HOLD, FLASH_FADE = 1, 0.5
local FLASH_RED = { 1, 0, 0 }

-- The game's own word, or ours when the client has none.
local function GameWord(global, key)
	local word = Plain(_G[global])
	if type(word) == "string" and word ~= "" then return word end
	return Text(key)
end

local FLASH_WORD = {
	UNIT_SPELLCAST_FAILED      = function() return GameWord("FAILED", "bars.cast.failed") end, -- locale: skip a game global
	UNIT_SPELLCAST_INTERRUPTED = function() return GameWord("INTERRUPTED", "bars.cast.interrupted") end, -- locale: skip a game global
}

local function StartFlash(set, word)
	local p = CastWords(set)
	if not p then return false end
	set.flash = GetTime()
	set.duration = nil
	local base = set.base
	-- The game's timer drives the fill until it is told otherwise.
	if base.ClearTimerDuration then pcall(base.ClearTimerDuration, base) end
	base:SetMinMaxValues(0, 1)
	base:SetValue(1)
	-- stateShown keeps the red through a texture swap (ns.ApplyTexture).
	base.stateShown = true
	base.shownColor = FLASH_RED
	base:SetStatusBarColor(unpack(FLASH_RED))
	p.castWord:SetText(word)
	p.castWord:SetAlpha(1)
	ShowCastWords(set, "flash")
	return true
end

-- The game has a cast for this unit right now.
local function StillCasting(unit)
	return UnitCastingDuration ~= nil and UnitCastingDuration(unit) ~= nil
end

-- The event's cast is the one on the bar. Plain IDs are compared. A
-- secret ID cannot be: then the bar's cast is the one that ended only if
-- the game has no cast left.
local function SameCast(set, castID)
	local mine = set.castID
	if not IsSecret(mine) and not IsSecret(castID) and mine ~= nil and castID ~= nil then
		return mine == castID
	end
	return not StillCasting(set.unit)
end

-- UNIT_SPELLCAST_FAILED or _INTERRUPTED for your cast bar. True when it
-- starts the flash. Not every one is the bar's cast: a spell you try while
-- another casts fails too, and so does one with no cast at all (on
-- cooldown, out of range). A channel has no cast ID, and only Interrupted
-- ends one.
local function CastNotFinished(set, event, castID)
	if not (set.duration and set.holder:IsShown()) then return false end
	if set.channel then
		if event ~= "UNIT_SPELLCAST_INTERRUPTED" then return false end
	elseif not SameCast(set, castID) then
		return false
	end
	return StartFlash(set, FLASH_WORD[event]())
end

-- UNIT_SPELLCAST_CHANNEL_STOP for your cast bar. Its interruptedBy is set
-- when the channel was cut short: the game's own bar reads Interrupted
-- from it, not from UNIT_SPELLCAST_INTERRUPTED. A secret one counts as
-- set; it is never compared.
local function ChannelCut(set, interruptedBy)
	if not (set.channel and set.duration and set.holder:IsShown()) then return false end
	if not IsSecret(interruptedBy) and interruptedBy == nil then return false end
	return StartFlash(set, FLASH_WORD.UNIT_SPELLCAST_INTERRUPTED())
end

-- Every frame while your cast bar shows: the time left, or the flash's
-- hold and fade. GetTime is plain.
local function CastTick(set)
	if set.flash then
		local t = GetTime() - set.flash
		if t >= FLASH_HOLD + FLASH_FADE then
			SetCastShown(set, false)
			return
		end
		local a = t <= FLASH_HOLD and 1 or 1 - (t - FLASH_HOLD) / FLASH_FADE
		set.holder:SetAlpha(CastAlpha() * a)
		local p = CastWords(set)
		if p then p.castWord:SetAlpha(a) end
	elseif set.duration then
		ShowTimeLeft(set)
	end
end

local function RefreshCast(set)
	local unit = set.unit
	local casting, channelling = false, false
	local duration

	if UnitCastingDuration then
		duration = UnitCastingDuration(unit)
		casting = TryTimer(set, duration, DIR_CAST)
	end

	if not casting and UnitChannelDuration then
		duration = UnitChannelDuration(unit)
		channelling = TryTimer(set, duration, DIR_CHAN)
	end

	if not (casting or channelling) then
		-- Failed or Interrupted stays for its time: the stop event that
		-- comes after it ends nothing. A stop before it ends the cast, and
		-- the word comes too late, as on the game's own bar.
		if set.flash then return end
		SetCastShown(set, false)
		if set.key == "targetcast" and ns.OnTargetCast then ns.OnTargetCast(nil, true) end
		return
	end

	-- A new cast ends Failed or Interrupted at once.
	EndFlash(set)

	-- One call each. Calling twice could straddle the end of the cast.
	local name, notInterruptible, castID
	if casting then
		local n, _, _, _, _, _, id, ni = UnitCastingInfo(unit)
		name, castID, notInterruptible = n, id, ni
	else
		local n, _, _, _, _, _, ni = UnitChannelInfo(unit)
		name, notInterruptible = n, ni
	end

	-- The cast bar's words: the name goes to the game as it is, secret
	-- or not, never joined or compared.
	local words = CastWords(set)
	if words then
		if not pcall(words.castName.SetText, words.castName, name) then
			words.castName:SetText("")
		end
		set.duration, set.channel, set.castID = duration, channelling, castID
		set.plainTime = PlainCasting(unit)
		ShowTimeLeft(set)
		ShowCastWords(set, "cast")
	end

	-- Yellow when you can interrupt, grey when you cannot. 255 and 0 are safe
	-- under either alpha scale: 255 clamps to fully on, 0 is fully off.
	if set.hot and set.hot.SetAlphaFromBoolean then
		pcall(set.hot.SetAlphaFromBoolean, set.hot, notInterruptible, 0, 255)
		pcall(set.base.SetAlphaFromBoolean, set.base, notInterruptible, 255, 0)
	end

	if set.key == "targetcast" and ns.OnTargetCast then
		ns.OnTargetCast(notInterruptible)
	end

	SetCastShown(set, true)
end

-- Your own cast bar rides on the power bar (LayoutBars), so it shows only
-- while both are on. With the power bar off it would have no place of its
-- own, and Blizzard's cast bar comes back instead (Core.lua BLIZZ_FRAMES).
local function PlayerCastWanted()
	local db = HUDiniDB
	return db.showPlayerCast and db.showPower
end

-- The target's power bar draws its fill only with the target's health bar
-- on, as before it had a bar of its own (TICK-0126).
local function TargetPowerWanted()
	local db = HUDiniDB
	return (db.showTargetHealth and db.showTargetPower) and true or false
end

-- Its slot stays for the target's cast too: with Target power off, the
-- slot keeps its place and shows only while the target casts, so the
-- interrupt alert has its bar, and the stack never jumps.
local function TargetPowerSlot()
	return (TargetPowerWanted() or HUDiniDB.showTargetCast) and true or false
end

--------------------------------------------------------------------------------
-- The class resource bar
--
-- The class profile names the resource (Classes.lua), one of two kinds:
--
--     { aura = "Name", max = 5 }                  stacks of a buff on you
--     { power = "ComboPoints", onlyWith = "ENERGY" }  a power type; onlyWith
--                                                  limits it to one form
--
-- A class without one gets no resource bar at all.
--
-- The first attempt went through 12.1's AuraContainer and SetApplicationBar.
-- That road is closed: the bar you hand to SetApplicationBar must be a
-- descendant of the AuraButton, and an addon frame cannot be reparented into
-- one ("Reparenting disallowed as child object would inherit forbidden
-- aspects").
--
-- SenseiClassResourceBar showed the short way. Just read the aura:
--
--     local data = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
--     local stacks = data and data.applications
--
-- data is a plain table, so testing it is safe. applications may be secret,
-- so it never gets read, compared, or defaulted with "or". It goes straight
-- into StatusBar:SetValue, which is built to swallow a secret.
--------------------------------------------------------------------------------

-- The class's resource right now, or nil. A power resource tied to one form
-- (a druid's combo points, onlyWith = "ENERGY") only counts in that form.
local function Resource()
	local r = ns.ClassValue("resource")
	if type(r) ~= "table" then return nil end
	if r.aura then return r end
	if r.power and Enum.PowerType and Enum.PowerType[r.power] then
		if r.onlyWith then
			local _, token = DisplayPower()
			if token ~= r.onlyWith then return nil end
		end
		return r
	end
	return nil
end

-- How many pips: the class file's max, else the game's own maximum.
local function ResourcePips(r)
	if r.max then return r.max end
	if r.power then
		local most = Plain(UnitPowerMax("player", Enum.PowerType[r.power]))
		if most and most > 0 then return most end
	end
	return 5
end

-- The bar shows only when you want it and your class has a resource.
local function ShowResource()
	return HUDiniDB.showResource and Resource() ~= nil
end

--------------------------------------------------------------------------------
-- Mana in forms (TICK-0107)
--
-- In Bear or Cat Form the power bar shows rage or energy, so a druid cannot
-- see if there is mana left to shift back and heal. A thin bar under the
-- power bar shows your mana while your power is another one of your class's
-- powers (the class file's list): today only the druid's rage and energy.
-- It rides on the power bar's switch too. Your mana is often secret in a
-- fight, so it goes straight to the bar, never read.
--------------------------------------------------------------------------------

ns.defaults.showDruidMana = true

local MANA = (Enum.PowerType and Enum.PowerType.Mana) or 0

-- Your class has mana and a form with another power (the class file's
-- powers list holds MANA and one more): today only the druid. A mage's list
-- is MANA alone, so its Options row stays gray.
local function HasFormMana()
	local tokens = ns.ClassValue("powers")
	if type(tokens) ~= "table" or #tokens < 2 then return false end
	for _, token in ipairs(tokens) do
		if token == "MANA" then return true end
	end
	return false
end

ns.HasFormMana = HasFormMana

-- The bar's row keeps its slot under the power bar whenever you want it,
-- the power bar is on and your class has a form with another power, in
-- caster form too. A shift then only shows or hides the bar, and never
-- moves the stack: the click buttons cannot follow a move in a fight
-- (Clicks.lua).
local function FormManaSlot()
	local db = HUDiniDB
	return (db.showDruidMana and db.showPower and HasFormMana()) and true or false
end

-- The bar shows in its slot while your power now is one of your class's
-- powers other than mana. A secret power type reads as mana
-- (DisplayPower), so it draws no bar.
local function ShowFormMana()
	if not FormManaSlot() then return false end
	local _, now = DisplayPower()
	if now == "MANA" then return false end
	for _, token in ipairs(ns.ClassValue("powers")) do
		if token == now then return true end
	end
	return false
end

ns.ShowFormMana = ShowFormMana

-- Thin: half a bar, at least 2 pixels.
local function FormManaHeight()
	return math.max(2, math.floor((HUDiniDB.barHeight or 10) / 2 + 0.5))
end

local function UpdateFormMana()
	if not ShowFormMana() then return end
	Fill(GetBar("druidmana"), UnitPower("player", MANA), UnitPowerMax("player", MANA))
end

function ns.UpdateResource()
	local resource = Resource()
	if not (HUDiniDB.showResource and resource) then return end

	local bar = GetBar("resource")

	if resource.power then
		-- A power type is a plain passthrough, like health.
		local ptype = Enum.PowerType[resource.power]
		Fill(bar, UnitPower("player", ptype), UnitPowerMax("player", ptype))
		return
	end

	bar:SetMinMaxValues(0, ResourcePips(resource))

	if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
		bar:SetValue(0)
		return
	end

	local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", resource.aura, "HELPFUL")

	-- No aura, or the call refused. Either way, empty.
	if not ok or not data then
		bar:SetValue(0)
		return
	end

	-- applications can be secret. Hand it over without looking at it, and fall
	-- back to empty only if the widget refuses it.
	if not pcall(bar.SetValue, bar, data.applications) then
		bar:SetValue(0)
	end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- topOffset is how far above the anchor the topmost icon row sits.
-- width matches the icon grid so everything lines up, and left is the
-- grid's left edge from the anchor's (0 when it grows right).
function ns.LayoutBars(topOffset, width, left)
	left = left or 0
	local db  = HUDiniDB
	local gap = db.barGap
	local y   = topOffset + gap

	-- Built bottom up, so the XP bar ends up closest to the icons, then the
	-- resource bar.
	-- Health bars stand taller than the rest.
	local tall = db.healthHeight

	-- The target block matches yours (TICK-0126): health on top, power
	-- under it, each as tall as yours. Its cast rides on its power bar
	-- (below), so it has no row of its own.
	local rows = {
		{ key = "xp",           show = ns.ShowXP and ns.ShowXP() or false, height = db.xpHeight },
		{ key = "resource",     show = ShowResource(),      height = db.barHeight },
		{ key = "druidmana",    show = FormManaSlot(),      height = FormManaHeight() },
		{ key = "power",        show = db.showPower,        height = db.barHeight },
		{ key = "health",       show = db.showHealth,       height = tall },
		{ key = "targetpower",  show = TargetPowerSlot(),   height = db.barHeight },
		{ key = "targethealth", show = db.showTargetHealth, height = tall },
	}

	-- Every enabled row keeps its slot even when it has nothing to draw, so
	-- the stack never jumps around mid fight. top: the stack's top edge.
	local top = topOffset
	for _, row in ipairs(rows) do
		local frame = GetBar(row.key)
		if row.show then
			frame:ClearAllPoints()
			frame:SetSize(width, row.height)
			frame:SetPoint("BOTTOMLEFT", HUDini, "TOPLEFT", left, y)
			if frame.predict and SizePredict then SizePredict(frame.predict, width) end

			if row.key == "resource" then
				LayoutResourceTicks(frame, width, row.height, ResourcePips(Resource()))
			end

			top = y + row.height
			y = top + gap
		end
	end

	ns.UpdateBarVisibility()

	-- Your own cast bar rides on top of the power bar, see-through. With the
	-- power bar off, the bar keeps its old points (or none after a /reload),
	-- so the cast bar is hidden instead of drawn over another row.
	local power = GetBar("power")
	local mine  = casts.playercast.holder
	mine:ClearAllPoints()
	if PlayerCastWanted() then
		mine:SetAllPoints(power)
		mine:SetFrameLevel(power:GetFrameLevel() + 2)
		mine:SetAlpha(db.castAlpha)
		-- The cast's words, above the see-through cast bar (TICK-0122).
		-- The fill is the holder's child, one level up: same level, no
		-- fixed order, so the layer goes above the fill.
		power.textLayer:SetFrameLevel(math.max(power:GetFrameLevel() + 4,
			casts.playercast.base:GetFrameLevel() + 1))
	else
		SetCastShown(casts.playercast, false)
	end

	-- The target's cast rides on the target's power bar the same way
	-- (TICK-0126). With Target power off the slot is still there, and
	-- the cast draws in it alone (TargetPowerSlot).
	local theirPower = GetBar("targetpower")
	local theirs = casts.targetcast
	theirs.holder:ClearAllPoints()
	if db.showTargetCast then
		theirs.holder:SetAllPoints(theirPower)
		theirs.holder:SetFrameLevel(theirPower:GetFrameLevel() + 2)
		theirs.holder:SetAlpha(db.castAlpha)
		theirPower.textLayer:SetFrameLevel(math.max(theirPower:GetFrameLevel() + 4,
			theirs.base:GetFrameLevel() + 1, theirs.hot:GetFrameLevel() + 1))
	else
		SetCastShown(theirs, false)
	end

	return top
end

--------------------------------------------------------------------------------
-- Damage trail
--
-- A second bar sits under your health fill and follows your health half a
-- second late. Take a hit and the fill drops at once while the trail stays,
-- so the chunk you lost shows between them, then the trail drains to catch up.
-- A heal needs nothing: the trail lags behind, hidden under the fill.
--
-- Health is secret in combat, so nothing here reads it. Both bars get the
-- number by passthrough, and "a hit happened" is never asked at all: every
-- health change just restarts the delay.
--------------------------------------------------------------------------------

local TRAIL_DELAY = 0.5
local TRAIL_EASE  = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local trailTimer

-- Bring the trail level with your health, draining smoothly when it can.
local function CatchUpTrail(smooth)
	local trail = bars.health and bars.health.trail
	if not trail then return end
	pcall(trail.SetMinMaxValues, trail, 0, UnitHealthMax("player"))
	if smooth and TRAIL_EASE
		and pcall(trail.SetValue, trail, UnitHealth("player"), TRAIL_EASE) then
		return
	end
	pcall(trail.SetValue, trail, UnitHealth("player"))
end

-- Every change to your health restarts the delay. With the trail off it
-- follows at once, so it stays hidden under the fill.
function ns.OnPlayerHealth()
	if trailTimer then trailTimer:Cancel() trailTimer = nil end
	if not HUDiniDB.damageTrail then
		CatchUpTrail(false)
		return
	end
	trailTimer = C_Timer.NewTimer(TRAIL_DELAY, function()
		trailTimer = nil
		CatchUpTrail(true)
	end)
end

--------------------------------------------------------------------------------
-- Shields and incoming heals (TICK-0120, D-026)
--
-- The game's own health bars draw four parts on top of the fill: heals on
-- their way (yours, then other players'), a damage shield, and a heal
-- absorb that eats into the fill. HUDini draws them on your health bar and
-- the target's.
--
-- Every amount is secret on 12.x, and UnitGetTotalAbsorbs and
-- UnitGetIncomingHeals are not read here. The game does the sums:
-- UnitGetDetailedHealPrediction fills a calculator (one per unit), the
-- calculator clamps each amount to the room on the bar, and each amount
-- goes straight to a part's SetValue, out of the unit's maximum health.
-- Lua never adds, compares, formats or tests an amount.
--
-- Each part is a StatusBar as wide as the health bar, its left end on the
-- right end of the fill before it, so a value of max would fill the whole
-- bar's width. The chain: health fill, your heals, other heals, shield.
-- The heal absorb fills leftward from the health fill's right end. A frame
-- that clips its children keeps any part that runs long inside the bar.
--
-- A shield bigger than the missing health shows the game's over-shield
-- glow at the bar's right end; a heal absorb bigger than the health, its
-- glow at the left end. "Bigger" is the calculator's clamped flag, a
-- secret boolean, so it goes to SetAlphaFromBoolean.
--
-- The parts are made once, out of a fight. A client without the API makes
-- none, and /hud debug modules says so.
--------------------------------------------------------------------------------

local PREDICT_BARS = { player = "health", target = "targethealth" }
local PREDICT_FAILED = "debug.healPrediction.failed" -- a note: the game gave no answer

-- The game's own colors when it has them; the classic frame's look if not.
local function GameColor(name, r, g, b, a)
	local c = _G[name]
	if type(c) == "table" and type(c.GetRGBA) == "function" then
		local ok, cr, cg, cb, ca = pcall(c.GetRGBA, c)
		if ok and type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
			return { cr, cg, cb, type(ca) == "number" and ca or 1 }
		end
	end
	return { r, g, b, a or 1 }
end

local predictModule = ns.NewModule("healprediction", {
	label = "Absorbs and incoming heals", -- locale: skip a debug name (/hud debug modules)
	isOn = function()
		return HUDiniDB and (HUDiniDB.showHealth or HUDiniDB.showTargetHealth)
	end,
})

-- The calculator's modes, set once: heals and shields fill only the missing
-- health, a heal absorb only the health there is, and each heal absorb and
-- incoming heal cancel out, as on the game's frames.
local function SetModes(calc)
	local E = Enum
	local function Mode(method, enum, key)
		local set = E[enum] and E[enum][key]
		if set ~= nil and type(calc[method]) == "function" then pcall(calc[method], calc, set) end
	end
	Mode("SetIncomingHealClampMode", "UnitIncomingHealClampMode", "MissingHealth")
	Mode("SetDamageAbsorbClampMode", "UnitDamageAbsorbClampMode", "MissingHealth")
	Mode("SetHealAbsorbClampMode", "UnitHealAbsorbClampMode", "CurrentHealth")
	Mode("SetHealAbsorbMode", "UnitHealAbsorbMode", "ReducedByIncomingHeals")
	Mode("SetMaximumHealthMode", "UnitMaximumHealthMode", "Default") -- locale: skip an enum key
end

-- A part: a StatusBar the health bar's width. texture: the game's own fill
-- texture, tinted; nil: the HUD's bar texture in that color.
local function Part(holder, texture, color)
	local part = CreateFrame("StatusBar", nil, holder)
	if texture then
		part:SetStatusBarTexture(texture)
		part:SetStatusBarColor(unpack(color))
		part:SetMinMaxValues(0, 1)
		part:SetValue(0)
	else
		-- A texture swap puts this color back (ApplyTexture).
		StyleBar(part, nil)
		part.shownColor = color
		part:SetStatusBarColor(unpack(color))
	end
	return part
end

-- The glow at one end of the bar, half over it, as the game's frames have it.
local function Glow(holder, bar, texture, atRight)
	local glow = holder:CreateTexture(nil, "OVERLAY")
	glow:SetTexture(texture)
	glow:SetBlendMode("ADD")
	glow:SetWidth(16)
	if atRight then
		glow:SetPoint("TOPLEFT", bar, "TOPRIGHT", -7, 0)
		glow:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", -7, 0)
	else
		glow:SetPoint("TOPRIGHT", bar, "TOPLEFT", 7, 0)
		glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 7, 0)
	end
	glow:SetAlpha(0)
	return glow
end

-- Put each part's left end on the right end of the fill before it.
local function After(part, before)
	local tex = before:GetStatusBarTexture()
	part:ClearAllPoints()
	part:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
	part:SetPoint("BOTTOMLEFT", tex, "BOTTOMRIGHT", 0, 0)
end

local function Anchor(p)
	local bar = p.bar
	After(p.myHeal, bar)
	After(p.otherHeal, p.myHeal)
	After(p.shield, p.otherHeal)
	local tex = bar:GetStatusBarTexture()
	p.healAbsorb:ClearAllPoints()
	p.healAbsorb:SetPoint("TOPRIGHT", tex, "TOPRIGHT", 0, 0)
	p.healAbsorb:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
end

local function SetWidths(p, width)
	for _, part in ipairs(p.parts) do pcall(part.SetWidth, part, width) end
end
SizePredict = SetWidths

-- Make the parts for one health bar. False when this client has no
-- calculator.
local function BuildPredict(bar)
	if bar.predict ~= nil then return bar.predict ~= false end
	local create = _G.CreateUnitHealPredictionCalculator
	if type(create) ~= "function" or type(_G.UnitGetDetailedHealPrediction) ~= "function" then
		bar.predict = false
		return false
	end
	local ok, calc = pcall(create)
	if not ok or calc == nil then
		bar.predict = false
		return false
	end
	SetModes(calc)

	local p = { bar = bar, calc = calc }
	-- Over the health fill, under the bar's text (and, on the target, under
	-- its power, which covers the lower half): CreateBar keeps level + 1
	-- and + 2 free for these.
	local level = bar:GetFrameLevel()
	p.clip = CreateFrame("Frame", nil, bar)
	p.clip:SetAllPoints(bar)
	p.clip:SetFrameLevel(level + 1)
	p.clip:SetClipsChildren(true)

	p.myHeal = Part(p.clip, nil, GameColor("HEALTHBAR_MY_HEAL_PREDICTION_COLOR", 0, 0.827, 0.765))
	p.otherHeal = Part(p.clip, nil, GameColor("HEALTHBAR_OTHER_HEAL_PREDICTION_COLOR", 0, 0.631, 0.557))
	p.shield = Part(p.clip, "Interface\\RaidFrame\\Shield-Fill", GameColor("HEALTHBAR_TOTAL_ABSORB_COLOR", 1, 1, 1))
	p.healAbsorb = Part(p.clip, "Interface\\RaidFrame\\Absorb-Fill", GameColor("HEALTHBAR_HEAL_ABSORB_COLOR", 1, 1, 1))
	p.healAbsorb:SetReverseFill(true)
	p.parts = { p.myHeal, p.otherHeal, p.shield, p.healAbsorb }
	for _, part in ipairs(p.parts) do part:SetFrameLevel(level + 2) end

	-- The glows stand half outside the bar, so they are not clipped.
	p.glows = CreateFrame("Frame", nil, bar)
	p.glows:SetAllPoints(bar)
	p.glows:SetFrameLevel(level + 2)
	p.overShield = Glow(p.glows, bar, "Interface\\RaidFrame\\Shield-Overshield", true)
	p.overHealAbsorb = Glow(p.glows, bar, "Interface\\RaidFrame\\Absorb-Overabsorb", false)

	Anchor(p)
	SetWidths(p, bar:GetWidth())
	bar:HookScript("OnSizeChanged", function(_, width) SetWidths(p, width) end)
	bar.predict = p
	return true
end

-- A new bar texture may give the fills new textures: put the chain back.
AnchorPredict = function()
	for _, key in pairs(PREDICT_BARS) do
		local bar = bars[key]
		if bar and bar.predict then Anchor(bar.predict) end
	end
end

-- Light a glow from the calculator's clamped flag, which can be secret.
-- 255 and 0 are safe under either alpha scale (see the target cast bar).
-- Without SetAlphaFromBoolean only a plain true lights it.
local function GlowFrom(glow, clamped)
	if glow.SetAlphaFromBoolean and pcall(glow.SetAlphaFromBoolean, glow, clamped, 255, 0) then
		return
	end
	glow:SetAlpha(Plain(clamped) == true and 1 or 0)
end

-- Every part empty and no glow.
local function ClearPredict(p)
	for _, part in ipairs(p.parts) do
		pcall(part.SetMinMaxValues, part, 0, 1)
		pcall(part.SetValue, part, 0)
	end
	p.overShield:SetAlpha(0)
	p.overHealAbsorb:SetAlpha(0)
end

-- Draw the parts for a unit from the game's calculator. A dead unit's bar
-- is full and gray (Dead, Ghost and Offline), with no parts on it.
local function Predict(bar, unit)
	local p = bar and bar.predict
	if not p then return end
	if not predictModule.enabled or bar.stateShown then
		ClearPredict(p)
		return
	end
	local calc = p.calc
	local okMax, maxHealth
	if pcall(_G.UnitGetDetailedHealPrediction, unit, "player", calc) then
		okMax, maxHealth = pcall(calc.GetMaximumHealth, calc)
	end
	-- No answer from the game: no parts, and /hud debug modules says why
	-- until it answers again.
	if not okMax then
		predictModule.note = PREDICT_FAILED
		ClearPredict(p)
		return
	end
	if predictModule.note == PREDICT_FAILED then predictModule.note = nil end
	local okHeal, _, mine, others = pcall(calc.GetIncomingHeals, calc)
	local okShield, shield, over = pcall(calc.GetDamageAbsorbs, calc)
	local okAbsorb, absorb, overAbsorb = pcall(calc.GetHealAbsorbs, calc)
	local function Draw(part, ok, amount)
		if not (ok and Fill(part, amount, maxHealth)) then
			pcall(part.SetMinMaxValues, part, 0, 1)
			pcall(part.SetValue, part, 0)
		end
	end
	Draw(p.myHeal, okHeal, mine)
	Draw(p.otherHeal, okHeal, others)
	Draw(p.shield, okShield, shield)
	Draw(p.healAbsorb, okAbsorb, absorb)
	if okShield then GlowFrom(p.overShield, over) else p.overShield:SetAlpha(0) end
	if okAbsorb then GlowFrom(p.overHealAbsorb, overAbsorb) else p.overHealAbsorb:SetAlpha(0) end
end

ns.PredictHealth = Predict

local function PredictUnit(unit)
	local key = PREDICT_BARS[unit]
	if key then Predict(bars[key], unit) end
end

-- Made once, out of a fight: the health bars exist by then (GetBar).
local function StartPredict()
	if InCombatLockdown() then
		predictModule.waiting = true
		return
	end
	predictModule.waiting = nil
	local made = false
	for unit, key in pairs(PREDICT_BARS) do
		if BuildPredict(GetBar(key)) then made = true end
		PredictUnit(unit)
	end
	predictModule.note = (not made) and "debug.healPrediction.missing" or nil
end

predictModule:On({ "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" },
	function(_, unit) PredictUnit(unit) end)
predictModule:On("PLAYER_REGEN_ENABLED", function()
	if predictModule.waiting then StartPredict() end
end)

function predictModule:OnEnable()
	StartPredict()
end

function predictModule:OnDisable()
	self.waiting = nil
	for _, key in pairs(PREDICT_BARS) do
		local bar = bars[key]
		if bar and bar.predict then ClearPredict(bar.predict) end
	end
end

--------------------------------------------------------------------------------
-- Visibility
--
-- The player bars sit in HUDini.body, so they come and go with the icons.
-- The target bars hang off the anchor and follow one rule only: do you have a
-- target. Hostile or friendly, in combat or not.
--------------------------------------------------------------------------------

function ns.UpdateBarVisibility()
	local db = HUDiniDB
	if not db then return end

	GetBar("health"):SetShown(db.showHealth)
	GetBar("power"):SetShown(db.showPower)
	GetBar("druidmana"):SetShown(ShowFormMana())
	GetBar("resource"):SetShown(ShowResource())
	GetBar("xp"):SetShown(ns.ShowXP and ns.ShowXP() or false)

	local hasTarget = UnitExists("target")
	GetBar("targethealth"):SetShown(db.showTargetHealth and hasTarget)
	GetBar("targetpower"):SetShown(TargetPowerWanted() and hasTarget)

	if not (db.showTargetCast and hasTarget) then
		casts.targetcast.holder:Hide()
	end

	-- The click buttons follow the bars (Clicks.lua).
	if ns.SyncClicks then ns.SyncClicks() end
end

--------------------------------------------------------------------------------
-- Dead, Ghost and Offline (TICK-0106)
--
-- A dead unit's bar is empty, and an empty bar shows no color at all. So a
-- unit in one of these states gets a full gray bar with the word on it.
-- Each answer can be secret: only a plain true counts, so a secret, a throw
-- or a missing API draws the normal bar. Offline is asked only of a player;
-- an NPC is never offline. Ghost comes before Dead, since a ghost is also
-- "dead or ghost".
--------------------------------------------------------------------------------

local GRAY = { 0.5, 0.5, 0.5 }

-- A plain answer from the game, or nil: a secret, a throw or a missing API.
-- The target marks below use it too.
local function Ask(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok then return nil end
	return Plain(v)
end

-- "offline", "ghost", "dead", or nil for a living unit, a unit with the
-- switch off, or any answer the game keeps secret.
function ns.UnitState(unit)
	local db = HUDiniDB
	if not (db and db.showDeadState) then return nil end
	if Ask(UnitIsPlayer, unit) == true and Ask(UnitIsConnected, unit) == false then
		return "offline"
	end
	if Ask(_G.UnitIsGhost, unit) == true then return "ghost" end
	if Ask(UnitIsDeadOrGhost, unit) == true then return "dead" end
	return nil
end

-- Fill the bar for a unit: full and gray with the word for a state, else
-- the passthrough fill in the bar's own color.
local function FillUnit(bar, unit, color)
	local state = ns.UnitState(unit)
	if state then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		color = GRAY
	else
		Fill(bar, UnitHealth(unit), UnitHealthMax(unit))
	end
	bar.state:SetText(state and Text("bars.state." .. state) or "")
	-- The word takes the number's place (TICK-0102).
	SetNumbers(bar.numbers, unit, nil, state == nil)
	local was = bar.stateShown
	bar.stateShown = state ~= nil
	if bar.shownColor ~= color then
		bar.shownColor = color
		bar:SetStatusBarColor(unpack(color))
	end
	if bar.level and was ~= bar.stateShown then PlaceTargetText(bar) end
	-- Shields and incoming heals follow the fill (TICK-0120).
	Predict(bar, unit)
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

-- No alert scan here: this runs on every health and power tick. The alerts
-- follow their own events (Alerts.lua), and the power bar picks up their
-- dispel tint (ns.powerTint) at the next fill.
function ns.UpdateBars()
	local db = HUDiniDB

	if db.showHealth then
		FillUnit(GetBar("health"), "player", Color("health"))
	end

	if db.showPower then
		local bar   = GetBar("power")
		local ptype = DisplayPower()
		Fill(bar, UnitPower("player", ptype), UnitPowerMax("player", ptype))
		UpdatePowerNumbers()

		-- The power's own colour, unless an alert tints it (a curse, Alerts.lua).
		local color = ns.powerTint or ns.PowerColor()
		if bar.shownColor ~= color then
			bar.shownColor = color
			bar:SetStatusBarColor(unpack(color))
		end

		UpdateFormMana()
	end

	if db.showTargetHealth and UnitExists("target") then
		-- The colour is stored on the bar as well, so a texture swap keeps it.
		FillUnit(GetBar("targethealth"), "target", TargetReactionColor())

		ns.UpdateTargetPower()
	elseif bars.targethealth then
		-- No target: drop the word and the numbers, so a sample (test mode)
		-- never shows them.
		local bar = bars.targethealth
		bar.numbers:SetText("")
		if bars.targetpower then
			bars.targetpower.powerShown = false
			bars.targetpower.numbers:SetText("")
		end
		if bar.stateShown then
			bar.state:SetText("")
			bar.stateShown = false
			PlaceTargetText(bar)
		end
	end

	ns.UpdateResource()
end

--------------------------------------------------------------------------------
-- Target power
--
-- Its own bar under the target's health bar since TICK-0126, as tall as
-- your power bar. Whether the target has a power at all is often hidden,
-- so it is never asked: the fill takes the numbers by passthrough, and a
-- maximum of 0 draws no fill. A plain 0 empties the bar outright. The bar
-- stays, as yours does at 0 rage, so the target's cast keeps its place.
--------------------------------------------------------------------------------

function ns.UpdateTargetPower()
	local bar = GetBar("targetpower")

	local ptype, token = UnitPowerType("target")
	ptype, token = Plain(ptype) or 0, Plain(token) or "MANA"
	bar.ptype = ptype

	if not (TargetPowerWanted() and UnitExists("target")) then
		bar.powerShown = false
		bar:Hide()
		UpdateTargetPowerNumbers()
		return
	end

	local most = UnitPowerMax("target", ptype)
	if not IsSecret(most) and (most or 0) <= 0 then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		bar.powerShown = false
	else
		Fill(bar, UnitPower("target", ptype), most)
		bar.powerShown = true
	end
	-- No number while the target casts, or while its health bar shows a
	-- word (Dead, Ghost, Offline: TICK-0102).
	UpdateTargetPowerNumbers()

	local color = PowerColorFor(token)
	if bar.shownColor ~= color then
		bar.shownColor = color
		bar:SetStatusBarColor(unpack(color))
	end
	bar:Show()
end

--------------------------------------------------------------------------------
-- Target text
--
-- Forever gives players a first and a last name. UnitFullName hands the
-- surname back in the slot Retail uses for the realm: "Offroad", "Hunt".
--
-- Any piece can come back secret when the game hides the unit's identity.
-- Plain pieces get joined and tested. A secret one is passed straight to
-- SetText on its own, or dropped, and never read.
--------------------------------------------------------------------------------

-- "Level %s" -> "Level". Line 2 of an NPC tooltip is its title, unless the
-- NPC has none and the level line moves up.
local LEVEL_PREFIX = ((TOOLTIP_UNIT_LEVEL or "Level %s"):match("^(.-)%s*%%") or "Level") -- locale: skip the game's tooltip text

local function NpcTitle()
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetUnit, "target")
	if not ok or not data or not data.lines then return nil end

	local line = data.lines[2]
	local text = line and Plain(line.leftText)
	if not text or text == "" then return nil end
	if LEVEL_PREFIX ~= "" and text:sub(1, #LEVEL_PREFIX) == LEVEL_PREFIX then return nil end
	return text
end

local function PlayerInfo()
	local guild = Plain(GetGuildInfo("target"))
	local className, classFile = UnitClass("target")
	className, classFile = Plain(className), Plain(classFile)

	local parts = {}
	if guild and guild ~= "" then parts[#parts + 1] = "<" .. guild .. ">" end
	if className then
		local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
		parts[#parts + 1] = (c and c.colorStr) and ("|c" .. c.colorStr .. className .. "|r") or className
	end
	return table.concat(parts, " ")
end

-- The creature type "Not specified" in the client's language: type ID 10
-- (TICK-0024). enUS when the client will not say. A secret name is
-- not kept: the next call asks again.
local notSpecified
local function NotSpecified()
	if notSpecified then return notSpecified end
	local info = C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo
	local ok, data = false, nil
	if info then ok, data = pcall(info, 10) end
	local name = ok and type(data) == "table" and Plain(data.name) or nil
	if type(name) == "string" and name ~= "" then notSpecified = name end
	return notSpecified or "Not specified" -- locale: skip the game's name
end

--------------------------------------------------------------------------------
-- Marks: the rank after the target's level, and a PvP mark (TICK-0097)
--
-- Each value is asked in a pcall and passed through Plain(). The 12.x API
-- docs flag UnitIsPVP secret when the unit's identity is restricted; the
-- others have no flag, but a missing flag is no promise. A secret, a throw
-- or a missing API draws no mark. Only plain values are compared.
--------------------------------------------------------------------------------

local SILVER = { 0.75, 0.80, 0.95 }
local GOLD   = { 1.00, 0.82, 0.00 }
local RED    = { 1.00, 0.30, 0.30 }

-- The target's rank as its text and color, or nil: a normal, trivial or
-- minus mob, a player, or a value the game keeps secret. A boss is one by
-- UnitIsBossMob (dungeon bosses) or by "worldboss".
function ns.TargetRank()
	local c = Ask(UnitClassification, "target")
	if Ask(UnitIsBossMob, "target") == true or c == "worldboss" then return Text("bars.rank.boss"), RED end
	if c == "rareelite" then return Text("bars.rank.rareelite"), SILVER end
	if c == "elite" then return Text("bars.rank.elite"), GOLD end
	if c == "rare" then return Text("bars.rank.rare"), SILVER end
	return nil
end

-- The game's own small PvP marks on Forever (its UnitFramePvPIndicatorStyle).
local PVP_ATLAS = {
	Horde    = "UI-HUD-UnitFrame-SmallCircle-Horde", -- locale: skip the game's atlas name
	Alliance = "UI-HUD-UnitFrame-SmallCircle-Alliance", -- locale: skip the game's atlas name
}
local FFA_ATLAS = "UI-HUD-UnitFrame-Player-PVP-FFAIcon" -- locale: skip the game's atlas name

-- The atlas of the unit's PvP mark, or nil: not flagged, no faction
-- (Neutral), or not known. Free-for-all first, as the game's frame does.
function ns.PvPAtlas(unit)
	if Ask(UnitIsPVPFreeForAll, unit) == true then return FFA_ATLAS end
	if Ask(UnitIsPVP, unit) ~= true then return nil end
	local faction = Ask(UnitFactionGroup, unit)
	return type(faction) == "string" and PVP_ATLAS[faction] or nil
end

-- A mark a little smaller than the bar is tall, 8 to 18 pixels.
local function MarkSize(bar)
	local h = bar:GetHeight()
	if type(h) ~= "number" or h <= 0 then h = 30 end
	return math.max(8, math.min(18, math.floor(h * 0.6 + 0.5)))
end

-- False only when the client says it has no such atlas. SetAtlas fails
-- silently on an unknown name, and the level would move right of an empty
-- gap. With no C_Texture.GetAtlasInfo, trust SetAtlas.
local function HasAtlas(name)
	local api = C_Texture and C_Texture.GetAtlasInfo
	if type(api) ~= "function" then return true end
	local ok, info = pcall(api, name)
	return ok and info ~= nil
end

local function ShowPvP(bar, atlas)
	local tex = bar.pvp
	if atlas and tex.atlas ~= atlas then
		-- An atlas the client lacks shows nothing, not a green box.
		tex.atlas = HasAtlas(atlas) and pcall(tex.SetAtlas, tex, atlas) and atlas or nil
		atlas = tex.atlas
	end
	if atlas then
		local size = MarkSize(bar)
		tex:SetSize(size, size)
		tex:Show()
	else
		tex:Hide()
	end
	bar.pvpShown = atlas ~= nil
end

function ns.UpdatePlayerMarks()
	local db = HUDiniDB
	ShowPvP(GetBar("health"), db and db.showPvPMark and ns.PvPAtlas("player") or nil)
end

-- With no target both marks go, so a sample (test mode) shows none.
local function UpdateTargetMarks(bar)
	local db = HUDiniDB
	local there = db and UnitExists("target")
	local text, color
	if there and db.showRankMark then text, color = ns.TargetRank() end
	if text then
		bar.rank:SetText(text)
		bar.rank:SetTextColor(color[1], color[2], color[3])
	else
		bar.rank:SetText("")
	end
	bar.rankShown = text ~= nil

	local atlas
	if there and db.showPvPMark and Ask(UnitIsPlayer, "target") == true then
		atlas = ns.PvPAtlas("target")
	end
	ShowPvP(bar, atlas)
	PlaceTargetText(bar)
end

-- The target's level in the game's difficulty color (TICK-0101): grey (no
-- XP), green, yellow, orange, red. The game's own target frame does the
-- same, and only for a target you can attack (Blizzard_UnitFrame
-- TargetFrame.lua: C_PlayerInfo.GetContentDifficultyCreatureForPlayer, then
-- GetDifficultyColor). Gold for anyone else, for a battle pet (as the game's
-- frame does), for a boss's "??", with the switch off, and for any answer
-- that is secret, missing or throws. The game's yellow (Fair) is this gold.
local function LevelColor(level)
	local db = HUDiniDB
	if not (db and db.colorTargetLevel) then return GOLD end
	local plain = Plain(level)
	if type(plain) ~= "number" or plain <= 0 then return GOLD end
	if not Ask(UnitCanAttack, "player", "target") then return GOLD end
	if Ask(_G.UnitIsWildBattlePet, "target") or Ask(_G.UnitIsBattlePetCompanion, "target") then
		return GOLD
	end
	local info = _G.C_PlayerInfo
	local difficulty = Ask(info and info.GetContentDifficultyCreatureForPlayer, "target")
	if difficulty == nil then return GOLD end
	local ok, color = pcall(_G.GetDifficultyColor, difficulty)
	if not ok or type(color) ~= "table" or IsSecret(color) then return GOLD end
	local r, g, b = Plain(color.r), Plain(color.g), Plain(color.b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return GOLD end
	return { r, g, b }
end

-- The level the game's own target frame shows: the effective level, which a
-- zone that scales levels or party sync can raise or lower (TICK-0111;
-- Blizzard_UnitFrame Mainline TargetFrame.lua CheckLevel, which Forever
-- loads). UnitLevel when the effective level is secret, missing or throws.
local function TargetLevel()
	local level = Ask(_G.UnitEffectiveLevel, "target")
	if type(level) == "number" then return level end
	return UnitLevel("target")
end

function ns.UpdateTargetText()
	local bar = GetBar("targethealth")
	UpdateTargetMarks(bar)
	if not UnitExists("target") then return end

	local isPlayer = Plain(UnitIsPlayer("target"))

	local first, last
	if isPlayer then
		first, last = UnitFullName("target")
	else
		first = UnitName("target")
	end

	if IsSecret(first) or IsSecret(last) then
		pcall(bar.name.SetText, bar.name, first)
	elseif last and last ~= "" then
		bar.name:SetText(first .. " " .. last)
	else
		bar.name:SetText(first or "")
	end

	-- A boss's level is -1, which the game draws as a skull: "??" here.
	local level = TargetLevel()
	local color = LevelColor(level)
	if Plain(level) == -1 then level = "??" end
	pcall(bar.level.SetText, bar.level, level)
	bar.level:SetTextColor(color[1], color[2], color[3])

	if isPlayer then
		local info = PlayerInfo()
		bar.info:SetText(info)
		PlaceTargetText(bar)
		return
	end

	-- Title for anyone who has one. Creature type (Undead, Beast...) only for
	-- things you can attack; on a friendly NPC it is almost always Humanoid.
	local parts = {}
	local title = NpcTitle()
	if title then parts[#parts + 1] = "<" .. title .. ">" end
	if Plain(UnitCanAttack("player", "target")) then
		-- "Not specified" tells you nothing, so it shows nothing: the
		-- client's name for it, and the enUS one too.
		local kind = Plain(UnitCreatureType("target"))
		if kind and kind ~= "" and kind ~= NotSpecified() and kind ~= "Not specified" then parts[#parts + 1] = kind end -- locale: skip the game's name
	end
	bar.info:SetText(table.concat(parts, "  "))
	PlaceTargetText(bar)
end

function ns.UpdateCastBars()
	local db = HUDiniDB

	if PlayerCastWanted() then
		RefreshCast(casts.playercast)
	else
		SetCastShown(casts.playercast, false)
	end

	if db.showTargetCast and UnitExists("target") then
		RefreshCast(casts.targetcast)
	else
		SetCastShown(casts.targetcast, false)
	end
end

function ns.RefreshBars()
	ns.ApplyTexture()
	ns.ApplyFont()
	ns.UpdateBarVisibility()
	ns.UpdateBars()
	ns.OnPlayerHealth()
	ns.UpdatePlayerMarks()
	ns.UpdateTargetText()
	ns.UpdateCastBars()
end

-- locale: skip a debug report (/hud debug aura), in English
-- Ask the game straight out whether the aura exists on you and how many
-- stacks it has. Legal out of combat, where auras are not secret yet.
function ns.ProbeAura(out)
	local resource = Resource()
	if not resource then
		out("  HUDini knows no resource buff for your class (" .. tostring(ns.ClassToken()) .. ").")
		out("  Pick one on the Your class page of the options.")
		return
	end
	if resource.power then
		out("  Resource: " .. resource.power .. ". It comes from your power, so there is no buff to check.")
		return
	end
	out("  Resource buff: " .. resource.aura .. ", " .. (resource.max or 5) .. " pips")

	if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
		out("  C_UnitAuras.GetAuraDataBySpellName is missing on this client")
		return
	end

	local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", resource.aura, "HELPFUL")
	if not ok then
		out("  The check failed, so the buff is secret right now.")
		return
	end
	if not data then
		out("  |cffff3333That buff is not on you right now.|r")
		out("  Build a few stacks out of combat, then run this again.")
		return
	end

	local apps = Plain(data.applications)
	out("  |cff33ff33The buff is on you.|r Stacks: " .. (apps and tostring(apps) or "secret"))
end

function ns.ReportBars(out)
	local function Mark(v) return v and "|cff33ff33yes|r" or "|cffff3333no|r" end
	out("  UnitCastingDuration                   " .. Mark(UnitCastingDuration ~= nil))
	out("  StatusBar:SetTimerDuration            " .. Mark(casts.playercast.base.SetTimerDuration ~= nil))
	out("  Region:SetAlphaFromBoolean            " .. Mark(casts.targetcast.hot.SetAlphaFromBoolean ~= nil))
	out("  StatusBar ease-out (damage trail)     " .. Mark(TRAIL_EASE ~= nil))
	out("  Heal prediction calculator            " .. Mark(_G.CreateUnitHealPredictionCalculator ~= nil))
	local resource = Resource()
	local label = "none for this class"
	if resource then
		label = (resource.aura or resource.power) .. " max " .. ResourcePips(resource)
	end
	local _, token = DisplayPower()
	out("  Power shown                           " .. tostring(token))
	out("  Resource                              " .. label)
end
-- locale: end

-- Write the whole diagnosis into SavedVariables. A /reload flushes it to
-- HUDini.lua on disk, where it can be read without a screenshot.
function ns.SaveReport()
	local lines = {}

	local function out(text)
		text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		lines[#lines + 1] = text
	end

	ns.ReportAura(out, out)
	ns.ReportBars(out)

	HUDiniDB.lastReport   = lines
	HUDiniDB.lastReportAt = date("%Y-%m-%d %H:%M:%S")
	return #lines
end

-- Everything known about the resource bar, in one place. /hud debug aura.
-- title prints the title line (ns.Say in chat), out the lines under it.
function ns.ReportAura(out, title)
	title(Text("debug.resourceTitle"))
	out("  Live aura check:") -- locale: skip a debug line
	ns.ProbeAura(out)
end

--------------------------------------------------------------------------------
-- Build the cast bar sets once
--------------------------------------------------------------------------------

CreateCastSet("playercast", "player", false, false) -- plain, fills left to right
casts.playercast.holder:SetScript("OnUpdate", function() CastTick(casts.playercast) end)
CreateCastSet("targetcast", "target", true,  true)  -- two tone, fills right to left
-- The target's time left too (TICK-0126). It never flashes: only your own
-- cast events start Failed or Interrupted.
casts.targetcast.holder:SetScript("OnUpdate", function() CastTick(casts.targetcast) end)

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function Listen(event, ...)
	local n = select("#", ...)
	if n > 0 then
		pcall(events.RegisterUnitEvent, events, event, ...)
	else
		pcall(events.RegisterEvent, events, event)
	end
end

local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTIBLE",
	"UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, unit, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		Listen("UNIT_HEALTH", "player", "target")
		Listen("UNIT_MAXHEALTH", "player", "target")
		Listen("UNIT_POWER_UPDATE", "player", "target")
		Listen("UNIT_POWER_FREQUENT", "player")
		Listen("UNIT_MAXPOWER", "player", "target")
		Listen("UNIT_DISPLAYPOWER", "player", "target")
		for _, e in ipairs(CAST_EVENTS) do Listen(e, "player", "target") end
		Listen("PLAYER_TARGET_CHANGED")
		Listen("PLAYER_REGEN_ENABLED")
		Listen("UNIT_NAME_UPDATE", "target")
		-- Your level too: it changes the target level's color (TICK-0101).
		Listen("UNIT_LEVEL", "player", "target")
		Listen("UNIT_CLASSIFICATION_CHANGED", "target")
		-- A PvP flag going on or off (TICK-0097).
		Listen("UNIT_FACTION", "player", "target")
		Listen("PLAYER_FLAGS_CHANGED", "player", "target")
		-- Dead, Ghost and Offline (TICK-0106): releasing and coming back
		-- change no health, and a player going offline changes nothing else.
		-- A hunter who stands up from Feign Death changes only the flags.
		Listen("PLAYER_DEAD")
		Listen("PLAYER_ALIVE")
		Listen("PLAYER_UNGHOST")
		Listen("UNIT_CONNECTION", "target")
		Listen("UNIT_FLAGS", "target")
		ns.RefreshBars()
		return
	end

	if (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and unit == "player" then
		ns.OnPlayerHealth()
	end

	-- A form change swaps the power, and can bring the resource bar in or out.
	if (event == "UNIT_DISPLAYPOWER" or event == "UNIT_MAXPOWER") and unit == "player" then
		HUDini:Layout()
		ns.UpdateBars()
		return
	end

	if event == "PLAYER_TARGET_CHANGED" then
		-- A cast already in flight fires no event for us, so probe it.
		HUDini:Layout()
		ns.UpdateBars()
		ns.UpdateTargetText()
		ns.UpdateCastBars()
		return
	end

	if event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
		ns.UpdateTargetText()
		return
	end

	if event == "UNIT_FACTION" or event == "PLAYER_FLAGS_CHANGED" then
		-- Attackable or not also changes the level's color (TICK-0101): your
		-- own faction too (a duel, a mind control).
		if unit == "player" then
			ns.UpdatePlayerMarks()
		end
		if (unit == "player" or unit == "target") and UnitExists("target") then
			ns.UpdateTargetText()
		end
		return
	end

	if event:find("^UNIT_SPELLCAST") then
		if unit == "player" then
			if PlayerCastWanted() then
				-- The event's first value after the unit is its cast ID.
				if FLASH_WORD[event] and CastNotFinished(casts.playercast, event, (...)) then return end
				-- After the unit: castGUID, spellID, interruptedBy.
				if event == "UNIT_SPELLCAST_CHANNEL_STOP"
					and ChannelCut(casts.playercast, (select(3, ...))) then return end
				RefreshCast(casts.playercast)
			else
				SetCastShown(casts.playercast, false)
			end
		elseif unit == "target" then
			-- Off means off: no bar, and no interrupt alert from it
			-- (ns.OnTargetCast), as ns.UpdateCastBars does.
			if HUDiniDB.showTargetCast then
				RefreshCast(casts.targetcast)
			else
				SetCastShown(casts.targetcast, false)
			end
		end
		return
	end

	ns.UpdateBars()
end)
