-- TICK-0161: the global cooldown alone does not make a spell "not ready".
-- The game says isOnGCD is to trust only inside SPELL_UPDATE_COOLDOWN
-- (SpellSharedDocumentation.lua:30), so that event notes it, and the
-- interrupt outline and the racial glow use the note outside it. The
-- outline on a target's cast looks again at each cooldown event: Bars.lua
-- asks only when the cast starts.

local SHOCK = 8042

-- A Shaman whose interrupt is Earth Shock. w.cd: what GetSpellCooldown
-- answers. w.secret: values the game hides. w:Field(t, key, v) gives t
-- whose read of key gives v and flags the very next secret check (true is
-- shared by isActive and isOnGCD), as in test_secret_alerts.lua.
local function World()
	local w = H.world()
	w.class, w.className = "SHAMAN", "Shaman"
	local env = w.env
	w.cd = { isActive = false, isOnGCD = false }
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
	function w:Field(t, key, v)
		return setmetatable(t, { __index = function(_, k)
			if k == key then
				self.arming, self.armValue = true, v
				return v
			end
		end })
	end
	env.C_Spell.GetSpellName = function(id) return id == SHOCK and "Earth Shock" or nil end
	env.C_Spell.GetSpellInfo = function(name)
		if name == "Earth Shock" then return { spellID = SHOCK } end
	end
	env.IsPlayerSpell = function(id) return id == SHOCK end
	env.C_Spell.GetSpellCooldown = function() return w.cd end
	env.C_Spell.IsSpellUsable = function() return true, false end
	-- The target casts, so its cast bar stays up when Bars.lua looks.
	env.UnitCastingInfo = function(unit)
		if unit == "target" then return "Shadow Bolt" end
	end
	local ns = w:loadAddon()
	ns.ClassDB().interrupt = "Earth Shock"
	-- The target's cast bar shows while it casts.
	ns.casts.targetcast.holder:Show()
	return w, ns
end

local function Outline(w, ns)
	local holder = ns.casts.targetcast.holder
	for _, f in ipairs(w.frames) do
		if f.edges and f:GetParent() == holder then return f end
	end
end

local function Cooldown(w, active, gcd)
	w.cd = { isActive = active, isOnGCD = gcd }
	w:fire("SPELL_UPDATE_COOLDOWN")
end

H.test("the global cooldown alone keeps the interrupt ready", function()
	local w, ns = World()
	H.eq(ns.ReadyInterrupt(), "Earth Shock", "off cooldown")
	Cooldown(w, true, true)
	H.eq(ns.ReadyInterrupt(), "Earth Shock", "the global cooldown only")
	Cooldown(w, true, false)
	H.eq(ns.ReadyInterrupt(), nil, "its own cooldown")
	Cooldown(w, false, false)
	H.eq(ns.ReadyInterrupt(), "Earth Shock", "ready again")
end)

H.test("isOnGCD outside the event is not trusted", function()
	local w, ns = World()
	H.eq(ns.ReadyInterrupt(), "Earth Shock", "asked once: noted from now on")
	-- Its own cooldown, as the event saw it; then, outside any event, the
	-- game says isOnGCD true (not to trust there).
	Cooldown(w, true, false)
	w.cd = { isActive = true, isOnGCD = true }
	H.eq(ns.ReadyInterrupt(), nil, "the note from the event stands")
	-- And the other way: the event said global only, then outside it isOnGCD
	-- reads false.
	Cooldown(w, true, true)
	w.cd = { isActive = true, isOnGCD = false }
	H.eq(ns.ReadyInterrupt(), "Earth Shock", "the note stands")
end)

H.test("a secret isOnGCD in the event counts as its own cooldown", function()
	local w, ns = World()
	Cooldown(w, true, true)
	H.eq(ns.ReadyInterrupt(), "Earth Shock", "plain: global only, ready")
	w.cd = w:Field({ isActive = true }, "isOnGCD", true)
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(ns.ReadyInterrupt(), nil, "secret isOnGCD alone: not noted as global only")
end)

H.test("the first ask in a global cooldown finds a note", function()
	local w, ns = World()
	Cooldown(w, true, true)
	H.eq(ns.ReadyInterrupt(), "Earth Shock", "never asked before the event: noted all the same")
end)

H.test("a shared cooldown a frame after the event takes the note away", function()
	local w, ns = World()
	Cooldown(w, true, true)
	ns.OnTargetCast(false, false)
	local outline = Outline(w, ns)
	H.eq(outline:IsShown(), true, "the event says global only: the outline shows")
	-- Flame Shock's shared cooldown lands on Earth Shock with no event.
	w.cd = { isActive = true, isOnGCD = false }
	w:runTimers()
	H.eq(ns.ReadyInterrupt(), nil, "a frame later: its own cooldown")
	H.eq(outline:IsShown(), false, "and the outline goes")
end)

H.test("a frame later, isOnGCD out of the event never gives a note", function()
	local w, ns = World()
	-- Two events in one frame: the first says global only and plans the
	-- late look; the second says its own cooldown.
	Cooldown(w, true, true)
	Cooldown(w, true, false)
	w.cd = { isActive = true, isOnGCD = true }
	w:runTimers()
	H.eq(ns.ReadyInterrupt(), nil, "its own cooldown, as the event said")
end)

H.test("a target cast bar hidden with no end drops the cast", function()
	local w, ns = World()
	Cooldown(w, true, false)
	ns.OnTargetCast(false, false)
	local outline = Outline(w, ns)
	ns.casts.targetcast.holder:Hide() -- the target cleared: no "ended"
	local calls = 0
	local real = ns.OnTargetCast
	ns.OnTargetCast = function(...) calls = calls + 1 return real(...) end
	Cooldown(w, false, false)
	H.eq(calls, 0, "no outline work on a hidden bar")
	ns.casts.targetcast.holder:Show()
	Cooldown(w, true, true)
	H.eq(calls, 0, "the cast stays dropped")
	ns.OnTargetCast = real
	H.eq(outline:IsShown(), false, "no outline")
end)

H.test("the outline on a target's cast follows your cooldowns while it runs", function()
	local w, ns = World()
	Cooldown(w, true, false)
	ns.OnTargetCast(false, false)
	local outline = Outline(w, ns)
	H.ok(outline, "the outline exists")
	H.eq(outline:IsShown(), false, "the cast starts with your interrupt on cooldown: no outline")
	Cooldown(w, false, false)
	H.eq(outline:IsShown(), true, "it comes off cooldown during the cast: the outline shows")
	Cooldown(w, true, true)
	H.eq(outline:IsShown(), true, "you cast another spell: the global cooldown keeps it")
	Cooldown(w, true, false)
	H.eq(outline:IsShown(), false, "you interrupt: its own cooldown puts it out")
	ns.OnTargetCast(nil, true)
	Cooldown(w, false, false)
	H.eq(outline:IsShown(), false, "the cast ended: a cooldown event shows nothing")
end)

H.test("with the target's cast bar off, a cooldown event shows no outline", function()
	local w, ns = World()
	ns.OnTargetCast(false, false)
	local outline = Outline(w, ns)
	H.eq(outline:IsShown(), true, "shown at the cast start")
	w.env.HUDiniDB.showTargetCast = false
	outline:Hide()
	Cooldown(w, false, false)
	H.eq(outline:IsShown(), false, "off means off")
end)

H.test("the outline's secret value is handed on, never read", function()
	local w, ns = World()
	local ni = setmetatable({}, { __eq = function() error("compared") end,
		__tostring = function() error("joined") end })
	w.secret[ni] = true
	Cooldown(w, true, false)
	ns.OnTargetCast(ni, false)
	Cooldown(w, false, false)
	H.eq(Outline(w, ns):IsShown(), true, "shown, with no error")
end)
