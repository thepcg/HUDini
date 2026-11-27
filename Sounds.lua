--[[--------------------------------------------------------------------------
	HUDini - Sounds: one sound choice, one play function, one picker
	(TICK-0232, D-051)

	Every place where the player picks a sound uses this file, as every bar
	look uses BarLookButton.lua.

	A sound choice (the saved shape):

		{ key = "voiceKick", volume = 50 }

	key is a sound of the list below; volume is one of ns.SOUND_VOLUMES
	(25, 50, 75, 100). Off is false, kept by the host, not by this file.
	ns.SoundChoice reads any saved value: a choice, a bare key (saved before
	TICK-0232: full volume), true (the host's default), or off. A key that
	left the list plays the default, at the saved volume.

	The volume (the TICK-0232 spike, its Notes):
	  - a game sound (a kit) plays through C_Sound.PlaySound, whose last
	    argument is a volume (12.1.0 and later); a client without it plays
	    PlaySound at full volume;
	  - a voice is a file, and no file API takes a volume: each voice has
	    quieter copies, Media/Sounds/<Name>_25.ogg, _50 and _75. A copy the
	    client cannot play (a file missing from the folder) gives the voice
	    at full volume. The copies and this file come in one build, and a
	    new file needs a full restart, not /reload;
	  - the game's buff-end sound in a fight takes a file (ns.SoundFile): a
	    voice gets its quieter copy, a game sound its one file at full
	    volume, since HUDini cannot ship copies of the game's files.

	The picker: a drop-down list of every sound, one column, one sound per
	row, that plays the sound when picked, and a volume slider next to it
	that plays it again at the new volume. A host (a settings row, a grid
	row) does this:

		local p = ns.CreateSoundPicker(rowFrame, 280)       -- once per frame
		ns.BindSoundPicker(p, {                              -- on each draw
			get = function() return saved end,  -- a choice, key, true or false
			set = function(choice) ... end,     -- a choice, or false for Off
			default = "readyCheck",             -- the key for true and for a
			                                    -- key that left the list
			withOff = true,                     -- Off first in the list
			label = ...,                        -- the tooltip title
			tip = nil,                          -- the tooltip's last line
			enabled = nil,                      -- optional: a function; when
			                                    -- it returns false or nil the
			                                    -- picker is gray and picks
			                                    -- nothing (the row's gray rule)
		})
		ns.UnbindSoundPicker(p)                              -- the frame goes
		                                                     -- to another row

	Or, for a row of its own on a settings page:

		ns.AddSoundRow(category, layout, { get = ..., set = ..., label = ... })

	The page's Defaults does not reach a bound picker: the host resets its
	saved value and calls ns.RepaintSoundPickers().
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local Text = ns.Text
-- The game's objects that some clients lack (C_Sound before 12.1.0, the
-- slider's mixin): read through _G, nil when absent.
local G = _G

--------------------------------------------------------------------------------
-- The sounds
--------------------------------------------------------------------------------

-- The game's own sound kits (SOUNDKIT, SoundKitConstants.lua), old enough
-- to be in WoW Forever's data (D-043, TICK-0167). The cooldown viewer's
-- kits (353392, 353397) are not: PlaySound returns nothing for them there
-- (DK's test, 2026-11-21). The third value is the kit's one sound file
-- (the game's SoundKitEntry table, by wago.tools), for the buff-end sound,
-- which takes a file (C_UnitAuras.AddAuraSound, Auras.lua, TICK-0168).
-- The names are the locale's "sound.<key>".
local GAME_SOUNDS = {
	{ "readyCheck",   8960, 567478 }, -- READY_CHECK
	{ "raidWarning",  8959, 567397 }, -- RAID_WARNING
	{ "mapPing",      3175, 567416 }, -- MAP_PING
	{ "whisper",      3081, 567421 }, -- TELL_MESSAGE
	{ "bossEmote",   12197, 567394 }, -- RAID_BOSS_EMOTE_WARNING
	{ "alarmClock",  12867, 567399 }, -- ALARM_CLOCK_WARNING_2
	{ "pvpQueue",     8459, 568011 }, -- PVP_THROUGH_QUEUE
	{ "coins",         120, 567428 }, -- LOOT_WINDOW_COIN_SOUND
}
-- HUDini's voice sounds (D-050, TICK-0230): DK's clips, after the game's
-- sounds. A key is "voice" and the clip's file name: voiceKick plays
-- Media/Sounds/Kick.ogg. Kept as keys, so no clip name reads as player text.
-- locale: skip keys; the menu names are sound.voice<Name>
-- TICK-0244 added Curse, Disease, Dodge, Enrage, FadingSoon, Magic, Purge
-- and Ready. In name order.
local VOICES = {
	"voiceBlocked", "voiceBuff", "voiceCombat", "voiceCurse", "voiceDisease",
	"voiceDodge", "voiceEnrage", "voiceExecute", "voiceFadingSoon", "voiceGotem",
	"voiceHealth", "voiceKick", "voiceMagic", "voiceMana", "voiceParried",
	"voicePoison", "voicePurge", "voiceReady", "voiceSafe", "voiceShield",
	"voiceShock", "voiceSilenced", "voiceStab", "voiceWarning",
}
-- locale: end
local VOICE_DIR = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Sounds\\" -- locale: skip a path

-- The volume stops, quietest first. A voice has a file for each.
ns.SOUND_VOLUMES = { 25, 50, 75, 100 }
local FULL = 100
-- DK heard it play on WoW Forever: the last try when a pick will not play.
local LAST_SOUND = 8959
-- The game's sound channel: Master, so a sound plays with Sound Effects
-- turned down.
local CHANNEL = "Master" -- locale: skip the game's sound channel

-- kit[key]: the kit ID of a game sound. fileOf[key]: its file ID.
-- voice[key]: a voice's name.
local kit, fileOf, voice, keys = {}, {}, {}, {}
for i, s in ipairs(GAME_SOUNDS) do
	keys[i], kit[s[1]], fileOf[s[1]] = s[1], s[2], s[3]
end
for _, key in ipairs(VOICES) do
	keys[#keys + 1], voice[key] = key, key:sub(6)
end

-- The keys in menu order (a copy).
function ns.SoundKeys()
	local out = {}
	for i, key in ipairs(keys) do out[i] = key end
	return out
end

-- True when key is a sound of the list.
function ns.IsSoundKey(key)
	return key ~= nil and (kit[key] ~= nil or voice[key] ~= nil)
end

-- Two defaults that differ, so good news and a warning are told apart.
ns.READY_SOUND_DEFAULT   = "readyCheck"
ns.MISSING_SOUND_DEFAULT = "raidWarning"

-- The names the alerts used before this file (Alerts.lua, TICK-0167): the
-- option rows and the setup still call them.
function ns.AlertSounds() return ns.SoundKeys() end
function ns.IsAlertSound(key) return ns.IsSoundKey(key) end
function ns.PlayAlertSound(saved, default) return ns.PlaySoundChoice(saved, default) end

-- The volume stop nearest to v (a number, 0 to 100); full for anything
-- else.
function ns.SnapVolume(v)
	if type(v) ~= "number" or v ~= v then return FULL end
	local best, gap = FULL, math.huge
	for _, stop in ipairs(ns.SOUND_VOLUMES) do
		local d = math.abs(stop - v)
		if d < gap then best, gap = stop, d end
	end
	return best
end

--------------------------------------------------------------------------------
-- The sound choice
--------------------------------------------------------------------------------

-- A new choice, or nil when key is not a sound of the list.
function ns.NewSoundChoice(key, volume)
	if not ns.IsSoundKey(key) then return nil end
	return { key = key, volume = ns.SnapVolume(volume) }
end

-- A saved value as a choice that plays (a new table), or nil for off.
-- saved: a choice, a bare key (full volume), true (default at full
-- volume), or false, nil or "off". A key that left the list gives the
-- default, at the saved volume; nil when default is not a sound either.
-- A table with no key is off, as ns.MigrateSounds saves it (false).
function ns.SoundChoice(saved, default)
	local key, volume
	if type(saved) == "table" then
		if type(saved.key) ~= "string" then return nil end
		key, volume = saved.key, saved.volume
	elseif saved == true then
		key = default
	elseif type(saved) == "string" and saved ~= "off" then
		key = saved
	else
		return nil
	end
	if not ns.IsSoundKey(key) then key = default end
	return ns.NewSoundChoice(key, volume)
end

-- True when two saved values are the same as saved: the same choice (key
-- and volume), or the same plain value (true, false, nil, a key).
function ns.SameSound(a, b)
	if type(a) == "table" and type(b) == "table" then
		return a.key == b.key and a.volume == b.volume
	end
	return a == b
end

-- The path of a voice at a volume: the full file, or its quieter copy.
local function VoicePath(name, volume)
	if volume >= FULL then return VOICE_DIR .. name .. ".ogg" end -- locale: skip a file type
	return ("%s%s_%d.ogg"):format(VOICE_DIR, name, volume) -- locale: skip a path
end

-- The file the game's buff-end sound plays for a choice (any saved value,
-- as ns.SoundChoice): a voice's path at its volume, or a game sound's file
-- ID (full volume). nil for off.
function ns.SoundFile(saved, default)
	local c = ns.SoundChoice(saved, default)
	if not c then return nil end
	if voice[c.key] then return VoicePath(voice[c.key], c.volume) end
	return fileOf[c.key]
end

--------------------------------------------------------------------------------
-- Playing
--------------------------------------------------------------------------------

-- One kit at a volume: C_Sound.PlaySound with its volume where the client
-- has it, else PlaySound (full volume). True when it plays.
local function PlayKit(id, volume)
	local api = G.C_Sound
	if api and api.PlaySound then
		-- forceNoDuplicates false, as PlaySound: a kit that still plays (two
		-- cooldowns at once, a slider moved faster than the sound) plays
		-- again at its volume, not through the full-volume PlaySound below.
		local ok, played = pcall(api.PlaySound, id, CHANNEL, false, false, nil, volume / FULL)
		if ok and played then return true end
		-- Not played (a kit C_Sound does not know) or an error: PlaySound
		-- may know it. Neither played, so the sound never plays twice.
	end
	local ok, played = pcall(PlaySound, id, CHANNEL)
	return ok and played and true or false
end

local function PlayFile(path)
	local ok, played = pcall(PlaySoundFile, path, CHANNEL)
	return ok and played and true or false
end

-- Plays a saved value's sound once (any saved value, as ns.SoundChoice).
-- If the client cannot play it: the voice at full volume (a quieter copy
-- the client has not found yet), then default's sound, then LAST_SOUND,
-- each at the choice's volume. The kit ID or file path played, or nil
-- (off, or nothing would play). A preview calls it on each pick, so it
-- never skips a call.
function ns.PlaySoundChoice(saved, default)
	local c = ns.SoundChoice(saved, default)
	if not c then
		if saved == nil or saved == false or saved == "off" or type(saved) == "table" then return nil end
		-- A key that left the list, with no default: only LAST_SOUND.
		c = { volume = FULL }
	end
	local tries = { c.key }
	if ns.IsSoundKey(default) then tries[2] = default end
	local tried = {}
	for _, key in ipairs(tries) do
		local name = voice[key]
		if name then
			for _, path in ipairs({ VoicePath(name, c.volume), VoicePath(name, FULL) }) do
				if not tried[path] then
					tried[path] = true
					if PlayFile(path) then return path end
				end
			end
		elseif kit[key] and not tried[kit[key]] then
			tried[kit[key]] = true
			if PlayKit(kit[key], c.volume) then return kit[key] end
		end
	end
	if not tried[LAST_SOUND] and PlayKit(LAST_SOUND, c.volume) then return LAST_SOUND end
	return nil
end

--------------------------------------------------------------------------------
-- Migration
--------------------------------------------------------------------------------

-- A bare key saved before TICK-0232 becomes a choice at full volume, so it
-- sounds as before; a choice gets its volume snapped to a stop. true,
-- false and nil stay: they mean "the default" and "off" to their hosts.
-- The cooldown sounds (readySounds, readySoundLast; ns.MigrateCooldowns
-- turns their old true into a key first) and the buff missing sound
-- (keepUpSound, keepUpSoundLast), in every class's table. Safe to run
-- again.
local function MigrateValue(v)
	if type(v) == "string" and v ~= "off" then return { key = v, volume = FULL } end
	if type(v) == "table" then
		-- Off, not nil: nil means "the start" to a host, which can be on,
		-- and a bad value reads as off (TICK-0203).
		if type(v.key) ~= "string" then return false end
		return { key = v.key, volume = ns.SnapVolume(v.volume) }
	end
	return v
end

function ns.MigrateSounds(db)
	if type(db) ~= "table" or type(db.classes) ~= "table" then return end
	for _, mine in pairs(db.classes) do
		if type(mine) == "table" then
			for _, part in ipairs({ "readySounds", "readySoundLast" }) do
				if type(mine[part]) == "table" then
					for name, v in pairs(mine[part]) do mine[part][name] = MigrateValue(v) end
				end
			end
			mine.keepUpSound = MigrateValue(mine.keepUpSound)
			mine.keepUpSoundLast = MigrateValue(mine.keepUpSoundLast)
		end
	end
end

--------------------------------------------------------------------------------
-- The picker
--------------------------------------------------------------------------------

local PICKER_W, MENU_W, ROW_H = 280, 150, 26
-- The list scrolls past this height, so it stays one column.
local MENU_MAX_H = 400

local pickers = setmetatable({}, { __mode = "k" })

-- The bound value as a choice (nil when off), and the volume the slider
-- shows (the choice's, else the last one picked on this picker).
local function Current(p)
	local bind = p.bind
	if not bind then return nil, FULL end
	local c = ns.SoundChoice(bind.get(), bind.default)
	return c, c and c.volume or p.lastVolume or FULL
end

-- False when the host grays the row: bind.enabled returns false or nil.
local function Enabled(bind)
	if not bind then return false end
	if bind.enabled == nil then return true end
	return bind.enabled() and true or false
end

-- Gray (bind.enabled says off): the list and the slider are off and the
-- picker is at half alpha, as the game's gray buttons. Else the list is on
-- and the slider is on with a sound.
local function Paint(p)
	local c, volume = Current(p)
	local on = Enabled(p.bind)
	p.lastVolume = volume
	p.painting = true
	local slider = p.volume
	if slider and slider.SetValue then slider:SetValue(volume) end
	if slider and slider.SetEnabled then slider:SetEnabled(on and c ~= nil) end
	p.painting = false
	local menu = p.menu
	if menu and menu.SetEnabled then menu:SetEnabled(on) end
	if p.SetAlpha then p:SetAlpha(on and 1 or 0.5) end
	if menu and menu.GenerateMenu then menu:GenerateMenu() end
end

-- Every bound picker shows its saved value again.
function ns.RepaintSoundPickers()
	for p in pairs(pickers) do Paint(p) end
end

local function Preview(p)
	local bind = p.bind
	if bind then ns.PlaySoundChoice(bind.get(), bind.default) end
end

-- Pick "off" or a key on a bound picker: the choice keeps the slider's
-- volume. Plays it (a preview). True if a choice was saved. A gray picker
-- picks nothing.
function ns.PickSound(p, key)
	local bind = p.bind
	if not Enabled(bind) then return false end
	if key == "off" then
		if not bind.withOff then return false end
		bind.set(false)
		Paint(p)
		return true
	end
	local c = ns.NewSoundChoice(key, p.lastVolume or FULL)
	if not c then return false end
	bind.set(c)
	Paint(p)
	Preview(p)
	return true
end

-- Move a bound picker's volume (snapped to a stop). With a sound on, saves
-- it and plays the sound at the new volume; with Off, the slider keeps it
-- for the next pick. True if a choice was saved. A gray picker changes
-- nothing.
function ns.PickVolume(p, v)
	if p.painting or not Enabled(p.bind) then return false end
	local volume = ns.SnapVolume(v)
	p.lastVolume = volume
	local c = Current(p)
	if not c then return false end
	if c.volume == volume then return false end
	c.volume = volume
	p.bind.set(c)
	Paint(p)
	Preview(p)
	return true
end

-- Fill a bound picker's list (root: the game's menu description): Off
-- when withOff, then every sound, one per row in one column. A function
-- of its own, so a test can fill a fake root.
function ns.SoundMenu(p, root)
	local bind = p.bind
	if not bind then return end
	if root.SetScrollMode then root:SetScrollMode(MENU_MAX_H) end
	local function Selected(key)
		local c = ns.SoundChoice(bind.get(), bind.default)
		if key == "off" then return c == nil end
		return c ~= nil and c.key == key
	end
	local function Radio(key, label)
		root:CreateRadio(label, function() return Selected(key) end,
			function() ns.PickSound(p, key) end, key)
	end
	if bind.withOff then Radio("off", Text("opt.sound.off")) end -- locale: skip a key
	for _, key in ipairs(keys) do
		local label = Text("sound." .. key)
		if key == bind.default then label = label .. " " .. Text("setup.default") end
		Radio(key, label)
	end
end

local function ShowTip(p)
	local bind = p.bind
	if not (bind and GameTooltip) then return end
	GameTooltip:SetOwner(p, "ANCHOR_RIGHT")
	GameTooltip:SetText(bind.label or "", 1, 1, 1)
	GameTooltip:AddLine(bind.tip or Text("opt.sound.picker.tip"), nil, nil, nil, true)
	GameTooltip:Show()
end

local function HideTip()
	if GameTooltip then GameTooltip:Hide() end
end

local function VolumeLabel(v)
	return Text("opt.sound.volume.value", ns.SnapVolume(v))
end

-- The game's minimal slider, 25 to 100 in three steps, its value at the
-- right. Without the template (the test harness) a plain frame.
local function NewSlider(p)
	local s = CreateFrame("Frame", nil, p, "MinimalSliderWithSteppersTemplate")
	local mixin = G.MinimalSliderWithSteppersMixin
	if s.Init and mixin and mixin.Label then
		local right = mixin.Label.Right
		local format = VolumeLabel
		if G.CreateMinimalSliderFormatter then format = G.CreateMinimalSliderFormatter(right, VolumeLabel) end
		s:Init(FULL, ns.SOUND_VOLUMES[1], FULL, #ns.SOUND_VOLUMES - 1, { [right] = format })
	end
	if s.RegisterCallback and mixin and mixin.Event then
		s:RegisterCallback(mixin.Event.OnValueChanged, function(_, v) ns.PickVolume(p, v) end, p)
	end
	return s
end

-- A sound picker, width wide: the list at the left, the volume slider at
-- the right. Made once per frame; BindSoundPicker gives it a saved value.
function ns.CreateSoundPicker(parent, width)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(width or PICKER_W, ROW_H)

	p.menu = CreateFrame("DropdownButton", nil, p, "WowStyle2DropdownTemplate")
	p.menu:SetPoint("LEFT", p, "LEFT", 0, 0)
	p.menu:SetWidth(MENU_W)
	if p.menu.SetupMenu then
		p.menu:SetupMenu(function(_, root) ns.SoundMenu(p, root) end)
	end

	p.volume = NewSlider(p)
	p.volume:SetPoint("LEFT", p.menu, "RIGHT", 8, 0)
	p.volume:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	p.volume:SetHeight(ROW_H)

	for _, part in ipairs({ p.menu, p.volume }) do
		part:HookScript("OnEnter", function() ShowTip(p) end)
		part:HookScript("OnLeave", HideTip)
	end
	return p
end

-- Bind a picker to a saved value (see the header for bind's fields) and
-- show it.
function ns.BindSoundPicker(p, bind)
	p.bind = bind
	pickers[p] = true
	Paint(p)
	return p
end

-- Free a picker for another row: it no longer reads or writes anything.
function ns.UnbindSoundPicker(p)
	p.bind = nil
	pickers[p] = nil
end

--------------------------------------------------------------------------------
-- A row of its own
--------------------------------------------------------------------------------

-- The game's base row template runs no OnLoad of its own (only its Tooltip
-- child has one), so its frame lacks the callback list that the mixin's
-- OnLoad makes and its Init asserts on (Blizzard_SettingControls.xml:50-78,
-- .lua:305-307 and :331, wow-ui-source forever 9dc84f0). Make it once, as
-- that OnLoad does (TICK-0240). Init then runs as for the game's rows: with
-- no list it errors, rather than leave a pooled frame's last label.
local function ReadyRow(frame)
	if frame.cbrHandles == nil and frame.OnLoad then frame:OnLoad() end
end

-- The bare template has no size either, and the list takes a row's height
-- from its initializer's GetExtent, else from the template (0 here:
-- Blizzard_SettingsList.lua:68-71). The game's own rows are 26 high
-- (SettingsCheckboxControlTemplate and its kin, Blizzard_SettingControls.xml
-- :107-140). TICK-0240.
local ROW_HEIGHT = 26
local function RowExtent() return ROW_HEIGHT end

local function InitRow(init, frame)
	ReadyRow(frame)
	if frame.Init then frame:Init(init) end
	local p = frame.hudiniSound
	if not p then
		p = ns.CreateSoundPicker(frame, PICKER_W)
		-- Where the game puts a dropdown on its rows.
		p:SetPoint("LEFT", frame, "CENTER", -80, 0)
		frame.hudiniSound = p
	end
	p:Show()
	ns.BindSoundPicker(p, init.data.sound)
end

-- The game pools its row frames: a frame given to another row hides the
-- picker.
local function ResetRow(_, frame)
	local p = frame.hudiniSound
	if p then
		p:Hide()
		ns.UnbindSoundPicker(p)
	end
	-- What the game's own resetter does (ScrollUtil.lua:1703-1707): free
	-- what Init signed up. A grayed row (GreyUnless) signs up one handle
	-- per setting it reads, and the next Init asserts the list is empty.
	if frame.Release then frame:Release() end
end

-- A settings row with the label at the left and a sound picker, its label
-- as a search tag. bind: as BindSoundPicker. Returns the row's initializer
-- (nil without the game's element initializer, as in the test harness).
function ns.AddSoundRow(_, layout, bind)
	if not (Settings and Settings.CreateElementInitializer) then return end
	local tip = bind.tip or Text("opt.sound.picker.tip")
	local init = Settings.CreateElementInitializer("SettingsListElementTemplate",
		{ name = bind.label, tooltip = tip, sound = bind })
	init.InitFrame, init.Resetter, init.GetExtent = InitRow, ResetRow, RowExtent
	layout:AddInitializer(init)
	if init.AddSearchTags and bind.label then init:AddSearchTags(bind.label) end
	return init
end
