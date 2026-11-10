--[[--------------------------------------------------------------------------
	HUDini - Feed: the box

	A frameless box of text that tells the screen what just happened: loot,
	money, XP, reputation, quests, new spells and more. The newest line sits
	at the bottom and older ones slide up. Each line fades on its own after
	HUDiniDB.feedTime seconds. /hud unlock, or Blizzard's Edit Mode, shows a
	blue box to drag.

	This file is only the box. The lines come from three more files:

		FeedLoot.lua    items, currency, crafts, reputation, skill-ups
		FeedGains.lua   money, XP, levels, quests, discovery, the session
		FeedWatch.lua   bags, gear, merchants, spells, collections, quest
		                progress

	They talk to the box through ns.Feed (F below):

		F.Line(spec)      add a line, or grow a matching one; returns it
		F.Refresh(line)   draw a line again after its data changed
		F.Highlight(spec) the big text above the box, for big moments
		F.On(kind)        is the feed, and that kind of line, switched on

	A spec is a table: kind, key, icon, text (a string, or a function of the
	line), color, and any data the text function reads. Two specs with the
	same key, five seconds apart or less, become one line: the amount and
	count add up (feedStack). raw is a secret string: it goes to the screen
	as it came, because a secret cannot be read or joined to other text.

	Each line is its own FontString, so it can slide and fade by itself. The
	icon is a texture beside the text, on the outer side of the box, so even
	a secret line gets one.

	The feed is a module (Modules.lua), one per file, all on showFeed. While
	it is off it has no events, tickers or timers, and the box and the
	highlight are made only the first time it goes on (D-002).
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Plain = ns.Plain
local Number, CharacterKey = ns.Number, ns.CharacterKey

local F = {}
ns.Feed = F

-- Every feed setting. The other feed files add none of their own.
local M = ns.NewModule("feed", {
	label = "Feed", -- locale: skip a debug name (/hud debug modules)
	setting = "showFeed",
	defaults = {
		showFeed       = true,
		feedTime       = 15,     -- seconds a line stays before it fades
		feedFontSize   = 14,
		feedLines      = 8,      -- the box's height, in lines
		feedWidth      = 420,
		feedLoot       = true,   -- items and currency
		feedMoney      = true,
		feedXP         = true,   -- experience and new levels
		feedRep        = true,
		feedSkill      = true,
		feedCraft      = true,
		feedQuests     = true,   -- quest turn-ins, with their XP and money
		feedDiscovery  = true,   -- new areas and flight paths
		feedSpells     = true,   -- new spells and recipes
		feedCollections = true,  -- new looks, mounts, pets and toys
		feedBags       = true,   -- bags at 5, 2 and 0 free slots
		feedGear       = true,   -- durability warnings and repair cost
		feedLevelSummary = true, -- how long the last level took
		feedResting    = true,   -- you start or stop resting (FeedWatch.lua)
		feedQuestProgress = false, -- objective counts as they move (a hint)
		feedUpgrade    = false,  -- "+N ilvl" on loot that beats what you wear (a hint)
		-- Details.
		feedStack      = true,   -- the same thing again soon joins the old line
		feedBagCount   = true,   -- "(47)": how many you now have
		feedValue      = true,   -- vendor price on loot, junk value at a merchant
		feedNewLook    = true,   -- "New look" on loot with an appearance you lack
		feedXPDetail   = true,   -- % of the level, rested part, kills to level
		feedRepDetail  = true,   -- "(1,200 to Honored)"
		feedHideGray   = false,  -- no lines for gray items
		feedHideBuys   = true,   -- no loot lines for what you buy at a vendor
		feedHideBank   = true,   -- no money lines for gold taken from a bank
		feedIgnore     = {},     -- [itemID] = true: never show these
		-- Look.
		feedHighlight  = true,   -- big text for a level, an epic, a mount
		feedHighlightSound = false,
		feedHoldInCombat = true, -- lines wait out a fight before they fade
		feedAnimate    = true,   -- lines slide and fade in
		feedBackdrop   = true,   -- a soft shade behind the lines
		feedThickOutline = false,
		feedAlign      = "auto", -- "auto" (from the box's side), "LEFT" or "RIGHT"
		feedPoint      = "BOTTOMRIGHT",
		feedRelPoint   = "BOTTOMRIGHT",
		feedX          = -60,
		feedY          = 260,
	},
})
F.module = M

-- Line kind -> its on/off setting. A kind not listed has no switch of its own.
F.KIND_SETTING = {
	loot       = "feedLoot",
	money      = "feedMoney",
	xp         = "feedXP",
	level      = "feedXP",
	rep        = "feedRep",
	skill      = "feedSkill",
	craft      = "feedCraft",
	quest      = "feedQuests",
	discovery  = "feedDiscovery",
	spell      = "feedSpells",
	collection = "feedCollections",
	bags       = "feedBags",
	gear       = "feedGear",
	summary    = "feedLevelSummary",
	progress   = "feedQuestProgress",
	resting    = "feedResting",
}

F.COLOR = {
	xp         = { 0.78, 0.55, 1.00 },
	level      = { 1.00, 0.82, 0.00 },
	up         = { 0.40, 0.90, 0.40 },
	down       = { 1.00, 0.35, 0.30 },
	skill      = { 0.55, 0.75, 1.00 },
	quest      = { 1.00, 0.82, 0.00 },
	discovery  = { 0.90, 0.85, 0.60 },
	spell      = { 0.45, 0.85, 1.00 },
	collection = { 1.00, 0.50, 1.00 },
	warn       = { 1.00, 0.65, 0.20 },
	bad        = { 1.00, 0.30, 0.30 },
	gray       = { 0.65, 0.65, 0.65 },
	info       = { 0.40, 0.80, 1.00 },
}

F.ICON = {
	xp     = "Interface\\Icons\\XP_Icon",
	money  = "Interface\\Icons\\INV_Misc_Coin_02",
	level  = "Interface\\Icons\\Achievement_Level_10",
	rep    = "Interface\\Icons\\Achievement_Reputation_01",
	bags   = "Interface\\Icons\\INV_Misc_Bag_08",
	map    = "Interface\\Icons\\INV_Misc_Map_01",
	gear   = "Interface\\Icons\\Trade_BlackSmithing",
	quest  = "Interface\\GossipFrame\\ActiveQuestIcon",
	flight = "Interface\\Minimap\\Tracking\\FlightMaster",
	info   = "Interface\\Icons\\INV_Misc_Spyglass_03",
	rest   = "Interface\\Icons\\Spell_Nature_Sleep",
}

local FADE_OUT     = 1.5    -- seconds a line takes to fade at the end of its time
local FADE_EXTRA   = 0.3    -- a line pushed past the top fades this fast
local FADE_IN      = 0.2
local SLIDE_FROM   = -8     -- a new line starts this far below its place
local GAP          = 2      -- pixels between lines

-- Numbers fields that add up when two lines join. The rest is replaced.
local SUMS = { amount = true, count = true, rested = true }

--------------------------------------------------------------------------------
-- Small helpers the other feed files share
--------------------------------------------------------------------------------

function F.On(kind)
	local db = HUDiniDB
	if not (db and db.showFeed and M.enabled) then return false end
	local key = F.KIND_SETTING[kind]
	return not key or db[key] and true or false
end


-- Blizzard's coin string gives its coins a fixed 14 px size, which sits
-- high in a bigger font. Size 0 makes each coin as tall as the text.
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"

function F.Coins(n)
	n = math.floor((tonumber(n) or 0) + 0.5)
	local g, s, c = math.floor(n / 10000), math.floor(n / 100) % 100, n % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = Number(g) .. COIN:format("Gold") end
	if s > 0 then parts[#parts + 1] = s .. COIN:format("Silver") end
	if c > 0 or n == 0 then parts[#parts + 1] = c .. COIN:format("Copper") end
	return table.concat(parts, " ")
end

function F.Gray(s) return "|cffa0a0a0" .. s .. "|r" end

-- A name with every link, colour, texture and bracket taken off: two lines
-- about the same thing compare equal however each one dressed it.
function F.Bare(s)
	if type(s) ~= "string" then return "" end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn.-:", ""):gsub("|r", "")
	s = s:gsub("|H.-|h", ""):gsub("|h", "")
	s = s:gsub("|A.-|a", ""):gsub("|T.-|t", "") -- locale: skip a Lua pattern
	s = s:gsub("[%[%]]", "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One of Blizzard's chat strings, as a Lua pattern. "You receive loot:
-- %s." picks out the link. open leaves the end free, for a string that can
-- have more after it ("... experience. (+45 exp Rested bonus)").
local patterns = {}

function F.Pattern(name, open)
	local cacheKey = open and (name .. "+") or name
	local p = patterns[cacheKey]
	if p ~= nil then return p end
	local fmt = _G[name]
	p = false
	if type(fmt) == "string" then
		p = fmt:gsub("%%%d%$([sdf])", "%%%1")                 -- %1$s -> %s
		-- Grammar codes some languages use: |3-1(%s) is a word ending, |1a;b;
		-- picks singular or plural, "|2 " is an elision. Any text may stand there.
		p = p:gsub("|3%-%d+%(%%s%)", "%%s")
		p = p:gsub("|1[^;]*;[^;]*;", "\1"):gsub("|2 ", "\1")
		p = p:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")      -- escape, except %
		p = p:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")       -- %s, %d
		p = p:gsub("%%%%%.%d+f", "([%%d%%.]+)")                -- %.1f, escaped to %%.1f
		p = p:gsub("\1", ".-")
		p = "^" .. p .. (open and "" or "$")
	end
	patterns[cacheKey] = p
	return p
end

function F.IconFor(link)
	if type(link) ~= "string" then return end
	local id = tonumber(link:match("item:(%d+)") or link:match("keystone:(%d+)"))
	if id then
		if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
		return GetItemIcon and GetItemIcon(id)
	end
	id = tonumber(link:match("currency:(%d+)"))
	if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		return info and info.iconFileID
	end
	id = tonumber(link:match("battlepet:(%d+)"))
	if id and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
		return (select(2, C_PetJournal.GetPetInfoBySpeciesID(id)))
	end
end

-- Which game windows are open: merchant, bank. Keys are
-- Enum.PlayerInteractionType values.
local openWindows = {}

function F.Open(kind)
	return openWindows[kind] and true or false
end

local IT = Enum and Enum.PlayerInteractionType or {}
F.MERCHANT = IT.Merchant or 5
local BANKS = { IT.Banker or 8, IT.GuildBanker or 10, IT.CharacterBanker or 67, IT.AccountBanker or 68 }

function F.AtBank()
	for _, t in ipairs(BANKS) do
		if openWindows[t] then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- The session: what this sitting brought in. Kept per character, and a
-- /reload carries on, like the XP bar's session (ns.LoadSession, Util.lua).
--------------------------------------------------------------------------------

local function NewSession()
	return { start = time(), coin = 0, value = 0, quests = 0, kills = 0, levels = 0, xp = 0 }
end

local function LoadSession()
	F.session = ns.LoadSession("feedSessions", NewSession)
end

function F.Count(field, n)
	local s = F.session
	if s then s[field] = (s[field] or 0) + (n or 1) end
end

function F.ResetSession()
	if not HUDiniDB then return end
	HUDiniDB.feedSessions = HUDiniDB.feedSessions or {}
	F.session = NewSession()
	HUDiniDB.feedSessions[CharacterKey()] = F.session
	-- Reset while the feed is off: its clock waits for the feed, as on an off.
	if not M.enabled then F.session.lastSeen = time() end
end

--------------------------------------------------------------------------------
-- The box. Its frames, and the highlight's, are made the first time the
-- feed goes on (M:OnEnable).
--------------------------------------------------------------------------------

local feed, backdrop

-- Settings read every frame, refreshed by ApplyFeed.
local size, lineH, iconSize, align, fontFlags = 14, 18, 16, "RIGHT", "OUTLINE"

local inEditMode = false
local setupMoving = false   -- HUDini setup's Move the feed (ns.FeedUnlock)

local function Unlocked()
	return inEditMode or setupMoving or not HUDiniDB.locked
end

local function BuildBox()
	feed = M:CreateFrame("Frame", "HUDiniFeed", UIParent)
	feed:SetFrameStrata("LOW")
	feed:SetClampedToScreen(true)
	feed:SetMovable(true)
	feed:EnableMouse(false)
	feed:SetSize(420, 144)
	feed:Hide()

	-- Blue, only while unlocked.
	feed.bg = feed:CreateTexture(nil, "BACKGROUND", nil, -1)
	feed.bg:SetAllPoints()
	feed.bg:SetColorTexture(0, 0.6, 1, 0.15)
	feed.bg:Hide()

	-- A soft dark band behind the lines that show, so they read on bright
	-- ground. Dark at the outer side, clear at the inner side.
	backdrop = feed:CreateTexture(nil, "BACKGROUND")
	backdrop:SetColorTexture(1, 1, 1, 1)
	backdrop:Hide()

	feed:SetScript("OnDragStart", function(self)
		if Unlocked() then self:StartMoving() end
	end)

	feed:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local db = HUDiniDB
		db.feedPoint, db.feedRelPoint, db.feedX, db.feedY = point, relPoint, x, y
		ns.ApplyFeed()   -- the side may change, and with it the icons' side
	end)
end

local function ResolveAlign()
	local db = HUDiniDB
	if db.feedAlign == "LEFT" or db.feedAlign == "RIGHT" then return db.feedAlign end
	local point = db.feedPoint or ""
	if point:find("RIGHT") then return "RIGHT" end
	return "LEFT"
end

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

local lines = {}   -- lines[1] is the newest, at the bottom
local pool = {}    -- spare { fs, tex } pairs

local function SetFont(fs, px, flags)
	if fs:SetFont(ns.BarFontPath(), px, flags) == false then
		fs:SetFont(STANDARD_TEXT_FONT, px, flags)
	end
end

-- Font, width and the icon's side, for one line's pair.
local function Style(L)
	local fs, tex = L.fs, L.tex
	SetFont(fs, size, fontFlags)
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetJustifyH(align)
	fs:SetJustifyV("BOTTOM")
	fs:SetWordWrap(true)
	if fs.SetMaxLines then fs:SetMaxLines(2) end
	fs:SetWidth(HUDiniDB.feedWidth - iconSize - 4)
	tex:SetSize(iconSize, iconSize)
	fs:ClearAllPoints()
	tex:ClearAllPoints()
	if align == "RIGHT" then
		tex:SetPoint("TOPLEFT", fs, "TOPRIGHT", 4, 0)
	else
		tex:SetPoint("TOPRIGHT", fs, "TOPLEFT", -4, 0)
	end
	L.anchored = false
end

local function Place(L)
	if align == "RIGHT" then
		L.fs:SetPoint("BOTTOMRIGHT", feed, "BOTTOMRIGHT", -(iconSize + 4), L.y)
	else
		L.fs:SetPoint("BOTTOMLEFT", feed, "BOTTOMLEFT", iconSize + 4, L.y)
	end
end

local function Render(L)
	local fs = L.fs
	if L.raw ~= nil then
		-- Secret: straight to the screen, never read.
		if not pcall(fs.SetText, fs, L.raw) then fs:SetText("") end
	else
		local body = L.text
		if type(body) == "function" then
			local ok, s = pcall(body, L)
			body = ok and s or nil
		end
		fs:SetText(body or "")
	end
	local c = L.color
	if c then fs:SetTextColor(c[1], c[2], c[3]) else fs:SetTextColor(1, 1, 1) end
	if L.icon then
		L.tex:SetTexture(L.icon)
		L.tex:Show()
	else
		L.tex:Hide()
	end
	fs:Show()
	-- A secret text may give a secret height. Then one line's height will do.
	local ok, h = pcall(fs.GetStringHeight, fs)
	h = ok and Plain(h) or nil
	L.h = (h and h > lineH) and h or lineH
end

local function Release(L)
	L.alive = false
	L.fs:Hide()
	L.fs:SetText("")
	L.tex:Hide()
	pool[#pool + 1] = { fs = L.fs, tex = L.tex }
end

local function Clear()
	for i = #lines, 1, -1 do
		Release(lines[i])
		lines[i] = nil
	end
	backdrop:Hide()
end

-- A finished pause (a fight, a loading screen): every line gets its full
-- time again.
local function Rearm()
	local now = GetTime()
	for _, L in ipairs(lines) do
		if not L.dying then L.born = now end
	end
end

local function OnUpdate(self, dt)
	local db = HUDiniDB
	if not db then return end
	local now = GetTime()
	local frozen = Unlocked() or (db.feedHoldInCombat and InCombatLockdown())
	local glide = db.feedAnimate and math.min(1, dt * 12) or 1
	local maxLines, life = db.feedLines, db.feedTime
	local y, top, brightest = 0, 0, 0

	local i = 1
	while i <= #lines do
		local L = lines[i]
		if i > maxLines and not L.dying then L.dying = 1 end

		local a
		if L.dying then
			L.dying = L.dying - dt / FADE_EXTRA
			a = L.dying
		else
			if frozen then L.born = L.born + dt end
			local age, keep = now - L.born, L.life or life
			a = age > keep and (1 - (age - keep) / FADE_OUT) or 1
		end
		if L.fadeIn < 1 then
			L.fadeIn = math.min(1, L.fadeIn + dt / FADE_IN)
			if L.fadeIn < a then a = L.fadeIn end
		end

		if a <= 0 then
			Release(L)
			table.remove(lines, i)
		else
			local dy = y - L.y
			if dy > 0.1 or dy < -0.1 then
				L.y = L.y + dy * glide
				Place(L)
			elseif not L.anchored or L.y ~= y then
				L.y = y
				L.anchored = true
				Place(L)
			end
			L.fs:SetAlpha(a)
			L.tex:SetAlpha(a)
			if a > brightest then brightest = a end
			top = L.y + L.h
			y = y + L.h + GAP
			i = i + 1
		end
	end

	if #lines == 0 then
		backdrop:Hide()
		self:SetScript("OnUpdate", nil)
		return
	end
	if db.feedBackdrop and brightest > 0 then
		backdrop:SetHeight(math.max(top, lineH) + 8)
		backdrop:SetAlpha(brightest)
		backdrop:Show()
	else
		backdrop:Hide()
	end
end

local function Wake()
	if not feed:GetScript("OnUpdate") then feed:SetScript("OnUpdate", OnUpdate) end
end

function F.Line(spec)
	if not (spec and F.On(spec.kind)) then return end
	local db = HUDiniDB
	local now = GetTime()

	-- Same key, still fresh: grow that line and bring it back to the bottom.
	if spec.key and db.feedStack then
		for i, L in ipairs(lines) do
			if L.key == spec.key and not L.dying and now - L.updated <= (L.life or db.feedTime) then
				for k, v in pairs(spec) do
					if SUMS[k] and not spec.replace and type(v) == "number" then
						L[k] = (L[k] or 0) + v
					else
						L[k] = v
					end
				end
				L.born, L.updated = now, now
				table.remove(lines, i)
				table.insert(lines, 1, L)
				Render(L)
				Wake()
				return L
			end
		end
	end

	local pair = table.remove(pool)
	if not pair then
		pair = { fs = feed:CreateFontString(nil, "OVERLAY"), tex = feed:CreateTexture(nil, "ARTWORK") }
		pair.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	local L = {}
	for k, v in pairs(spec) do L[k] = v end
	L.fs, L.tex = pair.fs, pair.tex
	L.alive = true
	L.born, L.updated = now, now
	L.fadeIn = db.feedAnimate and 0 or 1
	L.y = db.feedAnimate and SLIDE_FROM or 0
	Style(L)
	Render(L)
	L.fs:SetAlpha(0)
	L.tex:SetAlpha(0)
	table.insert(lines, 1, L)

	-- Far too many (a burst while frozen): drop the oldest at once.
	while #lines > db.feedLines + 6 do
		Release(table.remove(lines))
	end

	if spec.big then F.Highlight({ icon = spec.icon, text = spec.bigText, color = spec.color, line = L }) end
	Wake()
	return L
end

function F.Refresh(L)
	if L and L.alive then
		Render(L)
		Wake()
	end
end

-- The live lines whose key starts with prefix (setup's samples, "sample:").
function F.Keyed(prefix)
	local out = {}
	for _, L in ipairs(lines) do
		if not L.dying and type(L.key) == "string" and L.key:sub(1, #prefix) == prefix then
			out[#out + 1] = L
		end
	end
	return out
end

-- Fade a line now, even while the box is frozen (unlocked, Edit Mode).
function F.Fade(L)
	if L and L.alive and not L.dying then
		L.dying = 1
		Wake()
	end
end

--------------------------------------------------------------------------------
-- The highlight: big text above the box for a big moment (a level, an epic,
-- a new mount). It pops in, holds, and fades. More wait their turn.
--------------------------------------------------------------------------------

local HOLD = 2.5
local QUEUE_MAX = 3

local hl, popIn, grow, popOut
local queue, busy, shown = {}, false, 0
local NextHighlight

local function BuildHighlight()
	hl = M:CreateFrame("Frame", "HUDiniFeedHighlight", UIParent)
	hl:SetFrameStrata("MEDIUM")
	hl:SetSize(420, 40)
	hl:Hide()
	hl.text = hl:CreateFontString(nil, "OVERLAY")
	hl.text:SetAllPoints()
	hl.text:SetWordWrap(false)

	popIn = hl:CreateAnimationGroup()
	grow = popIn:CreateAnimation("Scale")
	grow:SetDuration(0.25)
	grow:SetSmoothing("OUT")
	if grow.SetScaleFrom then
		grow:SetScaleFrom(1.5, 1.5)
		grow:SetScaleTo(1, 1)
	end
	local show = popIn:CreateAnimation("Alpha")
	show:SetFromAlpha(0)
	show:SetToAlpha(1)
	show:SetDuration(FADE_IN)

	popOut = hl:CreateAnimationGroup()
	local hide = popOut:CreateAnimation("Alpha")
	hide:SetFromAlpha(1)
	hide:SetToAlpha(0)
	hide:SetDuration(0.6)
	if popOut.SetToFinalAlpha then popOut:SetToFinalAlpha(true) end

	popOut:SetScript("OnFinished", function()
		hl:SetAlpha(0)
		NextHighlight()
	end)
end

function NextHighlight()
	local item = table.remove(queue, 1)
	if not item then
		busy = false
		hl:Hide()
		return
	end
	busy = true
	shown = shown + 1
	local mine = shown
	local text = item.text
	if not text and item.line then
		local body = item.line.text
		if type(body) == "function" then
			local ok, s = pcall(body, item.line)
			body = ok and s or nil
		end
		text = body
	end
	if type(text) ~= "string" then return NextHighlight() end
	if item.icon then text = ("|T%s:0|t %s"):format(item.icon, text) end
	hl.text:SetText(text)
	local c = item.color or F.COLOR.level
	hl.text:SetTextColor(c[1], c[2], c[3])
	hl:SetAlpha(1)
	hl:Show()
	popIn:Stop()
	popOut:Stop()
	popIn:Play()
	if HUDiniDB.feedHighlightSound and SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then
		pcall(PlaySound, SOUNDKIT.UI_EPICLOOT_TOAST)
	end
	M:After(HOLD, function()
		if shown == mine then popOut:Play() end
	end)
end

function F.Highlight(item)
	local db = HUDiniDB
	if not (db and db.showFeed and db.feedHighlight and M.enabled) then return end
	if #queue >= QUEUE_MAX then return end
	queue[#queue + 1] = item
	if not busy then NextHighlight() end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local wasLocked = true

function ns.ApplyFeed()
	local db = HUDiniDB
	-- Off, there is nothing to set: M:OnDisable hid it all.
	if not (db and M.enabled and feed) then return end

	size = db.feedFontSize
	lineH = size + 4
	iconSize = size + 2
	align = ResolveAlign()
	fontFlags = db.feedThickOutline and "THICKOUTLINE" or "OUTLINE"

	feed:SetSize(db.feedWidth, db.feedLines * lineH)
	feed:ClearAllPoints()
	feed:SetPoint(db.feedPoint, UIParent, db.feedRelPoint, db.feedX, db.feedY)

	for _, L in ipairs(lines) do
		Style(L)
		Render(L)
	end

	-- The dark band hugs the outer side.
	backdrop:ClearAllPoints()
	local dark, clear = CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0)
	if align == "RIGHT" then
		backdrop:SetPoint("BOTTOMRIGHT", feed, "BOTTOMRIGHT", 8, -4)
		backdrop:SetGradient("HORIZONTAL", clear, dark)
	else
		backdrop:SetPoint("BOTTOMLEFT", feed, "BOTTOMLEFT", -8, -4)
		backdrop:SetGradient("HORIZONTAL", dark, clear)
	end
	backdrop:SetWidth(db.feedWidth + 16)

	-- The highlight sits just over the box, on the same side.
	SetFont(hl.text, math.floor(size * 1.6 + 0.5), "THICKOUTLINE")
	hl.text:SetShadowOffset(2, -2)
	hl.text:SetShadowColor(0, 0, 0, 1)
	hl.text:SetJustifyH(align)
	hl:SetSize(db.feedWidth, size * 2.4)
	hl:ClearAllPoints()
	if align == "RIGHT" then
		hl:SetPoint("BOTTOMRIGHT", feed, "TOPRIGHT", 0, 6)
	else
		hl:SetPoint("BOTTOMLEFT", feed, "TOPLEFT", 0, 6)
	end
	grow:SetOrigin(align, 0, 0)

	local locked = not Unlocked()
	feed:EnableMouse(not locked)
	if locked then feed:RegisterForDrag() else feed:RegisterForDrag("LeftButton") end
	feed.bg:SetShown(not locked)
	if wasLocked and not locked then
		F.Line({ kind = "info", key = "dragme", text = ns.Text("feed.dragMe"),
			color = F.COLOR.info, icon = F.ICON.info, life = math.huge })
	elseif locked and not wasLocked then
		for _, L in ipairs(lines) do
			if L.key == "dragme" then L.life, L.born = 0, GetTime() end
		end
	end
	wasLocked = locked
	feed:Show()
end

-- HUDini setup's Move the feed (TICK-0096): the feed alone shows its blue
-- box, and the HUD stays locked. Setup clears it on every way off the
-- step (Setup.lua Lock). Off, the flag waits for the feed to go on.
function ns.FeedUnlock(on)
	setupMoving = on and true or false
	ns.ApplyFeed()
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

-- Edit Mode tells EventRegistry when it opens and closes. Only a listener, so
-- nothing of Blizzard's is touched. Listened to only while the feed is on.
local function EditModeEnter()
	inEditMode = true
	ns.ApplyFeed()
end

local function EditModeExit()
	inEditMode = false
	ns.ApplyFeed()
end

function M:OnEnable()
	if not feed then
		BuildBox()
		BuildHighlight()
	end
	inEditMode = false
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", EditModeEnter, M)
		EventRegistry:RegisterCallback("EditMode.Exit", EditModeExit, M)
	end
end

function M:OnDisable()
	if EventRegistry and EventRegistry.UnregisterCallback then
		EventRegistry:UnregisterCallback("EditMode.Enter", M)
		EventRegistry:UnregisterCallback("EditMode.Exit", M)
	end
	inEditMode = false
	-- The session keeps its place for the next login, as at a logout.
	if F.session then F.session.lastSeen = time() end
	wipe(openWindows)
	if not feed then return end
	Clear()
	wipe(queue)
	busy = false
	popIn:Stop()
	popOut:Stop()
	hl:Hide()
	feed:SetScript("OnUpdate", nil)
	feed:EnableMouse(false)
	feed:RegisterForDrag()
	feed.bg:Hide()
	feed:Hide()
	-- On again while unlocked: "drag to move" shows again.
	wasLocked = true
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

M:On({
	"PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
	"MERCHANT_SHOW", "MERCHANT_CLOSED",
}, function(event, arg1, _, late)
	if not HUDiniDB then return end
	if event == "PLAYER_ENTERING_WORLD" then
		-- On again after an off (late): the time off is no session time,
		-- or, past RELOAD_GRACE, a new session starts.
		if late or not F.session then LoadSession() end
		-- On late, with a merchant or a bank open: it counts as shut until
		-- it opens again.
		wipe(openWindows)
		ns.ApplyFeed()
		Rearm()
	elseif event == "LOADING_SCREEN_DISABLED" then
		-- Lines kept ageing behind the loading screen. Give them their time.
		Rearm()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if HUDiniDB.feedHoldInCombat then Rearm() end
	elseif event == "PLAYER_LOGOUT" then
		if F.session then F.session.lastSeen = time() end
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		local t = Plain(arg1)
		if t then openWindows[t] = true end
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		local t = Plain(arg1)
		if t then openWindows[t] = nil end
	elseif event == "MERCHANT_SHOW" then
		openWindows[F.MERCHANT] = true
	elseif event == "MERCHANT_CLOSED" then
		openWindows[F.MERCHANT] = nil
	end
end)
