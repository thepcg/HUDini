-- The sound choice, its play function and the sound picker (TICK-0232,
-- D-051; Sounds.lua). A saved bare key plays at full volume as before; a
-- game sound plays through C_Sound.PlaySound with its volume, or
-- PlaySound at full volume on a client without it; a voice plays its
-- quieter copy, or the full file when the client cannot find the copy; the
-- buff-end file is the voice's copy or the game sound's one file. What the
-- player hears needs DK's play.

local function World(setup)
	local w = H.world()
	if setup then setup(w) end
	w:loadAddon()
	return w, w.ns, w.env.HUDiniDB
end

-- Records every sound call. fail[id or path] = true: that sound does not
-- play (returns false). cSound: give the client C_Sound.PlaySound.
local function Ears(w, fail, cSound)
	local heard = {}
	fail = fail or {}
	w.env.PlaySound = function(id, channel)
		heard[#heard + 1] = { api = "PlaySound", id = id, channel = channel }
		return not fail[id]
	end
	w.env.PlaySoundFile = function(path, channel)
		heard[#heard + 1] = { api = "PlaySoundFile", id = path, channel = channel }
		return not fail[path]
	end
	if cSound then
		w.env.C_Sound = {
			PlaySound = function(id, channel, noDup, callback, priority, volume)
				heard[#heard + 1] = { api = "C_Sound", id = id, channel = channel, volume = volume, noDup = noDup }
				return not fail[id]
			end,
		}
	end
	return heard
end

local DIR = "Interface\\AddOns\\HUDini\\Media\\Sounds\\"

--------------------------------------------------------------------------------
-- The list and the volume stops
--------------------------------------------------------------------------------

H.test("The list has the 8 game sounds, then the 24 voices", function()
	local _, ns = World()
	local keys = ns.SoundKeys()
	H.eq(#keys, 32)
	H.eq(keys[1], "readyCheck")
	H.eq(keys[9], "voiceBlocked")
	H.eq(keys[32], "voiceWarning")
	keys[1] = "changed"
	H.eq(ns.SoundKeys()[1], "readyCheck", "a copy")
	H.ok(ns.IsSoundKey("voiceKick"))
	H.ok(not ns.IsSoundKey("voiceNope"))
	H.ok(not ns.IsSoundKey(nil))
end)

H.test("Every sound has a menu name in the locale", function()
	local _, ns = World()
	for _, key in ipairs(ns.SoundKeys()) do
		H.ok(ns.TEXT[0]["sound." .. key], key)
	end
	H.ok(ns.TEXT[0]["opt.sound.volume.value"])
	H.ok(ns.TEXT[0]["opt.sound.picker.tip"])
end)

H.test("A volume snaps to the nearest stop; anything else is full", function()
	local _, ns = World()
	H.eq(ns.SnapVolume(25), 25)
	H.eq(ns.SnapVolume(0), 25)
	H.eq(ns.SnapVolume(60), 50)
	H.eq(ns.SnapVolume(63), 75)
	H.eq(ns.SnapVolume(250), 100)
	H.eq(ns.SnapVolume(nil), 100)
	H.eq(ns.SnapVolume("50"), 100)
	H.eq(ns.SnapVolume(0 / 0), 100)
end)

--------------------------------------------------------------------------------
-- The saved value
--------------------------------------------------------------------------------

H.test("A saved value reads as a choice, or nil for off", function()
	local _, ns = World()
	local c = ns.SoundChoice({ key = "voiceKick", volume = 50 }, "readyCheck")
	H.eq(c.key, "voiceKick"); H.eq(c.volume, 50)
	c = ns.SoundChoice("coins", "readyCheck")
	H.eq(c.key, "coins"); H.eq(c.volume, 100, "a bare key: full volume, as before")
	c = ns.SoundChoice(true, "raidWarning")
	H.eq(c.key, "raidWarning"); H.eq(c.volume, 100)
	H.eq(ns.SoundChoice(false, "readyCheck"), nil)
	H.eq(ns.SoundChoice(nil, "readyCheck"), nil)
	H.eq(ns.SoundChoice("off", "readyCheck"), nil)
end)

H.test("A key that left the list plays the default at the saved volume", function()
	local _, ns = World()
	local c = ns.SoundChoice({ key = "gone", volume = 25 }, "mapPing")
	H.eq(c.key, "mapPing"); H.eq(c.volume, 25)
	c = ns.SoundChoice("gone", "mapPing")
	H.eq(c.key, "mapPing"); H.eq(c.volume, 100)
	H.eq(ns.SoundChoice("gone", "alsoGone"), nil, "no sound to play")
end)

H.test("A saved choice is not changed by reading it", function()
	local _, ns = World()
	local saved = { key = "voiceKick", volume = 60 }
	local c = ns.SoundChoice(saved, "readyCheck")
	H.eq(c.volume, 50)
	H.eq(saved.volume, 60)
	H.ok(c ~= saved)
end)

--------------------------------------------------------------------------------
-- The migration
--------------------------------------------------------------------------------

H.test("The migration turns saved keys into choices at full volume", function()
	local _, ns = World()
	local db = { classes = {
		MAGE = {
			readySounds = { ["Frost Nova"] = "coins", ["Blink"] = false, ["Counterspell"] = true },
			readySoundLast = { ["Frost Nova"] = "voiceKick" },
			keepUpSound = "raidWarning",
		},
		ROGUE = { keepUpSound = false },
		DRUID = { keepUpSound = true, readySounds = { Moonfire = { key = "mapPing", volume = 40 } } },
		BAD = "not a table",
	} }
	ns.MigrateSounds(db)
	local mage = db.classes.MAGE
	H.eq(mage.readySounds["Frost Nova"].key, "coins")
	H.eq(mage.readySounds["Frost Nova"].volume, 100)
	H.eq(mage.readySounds["Blink"], false, "off stays off")
	H.eq(mage.readySounds["Counterspell"], true, "the default stays the default")
	H.eq(mage.readySoundLast["Frost Nova"].key, "voiceKick")
	H.eq(mage.keepUpSound.key, "raidWarning")
	H.eq(mage.keepUpSound.volume, 100)
	H.eq(db.classes.ROGUE.keepUpSound, false)
	H.eq(db.classes.DRUID.keepUpSound, true)
	H.eq(db.classes.DRUID.readySounds.Moonfire.volume, 50, "snapped to a stop")
	H.eq(db.classes.BAD, "not a table")
end)

H.test("The migration is safe to run again and on bad data", function()
	local _, ns = World()
	local db = { classes = { MAGE = { keepUpSound = "coins", readySounds = { A = { volume = 50 } } } } }
	ns.MigrateSounds(db)
	ns.MigrateSounds(db)
	H.eq(db.classes.MAGE.keepUpSound.key, "coins")
	H.eq(db.classes.MAGE.keepUpSound.volume, 100)
	H.eq(db.classes.MAGE.readySounds.A, false, "a choice with no key is off, not the start")
	ns.MigrateSounds(nil)
	ns.MigrateSounds({})
	ns.MigrateSounds({ classes = 5 })
end)

--------------------------------------------------------------------------------
-- Playing
--------------------------------------------------------------------------------

H.test("A game sound plays through C_Sound with its volume", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	H.eq(ns.PlaySoundChoice({ key = "readyCheck", volume = 50 }, "raidWarning"), 8960)
	H.eq(#heard, 1)
	H.eq(heard[1].api, "C_Sound")
	H.eq(heard[1].id, 8960)
	H.eq(heard[1].channel, "Master")
	H.eq(heard[1].volume, 0.5)
	H.eq(heard[1].noDup, false, "a sound that still plays may play again, at its volume")
end)

H.test("Without C_Sound a game sound plays at full volume", function()
	local w, ns = World()
	local heard = Ears(w)
	H.eq(ns.PlaySoundChoice({ key = "coins", volume = 25 }), 120)
	H.eq(#heard, 1)
	H.eq(heard[1].api, "PlaySound")
	H.eq(heard[1].id, 120)
	H.eq(heard[1].channel, "Master")
end)

H.test("A C_Sound that throws falls back to PlaySound", function()
	local w, ns = World()
	local heard = Ears(w)
	w.env.C_Sound = { PlaySound = function() error("bad argument") end }
	H.eq(ns.PlaySoundChoice("mapPing"), 3175)
	H.eq(heard[#heard].api, "PlaySound")
end)

H.test("A voice plays its quieter copy; full volume plays the full file", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	H.eq(ns.PlaySoundChoice({ key = "voiceKick", volume = 25 }), DIR .. "Kick_25.ogg")
	H.eq(heard[1].api, "PlaySoundFile")
	H.eq(heard[1].channel, "Master")
	H.eq(ns.PlaySoundChoice("voiceKick"), DIR .. "Kick.ogg")
	H.eq(#heard, 2)
end)

H.test("A copy the client cannot find plays the full voice", function()
	local w, ns = World()
	local heard = Ears(w, { [DIR .. "Shock_50.ogg"] = true })
	H.eq(ns.PlaySoundChoice({ key = "voiceShock", volume = 50 }), DIR .. "Shock.ogg")
	H.eq(#heard, 2)
end)

H.test("A sound that will not play falls to the default, then the last sound", function()
	local w, ns = World()
	local heard = Ears(w, { [120] = true }, true)
	H.eq(ns.PlaySoundChoice({ key = "coins", volume = 75 }, "mapPing"), 3175)
	H.eq(heard[#heard].volume, 0.75, "the default at the choice's volume")
	heard = Ears(w, { [120] = true, [3175] = true }, true)
	H.eq(ns.PlaySoundChoice({ key = "coins", volume = 75 }, "mapPing"), 8959)
	heard = Ears(w, { [120] = true, [8959] = true }, true)
	H.eq(ns.PlaySoundChoice("coins"), nil, "nothing plays")
	H.eq(#heard, 4, "C_Sound then PlaySound for each of the two")
end)

H.test("Off plays nothing", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	H.eq(ns.PlaySoundChoice(false, "readyCheck"), nil)
	H.eq(ns.PlaySoundChoice(nil, "readyCheck"), nil)
	H.eq(ns.PlaySoundChoice("off", "readyCheck"), nil, "off")
	H.eq(ns.PlaySoundChoice({}, "readyCheck"), nil, "a choice with no key")
	H.eq(ns.PlaySoundChoice({ volume = 50 }, nil), nil, "no key, no default")
	H.eq(#heard, 0)
end)

H.test("The buff-end file is the voice's copy or the game sound's file", function()
	local _, ns = World()
	H.eq(ns.SoundFile({ key = "voiceBuff", volume = 75 }), DIR .. "Buff_75.ogg")
	H.eq(ns.SoundFile("voiceBuff"), DIR .. "Buff.ogg")
	H.eq(ns.SoundFile({ key = "raidWarning", volume = 25 }), 567397, "full volume")
	H.eq(ns.SoundFile(true, "readyCheck"), 567478)
	H.eq(ns.SoundFile(false, "readyCheck"), nil)
end)

H.test("Every quieter copy is in the public file list", function()
	local _, ns = World()
	-- The list is private, so the public copy has none: check it only here.
	local f = io.open("tools/public-files.txt", "r")
	if not f then return end
	local listed = {}
	for line in f:lines() do listed[line:gsub("\r$", "")] = true end
	f:close()
	H.ok(listed["Sounds.lua"])
	for _, key in ipairs(ns.SoundKeys()) do
		local name = key:match("^voice(.+)$")
		if name then
			for _, v in ipairs({ 25, 50, 75 }) do
				H.ok(listed[("Media/Sounds/%s_%d.ogg"):format(name, v)], name .. v)
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- The picker
--------------------------------------------------------------------------------

-- A menu description that writes down its rows.
local function Root()
	local root = { rows = {} }
	function root:CreateRadio(text, isSet, set, value)
		local row = { text = text, isSet = isSet, set = set, value = value }
		self.rows[#self.rows + 1] = row
		return row
	end
	function root:SetScrollMode(h) self.scroll = h end
	return root
end

local function Find(root, value)
	for _, row in ipairs(root.rows) do
		if row.value == value then return row end
	end
end

-- A picker bound to a saved value in a box.
local function Picker(w, ns, saved, opts)
	local box = { v = saved, sets = 0 }
	local p = ns.CreateSoundPicker(w.env.UIParent, 280)
	local bind = {
		get = function() return box.v end,
		set = function(v) box.v = v; box.sets = box.sets + 1 end,
		default = "readyCheck",
		withOff = true,
		label = "Test sound",
	}
	for k, v in pairs(opts or {}) do bind[k] = v end
	ns.BindSoundPicker(p, bind)
	return p, box
end

H.test("The list shows Off, then every sound, in one scrolling column", function()
	local w, ns = World()
	local p = Picker(w, ns, "coins")
	local root = Root()
	ns.SoundMenu(p, root)
	H.eq(#root.rows, 33)
	H.eq(root.rows[1].value, "off")
	H.eq(root.rows[1].text, "Off")
	H.eq(root.rows[2].value, "readyCheck")
	H.eq(root.rows[2].text, "Ready check (default)")
	H.ok(root.scroll, "scrolls, so it stays one column")
	H.ok(Find(root, "coins").isSet())
	H.ok(not Find(root, "off").isSet())
end)

H.test("Without withOff the list has no Off row", function()
	local w, ns = World()
	local p = Picker(w, ns, "coins", { withOff = false })
	local root = Root()
	ns.SoundMenu(p, root)
	H.eq(#root.rows, 32)
	H.eq(ns.PickSound(p, "off"), false)
end)

H.test("A pick saves the sound at the slider's volume and plays it", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	local p, box = Picker(w, ns, { key = "coins", volume = 25 })
	local root = Root()
	ns.SoundMenu(p, root)
	Find(root, "voiceKick").set()
	H.eq(box.v.key, "voiceKick")
	H.eq(box.v.volume, 25, "keeps the volume")
	H.eq(heard[#heard].id, DIR .. "Kick_25.ogg", "a preview")
	H.ok(Find(root, "voiceKick").isSet())
end)

H.test("Off saves false and turns the slider off; the volume stays", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	local p, box = Picker(w, ns, { key = "coins", volume = 50 })
	H.eq(p.volume.__h.value, 50)
	H.eq(ns.PickSound(p, "off"), true)
	H.eq(box.v, false)
	H.eq(#heard, 0, "Off plays nothing")
	H.ok(p.volume.__h.disabled)
	ns.PickSound(p, "mapPing")
	H.eq(box.v.volume, 50, "the last volume")
	H.ok(not p.volume.__h.disabled)
end)

H.test("The slider saves the new volume and plays the sound at it", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	local p, box = Picker(w, ns, "raidWarning")
	H.eq(p.volume.__h.value, 100, "an old bare key shows full volume")
	H.eq(ns.PickVolume(p, 74), true)
	H.eq(box.v.key, "raidWarning")
	H.eq(box.v.volume, 75)
	H.eq(heard[#heard].volume, 0.75)
	H.eq(ns.PickVolume(p, 75), false, "the same stop saves nothing")
	H.eq(box.sets, 1)
end)

H.test("The slider with the sound off saves nothing but keeps the volume", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	local p, box = Picker(w, ns, false)
	H.eq(ns.PickVolume(p, 25), false)
	H.eq(box.v, false)
	H.eq(#heard, 0)
	ns.PickSound(p, "coins")
	H.eq(box.v.volume, 25)
end)

H.test("A gray picker turns off its list and slider and picks nothing", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	local gray = true
	local p, box = Picker(w, ns, { key = "coins", volume = 50 }, {
		enabled = function() return not gray end,
	})
	H.eq(p.menu:IsEnabled(), false, "the list is off")
	H.eq(p.volume:IsEnabled(), false, "the slider is off")
	H.eq(p:GetAlpha(), 0.5, "half alpha")
	H.eq(ns.PickSound(p, "mapPing"), false, "a pick saves nothing")
	H.eq(ns.PickSound(p, "off"), false, "Off saves nothing")
	H.eq(ns.PickVolume(p, 25), false, "the slider saves nothing")
	H.eq(box.sets, 0)
	H.eq(#heard, 0, "no preview")
	ns.RepaintSoundPickers()
	H.eq(p.volume:IsEnabled(), false, "a repaint keeps it gray")
	gray = false
	ns.RepaintSoundPickers()
	H.eq(p.menu:IsEnabled(), true, "on again: the list")
	H.eq(p.volume:IsEnabled(), true, "on again: the slider")
	H.eq(p:GetAlpha(), 1, "on again: full alpha")
	H.eq(ns.PickVolume(p, 25), true, "on again: the slider saves")
	H.eq(box.v.volume, 25)
end)

H.test("Without enabled a picker is never gray; Off still turns the slider off", function()
	local w, ns = World()
	local p = Picker(w, ns, false)
	H.eq(p.menu:IsEnabled(), true)
	H.eq(p.volume:IsEnabled(), false, "Off: the slider is off")
	H.eq(p:GetAlpha(), 1)
end)

H.test("The default (true) shows the default sound picked", function()
	local w, ns = World()
	local p = Picker(w, ns, true)
	local root = Root()
	ns.SoundMenu(p, root)
	H.ok(Find(root, "readyCheck").isSet())
end)

H.test("A repaint shows a value the host changed", function()
	local w, ns = World()
	local p, box = Picker(w, ns, { key = "coins", volume = 25 })
	box.v = { key = "coins", volume = 75 }
	ns.RepaintSoundPickers()
	H.eq(p.volume.__h.value, 75)
end)

H.test("An unbound picker reads and writes nothing", function()
	local w, ns = World()
	local heard = Ears(w, nil, true)
	local p, box = Picker(w, ns, "coins")
	ns.UnbindSoundPicker(p)
	H.eq(ns.PickSound(p, "mapPing"), false)
	H.eq(ns.PickVolume(p, 25), false)
	local root = Root()
	ns.SoundMenu(p, root)
	H.eq(#root.rows, 0)
	ns.RepaintSoundPickers()
	H.eq(box.v, "coins")
	H.eq(#heard, 0)
end)

-- A frame of the game's SettingsListElementTemplate as this client makes
-- it: the mixin's methods, and no callback list, as its OnLoad never runs
-- (the template has no OnLoad script of its own; only its Tooltip child
-- has one: Blizzard_SettingControls.xml:50-78, wow-ui-source forever
-- 9dc84f0). Init asserts the list is empty and signs up one handle per
-- setting a grayed row reads (.lua:331 and :349-354); Release empties it.
local function BaseRow(w)
	local frame = w:Frame(nil, w.env.UIParent)
	local log = {}
	frame.OnLoad = function(self)
		local n = 0
		self.cbrHandles = {
			IsEmpty = function() return n == 0 end,
			Add = function() n = n + 1 end,
			Unregister = function() n = 0; log[#log + 1] = "unregister" end,
		}
	end
	frame.Init = function(self, init)
		assert(self.cbrHandles:IsEmpty())
		for _ in ipairs(init:GetEvaluateStateCVars() or {}) do self.cbrHandles.Add() end
		self.data = init.data
		log[#log + 1] = "init"
	end
	frame.Release = function(self)
		self.cbrHandles:Unregister()
		self.data = nil
	end
	return frame, log
end

-- The game's element initializer, as far as the row uses it, with the
-- settings a grayed row reads (GreyUnless in Options.lua).
local function RowMaker(w)
	w.env.Settings.CreateElementInitializer = function(template, data)
		local cvars
		return { template = template, data = data, AddSearchTags = function() end,
			AddEvaluateStateCVar = function(_, v) cvars = cvars or {}; cvars[#cvars + 1] = v end,
			GetEvaluateStateCVars = function() return cvars end }
	end
	return { AddInitializer = function() end }
end

-- Draw, free, draw again on the same pooled frame, grayed by one setting.
-- part: the row's HUDini child; bound: its bound field.
local function PoolTwice(w, init, part, bound)
	init:AddEvaluateStateCVar("HUDini_showHealth")
	H.eq(init.GetExtent and init:GetExtent(), 26, "26 high, as the game's rows")
	local frame, log = BaseRow(w)
	local ok, err = pcall(init.InitFrame, init, frame)
	H.ok(ok, "no Lua error: " .. tostring(err))
	H.eq(log[1], "init", "the game's Init ran")
	local x = frame[part]
	H.ok(x and x:IsShown() and x[bound], "it shows, bound")
	init.Resetter(init, frame)
	H.eq(log[2], "unregister", "a freed row lets the game's list go")
	H.eq(x[bound], nil, "and its own part")
	ok, err = pcall(init.InitFrame, init, frame)
	H.ok(ok, "the pooled frame draws again, its list empty: " .. tostring(err))
	H.ok(x:IsShown() and x[bound], "bound again")
end

H.test("TICK-0240: a sound row draws on the game's base row, whose OnLoad never ran", function()
	local w, ns = World()
	local init = ns.AddSoundRow(nil, RowMaker(w), { label = "Ready",
		get = function() end, set = function() end })
	H.ok(init, "a row")
	PoolTwice(w, init, "hudiniSound", "bind")
end)

H.test("A row of its own needs the game's settings rows", function()
	local w, ns = World()
	H.eq(ns.AddSoundRow(nil, nil, { get = function() end, set = function() end }), nil)
	local _ = w
end)
