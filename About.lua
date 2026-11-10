--[[--------------------------------------------------------------------------
	HUDini - About

	The About window (D-013): which version
	runs, what HUDini is, who made it and how, and where to get help.
	Opened from Options > HUDini > About HUDini; /hud version says where.

	A plain window: no secure template, no protected frame, so it opens in
	a fight too. It is made the first time it opens and saves nothing. Its
	text is painted again each time it opens, at the flair level of the
	moment. Esc closes it (UISpecialFrames, or the link box while it has
	the cursor); the options stay open behind it unless Esc closes them too.
----------------------------------------------------------------------------]]

local _, ns = ...
local Text = ns.Text

-- The one place for the links (TICK-0033). While a
-- link is a placeholder (it has a "<"), its section is hidden, so a test
-- build never shows a dead link.
ns.LINKS = {
	issues = "https://<public repo>/issues", -- locale: skip a link
}

local PAD, GAP = 20, 10
-- The widths the window may take, narrow first (TICK-0083). It opens at
-- 400 px; when the text at that width is taller than the screen's room, it
-- takes the next width, until one fits or the screen's width stops it.
local WIDTHS = { 400, 520, 640, 760 }
-- Kept free above and below the window, and at each side.
local MARGIN = 20
local ICON = "Interface\\AddOns\\HUDini\\Media\\icon.tga"
local COPIED_FOR = 2

-- The texts are in Locales/enUS.lua ("about." keys), by flair level.
-- ns.Text reads the level now.
local TITLE = "HUDini"

-- The /hud version line (Core.lua).
function ns.VersionLine()
	return Text("about.versionLine", ns.VERSION)
end

local function IsPlaceholder(link)
	return type(link) ~= "string" or link == "" or link:find("<", 1, true) ~= nil
end

local frame, parts
local copiedTurn = 0

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

local function NewText(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	return fs
end

-- The link box: holds the link, selected in full on a click, read-only.
local function LinkBox(parent)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetAutoFocus(false)
	box:SetSize(WIDTHS[1] - 2 * PAD - 6, 22)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
	box:SetScript("OnTextChanged", function(self, typed)
		if typed then
			self:SetText(self.link)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		parent:Hide()
	end)
	box:SetScript("OnKeyDown", function(_, key)
		local copy = IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())
		if key ~= "C" or not copy then return end
		copiedTurn = copiedTurn + 1
		local turn = copiedTurn
		parts.copy:SetText(Text("about.copied"))
		C_Timer.After(COPIED_FOR, function()
			if copiedTurn == turn then parts.copy:SetText(Text("about.copyLine")) end
		end)
	end)
	return box
end

local function Build()
	local f = CreateFrame("Frame", "HUDiniAbout", UIParent, "BackdropTemplate")
	f:SetWidth(WIDTHS[1])
	f:SetPoint("CENTER")
	-- Above the options panel, so no part of it covers the window.
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(0, 0, 0, 1)
	Movable(f)
	f:Hide()
	tinsert(UISpecialFrames, "HUDiniAbout")

	local p = {}
	p.icon = f:CreateTexture(nil, "ARTWORK")
	p.icon:SetTexture(ICON)
	p.icon:SetSize(40, 40)
	p.icon:SetPoint("TOPLEFT", PAD, -PAD)

	p.title = NewText(f, "GameFontNormalLarge")
	p.title:SetText(TITLE)
	p.title:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 10, -2)
	p.version = NewText(f, "GameFontDisable")
	p.version:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)

	p.x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	p.x:SetPoint("TOPRIGHT", -6, -6)
	p.x:SetScript("OnClick", function() f:Hide() end)

	-- The body, top to bottom. Paint shows the parts that apply and stacks them.
	p.host     = NewText(f, "GameFontHighlight")
	p.tagline  = NewText(f, "GameFontHighlight")
	p.madeBy   = NewText(f, "GameFontHighlight")
	p.ai       = NewText(f, "GameFontHighlight")
	p.sharesHeader   = NewText(f, "GameFontNormal")
	p.shares         = NewText(f, "GameFontHighlight")
	p.promisesHeader = NewText(f, "GameFontNormal")
	p.promises       = NewText(f, "GameFontHighlight")
	p.header   = NewText(f, "GameFontNormal")
	p.linkLine = NewText(f, "GameFontHighlight")
	p.box      = LinkBox(f)
	p.copy     = NewText(f, "GameFontDisableSmall")
	p.help     = NewText(f, "GameFontHighlight")

	p.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	p.close:SetSize(96, 22)
	p.close:SetText(Text("about.close"))
	p.close:SetScript("OnClick", function() f:Hide() end)
	p.last = NewText(f, "GameFontHighlight")

	-- A "Copied." that waits is dropped when the window closes.
	f:SetScript("OnHide", function(self)
		Drop(self)
		copiedTurn = copiedTurn + 1
		p.box:ClearFocus()
	end)
	f.parts = p -- for the tests
	frame, parts = f, p
end

local TEXTS = { "host", "tagline", "madeBy", "ai", "sharesHeader", "shares", "promisesHeader",
	"promises", "header", "linkLine", "copy", "help" }

-- Stack the body under the title at this width; the height it needs.
local function Stack(body, width)
	local p = parts
	frame:SetWidth(width)
	for _, key in ipairs(TEXTS) do
		p[key]:SetWidth(width - 2 * PAD)
	end
	p.box:SetWidth(width - 2 * PAD - 6)
	p.last:SetWidth(width - 2 * PAD - 96 - 10)

	local y = PAD + 40 + GAP
	for i, part in ipairs(body) do
		part:ClearAllPoints()
		part:SetPoint("TOPLEFT", frame, "TOPLEFT", part == p.box and PAD + 6 or PAD, -y)
		local h = part == p.box and 22 or part:GetStringHeight()
		-- The link line, the box and the copy line sit close together.
		local tight = body[i + 1] == p.box or part == p.box
		y = y + h + (tight and 4 or GAP)
	end
	y = y + GAP
	p.close:ClearAllPoints()
	p.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
	p.last:ClearAllPoints()
	p.last:SetPoint("LEFT", frame, "TOPLEFT", PAD, -(y + 11))
	return y + 22 + PAD
end

-- The screen's room for the window: its height and width less the margins.
-- With no size known, there is no limit.
local function Room()
	local h, w = UIParent:GetHeight(), UIParent:GetWidth()
	h = (h and h > 0) and h - 2 * MARGIN or math.huge
	w = (w and w > 0) and w - 2 * MARGIN or math.huge
	return h, w
end

-- Fill in the texts at the flair level now, show what applies, stack the
-- body under the title and fit the height to it. An empty text (the host
-- line below level 2) is not shown and takes no room.
local function Paint()
	local p = parts
	local link = ns.LINKS.issues
	local hasLink = not IsPlaceholder(link)

	p.version:SetText(ns.VERSION ~= "unknown" and Text("about.version", ns.VERSION) or Text("about.versionUnknown"))
	p.host:SetText(Text("about.host"))
	p.tagline:SetText(Text("about.tagline"))
	p.madeBy:SetText(Text("about.madeBy"))
	p.ai:SetText(Text("about.ai"))
	p.sharesHeader:SetText(Text("about.shares.header"))
	p.shares:SetText(Text("about.shares"))
	p.promisesHeader:SetText(Text("about.promises.header"))
	p.promises:SetText(Text("about.promises"))
	p.header:SetText(Text("about.header"))
	p.linkLine:SetText(Text("about.linkLine"))
	p.box.link = hasLink and link or ""
	p.box:SetText(p.box.link)
	p.copy:SetText(Text("about.copyLine"))
	p.help:SetText(hasLink and Text("about.help") or Text("about.helpAlone"))
	p.last:SetText(Text("about.last"))

	local body = {}
	local function Add(part, show)
		part:SetShown(show)
		if show then body[#body + 1] = part end
	end
	Add(p.host, p.host:GetText() ~= "")
	for _, part in ipairs({ p.tagline, p.madeBy, p.ai, p.sharesHeader, p.shares, p.promisesHeader, p.promises }) do
		Add(part, true)
	end
	for _, part in ipairs({ p.header, p.linkLine, p.box, p.copy }) do
		Add(part, hasLink)
	end
	Add(p.help, true)

	-- The narrowest width whose height fits the screen; else the widest
	-- width the screen takes.
	local roomH, roomW = Room()
	local height
	for i, width in ipairs(WIDTHS) do
		if i > 1 and width > roomW then break end
		height = Stack(body, width)
		if height <= roomH then break end
	end
	frame:SetHeight(height)
end

-- Open the window. Opening it while it is open does nothing.
function ns.OpenAbout()
	if not frame then Build() end
	if frame:IsShown() then return end
	Paint()
	frame:Show()
end
