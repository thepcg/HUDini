-- The target's name, level and info line (Bars.lua ns.UpdateTargetText) when
-- the game hides an answer (TICK-0110). Each secret test flags the very value
-- that WOULD change the text (a player: true; a boss: -1; a foe: true), so
-- only Plain() keeps the text as it is for an unknown answer: a missing
-- guard fails the test. The plain run of the same value comes first, to prove
-- that the value would change the text.

-- A logged-in world with a target. w.targetIsPlayer: UnitIsPlayer for the
-- target. w.attack: UnitCanAttack. w.kind: UnitCreatureType. w.secret: the
-- values issecretvalue calls secret.
local function World()
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.UnitIsPlayer = function(u) return u == "player" or (u == "target" and w.targetIsPlayer) or false end
	env.UnitCanAttack = function() return w.attack end
	env.UnitCreatureType = function() return w.kind end
	env.UnitName = function(u) return u == "player" and "Tester" or "Mira" end
	env.UnitFullName = function(u) if u == "target" then return "Mira", "Stormrage" end return "Tester", "Realm" end
	w:loadAddon()
	w.level, w.hasTarget = 10, true
	return w, w.ns.GetBar("targethealth")
end

local function Change(w)
	w:fire("PLAYER_TARGET_CHANGED")
end

H.test("a secret player answer: the name as for anyone else, never the realm", function()
	local w, bar = World()
	w.targetIsPlayer = true
	Change(w)
	H.eq(bar.name:GetText(), "Mira Stormrage", "plain: a player's name and realm")
	w.secret[true] = true
	Change(w)
	H.eq(bar.name:GetText(), "Mira", "secret: the plain name only")
end)

H.test("a secret boss level is not drawn as ??", function()
	local w, bar = World()
	w.level = -1
	Change(w)
	H.eq(bar.level:GetText(), "??", "plain: a boss")
	w.secret[-1] = true
	Change(w)
	H.eq(bar.level:GetText(), -1, "secret: the game's own value, as it came")
end)

H.test("a secret attack answer shows no creature type", function()
	local w, bar = World()
	w.attack, w.kind = true, "Beast"
	Change(w)
	H.eq(bar.info:GetText(), "Beast", "plain: a foe's type")
	w.secret[true] = true
	Change(w)
	H.eq(bar.info:GetText(), "", "secret: no type")
end)
