-- Alerts.lua when the game hides an answer (TICK-0112). Each test first runs
-- the value that WOULD change an alert, plain, and checks that it does.
-- Then it flags that same value secret and checks that the alert does what
-- it does for no answer, and throws nothing. So a missing Plain() fails
-- the test (the method of TICK-0110).

-- A logged-in world. w.secret: the values issecretvalue calls secret.
-- w:Once(v) gives a stub that returns v and flags the very next check
-- secret if it asks about v: for true and false, which other answers
-- share. The next check is the guard's; without the guard the flag goes
-- unused. w:Field(t, key, v) does the same for a field read.
local function World(setup)
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
	function w:Field(t, key, v)
		return setmetatable(t, { __index = function(_, k)
			if k == key then
				self.arming, self.armValue = true, v
				return v
			end
		end })
	end
	w.auras = {}   -- w.auras[unit .. filter]: the auras in slot order
	env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		local list = w.auras[unit .. (filter or "")]
		return list and list[i]
	end
	if setup then setup(w, env) end
	local ns = w:loadAddon()
	return w, ns
end

-- A spell you know, by name and by id.
local function KnowSpell(env, name, id)
	local info, spellName = env.C_Spell.GetSpellInfo, env.C_Spell.GetSpellName
	env.C_Spell.GetSpellInfo = function(n)
		if n == name or n == id then return { spellID = id, name = name } end
		return info and info(n)
	end
	env.C_Spell.GetSpellName = function(i)
		if i == id then return name end
		return spellName and spellName(i)
	end
	local known = env.IsPlayerSpell
	env.IsPlayerSpell = function(i) return i == id or (known and known(i)) or false end
end

--------------------------------------------------------------------------------
-- 8. Racial: on the global cooldown only
--------------------------------------------------------------------------------

H.test("a secret on-the-GCD answer does not count as ready", function()
	local w, ns = World(function(w, env)
		env.UnitRace = function() return "Dwarf", "Dwarf", 3 end
		KnowSpell(env, "Stoneform", 20594)
		env.C_Spell.GetSpellCooldown = function() return w.cd end
		env.C_Spell.IsSpellUsable = function() return true end
	end)
	w.auras["playerHARMFUL"] = { { dispelName = "Poison" } }
	w.cd = { isActive = true, isOnGCD = true }
	ns.UpdateRacialGlow()
	H.eq(ns.HUDini.alertGlow.racial, 20594, "plain: on the GCD only, so lit")
	w.cd = w:Field({ isActive = true }, "isOnGCD", true)
	ns.UpdateRacialGlow()
	H.eq(ns.HUDini.alertGlow.racial, nil, "secret: not lit")
end)

--------------------------------------------------------------------------------
-- 4. Purgeable buffs on the target
--------------------------------------------------------------------------------

-- The purge icons on the target bar that show, right to left.
local function PurgeIcons(w)
	local bar, out = w.ns.GetBar("targethealth"), {}
	for _, f in ipairs(w.frames) do
		local point, to, rel = f:GetPoint(1)
		if f:GetParent() == bar and f.tex and point == "RIGHT" and to == bar and rel == "RIGHT" and f:IsShown() then
			out[#out + 1] = f
		end
	end
	return out
end

local function PurgeWorld(class, spell, id)
	local w, ns = World(function(w, env)
		w.class, w.className = class, class
		KnowSpell(env, spell, id)
		env.UnitCanAttack = function() return true end
	end)
	w.hasTarget = true
	return w, ns
end

H.test("a secret stealable answer shows no Spellsteal icon", function()
	local w, ns = PurgeWorld("MAGE", "Spellsteal", 30449)
	w.auras["targetHELPFUL"] = { { isStealable = true, icon = 136000 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 1, "plain: one icon")
	w.auras["targetHELPFUL"] = { w:Field({ icon = 136000 }, "isStealable", true) }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "secret: none")
end)

H.test("a secret buff icon draws the question mark", function()
	local w, ns = PurgeWorld("PRIEST", "Dispel Magic", 527)
	w.auras["targetHELPFUL"] = { { dispelName = "Magic", icon = 136001 } }
	ns.UpdateAlerts()
	local icon = PurgeIcons(w)[1]
	H.ok(icon, "plain: one icon")
	local drawn
	rawset(icon.tex, "SetTexture", function(_, t) drawn = t end)
	ns.UpdateAlerts()
	H.eq(drawn, 136001, "plain: the buff's own icon")
	w.secret[136001] = true
	ns.UpdateAlerts()
	H.eq(drawn, 134400, "secret: the question mark")
end)

--------------------------------------------------------------------------------
-- 6. The target buff icon
--------------------------------------------------------------------------------

local function TargetBuffIcon(w)
	local bar = w.ns.GetBar("targethealth")
	for _, f in ipairs(w.frames) do
		local point, to, rel = f:GetPoint(1)
		if f:GetParent() == bar and f.tex and point == "RIGHT" and to == bar and rel == "LEFT" then
			return f
		end
	end
end

local function Live(w)
	local n = 0
	for _, t in ipairs(w.tickers) do
		if not t.cancelled then n = n + 1 end
	end
	return n
end

-- A Mage who keeps Arcane Intellect up, and a friendly player target who
-- lacks it. w.player, w.assist, w.dead, w.online: stubs for the four
-- target answers.
local function BuffWorld(o)
	o = o or {}
	local w, ns = World(function(w, env)
		w.class, w.className = o.class or "MAGE", o.class or "Mage"
		KnowSpell(env, o.spell or "Arcane Intellect", o.id or 1459)
		env.SpellHasRange = function() return w.ranged() end
		env.UnitIsPlayer = function(u) return u == "player" or w.player end
		env.UnitCanAssist = function() return w.assist end
		env.UnitIsDeadOrGhost = function(u) if u == "target" then return w.dead() end return false end
		env.UnitIsConnected = function(u) if u == "target" then return w.online() end return true end
		env.C_Spell.IsSpellInRange = function() return w.inRange() end
	end)
	w.player, w.assist = "yes", "ally"
	w.ranged = function() return true end
	w.dead = function() return false end
	w.online = function() return true end
	w.inRange = function() return true end
	ns.ClassDB().buffSpells = { [o.spell or "Arcane Intellect"] = true }
	ns.HUDini.spells = {}
	w.hasTarget = true
	local function Shown()
		w:fire("PLAYER_TARGET_CHANGED")
		local icon = TargetBuffIcon(w)
		return icon ~= nil and icon:IsShown()
	end
	return w, ns, Shown
end

H.test("a secret no-range answer still asks for the buff", function()
	local w, _, Shown = BuffWorld()
	H.eq(Shown(), true, "a ranged buff: asked for")
	w.ranged = function() return false end
	H.eq(Shown(), false, "plain no range: a self buff, not asked for")
	w.ranged = w:Once(false)
	H.eq(Shown(), true, "secret: asked for")
end)

H.test("a secret name of your buff on the target is not read as no blessing", function()
	local w, _, Shown = BuffWorld({ class = "PALADIN", spell = "Blessing of Freedom", id = 1044 })
	w.auras["targetHELPFUL|PLAYER"] = { { name = "Seal of Light" } }
	H.eq(Shown(), true, "plain: not a blessing, so asked for")
	w.secret["Seal of Light"] = true
	H.eq(Shown(), false, "secret: the game will not say, so not asked for")
end)

H.test("a secret player or help answer on the target asks for nothing", function()
	local w, _, Shown = BuffWorld()
	H.eq(Shown(), true, "plain: asked for")
	w.secret.yes = true
	H.eq(Shown(), false, "secret player answer: not asked for")
	w.secret.yes, w.secret.ally = nil, true
	H.eq(Shown(), false, "secret help answer: not asked for")
end)

H.test("a secret dead answer asks for nothing; a secret online answer does", function()
	local w, _, Shown = BuffWorld()
	H.eq(Shown(), true, "plain alive: asked for")
	w.dead = w:Once(false)
	H.eq(Shown(), false, "secret alive: not asked for")

	w.dead = function() return false end
	w.online = function() return false end
	H.eq(Shown(), false, "plain offline: not asked for")
	w.online = w:Once(false)
	H.eq(Shown(), true, "secret offline: asked for")
end)

H.test("a secret out-of-range answer does not dim the target buff icon", function()
	local w, _, Shown = BuffWorld()
	w.inRange = function() return false end
	Shown()
	H.eq(TargetBuffIcon(w).__h.alpha, 0.4, "plain: dim")
	w.inRange = w:Once(false)
	Shown()
	H.eq(TargetBuffIcon(w).__h.alpha, 1, "secret: full")
end)

H.test("a secret player or help answer stops the target buff ticker", function()
	for _, key in ipairs({ "yes", "ally" }) do
		local w = BuffWorld()
		local idle = Live(w)
		w.hasTarget = false
		w:fire("PLAYER_TARGET_CHANGED")
		idle = Live(w)
		w.hasTarget = true
		w:fire("PLAYER_TARGET_CHANGED")
		H.eq(Live(w), idle + 1, key .. ", plain: the ticker runs")
		w.secret[key] = true
		w:runTickers()
		H.eq(Live(w), idle, key .. ", secret: it stops")
	end
end)

--------------------------------------------------------------------------------
-- /hud debug: the debuff on you
--------------------------------------------------------------------------------

H.test("a secret debuff type is reported as ?", function()
	local w, ns = World()
	w.auras["playerHARMFUL|RAID"] = { { dispelName = "Curse" } }
	local function Report()
		local lines = {}
		ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
		for _, line in ipairs(lines) do
			if line:find("Dispellable debuff on you now", 1, true) then return line end
		end
	end
	H.ok(Report():find("Curse", 1, true), "plain: the type")
	w.secret.Curse = true
	H.ok(Report():find("?", 1, true) and not Report():find("Curse", 1, true), "secret: ?")
end)
