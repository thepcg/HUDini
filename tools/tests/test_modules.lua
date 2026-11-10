-- Modules (TICK-0009): a part that is off has no events, tickers, timers or
-- frames (D-002), and goes on and off with its setting.

local FEED = { feed = true, feedLoot = true, feedGains = true, feedWatch = true }

local function Report(ns)
	local out = {}
	for _, m in ipairs(ns.ModuleReport()) do out[m.name] = m end
	return out
end

-- True if any frame in the world listens for the event.
local function Heard(w, event)
	for _, f in ipairs(w.frames) do
		if f.__h.events[event] then return true end
	end
	return false
end

-- Count the lines the feed is asked to show.
local function CountLines(ns)
	local F, n = ns.Feed, { 0 }
	local Line = F.Line
	F.Line = function(spec)
		n[1] = n[1] + 1
		return Line(spec)
	end
	return n
end

local function Off(w, setting)
	w.env.HUDiniDB[setting] = false
	w.ns.HUDini:Apply()
end

local function On(w, setting)
	w.env.HUDiniDB[setting] = true
	w.ns.HUDini:Apply()
end

H.test("the feed off at login makes no frame and listens to nothing", function()
	local w = H.world()
	w.env.HUDiniDB = { showFeed = false }
	local ns = w:loadAddon()
	H.eq(w.env.HUDiniFeed, nil, "no feed box")
	H.eq(w.env.HUDiniFeedHighlight, nil, "no highlight")
	local r = Report(ns)
	for name in pairs(FEED) do
		local m = H.ok(r[name], "module " .. name) or r[name]
		H.eq(m.on, false, name .. " off")
		H.eq(m.events + m.tickers + m.timers + m.frames, 0, name .. " has nothing")
	end
	for _, event in ipairs({ "CHAT_MSG_LOOT", "PLAYER_MONEY", "BAG_UPDATE", "MERCHANT_SHOW", "LOOT_READY" }) do
		H.eq(Heard(w, event), false, "nobody listens for " .. event)
	end
	H.eq(ns.Feed.On("loot"), false, "the feed says off")
	H.eq(ns.Feed.Line({ kind = "info", text = "x" }), nil, "a line goes nowhere")
	H.eq(#w.printed, 0, "lines printed at login")
end)

H.test("the feed on at login listens and has its frames", function()
	local w = H.world()
	local ns = w:loadAddon()
	H.ok(w.env.HUDiniFeed, "feed box made")
	H.ok(w.env.HUDiniFeedHighlight, "highlight made")
	local r = Report(ns)
	for name in pairs(FEED) do
		H.eq(r[name].on, true, name .. " on")
		H.ok(r[name].events > 0, name .. " listens")
	end
	H.eq(r.feed.frames, 3, "box, highlight and the event frame")
	H.eq(Heard(w, "CHAT_MSG_LOOT"), true, "loot heard")
	H.eq(Heard(w, "PLAYER_MONEY"), true, "money heard")
	H.ok(ns.Feed.session, "feed session loaded")
end)

H.test("the feed turned on late starts up", function()
	local w = H.world()
	w.env.HUDiniDB = { showFeed = false }
	local ns = w:loadAddon()
	On(w, "showFeed")
	H.ok(w.env.HUDiniFeed, "feed box made")
	H.ok(ns.Feed.session, "session loaded by the late start")
	H.eq(w.env.HUDiniFeed:IsShown(), true, "the box shows")
end)

H.test("the feed off and on again counts no gain from while it was off", function()
	local w = H.world()
	local money = 0
	w.env.GetMoney = function() return money end
	local ns = w:loadAddon()
	money = 100
	w:fire("PLAYER_MONEY")                    -- the feed's count is at 100
	w:runTimers()
	Off(w, "showFeed")
	money = 5000                              -- came while the feed was off
	On(w, "showFeed")
	local lines = CountLines(ns)
	w:fire("PLAYER_MONEY")
	w:runTimers()
	H.eq(lines[1], 0, "no line for the money from before")
	-- New money counts.
	money = 7000
	w:fire("PLAYER_MONEY")
	w:runTimers()
	H.eq(lines[1], 1, "a line for the new money")
end)

H.test("the feed turned off drops its events, timers and box", function()
	local w = H.world()
	local ns = w:loadAddon()
	local ran = false
	local timer = ns.Feed.module:After(1, function() ran = true end)
	H.eq(Report(ns).feed.timers, 1, "one timer waits")
	w.env.HUDiniFeedHighlight:Show()          -- a highlight on screen
	Off(w, "showFeed")
	H.eq(timer:IsCancelled(), true, "the timer is cancelled")
	local r = Report(ns)
	for name in pairs(FEED) do
		H.eq(r[name].on, false, name .. " off")
		H.eq(r[name].events + r[name].tickers + r[name].timers, 0, name .. " runs nothing")
	end
	H.eq(Heard(w, "CHAT_MSG_LOOT"), false, "loot not heard")
	H.eq(Heard(w, "PLAYER_MONEY"), false, "money not heard")
	H.eq(w.env.HUDiniFeed:IsShown(), false, "box hidden")
	H.eq(w.env.HUDiniFeedHighlight:IsShown(), false, "highlight hidden")
	w:runTimers()
	H.eq(ran, false, "the waiting timer never runs")
	H.eq(ns.Feed.module:After(1, function() ran = true end), nil, "no new timer while off")

	-- Off and on again before it was due: still not this run's timer.
	On(w, "showFeed")
	local late = false
	ns.Feed.module:After(1, function() late = true end)
	Off(w, "showFeed")
	On(w, "showFeed")
	w:runTimers()
	H.eq(late, false, "a timer from before the last off never runs")
end)

H.test("each setting has one default, and a fresh install gets them", function()
	local w = H.world()
	local ns = w:loadAddon()
	local db = w.env.HUDiniDB
	H.eq(ns.defaults.showFeed, true, "feed default")
	H.eq(ns.defaults.feedTime, 15, "feed time default")
	H.eq(ns.defaults.showXP, true, "XP default")
	H.eq(ns.defaults.moveWindows, false, "mover default")
	H.eq(db.showFeed, true, "fresh DB: feed")
	H.eq(db.feedTime, 15, "fresh DB: feed time")
	H.eq(db.xpHeight, 16, "fresh DB: XP height")
	H.eq(db.moveWindows, false, "fresh DB: mover")

	H.ok(not pcall(ns.NewModule, "feed", {}), "a second module named feed is an error")
	H.ok(not pcall(ns.NewModule, "other", { defaults = { showXP = false } }),
		"a second default for showXP is an error")
	H.eq(ns.defaults.showXP, true, "the first default stays")
end)

H.test("the XP bar off has no ticker, and on again counts no old XP", function()
	local w = H.world()
	local xp = 100
	w.env.UnitXP = function() return xp end
	local ns = w:loadAddon()
	local r = Report(ns)
	H.eq(r.xp.on, true, "XP on")
	H.eq(r.xp.tickers, 1, "one ticker")
	H.ok(r.xp.events > 0, "XP listens")
	local ticker = ns.GetModule("xp").tickers[1]

	Off(w, "showXP")
	r = Report(ns)
	H.eq(r.xp.tickers + r.xp.events, 0, "off: no ticker, no event")
	H.eq(ticker.cancelled, true, "the ticker is cancelled")

	local key = next(w.env.HUDiniDB.xpSessions)
	local session = w.env.HUDiniDB.xpSessions[key]
	H.eq(session.gained, 0, "nothing gained yet")
	xp = 600                                  -- came while the bar was off
	On(w, "showXP")
	r = Report(ns)
	H.eq(r.xp.tickers, 1, "one new ticker")
	H.ok(ns.GetModule("xp").tickers[1] ~= ticker, "a new ticker, not the old one")
	w:fire("PLAYER_XP_UPDATE", "player")
	H.eq(session.gained, 0, "old XP is no gain")
	xp = 650
	w:fire("PLAYER_XP_UPDATE", "player")
	H.eq(session.gained, 50, "new XP counts")
end)

H.test("/hud debug modules lists each part and what it runs", function()
	local w = H.world()
	w.env.HUDiniDB = { showFeed = false }
	w:loadAddon()
	w:slash("/hud debug modules")
	H.ok(H.printed(w, "HUDini|r: " .. w.ns.TEXT[0]["debug.modulesTitle"]), "title")
	H.ok(H.printed(w, "  Feed: off, 0 events, 0 tickers, 0 timers, 0 frames"), "feed line")
	H.ok(H.printed(w, "  XP bar: on, 10 events, 1 ticker, 0 timers, 1 frame"), "XP line")
	H.ok(H.printed(w, "  Move game windows: off, 0 events, 0 tickers, 0 timers, 0 frames"), "mover line")
end)

--------------------------------------------------------------------------------
-- Off and on again: each part still works after it (review of 6222676)
--------------------------------------------------------------------------------

-- The text of each line the feed is asked to show.
local function LineTexts(ns)
	local F, out = ns.Feed, {}
	local Line = F.Line
	F.Line = function(spec)
		local text = spec.text
		if type(text) == "function" then text = text(spec) end
		out[#out + 1] = tostring(text)
		return Line(spec)
	end
	return out
end

local function Has(list, text)
	for _, s in ipairs(list) do
		if s:find(text, 1, true) then return true end
	end
	return false
end

H.test("the XP rate counts only the time the bar was on", function()
	local w = H.world()
	local xp = 0
	w.env.UnitXP = function() return xp end
	w.env.UnitXPMax = function() return 100000 end
	w:loadAddon()                             -- the session starts at 1000
	local key = next(w.env.HUDiniDB.xpSessions)
	local function Session() return w.env.HUDiniDB.xpSessions[key] end
	H.eq(Session().start, 1000, "session start")
	w.time = 1600
	xp = 600
	w:fire("PLAYER_XP_UPDATE", "player")
	Off(w, "showXP")
	w.time = 1800                             -- 200 s off, inside RELOAD_GRACE
	On(w, "showXP")
	H.eq(Session().start, 1200, "the 200 s off are not session time")
	w.time = 2400
	xp = 700
	w:fire("PLAYER_XP_UPDATE", "player")
	H.eq(Session().gained, 700, "both gains count")
	-- 700 XP in the 1200 s the bar was on: 2100/hr.
	H.eq(Session().gained / (w.time - Session().start) * 3600, 2100, "the rate while on")

	-- Off for 3 hours: a new session, as after a logout.
	local old = Session()
	Off(w, "showXP")
	w.time = w.time + 3 * 3600
	On(w, "showXP")
	H.ok(Session() ~= old, "a new session")
	H.eq(Session().gained, 0, "it starts empty")
	H.eq(Session().start, math.floor(w.time), "it starts now")
end)

H.test("the feed session counts only the time the feed was on", function()
	local w = H.world()
	local ns = w:loadAddon()                  -- the session starts at 1000
	w.time = 1000 + 20 * 60
	Off(w, "showFeed")
	w.time = w.time + 120                     -- 2 min off, inside RELOAD_GRACE
	On(w, "showFeed")
	H.eq(ns.Feed.session.start, 1120, "the 2 min off are not session time")
	w:slash("/hud feedsession")
	H.ok(H.printed(w, ns.TEXT[0]["feed.session"]:format("20m")), "/hud feedsession says 20 minutes")

	-- Off for 3 hours: a new session.
	local old = ns.Feed.session
	Off(w, "showFeed")
	w.time = w.time + 3 * 3600
	On(w, "showFeed")
	H.ok(ns.Feed.session ~= old, "a new session")
	H.eq(ns.Feed.session.start, math.floor(w.time), "it starts now")
	H.eq(w.env.HUDiniDB.feedSessions[next(w.env.HUDiniDB.feedSessions)], ns.Feed.session, "and is saved")
end)

H.test("bags, gear and quests changed while the feed was off give no line", function()
	local w = H.world()
	local free = 10
	w.env.C_Container = {
		GetContainerNumSlots = function() return 16 end,
		GetContainerItemInfo = function() end,
		GetContainerNumFreeSlots = function(bag) return bag == 0 and free or 0, 0 end,
	}
	local ns = w:loadAddon()
	w:runTimers()                             -- notes 10 free slots
	local texts = LineTexts(ns)
	free = 0
	w:fire("BAG_UPDATE_DELAYED")
	H.ok(Has(texts, "Bags full."), "full bags give a line while on")
	free = 10
	w:fire("BAG_UPDATE_DELAYED")
	local n = #texts

	Off(w, "showFeed")
	free = 0                                  -- filled while the feed was off
	On(w, "showFeed")
	w:runTimers()
	H.eq(#texts, n, "no line for bags filled while off")
	free = 10
	w:fire("BAG_UPDATE_DELAYED")
	free = 0
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(#texts, n + 1, "full again while on: a line")
end)

H.test("a feed turned on again gives money lines after HUDini:Apply runs twice", function()
	local w = H.world()
	local money = 0
	w.env.GetMoney = function() return money end
	local ns = w:loadAddon()
	local lines = CountLines(ns)
	money = 100
	w:fire("PLAYER_MONEY")                    -- a line waits for its timer
	w.ns.HUDini:Apply()
	w.ns.HUDini:Apply()
	w:runTimers()
	H.eq(lines[1], 1, "Apply while on keeps the waiting line")

	money = 200
	w:fire("PLAYER_MONEY")                    -- waits again, then the feed goes off
	Off(w, "showFeed")
	On(w, "showFeed")
	w:runTimers()
	H.eq(lines[1], 1, "the line from before the off is dropped")
	money = 300
	w:fire("PLAYER_MONEY")
	w:runTimers()
	H.eq(lines[1], 2, "a new money line after off and on")
end)

H.test("a level-up after the feed goes off and on again shows its line", function()
	local w = H.world()
	local ns = w:loadAddon()
	local texts = LineTexts(ns)
	Off(w, "showFeed")
	On(w, "showFeed")
	w:fire("PLAYER_LEVEL_UP", 11, 0, 0, 0)
	w:runTimers()
	H.ok(Has(texts, "Level 11"), "the level line")
end)

H.test("a highlight shows after the feed goes off in the middle of one", function()
	local w = H.world()
	local ns = w:loadAddon()
	local hl = w.env.HUDiniFeedHighlight
	ns.Feed.Highlight({ text = "First" })
	H.eq(hl:IsShown(), true, "the first highlight shows")
	Off(w, "showFeed")                        -- before its timer ends it
	On(w, "showFeed")
	ns.Feed.Highlight({ text = "Second" })
	H.eq(hl:IsShown(), true, "a new highlight shows")
	H.eq(hl.text:GetText(), "Second", "with its own text")
end)

H.test("a quest scan waiting at the off does not stop the next one", function()
	local w = H.world()
	local ns = w:loadAddon()
	w:runTimers()
	w:fire("QUEST_LOG_UPDATE")                -- a scan waits
	Off(w, "showFeed")
	On(w, "showFeed")                         -- the late start waits to note things
	H.eq(Report(ns).feedWatch.timers, 1, "one timer: the late start")
	w:fire("QUEST_LOG_UPDATE")
	H.eq(Report(ns).feedWatch.timers, 2, "and a new scan")
end)

H.test("before login the feed says off, and login runs each start-up once", function()
	local w = H.world()
	w:load(unpack(H.tocFiles()))
	w:fire("ADDON_LOADED", "HUDini")
	local ns = w.ns
	H.eq(w.env.HUDiniDB.showFeed, true, "the setting is on")
	H.eq(ns.Feed.On("loot"), false, "but the feed is not on yet")
	H.eq(ns.Feed.Line({ kind = "info", text = "x" }), nil, "a line goes nowhere")
	w:fire("PLAYER_LOGIN")
	w:fire("PLAYER_ENTERING_WORLD", true, false)
	H.eq(ns.Feed.On("loot"), true, "on after login")
	H.eq(Report(ns).feedWatch.timers, 1, "one start-up timer, not one more at login")
end)

H.test("the feed off lets go of Edit Mode, its OnUpdate and the open windows", function()
	local w = H.world()
	local ns = w:loadAddon()
	local function Count(event)
		local n = 0
		for _ in pairs(w.callbacks[event] or {}) do n = n + 1 end
		return n
	end
	-- Core hears Edit Mode too, for the XP bar fade (TICK-0087): one of each
	-- event is Core's, and stays.
	H.eq(Count("EditMode.Enter"), 2, "Edit Mode heard while on")
	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	ns.Feed.Line({ kind = "info", text = "x" })
	H.ok(w.env.HUDiniFeed:GetScript("OnUpdate"), "a line ages on OnUpdate")
	w:fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
	H.eq(ns.Feed.AtBank(), true, "at the bank")

	Off(w, "showFeed")
	H.eq(Count("EditMode.Enter") + Count("EditMode.Exit"), 2, "Edit Mode not heard while off")
	H.eq(w.env.HUDiniFeed:GetScript("OnUpdate"), nil, "no OnUpdate while off")
	On(w, "showFeed")
	H.eq(Count("EditMode.Enter") + Count("EditMode.Exit"), 4, "heard again when on")
	H.eq(ns.Feed.AtBank(), false, "a bank shut while off counts as shut")
end)

-- (re-review of 46cb8f1)

H.test("/hud feedsession while the feed is off does not count the time off", function()
	local w = H.world()
	w:loadAddon()                             -- the session starts at 1000
	w.time = 1000 + 20 * 60
	Off(w, "showFeed")
	w.time = w.time + 4 * 60 + 40             -- off, inside RELOAD_GRACE
	w:slash("/hud feedsession")
	H.ok(H.printed(w, w.ns.TEXT[0]["feed.session"]:format("20m")), "20 minutes, not 24")
end)

H.test("the level clock stops while the feed is off", function()
	local w = H.world()
	w:loadAddon()                             -- the clock starts at 1000
	local key = next(w.env.HUDiniDB.feedLevels)
	local rec = w.env.HUDiniDB.feedLevels[key]
	local secs = rec.secs
	w.time = 1100                             -- 100 s on
	Off(w, "showFeed")
	w.time = 2100                             -- 1000 s off
	On(w, "showFeed")
	w.time = 2150                             -- 50 s on
	w:fire("PLAYER_LOGOUT")
	H.eq(rec.secs - secs, 150, "only the 150 s on count")
end)

H.test("gear worn down while the feed was off gives no line", function()
	local w = H.world()
	local dura = 100
	w.env.GetInventoryItemDurability = function(slot) if slot == 1 then return dura, 100 end end
	local ns = w:loadAddon()
	w:runTimers()                             -- notes 100%
	local texts = LineTexts(ns)
	dura = 40
	w:fire("UPDATE_INVENTORY_DURABILITY")
	H.ok(Has(texts, ns.TEXT[0]["feed.gearAt"]:format(40)), "low gear gives a line while on")
	dura = 100
	w:fire("UPDATE_INVENTORY_DURABILITY")
	local n = #texts

	Off(w, "showFeed")
	dura = 40                                 -- worn down while the feed was off
	On(w, "showFeed")
	w:runTimers()
	H.eq(#texts, n, "no line for gear worn while off")
	dura = 20
	w:fire("UPDATE_INVENTORY_DURABILITY")
	H.eq(#texts, n + 1, "lower again while on: a line")
end)

H.test("quest progress made while the feed was off gives no line", function()
	local w = H.world()
	local got = 1
	w.env.C_QuestLog = {
		GetNumQuestLogEntries = function() return 1 end,
		GetInfo = function() return { questID = 5, title = "Boar Hunt" } end,
		GetQuestObjectives = function() return { { numFulfilled = got, text = ("Boars: %d/9"):format(got) } } end,
		IsComplete = function() return false end,
	}
	w.env.HUDiniDB = { feedQuestProgress = true }
	local ns = w:loadAddon()
	w:runTimers()                             -- notes 1/9
	local texts = LineTexts(ns)
	got = 2
	w:fire("QUEST_LOG_UPDATE")
	w:runTimers()
	H.ok(Has(texts, "Boars: 2/9"), "progress gives a line while on")
	local n = #texts

	Off(w, "showFeed")
	got = 3                                   -- made while the feed was off
	On(w, "showFeed")
	w:runTimers()
	H.eq(#texts, n, "no line for progress made while off")
	got = 4
	w:fire("QUEST_LOG_UPDATE")
	w:runTimers()
	H.ok(Has(texts, "Boars: 4/9"), "more progress while on: a line")
end)

-- (re-review of 6a7f299)

H.test("/hud feedsession reset while the feed is off starts a clock that waits for the feed", function()
	local w = H.world()
	local ns = w:loadAddon()
	w.time = 1600
	Off(w, "showFeed")
	w:slash("/hud feedsession reset")
	local s = ns.Feed.session
	w.time = w.time + 240
	w:slash("/hud feedsession")
	H.ok(H.printed(w, ns.TEXT[0]["feed.session"]:format("1m")), "no time counted while off")
	H.ok(not H.printed(w, ns.TEXT[0]["feed.session"]:format("4m")), "not the 4 min off")
	On(w, "showFeed")
	H.eq(ns.Feed.session, s, "on again: the reset session carries on")
	H.eq(s.start, math.floor(w.time), "from now")
end)
