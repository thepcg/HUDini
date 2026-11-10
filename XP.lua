--[[--------------------------------------------------------------------------
	HUDini - XP

	The experience bar, at the bottom of the stack right above the icons.

		fill        your XP into this level
		behind it   rested XP: how far the rested bonus reaches
		ticks       one every 5%
		left text   12,345 / 45,600  27.1%
		right text  9.8k/hr  2h 05m   (XP per hour this session, time to level)

	The session is kept per character in HUDiniDB.xpSessions, so a /reload
	carries on where it was. A fresh login, or more than ns.RELOAD_GRACE
	seconds away, starts a new one (ns.LoadSession, Util.lua). /hud xp reset starts one by hand.

	The bar hides at max level and while XP gain is switched off.

	It is a module (Modules.lua) on showXP: while the bar is off it has no
	events and no ticker. The bar itself is Bars.lua's "xp" row.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local HUDini = ns.HUDini
local Plain  = ns.Plain
local Number = ns.Number

local M = ns.NewModule("xp", {
	label = "XP bar", -- locale: skip a debug name (/hud debug modules)
	setting = "showXP",
	defaults = {
		showXP         = true,   -- the XP bar, right above the icons
		showXPRate     = true,   -- ... with XP per hour and time to level
		xpHeight       = 16,     -- its height in pixels, room for its text
	},
})

local TICKS        = 20      -- segments, so a tick every 5%
local MIN_ELAPSED  = 60      -- seconds of session before a rate is shown

--------------------------------------------------------------------------------
-- When to show
--------------------------------------------------------------------------------

local function AtMaxLevel()
	local level = Plain(UnitLevel("player")) or 0
	local most  = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
		or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL
	return most ~= nil and level >= most
end

-- You still earn XP: below max level, and XP gain not turned off.
function ns.EarningXP()
	if IsXPUserDisabled and IsXPUserDisabled() then return false end
	return not AtMaxLevel()
end

function ns.ShowXP()
	if not (HUDiniDB and HUDiniDB.showXP) then return false end
	return ns.EarningXP()
end

--------------------------------------------------------------------------------
-- The bar: rested behind, ticks and text on top
--------------------------------------------------------------------------------

local decorated

-- Bars.lua makes the plain bar for the "xp" row. This adds the rest once.
local function XPBar()
	local bar = ns.GetBar("xp")
	if decorated then return bar end
	decorated = true

	-- Rested XP: a sibling one frame level down, so the XP fill draws over it.
	-- It carries the backdrop, since the XP bar's own would cover it.
	local rested = CreateFrame("StatusBar", "HUDiniBar_rested", bar:GetParent())
	ns.StyleBar(rested, "rested")
	rested:SetAllPoints(bar)
	bar:SetFrameLevel(rested:GetFrameLevel() + 1)

	rested.backdrop = rested:CreateTexture(nil, "BACKGROUND")
	rested.backdrop:SetPoint("TOPLEFT", -1, 1)
	rested.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
	rested.backdrop:SetColorTexture(0, 0, 0, 0.85)
	if bar.backdrop then bar.backdrop:Hide() end

	bar:HookScript("OnShow", function() rested:Show() end)
	bar:HookScript("OnHide", function() rested:Hide() end)
	rested:SetShown(bar:IsShown())
	bar.rested = rested

	-- A tick every 5%, re-placed whenever the bar changes size.
	bar.ticks = {}
	for i = 1, TICKS - 1 do
		local tick = bar:CreateTexture(nil, "OVERLAY")
		tick:SetColorTexture(0, 0, 0, 0.55)
		bar.ticks[i] = tick
	end
	local function PlaceTicks()
		local w, h = bar:GetWidth(), bar:GetHeight()
		for i, tick in ipairs(bar.ticks) do
			tick:ClearAllPoints()
			tick:SetSize(1, h)
			tick:SetPoint("LEFT", bar, "LEFT", math.floor(w * i / TICKS + 0.5), 0)
		end
	end
	bar:HookScript("OnSizeChanged", PlaceTicks)
	PlaceTicks()

	bar.left = ns.TrackText(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
	bar.left:SetPoint("LEFT", bar, "LEFT", 6, 0)
	bar.left:SetJustifyH("LEFT")
	bar.left:SetWordWrap(false)

	bar.right = ns.TrackText(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
	bar.right:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	bar.right:SetJustifyH("RIGHT")
	bar.right:SetWordWrap(false)

	ns.ApplyFont()
	ns.ApplyTexture()
	return bar
end

--------------------------------------------------------------------------------
-- The session
--------------------------------------------------------------------------------

local session

local function NewSession()
	return { start = time(), gained = 0 }
end

local function LoadSession()
	local s = ns.LoadSession("xpSessions", NewSession)
	s.lastXP, s.lastMax = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	session = s
end

function ns.ResetXPSession()
	if not HUDiniDB then return end
	HUDiniDB.xpSessions = HUDiniDB.xpSessions or {}
	HUDiniDB.xpSessions[ns.CharacterKey()] = nil
	LoadSession()
	ns.UpdateXP()
end

-- Count what came in since the last update. A level-up wraps: the rest of
-- the old level, then everything into the new one.
local function CountGain()
	if not session then return end
	local xp, most = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	if xp and session.lastXP then
		if xp >= session.lastXP then
			session.gained = session.gained + (xp - session.lastXP)
		elseif session.lastMax then
			session.gained = session.gained + (session.lastMax - session.lastXP) + xp
		end
	end
	session.lastXP, session.lastMax = xp, most
end

-- XP per second this session, or nil while there is too little to go on.
local function Rate()
	if not (session and session.gained > 0) then return nil end
	local elapsed = time() - session.start
	if elapsed < MIN_ELAPSED then return nil end
	return session.gained / elapsed
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function Short(n)
	if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
	if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

local function Clock(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm"):format(math.max(1, m))
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------

function ns.UpdateXP()
	if not ns.ShowXP() then return end
	local bar = XPBar()

	local xp, most = UnitXP("player"), UnitXPMax("player")
	local rested   = GetXPExhaustion and GetXPExhaustion() or 0

	-- Passthrough first: the widgets take the numbers whatever they are.
	pcall(bar.SetMinMaxValues, bar, 0, most)
	pcall(bar.SetValue, bar, xp)

	local pxp, pmost, prested = Plain(xp), Plain(most), Plain(rested) or 0
	if not (pxp and pmost and pmost > 0) then
		bar.rested:SetValue(0)
		bar.left:SetText("")
		bar.right:SetText("")
		return
	end

	bar.rested:SetMinMaxValues(0, pmost)
	bar.rested:SetValue(math.min(pxp + prested, pmost))

	bar.left:SetText(("%s / %s  %.1f%%"):format(Number(pxp), Number(pmost), pxp / pmost * 100))

	local right = ""
	local rate = HUDiniDB.showXPRate and Rate()
	if rate then
		right = ("%s/hr  %s"):format(Short(rate * 3600), Clock((pmost - pxp) / rate))
	elseif prested > 0 then
		right = ("+%d%% rested"):format(math.floor(prested / pmost * 100 + 0.5))
	end
	bar.right:SetText(right)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- Set once each time the bar goes on, at the first PLAYER_ENTERING_WORLD.
local started = false

-- Off: the session keeps its place, as at a logout. On again, LoadSession
-- takes the time off out of it.
function M:OnDisable()
	if session then session.lastSeen = time() end
	started = false
end

M:On({
	"PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP",
	"ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "PLAYER_UPDATE_RESTING",
	-- The max level can come after the login (TICK-0117; Core.lua).
	"PLAYER_MAX_LEVEL_UPDATE", "UPDATE_EXPANSION_LEVEL",
}, function(event, _, _, late)
	if event == "PLAYER_LOGOUT" then
		if session then session.lastSeen = time() end
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		if not started then
			started = true
			-- On again after an off, too: the time off is no session time
			-- (or, past RELOAD_GRACE, a new session starts), and XP that
			-- came while the bar was off is no gain.
			LoadSession()
			-- The rate and time to level move on their own, so refresh the
			-- text now and then.
			M:Every(5, function() ns.UpdateXP() end)
			-- On late, HUDini:Apply lays the HUD out right after.
			if not late then HUDini:Layout() end
		end
	elseif not started then
		-- Before the first loading screen ends: nothing to count yet.
		return
	elseif event == "PLAYER_XP_UPDATE" then
		CountGain()
	elseif event == "PLAYER_LEVEL_UP" or event == "ENABLE_XP_GAIN" or event == "DISABLE_XP_GAIN"
		or event == "PLAYER_MAX_LEVEL_UPDATE" or event == "UPDATE_EXPANSION_LEVEL" then
		-- Max level, or XP switched off, takes the bar away, and gives the
		-- default XP bar back. A max level that comes after the login
		-- gives the bar.
		HUDini:Layout()
		HUDini:ApplyBlizzardFrames()
	end

	ns.UpdateXP()
end)
