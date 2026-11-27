-- The weapon buff alert (TICK-0250). The weapon buff icon (TICK-0198) gets
-- a setting per class, on at the start, and a sound per class, off at the
-- start and voiceBuff when turned on. The sound plays once each time the
-- icon starts to show, out of a fight only. What the player sees and hears
-- needs DK's play.

local IDS = { ["Rockbiter Weapon"] = 8017, ["Arcane Intellect"] = 1459 }

-- A Shaman who knows Rockbiter Weapon, a sword in the main hand, the
-- health bar and the own-buff icon on. w.lines: the sword's tooltip.
-- w.enchant: what GetWeaponEnchantInfo says for the main hand. w.auras:
-- your buffs by name.
local function World()
	local w = H.world()
	local env = w.env
	w.class, w.className = "SHAMAN", "Shaman"
	w.auras, w.lines, w.enchant = {}, { "Sword" }, false
	env.C_Spell.GetSpellInfo = function(name)
		if IDS[name] then return { spellID = IDS[name], name = name } end
	end
	env.C_Spell.GetSpellName = function(id)
		for name, n in pairs(IDS) do
			if n == id then return name end
		end
	end
	env.C_Spell.GetSpellTexture = function(id) return id end
	env.IsPlayerSpell = function(id) return id == 8017 or id == 1459 end
	env.GetWeaponEnchantInfo = function() return w.enchant end
	env.C_TooltipInfo = { GetInventoryItem = function()
		if w.lines == nil then return nil end
		local rows = {}
		for i, text in ipairs(w.lines) do rows[i] = { leftText = text } end
		return { lines = rows }
	end }
	local ns = w:loadAddon()
	ns.HUDini.spells = {}
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name) return w.auras[name] end
	-- The fight's end reads your buffs again (ns.UpdateIconAuras) only
	-- with this.
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	ns.RegisterClass("SHAMAN", { weaponBuff = { "Rockbiter Weapon" } })
	w:holdItem(16, 2000, 2, 7, "Sword")
	local db = env.HUDiniDB
	db.warnOwnBuff, db.showHealth = true, true
	-- Each sound that plays, by its key.
	w.played = {}
	ns.PlaySoundChoice = function(saved, default)
		local c = ns.SoundChoice(saved, default)
		w.played[#w.played + 1] = c and c.key or "?"
		return c and c.key
	end
	return w, ns
end

-- The sounds played since the last call, joined.
local function Heard(w)
	local out = table.concat(w.played, ",")
	w.played = {}
	return out
end

local SOUND = "soundWeaponBuff"

--------------------------------------------------------------------------------
-- Defaults and the saved values
--------------------------------------------------------------------------------

H.test("the weapon buff alert starts on, its sound off; the sound turns on as voiceBuff", function()
	local _, ns = World()
	H.eq(ns.WEAPON_BUFF_SOUND.setting, SOUND)
	H.eq(ns.WEAPON_BUFF_SOUND.sound, "voiceBuff")
	H.eq(ns.HasWeaponBuffAlert(), true, "a Shaman has the alert")
	H.eq(ns.GetWeaponBuffAlert(), true, "on at the start")
	H.eq(ns.GetClassAlertSound(SOUND), false, "the sound: off at the start")
	H.eq(ns.SetClassAlertSound(SOUND, true), true, "turned on")
	H.eq(ns.SoundChoice(ns.GetClassAlertSound(SOUND), ns.WEAPON_BUFF_SOUND.sound).key, "voiceBuff",
		"on: voiceBuff")
	H.eq(ns.SetClassAlertSound(SOUND, "voiceKick"), true, "another sound")
	H.eq(ns.GetClassAlertSound(SOUND).key, "voiceKick")
	H.eq(ns.SetClassAlertSound(SOUND, false), true, "off again")
	H.eq(ns.ClassDB()[SOUND], nil, "off saves nothing")
end)

H.test("the alert's setting: off saves false, on saves nothing, per class", function()
	local w, ns = World()
	H.eq(ns.SetWeaponBuffAlert(true), false, "already on")
	H.eq(ns.SetWeaponBuffAlert(false), true, "off")
	H.eq(ns.GetWeaponBuffAlert(), false)
	H.eq(w.env.HUDiniDB.classes.SHAMAN.weaponBuffAlert, false, "saved for the Shaman")
	H.eq(ns.SetWeaponBuffAlert(false), false, "already off")
	H.eq(ns.SetWeaponBuffAlert(true), true, "on")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.weaponBuffAlert, nil, "on saves nothing")
end)

H.test("a class with no weapon buff in its file has no alert", function()
	local _, ns = World()
	ns.RegisterClass("SHAMAN", {})
	H.eq(ns.HasWeaponBuffAlert(), false)
end)

H.test("the weapon buff sound is beside the class alert list, not in it", function()
	local _, ns = World()
	for _, a in ipairs(ns.CLASS_ALERT_SOUNDS) do
		H.ok(a.setting ~= SOUND, "not in the list: the Alerts page loop makes no row for it")
	end
end)

--------------------------------------------------------------------------------
-- The alert off
--------------------------------------------------------------------------------

H.test("the alert off: no icon, no sound, no HUD for a bare weapon; a learned buff still shows", function()
	local w, ns = World()
	ns.SetClassAlertSound(SOUND, true)
	ns.SetWeaponBuffAlert(false)
	ns.RefreshWeaponBuffAlert()
	H.eq(ns.missingBuffID, nil, "no icon")
	H.eq(ns.WeaponBuffMissing(), false, "no HUD for it")
	H.eq(Heard(w), "", "no sound")
	ns.ClassDB().buffSpells = { ["Arcane Intellect"] = true }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 1459, "a learned buff off still shows")
	ns.ClassDB().buffSpells = nil
	ns.SetWeaponBuffAlert(true)
	ns.RefreshWeaponBuffAlert()
	H.eq(ns.missingBuffID, 8017, "on again: the icon at once")
	H.eq(Heard(w), "voiceBuff", "and its sound")
end)

--------------------------------------------------------------------------------
-- One sound for each showing
--------------------------------------------------------------------------------

H.test("the sound off: the icon shows, no sound", function()
	local w, ns = World()
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 8017, "the icon")
	H.eq(Heard(w), "", "no sound")
end)

H.test("one sound each time the icon shows, out of a fight only", function()
	local w, ns = World()
	ns.SetClassAlertSound(SOUND, true)
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 8017, "a bare weapon: the icon")
	H.eq(Heard(w), "voiceBuff", "the sound once")
	ns.UpdateBuffMissing()
	ns.UpdateBuffMissing()
	H.eq(Heard(w), "", "still bare: no sound again")

	-- Rockbiter cast: the icon goes. It runs out: the sound again.
	w.lines = { "Sword", "Rockbiter 3 (53 min)" }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "buffed: no icon")
	w.lines = { "Sword" }
	ns.UpdateBuffMissing()
	H.eq(Heard(w), "voiceBuff", "ran out: the sound again")

	-- A fight: no icon, no sound. The fight ends bare: the sound again.
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(ns.missingBuffID, nil, "in a fight: no icon")
	ns.UpdateBuffMissing()
	H.eq(Heard(w), "", "in a fight: no sound")
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(ns.missingBuffID, 8017, "the fight ended: the icon")
	H.eq(Heard(w), "voiceBuff", "the fight ended bare: the sound")

	-- No weapon, then a bare weapon put on: the sound again.
	w:holdItem(16, nil)
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	H.eq(ns.missingBuffID, nil, "no weapon: no icon")
	w:holdItem(16, 2000, 2, 7, "Sword")
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	H.eq(ns.missingBuffID, 8017, "a bare weapon put on: the icon")
	H.eq(Heard(w), "voiceBuff", "and the sound")
end)

H.test("a pass where the game would not say counts no new showing", function()
	local w, ns = World()
	ns.SetClassAlertSound(SOUND, true)
	ns.UpdateBuffMissing()
	H.eq(Heard(w), "voiceBuff", "the first showing")
	w.lines = nil
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "no tooltip: no icon")
	w.lines = { "Sword" }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 8017, "the tooltip back: the icon")
	H.eq(Heard(w), "", "the same showing: no second sound")
end)

H.test("a learned buff off beside a bare weapon: both icons, the weapon sound at once (TICK-0252)", function()
	local w, ns = World()
	ns.SetClassAlertSound(SOUND, true)
	ns.ClassDB().buffSpells = { ["Arcane Intellect"] = true }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 1459, "Arcane Intellect first")
	H.eq(ns.missingWeaponID, 8017, "the weapon buff has its own icon beside it")
	H.eq(Heard(w), "voiceBuff", "its icon shows: its sound")
	w.auras["Arcane Intellect"] = { auraInstanceID = 7, duration = 1800 }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 8017, "Arcane Intellect cast: the weapon buff's icon stays")
	H.eq(Heard(w), "", "the same showing: no second sound")
end)

H.test("the own-buff icon off: no sound for a bare weapon", function()
	local w, ns = World()
	ns.SetClassAlertSound(SOUND, true)
	w.env.HUDiniDB.warnOwnBuff = false
	ns.UpdateBuffMissing()
	H.eq(Heard(w), "", "no icon shows: no sound")
	w.env.HUDiniDB.warnOwnBuff = true
	ns.UpdateBuffMissing()
	H.eq(Heard(w), "voiceBuff", "the icon shows: the sound")
end)

H.test("a pass where the weapon look fails counts no new showing", function()
	local w, ns = World()
	ns.SetClassAlertSound(SOUND, true)
	ns.UpdateBuffMissing()
	H.eq(Heard(w), "voiceBuff", "the first showing")
	local real = ns.WeaponBuffIcon
	ns.WeaponBuffIcon = function() error("boom") end
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "the look failed: no icon")
	ns.WeaponBuffIcon = real
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 8017, "the look works again: the icon")
	H.eq(Heard(w), "", "the same showing: no second sound")
end)

H.test("test mode: no weapon buff sound while the samples are up", function()
	local w, ns = World()
	ns.SetClassAlertSound(SOUND, true)
	w.lines = { "Sword", "Rockbiter 3 (53 min)" }
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "buffed: no icon")
	ns.ShowAlertSamples(true)
	w.lines = { "Sword" }
	ns.UpdateBuffMissing()
	H.eq(Heard(w), "", "the samples are up: no sound")
	ns.ShowAlertSamples(false)
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 8017, "test mode ended, still bare: the icon")
	H.eq(Heard(w), "voiceBuff", "and its sound")
end)

H.test("the alert off with a learned buff off: only the learned buff's icon (TICK-0252)", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Arcane Intellect"] = true }
	ns.SetWeaponBuffAlert(false)
	ns.UpdateBuffMissing()
	H.eq(ns.missingWeaponID, nil, "no weapon buff icon")
	H.eq(#ns.missingBuffIDs, 1, "Arcane Intellect only")
	local second = ns.leftIcons.ownBuff2
	H.eq(second == nil or not second:IsShown(), true, "no second icon shows")
	ns.SetWeaponBuffAlert(true)
	ns.RefreshWeaponBuffAlert()
	H.eq(ns.missingWeaponID, 8017, "on again: the weapon buff icon")
	H.eq(ns.leftIcons.ownBuff2:IsShown(), true, "beside Arcane Intellect")
end)
