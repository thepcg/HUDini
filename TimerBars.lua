--[[--------------------------------------------------------------------------
	HUDini - Cooldown timer bars (TICK-0158, GitHub #2)

	A spell you turn on (the Your class page; Classes.lua ns.SetTimerBar)
	gets a bar under the HUD while its own cooldown runs: its icon on the
	left, a bar that drains, its name, and the time left as seconds or as a
	percent. The bar with the least time left is on top. The bars are part
	of the HUD: children of one holder frame, a child of HUDini.body, so
	they hide and fade with it. With no saved place they sit under the left
	end of the HUD, below the totem row when that is on, and move with it.

	Their own place (TICK-0169, D-044): while the HUD is unlocked a blue
	box covers the bars (at least two rows, so there is always something
	to grab); drag it to move them. The place is saved per class
	(ns.ClassDB().timerBarPlace, the holder's top left in screen pixels)
	and the HUD moving then leaves the bars. No drag starts in a fight.
	ns.ResetTimerBarsPlace() puts them back under the HUD, and so does
	/hud reset class. No saved place is today's place: an old save needs
	no migration.

	When a bar shows (the same reads as the ready alerts, Alerts.lua
	ns.CooldownReads, so both agree):
	  - Only SPELL_UPDATE_COOLDOWN (every watched spell) or
	    SPELL_UPDATE_CHARGES (the spells with charges) can start a bar: the
	    spell's plain isActive with isOnGCD false, or a charge coming back.
	    The game says isOnGCD is right only while it answers that event.
	    The payload is not filtered by spell ID.
	  - One look one frame later ("late", one per frame however many events
	    came) also finds starts, because a shared cooldown (Earth Shock and
	    Flame Shock) fires no event of its own. isOnGCD can be wrong there,
	    so it never ends a bar by it, and it does not start again a bar the
	    event just ended.
	  - Every other look (login, SPELLS_CHANGED, a change of options, the
	    end of a fight) only hands a shown bar its object again; the ticker
	    only ends bars. A cooldown that already runs then shows at the next
	    cooldown event (any cast).
	  - Each spell is asked by the ID the game uses now: its override (a
	    talent or form can swap one spell for another) or itself.
	  - A bar goes when the game plainly says the spell is ready (isActive
	    false, every charge back), or, in the event, when only the global
	    cooldown is left on it, or when its own Cooldown's time is up (a
	    spell with charges then gets the next charge's object).
	  - A secret or missing answer changes nothing.
	  - Known limit: in a fight a misread late start (the global cooldown
	    alone, read as the spell's own) cannot be told from a real one: the
	    zero object is secret too. It shows an empty bar until the ticker
	    sees the spell ready, about two seconds at most.

	Secret values (environment.md): in a fight the start, length and time
	left are secret. HUDini never reads them. It hands the game's duration
	object (C_Spell.GetSpellCooldownDuration with the global cooldown left
	out, or GetSpellChargeDuration) to the bar (SetTimerDuration), to the
	icon's Cooldown and to the text (a DurationTextBinding); the game draws
	from it. DK's probe (TICK-0156) showed all three take a secret object in
	a fight. Each event and each look but the ticker hand the object
	again, so a cooldown cut short or reset is right. The bar's own
	value (GetValue) is never read back: it is secret and a frame late. A
	bar is cleared with a zero duration, not by setting a value.

	Order: out of a fight, when no object holds a secret, the bars sort by
	time left. In a fight the time left cannot be compared, so the order
	stays: a bar whose spell is ready leaves, and a new bar joins at the
	end. When the fight ends each bar gets a new object (the old one stays
	secret) and the bars sort again.

	It is a module (Modules.lua): on while the class you play has at least
	one timer bar turned on. Off, it has no events and shows nothing.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local HUDini   = ns.HUDini
local Plain    = ns.Plain

local M = ns.NewModule("timerBars", {
	label = "Timer bars", -- locale: skip a debug name (/hud debug modules)
	isOn = function()
		if not HUDiniDB then return false end
		local saved = ns.ClassDB().timerBars
		return type(saved) == "table" and next(saved) ~= nil
	end,
	defaults = {
		-- The look of the bars. Cosmetic: the designer's call (TICK-0158).
		timerBarTexture = "hud",     -- a bar texture key, or "hud": the HUD's own bar texture
		timerBarTime    = "seconds", -- "seconds" (h.m.s) or "percent"
	},
})

local HEIGHT = 0.5  -- a bar's height, as a part of an icon's
local GAP    = 3    -- pixels between bars, and between the HUD and the bars
local SAMPLE = 2    -- bar rows the blue box covers at least while unlocked
local TOTEM  = 0.75 -- the totem row's size, as a part of an icon's (Totems.lua)

local INTERP = (Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate) or 0
local DRAIN  = (Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime) or 1

local watch = {}  -- { name = "Earth Shock", base = id, id = id now }, in the page's order
local bars  = {}  -- name -> its bar frame, made the first time it shows
local order = {}  -- the names with a bar showing, top to bottom
local busy  = false
local ended = {}  -- names the event just ended, which the late look leaves alone
local lateDue = false

local function Reads() return ns.CooldownReads end

--------------------------------------------------------------------------------
-- The duration object
--------------------------------------------------------------------------------

-- The game's duration object for the spell's own cooldown, or nil. A spell
-- with charges: the charge coming back. Else the cooldown with the global
-- cooldown left out (ignoreGCD), so a global cooldown alone is zero.
local function Duration(id)
	local get
	if Reads().ChargeInfo(id) then
		get = C_Spell.GetSpellChargeDuration
		if type(get) ~= "function" then return nil end
		local ok, object = pcall(get, id)
		return ok and object or nil
	end
	get = C_Spell.GetSpellCooldownDuration
	if type(get) ~= "function" then return nil end
	local ok, object = pcall(get, id, true)
	return ok and object or nil
end

-- True only when the object plainly says it is zero. A secret or missing
-- answer is not zero.
local function PlainZero(object)
	local ok, zero = pcall(function() return object:IsZero() end)
	return ok and Plain(zero) == true
end

-- A zero duration: a bar given it shows nothing (C_DurationUtil.CreateDuration
-- with no time set).
local zero
local function Zero()
	if zero == nil then
		local U = _G.C_DurationUtil
		local ok, object = false, nil
		if U and type(U.CreateDuration) == "function" then ok, object = pcall(U.CreateDuration) end
		zero = ok and object or false
	end
	return zero or nil
end

--------------------------------------------------------------------------------
-- A bar
--------------------------------------------------------------------------------

local function TexturePath()
	local key = HUDiniDB.timerBarTexture
	if key == nil or key == "hud" then return ns.BarTexturePath() end
	return ns.TexturePathFor(key)
end

-- The time text: a binding the game updates by itself. A new binding for
-- each format, so a change from seconds to percent leaves nothing behind.
local function Binding(f)
	local mode = HUDiniDB.timerBarTime == "percent" and "percent" or "seconds"
	if f.bind and f.bindMode == mode then return f.bind end
	if f.bind then pcall(f.bind.Disable, f.bind) end
	f.bind, f.bindMode = nil, nil
	f.time:SetText("")
	local U, S = _G.C_DurationUtil, _G.C_StringUtil
	if not (U and type(U.CreateDurationTextBinding) == "function" and S) then return nil end
	local ok, bind = pcall(U.CreateDurationTextBinding)
	if not ok or not bind then return nil end
	pcall(bind.SetFontString, bind, f.time)
	if mode == "percent" then
		local P = Enum.DurationTextBindingProperty
		if not (P and type(S.CreateNumericRuleFormatter) == "function") then return nil end
		local okF, fmt = pcall(S.CreateNumericRuleFormatter)
		if not okF or not fmt then return nil end
		-- Percent runs 0-100 (DK's probe, TICK-0156): whole numbers.
		pcall(fmt.SetBreakpoints, fmt, { { threshold = 0, format = "%.0f" } })
		pcall(bind.SetTextFormat, bind, "{}%", { { property = P.RemainingPercent, formatter = fmt } })
	elseif type(S.CreateSecondsFormatter) == "function" then
		local okF, fmt = pcall(S.CreateSecondsFormatter)
		if okF and fmt then pcall(bind.SetFormatter, bind, fmt) end
	end
	f.bind, f.bindMode = bind, mode
	return bind
end

local function Style(f)
	f.bar:SetStatusBarTexture(TexturePath())
	f.bar:SetStatusBarColor(unpack(ns.BarColor("timer")))
	local font = ns.BarFontPath()
	local size = math.max(8, math.floor(f:GetHeight() * 0.6 + 0.5))
	for _, fs in ipairs({ f.label, f.time }) do
		if fs:SetFont(font, size, "OUTLINE") == false then
			fs:SetFontObject("GameFontHighlightSmall")
		end
	end
end

local Look, Update -- set below

--------------------------------------------------------------------------------
-- The holder (TICK-0169): every bar is its child, and it is what moves.
--------------------------------------------------------------------------------

local holder
local moving = false  -- a drag runs: Place leaves the holder's point alone
local Place           -- set below

local function Unlocked()
	return M.enabled and HUDiniDB ~= nil and not HUDiniDB.locked
end

-- The saved place, or nil: the holder's top left, in screen pixels (so a
-- new HUD scale keeps that corner where it is).
local function Saved()
	local p = ns.ClassDB().timerBarPlace
	if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then return p end
end

local function Scale(f)
	local s = f:GetEffectiveScale()
	if type(s) ~= "number" or s <= 0 then return 1 end
	return s
end

local function DragStart()
	if not Unlocked() or InCombatLockdown() then return end
	moving = true
	holder:StartMoving()
end

local function DragStop()
	if not moving then return end
	moving = false
	holder:StopMovingOrSizing()
	-- HUDini saves the place itself; the game's layout cache must not.
	holder:SetUserPlaced(false)
	local x, y = holder:GetLeft(), holder:GetTop()
	if type(x) == "number" and type(y) == "number" then
		local s = Scale(holder)
		ns.ClassDB().timerBarPlace = { x = x * s, y = y * s }
	end
	Place()
end

local function Holder()
	if holder then return holder end
	holder = M:CreateFrame("Frame", "HUDiniTimerBars", HUDini.body)
	holder:SetSize(1, 1)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:EnableMouse(false)
	-- The blue box: a frame above the bars, so a full set of bars cannot
	-- hide it (TICK-0053). Hidden, it takes no mouse.
	local grab = M:CreateFrame("Frame", nil, holder)
	grab:SetAllPoints()
	grab:SetFrameLevel(holder:GetFrameLevel() + 50)
	grab:EnableMouse(true)
	grab:RegisterForDrag("LeftButton")
	grab:Hide()
	grab.bg = grab:CreateTexture(nil, "BACKGROUND")
	grab.bg:SetAllPoints()
	grab.bg:SetColorTexture(0, 0.6, 1, 0.15)
	grab.text = grab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	grab.text:SetPoint("CENTER")
	grab:SetScript("OnDragStart", DragStart)
	grab:SetScript("OnDragStop", DragStop)
	holder.grab = grab
	return holder
end

local function Bar(name)
	local f = bars[name]
	if f then return f end
	-- In the holder, a child of the body: only the body hides when idle.
	f = M:CreateFrame("Frame", nil, Holder())
	f:EnableMouse(false)

	f.backdrop = f:CreateTexture(nil, "BACKGROUND")
	f.backdrop:SetPoint("TOPLEFT", -1, 1)
	f.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
	f.backdrop:SetColorTexture(0, 0, 0, 0.75)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT")
	f.icon:SetPoint("BOTTOMLEFT")
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- No swipe and no numbers: the bar shows the time. It is here for its
	-- OnCooldownDone, a plain "this time is up", in a fight too.
	f.cd = M:CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f.icon)
	f.cd:SetDrawSwipe(false)
	f.cd:SetDrawEdge(false)
	if f.cd.SetDrawBling then f.cd:SetDrawBling(false) end
	f.cd:SetHideCountdownNumbers(true)
	f.cd:SetScript("OnCooldownDone", function()
		if not busy then Update("done", name) end
	end)

	f.bar = M:CreateFrame("StatusBar", nil, f)
	f.bar:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 1, 0)
	f.bar:SetPoint("BOTTOMRIGHT")
	f.bar:SetMinMaxValues(0, 1)
	f.bar:SetValue(0)

	f.label = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("LEFT", 3, 0)
	f.label:SetJustifyH("LEFT")
	f.label:SetWordWrap(false)
	f.time = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.time:SetPoint("RIGHT", -3, 0)
	f.time:SetJustifyH("RIGHT")
	f.label:SetPoint("RIGHT", f.time, "LEFT", -3, 0)

	f:Hide()
	bars[name] = f
	return f
end

-- Hand one duration object to the bar, the icon's Cooldown and the text.
local function Feed(f, object)
	if f.bar.SetTimerDuration then
		pcall(f.bar.SetTimerDuration, f.bar, object, INTERP, DRAIN)
	end
	if f.cd.SetCooldownFromDurationObject then
		pcall(f.cd.SetCooldownFromDurationObject, f.cd, object)
	end
	local bind = Binding(f)
	if bind then
		pcall(bind.SetDuration, bind, object)
		pcall(bind.Enable, bind)
	end
	f.object = object
end

local function Clear(f)
	busy = true
	local z = Zero()
	if z and f.bar.SetTimerDuration then pcall(f.bar.SetTimerDuration, f.bar, z, INTERP, DRAIN) end
	if f.cd.Clear then pcall(f.cd.Clear, f.cd) end
	if f.bind then pcall(f.bind.Disable, f.bind) end
	f.time:SetText("")
	f.object = nil
	f:Hide()
	busy = false
end

local function Showing(name)
	for i, n in ipairs(order) do
		if n == name then return i end
	end
end

local function Start(w, object)
	local f = Bar(w.name)
	local ok, icon = pcall(C_Spell.GetSpellTexture, w.id)
	if ok and icon ~= nil then pcall(f.icon.SetTexture, f.icon, icon) end
	-- The name of the spell the game uses now (an override has its own).
	local okN, label = pcall(C_Spell.GetSpellName, w.id)
	label = okN and Plain(label) or nil
	if type(label) ~= "string" or label == "" then label = w.name end
	f.label:SetText(label)
	busy = true
	Feed(f, object)
	busy = false
	f:Show()
	if not Showing(w.name) then order[#order + 1] = w.name end
end

local function Stop(name)
	local i = Showing(name)
	if i then table.remove(order, i) end
	local f = bars[name]
	if f then Clear(f) end
end

--------------------------------------------------------------------------------
-- When a bar shows
--------------------------------------------------------------------------------

-- The modes (the header says why):
--   "event"   in SPELL_UPDATE_COOLDOWN: starts and ends bars.
--   "charges" in SPELL_UPDATE_CHARGES: "event" for a spell with charges,
--             else "tick".
--   "late"    one frame after the event: starts bars, ends one only when
--             it is plainly ready.
--   "done"    the bar's own Cooldown's time is up (that bar only).
--   "refeed"  login, SPELLS_CHANGED, a change of options, the end of a
--             fight: hands a shown bar its object again.
--   "tick"    the ticker: ends a bar that is plainly ready.
function Look(w, mode)
	local R = Reads()
	local id = R.EffectiveID(w.base)
	if id ~= w.id then w.id = id end
	local shown = Showing(w.name) ~= nil
	if mode == "charges" then mode = R.ChargeInfo(id) and "event" or "tick" end

	if R.ReadyAgain(id) then return Stop(w.name) end
	if mode == "late" and ended[w.name] then return end
	if mode == "done" then
		-- The object leaves the global cooldown out, so its end is the
		-- spell's own end. A spell with charges: the next one comes back.
		if not R.ChargeInfo(id) then return Stop(w.name) end
		mode = "refeed"
	end
	if mode == "event" or mode == "late" then
		if R.CooldownStarted(id) then
			local object = Duration(id)
			-- A plain zero: the global cooldown alone (it is left out).
			if object == nil or PlainZero(object) then
				if shown then
					if mode == "event" then ended[w.name] = true end
					Stop(w.name)
				end
				return
			end
			return Start(w, object)
		end
		if mode == "event" and R.OnlyGCDLeft(id) then
			if shown then ended[w.name] = true end
			return Stop(w.name)
		end
	end
	-- Not known: a bar that shows keeps going, with its object handed again.
	if shown and mode ~= "tick" then
		local object = Duration(id)
		if object ~= nil then
			if PlainZero(object) then return Stop(w.name) end
			busy = true
			Feed(bars[w.name], object)
			busy = false
		end
	end
end

-- Out of a fight, when every bar's time left reads plain: least time on
-- top. Else the order stays.
local function Sort()
	if #order < 2 then return end
	if InCombatLockdown() then return end
	local left = {}
	for _, name in ipairs(order) do
		local object = bars[name] and bars[name].object
		if object == nil then return end
		local okS, secret = pcall(function() return object:HasSecretValues() end)
		if not okS or Plain(secret) ~= false then return end
		local okR, t = pcall(function() return object:GetRemainingDuration() end)
		t = okR and Plain(t) or nil
		if type(t) ~= "number" then return end
		left[name] = t
	end
	table.sort(order, function(a, b)
		if left[a] ~= left[b] then return left[a] < left[b] end
		return a < b
	end)
end

-- As wide as the HUD. With no saved place, under the HUD's left end (the
-- HUD's blue box covers the whole HUD), below the totem row when that is
-- on (a fixed place, so the bars do not jump when a totem goes).
function Place()
	local db = HUDiniDB
	if not db then return end
	local iconSize = db.iconSize or 40
	local h = math.max(12, math.floor(iconSize * HEIGHT + 0.5))
	local width = HUDini.mover and HUDini.mover:GetWidth()
	if type(width) ~= "number" or width < h * 4 then width = iconSize * 6 end
	width = width - 2
	-- The look, as one key: a bar is styled again only when it changed.
	local color = ns.BarColor("timer")
	local look = table.concat({ tostring(TexturePath()), tostring(ns.BarFontPath()), h,
		tostring(color[1]), tostring(color[2]), tostring(color[3]), tostring(color[4]) }, "|")
	local y = -GAP
	if db.showTotems and ns.ClassToken() == "SHAMAN" then
		y = y - (math.floor(iconSize * TOTEM + 0.5) + GAP)
	end
	local box = Holder()
	box:SetShown(M.enabled)
	local unlocked = Unlocked()
	local rows = #order
	if unlocked and rows < SAMPLE then rows = SAMPLE end
	box:SetSize(width, math.max(1, rows) * (h + GAP) - GAP)
	box.grab:SetShown(unlocked)
	if unlocked then box.grab.text:SetText(ns.Text("timerBars.dragMe")) end
	if not moving then
		box:ClearAllPoints()
		local saved = Saved()
		if saved then
			local s = Scale(box)
			box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x / s, saved.y / s)
		else
			box:SetPoint("TOPLEFT", HUDini.mover, "BOTTOMLEFT", 1, y)
		end
	end
	for i, name in ipairs(order) do
		local f = bars[name]
		f:SetSize(width, h)
		f.icon:SetWidth(h)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(i - 1) * (h + GAP))
		if f.look ~= look then
			Style(f)
			f.look = look
		end
	end
end

-- only: a name, to look at that spell alone (its Cooldown's end).
function Update(mode, only)
	for _, w in ipairs(watch) do
		if only == nil or w.name == only then Look(w, mode) end
	end
	-- A bar whose spell is no longer watched goes.
	for i = #order, 1, -1 do
		local keep = false
		for _, w in ipairs(watch) do
			if w.name == order[i] then keep = true break end
		end
		if not keep then Stop(order[i]) end
	end
	Sort()
	Place()
end

-- The spells to watch: each one turned on that you know, by name.
local function Rebuild()
	wipe(watch)
	for _, name in ipairs(ns.TimerBarSpells()) do
		if ns.GetTimerBar(name) and (not ns.KnownSpell or ns.KnownSpell(name)) then
			local base = ns.SpellID(name)
			if base then
				watch[#watch + 1] = { name = name, base = base, id = base }
			end
		end
	end
end

-- One frame after the event, once however many events came: a shared
-- cooldown fires no event of its own, and the game may not have moved
-- every spell yet.
local function Late()
	lateDue = false
	Update("late")
	wipe(ended)
end

local function OnCooldownEvent(event)
	if event == "SPELL_UPDATE_CHARGES" then return Update("charges") end
	Update("event")
	if not lateDue then
		lateDue = true
		M:After(0, Late)
	end
end

local function Begin()
	Rebuild()
	Update("refeed")
end

M:On({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES" }, OnCooldownEvent)
M:On({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }, Begin)
-- The fight is over: a new object reads plain again (one from the fight
-- stays secret), so the bars sort.
M:On("PLAYER_REGEN_ENABLED", function() Update("refeed") end)

-- A new icon size, scale or layout moves the bars with the HUD.
hooksecurefunc(HUDini, "Layout", Place) -- locale: skip a method name
-- /hud lock and unlock, and HUDini setup's Move the HUD: the blue box.
hooksecurefunc(HUDini, "ApplyLock", Place) -- locale: skip a method name

function M:OnEnable()
	-- A safety net for an end no event or Cooldown reported.
	M:Every(0.5, function()
		if #order > 0 then Update("tick") end
	end)
	Begin()
end

function M:OnDisable()
	for i = #order, 1, -1 do Stop(order[i]) end
	wipe(watch)
	-- Its timer is cancelled with the module.
	lateDue = false
	wipe(ended)
	moving = false
	-- Off (M.enabled is false now): the holder and its blue box hide.
	Place()
end

-- A spell turned on or off, or a new look (color, texture, time format):
-- the bars take it at once.
function ns.RefreshTimerBars()
	if not M:IsOn() or not M.enabled then return end
	Rebuild()
	for _, f in pairs(bars) do
		if f.object ~= nil then
			busy = true
			Feed(f, f.object)
			busy = false
		end
	end
	Update("refeed")
end

-- Back under the HUD, moving with it again. Not in a fight: false.
function ns.ResetTimerBarsPlace()
	if not HUDiniDB or InCombatLockdown() then return false end
	ns.ClassDB().timerBarPlace = nil
	moving = false
	Place()
	return true
end

-- For the tests: the names with a bar, top to bottom, and one bar.
function ns.TimerBarOrder() return order end
function ns.TimerBarFrame(name) return bars[name] end
function ns.TimerBarHolder() return Holder() end
