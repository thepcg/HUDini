-- Each buff off shows its own icon (TICK-0252). Two buffs off: two red
-- icons left of your health bar, side by side. Cast one: its icon goes, the
-- other stays. A group of buffs where one counts for the others (the Mage
-- armors) is one icon. A weapon buff a bare weapon needs comes after them,
-- and makes no sound. Each spell's HUD icon glows.

local AI, FROST, ICE, MAGE_ARMOR, RB, SLOW_FALL = 1459, 168, 7302, 6117, 8017, 130
local NAMES = {
	[AI] = "Arcane Intellect", [FROST] = "Frost Armor", [ICE] = "Ice Armor",
	[MAGE_ARMOR] = "Mage Armor", [RB] = "Rockbiter Weapon", [SLOW_FALL] = "Slow Fall",
}
local MISSING_SOUND = 8959

local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

-- A Mage who knows the spells in `known`, has learned the buffs in `learned`
-- (name -> length) and wears the buffs in w.on (id -> length). No grid
-- icons: every buff is off the grid.
local function Mage(learned, known)
	local w = H.world()
	Classes.Use(w)
	w.class, w.className = "MAGE", "Mage"
	local env = w.env
	w.known = known or { [AI] = true, [FROST] = true, [ICE] = true }
	w.on = {}
	w.unread = {} -- ids whose name will not read (a secret name)
	env.C_Spell.GetSpellName = function(id)
		if w.unread[id] then return nil end
		return NAMES[id]
	end
	env.C_Spell.GetSpellInfo = function(name)
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id, name = n } end
		end
	end
	env.C_Spell.GetSpellTexture = function(id) return "tex" .. id end
	env.IsPlayerSpell = function(id) return w.known[id] == true end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		for id, n in pairs(NAMES) do
			local d = w.on[id]
			if n == name and d then
				return { auraInstanceID = id, name = n, spellId = id, duration = d,
					expirationTime = 5000 }
			end
		end
	end
	env.C_UnitAuras.GetAuraDataByIndex = function() return nil end
	w.sounds = {}
	env.PlaySound = function(kit) table.insert(w.sounds, kit) return true end
	local ns = w:loadAddon()
	local db = env.HUDiniDB
	db.warnOwnBuff, db.showHealth = true, true
	ns.HUDini.spells = {}
	ns.ClassDB().buffSpells = learned or { ["Arcane Intellect"] = 3600, ["Frost Armor"] = 1800 }
	return ns, w
end

-- The own-buff icons that show, from the bar out, by the spell each glows.
local function Shown(ns)
	local list = {}
	for i = 1, 8 do
		local key = i == 1 and "ownBuff" or "ownBuff" .. i
		local icon = ns.leftIcons[key]
		if icon and icon:IsShown() then list[#list + 1] = ns.HUDini.alertGlow[key] end
	end
	return table.concat(list, ",")
end

H.test("two buffs off out of a fight: two icons; cast one: its icon goes, the other stays", function()
	local ns, w = Mage()
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), AI .. "," .. FROST, "Arcane Intellect, then Frost Armor")
	H.eq(ns.missingBuffID, AI, "the first stays the one icon older code reads")
	w.on[AI] = 3600
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), tostring(FROST), "Arcane Intellect cast: only Frost Armor")
	H.eq(ns.HUDini.alertGlow.ownBuff2, nil, "the second icon's glow goes")
	w.on[FROST] = 1800
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), "", "both cast: no icon")
	H.eq(ns.HUDini.alertGlow.ownBuff, nil, "and no glow")
	H.eq(ns.buffMissing, false)
end)

H.test("the Mage armors are one group: one icon for them", function()
	local ns = Mage({ ["Frost Armor"] = 1800, ["Ice Armor"] = 1800, ["Arcane Intellect"] = 3600 })
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), AI .. "," .. FROST, "one armor icon, not two")
	H.eq(#ns.missingBuffIDs, 2)
end)

H.test("a bare weapon and a buff off: two icons, the weapon buff last", function()
	local ns, w = Mage()
	ns.WeaponBuffIcon = function() return RB end
	w.on[FROST] = 1800
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), AI .. "," .. RB, "Arcane Intellect, then the weapon buff")
	H.eq(ns.buffMissing, true, "a learned buff is off")
	w.on[AI] = 3600
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), tostring(RB), "only the weapon buff")
	H.eq(ns.buffMissing, false, "the weapon buff does not count as your buff off")
	H.eq(ns.missingBuffID, RB, "the one icon older code reads")
end)

H.test("in a fight: one sound for two buffs off, none for a weapon buff alone", function()
	local ns, w = Mage()
	H.eq(ns.SetKeepUpSound(true), true, "the sound setting on")
	ns.UpdateBuffMissing()
	H.eq(#w.sounds, 0, "out of a fight: no sound")
	w.combat = true
	ns.UpdateBuffMissing()
	H.eq(#w.sounds, 1, "the fight starts: one sound")
	H.eq(w.sounds[1], MISSING_SOUND)
	H.eq(Shown(ns), AI .. "," .. FROST, "both icons in the fight")
	ns.UpdateBuffMissing()
	H.eq(#w.sounds, 1, "a second look: no second sound")

	local ns2, w2 = Mage()
	ns2.SetKeepUpSound(true)
	ns2.WeaponBuffIcon = function() return RB end
	w2.on[AI], w2.on[FROST] = 3600, 1800
	ns2.UpdateBuffMissing()
	w2.combat = true
	ns2.UpdateBuffMissing()
	H.eq(Shown(ns2), tostring(RB), "the weapon buff icon")
	H.eq(#w2.sounds, 0, "a weapon buff alone: no sound (TICK-0198)")
end)

H.test("the alert off: no icon and no glow", function()
	local ns, w = Mage()
	ns.UpdateBuffMissing()
	w.env.HUDiniDB.warnOwnBuff = false
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), "", "no icon")
	H.eq(ns.HUDini.alertGlow.ownBuff, nil, "no glow on the first")
	H.eq(ns.HUDini.alertGlow.ownBuff2, nil, "no glow on the second")
end)

H.test("the keep-up icon steps aside for its spell on the second own icon too", function()
	local ns, w = Mage()
	local value = ns.ClassValue
	ns.ClassValue = function(key, ...)
		if key == "keepUp" then return { "Frost Armor" } end
		return value(key, ...)
	end
	ns.UpdateBuffMissing()
	ns.UpdateAlerts()
	w.combat = true
	ns.UpdateBuffMissing()
	ns.UpdateAlerts()
	H.eq(Shown(ns), AI .. "," .. FROST, "Frost Armor is the second own icon")
	local keepUp = ns.leftIcons.keepUp
	H.eq(keepUp ~= nil and keepUp:IsShown(), false, "no keep-up icon for the same spell")
	-- The control: Frost Armor not learned, so no own icon for it.
	local ns2, w2 = Mage({ ["Arcane Intellect"] = 3600 })
	ns2.ClassValue = function(key, ...)
		if key == "keepUp" then return { "Frost Armor" } end
		return value(key, ...)
	end
	ns2.UpdateBuffMissing()
	ns2.UpdateAlerts()
	w2.combat = true
	ns2.UpdateBuffMissing()
	ns2.UpdateAlerts()
	H.eq(ns2.leftIcons.keepUp:IsShown(), true, "no own icon for it: the keep-up icon shows")
end)

H.test("the game's sound stands in only when it plays one for each learned buff off", function()
	-- The game plays a sound for Arcane Intellect only.
	local function Fight(learned, weapon, unread)
		local ns, w = Mage(learned)
		ns.SetKeepUpSound(true)
		if weapon then ns.WeaponBuffIcon = function() return RB end end
		ns.UpdateBuffMissing()
		ns.GameSounds = function(name) return name == "Arcane Intellect" end
		if unread then w.unread[FROST] = true end
		w.combat = true
		ns.UpdateBuffMissing()
		return #w.sounds
	end
	H.eq(Fight({ ["Arcane Intellect"] = 3600 }), 0, "the game plays it: none from HUDini")
	H.eq(Fight(), 1, "Frost Armor has no game sound: HUDini plays")
	H.eq(Fight(nil, false, true), 1, "Frost Armor's name will not read: HUDini plays")
	H.eq(Fight({ ["Arcane Intellect"] = 3600 }, true), 0, "a weapon buff's icon does not count")
end)

H.test("a buff whose group holds all of an earlier one's is dropped, not the other way", function()
	-- Slow Fall on counts for Arcane Intellect (a map you made); Slow Fall
	-- counts only for itself. Arcane Intellect cast leaves Slow Fall off.
	local ns, w = Mage({ ["Arcane Intellect"] = 3600, ["Slow Fall"] = 3600 },
		{ [AI] = true, [SLOW_FALL] = true })
	w.env.HUDiniDB.auraMap = { ["Arcane Intellect"] = { "Slow Fall" } }
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), AI .. "," .. SLOW_FALL, "two icons")
	w.on[AI] = 3600
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), tostring(SLOW_FALL), "Arcane Intellect cast: Slow Fall still off")
end)

--------------------------------------------------------------------------------
-- TICK-0255: the list stops at the icons there are (8), and an entry with no
-- names covers nothing.
--------------------------------------------------------------------------------

-- Nine more buffs, "Buff 1" to "Buff 9", each learned (1 hour) and known.
local function NineBuffs()
	local learned, known = {}, {}
	for i = 1, 9 do
		local id, name = 9000 + i, "Buff " .. i
		NAMES[id] = name
		learned[name] = 3600
		known[id] = true
	end
	return learned, known
end

H.test("nine buffs off and a bare weapon: eight icons, the weapon buff last, and its sound", function()
	local learned, known = NineBuffs()
	local ns, w = Mage(learned, known)
	ns.WeaponBuffIcon = function() return RB end
	local played = {}
	ns.PlaySoundChoice = function(_, default) played[#played + 1] = default end
	ns.SetClassAlertSound(ns.WEAPON_BUFF_SOUND.setting, true)
	ns.UpdateBuffMissing()
	H.eq(#ns.missingBuffIDs, 9, "Auras.lua still lists all nine")
	H.eq(Shown(ns), "9001,9002,9003,9004,9005,9006,9007," .. RB, "seven of yours, then the weapon buff")
	H.eq(table.concat(played, ","), ns.WEAPON_BUFF_SOUND.sound, "the weapon buff's sound, with its icon")
end)

H.test("the keep-up icon steps aside only for a buff with an icon", function()
	local learned, known = NineBuffs()
	local ns, w = Mage(learned, known)
	local value = ns.ClassValue
	ns.ClassValue = function(key, ...)
		if key == "keepUp" then return { "Buff 9" } end
		return value(key, ...)
	end
	ns.UpdateBuffMissing()
	ns.UpdateAlerts()
	w.combat = true
	ns.UpdateBuffMissing()
	ns.UpdateAlerts()
	H.eq(Shown(ns), "9001,9002,9003,9004,9005,9006,9007,9008", "eight icons, no ninth")
	H.eq(ns.leftIcons.keepUp:IsShown(), true, "Buff 9 has no own icon: the keep-up icon shows it")
end)

H.test("the weapon buff is your ninth buff off too: it still gets the last icon", function()
	local learned, known = NineBuffs()
	local ns = Mage(learned, known)
	ns.WeaponBuffIcon = function() return 9009 end
	local played = {}
	ns.PlaySoundChoice = function(_, default) played[#played + 1] = default end
	ns.SetClassAlertSound(ns.WEAPON_BUFF_SOUND.setting, true)
	ns.UpdateBuffMissing()
	H.eq(Shown(ns), "9001,9002,9003,9004,9005,9006,9007,9009", "Buff 8 makes way for it")
	H.eq(table.concat(played, ","), ns.WEAPON_BUFF_SOUND.sound, "its sound, with its icon")
end)

H.test("the weapon buff's icon past seven of yours is not one of yours for the sound", function()
	-- The game plays a sound for each of your buffs, not for the weapon buff.
	local learned, known = NineBuffs()
	local ns, w = Mage(learned, known)
	ns.SetKeepUpSound(true)
	ns.WeaponBuffIcon = function() return RB end
	ns.UpdateBuffMissing()
	ns.GameSounds = function(name) return name ~= "Rockbiter Weapon" end
	w.combat = true
	ns.UpdateBuffMissing()
	H.eq(#w.sounds, 0, "the game plays for your seven: none from HUDini")
end)

H.test("an entry with no names does not hide the buffs after it", function()
	local ns = Mage()
	-- A grid icon whose aura names came out empty.
	ns.HUDini.spells = { { spellID = AI, slot = 1, auraNames = {} } }
	ns.UpdateBuffMissing()
	H.eq(#ns.missingBuffIDs, 2, "Arcane Intellect and Frost Armor")
	H.eq(ns.missingBuffIDs[2], FROST, "Frost Armor still listed")
end)
