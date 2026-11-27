-- The 8 voices DK added on 2026-11-23 (TICK-0244): in every sound list,
-- 4 files each (full and the 25, 50 and 75 % copies), each public, and the
-- class alert sounds that start on them.

local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

local NEW = { "Curse", "Disease", "Dodge", "Enrage", "FadingSoon", "Magic", "Purge", "Ready" }
local DIR = "Interface\\AddOns\\HUDini\\Media\\Sounds\\"

local function World(class, purge)
	local w = Classes.Use(H.world())
	w.class, w.className = class, class
	local ns = w:loadAddon()
	if purge ~= nil then ns.RegisterClass(class, { purge = purge }) end
	return w, ns
end

-- The sound a class alert's picker turns on.
local function Default(ns, setting)
	for _, a in ipairs(ns.CLASS_ALERT_SOUNDS) do
		if a.setting == setting then return a.sound end
	end
end

H.test("the 8 new voices are in the list, in name order", function()
	local _, ns = World("PRIEST")
	local keys, at = ns.SoundKeys(), {}
	for i, key in ipairs(keys) do at[key] = i end
	for _, name in ipairs(NEW) do
		H.ok(ns.IsSoundKey("voice" .. name), name)
	end
	local last
	for _, key in ipairs(keys) do
		if key:match("^voice") then
			if last then H.ok(last:lower() < key:lower(), last .. " before " .. key) end
			last = key
		end
	end
	H.eq(#keys, 32, "8 game sounds and 24 voices")
end)

H.test("each new voice has a menu name", function()
	local _, ns = World("PRIEST")
	H.eq(ns.TEXT[0]["sound.voiceMagic"], "Voice: Magic")
	H.eq(ns.TEXT[0]["sound.voiceFadingSoon"], "Voice: Fading soon")
	for _, name in ipairs(NEW) do
		H.ok(type(ns.TEXT[0]["sound.voice" .. name]) == "string", name)
	end
end)

H.test("each new voice has its 4 files, all public", function()
	-- The list is private, so the public copy has none: check it only here.
	local f = io.open("tools/public-files.txt", "r")
	local listed
	if f then
		listed = {}
		for line in f:lines() do listed[line:gsub("\r$", "")] = true end
		f:close()
	end
	for _, name in ipairs(NEW) do
		for _, tail in ipairs({ "", "_25", "_50", "_75" }) do
			local path = ("Media/Sounds/%s%s.ogg"):format(name, tail)
			local ogg = io.open(path, "rb")
			H.ok(ogg ~= nil, path .. " is there")
			if ogg then
				H.eq(ogg:read(4), "OggS", path .. " is an Ogg file")
				ogg:close()
			end
			if listed then H.ok(listed[path], path .. " is public") end
		end
	end
end)

H.test("a new voice plays its file at each volume", function()
	local _, ns = World("PRIEST")
	H.eq(ns.SoundFile({ key = "voiceFadingSoon", volume = 100 }), DIR .. "FadingSoon.ogg")
	H.eq(ns.SoundFile({ key = "voiceEnrage", volume = 25 }), DIR .. "Enrage_25.ogg")
	H.eq(ns.SoundFile({ key = "voiceReady", volume = 75 }), DIR .. "Ready_75.ogg")
end)

H.test("the dispel sounds start on their own voices", function()
	local _, ns = World("PRIEST")
	H.eq(Default(ns, "soundMagic"), "voiceMagic")
	H.eq(Default(ns, "soundCurse"), "voiceCurse")
	H.eq(Default(ns, "soundDisease"), "voiceDisease")
	H.eq(Default(ns, "soundPoison"), "voicePoison", "unchanged")
	H.eq(Default(ns, "soundInterrupt"), "voiceKick", "unchanged")
	-- true is "the alert's own sound": it follows the new one.
	ns.SetClassAlertSound("soundMagic", true)
	H.eq(ns.SoundChoice(ns.GetClassAlertSound("soundMagic"), Default(ns, "soundMagic")).key, "voiceMagic")
	-- A picked sound keeps its key.
	ns.SetClassAlertSound("soundDisease", ns.NewSoundChoice("voiceWarning", 50))
	H.eq(ns.SoundChoice(ns.GetClassAlertSound("soundDisease"), Default(ns, "soundDisease")).key, "voiceWarning")
end)

H.test("the purge sound: Enrage for an enrage-only purge, Purge for the rest", function()
	local _, ns = World("HUNTER", { spell = "Tranquilizing Shot", enrage = true })
	H.eq(Default(ns, "soundPurge"), "voiceEnrage", "a Hunter")
	ns.RegisterClass("HUNTER", { purge = "Tranquilizing Shot" })
	H.eq(Default(ns, "soundPurge"), "voicePurge", "a magic purge")
	ns.RegisterClass("HUNTER", { purge = { spell = "Tranquilizing Shot", stealable = true, enrage = true } })
	H.eq(Default(ns, "soundPurge"), "voicePurge", "stealable wins, as PurgeRule reads it")
	local _, ns2 = World("MAGE", { spell = "Spellsteal", stealable = true })
	H.eq(Default(ns2, "soundPurge"), "voicePurge", "a Mage")
	local _, ns3 = World("WARRIOR")
	H.eq(Default(ns3, "soundPurge"), "voicePurge", "no purge")
end)
