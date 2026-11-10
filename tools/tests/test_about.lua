-- The About window (TICK-0058): the version it
-- shows is the .toc version, the options button opens it, it opens in a
-- fight, the placeholder link stays hidden, and the link box is read-only.

local function AboutWorld(opts)
	opts = opts or {}
	local w = H.world()
	w.version = opts.version
	w.buttons = {}
	w.env.CreateSettingsButtonInitializer = function(name, text, click, tooltip)
		w.buttons[name] = { text = text, click = click, tooltip = tooltip }
		return H.Fake()
	end
	w:loadAddon()
	if opts.link then w.ns.LINKS.issues = opts.link end
	return w, w.ns
end

local function Parts(w)
	local f = w.env.HUDiniAbout
	local p = {}
	for _, c in ipairs(w.frames) do
		local t = c.__h.text
		if t and c.__h.parent == f then p[t] = c end
	end
	return f, p
end

local function Has(list, value)
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

H.test("the window shows the .toc version, the same one /hud version prints", function()
	local w, ns = AboutWorld({ version = "3.2.1" })
	H.eq(w.env.HUDiniAbout, nil, "nothing is made before it opens")
	ns.OpenAbout()
	local f, p = Parts(w)
	H.eq(f:IsShown(), true, "open")
	H.ok(p["Version 3.2.1"], "Version 3.2.1")
	H.ok(p["HUDini"], "the title")
	w:slash("/hud version")
	H.ok(H.printed(w, ns.TEXT[0]["about.versionLine"]:format("3.2.1")), "/hud version")
end)

H.test("a .toc with no version shows Version unknown", function()
	local w, ns = AboutWorld({})
	ns.OpenAbout()
	local _, p = Parts(w)
	H.ok(p["Version unavailable"], "Version unavailable")
end)

H.test("the About HUDini button in the options opens the window", function()
	local w = AboutWorld({ version = "1.0.0" })
	local b = w.buttons["About HUDini"]
	H.ok(b, "the button is there")
	H.eq(b.text, "About HUDini")
	H.eq(b.tooltip, "Read about HUDini, its author, credits, and available support information.")
	b.click()
	H.eq(w.env.HUDiniAbout:IsShown(), true, "open")
end)

H.test("it opens in a fight: a plain window, nothing blocked; Esc and Close close it", function()
	local w, ns = AboutWorld({ version = "1.0.0" })
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	ns.OpenAbout()
	local f, p = Parts(w)
	H.eq(f:IsProtected(), false, "not protected")
	H.eq(f:IsShown(), true, "open in the fight")
	H.ok(Has(w.env.UISpecialFrames, "HUDiniAbout"), "Esc closes it")
	w:Run(p["Close"], "OnClick")
	H.eq(f:IsShown(), false, "Close closes it")
	ns.OpenAbout()
	ns.OpenAbout()
	H.eq(#w.env.UISpecialFrames, 1, "made once")
	H.eq(f:IsShown(), true, "open again")
	H.eq(#w.blocked, 0)
end)

H.test("while the link is a placeholder its section is hidden, and the help line stands alone", function()
	local w, ns = AboutWorld({ version = "1.0.0" })
	ns.OpenAbout()
	local _, p = Parts(w)
	H.eq(p["Help and feedback"]:IsShown(), false, "no header")
	H.eq(p["Project support:"]:IsShown(), false, "no link line")
	H.eq(p["Select the address and press Ctrl+C to copy it."]:IsShown(), false, "no copy line")
	H.ok(p["Use /hud help for commands and /hud version for your version. This build has no configured support link."], "help alone")
	H.eq(p["https://<public repo>/issues"], nil, "the placeholder is never shown")
	H.ok(p["Enjoy the view."], "the last line")
	H.ok(p[ns.TEXT[0]["about.ai"]], "the AI help line")
end)

H.test("with a real link: the box holds it, typing puts it back, Ctrl+C says Copied. for 2 seconds", function()
	local link = "https://example.org/hudini/issues"
	local w, ns = AboutWorld({ version = "1.0.0", link = link })
	ns.OpenAbout()
	local _, p = Parts(w)
	local box = p[link]
	H.ok(box, "the box holds the link")
	H.eq(box:IsShown(), true, "shown")
	H.ok(p["When reporting a problem, include your HUDini version, what you expected, what happened, and any error text."], "help line")
	local copy = p["Select the address and press Ctrl+C to copy it."]
	H.eq(copy:IsShown(), true, "copy line")

	box:SetText("junk")
	w:Run(box, "OnTextChanged", true)
	H.eq(box:GetText(), link, "typed keys do nothing")

	w:Run(box, "OnKeyDown", "C")
	H.eq(copy:GetText(), "Select the address and press Ctrl+C to copy it.", "C alone copies nothing")
	w.keys.ctrl = true
	w:Run(box, "OnKeyDown", "A")
	H.eq(copy:GetText(), "Select the address and press Ctrl+C to copy it.", "Ctrl+A copies nothing")
	w:Run(box, "OnKeyDown", "C")
	w.keys.ctrl = false
	H.eq(copy:GetText(), "Copy shortcut pressed.", "Copy shortcut pressed.")
	w:runTimers()
	H.eq(copy:GetText(), "Select the address and press Ctrl+C to copy it.", "and back")

	w.keys.meta = true
	w:Run(box, "OnKeyDown", "C")
	w.keys.meta = nil
	H.eq(copy:GetText(), "Copy shortcut pressed.", "Cmd+C too")
end)

H.test("the body lines follow the flair level each time it opens", function()
	local w, ns = AboutWorld({ version = "1.0.0" })
	local level = 2
	ns.FlairLevel = function() return level end
	ns.OpenAbout()
	local f, p = Parts(w)
	H.ok(p["Do look up occasionally. We went to some trouble to clear the view."], "level 2 last line")
	H.ok(p["HUDini"], "the title has one text")
	f:Hide()
	level = 1
	ns.OpenAbout()
	_, p = Parts(w)
	H.ok(p["Now, enjoy the view."], "level 1 when opened again")
	w:slash("/hud version")
	H.ok(H.printed(w, ns.TEXT[1]["about.versionLine"]:format("1.0.0")), "/hud version at level 1")
	level = 7
	f:Hide()
	ns.OpenAbout()
	_, p = Parts(w)
	H.ok(p["Enjoy the view."], "a level not known gives level 0")
end)

H.test("the About window is solid, drags with the left button, and keeps its place until a reload", function()
	local w, ns = AboutWorld({ version = "1.0.0" })
	ns.OpenAbout()
	local f = w.env.HUDiniAbout
	H.eq(select(4, f:GetBackdropColor()), 1, "backdrop alpha")
	H.eq(f.__h.backdrop.bgFile, "Interface\\Buttons\\WHITE8X8", "a solid fill, not the see-through dialog background")
	H.eq(f.__h.backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Border", "the dialog border stays")
	H.eq(f:IsMovable(), true, "movable")
	H.eq(f:IsClampedToScreen(), true, "clamped to the screen")
	H.ok(#f.__h.drag == 1 and f.__h.drag[1] == "LeftButton", "the left button only")
	H.eq(f:GetPoint(), "CENTER", "the default place")
	H.eq(f:GetFrameStrata(), "DIALOG", "the strata is the same")
	w:Run(f, "OnDragStart")
	w:Run(f, "OnDragStop")
	H.eq(f:GetPoint(), "CURSOR", "where the mouse let go")
	H.eq(f:IsUserPlaced(), false, "the game does not save the place")
	f:Hide()
	w:Run(f, "OnHide")
	ns.OpenAbout()
	H.ok(f:IsShown(), "open again")
	H.eq(f:GetPoint(), "CURSOR", "the same place in the same session")
	w:Run(f, "OnDragStart")
	f:Hide()
	w:Run(f, "OnHide")
	H.eq(f.__h.moving, false, "a hide ends a drag")

	local w2, ns2 = AboutWorld({ version = "1.0.0" })
	ns2.OpenAbout()
	H.eq(w2.env.HUDiniAbout:GetPoint(), "CENTER", "after a reload: the default place")
end)

--------------------------------------------------------------------------------
-- The host line and the two sections (TICK-0083)
--------------------------------------------------------------------------------

-- The y offset a part is placed at: more negative is lower.
local function Y(part) return select(5, part:GetPoint()) end

-- The copy of D-029 (TICK-0134) gives the host line a text at every level, so
-- it shows first at every level. An empty text still hides it with no gap.
H.test("the host line shows first at every level; an empty one is hidden and leaves no gap", function()
	local w, ns = AboutWorld({ version = "1.0.0" })
	local T = ns.TEXT
	local level = 0
	ns.FlairLevel = function() return level end
	ns.OpenAbout()
	local f = w.env.HUDiniAbout
	local p = f.parts
	local first = -(20 + 40 + 10)
	for l = 0, 2 do
		level = l
		f:Hide()
		ns.OpenAbout()
		H.eq(p.host:GetText(), T[l]["about.host"] or T[0]["about.host"], "level " .. l .. ": its text")
		H.eq(p.host:IsShown(), true, "level " .. l .. ": shown")
		H.eq(Y(p.host), first, "level " .. l .. ": the host line is first")
		H.eq(Y(p.tagline), first - 12 - 10, "level " .. l .. ": the tagline is under it")
	end
	local saved = T[0]["about.host"]
	T[0]["about.host"] = ""
	level = 0
	f:Hide()
	ns.OpenAbout()
	T[0]["about.host"] = saved
	H.eq(p.host:IsShown(), false, "an empty text: hidden")
	H.eq(Y(p.tagline), first, "an empty text: the tagline takes the first place, no gap")
end)

H.test("at every level the shares and promises sections show with their headers, in order", function()
	local w, ns = AboutWorld({ version = "1.0.0" })
	local T = ns.TEXT
	local level = 0
	ns.FlairLevel = function() return level end
	local f
	for l = 0, 2 do
		level = l
		if f then f:Hide() end
		ns.OpenAbout()
		f = w.env.HUDiniAbout
		local p = f.parts
		H.eq(p.sharesHeader:GetText(), T[0]["about.shares.header"], "level " .. l)
		H.eq(p.shares:GetText(), T[l]["about.shares"], "level " .. l)
		H.eq(p.promisesHeader:GetText(), T[0]["about.promises.header"], "level " .. l)
		H.eq(p.promises:GetText(), T[l]["about.promises"], "level " .. l)
		local order = { p.ai, p.sharesHeader, p.shares, p.promisesHeader, p.promises, p.help }
		for i, part in ipairs(order) do
			H.eq(part:IsShown(), true, "level " .. l .. ": part " .. i .. " shown")
			if i > 1 then H.ok(Y(part) < Y(order[i - 1]), "level " .. l .. ": part " .. i .. " is under the one before") end
		end
		H.ok(Y(p.close) < Y(p.help), "Close is under the body")
		H.eq(f:GetHeight(), -Y(p.close) + 22 + 20, "the height fits the body")
	end
end)

H.test("a window too tall for the screen takes the next width until it fits", function()
	local w, ns = AboutWorld({ version = "1.0.0" })
	ns.OpenAbout()
	local f = w.env.HUDiniAbout
	local p = f.parts
	H.eq(f:GetWidth(), 400, "no screen size known: 400 px")
	-- A text that wraps: its height falls as its width grows.
	p.shares.GetStringHeight = function(self) return math.floor(48000 / self:GetWidth()) end

	w.env.UIParent:SetSize(2000, 1000)
	f:Hide()
	ns.OpenAbout()
	H.eq(f:GetWidth(), 400, "room enough: 400 px")
	-- The host line shows at level 0 (TICK-0134).
	H.eq(f:GetHeight(), 441)

	w.env.UIParent:SetSize(2000, 452)
	f:Hide()
	ns.OpenAbout()
	H.eq(f:GetWidth(), 520, "too tall at 400: the next width")
	H.eq(f:GetHeight(), 408, "and it fits in 452 - 40")
	H.eq(p.shares:GetWidth(), 480, "the text follows the width")
	H.eq(p.tagline:GetWidth(), 480)
	H.eq(p.box:GetWidth(), 474)
	H.eq(p.last:GetWidth(), 374)
	H.eq(select(4, p.close:GetPoint()), -20, "Close keeps its place at the right")

	w.env.UIParent:SetSize(600, 300)
	f:Hide()
	ns.OpenAbout()
	H.eq(f:GetWidth(), 520, "too tall at every width: the widest the screen takes")

	w.env.UIParent:SetSize(2000, 1000)
	f:Hide()
	ns.OpenAbout()
	H.eq(f:GetWidth(), 400, "back to 400 px when it fits again")
	H.eq(p.shares:GetWidth(), 360)
end)
