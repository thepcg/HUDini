-- Health and power numbers on the bars (Bars.lua, TICK-0102). barNumbers
-- is "off", "percent", "number" or "both", on your health and power bars
-- and your target's. The game does all the maths: UnitHealthPercent and
-- UnitPowerPercent with CurveConstants.ScaleTo100 give the percent,
-- AbbreviateNumbers the short number. HUDini only hands each answer to
-- SetText or SetFormattedText. What it looks like needs a test sitting.

-- The fakes for the game calls the harness has no stub for. w.health,
-- w.power: what UnitHealth and UnitPower give, by unit. w.pct, w.powerPct:
-- the percents, by unit. w.asked: each call, with its arguments.
local CURVE = { name = "ScaleTo100" }

local function Short(v)
	if v >= 1000 then return ("%.1fk"):format(v / 1000) end
	return tostring(v)
end

local function World(setup)
	local w = H.world()
	local env = w.env
	w.secret = {}
	w.health = { player = 12345, target = 800 }
	w.power = { player = 4200, target = 300 }
	w.pct = { player = 87.6, target = 40.2 }
	w.powerPct = { player = 99.7, target = 15 }
	w.asked = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.CurveConstants = { ScaleTo100 = CURVE }
	env.UnitHealth = function(unit) return w.health[unit] or 0 end
	env.UnitPower = function(unit) return w.power[unit] or 0 end
	env.UnitHealthPercent = function(unit, predicted, curve)
		w.asked[#w.asked + 1] = { "health", unit, predicted, curve }
		return w.pct[unit] or 0
	end
	env.UnitPowerPercent = function(unit, ptype, unmodified, curve)
		w.asked[#w.asked + 1] = { "power", unit, ptype, unmodified, curve }
		return w.powerPct[unit] or 0
	end
	env.AbbreviateNumbers = function(v) return Short(v) end
	if setup then setup(w) end
	local ns = w:loadAddon()
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	return w, ns
end

-- The four texts: your health, your power, the target's health and power.
-- The target's power number is at the middle of its own bar (TICK-0126).
local function Texts(ns)
	return {
		ns.GetBar("health").numbers:GetText(),
		ns.GetBar("power").numbers:GetText(),
		ns.GetBar("targethealth").numbers:GetText(),
		ns.GetBar("targetpower").numbers:GetText(),
	}
end

local function Shows(w, ns, mode, want, msg)
	w.env.HUDiniDB.barNumbers = mode
	w:fire("PLAYER_TARGET_CHANGED")
	local got = Texts(ns)
	local names = { "your health", "your power", "target health", "target power" }
	for i = 1, 4 do H.eq(got[i], want[i], msg .. ": " .. names[i]) end
end

H.test("on by default, as a percent", function()
	local w, ns = World()
	H.eq(w.env.HUDiniDB.barNumbers, "percent", "the default")
	H.eq(Texts(ns)[1], "87%", "your health")
end)

H.test("each format with plain numbers", function()
	local w, ns = World()
	Shows(w, ns, "percent", { "87%", "99%", "40%", "15%" }, "percent")
	Shows(w, ns, "number", { "12.3k", "4.2k", "800", "300" }, "number")
	Shows(w, ns, "both", { "12.3k (87%)", "4.2k (99%)", "800 (40%)", "300 (15%)" }, "both")
	Shows(w, ns, "off", { "", "", "", "" }, "off")
end)

H.test("an unknown setting shows no number", function()
	local w, ns = World()
	Shows(w, ns, "bogus", { "", "", "", "" }, "bogus")
	Shows(w, ns, nil, { "", "", "", "" }, "nil")
end)

H.test("the percent rounds down, so 100% means full", function()
	local w, ns = World()
	w.pct.player = 99.9
	w:fire("UNIT_HEALTH", "player")
	H.eq(Texts(ns)[1], "99%", "99.9 is not full")
	w.pct.player = 100
	w:fire("UNIT_HEALTH", "player")
	H.eq(Texts(ns)[1], "100%", "full")
end)

H.test("the game's curve scales the percent, and the power type goes with it", function()
	local w = World()
	local health, power = 0, 0
	for _, a in ipairs(w.asked) do
		if a[1] == "health" then
			health = health + 1
			H.eq(a[3], true, "predicted health")
			H.ok(rawequal(a[4], CURVE), "health: CurveConstants.ScaleTo100")
		else
			power = power + 1
			H.eq(a[3], 0, "power type: mana")
			H.eq(a[4], false, "power: not unmodified")
			H.ok(rawequal(a[5], CURVE), "power: CurveConstants.ScaleTo100")
		end
	end
	H.ok(health > 0 and power > 0, "both asked")
end)

-- A secret stands for itself here: a table that throws on any maths,
-- compare, join, length, call or field read. Each one must reach the
-- widget call as it came, the very same value.
local function Poison(name)
	local function no() error("maths on the secret " .. name, 2) end
	return setmetatable({}, {
		__add = no, __sub = no, __mul = no, __div = no, __mod = no, __pow = no,
		__unm = no, __concat = no, __len = no, __eq = no, __lt = no, __le = no,
		__index = no, __newindex = no, __call = no,
	})
end

-- Record what each number text is handed, in place of the fake widget's
-- own SetText and SetFormattedText.
local function Record(ns)
	local got = {}
	local texts = {
		health = ns.GetBar("health").numbers, power = ns.GetBar("power").numbers,
		target = ns.GetBar("targethealth").numbers, targetpower = ns.GetBar("targetpower").numbers,
	}
	for key, fs in pairs(texts) do
		rawset(fs, "SetText", function(_, v) got[key] = { v } end)
		rawset(fs, "SetFormattedText", function(_, f, ...) got[key] = { f, ... } end)
	end
	return got
end

H.test("a secret goes to the widget unchanged, with no maths on it", function()
	local HP, MP, THP, TMP = Poison("health"), Poison("power"), Poison("target health"), Poison("target power")
	local SHORT, PCT = Poison("short"), Poison("percent")
	local w, ns = World(function(w)
		for _, v in ipairs({ HP, MP, THP, TMP, SHORT, PCT }) do w.secret[v] = true end
		w.health = { player = HP, target = THP }
		w.power = { player = MP, target = TMP }
		w.pct = { player = PCT, target = PCT }
		w.powerPct = { player = PCT, target = PCT }
	end)
	local gave = {}
	w.env.AbbreviateNumbers = function(v)
		gave[#gave + 1] = v
		return SHORT
	end
	local got = Record(ns)

	w.env.HUDiniDB.barNumbers = "number"
	w:fire("PLAYER_TARGET_CHANGED")
	local seen = {}
	for _, v in ipairs(gave) do seen[v] = true end
	for _, v in ipairs({ HP, MP, THP, TMP }) do
		H.ok(seen[v], "number: the secret itself goes to AbbreviateNumbers")
	end
	for _, key in ipairs({ "health", "power", "target", "targetpower" }) do
		H.ok(rawequal(got[key][1], SHORT), "number: " .. key .. " gets the game's text")
	end

	w.env.HUDiniDB.barNumbers = "percent"
	w:fire("PLAYER_TARGET_CHANGED")
	for _, key in ipairs({ "health", "power", "target", "targetpower" }) do
		H.eq(got[key][1], "%d%%", "percent: " .. key .. " format")
		H.ok(rawequal(got[key][2], PCT), "percent: " .. key .. " gets the secret")
	end

	w.env.HUDiniDB.barNumbers = "both"
	w:fire("PLAYER_TARGET_CHANGED")
	for _, key in ipairs({ "health", "power", "target", "targetpower" }) do
		H.eq(got[key][1], "%s (%d%%)", "both: " .. key .. " format")
		H.ok(rawequal(got[key][2], SHORT) and rawequal(got[key][3], PCT),
			"both: " .. key .. " gets both secrets")
	end
end)

H.test("a missing or throwing game call shows no number, and throws nothing", function()
	local w, ns = World()
	w.env.CurveConstants = nil
	Shows(w, ns, "percent", { "", "", "", "" }, "no curve")
	w.env.CurveConstants = { ScaleTo100 = CURVE }
	w.env.UnitHealthPercent = nil
	w.env.UnitPowerPercent = function() error("refused") end
	Shows(w, ns, "percent", { "", "", "", "" }, "no or a refused percent")
	w.env.AbbreviateNumbers = nil
	Shows(w, ns, "number", { "", "", "", "" }, "no AbbreviateNumbers")
	w.env.AbbreviateNumbers = function() error("refused") end
	Shows(w, ns, "both", { "", "", "", "" }, "a refused AbbreviateNumbers")
end)

H.test("Both shows the half the game did give", function()
	-- An old AbbreviateNumbers compares the number: on a secret it throws.
	local w, ns = World()
	w.env.AbbreviateNumbers = function() error("compare on a secret") end
	Shows(w, ns, "both", { "87%", "99%", "40%", "15%" }, "no number: the percent")
	w.env.AbbreviateNumbers = function(v) return Short(v) end
	w.env.UnitHealthPercent, w.env.UnitPowerPercent = nil, nil
	Shows(w, ns, "both", { "12.3k", "4.2k", "800", "300" }, "no percent: the number")
end)

H.test("a widget that refuses the value shows no number", function()
	local w, ns = World()
	local fs = ns.GetBar("health").numbers
	H.eq(fs:GetText(), "87%", "before")
	rawset(fs, "SetFormattedText", function() error("refused") end)
	w:fire("UNIT_HEALTH", "player")
	H.eq(fs:GetText(), "", "percent: empty, not the old text")
	-- Number: SetText refuses the game's text, but not the empty one.
	rawset(fs, "SetFormattedText", nil)
	w.env.HUDiniDB.barNumbers = "both"
	w:fire("UNIT_HEALTH", "player")
	H.eq(fs:GetText(), "12.3k (87%)", "before")
	local set = fs.SetText
	rawset(fs, "SetText", function(self, v)
		if v ~= "" then error("refused") end
		return set(self, v)
	end)
	w.env.HUDiniDB.barNumbers = "number"
	w:fire("UNIT_HEALTH", "player")
	H.eq(fs:GetText(), "", "number: empty, not the old text")
end)

H.test("Dead takes the place of the number", function()
	local dead = {}
	local w, ns = World(function(w)
		w.env.UnitIsDeadOrGhost = function(unit) return dead[unit] == true end
	end)
	dead.player, dead.target = true, true
	w:fire("PLAYER_TARGET_CHANGED")
	local t = Texts(ns)
	H.eq(t[1], "", "your health")
	H.eq(t[3], "", "target health")
	H.eq(t[4], "", "target power")
	H.eq(ns.GetBar("health").state:GetText(), ns.Text("bars.state.dead"), "the word")
	H.eq(t[2], "99%", "your power still shows")
	dead.player, dead.target = nil, nil
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(Texts(ns)[1], "87%", "alive again")
end)

-- The target's power is its own bar (TICK-0126), so its number must hear
-- of the word on the health bar even when only the health event comes
-- (ns.UpdateBars does the power after the health).
H.test("the target dies on a health event alone: its power number goes too", function()
	local dead = false
	local w, ns = World(function(w)
		w.env.UnitIsDeadOrGhost = function(unit) return unit == "target" and dead end
	end)
	local before = Texts(ns)[4]
	H.ok(before ~= "", "alive: the number shows")
	dead = true
	w:fire("UNIT_HEALTH", "target")
	H.eq(Texts(ns)[4], "", "dead: no target power number")
	dead = false
	w:fire("UNIT_HEALTH", "target")
	H.eq(Texts(ns)[4], before, "alive again: back")
end)

H.test("your cast bar hides your power number while it shows", function()
	local casting = false
	local w, ns = World(function(w)
		w.env.UnitCastingDuration = function(unit)
			if unit == "player" and casting then return {} end
		end
		w.env.UnitCastingInfo = function(unit)
			if unit == "player" and casting then return "Fireball" end
		end
	end)
	local base = ns.casts.playercast.base
	base.SetTimerDuration = function(_, d) assert(d ~= nil) end
	H.eq(Texts(ns)[2], "99%", "no cast")
	casting = true
	w:fire("UNIT_SPELLCAST_START", "player")
	H.eq(ns.casts.playercast.holder:IsShown(), true, "the cast bar shows")
	H.eq(Texts(ns)[2], "", "casting: no power number")
	casting = false
	w:fire("UNIT_SPELLCAST_STOP", "player")
	H.eq(Texts(ns)[2], "99%", "the cast ends: back")
end)

H.test("the target's cast bar hides the target's power number while it shows", function()
	local casting = false
	local w, ns = World(function(w)
		w.env.UnitCastingDuration = function(unit)
			if unit == "target" and casting then return {} end
		end
		w.env.UnitCastingInfo = function(unit)
			if unit == "target" and casting then return "Shadow Bolt" end
		end
	end)
	local tc = ns.casts.targetcast
	tc.base.SetTimerDuration = function(_, d) assert(d ~= nil) end
	tc.hot.SetTimerDuration = tc.base.SetTimerDuration
	local before = Texts(ns)[4]
	H.ok(before ~= "", "no cast: the number shows")
	casting = true
	w:fire("UNIT_SPELLCAST_START", "target")
	H.eq(tc.holder:IsShown(), true, "the cast bar shows")
	H.eq(Texts(ns)[4], "", "casting: no target power number")
	H.eq(Texts(ns)[2], "99%", "your power number is not touched")
	w:fire("UNIT_POWER_UPDATE", "target")
	H.eq(Texts(ns)[4], "", "a power tick under the cast: still none")
	casting = false
	w:fire("UNIT_SPELLCAST_STOP", "target")
	H.eq(Texts(ns)[4], before, "the cast ends: back")
end)

H.test("no target, or a target with no power: no target number", function()
	local w, ns = World()
	w.env.UnitPowerMax = function(unit) if unit == "target" then return 0 end return 100 end
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(Texts(ns)[4], "", "no power")
	H.eq(Texts(ns)[3], "40%", "the health still shows")
	w.hasTarget = false
	w:fire("PLAYER_TARGET_CHANGED")
	local t = Texts(ns)
	H.eq(t[3], "", "no target: no health number")
	H.eq(t[4], "", "no target: no power number")
end)

H.test("the name stops short of the health number; line 2 runs to the bar's end", function()
	local w, ns = World()
	local bar = ns.GetBar("targethealth")
	local _, to = bar.name:GetPoint(2)
	H.eq(to, bar.numbers, "the name stops at the health number")
	-- The power number is on the target's power bar (TICK-0126).
	_, to = bar.info:GetPoint(2)
	H.eq(to, bar, "line 2 runs to the bar's end")
	w.env.HUDiniDB.barNumbers = "off"
	w:fire("PLAYER_TARGET_CHANGED")
	_, to = bar.name:GetPoint(2)
	H.eq(to, bar, "off: the name runs to the bar's end")
	_, to = bar.info:GetPoint(2)
	H.eq(to, bar, "off: line 2 runs to the bar's end")
end)
