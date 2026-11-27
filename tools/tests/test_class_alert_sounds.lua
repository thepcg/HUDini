-- The class alert sounds (TICK-0234, D-051). The interrupt outline, each
-- dispel type and the purge icons play their own sound once as the alert
-- starts showing; the buff missing sound can repeat while its icon shows,
-- 2 seconds after each play ends (TICK-0249). All off at the start. What
-- the player hears needs DK's play.

local IDS = {
	["Wind Shear"] = 57994, ["Cure Poison"] = 526, ["Cure Disease"] = 2870,
	["Purge"] = 370, ["Cleanse"] = 4987, ["Lightning Shield"] = 324,
}

-- A Shaman (or a profile of your own) who knows every spell above.
-- w.debuffs: your dispellable debuffs (HARMFUL|RAID), in slot order.
-- w.buffs: the target's buffs. w.guid: the target's GUID. w.auras[name]:
-- your buff by name. w.hostile: what UnitCanAttack says (true at the
-- start). w.secret[v]: the game hides the value v.
local function World(profile)
	local w = H.world()
	local env = w.env
	w.class, w.className = "SHAMAN", "Shaman"
	w.debuffs, w.buffs, w.auras, w.secret = {}, {}, {}, {}
	w.guid, w.hostile = "Creature-1", true
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_Spell.GetSpellInfo = function(name)
		if IDS[name] then return { spellID = IDS[name] } end
	end
	env.C_Spell.GetSpellName = function(id)
		for name, n in pairs(IDS) do
			if n == id then return name end
		end
	end
	env.C_Spell.GetSpellTexture = function(id) return id end
	env.C_Spell.GetSpellCooldown = function() return { isActive = false } end
	env.IsPlayerSpell = function(id)
		for _, n in pairs(IDS) do
			if n == id then return true end
		end
		return false
	end
	-- w.hideHostile: the game hides its answer (from the moment it gives it,
	-- so the plain false of the cooldown read before it stays plain).
	env.UnitCanAttack = function()
		if w.hideHostile then w.secret[w.hostile] = true end
		return w.hostile
	end
	env.UnitGUID = function(unit)
		if unit == "target" then return w.hasTarget and w.guid or nil end
		return "Player-1-0001"
	end
	local ns = w:loadAddon()
	env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		if unit == "player" and filter == "HARMFUL|RAID" then return w.debuffs[i] end
		if unit == "target" and filter == "HELPFUL" then return w.buffs[i] end
	end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name) return w.auras[name] end
	ns.RegisterClass("SHAMAN", profile or {
		interrupt = "Wind Shear",
		dispel    = { Poison = "Cure Poison", Disease = "Cure Disease" },
		purge     = "Purge",
		keepUp    = { "Lightning Shield" },
	})
	local db = env.HUDiniDB
	db.glowOnKickable, db.warnDispel, db.showPower = true, true, true
	db.showPurgeable, db.showTargetHealth = true, true
	db.warnKeepUp, db.showHealth = true, true
	-- Each sound that plays, by its key.
	w.played = {}
	ns.PlaySoundChoice = function(saved, default)
		local c = ns.SoundChoice(saved, default)
		w.played[#w.played + 1] = c and c.key or "?"
		return c and c.key
	end
	return w, ns
end

-- The sounds played since the last call, joined: "voiceKick,voicePoison".
local function Heard(w)
	local out = table.concat(w.played, ",")
	w.played = {}
	return out
end

local function Debuff(dispelName) return { dispelName = dispelName, auraInstanceID = 1 } end

--------------------------------------------------------------------------------
-- Defaults and the saved values
--------------------------------------------------------------------------------

H.test("every class alert sound and the repeat start off", function()
	local w, ns = World()
	for _, a in ipairs(ns.CLASS_ALERT_SOUNDS) do
		H.eq(ns.GetClassAlertSound(a.setting), false, a.setting)
	end
	H.eq(ns.GetKeepUpRepeat(), false, "repeat")
	-- Every alert shows: nothing plays.
	ns.OnTargetCast(false)
	w.debuffs[1] = Debuff("Poison")
	w.hasTarget, w.buffs[1] = true, { dispelName = "Magic", icon = 1 }
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "no sound with every alert showing")
end)

H.test("a sound saves as a choice per class; off saves nothing", function()
	local w, ns = World()
	H.eq(ns.SetClassAlertSound("soundInterrupt", "voiceKick"), true)
	local saved = ns.ClassDB().soundInterrupt
	H.eq(saved.key, "voiceKick")
	H.eq(saved.volume, 100)
	H.eq(ns.SetClassAlertSound("soundInterrupt", { key = "voiceKick", volume = 100 }), false, "the same")
	H.eq(ns.SetClassAlertSound("soundInterrupt", { key = "voiceKick", volume = 50 }), true, "a new volume")
	H.eq(ns.GetClassAlertSound("soundInterrupt").volume, 50)
	H.eq(ns.SetClassAlertSound("soundInterrupt", "voiceStab"), true, "a key")
	H.eq(ns.GetClassAlertSound("soundInterrupt").volume, 50, "a key keeps the volume")
	H.eq(ns.SetClassAlertSound("soundInterrupt", "noSuchSound"), false, "a key not in the list")
	H.eq(ns.SetClassAlertSound("soundNoSuchAlert", "voiceKick"), false, "not an alert")
	H.eq(ns.SetClassAlertSound("soundInterrupt", 5), false, "a number")
	H.eq(ns.GetClassAlertSound("soundInterrupt").key, "voiceStab", "kept")
	H.eq(ns.SetClassAlertSound("soundInterrupt", "off"), true)
	H.eq(ns.ClassDB().soundInterrupt, nil, "off saves nothing")
	H.eq(ns.SetClassAlertSound("soundInterrupt", false), false, "already off")
	H.eq(ns.SetClassAlertSound("soundPurge", true), true, "true: the alert's own sound")
	H.eq(ns.GetClassAlertSound("soundPurge"), true)
	H.eq(w.env.HUDiniDB.classes.SHAMAN.soundPurge, true, "in the class's table")
end)

H.test("the alerts your class has", function()
	local _, ns = World()
	local list = {}
	for _, a in ipairs(ns.ClassAlertSounds()) do list[#list + 1] = a.setting end
	H.eq(table.concat(list, ","), "soundInterrupt,soundPoison,soundDisease,soundPurge")
end)

--------------------------------------------------------------------------------
-- The interrupt
--------------------------------------------------------------------------------

H.test("the interrupt sound plays once per cast", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundInterrupt", "voiceKick")
	ns.OnTargetCast(false)
	H.eq(Heard(w), "voiceKick", "the cast starts")
	for _ = 1, 5 do ns.OnTargetCast(false) end
	H.eq(Heard(w), "", "the cast bar refreshes")
	ns.OnTargetCast(nil, true)
	ns.OnTargetCast(false)
	H.eq(Heard(w), "voiceKick", "the next cast")
end)

H.test("an outline that hides and comes back in one cast plays once", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundInterrupt", "voiceKick")
	local usable = true
	w.env.C_Spell.IsSpellUsable = function() return usable end
	ns.OnTargetCast(false)
	H.eq(Heard(w), "voiceKick")
	usable = false
	ns.OnTargetCast(false)
	usable = true
	ns.OnTargetCast(false)
	H.eq(Heard(w), "", "not enough energy for a moment: the same cast")
	ns.OnTargetCast(nil, true)
	ns.OnTargetCast(false)
	H.eq(Heard(w), "voiceKick", "the next cast")
end)

H.test("a new target's cast plays again", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundInterrupt", "voiceKick")
	w.hasTarget = true
	-- As Bars.lua: on a new target the cast bar refreshes the new caster's
	-- cast with no "ended" first (here, the harness gives no cast to read).
	ns.UpdateCastBars = function() ns.OnTargetCast(false) end
	ns.OnTargetCast(false)
	H.eq(Heard(w), "voiceKick")
	ns.UpdateCastBars()
	H.eq(Heard(w), "", "a refresh of the same cast")
	-- The new caster: once, on the event or at the next refresh (the cast
	-- bar may look before the alerts hear of the new target).
	w:fire("PLAYER_TARGET_CHANGED")
	ns.UpdateCastBars()
	H.eq(Heard(w), "voiceKick", "the new target's cast")
	ns.UpdateCastBars()
	H.eq(Heard(w), "", "and no more")
end)

H.test("no interrupt sound for a target you plainly cannot attack; a hidden answer plays", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundInterrupt", "voiceKick")
	w.hostile = false
	ns.OnTargetCast(false)
	H.eq(Heard(w), "", "a friend mounts")
	w.hideHostile = true
	ns.OnTargetCast(false)
	w.secret[false] = nil
	H.eq(Heard(w), "voiceKick", "secret: never read, so it plays")
end)

H.test("a cast that becomes interruptible plays then", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundInterrupt", "voiceKick")
	ns.OnTargetCast(true)
	H.eq(Heard(w), "", "shielded")
	ns.OnTargetCast(false)
	H.eq(Heard(w), "voiceKick", "the shield drops in the cast")
end)

H.test("an interrupt sound turned on in a cast plays at the next refresh", function()
	local w, ns = World()
	ns.OnTargetCast(false)
	H.eq(Heard(w), "", "the sound off")
	ns.SetClassAlertSound("soundInterrupt", "voiceKick")
	ns.OnTargetCast(false)
	H.eq(Heard(w), "voiceKick", "on now, the same cast")
end)

H.test("the interrupt sound waits for your interrupt to be ready", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundInterrupt", "voiceKick")
	w.env.C_Spell.GetSpellCooldown = function() return { isActive = true } end
	ns.OnTargetCast(false)
	H.eq(Heard(w), "", "on cooldown: no outline, no sound")
	w.env.C_Spell.GetSpellCooldown = function() return { isActive = false } end
	ns.OnTargetCast(false)
	H.eq(Heard(w), "voiceKick", "ready in the cast")
end)

H.test("no interrupt sound for a cast the game plainly says is shielded; a hidden answer plays", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundInterrupt", "voiceKick")
	ns.OnTargetCast(true)
	H.eq(Heard(w), "", "plain: cannot be interrupted")
	ns.OnTargetCast(nil, true)
	w.secret[true] = true
	ns.OnTargetCast(true)
	w.secret[true] = nil
	H.eq(Heard(w), "voiceKick", "secret: never read, so it plays")
end)

--------------------------------------------------------------------------------
-- Dispel
--------------------------------------------------------------------------------

H.test("a dispel sound plays once as the tint comes up, by type", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundPoison", "voicePoison")
	ns.SetClassAlertSound("soundDisease", "voiceWarning")
	w.debuffs[1] = Debuff("Poison")
	ns.UpdateAlerts()
	H.eq(Heard(w), "voicePoison")
	ns.UpdateAlerts()
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "the same debuff: once")
	w.debuffs[1] = Debuff("Disease")
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceWarning", "another type")
	w.debuffs[1] = nil
	ns.UpdateAlerts()
	H.eq(ns.powerTint, nil)
	w.debuffs[1] = Debuff("Disease")
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceWarning", "gone and back")
end)

H.test("a dispel type with its sound off plays nothing", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundPoison", "voicePoison")
	w.debuffs[1] = Debuff("Disease")
	ns.UpdateAlerts()
	H.ok(ns.powerTint ~= nil, "the tint shows")
	H.eq(Heard(w), "")
end)

H.test("a debuff whose type the game hides", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundDisease", "voiceWarning")
	local aura = Debuff("Poison")
	w.debuffs[1] = aura
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "plain: a poison, its sound off")
	w.secret[aura] = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "the same debuff, its type now hidden: no new sound")
	w.debuffs[1] = nil
	ns.UpdateAlerts()
	w.debuffs[1] = aura
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceWarning", "hidden from the start: the first type's sound that is on")
	w.secret[aura] = nil
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "its type read again: the same debuff")
end)

H.test("a hidden debuff plays only a type your class removes", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundMagic", "voiceKick")
	ns.SetClassAlertSound("soundDisease", "voiceWarning")
	local aura = Debuff("Poison")
	w.secret[aura] = true
	w.debuffs[1] = aura
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceWarning", "a Shaman removes no magic")
end)

H.test("a class with one dispel type hears it for a hidden debuff", function()
	local w, ns = World({ dispel = { Poison = "Cure Poison" } })
	ns.SetClassAlertSound("soundPoison", "voicePoison")
	local aura = Debuff("Poison")
	w.secret[aura] = true
	w.debuffs[1] = aura
	ns.UpdateAlerts()
	H.eq(Heard(w), "voicePoison")
end)

--------------------------------------------------------------------------------
-- Purge
--------------------------------------------------------------------------------

H.test("the purge sound plays once as the first icon comes up, and for a new target", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundPurge", "voiceShield")
	w.hasTarget = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "no buff to purge")
	w.buffs[1] = { dispelName = "Magic", icon = 1 }
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceShield")
	w.buffs[2] = { dispelName = "Magic", icon = 2 }
	ns.UpdateAlerts()
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "a second icon, and more updates")
	w.guid = "Creature-2"
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceShield", "a new target with one")
	w.buffs = {}
	ns.UpdateAlerts()
	w.buffs[1] = { dispelName = "Magic", icon = 1 }
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceShield", "gone and back")
end)

H.test("a target GUID the game hides is never compared", function()
	local w, ns = World()
	ns.SetClassAlertSound("soundPurge", "voiceShield")
	w.hasTarget = true
	w.buffs[1] = { dispelName = "Magic", icon = 1 }
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceShield")
	w.guid = "Creature-2"
	w.secret["Creature-2"] = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "secret: never compared")
	w.guid = "Creature-3"
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceShield", "plain and new: compared with the last plain one")
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "the same")
end)

--------------------------------------------------------------------------------
-- The buff missing repeat
--------------------------------------------------------------------------------

local function Shield(w)
	w.auras["Lightning Shield"] = { auraInstanceID = 7, spellId = 324, name = "Lightning Shield", duration = 600 }
end

H.test("the buff missing sound plays once with the repeat off", function()
	local w, ns = World()
	ns.SetKeepUpSound("voiceBuff")
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceBuff", "the icon comes up")
	ns.UpdateAlerts()
	w:runTickers()
	w:runTickers()
	H.eq(Heard(w), "", "no repeat")
end)

H.test("the repeat plays at each tick while the icon shows, and stops when the buff is back", function()
	local w, ns = World()
	ns.SetKeepUpSound("voiceBuff")
	H.eq(ns.SetKeepUpRepeat(true), true)
	H.eq(ns.ClassDB().keepUpRepeat, true)
	H.eq(ns.SetKeepUpRepeat(true), false, "already on")
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceBuff")
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "an update is not a tick")
	w:runTickers()
	H.eq(Heard(w), "voiceBuff", "tick 1")
	w:runTickers()
	H.eq(Heard(w), "voiceBuff", "tick 2")
	Shield(w)
	ns.UpdateAlerts()
	w:runTickers()
	H.eq(Heard(w), "", "the buff is back")
end)

H.test("the repeat stops at the fight's end, with the sound off, or with the repeat off", function()
	local w, ns = World()
	ns.SetKeepUpSound("voiceBuff")
	ns.SetKeepUpRepeat(true)
	w.combat = true
	ns.UpdateAlerts()
	Heard(w)
	w.combat = false
	ns.UpdateAlerts()
	w:runTickers()
	H.eq(Heard(w), "", "the fight ended")

	w.combat = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceBuff", "a new fight")
	ns.SetKeepUpSound(false)
	w:runTickers()
	H.eq(Heard(w), "", "the sound off")

	ns.SetKeepUpSound("voiceBuff")
	w:runTickers()
	H.eq(Heard(w), "", "the sound on again: the repeat waits for the next look")
	ns.UpdateAlerts()
	w:runTickers()
	H.eq(Heard(w), "voiceBuff", "the next look, the icon still up")
	H.eq(ns.SetKeepUpRepeat(false), true)
	H.eq(ns.ClassDB().keepUpRepeat, nil, "off saves nothing")
	w:runTickers()
	H.eq(Heard(w), "", "the repeat off")
end)

H.test("repeat turned on with the icon up starts at once", function()
	local w, ns = World()
	ns.SetKeepUpSound("voiceBuff")
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceBuff")
	ns.SetKeepUpRepeat(true)
	w:runTickers()
	H.eq(Heard(w), "voiceBuff", "the next tick, with no new look")
end)

H.test("the repeat runs where the game played the first sound", function()
	local w, ns = World()
	ns.SetKeepUpSound("voiceBuff")
	ns.SetKeepUpRepeat(true)
	ns.GameSounds = function() return true end
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "", "the game's sound, not HUDini's")
	w:runTickers()
	H.eq(Heard(w), "voiceBuff", "the repeat is HUDini's own")
end)

-- TICK-0249 (DK): 2 seconds of quiet after each play ends. A HUDini voice
-- file is at most 1.5 seconds (ffprobe, the quieter copies too), so the next
-- starts 3.5 seconds after the last one started. A game sound's length is
-- not known: 2 seconds, so 4.
H.test("the repeat leaves 2 seconds of quiet after each play", function()
	local w, ns = World()
	local periods = {}
	local NewTicker = w.env.C_Timer.NewTicker
	w.env.C_Timer.NewTicker = function(period, fn)
		periods[#periods + 1] = period
		return NewTicker(period, fn)
	end
	ns.SetKeepUpSound("voiceShield")
	ns.SetKeepUpRepeat(true)
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Heard(w), "voiceShield")
	H.eq(periods[#periods], 3.5, "a voice: 1.5 seconds at most, then 2 of quiet")
	w:runTickers()
	H.eq(Heard(w), "voiceShield", "the repeat")

	ns.SetKeepUpSound("raidWarning")
	ns.UpdateAlerts()
	H.eq(periods[#periods], 4, "a game sound: 2 seconds, then 2 of quiet")
	w:runTickers()
	H.eq(Heard(w), "raidWarning", "one ticker plays, at the new pace")
end)

H.test("test mode stops the repeat", function()
	local w, ns = World()
	ns.SetKeepUpSound("voiceBuff")
	ns.SetKeepUpRepeat(true)
	w.combat = true
	ns.UpdateAlerts()
	Heard(w)
	ns.ShowAlertSamples(true)
	w:runTickers()
	H.eq(Heard(w), "", "samples up")
end)
