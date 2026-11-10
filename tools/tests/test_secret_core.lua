-- Core.lua when the game hides an answer (TICK-0112). Each test first runs
-- the value that WOULD change what HUDini does, plain, and checks that it
-- does. Then it flags that same value secret and checks that HUDini does
-- what it does for no answer, and throws nothing. So a missing Plain() or
-- IsSecret() fails the test (the method of TICK-0110).

-- A logged-in world. w.secret: the values issecretvalue calls secret.
-- w:Once(v) gives a stub that returns v and flags it secret for the next
-- check only: for true and false, which other answers share. The next
-- check is the guard's. Without the guard it is some other value's: the
-- flag goes unused, unless that value is equal (another false), which
-- then turns secret. The probe, not this stub, proves each guard caught.
local function World(setup)
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v)
		if v == nil then return false end
		if w.secret[v] then return true end
		-- Armed for the very next check, whatever it asks about.
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
	if setup then setup(w, env) end
	local ns = w:loadAddon()
	return w, ns, ns.HUDini
end

--------------------------------------------------------------------------------
-- The icons: count, usable, range, the assist hint, the glow
--------------------------------------------------------------------------------

-- One fake icon that records what it is told.
local function Icon()
	local r = {}
	local f = { r = r }
	f.count = { SetText = function(_, t) r.count = t end }
	f.icon = {
		SetVertexColor = function(_, a, b, c) r.color = { a, b, c } end,
		SetDesaturated = function(_, d) r.desat = d end,
		SetAlpha = function(_, a) r.alpha = a end,
	}
	f.backdrop = { SetAlpha = function() end }
	f.assist = { SetShown = function(_, s) r.assist = s end }
	return f
end

local function OneIcon(hud, entry)
	local f = Icon()
	hud.spells, hud.icons = { entry }, { f }
	return f.r
end

H.test("a secret item count is not drawn", function()
	local w, _, hud = World(function(w, env)
		env.C_ActionBar.GetActionDisplayCount = function() return w.count end
	end)
	local r = OneIcon(hud, { slot = 1, itemID = 5 })
	w.count = "12"
	hud:UpdateCounts()
	H.eq(r.count, "12", "plain: the count")
	w.secret["12"] = true
	hud:UpdateCounts()
	H.eq(r.count, "", "secret: no count")
end)

H.test("a secret not-usable answer does not gray the icon", function()
	local w, _, hud = World(function(w, env)
		env.C_ActionBar.IsUsableAction = function() return w.usable and w.usable() end
	end)
	w.env.HUDiniDB.showUsable, w.env.HUDiniDB.showRange = true, false
	local r = OneIcon(hud, { slot = 1 })
	w.usable = function() return false end
	hud:UpdateUsable()
	H.eq(r.alpha, 0.5, "plain false: faded")
	w.usable = w:Once(false)
	hud:UpdateUsable()
	H.eq(r.alpha, 1, "secret false: full")
	H.eq(r.desat, false, "and in color")
end)

H.test("a secret out-of-range answer does not redden the icon", function()
	local w, _, hud = World(function(w, env)
		env.C_ActionBar.IsActionInRange = function() return w.range and w.range() end
	end)
	w.env.HUDiniDB.showUsable, w.env.HUDiniDB.showRange = false, true
	local r = OneIcon(hud, { slot = 1 })
	w.range = function() return false end
	hud:UpdateUsable()
	H.eq(r.color[2], 0.25, "plain false: red")
	w.range = w:Once(false)
	hud:UpdateUsable()
	H.eq(r.color[2], 1, "secret false: white")
end)

H.test("a secret assist answer marks no icon", function()
	local w, _, hud = World(function(w, env)
		env.C_AssistedCombat = { GetNextCastSpell = function() return w.next end }
	end)
	w.env.HUDiniDB.showAssist = true
	local r = OneIcon(hud, { slot = 1, spellID = 4077 })
	w.next = 4077
	hud:UpdateAssist()
	H.eq(r.assist, true, "plain: marked")
	w.secret[4077] = true
	hud:UpdateAssist()
	H.eq(r.assist, false, "secret: not marked")
end)

H.test("a secret spell in a glow event lights and clears nothing", function()
	local w, _, hud = World()
	w:fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 4078)
	H.eq(hud.glowing[4078], true, "plain show: lit")
	w:fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 4078)
	H.eq(hud.glowing[4078], nil, "plain hide: cleared")

	hud.glowing[4079] = true
	w.secret[4079] = true
	w:fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 4079)
	H.eq(hud.glowing[4079], true, "secret hide: left lit")
	hud.glowing[4079] = nil
	w:fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 4079)
	H.eq(hud.glowing[4079], nil, "secret show: not lit")
end)

--------------------------------------------------------------------------------
-- Hide when idle (ShouldShow)
--------------------------------------------------------------------------------

-- Locked, hide when idle on, and only the given reason to show turned on.
local function Idle(setting, setup)
	local w, ns, hud = World(setup)
	local db = w.env.HUDiniDB
	db.locked, db.hideWhenIdle = true, true
	for _, k in ipairs({ "showInCombat", "showOnHostile", "showWhenHurt", "showWhenPower", "showWhenBuffMissing" }) do
		db[k] = false
	end
	db[setting] = true
	hud.spells = { {} }
	local function Why()
		local _, why = hud:ShouldShow()
		return why
	end
	return w, ns, Why
end

H.test("a secret in-combat answer is not a fight", function()
	local w, ns, Why = Idle("showInCombat", function(w, env)
		env.UnitAffectingCombat = function() return w.fight and w.fight() end
	end)
	w.fight = function() return true end
	H.eq(Why(), ns.Text("why.combat"), "plain: a fight")
	w.fight = w:Once(true)
	H.ok(Why() ~= ns.Text("why.combat"), "secret: no fight")
end)

H.test("a secret attack or dead answer on the target is not a hostile target", function()
	local w, ns, Why = Idle("showOnHostile", function(w, env)
		env.UnitCanAttack = function() return w.foe end
		env.UnitIsDead = function() return w.dead end
	end)
	w.hasTarget, w.foe, w.dead = true, "foe", nil
	H.eq(Why(), ns.Text("why.hostile"), "plain: hostile")
	w.secret.foe = true
	H.ok(Why() ~= ns.Text("why.hostile"), "secret attack answer: not hostile")

	w.secret.foe, w.dead = nil, "corpse"
	H.ok(Why() ~= ns.Text("why.hostile"), "plain dead: not hostile")
	w.secret.corpse = true
	H.eq(Why(), ns.Text("why.hostile"), "secret dead answer: alive, so hostile")
end)

H.test("a secret health is not compared", function()
	local w, ns, Why = Idle("showWhenHurt", function(w, env)
		env.UnitHealth = function() return w.hp end
		env.UnitHealthMax = function() return w.most end
	end)
	w.hp, w.most = 41, 77
	local hurt = ns.Text("why.health", 41, 77)
	H.eq(Why(), hurt, "plain: hurt")
	w.secret[41] = true
	H.ok(Why() ~= hurt, "secret health: not compared")
	w.secret[41], w.secret[77] = nil, true
	H.ok(Why() ~= hurt, "secret maximum: not compared")
end)

H.test("a secret power is not compared", function()
	local w, ns, Why = Idle("showWhenPower", function(w, env)
		env.UnitPower = function(u) if u == "player" then return w.cur end return 0 end
		env.UnitPowerMax = function(u) if u == "player" then return w.most end return 0 end
	end)
	w.cur, w.most = 43, 91
	local low = ns.Text("why.power", "mana", 43, 91)
	H.eq(Why(), low, "plain: not full")
	w.secret[43] = true
	H.ok(Why() ~= low, "secret power: not compared")
	w.secret[43], w.secret[91] = nil, true
	H.ok(Why() ~= low, "secret maximum: not compared")
end)

--------------------------------------------------------------------------------
-- Hide player frame: the alpha and the mouse walk
--------------------------------------------------------------------------------

-- The player frame (not protected, so its own mouse never waits) with one
-- part under it that takes clicks.
local function FrameWorld(setup)
	local w, ns, hud = World(function(w, env)
		w.top = w:Frame("PlayerFrame", nil, { mouse = true })
		w.part = w:Frame(nil, w.top, { mouse = true })
		table.insert(w.top.__h.children, w.part)
		rawset(w.part, "IsProtected", function() return false end)
		if setup then setup(w, env) end
	end)
	local function Hide(on)
		w.env.HUDiniDB.hideBlizzardPlayer = on
		hud:ApplyBlizzardFrames()
	end
	return w, ns, Hide
end

H.test("a secret alpha of the player frame is not kept for the restore", function()
	local w, _, Hide = FrameWorld()
	w.top:SetAlpha(0.6)
	Hide(true)
	Hide(false)
	H.eq(w.top.__h.alpha, 0.6, "plain: the alpha it had comes back")

	w.top:SetAlpha(0.7)
	w.secret[0.7] = true
	Hide(true)
	Hide(false)
	H.ok(w.top.__h.alpha ~= 0.7, "secret: not kept")
end)

H.test("a secret player frame, or a secret forbidden answer on it, is not walked", function()
	local w, _, Hide = FrameWorld()
	Hide(true)
	H.eq(w.part.__h.mouse, false, "plain: its part takes no click")
	Hide(false)
	H.eq(w.part.__h.mouse, true, "back")

	w.secret[w.top] = true
	Hide(true)
	H.eq(w.part.__h.mouse, true, "secret frame: left alone")
	Hide(false)
	w.secret[w.top] = nil

	rawset(w.top, "IsForbidden", w:Once(false))
	Hide(true)
	H.eq(w.part.__h.mouse, true, "secret forbidden answer: left alone")
end)

H.test("a secret part, or a secret forbidden answer on a part, is left alone", function()
	local w, _, Hide = FrameWorld()
	w.secret[w.part] = true
	Hide(true)
	H.eq(w.part.__h.mouse, true, "secret part: left alone")
	Hide(false)
	w.secret[w.part] = nil

	rawset(w.part, "IsForbidden", w:Once(false))
	Hide(true)
	H.eq(w.part.__h.mouse, true, "secret forbidden answer: left alone")
end)

H.test("a secret mouse answer is not taken as on", function()
	local w, _, Hide = FrameWorld()
	rawset(w.part, "IsMouseClickEnabled", w:Once(true))
	Hide(true)
	H.eq(w.part.__h.mouse, true, "secret: HUDini took no click")
	Hide(false)
	rawset(w.part, "IsMouseClickEnabled", nil)
	Hide(true)
	H.eq(w.part.__h.mouse, false, "plain: the click is taken")
end)

H.test("in a fight, a secret not-protected answer waits for the fight to end", function()
	local w, _, Hide = FrameWorld()
	w.combat = true
	Hide(true)
	H.eq(w.part.__h.mouse, false, "plain not protected: the click is taken at once")
	w.combat = false
	Hide(false)

	w.combat = true
	rawset(w.part, "IsProtected", w:Once(false))
	Hide(true)
	H.eq(w.part.__h.mouse, true, "secret: it waits")
end)
