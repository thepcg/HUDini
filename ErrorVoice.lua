--[[--------------------------------------------------------------------------
	HUDini - Quiet error voice (TICK-0133, D-028)

	Opt-in, off at the start. With it on, your character no longer says that
	a spell or item is still on cooldown ("That's still recharging") or that
	the target is out of range ("That's too far away"). The red error text
	stays, and so does every other sound.

	How the game plays them (wow-ui-source, forever 9dc84f0): the error frame
	takes UI_ERROR_MESSAGE, shows the red text, and asks GetGameMessageInfo
	for the error's voice; with one it calls C_Sound.PlayVocalErrorSound
	(Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:146-156). The game
	then plays one sound file for your race and sex. The game's own switch,
	the Sound_EnableErrorSpeech setting (Error Speech, under Dialog; Blizzard_
	SettingsDefinitions_Shared/Audio.lua:596), silences every error line,
	"Not enough mana" too. So HUDini changes no game setting: it mutes only
	the files below, with MuteSoundFile, and unmutes them when you turn it
	off. A mute is never saved, so nothing is left behind once the game
	closes.

	The files come from the Forever client's own tables, build 1.60.1.70862
	(wowf; wago.tools/db2, VocalUISounds and SoundKitEntry). The
	game plays a vocal error by its number, your race and your sex: a row of
	VocalUISounds gives a sound kit for each sex, and SoundKitEntry gives the
	kit's files. The numbers muted here: 12 spell, 50 ability, 5 item and 47
	potion on cooldown; 10, 46, 57 and 67 out of range. All their files, for
	every race the table has: the 8 first races and the skyborne elves (race
	95 and 96 share one voice); goblins (race 9) have no rows for these. 230
	files. Night elves also play 3 undead male lines for number 67 (the
	game's own data); those sit once, under undead male. TICK-0133 first took
	the IDs from the community file list by the name *_err_<error>NN.ogg; the
	skyborne elves' files have other names (*_spellcooling_*), so the match
	missed them and their voice still talked. A new race or a new client build
	can bring new files: read the two tables again for that build.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local FILES = {
	540543, 540550, 540551, 540552, 540557, 540568, 540583, 540584, 540585, 540595, 540596, 540599, 540604, -- human female (race 1)
	540742, 540746, 540759, 540767, 540780, 540781, 540785, 540786, 540787, 540793, 540795, 540799, 540802, -- human male (race 1)
	541161, 541164, 541173, 541183, 541189, 541191, 541194, 541195, 541202, 541205, 541206, 541207, 541223, -- orc female (race 2)
	541242, 541255, 541256, 541262, 541270, 541279, 541289, 541295, 541297, 541299, 541300, -- orc male (race 2)
	539811, 539818, 539820, 539822, 539824, 539827, 539828, 539829, 539838, 539845, 539855, 539859, 539865, -- dwarf female (race 3)
	539893, 539904, 539914, 539915, 539917, 539922, 539923, 539927, 539936, 539942, 539945, 539946, 539948, -- dwarf male (race 3)
	540881, 540882, 540886, 540895, 540902, 540904, 540905, 540916, 540919, 540928, 540937, 540940, 540943, -- night elf female (race 4)
	540962, 540965, 540974, 540983, 540988, 540992, 540994, 540997, 541004, 541005, 541007, 541013, 541017, -- night elf male (race 4)
	542531, 542537, 542541, 542544, 542548, 542553, 542556, 542563, 542564, 542565, 542574, 542577, 542578, -- undead female (race 5)
	542621, 542622, 542626, 542630, 542634, 542638, 542642, 542644, 542653, 542655, 542658, 542661, 542670, -- undead male (race 5)
	542831, 542833, 542838, 542840, 542841, 542856, 542858, 542869, 542874, 542877, 542879, 542880, 542881, -- tauren female (race 6)
	542918, 542923, 542924, 542926, 542930, 542935, 542940, 542943, 542944, 542954, 542956, 542957, 542965, -- tauren male (race 6)
	540289, 540297, 540300, 540315, 540318, 540319, 540321, 540328, 540332, 540334, 540335, 540340, 540341, -- gnome female (race 7)
	540345, 540350, 540355, 540373, 540375, 540378, 540382, 540383, 540385, 540386, 540391, 540394, 540402, -- gnome male (race 7)
	543107, 543115, 543123, 543124, 543127, 543129, 543134, 543137, 543139, 543142, 543147, 543151, 543157, -- troll female (race 8)
	543164, 543166, 543171, 543180, 543181, 543182, 543187, 543188, 543197, 543199, 543218, 543222, 543223, -- troll male (race 8)
	7744946, 7744947, 7744962, 7744963, 7744964, 7744971, 7744973, 7744977, 7744978, 7744979, 7744980, 7744981, -- skyborne elf female (race 95 and 96)
	7744534, 7744535, 7744550, 7744551, 7744552, 7744559, 7744561, 7744565, 7744566, 7744567, 7744568, 7744569, -- skyborne elf male (race 95 and 96)
}
ns.ERROR_VOICE_FILES = FILES -- for the test harness

local M = ns.NewModule("errorVoice", {
	label    = "Quiet error voice", -- locale: skip a debug name (/hud debug modules)
	setting  = "muteErrorVoice",
	defaults = { muteErrorVoice = false },
})

-- How many files the last turn-on muted: 0 when off, nil when the client
-- has no MuteSoundFile. /hud debug modules prints it.
local mutedCount = 0

local function SetMuted(on)
	local fn
	if on then fn = MuteSoundFile else fn = UnmuteSoundFile end
	if not fn then
		mutedCount = nil
		return
	end
	for _, id in ipairs(FILES) do fn(id) end
	mutedCount = on and #FILES or 0
end

-- One line for /hud debug modules: the count, and your race and sex as the
-- game gives them, so a report shows whose voice files are in play.
-- locale: skip a debug report (/hud debug modules), in English
function M.Report()
	local unitRace, unitSex = _G.UnitRace, _G.UnitSex
	local race, raceID, sex
	if unitRace then
		local _, file, id = unitRace("player")
		race, raceID = ns.Plain(file), ns.Plain(id)
	end
	if unitSex then sex = ns.Plain(unitSex("player")) end
	local muted
	if mutedCount then
		muted = ("%d of %d files muted"):format(mutedCount, #FILES)
	else
		muted = "no MuteSoundFile on this client"
	end
	return ("%s; you: %s, race %s, sex %s (2 male, 3 female)"):format(
		muted, tostring(race), tostring(raceID), tostring(sex))
end
-- locale: end

function M:OnEnable() SetMuted(true) end
function M:OnDisable() SetMuted(false) end

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
