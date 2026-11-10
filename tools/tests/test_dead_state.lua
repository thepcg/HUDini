-- Dead, Ghost and Offline on the health bars (TICK-0106). A unit in one of
-- these states gets a full gray bar with the word on it; a living unit gets
-- its normal fill, color and no word. Only a plain true counts: a secret, a
-- throw or a missing API draws the normal bar and throws nothing. Offline
-- is asked only of a player. What it looks like needs a test sitting.

local GRAY = { 0.5, 0.5, 0.5 }

-- A logged-in world with a target. w.dead, w.ghost, w.offline name the
-- units ("player", "target") in each state; w.npc makes the target an NPC.
-- w.secret: values the game hides. A secret test flags the very value that
-- WOULD draw the word (true for dead or ghost, false for connected), so only
-- the guard keeps the bar normal: a missing guard fails the test.
local function World()
	local w = H.world()
	local env = w.env
	w.secret = {}
	w.dead, w.ghost, w.offline = {}, {}, {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.UnitIsDeadOrGhost = function(unit) return w.dead[unit] == true or w.ghost[unit] == true end
	env.UnitIsGhost = function(unit) return w.ghost[unit] == true end
	env.UnitIsConnected = function(unit) return not w.offline[unit] end
	env.UnitIsPlayer = function(unit) return unit == "player" or (unit == "target" and not w.npc) end
	local ns = w:loadAddon()
	w.hasTarget = true
	-- Record the color each bar is told: the fake bar keeps none.
	for _, key in ipairs({ "health", "targethealth" }) do
		local bar = ns.GetBar(key)
		rawset(bar, "SetStatusBarColor", function(self, r, g, b) w[key] = { r, g, b } end)
	end
	return w, ns
end

local function Bar(ns, key) return ns.GetBar(key) end
local function Word(ns, key) return Bar(ns, key).state:GetText() end

local function Same(got, want, msg)
	H.ok(got, (msg or "") .. ": no color set")
	for i = 1, 3 do
		H.ok(math.abs(got[i] - want[i]) < 1e-6,
			("%s: got %s,%s,%s"):format(msg or "", tostring(got[1]), tostring(got[2]), tostring(got[3])))
	end
end

-- The bar is full and gray with the word on it.
local function Stated(w, ns, key, word, msg)
	H.eq(Word(ns, key), ns.Text("bars.state." .. word), msg .. ": word")
	local h = Bar(ns, key).__h
	H.eq(h.max, 1, msg .. ": full (max)")
	H.eq(h.value, 1, msg .. ": full (value)")
	Same(w[key], GRAY, msg .. ": gray")
end

-- The bar has its normal fill and color, and no word.
local function Normal(w, ns, key, msg)
	H.eq(Word(ns, key), "", msg .. ": no word")
	local h = Bar(ns, key).__h
	H.eq(h.max, 100, msg .. ": normal max")
	H.eq(h.value, 100, msg .. ": normal value")
	if w[key] then
		H.ok(math.abs(w[key][1] - GRAY[1]) > 1e-6 or math.abs(w[key][2] - GRAY[2]) > 1e-6,
			msg .. ": not gray")
	end
end

H.test("the three words are level 0 texts", function()
	local _, ns = World()
	H.eq(ns.Text("bars.state.dead"), "Dead")
	H.eq(ns.Text("bars.state.ghost"), "Ghost")
	H.eq(ns.Text("bars.state.offline"), "Offline")
end)

H.test("a living you and a living target draw no word", function()
	local w, ns = World()
	H.eq(w.env.HUDiniDB.showDeadState, true, "on by default")
	w:fire("PLAYER_TARGET_CHANGED")
	Normal(w, ns, "health", "you")
	Normal(w, ns, "targethealth", "target")
end)

H.test("a dead target: Dead on a full gray bar; alive again, the normal bar", function()
	local w, ns = World()
	w:fire("PLAYER_TARGET_CHANGED")
	local living = w.targethealth
	w.dead.target = true
	w:fire("UNIT_HEALTH", "target")
	Stated(w, ns, "targethealth", "dead", "dead target")
	Normal(w, ns, "health", "you stay normal")
	w.dead.target = nil
	w:fire("UNIT_HEALTH", "target")
	Normal(w, ns, "targethealth", "alive again")
	Same(w.targethealth, living, "its reaction color comes back")
end)

H.test("you die, then release: Dead, then Ghost, then back to normal", function()
	local w, ns = World()
	w:fire("PLAYER_TARGET_CHANGED")
	w.dead.player = true
	w:fire("PLAYER_DEAD")
	Stated(w, ns, "health", "dead", "dead")
	w.dead.player, w.ghost.player = nil, true
	w:fire("PLAYER_ALIVE")
	Stated(w, ns, "health", "ghost", "ghost")
	w.ghost.player = nil
	w:fire("PLAYER_UNGHOST")
	Normal(w, ns, "health", "back in your body")
	Same(w.health, ns.BarColor("health"), "your health color comes back")
end)

H.test("an offline player target: Offline; an NPC that is not connected: no word", function()
	local w, ns = World()
	w.offline.target = true
	w:fire("PLAYER_TARGET_CHANGED")
	Stated(w, ns, "targethealth", "offline", "offline player")
	w.offline.target = nil
	w:fire("UNIT_CONNECTION", "target")
	Normal(w, ns, "targethealth", "back online")
	w.npc, w.offline.target = true, true
	w:fire("PLAYER_TARGET_CHANGED")
	Normal(w, ns, "targethealth", "an NPC is never offline")
end)

H.test("a target that stands up with no health change loses its word", function()
	-- An enemy hunter's Feign Death ends with a flags change only.
	local w, ns = World()
	w.dead.target = true
	w:fire("PLAYER_TARGET_CHANGED")
	Stated(w, ns, "targethealth", "dead", "feigning")
	w.dead.target = nil
	w:fire("UNIT_FLAGS", "target")
	Normal(w, ns, "targethealth", "stood up")
end)

H.test("the word on the target sits at the top line's end, and the name stops short of it", function()
	local w, ns = World()
	local bar = Bar(ns, "targethealth")
	w:fire("PLAYER_TARGET_CHANGED")
	-- The health number (TICK-0102, on by default) has the line's end.
	local _, to = bar.name:GetPoint(2)
	H.eq(to, bar.numbers, "living: the name runs to the health number")
	w.dead.target = true
	w:fire("UNIT_HEALTH", "target")
	_, to = bar.name:GetPoint(2)
	H.eq(to, bar.state, "dead: the name stops at the word")
	w.dead.target = nil
	w:fire("UNIT_HEALTH", "target")
	_, to = bar.name:GetPoint(2)
	H.eq(to, bar.numbers, "alive again: the name runs to the number")
	-- With the numbers off, the name runs to the bar's end.
	w.env.HUDiniDB.barNumbers = "off"
	w:fire("PLAYER_TARGET_CHANGED")
	_, to = bar.name:GetPoint(2)
	H.eq(to, bar, "numbers off: the name runs to the bar's end")
end)

H.test("a secret dead answer draws no word and throws nothing", function()
	-- The true that would draw it, flagged secret.
	local w, ns = World()
	w.dead.target = true
	w:fire("PLAYER_TARGET_CHANGED")
	Stated(w, ns, "targethealth", "dead", "plain dead")
	w.secret[true] = true
	w:fire("UNIT_HEALTH", "target")
	Normal(w, ns, "targethealth", "the same dead, secret")
end)

H.test("a secret ghost answer draws no word and throws nothing", function()
	-- Plain first, then secret. UnitIsDeadOrGhost is secret too.
	local w, ns = World()
	w.ghost.player = true
	w:fire("PLAYER_ALIVE")
	Stated(w, ns, "health", "ghost", "plain ghost")
	w.secret[true] = true
	w:fire("PLAYER_ALIVE")
	Normal(w, ns, "health", "the same ghost, secret")
end)

H.test("a secret connected answer draws no word and throws nothing", function()
	-- The false that would draw Offline, flagged secret.
	local w, ns = World()
	w.offline.target = true
	w:fire("PLAYER_TARGET_CHANGED")
	Stated(w, ns, "targethealth", "offline", "plain offline")
	w.secret[false] = true
	w:fire("UNIT_CONNECTION", "target")
	Normal(w, ns, "targethealth", "the same offline, secret")
end)

H.test("a ghost with only a secret UnitIsGhost is not called a ghost", function()
	-- UnitIsGhost hidden, UnitIsDeadOrGhost plain: the bar says Dead, the
	-- one thing the game told us.
	local w, ns = World()
	w.ghost.player = true
	w.env.UnitIsGhost = function() return "hidden" end
	w.secret.hidden = true
	w:fire("PLAYER_ALIVE")
	Stated(w, ns, "health", "dead", "secret ghost answer")
end)

H.test("a throw or a missing API draws only what the game did answer", function()
	-- UnitIsGhost throws, then is missing: a ghost reads Dead, from the plain
	-- UnitIsDeadOrGhost. (Alerts.lua asks UnitIsDeadOrGhost and
	-- UnitIsConnected outside a pcall, so only UnitIsGhost throws here.)
	local w, ns = World()
	w.ghost.player = true
	w.env.UnitIsGhost = function() error("restricted") end
	w:fire("PLAYER_TARGET_CHANGED")
	Stated(w, ns, "health", "dead", "you: UnitIsGhost throws")
	w.env.UnitIsGhost = nil
	w:fire("PLAYER_ALIVE")
	Stated(w, ns, "health", "dead", "you: no UnitIsGhost")
end)

H.test("the switch off draws no word", function()
	local w, ns = World()
	w.dead.target, w.ghost.player = true, true
	w:fire("PLAYER_TARGET_CHANGED")
	Stated(w, ns, "targethealth", "dead", "on")
	Stated(w, ns, "health", "ghost", "on")
	w.env.HUDiniDB.showDeadState = false
	w:fire("UNIT_HEALTH", "target")
	Normal(w, ns, "targethealth", "off")
	Normal(w, ns, "health", "off")
end)

H.test("losing the target drops its word", function()
	local w, ns = World()
	w.dead.target = true
	w:fire("PLAYER_TARGET_CHANGED")
	Stated(w, ns, "targethealth", "dead", "dead target")
	w.hasTarget = false
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(Word(ns, "targethealth"), "", "no target: no word")
	H.eq(Bar(ns, "targethealth").stateShown, false, "no target: not shown")
end)

H.test("a texture swap keeps the gray", function()
	local w, ns = World()
	w.ghost.player = true
	w:fire("PLAYER_ALIVE")
	w.health = nil
	ns.ApplyTexture()
	Same(w.health, GRAY, "after the swap")
end)
