-- The target's level in the game's difficulty color (TICK-0101). Like the
-- game's own target frame: only for a target you can attack, from
-- C_PlayerInfo.GetContentDifficultyCreatureForPlayer and GetDifficultyColor.
-- Gold for a friend, a boss's "??", the switch off, and any answer that is
-- secret, missing or throws. What the colors look like needs a test sitting.

local GOLD = { 1, 0.82, 0 }

-- The game's five difficulties and the colors GetDifficultyColor gives.
-- The game's Fair yellow is (1, 0.82, 0), the same as gold
-- (Blizzard_FrameXMLBase/Constants.lua:198), so a test could not tell it
-- from the gold fallback: here Fair gets another yellow.
local COLORS = {
	[0] = { r = 0.50, g = 0.50, b = 0.50 }, -- Trivial: grey
	[1] = { r = 0.25, g = 0.75, b = 0.25 }, -- Easy: green
	[2] = { r = 1.00, g = 1.00, b = 0.10 }, -- Fair: yellow (not the game's)
	[3] = { r = 1.00, g = 0.50, b = 0.25 }, -- Difficult: orange
	[4] = { r = 1.00, g = 0.10, b = 0.10 }, -- Impossible: red
}

-- A logged-in world with a target. w.level is the target's level,
-- w.attack whether you can attack it, w.difficulty what the game answers.
-- o.noApi: no C_PlayerInfo call. o.throws: the call throws. w.secret: the
-- values the game hides. A secret test flags the very value that WOULD color
-- the level (level 10, difficulty 4, the attack answer true, each channel), so
-- only the guard keeps it gold: a missing guard fails the test.
local function World(o)
	o = o or {}
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.attack, w.difficulty = true, 1
	env.UnitCanAttack = function() return w.attack end
	env.UnitIsWildBattlePet = function() return w.pet == "wild" end
	env.UnitIsBattlePetCompanion = function() return w.pet == "companion" end
	if not o.noApi then
		env.C_PlayerInfo = { GetContentDifficultyCreatureForPlayer = function(unit)
			if o.throws then error("restricted") end
			if unit == "target" then return w.difficulty end
		end }
	end
	env.GetDifficultyColor = function(d) return COLORS[d] or COLORS[2] end
	local ns = w:loadAddon()
	w.level = 10
	w.hasTarget = true
	-- Record what the level text is told: the fake font string has no color.
	local level = ns.GetBar("targethealth").level
	rawset(level, "SetTextColor", function(_, r, g, b) w.color = { r, g, b } end)
	return w, ns
end

-- The level's color after a target change.
local function Color(w)
	w.color = nil
	w:fire("PLAYER_TARGET_CHANGED")
	return w.color
end

local function Same(got, want, msg)
	H.ok(got, (msg or "") .. ": no color set")
	for i = 1, 3 do
		H.ok(math.abs(got[i] - want[i]) < 1e-6,
			("%s: got %s,%s,%s"):format(msg or "", tostring(got[1]), tostring(got[2]), tostring(got[3])))
	end
end

H.test("each difficulty gives its color on a target you can attack", function()
	local w = World()
	for d = 0, 4 do
		w.difficulty = d
		local c = COLORS[d]
		Same(Color(w), { c.r, c.g, c.b }, "difficulty " .. d)
	end
end)

H.test("a target you cannot attack stays gold", function()
	local w = World()
	w.attack = false
	w.difficulty = 4
	Same(Color(w), GOLD, "friendly")
end)

H.test("a wild battle pet or a pet companion stays gold, as on the game's frame", function()
	local w = World()
	w.difficulty = 0
	for _, pet in ipairs({ "wild", "companion" }) do
		w.pet = pet
		Same(Color(w), GOLD, pet)
	end
end)

H.test("a missing level stays gold and throws nothing", function()
	local w = World()
	w.level, w.difficulty = nil, 4
	Same(Color(w), GOLD, "no level")
end)

H.test("a boss's ?? stays gold", function()
	local w = World()
	w.level, w.difficulty = -1, 4
	Same(Color(w), GOLD, "boss")
	H.eq(w.ns.GetBar("targethealth").level:GetText(), "??", "still ??")
end)

H.test("the switch off stays gold", function()
	local w = World()
	H.eq(w.env.HUDiniDB.colorTargetLevel, true, "on at the start")
	w.env.HUDiniDB.colorTargetLevel = false
	w.difficulty = 4
	Same(Color(w), GOLD, "off")
end)

H.test("a secret level, attack answer, difficulty or color stays gold and throws nothing", function()
	-- Orange's three channels differ, so a secret channel flags that one only.
	local cases = {
		{ "secret level 10", function(w) w.secret[10] = true end, 4 },
		{ "secret attack answer", function(w) w.secret[true] = true end, 4 },
		{ "secret difficulty 4", function(w) w.secret[4] = true end, 4 },
		{ "secret color table", function(w) w.secret[COLORS[4]] = true end, 4 },
		{ "secret r of orange", function(w) w.secret[COLORS[3].r] = true end, 3 },
		{ "secret g of orange", function(w) w.secret[COLORS[3].g] = true end, 3 },
		{ "secret b of orange", function(w) w.secret[COLORS[3].b] = true end, 3 },
	}
	for _, case in ipairs(cases) do
		local w = World()
		local c = COLORS[case[3]]
		w.difficulty = case[3]
		Same(Color(w), { c.r, c.g, c.b }, case[1] .. ": plain, it has its color")
		case[2](w)
		Same(Color(w), GOLD, case[1])
	end
end)

H.test("a missing or throwing API stays gold", function()
	local w = World({ noApi = true })
	Same(Color(w), GOLD, "no C_PlayerInfo")
	w = World({ throws = true })
	Same(Color(w), GOLD, "throws")
	w = World()
	w.env.GetDifficultyColor = nil
	Same(Color(w), GOLD, "no GetDifficultyColor")
	w.env.GetDifficultyColor = function() error("boom") end
	Same(Color(w), GOLD, "GetDifficultyColor throws")
end)

H.test("your level going up, or the target turning hostile, colors the level again", function()
	local w = World()
	w.difficulty = 4
	Color(w)
	w.difficulty = 3
	w.color = nil
	w:fire("UNIT_LEVEL", "player")
	Same(w.color, { 1, 0.5, 0.25 }, "after your level")
	w.attack = false
	w.color = nil
	w:fire("UNIT_FACTION", "target")
	Same(w.color, GOLD, "after a faction change")
	w.attack = true
	w.color = nil
	w:fire("UNIT_FACTION", "player")
	Same(w.color, { 1, 0.5, 0.25 }, "after your own faction change (a duel)")
end)
