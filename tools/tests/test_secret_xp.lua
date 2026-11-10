-- XP.lua, and the session key in Util.lua, when the game hides an answer
-- (TICK-0112). Each test first runs the value that WOULD change the bar,
-- plain, and checks that it does. Then it flags that same value secret and
-- checks that the bar does what it does for no answer, and throws nothing.
-- So a missing Plain() fails the test (the method of TICK-0110).

-- A logged-in character below max level. w.secret: the values
-- issecretvalue calls secret. w:Once(v) gives a stub that returns v and
-- flags the very next check secret if it asks about v (see
-- test_secret_core.lua). w.xp, w.max, w.rested: stubs for UnitXP,
-- UnitXPMax and GetXPExhaustion, set before the login reads them.
-- atLogin: a value that is secret only while the login runs (the login
-- reads XP more than once, so a one-check flag would go to the wrong read).
local function World(xp, max, rested, atLogin)
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v)
		if v == nil then return false end
		if w.secret[v] then return true end
		if w.arming then
			w.arming = false
			return v == w.armValue
		end
		return false
	end
	function w:Once(v)
		return function()
			self.arming, self.armValue = true, v
			return v
		end
	end
	local function Stub(v) return type(v) == "function" and v or function() return v end end
	w.xp, w.max, w.rested = Stub(xp or 0), Stub(max or 1000), Stub(rested)
	env.UnitXP = function() return w.xp() end
	env.UnitXPMax = function() return w.max() end
	env.GetXPExhaustion = function() return w.rested() end
	if atLogin then w.secret[atLogin] = true end
	local ns = w:loadAddon()
	if atLogin then w.secret[atLogin] = nil end
	function w:Set(x, m, r)
		if x ~= nil then self.xp = Stub(x) end
		if m ~= nil then self.max = Stub(m) end
		if r ~= nil then self.rested = Stub(r) end
	end
	-- XP comes in: the event, as the game sends it.
	function w:Gain(x, m)
		self:Set(x, m)
		self:fire("PLAYER_XP_UPDATE", "player")
	end
	-- The right text a minute and more later, with plain numbers again.
	function w:RateText(x, m)
		self:Set(x, m)
		self.time = self.time + 120
		ns.UpdateXP()
		return ns.GetBar("xp").right:GetText() or ""
	end
	return w, ns
end

local function HasRate(text) return text:find("/hr", 1, true) ~= nil end

--------------------------------------------------------------------------------
-- When to show
--------------------------------------------------------------------------------

H.test("a secret level is not max level", function()
	local w, ns = World()
	w.level = 63
	H.eq(ns.EarningXP(), false, "plain: past max, no XP")
	w.secret[63] = true
	H.eq(ns.EarningXP(), true, "secret: not known to be max")
end)

--------------------------------------------------------------------------------
-- The session: what came in
--------------------------------------------------------------------------------

H.test("a secret XP at login is not counted from", function()
	local w = World(333)
	w:Gain(400)
	H.eq(HasRate(w:RateText(400)), true, "plain: 67 gained, a rate")
	w = World(333, nil, nil, 333)
	w:Gain(400)
	H.eq(w:RateText(400), "", "secret: nothing gained")
end)

H.test("a secret XP maximum at login gives a level-up no gain", function()
	local w = World(900, 1001)
	w:Gain(50)
	H.eq(HasRate(w:RateText(50)), true, "plain: the rest of the level and 50 more")
	w = World(900, 1001, nil, 1001)
	w:Gain(50)
	H.eq(w:RateText(50), "", "secret: nothing gained")
end)

H.test("a secret XP in an update is no gain", function()
	local w = World(333)
	w:Gain(400)
	H.eq(HasRate(w:RateText(400)), true, "plain: a rate")
	w = World(333)
	w:Gain(w:Once(400))
	H.eq(w:RateText(400), "", "secret: nothing gained")
end)

H.test("a secret XP maximum in an update gives the next level-up no gain", function()
	local w = World(900, 1001)
	w:Gain(900)
	w:Gain(50)
	H.eq(HasRate(w:RateText(50)), true, "plain: a rate")
	w = World(900, 1001)
	w:Gain(900, w:Once(1001))
	w:Gain(50, 1001)
	H.eq(w:RateText(50), "", "secret: nothing gained")
end)

--------------------------------------------------------------------------------
-- The text
--------------------------------------------------------------------------------

H.test("a secret XP or maximum writes no XP text", function()
	local w, ns = World(401, 1003)
	local left = ns.GetBar("xp").left
	ns.UpdateXP()
	H.ok(left:GetText():find("401", 1, true), "plain: the XP")
	w.secret[401] = true
	ns.UpdateXP()
	H.eq(left:GetText(), "", "secret XP: none")
	w.secret[401], w.secret[1003] = nil, true
	ns.UpdateXP()
	H.eq(left:GetText(), "", "secret maximum: none")
end)

H.test("a secret rested XP writes no rested text", function()
	local w, ns = World(401, 1000, 251)
	w.env.HUDiniDB.showXPRate = false
	local right = ns.GetBar("xp").right
	ns.UpdateXP()
	H.eq(right:GetText(), "+25% rested", "plain: rested")
	w.secret[251] = true
	ns.UpdateXP()
	H.eq(right:GetText(), "", "secret: none")
end)

--------------------------------------------------------------------------------
-- Util.lua: the session key
--------------------------------------------------------------------------------

H.test("a secret GUID keys the session by name and realm", function()
	local w, ns = World()
	H.eq(ns.CharacterKey(), "Player-1-0001", "plain: the GUID")
	w.secret["Player-1-0001"] = true
	H.eq(ns.CharacterKey(), "Tester-Realm", "secret: name and realm")
end)
