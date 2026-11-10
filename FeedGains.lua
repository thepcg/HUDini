--[[--------------------------------------------------------------------------
	HUDini - Feed: money, XP, levels, quests, discovery, the session

	Money and XP do not read chat. They watch your totals go up (GetMoney,
	UnitXP), so every source counts and no language matters. Gains wait in a
	bucket for a moment, so a burst becomes one line.

	A quest turn-in or a discovery says how much XP and money it gave. Its
	line shows them, and takes that much out of the bucket, so the same XP
	does not show twice.

	Banks: gold you take out of a bank is not a gain, so money is not
	counted while a bank is open. At a vendor, a gain reads "Sold".

	XP detail: the share of the level, the part that came from rested XP,
	and about how many kills are left to the level (from your last kills).

	A new level waits a moment, so its XP line comes first. Then a summary
	of the level just done: how long it took, quests, kills.

	Secrets: every number is checked before it is used. A secret one is
	skipped, and the last good value is kept.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local Text = ns.Text

local Plain, IsSecret = ns.Plain, ns.IsSecret
local Number, CharacterKey = ns.Number, ns.CharacterKey
local F = ns.Feed

-- A module of its own (Modules.lua), on with the feed: while the feed is
-- off it has no events and no timers.
local M = ns.NewModule("feedGains", { label = "Feed (money, XP, quests)", setting = "showFeed" }) -- locale: skip a debug name (/hud debug modules)
local C = F.COLOR

local FLUSH = 0.4          -- seconds a gain waits for more of its kind
local CLAIM_TIME = 2       -- seconds a turn-in's XP and money wait to be taken
local KILL_SAMPLES = 5

F.questTitles = F.questTitles or {}

--------------------------------------------------------------------------------
-- Claims: XP and money a quest or discovery line already shows
--------------------------------------------------------------------------------

local claim = { xp = 0, money = 0, untilTime = 0 }

-- Take what a claim covers out of a gain. Returns what is left.
local function TakeClaim(field, gain)
	if GetTime() > claim.untilTime then
		claim.xp, claim.money = 0, 0
		return gain
	end
	local take = math.min(claim[field], gain)
	claim[field] = claim[field] - take
	return gain - take
end

--------------------------------------------------------------------------------
-- Buckets
--------------------------------------------------------------------------------

local bucket = { xp = 0, rested = 0, money = 0, sold = 0 }
local flushing = false
local lastMax

local function XPText(L)
	local s = "+" .. Number(L.amount) .. " XP"
	if not HUDiniDB.feedXPDetail then return s end
	local parts = {}
	if L.max and L.max > 0 then parts[#parts + 1] = ("%.1f%%"):format(L.amount / L.max * 100) end
	if L.rested and L.rested > 0 then parts[#parts + 1] = Text("feed.rested", Number(L.rested)) end
	local left = F.KillsLeft and F.KillsLeft()
	if left then parts[#parts + 1] = left == 1 and Text("feed.killToLevel", left) or Text("feed.killsToLevel", left) end
	if #parts > 0 then s = s .. " " .. F.Gray("(" .. table.concat(parts, " · ") .. ")") end
	return s
end

local function MoneyText(L)
	if L.sold then return Text("feed.sold", F.Coins(L.amount)) end
	return "+ " .. F.Coins(L.amount)
end

local function Flush()
	if bucket.xp > 0 then
		F.Line({ kind = "xp", key = "xp", amount = bucket.xp, rested = bucket.rested, max = lastMax,
			icon = F.ICON.xp, color = C.xp, text = XPText })
	end
	if bucket.money > 0 then
		F.Line({ kind = "money", key = "money", amount = bucket.money, icon = F.ICON.money, text = MoneyText })
	end
	if bucket.sold > 0 then
		F.Line({ kind = "money", key = "sold", amount = bucket.sold, sold = true, icon = F.ICON.money,
			text = MoneyText })
	end
	bucket.xp, bucket.rested, bucket.money, bucket.sold = 0, 0, 0, 0
end

local function SoonFlush()
	if flushing then return end
	flushing = true
	M:After(FLUSH, function()
		flushing = false
		Flush()
	end)
end

-- A quest or discovery line shows this XP and money: take it from the
-- buckets now, and from gains still to come.
local function Covers(xp, money)
	local take = math.min(bucket.xp, xp)
	bucket.xp = bucket.xp - take
	bucket.rested = math.min(bucket.rested, bucket.xp)
	xp = xp - take
	take = math.min(bucket.money, money)
	bucket.money = bucket.money - take
	money = money - take
	if GetTime() > claim.untilTime then claim.xp, claim.money = 0, 0 end
	claim.xp, claim.money = claim.xp + xp, claim.money + money
	claim.untilTime = GetTime() + CLAIM_TIME
end

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

local lastMoney

local function OnMoney()
	local now = Plain(GetMoney())
	if not now then return end
	if lastMoney and now > lastMoney then
		local gain = now - lastMoney
		if not (HUDiniDB.feedHideBank and F.AtBank()) then
			F.Count("coin", gain)
			gain = TakeClaim("money", gain)
			if gain > 0 then
				if F.Open(F.MERCHANT) then
					bucket.sold = bucket.sold + gain
				else
					bucket.money = bucket.money + gain
				end
				SoonFlush()
			end
		end
	end
	lastMoney = now
end

--------------------------------------------------------------------------------
-- XP and kills
--------------------------------------------------------------------------------

local lastXP, lastLevel, lastRested
local kills = {}   -- XP of the last few kills

function F.KillsLeft()
	if #kills == 0 or not (lastXP and lastMax) then return end
	local sum = 0
	for _, k in ipairs(kills) do sum = sum + k end
	local each = sum / #kills
	if each <= 0 then return end
	return math.ceil((lastMax - lastXP) / each)
end

-- This level's numbers, kept per character. full: the record began at a
-- level-up, so it holds the whole level.
local levelRec, since

local function LoadLevel()
	HUDiniDB.feedLevels = HUDiniDB.feedLevels or {}
	local key = CharacterKey()
	local level = Plain(UnitLevel("player"))
	local rec = HUDiniDB.feedLevels[key]
	if not (rec and rec.level == level) then
		rec = { level = level, secs = 0, quests = 0, kills = 0, full = false }
		HUDiniDB.feedLevels[key] = rec
	end
	levelRec, since = rec, GetTime()
end

local function CountLevel(field)
	if levelRec then levelRec[field] = (levelRec[field] or 0) + 1 end
end

local function Duration(secs)
	local h, m = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
	if h > 0 then return ("%dh %dm"):format(h, m) end
	return ("%dm"):format(math.max(m, 1))
end

local function OnXP()
	local rawRested = GetXPExhaustion and GetXPExhaustion()
	local now, most = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	local level = Plain(UnitLevel("player"))
	if not (now and most) then return end

	-- One guard: restedKnown says the game gave an answer (nil counts: no rested XP).
	local restedKnown = not IsSecret(rawRested)
	local rested = restedKnown and rawRested or nil
	if lastXP and lastMax then
		local ups = (level and lastLevel) and (level - lastLevel) or 0
		local gain
		if ups == 0 and now >= lastXP then
			gain = now - lastXP
		elseif ups <= 1 then
			-- One level went by (or UnitLevel has not caught up yet).
			gain = (lastMax - lastXP) + now
		end
		-- Two or more levels at once: no honest number to show.
		if gain and gain > 0 then
			F.Count("xp", gain)
			local used = 0
			if restedKnown and lastRested then used = math.max(0, lastRested - (rested or 0)) end
			gain = TakeClaim("xp", gain)
			if gain > 0 then
				bucket.xp = bucket.xp + gain
				bucket.rested = bucket.rested + math.min(used, gain)
				SoonFlush()
			end
		end
	end

	if restedKnown then
		if lastRested and lastRested > 0 and not rested then
			F.Line({ kind = "xp", key = "rested", text = Text("feed.restedUsed"), color = C.gray, icon = F.ICON.xp })
		end
		lastRested = rested
	end
	lastXP, lastMax = now, most
	if level then lastLevel = level end
end

local function OnKill(msg)
	local text = Plain(msg)
	if not text then return end
	local pat = F.Pattern("COMBATLOG_XPGAIN_FIRSTPERSON", true)
	local name, xp
	if pat then name, xp = text:match(pat) end
	xp = tonumber(xp)
	if not xp then return end
	table.insert(kills, xp)
	if #kills > KILL_SAMPLES then table.remove(kills, 1) end
	F.Count("kills")
	CountLevel("kills")
end

local function OnLevel(level, talents)
	level = Plain(level)
	talents = Plain(talents)
	if not level then return end
	F.Count("levels")
	-- Wait for the XP of the last kill to show first.
	M:After(0.8, function()
		Flush()
		F.Line({ kind = "level", text = Text("feed.level", level), color = C.level, icon = F.ICON.level,
			big = true, bigText = Text("feed.levelBig", level) })

		local rec = levelRec
		if rec then
			rec.secs = rec.secs + (GetTime() - since)
			if rec.full and rec.level == level - 1 and rec.secs >= 60 then
				local parts = { Text("feed.levelTook", rec.level, Duration(rec.secs)) }
				if rec.quests > 0 then parts[#parts + 1] = (rec.quests == 1 and Text("feed.quest", rec.quests) or Text("feed.quests", rec.quests)) end
				if rec.kills > 0 then parts[#parts + 1] = (rec.kills == 1 and Text("feed.kill", rec.kills) or Text("feed.kills", rec.kills)) end
				if talents and talents > 0 then
					parts[#parts + 1] = (talents == 1 and Text("feed.talent", talents) or Text("feed.talents", talents))
				end
				F.Line({ kind = "summary", text = table.concat(parts, " · "), color = C.gray, icon = F.ICON.level })
			end
		end
		levelRec = { level = level, secs = 0, quests = 0, kills = 0, full = true }
		HUDiniDB.feedLevels = HUDiniDB.feedLevels or {}
		HUDiniDB.feedLevels[CharacterKey()] = levelRec
		since = GetTime()
	end)
end

--------------------------------------------------------------------------------
-- Quests turned in
--------------------------------------------------------------------------------

local function QuestText(L)
	local s = Text("feed.turnedIn", L.title)
	if L.xp > 0 and F.On("xp") then s = s .. "  |cffc78cff+" .. Number(L.xp) .. " XP|r" end
	if L.money > 0 and F.On("money") then s = s .. "  " .. F.Coins(L.money) end
	return s
end

local function OnQuest(questID, xp, money)
	questID, xp, money = Plain(questID), Plain(xp) or 0, Plain(money) or 0
	F.Count("quests")
	CountLevel("quests")
	if not F.On("quest") then return end
	local title = questID and F.questTitles[questID]
	if not title and questID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
		title = C_QuestLog.GetTitleForQuestID(questID)
	end
	if not title and GetTitleText then title = Plain(GetTitleText()) end
	if not title or title == "" then title = Text("feed.aQuest") end
	-- Only what the quest line shows is taken from the other lines.
	Covers(F.On("xp") and xp or 0, F.On("money") and money or 0)
	F.Line({ kind = "quest", title = title, xp = xp, money = money, text = QuestText,
		color = C.quest, icon = F.ICON.quest })
end

--------------------------------------------------------------------------------
-- Discovery
--------------------------------------------------------------------------------

local function OnSystem(msg)
	local text = Plain(msg)
	if not (text and F.On("discovery")) then return end
	local pat = F.Pattern("ERR_ZONE_EXPLORED_XP")
	local place, xp
	if pat then place, xp = text:match(pat) end
	xp = tonumber(xp)
	if place and xp then
		local shown = F.On("xp") and xp or 0
		Covers(shown, 0)
		F.Line({ kind = "discovery", color = C.discovery, icon = F.ICON.map,
			text = Text("feed.discovered", place) .. (shown > 0 and ("  |cffc78cff+" .. Number(xp) .. " XP|r") or "") })
		return
	end
	pat = F.Pattern("ERR_ZONE_EXPLORED")
	place = pat and text:match(pat)
	if place then
		F.Line({ kind = "discovery", text = Text("feed.discovered", place), color = C.discovery, icon = F.ICON.map })
		return
	end
	if ERR_NEWTAXIPATH and text == ERR_NEWTAXIPATH then
		F.Line({ kind = "discovery", text = Text("feed.flightPath"), color = C.discovery, icon = F.ICON.flight,
			big = true })
	end
end

--------------------------------------------------------------------------------
-- The session: /hud feedsession
--------------------------------------------------------------------------------

function ns.FeedSession(rest)
	local say = ns.Say
	if rest and rest:lower() == "reset" then
		F.ResetSession()
		say(Text("feed.sessionReset"))
		return
	end
	local s = F.session
	if not s then
		say(Text("feed.noSession"))
		return
	end
	-- While the feed is off, the clock stopped when it went off (lastSeen).
	say(Text("feed.session", Duration((s.lastSeen or time()) - s.start)))
	ns.Detail(Text("feed.sessionMoney", F.Coins(s.coin or 0)))
	ns.Detail(Text("feed.sessionLoot", F.Coins(s.value or 0)))
	ns.Detail(Text("feed.sessionCounts", Number(s.xp or 0), s.kills or 0,
		s.quests or 0, s.levels or 0))
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- Off: gains not shown yet are dropped, with their timer, and the level's
-- clock stops. The session and the level count only while the feed is on.
function M:OnDisable()
	bucket.xp, bucket.rested, bucket.money, bucket.sold = 0, 0, 0, 0
	flushing = false
	if levelRec and since then levelRec.secs = levelRec.secs + (GetTime() - since) end
	since = nil
end

-- On late (the 4th argument), PLAYER_ENTERING_WORLD runs at once: it starts
-- the count from here, so what came while the feed was off is no gain.
M:On({
	"PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
	"UPDATE_EXHAUSTION", "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM",
}, function(event, ...)
	if not HUDiniDB then return end
	if event == "PLAYER_MONEY" then
		OnMoney()
	elseif event == "PLAYER_XP_UPDATE" then
		OnXP()
	elseif event == "UPDATE_EXHAUSTION" then
		-- Only a rise (rest in an inn). A drop belongs to the XP that used
		-- it, and OnXP reads it there.
		local raw = GetXPExhaustion and GetXPExhaustion()
		local rested = Plain(raw)
		if rested and rested > (lastRested or 0) then lastRested = rested end
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
		OnKill((...))
	elseif event == "PLAYER_LEVEL_UP" then
		local level, _, _, talents = ...
		OnLevel(level, talents)
	elseif event == "QUEST_TURNED_IN" then
		OnQuest(...)
	elseif event == "CHAT_MSG_SYSTEM" then
		OnSystem((...))
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Start counting from here, so a login is not a gain.
		lastMoney = Plain(GetMoney())
		local now, most = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
		if now and most then lastXP, lastMax = now, most end
		lastLevel = Plain(UnitLevel("player")) or lastLevel
		local raw = GetXPExhaustion and GetXPExhaustion()
		if not IsSecret(raw) then lastRested = raw end
		if not levelRec then
			LoadLevel()
		elseif not since then
			since = GetTime()
		end
	elseif event == "PLAYER_LOGOUT" then
		if levelRec and since then
			levelRec.secs = levelRec.secs + (GetTime() - since)
			since = GetTime()
		end
	end
end)
