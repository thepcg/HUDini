--[[--------------------------------------------------------------------------
	HUDini - Quiet error voice (TICK-0133, D-028; one box per line TICK-0247)

	Opt-in, each line off at the start. Seven voice lines, each with its own
	setting: your character no longer says it. The red error text stays, and
	so does every other sound.

	  muteVoiceCooldown  "still recharging": spell 12, ability 50, item 5
	  muteVoiceNotYet    "I can't do that yet": potion 47
	  muteVoiceRange     "too far away": 10, 46, 57, 67
	  muteVoiceMana      "not enough mana": 15
	  muteVoiceRage      "not enough rage": 63
	  muteVoiceEnergy    "not enough energy": 64
	  muteVoiceAttack    "can't attack that": 11 (an invalid attack target)

	The numbers are the game's vocal error numbers (VocalUISounds.
	VocalUIEnum). Until TICK-0247 one box (muteErrorVoice) muted the first
	three rows; Core.lua's migration step 1 turns its saved "on" into those
	three. "I can't do that yet" is the potion line: its error text is "You
	can't do that yet." and it is the one cooldown number with one take per
	voice. Not proven by ear: DK's play tells (TICK-0247 Notes).

	How the game plays them (wow-ui-source, forever 9dc84f0): the error frame
	takes UI_ERROR_MESSAGE, shows the red text, and asks GetGameMessageInfo
	for the error's voice; with one it calls C_Sound.PlayVocalErrorSound
	(Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:146-156). The game
	then plays one sound file for your race and sex. The game's own switch,
	the Sound_EnableErrorSpeech setting (Error Speech, under Dialog; Blizzard_
	SettingsDefinitions_Shared/Audio.lua:596), silences every error line at
	once. So HUDini changes no game setting: it mutes only the files below,
	with MuteSoundFile, and unmutes them when you turn a line off. A mute is
	never saved, so nothing is left behind once the game closes.

	The files come from the Forever client's own tables, build 1.60.1.71037
	(wowf; wago.tools/db2, VocalUISounds and SoundKitEntry). The game plays a
	vocal error by its number, your race and your sex: a row of VocalUISounds
	gives a sound kit for each sex, and SoundKitEntry gives the kit's files.
	All their files, for every race the table has: the 8 first races and the
	skyborne elves (race 95 and 96 share one voice); goblins (race 9) have no
	voice rows. 392 files, each in one list only. Night elves also play 3
	undead male "too far away" files (the game's own data); those sit once,
	under undead male. The file names (community list) match each list: no
	file of one line is in another. A new race or a new client build can
	bring new files: read the two tables again for that build.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- One list of file IDs per line, by race and sex.
local FILES = {
	cooldown = {
		540543, 540550, 540552, 540557, 540568, 540583, 540584, 540595, 540596, -- human female (race 1)
		540742, 540746, 540780, 540785, 540786, 540787, 540793, 540799, 540802, -- human male (race 1)
		541164, 541173, 541189, 541195, 541202, 541205, 541206, 541207, 541223, -- orc female (race 2)
		541242, 541255, 541262, 541270, 541297, 541299, 541300, -- orc male (race 2)
		539811, 539820, 539822, 539824, 539828, 539838, 539845, 539855, 539865, -- dwarf female (race 3)
		539914, 539917, 539923, 539927, 539936, 539942, 539945, 539946, 539948, -- dwarf male (race 3)
		540882, 540886, 540895, 540902, 540904, 540905, 540937, 540940, 540943, -- night elf female (race 4)
		540962, 540965, 540974, 540988, 540992, 540994, 541004, 541005, 541007, -- night elf male (race 4)
		542531, 542541, 542544, 542548, 542563, 542564, 542565, 542574, 542578, -- undead female (race 5)
		542621, 542622, 542626, 542630, 542634, 542638, 542642, 542661, 542670, -- undead male (race 5)
		542833, 542841, 542856, 542869, 542874, 542877, 542879, 542880, 542881, -- tauren female (race 6)
		542918, 542923, 542924, 542930, 542940, 542943, 542954, 542956, 542957, -- tauren male (race 6)
		540297, 540300, 540315, 540318, 540319, 540321, 540332, 540334, 540340, -- gnome female (race 7)
		540345, 540350, 540355, 540373, 540375, 540378, 540382, 540386, 540402, -- gnome male (race 7)
		543107, 543115, 543123, 543127, 543129, 543134, 543137, 543147, 543157, -- troll female (race 8)
		543164, 543166, 543171, 543180, 543181, 543182, 543187, 543199, 543218, -- troll male (race 8)
		7744946, 7744947, 7744962, 7744963, 7744964, 7744977, 7744978, 7744979, -- skyborne elf female (race 95 and 96)
		7744534, 7744535, 7744550, 7744551, 7744552, 7744565, 7744566, 7744567, -- skyborne elf male (race 95 and 96)
	},
	notYet = {
		540599, -- human female (race 1)
		540795, -- human male (race 1)
		541191, -- orc female (race 2)
		541295, -- orc male (race 2)
		539859, -- dwarf female (race 3)
		539922, -- dwarf male (race 3)
		540881, -- night elf female (race 4)
		541013, -- night elf male (race 4)
		542556, -- undead female (race 5)
		542658, -- undead male (race 5)
		542838, -- tauren female (race 6)
		542944, -- tauren male (race 6)
		540335, -- gnome female (race 7)
		540394, -- gnome male (race 7)
		543124, -- troll female (race 8)
		543197, -- troll male (race 8)
		7744973, -- skyborne elf female (race 95 and 96)
		7744561, -- skyborne elf male (race 95 and 96)
	},
	range = {
		540551, 540585, 540604, -- human female (race 1)
		540759, 540767, 540781, -- human male (race 1)
		541161, 541183, 541194, -- orc female (race 2)
		541256, 541279, 541289, -- orc male (race 2)
		539818, 539827, 539829, -- dwarf female (race 3)
		539893, 539904, 539915, -- dwarf male (race 3)
		540916, 540919, 540928, -- night elf female (race 4)
		540983, 540997, 541017, -- night elf male (race 4)
		542537, 542553, 542577, -- undead female (race 5)
		542644, 542653, 542655, -- undead male (race 5)
		542831, 542840, 542858, -- tauren female (race 6)
		542926, 542935, 542965, -- tauren male (race 6)
		540289, 540328, 540341, -- gnome female (race 7)
		540383, 540385, 540391, -- gnome male (race 7)
		543139, 543142, 543151, -- troll female (race 8)
		543188, 543222, 543223, -- troll male (race 8)
		7744971, 7744980, 7744981, -- skyborne elf female (race 95 and 96)
		7744559, 7744568, 7744569, -- skyborne elf male (race 95 and 96)
	},
	mana = {
		540561, 540576, 540588, -- human female (race 1)
		540776, 540801, 540803, -- human male (race 1)
		541193, 541197, 541212, -- orc female (race 2)
		541247, 541260, 541294, -- orc male (race 2)
		539819, 539833, 539842, -- dwarf female (race 3)
		539897, 539909, 539951, -- dwarf male (race 3)
		540915, 540917, 540935, -- night elf female (race 4)
		540968, 540970, 541019, -- night elf male (race 4)
		542539, 542558, 542579, -- undead female (race 5)
		542637, 542646, 542665, -- undead male (race 5)
		542830, 542848, 542886, -- tauren female (race 6)
		542905, 542916, 542948, -- tauren male (race 6)
		540283, 540310, 540311, -- gnome female (race 7)
		540366, 540369, 540371, -- gnome male (race 7)
		543111, 543113, 543140, -- troll female (race 8)
		543208, 543216, 543217, -- troll male (race 8)
		7744968, 7744969, 7744970, -- skyborne elf female (race 95 and 96)
		7744556, 7744557, 7744558, -- skyborne elf male (race 95 and 96)
	},
	rage = {
		540566, 540573, -- human female (race 1)
		540760, 540797, -- human male (race 1)
		541180, 541184, -- orc female (race 2)
		541244, 541291, -- orc male (race 2)
		539837, 539862, -- dwarf female (race 3)
		539889, 539892, -- dwarf male (race 3)
		540885, 540912, -- night elf female (race 4)
		540998, 541000, -- night elf male (race 4)
		542547, 542589, -- undead female (race 5)
		542611, 542654, -- undead male (race 5)
		542859, 542860, -- tauren female (race 6)
		542913, 542945, -- tauren male (race 6)
		540281, 540337, -- gnome female (race 7)
		540359, 540363, -- gnome male (race 7)
		543104, 543116, -- troll female (race 8)
		543195, 543220, -- troll male (race 8)
		7744958, 7744959, -- skyborne elf female (race 95 and 96)
		7744546, 7744547, -- skyborne elf male (race 95 and 96)
	},
	energy = {
		540555, 540602, -- human female (race 1)
		540789, 540794, -- human male (race 1)
		541166, 541186, -- orc female (race 2)
		541287, 541292, -- orc male (race 2)
		539813, 539825, -- dwarf female (race 3)
		539931, 539944, -- dwarf male (race 3)
		540921, 540923, -- night elf female (race 4)
		540959, 540976, -- night elf male (race 4)
		542566, 542583, -- undead female (race 5)
		542645, 542672, -- undead male (race 5)
		542845, 542846, -- tauren female (race 6)
		542908, 542920, -- tauren male (race 6)
		540301, 540336, -- gnome female (race 7)
		540388, 540390, -- gnome male (race 7)
		543128, 543148, -- troll female (race 8)
		543175, 543203, -- troll male (race 8)
		7744966, 7744967, -- skyborne elf female (race 95 and 96)
		7744554, 7744555, -- skyborne elf male (race 95 and 96)
	},
	attack = {
		540546, 540547, -- human female (race 1)
		540748, 540763, -- human male (race 1)
		541165, 541178, -- orc female (race 2)
		541301, 541304, -- orc male (race 2)
		539835, 539861, -- dwarf female (race 3)
		539895, 539941, -- dwarf male (race 3)
		540888, 540903, -- night elf female (race 4)
		540973, 540980, -- night elf male (race 4)
		542572, 542575, -- undead female (race 5)
		542614, 542662, -- undead male (race 5)
		542865, 542884, -- tauren female (race 6)
		542904, 542947, -- tauren male (race 6)
		540280, 540303, -- gnome female (race 7)
		540384, 540387, -- gnome male (race 7)
		543149, 543152, -- troll female (race 8)
		543173, 543184, -- troll male (race 8)
		7744944, 7744945, -- skyborne elf female (race 95 and 96)
		7744532, 7744533, -- skyborne elf male (race 95 and 96)
	},
}

-- The seven lines, in the order the options show them: the saved key, the
-- list, and the name in /hud debug modules. The rows TICK-0248 adds are
-- plain checkboxes on these keys: a change goes through HUDini:Apply, which
-- mutes or unmutes that one line at once.
-- locale: skip the label is a debug name (/hud debug modules)
local LINES = {
	{ key = "muteVoiceCooldown", files = FILES.cooldown, label = "still recharging" },
	{ key = "muteVoiceRange",    files = FILES.range,    label = "too far away" },
	{ key = "muteVoiceMana",     files = FILES.mana,     label = "not enough mana" },
	{ key = "muteVoiceRage",     files = FILES.rage,     label = "not enough rage" },
	{ key = "muteVoiceEnergy",   files = FILES.energy,   label = "not enough energy" },
	{ key = "muteVoiceAttack",   files = FILES.attack,   label = "can't attack that" },
	{ key = "muteVoiceNotYet",   files = FILES.notYet,   label = "I can't do that yet" },
}
-- locale: end
ns.ERROR_VOICE_FILES, ns.ERROR_VOICE_LINES = FILES, LINES -- for the test harness and Options.lua

-- Your race and sex as the game gives them, for the first line's report,
-- so a report shows whose voice files are in play.
-- locale: skip a debug report (/hud debug modules), in English
local function WhoYouAre()
	local unitRace, unitSex = _G.UnitRace, _G.UnitSex
	local race, raceID, sex
	if unitRace then
		local _, file, id = unitRace("player")
		race, raceID = ns.Plain(file), ns.Plain(id)
	end
	if unitSex then sex = ns.Plain(unitSex("player")) end
	return ("you: %s, race %s, sex %s (2 male, 3 female)"):format(
		tostring(race), tostring(raceID), tostring(sex))
end
-- locale: end

-- One module per line (D-002): on while its key is on. A module mutes and
-- unmutes only its own files, so one line goes on or off alone.
for i, line in ipairs(LINES) do
	local M = ns.NewModule("errorVoice." .. line.key, {
		label    = "Quiet error voice: " .. line.label, -- locale: skip a debug name (/hud debug modules)
		setting  = line.key,
		defaults = { [line.key] = false },
	})

	-- How many files the last turn-on muted: 0 when off, nil when the
	-- client has no MuteSoundFile. /hud debug modules prints it.
	local mutedCount = 0

	local function SetMuted(on)
		local fn
		if on then fn = MuteSoundFile else fn = UnmuteSoundFile end
		if not fn then
			mutedCount = nil
			return
		end
		for _, id in ipairs(line.files) do fn(id) end
		mutedCount = on and #line.files or 0
	end

	-- locale: skip a debug report (/hud debug modules), in English
	function M.Report()
		local muted
		if mutedCount then
			muted = ("%d of %d files muted"):format(mutedCount, #line.files)
		else
			muted = "no MuteSoundFile on this client"
		end
		if i == 1 then return muted .. "; " .. WhoYouAre() end
		return muted
	end
	-- locale: end

	function M:OnEnable() SetMuted(true) end
	function M:OnDisable() SetMuted(false) end
end

--[[--------------------------------------------------------------------------
	Chat date and time stamps (TICK-0154, D-038; shapes TICK-0155, D-039)

	Opt-in, off at the start. With it on, each new line in the game's chat
	windows starts with the realm date and time, in one of three shapes
	(setting chatStampShape), all 24-hour, two digits each:
	  long (the default)  "26-11-14@09:25:04 | "
	  short               "[09:25] "
	  dated               "11/14/26 [09:25] "   (month/day/year)
	It sits in this file so a /reload deploys it (no new .toc file); it is a
	module of its own.

	How (wow-ui-source, forever 1.60.1.70938): a chat window's AddMessage
	puts the line in its history (ChatFrameMixin:AddMessage, Shared/
	ChatFrame.lua:35). HUDini hooks AddMessage after the fact
	(hooksecurefunc: the game's code runs on untainted) and then rewrites
	that newest line through TransformMessages, which the game gives addons
	for this: it is a secure elevation barrier (ScrollingMessageFrame.lua:
	797-824). HUDini never sets a game global or a game setting.
	- A secret line is left as it is: HUDini never joins or compares it.
	- The game's own Chat Timestamps (Settings "showTimestamps") put their
	  stamp first on player chat; HUDini takes that stamp off the line it
	  stamps, so a line shows one stamp. A secret line keeps the game's.
	- Realm time: GetServerTime() is UTC, with seconds; the calendar
	  (C_DateAndTime.GetCurrentCalendarTime) gives the realm's date, hour and
	  minute. Their difference, to the nearest 15 minutes, is the realm's
	  time zone. No calendar from the game: no stamp, never the PC clock.
	- Not the combat log window (COMBATLOG): it has its own timestamp
	  option, and its lines come fast.
	- The feed is no chat window, so it gets no stamp.
	- A line the game copies into a whisper window or a popped-out tab keeps
	  its own stamp, or its lack of one; a line that has HUDini's stamp at
	  the start, in any of the three shapes, never gets a second.
	- Lines from before the setting went on keep no stamp; lines stamped
	  stay stamped when it goes off. A hook cannot be taken out, so off
	  makes it do nothing.
----------------------------------------------------------------------------]]

local CS = ns.NewModule("chatStamps", {
	label    = "Chat date and time stamps", -- locale: skip a debug name (/hud debug modules)
	setting  = "chatStamps",
	defaults = { chatStamps = false, chatStampShape = "long" },
})

local floor = math.floor

-- Days since 1970-01-01 for a date, and back (H. Hinnant's civil
-- algorithms): plain sums, so no PC time zone gets in.
local function DaysFromCivil(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = floor(y / 400)
	local yoe = y - era * 400
	local doy = floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

local function CivilFromDays(z)
	z = z + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	local y = yoe + era * 400
	if m <= 2 then y = y + 1 end
	return y, m, d
end

-- The realm's time zone: realm time minus UTC, in seconds. Read again each
-- minute, so a change of summer time follows.
local zone, zoneAt

local function ReadZone(now)
	local C = _G.C_DateAndTime
	local ok, t = pcall(function() return C.GetCurrentCalendarTime() end)
	if not ok or type(t) ~= "table" or ns.IsSecret(t) then return nil end
	local y, m, d = ns.Plain(t.year), ns.Plain(t.month), ns.Plain(t.monthDay)
	local h, mi = ns.Plain(t.hour), ns.Plain(t.minute)
	local parts = { y, m, d, h, mi }
	for i = 1, 5 do
		if type(parts[i]) ~= "number" then return nil end
	end
	-- A calendar that is not ready yet (at login: month 0, day 0) gives no
	-- zone, not a wrong date for a minute.
	if m < 1 or m > 12 or d < 1 or d > 31 or h < 0 or h > 23 or mi < 0 or mi > 59 then return nil end
	local realm = DaysFromCivil(y, m, d) * 86400 + h * 3600 + mi * 60
	local z = floor((realm - now + 450) / 900) * 900
	if z < -14 * 3600 or z > 14 * 3600 then return nil end -- no time zone is that far
	return z
end

-- Realm time now, in seconds since 1970 as if the realm were UTC; nil when
-- the game does not say.
local function RealmNow()
	local get = _G.GetServerTime
	local now = get and ns.Plain(get())
	if type(now) ~= "number" then return nil end
	if not zone or now - zoneAt >= 60 or now < zoneAt then
		local z = ReadZone(now)
		if z then zone, zoneAt = z, now end
	end
	return zone and now + zone
end

-- The three shapes (D-039): how to write one for a date and time, and a
-- Lua pattern for a line that starts with one. In game text "|" starts a
-- code; "||" shows one "|", so the long shape is stored with "||".
local SHAPES = {
	long = {
		make = function(y, m, d, h, mi, s) return ("%02d-%02d-%02d@%02d:%02d:%02d || "):format(y, m, d, h, mi, s) end,
		find = "^%d%d%-%d%d%-%d%d@%d%d:%d%d:%d%d || ",
	},
	short = {
		make = function(_, _, _, h, mi) return ("[%02d:%02d] "):format(h, mi) end,
		find = "^%[%d%d:%d%d%] ",
	},
	dated = {
		make = function(y, m, d, h, mi) return ("%02d/%02d/%02d [%02d:%02d] "):format(m, d, y, h, mi) end,
		find = "^%d%d/%d%d/%d%d %[%d%d:%d%d%] ",
	},
}

-- The stamp for t (seconds as RealmNow gives them) in a shape; an unknown
-- shape is the long one.
local function Stamp(t, shape)
	local y, m, d = CivilFromDays(floor(t / 86400))
	local s = t % 86400
	return (SHAPES[shape] or SHAPES.long).make(y % 100, m, d, floor(s / 3600), floor(s % 3600 / 60), s % 60)
end

-- True when the line starts with a HUDini stamp, in any shape: whatever
-- the shape was when it was stamped, it gets no second.
local function HasOurStamp(text)
	for _, shape in pairs(SHAPES) do
		if text:find(shape.find) then return true end
	end
	return false
end
CS.Stamp, CS.RealmNow = Stamp, RealmNow -- for the test harness

-- A Lua pattern for the start of a line that the game's own timestamp
-- format makes, or nil (that option off, or a code HUDini does not know).
local CODES = {
	H = "%d%d?", I = "%d%d?", M = "%d%d", S = "%d%d", p = "[%a%.]+",
	y = "%d%d", Y = "%d%d%d%d", m = "%d%d?", d = "%d%d?",
}
local patternFor, pattern

local function Pattern(fmt)
	local out, i = { "^" }, 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local p = CODES[fmt:sub(i + 1, i + 1)]
			if not p then return nil end
			out[#out + 1] = p
			i = i + 2
		else
			out[#out + 1] = c:find("%W") and "%" .. c or c
			i = i + 1
		end
	end
	return table.concat(out)
end

local function GameStampPattern()
	local U = _G.ChatFrameUtil
	local ok, fmt = pcall(function() return U.GetTimestampFormat() end)
	fmt = ok and ns.Plain(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	if fmt ~= patternFor then patternFor, pattern = fmt, Pattern(fmt) end
	return pattern
end
CS.GameStampPattern = GameStampPattern -- for the test harness

-- Windows the game is filling with copies of old lines. When it opens a
-- whisper window or pops a chat tab out, it clears the window and then
-- calls AddMessage for each old line it copies (FloatingChatFrame.lua:
-- 919-936, ChatFrameUtil.lua:740-795). A copy is not a new line: it keeps
-- its stamp, or its lack of one. The flag ends when that game function
-- returns, or at the next screen frame at the latest.
local copying = {}

local function OnClear(frame)
	copying[frame] = true
	local T = _G.C_Timer
	if T and T.After then T.After(0, function() copying[frame] = nil end) end
end

local function CopiesDone()
	for frame in pairs(copying) do copying[frame] = nil end
end

-- After a chat window's AddMessage: stamp the line it just added.
local function OnAddMessage(frame, message)
	if not CS.enabled or ns.IsSecret(message) or type(message) ~= "string" then return end
	if frame == _G.COMBATLOG or copying[frame] then return end
	-- A line with HUDini's stamp is not stamped again. The game's own stamp
	-- comes first: the game's options have no brackets, but a stamp format
	-- set by hand (/console showTimestamps, another addon) can look like the
	-- short shape. A line that starts with the game's stamp is a new line,
	-- whose game stamp the transform takes off, so it still shows one stamp.
	local game = GameStampPattern()
	if not (game and message:find(game)) and HasOurStamp(message) then return end
	-- The newest line's place in the history, so an older line with the same
	-- text is left alone. A client that hides it: no stamp.
	local ok, newest = pcall(function() return frame.historyBuffer:CalculateElementIndex(1) end)
	if not ok or type(newest) ~= "number" then return end
	local now = RealmNow()
	if not now then return end
	local stamp = Stamp(now, HUDiniDB.chatStampShape)
	local seen, done = 0, false
	frame:TransformMessages(function(text)
		seen = seen + 1
		if done or seen ~= newest then return false end
		if ns.IsSecret(text) or text ~= message then return false end
		done = true
		return true
	end, function(text, ...)
		if game then text = text:gsub(game, "", 1) end
		return stamp .. text, ...
	end)
end

local hooked = {}

local function Hook(frame)
	if type(frame) ~= "table" or hooked[frame] then return end
	if type(frame.AddMessage) ~= "function" or type(frame.TransformMessages) ~= "function" then return end
	hooked[frame] = true
	hooksecurefunc(frame, "AddMessage", OnAddMessage)
	if type(frame.Clear) == "function" then hooksecurefunc(frame, "Clear", OnClear) end -- locale: skip a method name
end

-- Every chat window the game has made: the docked and floating ones, and
-- the whisper windows it opens later (CHAT_FRAMES lists them all by name).
local function HookAll()
	local names = _G.CHAT_FRAMES
	if type(names) == "table" then
		for _, name in pairs(names) do Hook(_G[name]) end
	end
	for i = 1, tonumber(_G.NUM_CHAT_WINDOWS) or 10 do Hook(_G["ChatFrame" .. i]) end
end

local watching = false

function CS:OnEnable()
	HookAll()
	if not watching and type(_G.FCF_OpenTemporaryWindow) == "function" then
		watching = true
		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			CopiesDone()
			if CS.enabled then HookAll() end
		end)
		local U = _G.ChatFrameUtil
		if type(U) == "table" and type(U.PopOutChat) == "function" then
			hooksecurefunc(U, "PopOutChat", CopiesDone)
		end
	end
end
