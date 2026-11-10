-- Racial ability alert (TICK-0099, D-022). A dwarf's Stoneform lights up
-- while it is ready and a poison, disease or bleed is on you. Only a plain
-- debuff type counts: a secret type or a secret aura lights nothing and
-- throws nothing. An unknown race, the switch off, or Stoneform on cooldown
-- lights nothing. The global cooldown alone does not turn it off.

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
-- A secret aura table: reading a field throws.
local SECRET_AURA = setmetatable({}, { __index = function() error("secret aura") end })
local STONEFORM = 20594

-- A world for one race. o.race: UnitRace's second value ("Dwarf"), or
-- false for no UnitRace at all. o.debuffs: the player's harmful auras, in
-- slot order. o.cd: what C_Spell.GetSpellCooldown answers. o.usable: what
-- C_Spell.IsSpellUsable answers. o.known: false when you do not know
-- Stoneform. o.auraThrows: GetAuraDataByIndex throws. o.secret (or
-- state.secret later): values the game hides. A secret test flags the very
-- value that WOULD light Stoneform ("Poison", "Dwarf", isActive false), so
-- only Plain() keeps it dark: a missing Plain() fails the test.
local function World(o)
	o = o or {}
	local w = H.world()
	local env = w.env
	local secret = o.secret or {}
	env.issecretvalue = function(v)
		return v == SECRET or v == SECRET_AURA or (v ~= nil and secret[v] == true)
	end
	local race = o.race == nil and "Dwarf" or o.race
	if race then
		env.UnitRace = function() return race, race, 3 end
	end
	local state = { debuffs = o.debuffs or {}, cd = o.cd or { isActive = false, isOnGCD = false }, secret = secret }
	env.C_Spell.GetSpellInfo = function(name)
		if type(name) == "string" and name:lower() == "stoneform" then
			return { spellID = STONEFORM }
		end
	end
	env.C_Spell.GetSpellName = function(id) if id == STONEFORM then return "Stoneform" end end
	env.IsPlayerSpell = function(id) return id == STONEFORM and o.known ~= false end
	env.C_Spell.GetSpellCooldown = function() return state.cd end
	env.C_Spell.IsSpellUsable = function() if o.usable == nil then return true end return o.usable end
	env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		if o.auraThrows then error("restricted") end
		if unit ~= "player" or filter ~= "HARMFUL" then return nil end
		return state.debuffs[i]
	end
	local ns = w:loadAddon()
	return ns, w, state
end

local function Lit(ns) return ns.HUDini.alertGlow.racial end

-- One icon in the grid with the given spell, and its glow.
local function OneIcon(ns, spellID)
	local glow = { shown = false, anim = {} }
	function glow:IsShown() return self.shown end
	function glow:Show() self.shown = true end
	function glow:Hide() self.shown = false end
	function glow.anim.Play() end
	function glow.anim.Stop() end
	ns.HUDini.spells = { { spellID = spellID } }
	ns.HUDini.icons = { { glow = glow } }
	return glow
end

H.test("the race table: a dwarf gets Stoneform for poison, disease, bleed", function()
	local ns = World()
	local spell, types = ns.RacialAlert()
	H.eq(spell, "Stoneform")
	H.eq(types.Poison, true, "Poison")
	H.eq(types.Disease, true, "Disease")
	H.eq(types.Bleed, true, "Bleed")
	H.eq(types.Magic, nil, "no Magic")
	H.eq(types.Curse, nil, "no Curse")
end)

H.test("each answered debuff type lights Stoneform", function()
	for _, kind in ipairs({ "Poison", "Disease", "Bleed" }) do
		local ns, _, state = World()
		state.debuffs = { { dispelName = kind } }
		ns.UpdateAlerts()
		H.eq(Lit(ns), STONEFORM, kind)
	end
end)

H.test("the answered debuff may sit behind other debuffs", function()
	local ns, _, state = World()
	state.debuffs = { { dispelName = "Magic" }, {}, { dispelName = SECRET }, { dispelName = "Disease" } }
	ns.UpdateAlerts()
	H.eq(Lit(ns), STONEFORM)
end)

H.test("a type Stoneform does not answer lights nothing", function()
	local ns, _, state = World()
	state.debuffs = { { dispelName = "Magic" }, { dispelName = "Curse" }, {} }
	ns.UpdateAlerts()
	H.eq(Lit(ns), nil)
end)

H.test("a secret type, a secret aura, or a refused answer lights nothing and throws nothing", function()
	local ns, _, state = World()
	state.debuffs = { { dispelName = "Poison" } }
	ns.UpdateAlerts()
	H.eq(Lit(ns), STONEFORM, "plain Poison lights")
	state.secret.Poison = true
	ns.UpdateAlerts()
	H.eq(Lit(ns), nil, "the same Poison, secret, lights nothing")
	state.secret.Poison = nil
	state.debuffs = { SECRET_AURA }
	ns.UpdateAlerts()
	H.eq(Lit(ns), nil, "secret aura")
	local ns2 = World({ auraThrows = true, debuffs = { { dispelName = "Poison" } } })
	ns2.UpdateAlerts()
	H.eq(Lit(ns2), nil, "the game throws")
end)

H.test("an unknown race, a secret Dwarf, or no UnitRace lights nothing", function()
	for _, race in ipairs({ "Human", "secret Dwarf", false }) do
		local o = { race = race }
		if race == "secret Dwarf" then o.race, o.secret = "Dwarf", { Dwarf = true } end
		local ns, _, state = World(o)
		state.debuffs = { { dispelName = "Poison" } }
		ns.UpdateAlerts()
		H.eq(Lit(ns), nil, tostring(race))
		H.eq(ns.RacialAlert(), nil, tostring(race) .. ": no racial")
	end
end)

H.test("Stoneform not known lights nothing", function()
	local ns = World({ known = false, debuffs = { { dispelName = "Poison" } } })
	ns.UpdateAlerts()
	H.eq(Lit(ns), nil)
end)

H.test("Stoneform on cooldown lights nothing; the global cooldown alone still lights", function()
	local ns, w, state = World({ debuffs = { { dispelName = "Poison" } } })
	ns.UpdateAlerts()
	H.eq(Lit(ns), STONEFORM, "ready")
	state.cd = { isActive = true, isOnGCD = false }
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Lit(ns), nil, "on cooldown: the cooldown event turns it off")
	state.cd = { isActive = true, isOnGCD = true }
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Lit(ns), STONEFORM, "global cooldown only")
	state.cd = { isActive = false, isOnGCD = false }
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Lit(ns), STONEFORM, "ready again")
	state.secret[false] = true
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Lit(ns), nil, "the same off-cooldown answer, secret, lights nothing")
end)

H.test("Stoneform you cannot cast now lights nothing", function()
	local ns = World({ usable = false, debuffs = { { dispelName = "Poison" } } })
	ns.UpdateAlerts()
	H.eq(Lit(ns), nil)
end)

H.test("the switch off puts out a lit Stoneform", function()
	local ns, w, state = World()
	H.eq(w.env.HUDiniDB.warnRacial, true, "on at the start")
	local glow = OneIcon(ns, STONEFORM)
	state.debuffs = { { dispelName = "Bleed" } }
	ns.UpdateAlerts()
	H.eq(glow.shown, true, "lit first")
	w.env.HUDiniDB.warnRacial = false
	ns.UpdateAlerts()
	H.eq(Lit(ns), nil, "off")
	H.eq(glow.shown, false, "the icon goes dark")
end)

H.test("the glow is on the Stoneform icon, and goes when the debuff goes", function()
	local ns, _, state = World()
	local glow = OneIcon(ns, STONEFORM)
	state.debuffs = { { dispelName = "Poison" } }
	ns.UpdateAlerts()
	H.eq(glow.shown, true, "lit")
	state.debuffs = {}
	ns.UpdateAlerts()
	H.eq(glow.shown, false, "debuff gone")
end)

H.test("the alert glow does not need the proc glow setting, and leaves other icons dark", function()
	local ns, w, state = World()
	w.env.HUDiniDB.showProcGlow = false
	local glow = OneIcon(ns, 12345)
	state.debuffs = { { dispelName = "Poison" } }
	ns.UpdateAlerts()
	H.eq(glow.shown, false, "another spell's icon stays dark")
	glow = OneIcon(ns, STONEFORM)
	ns.HUDini.alertGlow = {}
	ns.UpdateAlerts()
	H.eq(glow.shown, true, "Stoneform lit with Proc glow off")
end)

H.test("a lit Stoneform wakes the HUD that hides when idle, and /hud why says so", function()
	local ns, w, state = World()
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	OneIcon(ns, STONEFORM)
	ns.HUDini:UpdateVisibility()
	local show = ns.HUDini:ShouldShow()
	H.eq(show, false, "idle: hidden")
	state.debuffs = { { dispelName = "Disease" } }
	ns.UpdateAlerts()
	local why
	show, why = ns.HUDini:ShouldShow()
	H.eq(show, true, "lit: shows")
	H.eq(why, ns.Text("why.racial"))
	state.debuffs = {}
	ns.UpdateAlerts()
	H.eq((ns.HUDini:ShouldShow()), false, "gone: idle again")
end)
