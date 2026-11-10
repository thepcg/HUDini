-- FeedGains.lua when the game hides an answer (TICK-0112). Each test first
-- runs the value that WOULD change the feed, plain, and checks that it does.
-- Then it flags that same value secret and checks that the feed does what it
-- does for no answer, and throws nothing. So a missing Plain() or IsSecret()
-- fails the test (the method of TICK-0110). Each flagged value is used for
-- nothing else in its test.

local KEY = "Player-1-0001"   -- ns.CharacterKey() in the harness

-- A logged-in world with the feed on. w.secret: the values issecretvalue
-- calls secret. w.xp, w.max, w.rested, w.money, w.level: what the game says
-- now. opts: the login's values (xp, max, rested, money, level), saved
-- (HUDiniDB), and atLogin, a value that is secret only while the login runs.
local function World(opts)
	opts = opts or {}
	local w = H.world()
	w.secret = {}
	for k, v in pairs({
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience.",
		ERR_ZONE_EXPLORED = "Discovered: %s",
	}) do w.env[k] = v end
	w.env.HUDiniDB = opts.saved
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.xp, w.max, w.rested = opts.xp or 100, opts.max or 1000, opts.rested
	w.money, w.level = opts.money or 1000, opts.level or 10
	w.env.UnitXP = function() return w.xp end
	w.env.UnitXPMax = function() return w.max end
	w.env.GetXPExhaustion = function() return w.rested end
	w.env.GetMoney = function() return w.money end
	if opts.atLogin then w.secret[opts.atLogin] = true end
	w:loadAddon()
	if opts.atLogin then w.secret[opts.atLogin] = nil end
	w.time = w.time + 10                       -- past the quiet time after login
	local F, shown = w.ns.Feed, {}
	local Line = F.Line
	F.Line = function(spec)
		local L = Line(spec)
		if L then shown[#shown + 1] = L end
		return L
	end
	w.shown = shown
	-- Fire event, let the feed show it; the new line whose field is value.
	function w:Show(field, value, event, ...)
		local n = #self.shown
		self:fire(event, ...)
		self:runTimers()
		for i = n + 1, #self.shown do
			if self.shown[i][field] == value then return self.shown[i] end
		end
	end
	-- XP comes in: the line it shows, or nil.
	function w:Gain(xp, level)
		self.xp, self.level = xp, level or self.level
		return self:Show("key", "xp", "PLAYER_XP_UPDATE", "player")
	end
	function w:Money(money)
		self.money = money
		return self:Show("key", "money", "PLAYER_MONEY")
	end
	return w
end

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

H.test("a secret money total is no gain", function()
	local w = World()
	H.eq(w:Money(1500).amount, 500, "plain: +500")
	w = World()
	w.secret[1500] = true
	H.eq(w:Money(1500), nil, "secret: none")
end)

H.test("a secret money total at login is not counted from", function()
	local w = World({ money = 1001 })
	H.eq(w:Money(1500).amount, 499, "plain: +499")
	w = World({ money = 1001, atLogin = 1001 })
	H.eq(w:Money(1500), nil, "secret: none")
end)

--------------------------------------------------------------------------------
-- XP
--------------------------------------------------------------------------------

H.test("a secret XP is no gain", function()
	local w = World()
	H.eq(w:Gain(300).amount, 200, "plain: +200")
	w = World()
	w.secret[300] = true
	H.eq(w:Gain(300), nil, "secret: none")
end)

H.test("a secret XP maximum is no gain", function()
	local w = World({ max = 1001 })
	H.eq(w:Gain(300).amount, 200, "plain: +200")
	w = World({ max = 1001 })
	w.secret[1001] = true
	H.eq(w:Gain(300), nil, "secret: none")
end)

H.test("a secret level counts as no level-up", function()
	-- Two levels at once give no number; a level not known gives the wrap.
	local w = World({ xp = 900 })
	H.eq(w:Gain(50, 12), nil, "plain: two levels, none")
	w = World({ xp = 900 })
	w.secret[12] = true
	H.eq(w:Gain(50, 12).amount, 150, "secret: the rest of the level and 50")
end)

H.test("a secret rested XP counts none of the gain as rested", function()
	local w = World({ rested = 500 })
	w.rested = 400
	H.eq(w:Gain(300).rested, 100, "plain: 100 of it rested")
	w = World({ rested = 500 })
	w.rested, w.secret[400] = 400, true
	H.eq(w:Gain(300).rested, 0, "secret: none")
end)

H.test("a secret rested XP from an inn is not kept", function()
	local w = World()
	w.rested = 600
	w:fire("UPDATE_EXHAUSTION")
	w.rested = 450
	H.eq(w:Gain(300).rested, 150, "plain: 150 of it rested")
	w = World()
	w.rested, w.secret[600] = 600, true
	w:fire("UPDATE_EXHAUSTION")
	w.rested = 450
	H.eq(w:Gain(300).rested, 0, "secret: none")
end)

H.test("a secret XP or maximum at login is not counted from", function()
	local w = World({ xp = 101, max = 1001 })
	H.eq(w:Gain(300).amount, 199, "plain: +199")
	w = World({ xp = 101, max = 1001, atLogin = 101 })
	H.eq(w:Gain(300), nil, "secret XP: none")
	w = World({ xp = 101, max = 1001, atLogin = 1001 })
	H.eq(w:Gain(300), nil, "secret maximum: none")
end)

H.test("a secret level at login is not counted from", function()
	local w = World({ xp = 900, level = 11 })
	H.eq(w:Gain(50, 13), nil, "plain: two levels, none")
	w = World({ xp = 900, level = 11, atLogin = 11 })
	H.eq(w:Gain(50, 13).amount, 150, "secret: the rest of the level and 50")
end)

H.test("a secret rested XP at login is not counted from", function()
	local w = World({ rested = 501 })
	w.rested = 400
	H.eq(w:Gain(300).rested, 101, "plain: 101 of it rested")
	w = World({ rested = 501, atLogin = 501 })
	w.rested = 400
	H.eq(w:Gain(300).rested, 0, "secret: none")
end)

H.test("a secret kill line is no kill", function()
	local w = World()
	w:fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 45 experience.")
	H.eq(w.ns.Feed.KillsLeft(), 20, "plain: 900 to go at 45 each")
	w = World()
	w.secret["Wolf dies, you gain 45 experience."] = true
	w:fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 45 experience.")
	H.eq(w.ns.Feed.KillsLeft(), nil, "secret: no kills")
end)

--------------------------------------------------------------------------------
-- Levels
--------------------------------------------------------------------------------

H.test("a secret level at login does not keep the saved level", function()
	local saved = { feedLevels = { [KEY] = { level = 23, secs = 100, quests = 2, kills = 0, full = true } } }
	local w = World({ level = 23, saved = H.copy(saved) })
	H.eq(w.env.HUDiniDB.feedLevels[KEY].quests, 2, "plain: the same level, kept")
	w = World({ level = 23, saved = H.copy(saved), atLogin = 23 })
	H.eq(w.env.HUDiniDB.feedLevels[KEY].quests, 0, "secret: a new record")
end)

H.test("a secret new level shows no level line", function()
	local w = World()
	H.ok(w:Show("kind", "level", "PLAYER_LEVEL_UP", 11), "plain: level 11")
	w = World()
	w.secret[11] = true
	H.eq(w:Show("kind", "level", "PLAYER_LEVEL_UP", 11), nil, "secret: none")
end)

H.test("a secret talent count leaves talents out of the summary", function()
	local saved = { feedLevels = { [KEY] = { level = 10, secs = 100, quests = 0, kills = 0, full = true } } }
	local w = World({ saved = H.copy(saved) })
	local L = w:Show("kind", "summary", "PLAYER_LEVEL_UP", 11, 0, 0, 3)
	H.ok(L.text:find(w.ns.TEXT[0]["feed.talents"]:format(3), 1, true), "plain: +3 talents")
	w = World({ saved = H.copy(saved) })
	w.secret[3] = true
	L = w:Show("kind", "summary", "PLAYER_LEVEL_UP", 11, 0, 0, 3)
	H.eq(L.text:find("talent", 1, true), nil, "secret: none")
end)

--------------------------------------------------------------------------------
-- Quests and discovery
--------------------------------------------------------------------------------

local function QuestWorld()
	local w = World()
	w.env.C_QuestLog = w.env.C_QuestLog or {}
	w.env.C_QuestLog.GetTitleForQuestID = function(id) if id == 777 then return "Wolves" end end
	w.env.GetTitleText = function() return w.title end
	function w:TurnIn(...) return self:Show("kind", "quest", "QUEST_TURNED_IN", ...) end
	return w
end

H.test("a secret quest ID gives no title from it", function()
	local w = QuestWorld()
	H.eq(w:TurnIn(777, 250, 120).title, "Wolves", "plain")
	w = QuestWorld()
	w.secret[777] = true
	H.eq(w:TurnIn(777, 250, 120).title, "a quest", "secret")
end)

H.test("a secret quest XP shows none", function()
	local w = QuestWorld()
	H.eq(w:TurnIn(777, 250, 120).xp, 250, "plain")
	w = QuestWorld()
	w.secret[250] = true
	H.eq(w:TurnIn(777, 250, 120).xp, 0, "secret")
end)

H.test("a secret quest money shows none", function()
	local w = QuestWorld()
	H.eq(w:TurnIn(777, 250, 120).money, 120, "plain")
	w = QuestWorld()
	w.secret[120] = true
	H.eq(w:TurnIn(777, 250, 120).money, 0, "secret")
end)

H.test("a secret quest window title is no title", function()
	local w = QuestWorld()
	w.title = "Bears"
	H.eq(w:TurnIn(nil, 250, 120).title, "Bears", "plain")
	w = QuestWorld()
	w.title, w.secret.Bears = "Bears", true
	H.eq(w:TurnIn(nil, 250, 120).title, "a quest", "secret")
end)

H.test("a secret system line is no discovery", function()
	local w = World()
	H.ok(w:Show("kind", "discovery", "CHAT_MSG_SYSTEM", "Discovered: Elwynn"), "plain")
	w = World()
	w.secret["Discovered: Elwynn"] = true
	H.eq(w:Show("kind", "discovery", "CHAT_MSG_SYSTEM", "Discovered: Elwynn"), nil, "secret: none")
end)
