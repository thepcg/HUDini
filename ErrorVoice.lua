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
