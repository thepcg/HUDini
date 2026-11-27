-- Your pet needs you (TICK-0192, D-047). The class file's pet field: one icon
-- left of your health bar. Out of a fight, a dead pet shows the revive spell
-- and an unhappy Hunter pet the feed spell; no pet out shows the call spell
-- (a Warlock's last summon), in and out of a fight. Nothing while you are
-- dead, mounted or on a taxi, or while a sacrifice buff is on you. What the
-- player sees needs DK's play.

local IDS = {
	["Revive Pet"] = 982, ["Call Pet"] = 883, ["Feed Pet"] = 6991,
	["Summon Imp"] = 688, ["Summon Voidwalker"] = 697, ["Summon Succubus"] = 712,
}
local HUNTER_PET = { revive = "Revive Pet", call = { "Call Pet" }, feed = "Feed Pet" }
local WARLOCK_PET = {
	call = { "Summon Imp", "Summon Voidwalker", "Summon Succubus" },
	sacrifice = { "Burning Wish", "Fel Stamina" },
}

-- A world of this class with this pet field. w.pet: nil (none out),
-- "alive" or "dead"; w.hunterPet: HasPetUI's second answer; w.happy: the
-- mood (1 unhappy); w.known[name]: you know the spell; w.auras[name]: the
-- buff on you; w.hide: your auras are hidden (a fight, PvP), so no read
-- finds them; w.secret[v]: the game hides the value v (harness.lua: flag
-- the same value that works plain).
local DEAD = "dead pet" -- UnitIsDead("pet")'s answer for a dead pet: its own value to flag
local function World(class, pet, known)
	local w = H.world()
	local env = w.env
	w.class, w.className = class, class:sub(1, 1) .. class:sub(2):lower()
	w.known, w.auras = known or {}, {}
	w.hunterPet, w.happy = class == "HUNTER", 3
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.hide == true end }
	env.C_Spell.GetSpellInfo = function(name)
		if IDS[name] then return { spellID = IDS[name] } end
	end
	env.C_Spell.GetSpellTexture = function(id) return id end
	env.C_Spell.GetSpellName = function(id)
		for name, n in pairs(IDS) do
			if n == id then return name end
		end
	end
	env.IsPlayerSpell = function(id)
		for name, n in pairs(IDS) do
			if n == id then return w.known[name] == true end
		end
		return false
	end
	local exists = env.UnitExists
	env.UnitExists = function(unit)
		if unit == "pet" then return w.pet ~= nil end
		return exists(unit)
	end
	env.UnitIsDead = function(unit)
		if unit == "pet" then return w.pet == "dead" and DEAD or false end
		return false
	end
	env.HasPetUI = function() return w.pet ~= nil, w.pet ~= nil and w.hunterPet end
	env.C_PetInfo = { GetPetHappiness = function() return w.happy end }
	env.IsMounted = function() return w.mounted == true end
	env.UnitOnTaxi = function() return w.taxi == true end
	env.UnitIsDeadOrGhost = function(unit) return unit == "player" and w.ghost == true end
	local ns = w:loadAddon()
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.hide then return nil end
		return w.auras[name]
	end
	ns.RegisterClass(class, { pet = pet })
	-- The harness keeps no texture file: keep the last one here.
	ns.leftIcons.pet.tex.SetTexture = function(self, file) self.file = file end
	ns.UpdateAlerts()
	return w, ns
end

local function Icon(ns) return ns.leftIcons.pet end
local function Shown(ns) return Icon(ns) ~= nil and Icon(ns):IsShown() end
-- The need on show, or nil.
local function Need(ns)
	ns.UpdatePetAlert()
	return Shown(ns) and Icon(ns).need or nil
end
local function Texture(ns)
	return Icon(ns).tex.file
end

local ALL_HUNTER = { ["Revive Pet"] = true, ["Call Pet"] = true, ["Feed Pet"] = true }

H.test("a Hunter's pet dies; out of the fight the Revive Pet icon shows", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	w.pet = "alive"
	w:fire("UNIT_PET", "player")
	H.eq(Shown(ns), false, "a live, happy pet: no icon")
	w.combat = true
	w.pet = "dead"
	w:fire("UNIT_HEALTH", "pet")
	H.eq(Shown(ns), false, "dead in the fight: no icon, Call Pet cannot call it")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Shown(ns), true, "the fight is over: the icon")
	H.eq(Icon(ns).need, "revive")
	H.eq(Texture(ns), IDS["Revive Pet"], "the Revive Pet icon")
	w.pet = "alive"
	w:fire("UNIT_PET", "player")
	H.eq(Shown(ns), false, "revived: gone")
end)

H.test("the corpse goes: a pet seen dead still shows Revive Pet, until a live pet is out", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	w.pet = "dead"
	H.eq(Need(ns), "revive")
	w.pet = nil
	w:fire("UNIT_PET", "player")
	H.eq(Need(ns), "revive", "no pet out, but HUDini saw it die")
	w.pet = "alive"
	H.eq(Need(ns), nil, "a live pet")
	w.pet = nil
	H.eq(Need(ns), "call", "dismissed: Call Pet")
	H.eq(Texture(ns), IDS["Call Pet"])
end)

H.test("no pet out shows Call Pet, in and out of a fight", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	H.eq(Need(ns), "call", "out of a fight")
	w.combat = true
	H.eq(Need(ns), "call", "in a fight")
end)

H.test("a spell you do not know yet shows nothing", function()
	local w, ns = World("HUNTER", HUNTER_PET, {})
	H.eq(Need(ns), nil, "level 8: no Call Pet")
	w.pet = "dead"
	H.eq(Need(ns), nil, "no Revive Pet")
	w.known["Call Pet"] = true
	H.eq(Need(ns), nil, "a dead pet does not fall back to Call Pet")
	w.pet = nil
	w.known["Revive Pet"] = true
	H.eq(Need(ns), "revive")
end)

H.test("an unhappy Hunter pet shows Feed Pet out of a fight only", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	w.pet, w.happy = "alive", 1
	w:fire("UNIT_HAPPINESS", "pet")
	H.eq(Shown(ns), true, "unhappy: heard at UNIT_HAPPINESS")
	H.eq(Icon(ns).need, "feed")
	H.eq(Texture(ns), IDS["Feed Pet"])
	w.happy = 2
	H.eq(Need(ns), nil, "content")
	w.happy = 1
	w.combat = true
	H.eq(Need(ns), nil, "in a fight")
	w.combat = false
	H.eq(Need(ns), "feed", "plain again")
	w.secret[1] = true
	H.eq(Need(ns), nil, "a secret mood")
end)

H.test("a demon with a mood is not fed", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	w.pet, w.happy, w.hunterPet = "alive", 1, false
	H.eq(Need(ns), nil, "HasPetUI: not a Hunter pet")
end)

H.test("dead, a ghost, mounted or on a taxi: no icon", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	H.eq(Need(ns), "call")
	w.mounted = true
	H.eq(Need(ns), nil, "mounted")
	w.mounted, w.taxi = false, true
	H.eq(Need(ns), nil, "on a taxi")
	w.taxi, w.ghost = false, true
	H.eq(Need(ns), nil, "a ghost")
	w.ghost = false
	H.eq(Need(ns), "call", "back")
end)

H.test("a secret dead read shows nothing, and is not a live pet", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	w.pet, w.happy = "dead", 1
	H.eq(Need(ns), "revive", "plain: dead")
	w.secret[DEAD] = true
	H.eq(Need(ns), nil, "secret: no Feed Pet for an unhappy pet it cannot see")
end)

H.test("a secret dead read keeps what HUDini saw before", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	w.pet = "dead"
	H.eq(Need(ns), "revive")
	w.secret[DEAD] = true
	H.eq(Need(ns), nil)
	w.pet, w.secret[DEAD] = nil, nil
	H.eq(Need(ns), "revive", "still seen dead")
end)

H.test("the alert off, or the health bar off: no icon", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	H.eq(ns.GetPetAlert(), true, "nothing saved: on")
	H.eq(ns.SetPetAlert(false), true, "changed")
	H.eq(ns.ClassDB().petOn, false, "saved per class, not as pet")
	H.eq(ns.ClassDB().pet, nil)
	H.eq(Shown(ns), false, "off")
	H.eq(ns.SetPetAlert(false), false, "no change")
	ns.SetPetAlert(true)
	H.eq(Need(ns), "call")
	w.env.HUDiniDB.showHealth = false
	H.eq(Need(ns), nil, "no health bar")
end)

H.test("a class with no pet field never shows the icon", function()
	local _, ns = World("MAGE", nil, ALL_HUNTER)
	H.eq(Need(ns), nil)
end)

H.test("a Warlock with no demon sees the last summon cast, else the first known", function()
	local w, ns = World("WARLOCK", WARLOCK_PET, { ["Summon Imp"] = true, ["Summon Voidwalker"] = true })
	H.eq(Need(ns), "call")
	H.eq(Texture(ns), IDS["Summon Imp"], "none cast yet: the first you know")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", IDS["Summon Voidwalker"])
	H.eq(ns.ClassDB().petLast, "Summon Voidwalker", "saved")
	w.pet = "alive"
	w:fire("UNIT_PET", "player")
	H.eq(Shown(ns), false, "the demon is out")
	w.pet = nil
	w:fire("UNIT_PET", "player")
	H.eq(Texture(ns), IDS["Summon Voidwalker"], "it dies: the Voidwalker")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 133)
	H.eq(ns.ClassDB().petLast, "Summon Voidwalker", "another spell changes nothing")
	-- A secret spell ID: never compared, never saved (it throws in the game).
	local asked = 0
	local spellID = ns.SpellID
	ns.SpellID = function(spell)
		if w.secret[IDS["Summon Imp"]] then asked = asked + 1 end
		return spellID(spell)
	end
	w.secret[IDS["Summon Imp"]] = true
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", IDS["Summon Imp"])
	w.secret[IDS["Summon Imp"]] = nil
	ns.SpellID = spellID
	H.eq(asked, 0, "the secret ID meets no compare")
	H.eq(ns.ClassDB().petLast, "Summon Voidwalker", "not saved")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", IDS["Summon Imp"])
	H.eq(ns.ClassDB().petLast, "Summon Imp", "the same ID plain: saved")
	ns.ClassDB().petLast = "Summon Succubus"
	H.eq(Need(ns), "call")
	H.eq(Texture(ns), IDS["Summon Imp"], "a last summon you do not know: the first you know")
	w.pet = "dead"
	H.eq(Need(ns), "call", "no revive spell: a dead demon shows the summon")
end)

H.test("a sacrifice buff keeps no demon quiet, and a fight keeps that answer", function()
	local w, ns = World("WARLOCK", WARLOCK_PET, { ["Summon Imp"] = true })
	w.auras["Burning Wish"] = { spellId = 18789 }
	H.eq(Need(ns), nil, "sacrificed")
	w.combat, w.hide = true, true
	H.eq(Need(ns), nil, "in the fight the buffs hide: still sacrificed")
	w.combat = false
	H.eq(Need(ns), nil, "out of the fight but still hidden: still sacrificed")
	w.combat, w.hide = false, false
	w.auras["Burning Wish"] = nil
	H.eq(Need(ns), "call", "the buff ran out: the summon")
	w.combat, w.hide = true, true
	H.eq(Need(ns), "call", "a fight with no sacrifice before it")
end)

H.test("auras hidden out of a fight (PvP): the sacrifice answer stays", function()
	local w, ns = World("WARLOCK", WARLOCK_PET, { ["Summon Imp"] = true })
	w.auras["Burning Wish"] = { spellId = 18789 }
	H.eq(Need(ns), nil, "sacrificed")
	w.hide = true
	w.auras["Burning Wish"] = nil
	H.eq(Need(ns), nil, "not found while hidden: still sacrificed")
	w.hide = false
	H.eq(Need(ns), "call", "shown again and gone: the summon")
end)

H.test("a secret sacrifice buff answer keeps the old answer", function()
	local w, ns = World("WARLOCK", WARLOCK_PET, { ["Summon Imp"] = true })
	H.eq(Need(ns), "call", "no buff")
	local buff = { spellId = 18789 }
	w.auras["Burning Wish"] = buff
	w.secret[buff] = true
	H.eq(Need(ns), "call", "secret: not taken as sacrificed")
	w.secret[buff] = nil
	H.eq(Need(ns), nil, "the same answer plain: sacrificed")
end)

H.test("a sacrificed demon that reads as a dead pet shows no summon", function()
	local w, ns = World("WARLOCK", WARLOCK_PET, { ["Summon Imp"] = true })
	w.pet = "dead"
	H.eq(Need(ns), "call", "dead, no sacrifice: the summon")
	w.auras["Burning Wish"] = { spellId = 18789 }
	H.eq(Need(ns), nil, "dead and sacrificed")
end)

H.test("test mode shows the pet sample for a class with a pet field", function()
	local _, ns = World("HUNTER", HUNTER_PET, {})
	ns.ShowAlertSamples(true)
	H.eq(Shown(ns), true, "the sample")
	ns.UpdatePetAlert()
	H.eq(Shown(ns), true, "the real update leaves it")
	ns.ShowAlertSamples(false)
	H.eq(Shown(ns), false, "no spell known: gone again")
	local _, mage = World("MAGE", nil, {})
	mage.ShowAlertSamples(true)
	H.eq(Shown(mage), false, "a Mage: none")
end)

H.test("/hud debug aura reports the pet reads", function()
	local w, ns = World("HUNTER", HUNTER_PET, ALL_HUNTER)
	w.pet, w.happy = "alive", 1
	ns.UpdatePetAlert()
	local lines = {}
	ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
	local text = table.concat(lines, "\n")
	H.ok(text:find("Pet alert on", 1, true), "the row")
	H.ok(text:find("now feed", 1, true), "what shows")
	H.ok(text:find("pet out true, dead false", 1, true), "the reads")
	H.ok(text:find("happiness 1", 1, true), "the mood")
end)
