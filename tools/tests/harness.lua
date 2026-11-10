--[[--------------------------------------------------------------------------
	HUDini test harness (TICK-0013)

	Lua 5.1 tests for logic with no screen: defaults, migrations, slash
	commands, which hooks go in and when. tools/check.py runs every
	tools/tests/test_*.lua in a fresh Lua 5.1 state, with this file loaded
	first as the global H.

	A test makes a world, loads real addon files into it, and pokes it:

		H.test("what it proves", function()
			local w = H.world()
			w:load("Modules.lua", "Mover.lua")
			w:fire("PLAYER_LOGIN")
			H.eq(w.env.HUDiniDB, nil)
		end)

	A world is one game client with one addon namespace. Its env holds the
	addon's globals (HUDiniDB, SLASH_*), the WoW stubs below, and the part of
	plain Lua that WoW has (WOW_LUA: no io, require, dofile, debug...). Any
	other global reads as nil, as it does in the game, so a file that needs a
	new API fails here until the stub is added.

	Names that do not exist fail too. A fake frame answers only the widget
	methods in FrameMethods and WIDGET_API; the Settings fakes answer only
	FAKE_API. Any other method reads as nil, so a misspelled call throws, as
	it does in the game. Add a name to those lists only after checking it in
	the 12.x API. FORBIDDEN names (environment.md: they taint) throw on sight.

	Combat lockdown (TICK-0052). In a fight (w.combat = true), a call that
	shows, hides, moves, drags, sizes, scales, layers or reparents a
	protected frame, sets its attributes or its mouse, or registers a state or
	attribute driver on any frame, is blocked as in the game
	(ADDON_ACTION_BLOCKED): it does nothing and goes in w.blocked. A frame is protected when it is made with
	{ protected = true } or from a Secure* template. A test that ends with
	anything in w.blocked fails. A test that means to provoke one reads and
	clears the log with w:takeBlocked().

	Secret values (TICK-0110). The game's secrets throw when compared,
	joined or used as a table key; ns.Plain() and ns.IsSecret() stop them.
	A stub cannot make a plain Lua value throw like that (no metamethod
	catches ==, a truth test or a table key), so write a secret test this way:
	  1. Set env.issecretvalue before w:loadAddon() (Util.lua reads it at
	     load). Make it flag the values the test names, for example
	     function(v) return v ~= nil and w.secret[v] == true end.
	  2. Run the code once with the value that WOULD match, draw or light
	     ("Magic", true, -1, a color channel), plain: assert what it does.
	  3. Flag that same value secret and run it again: assert it does not.
	Do not stand for a secret with "SECRET" or another value that fails the
	compare on its own: the test then passes with the guard taken out. Two
	values that are equal are one value to the stub: give each one you flag
	its own value (color channels 0.95, 0.96, 0.97, not 1, 1, 1). Check a new
	guard by taking it out in a scratch copy: a test must fail.

	Stubs are fakes, not the game. They prove logic, never what a player
	sees: that needs a test in the game.
----------------------------------------------------------------------------]]

H = { results = {} }

local ROOT = assert(H_ROOT, "H_ROOT is not set")

--------------------------------------------------------------------------------
-- Tests and asserts
--------------------------------------------------------------------------------

local function show(v)
	if type(v) == "string" then return ("%q"):format(v) end
	return tostring(v)
end

-- The worlds the running test made, to check their blocked-action logs.
local worlds

-- Run a test body. False and the error when it fails, or when a world it
-- made still has a blocked action in its log.
function H.run(fn)
	local outer = worlds
	worlds = {}
	-- The trace names the addon line that failed, not only the assert.
	local ok, err = xpcall(fn, function(e)
		local trace = debug.traceback(tostring(e), 2)
		return (trace:gsub("\n[^\n]*tools/tests/harness%.lua[^\n]*", ""))
	end)
	if ok then
		for _, w in ipairs(worlds) do
			if w.blocked[1] then
				ok, err = false, ("blocked in combat: %s (%d in all; w:takeBlocked() reads them)")
					:format(w.blocked[1], #w.blocked)
				break
			end
		end
	end
	worlds = outer
	return ok, err
end

function H.test(name, fn)
	local ok, err = H.run(fn)
	H.results[#H.results + 1] = { name = name, ok = ok, err = (not ok) and tostring(err) or nil }
end

function H.ok(cond, msg)
	if not cond then error(msg or "expected true", 2) end
end

function H.eq(got, want, msg)
	if got ~= want then
		error(("%sgot %s, want %s"):format(msg and (msg .. ": ") or "", show(got), show(want)), 2)
	end
end

-- The first place two values differ, as a path ("classes.MAGE.x"), or nil
-- when they are the same all the way down.
function H.diff(a, b, path)
	path = path or "value"
	if type(a) ~= "table" or type(b) ~= "table" then
		if a ~= b then return ("%s: %s vs %s"):format(path, show(a), show(b)) end
		return nil
	end
	for k, v in pairs(a) do
		local d = H.diff(v, b[k], path .. "." .. tostring(k))
		if d then return d end
	end
	for k, v in pairs(b) do
		if a[k] == nil then return H.diff(nil, v, path .. "." .. tostring(k)) end
	end
	return nil
end

function H.copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = H.copy(x) end
	return c
end

-- True if any line printed in the world contains the plain text.
function H.printed(w, text)
	for _, line in ipairs(w.printed) do
		if line:find(text, 1, true) then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- Fake frames
--------------------------------------------------------------------------------

-- Methods a fake frame really answers. WIDGET_API (below) lists the other
-- methods it takes as no-ops; any name in neither list reads as nil.
local FrameMethods = {}

function FrameMethods:SetScript(what, fn) self.__h.scripts[what] = fn end
function FrameMethods:GetScript(what) return self.__h.scripts[what] end
function FrameMethods:HasScript() return true end
function FrameMethods:HookScript(what, fn)
	self.__h.hooks[what] = self.__h.hooks[what] or {}
	table.insert(self.__h.hooks[what], fn)
	self.__h.world.log.hookScript = self.__h.world.log.hookScript + 1
end
-- As in the game: RegisterEvent takes the event for every unit, and
-- RegisterUnitEvent only for the units it names. World:fire reads the
-- event's first argument as its unit.
function FrameMethods:RegisterEvent(e)
	if self.__h.world.badEvents[e] then error("unknown event " .. e) end
	self.__h.events[e] = true
	self.__h.units[e] = nil
end
function FrameMethods:RegisterUnitEvent(e, ...)
	self.__h.events[e] = true
	local units = {}
	for i = 1, select("#", ...) do units[select(i, ...)] = true end
	self.__h.units[e] = next(units) and units or nil
end
function FrameMethods:UnregisterEvent(e) self.__h.events[e] = nil; self.__h.units[e] = nil end
function FrameMethods:UnregisterAllEvents() self.__h.events = {}; self.__h.units = {} end
function FrameMethods:IsEventRegistered(e) return self.__h.events[e] == true end
function FrameMethods:Show() self.__h.shown = true end
function FrameMethods:Hide() self.__h.shown = false end
function FrameMethods:SetShown(v) self.__h.shown = v and true or false end
function FrameMethods:IsShown() return self.__h.shown end
function FrameMethods:IsVisible() return self.__h.shown end
function FrameMethods:SetAlpha(a) self.__h.alpha = a end
function FrameMethods:GetAlpha() return self.__h.alpha end
-- TICK-0104: a frame that ignores its parent's alpha shows at its own.
function FrameMethods:SetIgnoreParentAlpha(v) self.__h.ignoreParentAlpha = v and true or false end
function FrameMethods:IsIgnoringParentAlpha() return self.__h.ignoreParentAlpha == true end
function FrameMethods:SetScale(s) self.__h.scale = s end
function FrameMethods:GetScale() return self.__h.scale end
function FrameMethods:GetEffectiveScale() return self.__h.scale end
function FrameMethods:GetName() return self.__h.name end
function FrameMethods:GetParent() return self.__h.parent end
function FrameMethods:SetParent(p) self.__h.parent = p end
function FrameMethods:GetChildren() return unpack(self.__h.children) end
function FrameMethods:IsProtected() return self.__h.protected end
function FrameMethods:IsForbidden() return false end
-- The mouse has two halves: clicks (h.mouse) and motion, for tooltips
-- (h.motion; nil = the same as clicks). EnableMouse sets both.
local function Motion(h) if h.motion == nil then return h.mouse end return h.motion end
function FrameMethods:IsMouseEnabled() return self.__h.mouse or Motion(self.__h) end
function FrameMethods:EnableMouse(v) self.__h.mouse, self.__h.motion = v and true or false, nil end
function FrameMethods:IsMouseClickEnabled() return self.__h.mouse end
function FrameMethods:IsMouseMotionEnabled() return Motion(self.__h) end
function FrameMethods:SetMouseClickEnabled(v)
	self.__h.motion = Motion(self.__h)
	self.__h.mouse = v and true or false
end
function FrameMethods:SetMouseMotionEnabled(v) self.__h.motion = v and true or false end
function FrameMethods:IsMovable() return self.__h.movable end
function FrameMethods:SetMovable(v) self.__h.movable = v and true or false end
-- The game flags a frame it starts moving as user placed
-- (warcraft.wiki.gg, API Frame StartMoving).
function FrameMethods:StartMoving() self.__h.moving, self.__h.userPlaced = true, true end
-- A drag leaves the frame where the mouse let go: one point, "CURSOR".
function FrameMethods:StopMovingOrSizing()
	if self.__h.moving then self.__h.points = { { "CURSOR" } } end
	self.__h.moving = false
end
-- Drag and backdrop (TICK-0079): kept, so a test can read what was asked.
function FrameMethods:SetClampedToScreen(v) self.__h.clamped = v and true or false end
function FrameMethods:IsClampedToScreen() return self.__h.clamped == true end
function FrameMethods:RegisterForDrag(...) self.__h.drag = { ... } end
function FrameMethods:SetUserPlaced(v) self.__h.userPlaced = v and true or false end
function FrameMethods:IsUserPlaced() return self.__h.userPlaced == true end
function FrameMethods:SetBackdrop(t) self.__h.backdrop = t end
function FrameMethods:SetBackdropColor(r, g, b, a) self.__h.backdropColor = { r, g, b, a or 1 } end
function FrameMethods:GetBackdropColor()
	local c = self.__h.backdropColor
	if c then return unpack(c) end
end
function FrameMethods:ClearAllPoints() self.__h.points = {} end
function FrameMethods:SetPoint(...) table.insert(self.__h.points, { ... }) end
function FrameMethods:SetAllPoints(to) self.__h.points = { { "ALL", to } } end
function FrameMethods:GetNumPoints() return #self.__h.points end
function FrameMethods:GetPoint(i) return unpack(self.__h.points[i or 1] or {}) end
function FrameMethods:GetWidth() return self.__h.width end
function FrameMethods:GetHeight() return self.__h.height end
function FrameMethods:SetWidth(v) self.__h.width = v end
function FrameMethods:SetHeight(v) self.__h.height = v end
function FrameMethods:SetSize(w, h) self.__h.width, self.__h.height = w, h or w end
function FrameMethods:GetSize() return self.__h.width, self.__h.height end
function FrameMethods:GetFrameLevel() return self.__h.level end
function FrameMethods:SetFrameLevel(v) self.__h.level = v end
function FrameMethods:GetFrameStrata() return self.__h.strata end
function FrameMethods:SetFrameStrata(v) self.__h.strata = v end
-- Texture atlas (TICK-0097): kept, so a test can read which mark is drawn.
function FrameMethods:SetAtlas(name) self.__h.atlas = name end
function FrameMethods:GetAtlas() return self.__h.atlas end
function FrameMethods:GetText() return self.__h.text end
function FrameMethods:SetText(v) self.__h.text = v end
function FrameMethods:SetFormattedText(f, ...) self.__h.text = f:format(...) end
-- One line of 12 px for any text: enough to stack text, never a real size.
function FrameMethods:GetStringHeight() return self.__h.text and 12 or 0 end
function FrameMethods:GetAttribute(k) return self.__h.attributes[k] end
function FrameMethods:SetAttribute(k, v) self.__h.attributes[k] = v end
function FrameMethods:GetMinMaxValues() return self.__h.min, self.__h.max end
function FrameMethods:SetMinMaxValues(a, b) self.__h.min, self.__h.max = a, b end
function FrameMethods:GetValue() return self.__h.value end
function FrameMethods:SetValue(v) self.__h.value = v end
-- CheckButton: the dot of a radio row (Setup.lua).
function FrameMethods:SetChecked(v) self.__h.checked = v and true or false end
function FrameMethods:GetChecked() return self.__h.checked == true end
-- A button or check box that takes no click (Setup.lua's gray boxes). A
-- fake starts enabled. The fake does not stop a script a test runs.
function FrameMethods:SetEnabled(v) self.__h.disabled = not v end
function FrameMethods:IsEnabled() return not self.__h.disabled end
-- A font string's font, by name ("GameFontDisable" is gray).
function FrameMethods:SetFontObject(v) self.__h.fontObject = v end
function FrameMethods:GetFontObject() return self.__h.fontObject end
-- Keyboard (Setup.lua). SetPropagateKeyboardInput is #nocombat since
-- 10.1.5 (warcraft.wiki.gg, API Frame SetPropagateKeyboardInput): in a
-- fight it is blocked on any frame.
function FrameMethods:EnableKeyboard(v) self.__h.keyboard = v and true or false end
function FrameMethods:IsKeyboardEnabled() return self.__h.keyboard == true end
function FrameMethods:SetPropagateKeyboardInput(v)
	local h = self.__h
	if h.world.combat then
		h.world:Block(("%s:SetPropagateKeyboardInput()"):format(h.name or "a frame"))
		return
	end
	h.propagate = v and true or false
end
function FrameMethods:GetPropagateKeyboardInput() return self.__h.propagate == true end
-- The center, in the frame's own scale: nil until a test places it
-- ({ center = { x, y } }), as an unplaced frame gives nil in the game.
function FrameMethods:GetCenter()
	local c = self.__h.center
	if c then return c[1], c[2] end
end
-- GameTooltip (MinimapButton.lua): SetOwner starts a new tooltip; the
-- title is its SetText, then each AddLine goes in h.lines.
function FrameMethods:SetOwner(owner, anchor)
	self.__h.owner, self.__h.anchor, self.__h.lines, self.__h.text = owner, anchor, {}, nil
end
function FrameMethods:IsOwned(owner) return self.__h.owner == owner end
function FrameMethods:AddLine(text) table.insert(self.__h.lines, text) end

-- Combat lockdown: on a protected frame in a fight these are blocked.
local LOCKED = { "Show", "Hide", "SetShown", "ClearAllPoints", "SetPoint", "SetAllPoints",
	"SetParent", "SetScale", "SetSize", "SetWidth", "SetHeight", "SetFrameStrata", "SetFrameLevel",
	"SetAttribute", "EnableMouse", "SetMouseClickEnabled", "SetMouseMotionEnabled",
	-- Restricted on protected frames in combat since 11.1.7 (warcraft.wiki.gg,
	-- API Frame StartMoving and StopMovingOrSizing). The wiki says nothing
	-- about SetMovable, so it is not here.
	"StartMoving", "StopMovingOrSizing" }
for _, m in ipairs(LOCKED) do
	local fn = FrameMethods[m]
	FrameMethods[m] = function(self, ...)
		local h = self.__h
		if h.protected and h.world.combat then
			h.world:Block(("%s:%s()"):format(h.name or "a protected frame", m))
			return
		end
		return fn(self, ...)
	end
end

local function NoOp() end

-- Children made by a frame are fake frames too.
for _, m in ipairs({ "CreateTexture", "CreateFontString", "CreateAnimationGroup",
		"CreateAnimation", "CreateMaskTexture", "CreateLine" }) do
	FrameMethods[m] = function(self) return self.__h.world:Frame(nil, self) end
end
-- StatusBar (TICK-0120): its fill texture, one fake made on first ask and
-- the same after, so a part can anchor to it and a test can find it.
function FrameMethods:GetStatusBarTexture()
	local h = self.__h
	h.fill = h.fill or h.world:Frame(nil, self)
	return h.fill
end
-- Kept, so a test can see a frame clips its children (TICK-0120).
function FrameMethods:SetClipsChildren(v) self.__h.clips = v and true or false end
-- StatusBar: kept, so a test can see which way a bar fills (TICK-0120).
function FrameMethods:SetReverseFill(v) self.__h.reverse = v and true or false end
function FrameMethods:GetReverseFill() return self.__h.reverse == true end

-- Names environment.md forbids: they taint Blizzard's settings search.
local FORBIDDEN = { AddShownPredicate = true, SetParentInitializer = true }

local function Forbidden(k)
	if FORBIDDEN[k] then
		error(k .. " is forbidden: it taints the Settings panel and its search", 3)
	end
end

-- Real 12.x widget methods (Frame, Button, StatusBar, Texture, FontString,
-- Animation, AnimationGroup) that a fake frame takes as no-ops returning
-- nil. One list for every widget type, so it cannot catch a method called
-- on the wrong type, only a name that no widget has.
local WIDGET_API = {}
for _, k in ipairs({
	"EnableMouseWheel", "RegisterForClicks", "SetHighlightTexture",
	"SetStatusBarColor", "SetStatusBarTexture",
	"SetColorTexture", "SetDesaturated", "SetGradient", "SetTexCoord", "SetTexture", "SetVertexColor",
	"SetFont", "SetJustifyH", "SetJustifyV", "SetShadowColor", "SetShadowOffset", "SetTextColor", "SetWordWrap",
	"SetDuration", "SetFromAlpha", "SetToAlpha", "SetOrigin", "SetScaleFrom", "SetScaleTo",
	"SetSmoothing", "SetToFinalAlpha", "Play", "Stop", "IsPlaying", "GetLeft", "GetTop",
	"SetBackdropBorderColor", "SetToplevel", "LockHighlight", "UnlockHighlight",
	"SetAutoFocus", "HighlightText", "ClearFocus",
	"SetBlendMode", "SetCheckedTexture", "SetDrawBling", "SetDrawEdge", "SetDrawSwipe", "SetHideCountdownNumbers", "SetLooping",
}) do WIDGET_API[k] = NoOp end

-- Lowercase keys are fields the addon set (frame.hudiniHome): nil until set.
local FrameMeta = {
	__index = function(_, k)
		Forbidden(k)
		return FrameMethods[k] or WIDGET_API[k]
	end,
}

-- An API the tests do not look into (the Settings panel, colors, the edit
-- mode callbacks): a name in FAKE_API gives another fake, and a call
-- returns new fakes. Any other name reads as nil. Never use a fake for an
-- API whose answers the addon's logic depends on.
local FAKE_API = {}
for _, k in ipairs({
	-- Settings
	"RegisterAddOnCategory", "RegisterAddOnSetting", "RegisterProxySetting",
	"RegisterVerticalLayoutCategory", "RegisterVerticalLayoutSubcategory",
	"CreateCheckbox", "CreateDropdown", "CreateSlider", "CreateSliderOptions",
	"SetOnValueChangedCallback", "VarType", "Boolean", "Number", "String",
	-- Settings.CreateColorSwatch is left out: Options.lua checks for it,
	-- and it is not confirmed in 12.x. Without it the fallback row runs.
	-- Layouts, initializers, slider options
	"AddInitializer", "AddModifyPredicate", "AddEvaluateStateCVar", "Indent",
	"SetLabelFormatter", "Label", "Right",
	-- ColorMixin, EventRegistry
	"GenerateHexColor", "RegisterCallback",
}) do FAKE_API[k] = true end

local FakeMeta = {}
FakeMeta.__index = function(t, k)
	Forbidden(k)
	if not FAKE_API[k] then return nil end
	local v = setmetatable({}, FakeMeta)
	rawset(t, k, v)
	return v
end
-- Two returns, for calls like RegisterVerticalLayoutCategory (category, layout).
FakeMeta.__call = function() return setmetatable({}, FakeMeta), setmetatable({}, FakeMeta) end
function H.Fake() return setmetatable({}, FakeMeta) end

--------------------------------------------------------------------------------
-- A world
--------------------------------------------------------------------------------

local World = {}
World.__index = World

-- A fake frame. Named ones are globals in the world, as in the game.
function World:Frame(name, parent, opts)
	-- The fake's own data lives in f.__h, so the addon's fields never clash.
	local h = {
		world = self, name = name, parent = parent,
		scripts = {}, hooks = {}, events = {}, units = {}, points = {}, children = {}, attributes = {},
		shown = true, alpha = 1, scale = 1, level = 1, strata = "MEDIUM", width = 0, height = 0,
		mouse = false, movable = false, protected = false,
	}
	for k, v in pairs(opts or {}) do h[k] = v end
	local f = setmetatable({ __h = h }, FrameMeta)
	if name then self.env[name] = f end
	self.frames[#self.frames + 1] = f
	return f
end

-- Note a blocked action, as ADDON_ACTION_BLOCKED would.
function World:Block(what)
	self.blocked[#self.blocked + 1] = what
end

-- The blocked actions so far, and a clean log after.
function World:takeBlocked()
	local b = self.blocked
	self.blocked = {}
	return b
end

-- Run a frame's script, then its hooks, as the game does.
function World:Run(frame, what, ...)
	local fn = frame.__h.scripts[what]
	if fn then fn(frame, ...) end
	for _, hook in ipairs(frame.__h.hooks[what] or {}) do hook(frame, ...) end
end

-- Send an event to every frame that registered it. A frame made while the
-- event runs does not get it: the list is copied first.
function World:fire(event, ...)
	local frames = { unpack(self.frames) }
	for _, f in ipairs(frames) do
		local h = f.__h
		local units = h.units[event]
		local heard = not units or units[(...)]
		if h.events[event] and heard and h.scripts.OnEvent then h.scripts.OnEvent(f, event, ...) end
	end
end

-- Put an item in an inventory slot (16 = main hand): its ID, and the class
-- and subclass GetItemInfoInstant gives for it (2, 20 = a fishing pole).
-- The link carries the name. No itemID empties the slot.
function World:holdItem(slot, itemID, classID, subclassID, name)
	self.held = self.held or {}
	local held = self.held
	held[slot] = itemID and { id = itemID, class = classID, sub = subclassID, name = name or "Item" } or nil
	local s = self.env
	s.GetInventoryItemID = function(_, at) return held[at] and held[at].id end
	s.GetInventoryItemLink = function(_, at)
		local h = held[at]
		return h and ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(h.id, h.name) or nil
	end
	s.GetItemInfoInstant = function(id)
		for _, h in pairs(held) do
			if h.id == id then return h.id, "", "", "", 0, h.class, h.sub end
		end
	end
end

-- Run the C_Timer.After callbacks that are due (all of them: no clock).
function World:runTimers()
	local due = self.timers
	self.timers = {}
	for _, fn in ipairs(due) do fn() end
end

-- Fire every ticker not cancelled, once.
function World:runTickers()
	for _, t in ipairs(self.tickers) do
		if not t.cancelled then t.fn() end
	end
end

-- Type a slash command, as the chat box would.
function World:slash(line)
	local word, rest = line:match("^/(%S+)%s*(.-)$")
	word = "/" .. word:lower()
	for key, fn in pairs(self.env.SlashCmdList) do
		for i = 1, 9 do
			local cmd = self.env["SLASH_" .. key .. i]
			if not cmd then break end
			if cmd:lower() == word then return fn(rest) end
		end
	end
	error("no slash command " .. word)
end

local function ReadFile(rel)
	local fh = assert(io.open(ROOT .. "/" .. rel, "rb"))
	local src = fh:read("*a")
	fh:close()
	return src
end
H.readFile = ReadFile -- a repo file's text, by its path from the repo root

-- The .lua files the .toc lists, in load order.
function H.tocFiles()
	local files = {}
	for line in ReadFile("HUDini.toc"):gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and not line:find("^#") then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	return files
end

-- Load addon files into the world, in the order given, as the client does:
-- each file is a chunk called with (addon name, shared namespace).
function World:load(...)
	for i = 1, select("#", ...) do
		local rel = select(i, ...)
		local chunk = assert(loadstring(ReadFile(rel), "@" .. rel))
		setfenv(chunk, self.env)
		chunk("HUDini", self.ns)
	end
	return self.ns
end

-- Load every file in the .toc, then log in: ADDON_LOADED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD, as the client sends them.
function World:loadAddon()
	self:load(unpack(H.tocFiles()))
	self:fire("ADDON_LOADED", "HUDini")
	self:fire("PLAYER_LOGIN")
	self:fire("PLAYER_ENTERING_WORLD", true, false)
	return self.ns
end

--------------------------------------------------------------------------------
-- WoW API stubs
--------------------------------------------------------------------------------

-- The plain Lua 5.1 that WoW's Lua has. No io, require, dofile, loadfile,
-- load, module, package, debug or os.getenv: in the game they are nil.
-- WoW also has the bit library, which lupa does not: add a stub if needed.
local WOW_LUA = {}
for _, k in ipairs({ "assert", "collectgarbage", "error", "gcinfo", "getfenv",
		"getmetatable", "ipairs", "loadstring", "next", "pairs", "pcall", "rawequal",
		"rawget", "rawset", "select", "setfenv", "setmetatable", "tonumber",
		"tostring", "type", "unpack", "xpcall", "string", "table", "math",
		"coroutine" }) do
	WOW_LUA[k] = _G[k]
end
WOW_LUA.os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime }
-- WoW's short names for library functions.
WOW_LUA.date = os.date
for k, v in pairs({ floor = math.floor, ceil = math.ceil, abs = math.abs,
		max = math.max, min = math.min, sqrt = math.sqrt, random = math.random,
		mod = math.fmod, strlen = string.len, strrep = string.rep,
		strbyte = string.byte, strchar = string.char, strmatch = string.match,
		strrev = string.reverse, gsub = string.gsub, gmatch = string.gmatch,
		sort = table.sort, getn = table.getn }) do
	WOW_LUA[k] = v
end

local function Stubs(w)
	local s = {}

	s.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		w.printed[#w.printed + 1] = table.concat(parts, " ")
	end

	-- Lua extras the WoW client adds.
	s.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	s.strtrim = function(v) return (v:match("^%s*(.-)%s*$")) end
	s.strsplit = function(sep, v, limit)
		local out, from = {}, 1
		while true do
			if limit and #out == limit - 1 then break end
			local a, b = v:find(sep, from, true)
			if not a then break end
			out[#out + 1] = v:sub(from, a - 1)
			from = b + 1
		end
		out[#out + 1] = v:sub(from)
		return unpack(out)
	end
	s.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
	s.strlower, s.strupper, s.strfind, s.strsub, s.format =
		string.lower, string.upper, string.find, string.sub, string.format
	s.tinsert, s.tremove = table.insert, table.remove
	s.tContains = function(t, v)
		for _, x in pairs(t) do if x == v then return true end end
		return false
	end
	s.CopyTable = function(t)
		local function copy(v)
			if type(v) ~= "table" then return v end
			local c = {}
			for k, x in pairs(v) do c[k] = copy(x) end
			return c
		end
		return copy(t)
	end
	s.Mixin = function(t, ...)
		for i = 1, select("#", ...) do
			for k, v in pairs((select(i, ...))) do t[k] = v end
		end
		return t
	end

	-- Frames and hooks.
	s.CreateFrame = function(_, name, parent, template)
		local secure = type(template) == "string" and template:find("Secure") ~= nil
		return w:Frame(name, parent, secure and { protected = true } or nil)
	end
	s.hooksecurefunc = function(a, b, c)
		local tbl, name, fn = a, b, c
		if type(a) == "string" then tbl, name, fn = w.env, a, b end
		local orig = tbl[name]
		-- The game throws here too: there is nothing to hook.
		if type(orig) ~= "function" then
			error(("hooksecurefunc: %s is not a function"):format(tostring(name)), 2)
		end
		tbl[name] = function(...)
			local r = { orig(...) }
			fn(...)
			return unpack(r)
		end
		w.log.secure = w.log.secure + 1
		w.secureHooks[#w.secureHooks + 1] = { tbl = tbl, name = name, fn = fn }
	end
	-- A driver goes through SecureStateDriverManager, which is protected:
	-- in a fight, registering one is blocked for any frame.
	local function Locked(what, f)
		if not w.combat then return false end
		w:Block(("%s(%s)"):format(what, f.__h.name or "a frame"))
		return true
	end
	s.RegisterAttributeDriver = function(f, attr, v)
		if Locked("RegisterAttributeDriver", f) then return end
		if attr == "state-visibility" then f.__h.driver = v; f.__h.shown = false end
	end
	s.UnregisterAttributeDriver = function(f, attr)
		if Locked("UnregisterAttributeDriver", f) then return end
		if attr == "state-visibility" then f.__h.driver = nil end
	end
	s.InCombatLockdown = function() return w.combat end
	s.ReloadUI = function() w.log.reload = w.log.reload + 1 end
	s.issecure = function() return false end

	-- Timers: After and NewTimer wait for w:runTimers(); a ticker fires once
	-- for each w:runTickers(). A cancelled one never fires again.
	local function Handle(fn)
		local t = { fn = fn, cancelled = false }
		function t:Cancel() self.cancelled = true end
		function t:IsCancelled() return self.cancelled end
		return t
	end
	s.C_Timer = {
		After = function(_, fn) table.insert(w.timers, fn) end,
		NewTimer = function(_, fn)
			local t = Handle(fn)
			table.insert(w.timers, function() if not t.cancelled then fn() end end)
			return t
		end,
		NewTicker = function(_, fn)
			local t = Handle(fn)
			table.insert(w.tickers, t)
			return t
		end,
	}
	s.GetTime = function() return w.time end
	s.time = function() return math.floor(w.time) end

	-- The player.
	s.UnitExists = function(unit) return unit == "player" or (unit == "target" and w.hasTarget) end
	s.UnitClass = function() return w.className, w.class end
	s.UnitName = function(unit) return unit == "player" and "Tester" or nil end
	s.UnitLevel = function() return w.level end
	s.UnitIsDeadOrGhost = function() return false end
	s.UnitAffectingCombat = function() return w.combat end
	s.GetMaxPlayerLevel = function() return w.maxLevel end
	s.IsShiftKeyDown = function() return w.keys.shift end
	s.IsControlKeyDown = function() return w.keys.ctrl end
	s.IsMetaKeyDown = function() return w.keys.meta end
	s.IsAltKeyDown = function() return w.keys.alt end

	-- Units: full health, half mana, no cast, no auras.
	s.UnitHealth = function() return 100 end
	s.UnitHealthMax = function() return 100 end
	s.UnitPower = function() return 50 end
	s.UnitPowerMax = function() return 100 end
	s.UnitPowerType = function() return 0, "MANA" end
	s.UnitXP = function() return 0 end
	s.UnitXPMax = function() return 1000 end
	s.GetXPExhaustion = function() return nil end
	s.IsXPUserDisabled = function() return false end
	s.GetMaxLevelForPlayerExpansion = function() return w.maxLevel end
	s.UnitCastingInfo = NoOp
	s.UnitChannelInfo = NoOp
	s.UnitGUID = function(unit) return unit == "player" and "Player-1-0001" or nil end
	s.UnitFullName = function() return "Tester", "Realm" end
	s.GetRealmName = function() return "Realm" end
	s.UnitIsPlayer = function(unit) return unit == "player" end
	s.UnitIsDead = function() return false end
	s.UnitIsConnected = function() return true end
	s.UnitCanAttack = function() return false end
	s.UnitCanAssist = function() return true end
	s.UnitReaction = function() return 5 end
	s.UnitIsTapDenied = function() return false end
	s.UnitCreatureType = NoOp
	s.C_UnitAuras = { GetAuraDataByIndex = NoOp, GetAuraDataBySpellName = NoOp, GetPlayerAuraBySpellID = NoOp }
	s.GetWeaponEnchantInfo = NoOp
	s.CanDualWield = function() return false end

	-- Action bars: every slot empty, no key bound.
	s.GetActionInfo = NoOp
	s.GetBindingKey = NoOp
	s.GetMacroSpell = NoOp
	s.GetMacroItem = NoOp
	s.IsPlayerSpell = function() return false end
	s.SpellHasRange = function() return false end
	s.C_ActionBar = {}
	s.C_Spell = { GetSpellInfo = NoOp, GetSpellTexture = NoOp, GetSpellCooldown = NoOp, GetSpellCharges = NoOp }
	s.GetSpellTexture = NoOp
	s.GetSpellLink = NoOp

	-- Items and money.
	s.GetMoney = function() return 0 end
	s.GetItemInfo = NoOp
	s.GetItemInfoInstant = NoOp
	s.GetItemIcon = NoOp
	s.GetDetailedItemLevelInfo = NoOp
	s.GetInventoryItemLink = NoOp
	s.GetInventoryItemID = NoOp
	s.GetInventoryItemDurability = NoOp
	s.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = NoOp }
	s.C_Item = {}
	s.NUM_BAG_SLOTS = 4
	s.BreakUpLargeNumbers = function(n) return tostring(n) end
	s.GetProfessions = NoOp
	s.GetGuildInfo = NoOp

	-- Sound, fonts, colors.
	s.PlaySound = NoOp
	s.MuteSoundFile = NoOp
	s.UnmuteSoundFile = NoOp
	s.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
	s.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
	s.RAID_CLASS_COLORS = setmetatable({}, { __index = function()
		return { r = 1, g = 1, b = 1, colorStr = "ffffffff" }
	end })
	s.PowerBarColor = setmetatable({}, { __index = function() return { r = 0, g = 0, b = 1 } end })
	s.DebuffTypeColor = setmetatable({}, { __index = function() return { r = 1, g = 0, b = 1 } end })
	s.GameTooltip = w:Frame("GameTooltip", nil, { lines = {} })
	-- The minimap: round, 198 px across, its center at (1000, 600). The
	-- cursor (GetCursorPosition) is w.cursor, in screen pixels.
	s.Minimap = w:Frame("Minimap", nil, { width = 198, height = 198, center = { 1000, 600 } })
	s.GetCursorPosition = function() return w.cursor[1], w.cursor[2] end
	s.GameFontHighlight = H.Fake()
	-- EventRegistry (CallbackRegistryMixin): one callback per event and
	-- owner, called as fn(owner, ...). w.callbacks[event][owner] = fn, and
	-- EventRegistry:TriggerEvent(event, ...) calls them, as the game does.
	w.callbacks = {}
	s.EventRegistry = {
		RegisterCallback = function(_, event, fn, owner)
			w.callbacks[event] = w.callbacks[event] or {}
			w.callbacks[event][owner or fn] = fn
		end,
		UnregisterCallback = function(_, event, owner)
			if w.callbacks[event] then w.callbacks[event][owner] = nil end
		end,
		TriggerEvent = function(_, event, ...)
			for owner, fn in pairs(w.callbacks[event] or {}) do fn(owner, ...) end
		end,
	}
	-- f.__h.states[state] = the last driver string, e.g. "[combat] show; hide".
	s.RegisterStateDriver = function(f, state, v)
		if Locked("RegisterStateDriver", f) then return end
		f.__h.states = f.__h.states or {}
		f.__h.states[state] = v
	end

	-- The addon.
	s.C_AddOns = {
		GetAddOnMetadata = function(addon, field)
			if addon == "HUDini" and field == "Version" then return w.version end
		end,
		IsAddOnLoaded = function() return false end,
	}

	-- Addon code finds frames by name through _G: it is the world's env.
	s._G = w.env
	s.UIParent = w:Frame("UIParent")
	s.SlashCmdList = {}
	s.UIPanelWindows = {}
	s.UISpecialFrames = {}
	s.ShowUIPanel = NoOp
	s.Enum = { PowerType = {}, ItemClass = { Weapon = 2, Armor = 4 },
		ItemWeaponSubclass = { Fishingpole = 20 } }

	-- The options panel: built at load, never looked into here.
	s.Settings = H.Fake()
	s.SettingsPanel = w:Frame("SettingsPanel")
	for _, name in ipairs({ "CreateSettingsListSectionHeaderInitializer",
			"CreateSettingsCheckboxWithColorSwatchInitializer", "CreateSettingsButtonInitializer",
			"MinimalSliderWithSteppersMixin", "CreateColor", "CreateColorFromHexString",
			"CreateFont" }) do
		s[name] = H.Fake()
	end
	return s
end

-- A new client: no frames, no saved variables, out of combat.
function H.world()
	local w = setmetatable({
		frames = {}, timers = {}, tickers = {}, printed = {}, secureHooks = {}, blocked = {},
		log = { hookScript = 0, secure = 0, reload = 0 },
		badEvents = {},
		combat = false, hasTarget = false, time = 1000,
		level = 10, maxLevel = 60, keys = {}, cursor = { 0, 0 },
		version = "9.9.9",
		ns = {},
	}, World)
	w.class, w.className = "MAGE", "Mage"
	if worlds then worlds[#worlds + 1] = w end
	w.env = {}
	local stubs = Stubs(w)
	setmetatable(w.env, {
		__index = function(_, k)
			local v = stubs[k]
			if v ~= nil then return v end
			return WOW_LUA[k]
		end,
	})
	return w
end
