-- Absorbs and incoming heals on your health bar and the target's (TICK-0120,
-- D-026). The game's calculator gives every amount, and every amount is
-- secret in a fight. Here each amount is a tripwire: a table whose every
-- Lua operation (sum, compare, join, index, length, call) records a
-- violation and throws. A test passes only if each amount reaches its
-- part's SetValue as the very same table, with no violation. What the
-- parts look like needs the game.

local MODES = { "SetIncomingHealClampMode", "SetDamageAbsorbClampMode", "SetHealAbsorbClampMode",
	"SetHealAbsorbMode", "SetMaximumHealthMode" }

-- A logged-in world with a target and the game's calculator. Options:
-- o.noApi: the client has no calculator; o.before(w): runs before load.
local function World(o)
	o = o or {}
	local w = H.world()
	local env = w.env
	w.violations = {}
	w.secret = {}
	w.calls = {}
	w.calcs = {}
	w.dead = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.UnitIsDeadOrGhost = function(unit) return w.dead[unit] == true end
	env.Enum.UnitIncomingHealClampMode = { MissingHealth = 11 }
	env.Enum.UnitDamageAbsorbClampMode = { MissingHealth = 12 }
	env.Enum.UnitHealAbsorbClampMode = { CurrentHealth = 13 }
	env.Enum.UnitHealAbsorbMode = { ReducedByIncomingHeals = 14 }
	env.Enum.UnitMaximumHealthMode = { Default = 15 }

	local trip = { __tostring = function() return "<secret>" end }
	for _, mm in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm",
			"__lt", "__le", "__eq", "__concat", "__len", "__call", "__index", "__newindex" }) do
		trip[mm] = function()
			table.insert(w.violations, mm)
			error("Lua touched a secret amount: " .. mm, 2)
		end
	end
	-- A secret amount, named for the messages.
	function w.Secret()
		local t = setmetatable({}, trip)
		w.secret[t] = true
		return t
	end
	-- Each unit's amounts, as the calculator gives them.
	w.amounts = {}
	for _, unit in ipairs({ "player", "target" }) do
		w.amounts[unit] = {
			max = w.Secret(), total = w.Secret(), mine = w.Secret(), others = w.Secret(),
			healClamped = w.Secret(), shield = w.Secret(), over = w.Secret(),
			absorb = w.Secret(), overAbsorb = w.Secret(),
		}
	end

	if not o.noApi then
		env.CreateUnitHealPredictionCalculator = function()
			local c = { modes = {} }
			for _, m in ipairs(MODES) do c[m] = function(self, v) self.modes[m] = v end end
			local function A(self) return w.amounts[self.unit] end
			function c:GetMaximumHealth()
				if w.throwMax then error("no maximum here") end
				return A(self).max
			end
			function c:GetIncomingHeals()
				local a = A(self)
				return a.total, a.mine, a.others, a.healClamped
			end
			function c:GetDamageAbsorbs()
				if w.throwShield then error("no shield here") end
				return A(self).shield, A(self).over
			end
			function c:GetHealAbsorbs() return A(self).absorb, A(self).overAbsorb end
			table.insert(w.calcs, c)
			return c
		end
		env.UnitGetDetailedHealPrediction = function(unit, healer, calc)
			if w.throwPredict then error("no prediction here") end
			table.insert(w.calls, { unit = unit, healer = healer, calc = calc })
			calc.unit = unit
		end
	end
	if o.before then o.before(w) end
	local ns = w:loadAddon()
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	return w, ns
end

local function P(ns, key) return ns.GetBar(key).predict end

local function NoViolation(w, msg)
	H.eq(#w.violations, 0, (msg or "") .. ": Lua touched an amount (" .. table.concat(w.violations, ", ") .. ")")
end

-- Each part holds its unit's amount, out of its unit's maximum health.
local function Drawn(w, ns, key, unit, msg)
	local p, a = P(ns, key), w.amounts[unit]
	for part, amount in pairs({ myHeal = a.mine, otherHeal = a.others, shield = a.shield, healAbsorb = a.absorb }) do
		local h = p[part].__h
		H.ok(rawequal(h.value, amount), ("%s: %s holds its amount"):format(msg, part))
		H.ok(rawequal(h.max, a.max), ("%s: %s is out of the maximum health"):format(msg, part))
		H.eq(h.min, 0, ("%s: %s starts at 0"):format(msg, part))
	end
end

-- Every part empty.
local function Empty(ns, key, msg)
	local p = P(ns, key)
	for _, part in ipairs({ "myHeal", "otherHeal", "shield", "healAbsorb" }) do
		H.eq(p[part].__h.value, 0, ("%s: %s is empty"):format(msg, part))
		H.eq(p[part].__h.max, 1, ("%s: %s max"):format(msg, part))
	end
	H.eq(p.overShield:GetAlpha(), 0, msg .. ": no shield glow")
	H.eq(p.overHealAbsorb:GetAlpha(), 0, msg .. ": no heal absorb glow")
end

H.test("both health bars get four parts, a clip frame and two glows, on by default", function()
	local w, ns = World()
	for _, key in ipairs({ "health", "targethealth" }) do
		local bar, p = ns.GetBar(key), P(ns, key)
		H.ok(type(p) == "table", key .. ": parts made")
		H.eq(p.clip.__h.clips, true, key .. ": the clip frame clips")
		H.eq(p.clip:GetFrameLevel(), bar:GetFrameLevel() + 1, key .. ": clip above the fill")
		for _, part in ipairs({ "myHeal", "otherHeal", "shield", "healAbsorb" }) do
			H.eq(p[part]:GetFrameLevel(), bar:GetFrameLevel() + 2, key .. ": " .. part .. " level")
		end
		H.eq(p.glows:GetFrameLevel(), bar:GetFrameLevel() + 2, key .. ": glows level")
		H.ok(p.glows.__h.clips ~= true, key .. ": the glows are not clipped")
		-- In the clip frame, so a long part stays inside the bar.
		H.ok(p.clip:GetParent() == bar, key .. ": the clip frame is the bar's")
		for _, part in ipairs({ "myHeal", "otherHeal", "shield", "healAbsorb" }) do
			H.ok(p[part]:GetParent() == p.clip, key .. ": " .. part .. " is in the clip frame")
		end
		H.ok(p.glows:GetParent() == bar, key .. ": the glows frame is the bar's")
		H.ok(p.overShield:GetParent() == p.glows and p.overHealAbsorb:GetParent() == p.glows,
			key .. ": the glows are in the glows frame, not clipped")
		-- The heal absorb eats into the fill: it fills leftward.
		H.eq(p.healAbsorb:GetReverseFill(), true, key .. ": the heal absorb fills leftward")
		for _, part in ipairs({ "myHeal", "otherHeal", "shield" }) do
			H.eq(p[part]:GetReverseFill(), false, key .. ": " .. part .. " fills rightward")
		end
		H.eq(bar:GetReverseFill(), false, key .. ": the health fill runs rightward")
	end
	H.eq(#w.calcs, 2, "one calculator per unit")
	H.ok(w.calcs[1] ~= w.calcs[2], "not shared")
	for _, c in ipairs(w.calcs) do
		H.eq(c.modes.SetIncomingHealClampMode, 11, "heals fill the missing health")
		H.eq(c.modes.SetDamageAbsorbClampMode, 12, "shields fill the missing health")
		H.eq(c.modes.SetHealAbsorbClampMode, 13, "a heal absorb fills the health there is")
		H.eq(c.modes.SetHealAbsorbMode, 14, "heal absorbs and heals cancel out")
		H.eq(c.modes.SetMaximumHealthMode, 15, "the default maximum")
	end
	local found
	for _, m in ipairs(ns.ModuleReport()) do
		if m.name == "healprediction" then found = m end
	end
	H.ok(found and found.on, "the module is on")
	H.eq(found.note, nil, "no note")
end)

H.test("the text stays above the parts", function()
	local _, ns = World()
	local health, target = ns.GetBar("health"), ns.GetBar("targethealth")
	H.ok(health.textLayer:GetFrameLevel() > P(ns, "health").myHeal:GetFrameLevel(), "your health text is above")
	-- The target's power is its own bar now (TICK-0126), not over the parts.
	H.eq(target.power, nil, "no power inside the target's health bar")
	H.ok(target.textLayer:GetFrameLevel() > P(ns, "targethealth").glows:GetFrameLevel(), "the target's text is above")
end)

H.test("the chain: heals start at the fill's end, the heal absorb ends there", function()
	local _, ns = World()
	for _, key in ipairs({ "health", "targethealth" }) do
		local bar, p = ns.GetBar(key), P(ns, key)
		local function From(part, before)
			local tex = before:GetStatusBarTexture()
			local a1, to1, r1 = p[part]:GetPoint(1)
			local a2, to2, r2 = p[part]:GetPoint(2)
			H.eq(p[part]:GetNumPoints(), 2, key .. ": " .. part .. " points")
			H.eq(a1 .. r1 .. a2 .. r2, "TOPLEFTTOPRIGHTBOTTOMLEFTBOTTOMRIGHT", key .. ": " .. part .. " left end")
			H.ok(to1 == tex and to2 == tex, key .. ": " .. part .. " on the fill before it")
		end
		From("myHeal", bar)
		From("otherHeal", p.myHeal)
		From("shield", p.otherHeal)
		local tex = bar:GetStatusBarTexture()
		local a1, to1, r1 = p.healAbsorb:GetPoint(1)
		local a2, to2, r2 = p.healAbsorb:GetPoint(2)
		H.eq(a1 .. r1 .. a2 .. r2, "TOPRIGHTTOPRIGHTBOTTOMRIGHTBOTTOMRIGHT", key .. ": heal absorb right end")
		H.ok(to1 == tex and to2 == tex, key .. ": heal absorb on the health fill's end")
		-- A new bar texture puts the chain back.
		p.myHeal:ClearAllPoints()
		ns.ApplyTexture()
		From("myHeal", bar)
	end
end)

H.test("each amount goes straight to its part: no Lua sum, compare or join", function()
	local w, ns = World()
	w:fire("UNIT_HEALTH", "player")
	w:fire("UNIT_HEALTH", "target")
	NoViolation(w, "after the health ticks")
	Drawn(w, ns, "health", "player", "you")
	Drawn(w, ns, "targethealth", "target", "target")
	local last = w.calls[#w.calls]
	H.eq(last.healer, "player", "your heals count as yours")
	H.ok(last.calc == P(ns, last.unit == "player" and "health" or "targethealth").calc, "its own calculator")
end)

H.test("the three game events redraw the right bar", function()
	local w, ns = World()
	for _, event in ipairs({ "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" }) do
		for _, unit in ipairs({ "player", "target" }) do
			local key = unit == "player" and "health" or "targethealth"
			local a = w.amounts[unit]
			a.shield = w.Secret()
			w.calls = {}
			w:fire(event, unit)
			H.eq(#w.calls, 1, event .. " " .. unit .. ": asked once")
			H.eq(w.calls[1].unit, unit, event .. ": for its unit")
			H.ok(rawequal(P(ns, key).shield.__h.value, a.shield), event .. " " .. unit .. ": new shield drawn")
		end
		w.calls = {}
		w:fire(event, "party1")
		H.eq(#w.calls, 0, event .. ": another unit asks nothing")
	end
	NoViolation(w, "events")
end)

H.test("the glows take the clamped flag through SetAlphaFromBoolean", function()
	local w, ns = World()
	local seen = {}
	for _, key in ipairs({ "health", "targethealth" }) do
		local p = P(ns, key)
		for _, g in ipairs({ "overShield", "overHealAbsorb" }) do
			rawset(p[g], "SetAlphaFromBoolean", function(_, flag, on, off)
				seen[key .. g] = { flag = flag, on = on, off = off }
			end)
		end
	end
	w:fire("UNIT_HEALTH", "player")
	w:fire("UNIT_HEALTH", "target")
	NoViolation(w, "glows")
	for _, unit in ipairs({ "player", "target" }) do
		local key = unit == "player" and "health" or "targethealth"
		local a = w.amounts[unit]
		local s, h = seen[key .. "overShield"], seen[key .. "overHealAbsorb"]
		H.ok(s and rawequal(s.flag, a.over), key .. ": shield glow from its clamped flag")
		H.ok(h and rawequal(h.flag, a.overAbsorb), key .. ": heal absorb glow from its clamped flag")
		H.eq(s.on, 255, key .. ": on")
		H.eq(s.off, 0, key .. ": off")
	end
end)

H.test("without SetAlphaFromBoolean: a plain true lights a glow, a secret does not", function()
	local w, ns = World()
	local a = w.amounts.player
	a.over, a.overAbsorb = true, false
	w:fire("UNIT_HEALTH", "player")
	local p = P(ns, "health")
	H.eq(p.overShield:GetAlpha(), 1, "plain true: lit")
	H.eq(p.overHealAbsorb:GetAlpha(), 0, "plain false: dark")
	w.secret[true] = true -- the game hides the flag
	w:fire("UNIT_HEALTH", "player")
	H.eq(p.overShield:GetAlpha(), 0, "secret: dark, and no throw")
	NoViolation(w, "fallback")
end)

H.test("Dead, Ghost or Offline: the parts go; alive again, they come back", function()
	local w, ns = World()
	w:fire("UNIT_HEALTH", "target")
	Drawn(w, ns, "targethealth", "target", "alive")
	w.dead.target = true
	w:fire("UNIT_HEALTH", "target")
	Empty(ns, "targethealth", "dead target")
	Drawn(w, ns, "health", "player", "you stay")
	w.dead.target = nil
	w:fire("UNIT_HEALTH", "target")
	Drawn(w, ns, "targethealth", "target", "alive again")
	NoViolation(w, "dead")
end)

H.test("both health bars off: the module is off and the parts are empty", function()
	local w, ns = World()
	w:fire("UNIT_HEALTH", "player")
	local db = w.env.HUDiniDB
	db.showHealth, db.showTargetHealth = false, false
	ns.UpdateModules()
	Empty(ns, "health", "off")
	Empty(ns, "targethealth", "off")
	w.calls = {}
	w:fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
	H.eq(#w.calls, 0, "off: no event, nothing asked")
	db.showHealth = true
	ns.UpdateModules()
	Drawn(w, ns, "health", "player", "on again")
	H.eq(#w.calcs, 2, "made once")
end)

H.test("a throw from the game draws nothing for that part and throws nothing", function()
	local w, ns = World()
	w.throwShield = true
	w:fire("UNIT_HEALTH", "player")
	local p = P(ns, "health")
	H.eq(p.shield.__h.value, 0, "no shield")
	H.eq(p.overShield:GetAlpha(), 0, "no shield glow")
	H.ok(rawequal(p.myHeal.__h.value, w.amounts.player.mine), "the heals still draw")
	w.throwShield = nil
	w.throwPredict = true
	w:fire("UNIT_HEALTH", "player")
	Empty(ns, "health", "no prediction")
	NoViolation(w, "throws")
end)

-- The note for a game that gives no answer.
local function Note(ns)
	for _, m in ipairs(ns.ModuleReport()) do
		if m.name == "healprediction" then return m.note end
	end
end

H.test("no answer from the game: no parts, no glow, and debug says why until it answers", function()
	local w, ns = World()
	local a = w.amounts.player
	a.over, a.overAbsorb = true, true -- plain: a glow would light
	for _, flag in ipairs({ "throwPredict", "throwMax" }) do
		w[flag] = true
		w:fire("UNIT_HEALTH", "player")
		Empty(ns, "health", flag)
		H.eq(Note(ns), "debug.healPrediction.failed", flag .. ": the note")
		w:slash("/hud debug modules")
		H.ok(H.printed(w, ns.TEXT[0]["debug.healPrediction.failed"]), flag .. ": /hud debug modules says why")
		w[flag] = nil
		w:fire("UNIT_HEALTH", "player")
		Drawn(w, ns, "health", "player", flag .. ", answered again")
		H.eq(Note(ns), nil, flag .. ": the note goes")
	end
	NoViolation(w, "no answer")
end)

H.test("module off: a later health tick asks nothing and draws nothing", function()
	local w, ns = World()
	local db = w.env.HUDiniDB
	db.showHealth, db.showTargetHealth = false, false
	ns.UpdateModules()
	w.calls = {}
	ns.PredictHealth(ns.GetBar("health"), "player")
	ns.PredictHealth(ns.GetBar("targethealth"), "target")
	H.eq(#w.calls, 0, "off: nothing asked")
	Empty(ns, "health", "off, after a tick")
	Empty(ns, "targethealth", "off, after a tick")
end)

H.test("a client without the calculator: no error, no parts, and debug says why", function()
	local w, ns = World({ noApi = true })
	w:fire("UNIT_HEALTH", "player")
	w:fire("UNIT_ABSORB_AMOUNT_CHANGED", "target")
	H.eq(P(ns, "health"), false, "no parts on your bar")
	H.eq(P(ns, "targethealth"), false, "no parts on the target's")
	local found
	for _, m in ipairs(ns.ModuleReport()) do
		if m.name == "healprediction" then found = m end
	end
	H.eq(found.note, "debug.healPrediction.missing", "the report has the note")
	w:slash("/hud debug modules")
	H.ok(H.printed(w, ns.TEXT[0]["debug.healPrediction.missing"]), "/hud debug modules says why")
	local lines = {}
	ns.ReportBars(function(text) lines[#lines + 1] = text end)
	H.ok(table.concat(lines, " "):find("Heal prediction calculator", 1, true), "the bar report names the calculator")
end)

H.test("turned on in a fight: made when the fight ends", function()
	local w, ns = World({ before = function(w)
		w.env.HUDiniDB = { showHealth = false, showTargetHealth = false }
	end })
	H.eq(#w.calcs, 0, "off at login: nothing made")
	w.combat = true
	w.env.HUDiniDB.showHealth = true
	ns.UpdateModules()
	H.eq(#w.calcs, 0, "in the fight: nothing made")
	ns.GetBar("health"):SetWidth(222) -- laid out already, no size change to come
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(#w.calcs, 2, "made when the fight ends")
	H.ok(type(P(ns, "health")) == "table", "your bar has its parts")
	for _, part in ipairs({ "myHeal", "otherHeal", "shield", "healAbsorb" }) do
		H.eq(P(ns, "health")[part]:GetWidth(), 222, part .. ": the bar's width when made")
	end
	H.eq(#w.blocked, 0, "nothing blocked")
end)

H.test("each part is as wide as its health bar, and follows it", function()
	local _, ns = World()
	local bar, p = ns.GetBar("health"), P(ns, "health")
	H.ok((bar:GetWidth() or 0) > 0, "the bar has a width")
	for _, part in ipairs({ "myHeal", "otherHeal", "shield", "healAbsorb" }) do
		H.eq(p[part]:GetWidth(), bar:GetWidth(), part .. " width when made")
	end
	-- A new HUD width: the layout sizes the bar, and the parts with it.
	ns.LayoutBars(0, 300, 0)
	for _, part in ipairs({ "myHeal", "otherHeal", "shield", "healAbsorb" }) do
		H.eq(p[part]:GetWidth(), 300, part .. " width after a new layout")
	end
	for _, fn in ipairs(bar.__h.hooks.OnSizeChanged or {}) do fn(bar, 217, 30) end
	for _, part in ipairs({ "myHeal", "otherHeal", "shield", "healAbsorb" }) do
		H.eq(p[part]:GetWidth(), 217, part .. " width")
	end
end)

H.test("Bars.lua reads no absorb or heal amount itself", function()
	local src = H.readFile("Bars.lua")
	for _, name in ipairs({ "UnitGetTotalAbsorbs", "UnitGetIncomingHeals", "UnitGetTotalHealAbsorbs" }) do
		H.ok(not src:find(name .. "(", 1, true), "Bars.lua calls " .. name)
	end
end)
