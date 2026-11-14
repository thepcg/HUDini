-- A missing buff lights its HUD icon (D-035, TICK-0150). While the "Your
-- buff is off" icon shows a buff, the HUD icon of the spell that casts it
-- glows, through the alert glow (it shows with the proc glow setting off).
-- No alert, no glow. A fight hides your buffs, so HUDini goes by what it
-- last saw (Auras.lua BuffState): each test lets it see the buff off first.

-- A shaman with Lightning Shield (10 minutes, learned) on the first icon
-- and Arcane Intellect (1 hour, learned) on the second.
local function World()
	local w = H.world()
	local env = w.env
	w.names = { [324] = "Lightning Shield", [1459] = "Arcane Intellect" }
	w.byName = { ["Lightning Shield"] = 324, ["Arcane Intellect"] = 1459 }
	env.C_Spell.GetSpellName = function(id) return w.names[id] end
	env.C_Spell.GetSpellInfo = function(name)
		local id = w.byName[name]
		if id then return { spellID = id, name = name } end
	end
	env.IsPlayerSpell = function(id) return w.names[id] ~= nil end
	w.auras = {}
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name) return w.auras[name] end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataByIndex = function() return nil end
	local ns = w:loadAddon()
	local db = env.HUDiniDB
	db.warnOwnBuff, db.showHealth = true, true
	ns.HUDini.spells = { { spellID = 324, slot = 1 } }
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	return w, ns, db
end

local function Glow(ns)
	ns.UpdateBuffMissing()
	return ns.HUDini.alertGlow.ownBuff
end

H.test("Lightning Shield off in a fight: its HUD icon glows; cast it: the glow goes", function()
	local w, ns = World()
	H.eq(Glow(ns), nil, "out of a fight: no glow")
	w.combat = true
	H.eq(Glow(ns), 324, "off in a fight: the icon glows")
	w.auras["Lightning Shield"] = { auraInstanceID = 901, duration = 600, expirationTime = 700 }
	H.eq(Glow(ns), nil, "cast: no glow")
end)

H.test("a short buff out of a fight: no glow, and the fight's end takes it away", function()
	local w, ns = World()
	H.eq(Glow(ns), nil, "out of a fight: no glow")
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(ns.HUDini.alertGlow.ownBuff, 324, "the fight starts: the glow")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.eq(ns.HUDini.alertGlow.ownBuff, nil, "the fight ends: no glow")
end)

H.test("a long buff off: it glows out of a fight too", function()
	local _, ns = World()
	ns.HUDini.spells = { { spellID = 1459, slot = 2 } }
	ns.ClassDB().buffSpells = { ["Arcane Intellect"] = 3600 }
	H.eq(Glow(ns), 1459, "the glow")
end)

H.test("the alert off, or no health bar: no glow", function()
	local w, ns, db = World()
	Glow(ns)
	w.combat = true
	db.warnOwnBuff = false
	H.eq(Glow(ns), nil, "Your buff is off alert off")
	db.warnOwnBuff, db.showHealth = true, false
	H.eq(Glow(ns), nil, "no health bar, so no alert")
end)

H.test("proc glows off: the buff's icon still glows", function()
	local w, ns, db = World()
	db.showProcGlow = false
	local f = ns.HUDini:GetIcon(1)
	Glow(ns)
	H.eq(f.glow:IsShown(), false, "out of a fight: no glow")
	w.combat = true
	Glow(ns)
	H.eq(f.glow:IsShown(), true, "the icon glows")
	w.auras["Lightning Shield"] = { auraInstanceID = 901, duration = 600, expirationTime = 700 }
	Glow(ns)
	H.eq(f.glow:IsShown(), false, "cast: it stops")
end)

H.test("the buff glow and the racial glow never clear each other", function()
	local w, ns = World()
	ns.HUDini:SetAlertGlow("racial", 20594)
	Glow(ns)
	w.combat = true
	H.eq(Glow(ns), 324, "the buff glow")
	w.auras["Lightning Shield"] = { auraInstanceID = 901, duration = 600, expirationTime = 700 }
	Glow(ns)
	H.eq(ns.HUDini.alertGlow.racial, 20594, "the racial glow stays")
end)
