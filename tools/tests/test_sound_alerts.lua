-- The five sound alerts for every class (TICK-0235, SoundAlerts.lua):
-- combat start and end, low health, low mana, an honorable kill. All off
-- at the start; low health and low mana play once per drop below the
-- line; a secret reading plays nothing and throws nothing. What the player
-- hears, and how often the game gives a plain reading, needs DK's play.

-- w.hp, w.hpMax, w.mp, w.mpMax: the player's values (a number, or a
-- w:Hidden() secret). w.dead: UnitIsDeadOrGhost. w.kills: today's
-- honorable kills (nil: no GetPVPSessionStats). w.heard: every sound file.
local function World(setup)
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	function w:Hidden()
		local function Throw() error("a secret value was used") end
		local t = setmetatable({}, { __lt = Throw, __le = Throw, __concat = Throw, __index = Throw,
			__div = Throw, __mul = Throw, __add = Throw, __sub = Throw })
		self.secret[t] = true
		return t
	end
	w.hp, w.hpMax, w.mp, w.mpMax, w.dead = 100, 100, 100, 100, false
	env.UnitHealth = function() return w.hp end
	env.UnitHealthMax = function() return w.hpMax end
	env.UnitPower = function(_, power) if power == 0 then return w.mp end return 50 end
	env.UnitPowerMax = function(_, power) if power == 0 then return w.mpMax end return 100 end
	env.UnitIsDeadOrGhost = function() return w.dead end
	w.heard = {}
	env.PlaySoundFile = function(path)
		w.heard[#w.heard + 1] = path
		return true
	end
	env.PlaySound = function(id)
		w.heard[#w.heard + 1] = id
		return true
	end
	if setup then setup(w) end
	w:loadAddon()
	return w, w.ns, w.env.HUDiniDB
end

local function Mod(ns) return ns.GetModule("soundAlerts") end

local function Voice(key) return { key = key, volume = 100 } end

local function Health(w, v)
	w.hp = v
	w:fire("UNIT_HEALTH", "player")
end

local function Mana(w, v, token)
	w.mp = v
	w:fire("UNIT_POWER_UPDATE", "player", token or "MANA")
end

H.test("All five start off with a 30% line, and the part listens to nothing", function()
	local w, ns, db = World()
	for _, k in ipairs({ "soundCombatStart", "soundCombatEnd", "soundLowHealth", "soundLowMana", "soundHonorKill" }) do
		H.eq(db[k], false, k)
	end
	H.eq(db.soundLowHealthAt, 30)
	H.eq(db.soundLowManaAt, 30)
	H.eq(Mod(ns).enabled, false, "off with all five off")
	w:fire("PLAYER_REGEN_DISABLED")
	w:fire("PLAYER_REGEN_ENABLED")
	Health(w, 100); Health(w, 10)
	w:fire("PLAYER_PVP_KILLS_CHANGED")
	H.eq(#w.heard, 0, "no sound")
end)

H.test("Each alert names a sound of the list to turn on with", function()
	local _, ns = World()
	local want = { soundCombatStart = "voiceCombat", soundCombatEnd = "voiceSafe",
		soundLowHealth = "voiceHealth", soundLowMana = "voiceMana", soundHonorKill = "voiceGotem" }
	H.eq(#ns.SOUND_ALERTS, 5)
	for _, a in ipairs(ns.SOUND_ALERTS) do
		H.eq(a.sound, want[a.setting], a.setting)
		H.ok(ns.IsSoundKey(a.sound), a.sound .. " is on the list")
	end
end)

H.test("Combat start and combat end each play their own sound once", function()
	local w, ns, db = World()
	H.eq(ns.SetSoundAlert("soundCombatStart", Voice("voiceCombat")), true)
	H.eq(Mod(ns).enabled, true, "on with one sound")
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(#w.heard, 1)
	H.ok(tostring(w.heard[1]):find("Combat"), "the Combat voice")
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(#w.heard, 1, "combat end is off")
	ns.SetSoundAlert("soundCombatEnd", Voice("voiceSafe"))
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(#w.heard, 2)
	H.ok(tostring(w.heard[2]):find("Safe"), "the Safe voice")
	H.eq(ns.SetSoundAlert("soundCombatStart", Voice("voiceCombat")), false, "the same sound saves nothing")
	ns.SetSoundAlert("soundCombatStart", false)
	ns.SetSoundAlert("soundCombatEnd", false)
	H.eq(Mod(ns).enabled, false, "off again with all five off")
	H.eq(db.soundCombatStart, false)
end)

H.test("Low health plays once per drop below the line", function()
	local w, ns = World()
	ns.SetSoundAlert("soundLowHealth", Voice("voiceHealth"))
	Health(w, 80)
	H.eq(#w.heard, 0)
	w.hp = 25
	w:fire("UNIT_HEALTH", "target")
	H.eq(#w.heard, 0, "another unit's event")
	Health(w, 25)
	H.eq(#w.heard, 1, "the drop below 30%")
	H.ok(tostring(w.heard[1]):find("Health"), "the Health voice")
	Health(w, 20)
	H.eq(#w.heard, 1, "still low: no second sound")
	Health(w, 30)
	Health(w, 29)
	H.eq(#w.heard, 2, "back to the line, then below it again")
end)

H.test("A player who is low at the first reading hears nothing", function()
	local w, ns = World(function(w) w.hp = 20 end)
	ns.SetSoundAlert("soundLowHealth", Voice("voiceHealth"))
	Health(w, 15)
	H.eq(#w.heard, 0, "turned on while low")
	w:fire("PLAYER_ENTERING_WORLD", false, false)
	Health(w, 10)
	H.eq(#w.heard, 0, "a loading screen while low")
	Health(w, 50)
	Health(w, 20)
	H.eq(#w.heard, 1, "a real drop")
end)

H.test("A dead player hears nothing, and the first reading after learns", function()
	local w, ns = World()
	ns.SetSoundAlert("soundLowHealth", Voice("voiceHealth"))
	Health(w, 80)
	w.dead = true
	Health(w, 0)
	H.eq(#w.heard, 0, "death")
	w.dead = false
	Health(w, 20)
	H.eq(#w.heard, 0, "back to life at 20%")
	Health(w, 60)
	Health(w, 25)
	H.eq(#w.heard, 1)
end)

H.test("A secret health plays nothing, throws nothing, and the next plain one only learns", function()
	-- Plain first: the drop plays.
	local w, ns = World()
	ns.SetSoundAlert("soundLowHealth", Voice("voiceHealth"))
	Health(w, 80)
	Health(w, 20)
	H.eq(#w.heard, 1, "plain drop")
	-- The same drop, secret: nothing.
	w, ns = World()
	ns.SetSoundAlert("soundLowHealth", Voice("voiceHealth"))
	Health(w, 80)
	w.secret[21] = true
	Health(w, 21)
	H.eq(#w.heard, 0, "secret number")
	Health(w, w:Hidden())
	H.eq(#w.heard, 0, "secret value")
	w.hp, w.hpMax = 20, w:Hidden()
	w:fire("UNIT_MAXHEALTH", "player")
	H.eq(#w.heard, 0, "secret max")
	w.hpMax = 100
	Health(w, 20)
	H.eq(#w.heard, 0, "the next plain reading only learns: no sound after a fight")
	Health(w, 60)
	Health(w, 25)
	H.eq(#w.heard, 1, "a plain drop after that plays")
	-- A secret dead flag counts as alive: no error.
	w, ns = World()
	ns.SetSoundAlert("soundLowHealth", Voice("voiceHealth"))
	Health(w, 80)
	w.dead = w:Hidden()
	Health(w, 20)
	H.eq(#w.heard, 1, "secret dead flag")
end)

H.test("A saved true, or a key that left the list, plays the alert's own sound", function()
	local w, ns, db = World()
	db.soundCombatStart = true
	ns.UpdateModules()
	H.eq(Mod(ns).enabled, true, "true is on")
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(#w.heard, 1)
	H.ok(tostring(w.heard[1]):find("Combat"), "the Combat voice")
	db.soundLowHealth = { key = "gone", volume = 100 }
	ns.UpdateModules()
	Health(w, 80)
	Health(w, 20)
	H.eq(#w.heard, 2, "a gone key plays")
	H.ok(tostring(w.heard[2]):find("Health"), "the Health voice")
end)

H.test("The fight's end plays no Safe as you die", function()
	local w, ns = World()
	ns.SetSoundAlert("soundCombatEnd", Voice("voiceSafe"))
	w.dead = true
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(#w.heard, 0, "dead")
	w.dead = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(#w.heard, 1, "alive")
end)

H.test("The line snaps to a step of 5 between 10 and 90; a new line plays nothing", function()
	local w, ns, db = World()
	H.eq(ns.SoundAlertLine(7), 10)
	H.eq(ns.SoundAlertLine(93), 90)
	H.eq(ns.SoundAlertLine(33), 35)
	H.eq(ns.SoundAlertLine(32), 30)
	H.eq(ns.SoundAlertLine("x"), 30)
	H.eq(ns.SoundAlertLine(nil), 30)
	ns.SetSoundAlert("soundLowHealth", Voice("voiceHealth"))
	Health(w, 40)
	H.eq(ns.SetSoundAlertLine("soundLowHealthAt", 52), true)
	H.eq(db.soundLowHealthAt, 50)
	H.eq(#w.heard, 0, "40% is below the new line, but a new line only learns")
	Health(w, 60)
	Health(w, 45)
	H.eq(#w.heard, 1, "a drop below 50%")
	H.eq(ns.SetSoundAlertLine("soundLowHealthAt", 50), false, "the same line saves nothing")
	H.eq(ns.SetSoundAlertLine("soundCombatStart", 50), false, "not a line")
end)

H.test("Low mana plays once per drop, reads only mana, and stays quiet with no mana", function()
	local w, ns = World()
	ns.SetSoundAlert("soundLowMana", Voice("voiceMana"))
	Mana(w, 80)
	Mana(w, 20, "RAGE")
	H.eq(#w.heard, 0, "another power's event")
	w:fire("UNIT_POWER_UPDATE", "player", "MANA")
	H.eq(#w.heard, 1, "the drop below 30%")
	H.ok(tostring(w.heard[1]):find("Mana"), "the Mana voice")
	Mana(w, 10)
	H.eq(#w.heard, 1)
	-- A class with no mana: the game gives a max of 0.
	w, ns = World(function(w) w.mpMax = 0 end)
	ns.SetSoundAlert("soundLowMana", Voice("voiceMana"))
	Mana(w, 0); Mana(w, 50); Mana(w, 0)
	H.eq(#w.heard, 0, "no mana")
	-- Secret mana: nothing, and no error.
	w, ns = World()
	ns.SetSoundAlert("soundLowMana", Voice("voiceMana"))
	Mana(w, 80)
	Mana(w, w:Hidden())
	H.eq(#w.heard, 0, "secret mana")
end)

H.test("An honorable kill plays once for each kill the count shows", function()
	local w, ns = World(function(w)
		w.kills = 3
		w.env.GetPVPSessionStats = function() return w.kills, 0 end
	end)
	ns.SetSoundAlert("soundHonorKill", Voice("voiceGotem"))
	w.kills = 4
	w:fire("PLAYER_PVP_KILLS_CHANGED", "target")
	H.eq(#w.heard, 1)
	H.ok(tostring(w.heard[1]):find("Gotem"), "the Gotem voice")
	w:fire("PLAYER_PVP_KILLS_CHANGED", "target")
	H.eq(#w.heard, 1, "the count did not go up")
	-- A secret count, or no count at all: the event alone plays.
	w.secret[4] = true
	w:fire("PLAYER_PVP_KILLS_CHANGED", "target")
	H.eq(#w.heard, 2, "secret count, as the last plain one")
	w.kills = w:Hidden()
	w:fire("PLAYER_PVP_KILLS_CHANGED", "target")
	H.eq(#w.heard, 3, "secret count that throws")
	w.secret[4], w.kills = nil, 4
	w:fire("PLAYER_PVP_KILLS_CHANGED", "target")
	H.eq(#w.heard, 3, "a secret count keeps the last plain one")
	w.kills = 1
	w:fire("PLAYER_PVP_KILLS_CHANGED", "target")
	H.eq(#w.heard, 4, "a new day: the count dropped")
	w.kills = 2
	w:fire("PLAYER_PVP_KILLS_CHANGED", "target")
	H.eq(#w.heard, 5, "the next kill of the new day")
	w, ns = World()
	ns.SetSoundAlert("soundHonorKill", Voice("voiceGotem"))
	w:fire("PLAYER_PVP_KILLS_CHANGED", "target")
	H.eq(#w.heard, 1, "no GetPVPSessionStats")
end)

-- TICK-0239: low health and low mana listen to your own unit only.
H.test("Low health and low mana register their events for the player only", function()
	local _, ns = World()
	ns.SetSoundAlert("soundLowHealth", Voice("voiceHealth"))
	local h = Mod(ns).frame.__h
	for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" }) do
		H.eq(h.events[e], true, e .. " registered")
		H.ok(h.units[e] and h.units[e].player and next(h.units[e], "player") == nil, e .. " for the player only")
	end
	H.eq(h.units.PLAYER_REGEN_DISABLED, nil, "not a unit event")
end)
