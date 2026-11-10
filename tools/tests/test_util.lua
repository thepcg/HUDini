-- Util.lua: the shared helpers (TICK-0012).

local KEY = "Player-1-0001"   -- the harness's UnitGUID("player")

H.test("Util.lua loads first in the .toc", function()
	H.eq(H.tocFiles()[1], "Util.lua")
end)

H.test("Plain hides a secret and IsSecret names it", function()
	local w = H.world()
	w.env.issecretvalue = function(v) return v == "SECRET" end
	local ns = w:load("Util.lua")
	H.eq(ns.Plain("SECRET"), nil, "Plain of a secret")
	H.eq(ns.Plain(5), 5, "Plain of a number")
	H.eq(ns.IsSecret("SECRET"), true, "IsSecret of a secret")
	H.eq(ns.IsSecret(5), false, "IsSecret of a number")
	H.eq(ns.IsSecret(nil), false, "IsSecret of nil")
end)

H.test("InCombat: lockdown or the combat flag; a secret flag is not a fight", function()
	local w = H.world()
	w.env.issecretvalue = function(v) return v == "SECRET" end
	local ns = w:load("Util.lua")
	H.eq(ns.InCombat(), false, "out of combat")
	w.combat = true
	H.eq(ns.InCombat(), true, "in combat")
	-- A secret flag: only lockdown can answer.
	w.env.UnitAffectingCombat = function() return "SECRET" end
	w.env.InCombatLockdown = function() return true end
	H.eq(ns.InCombat(), true, "lockdown with a secret flag")
	w.env.InCombatLockdown = function() return false end
	H.eq(ns.InCombat(), false, "secret flag, no lockdown")
end)

H.test("Say prints one HUDini line", function()
	local w = H.world()
	local ns = w:load("Util.lua")
	ns.Say("hello.")
	H.eq(w.printed[#w.printed], "|cff33ccffHUDini|r: hello.")
end)

H.test("Number rounds to a whole number", function()
	local w = H.world()
	local ns = w:load("Util.lua")
	H.eq(ns.Number(12.5), "13")
	H.eq(ns.Number(12.4), "12")
	H.eq(ns.Number(7), "7")
end)

H.test("LoadSession keeps a session seen within the grace, and starts one after", function()
	local w = H.world()
	local ns = w:load("Util.lua")
	w.env.HUDiniDB = {}
	local made = 0
	local function New() made = made + 1; return { n = made } end

	local s = ns.LoadSession("testSessions", New)
	H.eq(s.n, 1, "first session")
	H.eq(w.env.HUDiniDB.testSessions[KEY], s, "kept under the character key")

	-- No lastSeen: the game crashed or quit without PLAYER_LOGOUT.
	s = ns.LoadSession("testSessions", New)
	H.eq(s.n, 2, "never logged out: a new session")
	s.lastSeen = w.time - ns.RELOAD_GRACE
	H.eq(ns.LoadSession("testSessions", New), s, "seen within the grace")
	s.lastSeen = w.time - ns.RELOAD_GRACE - 1
	local s2 = ns.LoadSession("testSessions", New)
	H.eq(s2.n, 3, "seen too long ago: a new session")
	H.eq(w.env.HUDiniDB.testSessions[KEY], s2, "the new session is stored")
end)

H.test("the XP and feed sessions carry on over a /reload", function()
	local w = H.world()
	w:loadAddon()
	local db = w.env.HUDiniDB
	local xp, feed = db.xpSessions[KEY], db.feedSessions[KEY]
	H.ok(xp and feed, "both sessions made at login")
	local xpStart, feedStart = xp.start, feed.start
	w:fire("PLAYER_LOGOUT")

	-- The /reload: a new client, the same saved variables, 10 seconds on.
	local w2 = H.world()
	w2.env.HUDiniDB = db
	w2.time = w.time + 10
	w2:loadAddon()
	H.eq(db.xpSessions[KEY], xp, "XP session kept")
	H.eq(db.feedSessions[KEY], feed, "feed session kept")
	H.eq(xp.start, xpStart + 10, "the 10 s of the /reload are no XP session time")
	H.eq(feed.start, feedStart + 10, "nor feed session time")
end)

H.test("Detail prints a debug line as it is, with no prefix", function()
	local w = H.world()
	local ns = w:load("Util.lua")
	ns.Detail("  Money: 5")
	H.eq(w.printed[#w.printed], "  Money: 5")
end)
