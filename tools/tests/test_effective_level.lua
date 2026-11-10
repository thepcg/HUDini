-- The target's level is the one the game's own target frame shows
-- (TICK-0111): UnitEffectiveLevel, which a zone that scales levels or party
-- sync can raise or lower. When the effective level is secret, missing or
-- throws, the level is UnitLevel, as before. The "??" for a boss and the
-- gold rules stay. What it looks like needs a test sitting.

local GOLD = { 1, 0.82, 0 }
local RED = { 1, 0.1, 0.1 }

-- A logged-in world with a target you can attack. w.level is UnitLevel,
-- w.effective is UnitEffectiveLevel ("none" for no such API).
-- w.effectiveThrows: the call throws. w.secret: the values the game hides.
-- A secret test flags the very value that WOULD show (the effective level
-- 25), so only the guard keeps the UnitLevel: a missing guard fails the test.
local function World()
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.UnitCanAttack = function() return true end
	env.C_PlayerInfo = { GetContentDifficultyCreatureForPlayer = function() return 4 end }
	env.GetDifficultyColor = function(d)
		if d == 4 then return { r = RED[1], g = RED[2], b = RED[3] } end
	end
	env.UnitEffectiveLevel = function(unit)
		if w.effectiveThrows then error("restricted") end
		if unit == "target" then return w.effective end
	end
	local ns = w:loadAddon()
	w.level, w.effective = 10, 25
	w.hasTarget = true
	local level = ns.GetBar("targethealth").level
	rawset(level, "SetTextColor", function(_, r, g, b) w.color = { r, g, b } end)
	return w, ns
end

-- The level text and its color after a target change.
local function Shown(w, ns)
	w.color = nil
	w:fire("PLAYER_TARGET_CHANGED")
	return ns.GetBar("targethealth").level:GetText(), w.color
end

local function Same(got, want, msg)
	H.ok(got, (msg or "") .. ": no color set")
	for i = 1, 3 do
		H.ok(math.abs(got[i] - want[i]) < 1e-6,
			("%s: got %s,%s,%s"):format(msg or "", tostring(got[1]), tostring(got[2]), tostring(got[3])))
	end
end

H.test("a scaled target shows its effective level, in its difficulty color", function()
	local w, ns = World()
	local text, color = Shown(w, ns)
	H.eq(text, 25, "the effective level, not UnitLevel's 10")
	Same(color, RED, "difficulty color")
end)

H.test("an effective level that changes shows at UNIT_LEVEL", function()
	-- Party sync starts or stops with no target change.
	local w, ns = World()
	Shown(w, ns)
	w.effective = 12
	w:fire("UNIT_LEVEL", "target")
	H.eq(ns.GetBar("targethealth").level:GetText(), 12)
end)

H.test("a secret effective level shows UnitLevel and throws nothing", function()
	local w, ns = World()
	H.eq((Shown(w, ns)), 25, "plain: the effective level")
	w.secret[25] = true
	local text, color = Shown(w, ns)
	H.eq(text, 10, "the same 25, secret: UnitLevel")
	Same(color, RED, "still colored")
end)

H.test("a missing effective level shows UnitLevel", function()
	local w, ns = World()
	w.effective = nil
	H.eq((Shown(w, ns)), 10, "nil")
	w.env.UnitEffectiveLevel = nil
	w.effective = 25
	H.eq((Shown(w, ns)), 10, "no UnitEffectiveLevel")
end)

H.test("a throwing effective level shows UnitLevel", function()
	local w, ns = World()
	w.effectiveThrows = true
	local text, color = Shown(w, ns)
	H.eq(text, 10)
	Same(color, RED, "still colored")
end)

H.test("a boss's effective level of -1 shows ?? in gold", function()
	local w, ns = World()
	w.effective = -1
	local text, color = Shown(w, ns)
	H.eq(text, "??")
	Same(color, GOLD, "boss")
end)

H.test("a boss keeps its ?? in gold when the effective level is secret or missing", function()
	-- UnitLevel -1: the "??" must come from the fallback, not the effective level.
	local w, ns = World()
	w.level = -1
	local text, color = Shown(w, ns)
	H.eq(text, 25, "plain: the effective level")
	Same(color, RED, "plain: colored")
	w.secret[25] = true
	text, color = Shown(w, ns)
	H.eq(text, "??", "the same 25, secret: UnitLevel's ??")
	Same(color, GOLD, "secret: gold")
	w.secret[25] = nil
	w.effective = nil
	text, color = Shown(w, ns)
	H.eq(text, "??", "nil: UnitLevel's ??")
	Same(color, GOLD, "nil: gold")
	w.effective, w.effectiveThrows = 25, true
	text, color = Shown(w, ns)
	H.eq(text, "??", "throws: UnitLevel's ??")
	Same(color, GOLD, "throws: gold")
end)

H.test("a secret effective level and a secret UnitLevel stay gold and throw nothing", function()
	local w, ns = World()
	w.secret[25], w.secret[10] = true, true
	local text, color = Shown(w, ns)
	H.eq(text, 10, "the secret UnitLevel goes to the text as it is")
	Same(color, GOLD, "no plain level: gold")
end)
