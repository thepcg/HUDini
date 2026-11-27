-- The tank buff (TICK-0208). A class file's tankBuff = { buff = "Righteous
-- Fury", with = { "Seal of Fury" } }: in a fight, a Paladin who knows
-- Righteous Fury, has Seal of Fury on and no Righteous Fury gets its icon
-- left of the health bar. Another seal: no icon. A "Your class" row turns it
-- off (ns.SetTankBuff). A fight hides your auras, so what HUDini last saw,
-- or a cast it saw, counts (Auras.lua BuffState, OnCast).

local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

local IDS = {
	["Righteous Fury"] = 25780,
	["Seal of Fury"] = 1311649,
	["Seal of Righteousness"] = 20154,
	["Arcane Intellect"] = 1459,
}

local function NameOf(id)
	for n, i in pairs(IDS) do
		if i == id then return n end
	end
end

-- The test Paladin (classes_fixture.lua), with Seal of Fury and the tank
-- buff added, or opts.class. w.auras[name]: the buff is on you. w.inFight:
-- your auras are hidden (a read gives nil). w.known: the spells you know
-- (all of IDS when not given).
local function World(opts)
	opts = opts or {}
	local w = Classes.Use(H.world())
	w.class, w.className = opts.class or "PALADIN", opts.className or "Paladin"
	local env = w.env
	env.C_Spell.GetSpellName = function(id) return NameOf(id) end
	env.C_Spell.GetSpellInfo = function(name)
		if IDS[name] then return { spellID = IDS[name], name = name } end
	end
	-- The harness keeps no texture: w.textures lists each spell asked for.
	w.textures = {}
	env.C_Spell.GetSpellTexture = function(id)
		w.textures[#w.textures + 1] = id
		return id
	end
	env.IsPlayerSpell = function(id)
		local name = NameOf(id)
		if w.known then return name ~= nil and w.known[name] == true end
		return name ~= nil
	end
	-- No aura containers: the keep-up list's watch plays no part here.
	env.CreateFrame = (function(make)
		return function(kind, ...)
			if kind == "AuraContainer" then error("Unknown frame type 'AuraContainer'") end
			return make(kind, ...)
		end
	end)(env.CreateFrame)
	local ns = w:loadAddon()
	if not opts.class then
		local paladin = H.copy(Classes.profiles.PALADIN)
		table.insert(paladin.keepUp, 2, "Seal of Fury")
		paladin.tankBuff = { buff = "Righteous Fury", with = { "Seal of Fury" } }
		ns.RegisterClass("PALADIN", paladin)
	end
	w.auras = {}
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.inFight then return nil end
		return w.auras[name]
	end
	env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
		if w.inFight then return nil end
		local list = {}
		for _, data in pairs(w.auras) do list[#list + 1] = data end
		return list[i]
	end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.inFight == true end }
	local db = env.HUDiniDB
	db.showHealth = true
	ns.HUDini.body:Show()
	w.time = 100
	return w, ns
end

local function On(w, name, length)
	w.auras[name] = { auraInstanceID = IDS[name], spellId = IDS[name], name = name,
		duration = length, expirationTime = w.time + length }
end

local function StartFight(w)
	w.combat = false
	w:fire("PLAYER_REGEN_DISABLED")
	w.combat = true
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
	w.inFight = true
	w:runTimers()
end

local function EndFight(w)
	w.combat, w.inFight = false, false
	w:fire("PLAYER_REGEN_ENABLED")
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
	w:runTimers()
end

local function Icon(ns)
	return ns.leftIcons.tankBuff
end

local function Shows(ns)
	ns.UpdateAlerts()
	local icon = Icon(ns)
	return icon ~= nil and icon:IsShown()
end

H.test("tank: Seal of Fury on, Righteous Fury off, in a fight: its icon shows", function()
	local w, ns = World()
	On(w, "Seal of Fury", 30)
	H.eq(Shows(ns), false, "out of a fight: no icon")
	StartFight(w)
	H.eq(Shows(ns), true, "in the fight: the icon")
	H.eq(w.textures[#w.textures], IDS["Righteous Fury"], "Righteous Fury's own icon")
	EndFight(w)
	H.eq(Shows(ns), false, "after the fight: no icon")
end)

H.test("tank: Seal of Righteousness instead of Seal of Fury: no icon", function()
	local w, ns = World()
	On(w, "Seal of Righteousness", 30)
	ns.UpdateAlerts()
	StartFight(w)
	H.eq(Shows(ns), false, "another seal: no icon")
end)

H.test("tank: Righteous Fury on with Seal of Fury: no icon", function()
	local w, ns = World()
	On(w, "Seal of Fury", 30)
	On(w, "Righteous Fury", 1800)
	ns.UpdateAlerts()
	StartFight(w)
	H.eq(Shows(ns), false, "both on: no icon")
end)

H.test("tank: no seal at all: no icon", function()
	local w, ns = World()
	ns.UpdateAlerts()
	StartFight(w)
	H.eq(Shows(ns), false, "no seal: no icon")
end)

H.test("tank: the Your class row off: no icon; on again: the icon", function()
	local w, ns = World()
	On(w, "Seal of Fury", 30)
	H.eq(ns.GetTankBuff(), true, "starts on")
	H.eq(ns.SetTankBuff(false), true, "turned off")
	H.eq(ns.ClassDB().tankBuffOn, false, "saved per class, not as the class file key")
	H.eq(type(ns.ClassValue("tankBuff")), "table", "the class file's tankBuff still reads")
	H.eq(ns.SetTankBuff(false), false, "off again changes nothing")
	StartFight(w)
	H.eq(Shows(ns), false, "off: no icon")
	H.eq(ns.SetTankBuff(true), true, "turned on")
	H.eq(Shows(ns), true, "on: the icon")
end)

H.test("tank: a Paladin who does not know Righteous Fury gets no icon and no row", function()
	local w, ns = World()
	w.known = { ["Seal of Fury"] = true, ["Seal of Righteousness"] = true }
	On(w, "Seal of Fury", 30)
	H.eq(ns.TankBuffSpell(), nil, "no row to show")
	StartFight(w)
	H.eq(Shows(ns), false, "no icon")
	w.known["Righteous Fury"] = true
	H.eq(ns.TankBuffSpell(), IDS["Righteous Fury"], "known: the row shows")
end)

H.test("tank: a class with no tank buff gets no icon and no row", function()
	local w, ns = World({ class = "MAGE", className = "Mage" })
	On(w, "Seal of Fury", 30)
	H.eq(ns.TankBuffSpell(), nil, "no row")
	H.eq(ns.TankBuffMissing(), nil, "nothing due")
	StartFight(w)
	H.eq(Shows(ns), false, "no icon")
end)

H.test("tank: the seal last seen on counts in the fight, to its end", function()
	local w, ns = World()
	On(w, "Seal of Fury", 30)
	ns.UpdateAlerts()
	StartFight(w)
	H.eq(Shows(ns), true, "hidden auras: the seal last seen on counts")
	w.time = w.time + 31
	H.eq(Shows(ns), false, "past the seal's end: not tanking, no icon")
end)

H.test("tank: Righteous Fury cast in the fight takes the icon down", function()
	local w, ns = World()
	On(w, "Seal of Fury", 30)
	ns.UpdateAlerts()
	StartFight(w)
	H.eq(Shows(ns), true, "the icon")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", IDS["Righteous Fury"])
	H.eq(Icon(ns):IsShown(), false, "cast: the icon goes")
	H.eq(Shows(ns), false, "and stays down")
end)

H.test("tank: Seal of Fury cast in the fight brings the icon", function()
	local w, ns = World()
	On(w, "Seal of Righteousness", 30)
	ns.UpdateAlerts()
	StartFight(w)
	H.eq(Shows(ns), false, "another seal: no icon")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", IDS["Seal of Fury"])
	H.eq(Shows(ns), true, "Seal of Fury cast: the icon")
end)

H.test("tank: Righteous Fury is still never learned as a buff to keep", function()
	local w, ns = World()
	On(w, "Righteous Fury", 1800)
	ns.UpdateBuffMissing()
	H.eq((ns.ClassDB().buffSpells or {})["Righteous Fury"], nil, "not learned")
end)

H.test("tank: Righteous Fury never seen (auras hidden since login): no icon", function()
	local w, ns = World()
	w.combat, w.inFight = true, true
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", IDS["Seal of Fury"])
	H.eq(Shows(ns), false, "a buff the game will not answer for counts as on")
end)

H.test("tank: the first Seal of Fury since login, cast in a fight, ends after 30 seconds", function()
	local w, ns = World()
	-- No Seal of Fury read since login: HUDini has no length for it.
	On(w, "Seal of Righteousness", 30)
	ns.UpdateAlerts()
	StartFight(w)
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", IDS["Seal of Fury"])
	H.eq(Shows(ns), true, "cast: the icon")
	w.time = w.time + 29
	H.eq(Shows(ns), true, "29 seconds on: still the icon")
	w.time = w.time + 2
	H.eq(Shows(ns), false, "past 30 seconds: the seal counts as ended, no icon")
end)

H.test("tank: in a fight its icon sits left of the health bar", function()
	local w, ns = World()
	local bar = ns.GetBar("health")
	On(w, "Seal of Fury", 30)
	StartFight(w)
	H.eq(Shows(ns), true, "the icon")
	local point, to, rel = Icon(ns):GetPoint(1)
	H.eq(point, "RIGHT", "its right edge")
	H.ok(to == bar, "on the health bar")
	H.eq(rel, "LEFT", "at the bar's left edge")
end)

H.test("tank: test mode puts the samples in order: keep-up, tank buff, your buff", function()
	local w, ns = World()
	ns.ShowAlertSamples(true)
	local bar = ns.GetBar("health")
	local keepUp, tank = ns.leftIcons.keepUp, Icon(ns)
	H.ok(keepUp:IsShown() and tank:IsShown(), "both samples show")
	local _, to = keepUp:GetPoint(1)
	H.ok(to == bar, "the keep-up sample on the bar")
	_, to = tank:GetPoint(1)
	H.ok(to == keepUp, "the tank sample left of the keep-up sample")
	local own = ns.leftIcons.ownBuff
	H.ok(own ~= nil and own:IsShown(), "your buff's sample")
	_, to = own:GetPoint(1)
	H.ok(to == tank, "your buff's sample left of the tank sample")
end)

H.test("tank: test mode shows no tank sample when you do not know the buff", function()
	local w, ns = World()
	w.known = { ["Seal of Fury"] = true }
	ns.ShowAlertSamples(true)
	H.eq(Icon(ns):IsShown(), false, "no sample for a row you do not see")
end)

H.test("tank: the health bar off, or hidden: no icon", function()
	local w, ns = World()
	On(w, "Seal of Fury", 30)
	StartFight(w)
	H.eq(Shows(ns), true, "the icon")
	w.env.HUDiniDB.showHealth = false
	H.eq(Shows(ns), false, "the health bar turned off: no icon")
	w.env.HUDiniDB.showHealth = true
	ns.GetBar("health"):Hide()
	H.eq(Shows(ns), false, "the health bar hidden: no icon")
end)

-- With the buff-missing sound on: one sound when the icon comes, none while
-- it stays. Seal of Fury is on the Paladin's keep-up list: when it ends, the
-- keep-up icon takes the tank icon's place with no new sound (an icon was
-- missing all along). Cast again, the keep-up icon goes first, then the tank
-- icon comes back and sounds. So a tank with no Righteous Fury hears one
-- sound each time the seal is cast again, about every 30 seconds (the
-- ticket's Notes, for DK's veto).
H.test("tank: its icon sounds once when it comes, and again with each new Seal of Fury", function()
	local w, ns = World()
	local sounds = {}
	w.env.PlaySound = function(kit) sounds[#sounds + 1] = kit return true end
	ns.SetKeepUpSound(true)
	On(w, "Seal of Fury", 30)
	ns.UpdateAlerts()
	H.eq(#sounds, 0, "out of a fight: no sound")
	StartFight(w)
	H.eq(Shows(ns), true, "the icon")
	H.eq(#sounds, 1, "the icon comes: one sound")
	ns.UpdateAlerts()
	ns.UpdateAlerts()
	H.eq(#sounds, 1, "it stays: no more sound")
	w.time = w.time + 31
	H.eq(Shows(ns), false, "the seal ended: no tank icon")
	H.eq(ns.leftIcons.keepUp:IsShown(), true, "the keep-up icon instead")
	H.eq(#sounds, 1, "an icon was missing all along: no new sound")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", IDS["Seal of Fury"])
	H.eq(Icon(ns):IsShown(), true, "the seal again: the tank icon")
	H.eq(ns.leftIcons.keepUp:IsShown(), false, "the keep-up icon goes")
	H.eq(#sounds, 2, "the tank icon sounds again")
end)
