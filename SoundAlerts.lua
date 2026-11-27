--[[--------------------------------------------------------------------------
	HUDini - Sound alerts for every class (TICK-0235, D-051 addition 2)

	Five sounds, saved for every character, all off at the start:

		soundCombatStart  you enter combat (PLAYER_REGEN_DISABLED)
		soundCombatEnd    you leave combat (PLAYER_REGEN_ENABLED)
		soundLowHealth    your health drops below soundLowHealthAt %
		soundLowMana      your mana drops below soundLowManaAt %
		soundHonorKill    an honorable kill (PLAYER_PVP_KILLS_CHANGED)

	Each one is a sound choice (Sounds.lua): false is off, a choice plays,
	and true (or a key that left the list) plays the alert's own sound.
	ns.SOUND_ALERTS lists them with the sound a picker offers when the
	player turns one on, for the Alerts page (designer's TICK-0233).

	Low health and low mana play once when the value drops below the line,
	and again only after it rose to the line or above. The first reading
	after login, a death or a new line only learns where the value is: a
	player who logs in low hears nothing. A dead player hears nothing.

	Secret values: on WoW Forever your own health and power can be secret,
	and a secret cannot be compared. HUDini compares only a plain number
	(ns.Plain). A secret reading plays nothing, throws nothing, and makes
	HUDini forget the last value: the next plain reading only learns. So a
	drop in a fight, where every reading is secret, does not play after
	the fight, with the danger gone. Where the game keeps the value secret
	(in combat, or always), that sound plays only out of a fight, or never.
	Only DK's play shows how often a reading is plain.

	Combat end: the fight ends as you die too; a dead player hears no end.

	The honorable kill: the game sends PLAYER_PVP_KILLS_CHANGED for an
	honorable kill only (warcraft.wiki.gg, Event:PLAYER_PVP_KILLS_CHANGED).
	As a guard, when GetPVPSessionStats gives a plain count, the sound
	plays only when that count changed: a drop (a new day) plays and
	starts the count again.

	The module is on only while one of the five has a sound, so with all
	five off it listens to no event (D-002).
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local G = _G
local Plain = ns.Plain

local LINE_DEFAULT, LINE_MIN, LINE_MAX, LINE_STEP = 30, 10, 90, 5

-- setting, the sound a picker turns on, and the line's setting (%).
ns.SOUND_ALERTS = {
	{ setting = "soundCombatStart", sound = "voiceCombat" },
	{ setting = "soundCombatEnd",   sound = "voiceSafe" },
	{ setting = "soundLowHealth",   sound = "voiceHealth", line = "soundLowHealthAt" },
	{ setting = "soundLowMana",     sound = "voiceMana",   line = "soundLowManaAt" },
	{ setting = "soundHonorKill",   sound = "voiceGotem" },
}
ns.SOUND_ALERT_LINE = { default = LINE_DEFAULT, min = LINE_MIN, max = LINE_MAX, step = LINE_STEP }

local byKey = {}
for _, a in ipairs(ns.SOUND_ALERTS) do byKey[a.setting] = a end

local function AnyOn()
	local db = HUDiniDB
	if not db then return false end
	for _, a in ipairs(ns.SOUND_ALERTS) do
		if ns.SoundChoice(db[a.setting], a.sound) then return true end
	end
	return false
end

local M = ns.NewModule("soundAlerts", {
	label    = "Sound alerts", -- locale: skip a debug name (/hud debug modules)
	isOn     = AnyOn,
	defaults = {
		soundCombatStart = false,
		soundCombatEnd   = false,
		soundLowHealth   = false,
		soundLowHealthAt = LINE_DEFAULT,
		soundLowMana     = false,
		soundLowManaAt   = LINE_DEFAULT,
		soundHonorKill   = false,
	},
})

-- A saved line as a whole step between the ends; the default for a bad value.
function ns.SoundAlertLine(v)
	v = tonumber(Plain(v))
	if not v or v ~= v then return LINE_DEFAULT end
	v = math.floor(v / LINE_STEP + 0.5) * LINE_STEP
	if v < LINE_MIN then return LINE_MIN end
	if v > LINE_MAX then return LINE_MAX end
	return v
end

-- A saved true, or a key that left the list, means the alert's own sound
-- (the picker's default mark), here and in AnyOn and Check alike.
local function Play(setting)
	local db = HUDiniDB
	if not db then return nil end
	return ns.PlaySoundChoice(db[setting], byKey[setting].sound)
end

--------------------------------------------------------------------------------
-- Low health and low mana
--------------------------------------------------------------------------------

-- low[setting]: true below the line, false at or above it, nil not known.
local low = {}

-- A plain percent (0-100), or nil when the game gives no plain number.
local function Percent(value, max)
	value, max = Plain(value), Plain(max)
	if type(value) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
	return value / max * 100
end

local function HealthPercent()
	local ok, value = pcall(G.UnitHealth, "player")
	local ok2, max = pcall(G.UnitHealthMax, "player")
	if not (ok and ok2) then return nil end
	return Percent(value, max)
end

local MANA = 0 -- Enum.PowerType.Mana; the harness has no Enum.PowerType.Mana

local function ManaPercent()
	local ok, value = pcall(G.UnitPower, "player", MANA)
	local ok2, max = pcall(G.UnitPowerMax, "player", MANA)
	if not (ok and ok2) then return nil end
	return Percent(value, max)
end

local reader = { soundLowHealth = HealthPercent, soundLowMana = ManaPercent }

-- Read one value and play its sound on a drop below the line.
local function Check(setting)
	local db = HUDiniDB
	if not (db and ns.SoundChoice(db[setting], byKey[setting].sound)) then
		low[setting] = nil
		return
	end
	local dead = G.UnitIsDeadOrGhost and Plain(G.UnitIsDeadOrGhost("player"))
	if dead then
		low[setting] = nil
		return
	end
	local pct = reader[setting]()
	-- Secret or no value: forget the last one, so the next plain reading
	-- only learns. Else a drop in a fight (all secret) would play after it,
	-- with the danger gone. So with health secret in a fight, the alert
	-- plays only out of one.
	if not pct then
		low[setting] = nil
		return
	end
	local now = pct < ns.SoundAlertLine(db[byKey[setting].line])
	local was = low[setting]
	low[setting] = now
	if now and was == false then Play(setting) end
end

-- Your own unit only (TICK-0239): the frame is not woken for every unit
-- nearby.
M:On({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }, function(_, unit)
	if unit == "player" then Check("soundLowHealth") end
end, "player")

M:On({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" }, function(_, unit, power)
	if unit == "player" and (power == nil or power == "MANA") then Check("soundLowMana") end
end, "player")

--------------------------------------------------------------------------------
-- Combat and the honorable kill
--------------------------------------------------------------------------------

M:On("PLAYER_REGEN_DISABLED", function() Play("soundCombatStart") end)
-- The fight ends as you die too: no "Safe" then.
M:On("PLAYER_REGEN_ENABLED", function()
	local dead = G.UnitIsDeadOrGhost and Plain(G.UnitIsDeadOrGhost("player"))
	if not dead then Play("soundCombatEnd") end
end)

-- Today's honorable kills as a plain number, or nil.
local function Kills()
	if type(G.GetPVPSessionStats) ~= "function" then return nil end
	local ok, kills = pcall(G.GetPVPSessionStats)
	kills = ok and Plain(kills) or nil
	return type(kills) == "number" and kills or nil
end

local kills

M:On("PLAYER_PVP_KILLS_CHANGED", function()
	local now = Kills()
	-- A count that drops (a new day) is a new start: learn it and play.
	local went = not (now and kills) or now ~= kills
	if now then kills = now end
	if went then Play("soundHonorKill") end
end)

M:On("PLAYER_ENTERING_WORLD", function()
	kills = Kills()
	wipe(low)
	Check("soundLowHealth")
	Check("soundLowMana")
end)

function M:OnEnable()
	kills = Kills()
	wipe(low)
end

--------------------------------------------------------------------------------
-- Setting them (the Alerts page)
--------------------------------------------------------------------------------

-- Save one of the five sounds (any saved value, as ns.SoundChoice) and
-- switch the module to match. True when the saved value changed.
function ns.SetSoundAlert(setting, value)
	local db = HUDiniDB
	if not (db and byKey[setting]) then return false end
	if ns.SameSound(db[setting], value) then return false end
	db[setting] = value
	ns.UpdateModules()
	if M.enabled and reader[setting] then Check(setting) end
	return true
end

-- Save a line (soundLowHealthAt or soundLowManaAt) as a whole step. The
-- next reading learns where the value is, so a new line plays nothing.
function ns.SetSoundAlertLine(lineSetting, v)
	local db = HUDiniDB
	if not db then return false end
	for _, a in ipairs(ns.SOUND_ALERTS) do
		if a.line == lineSetting then
			v = ns.SoundAlertLine(v)
			if db[lineSetting] == v then return false end
			db[lineSetting] = v
			low[a.setting] = nil
			if M.enabled then Check(a.setting) end
			return true
		end
	end
	return false
end
