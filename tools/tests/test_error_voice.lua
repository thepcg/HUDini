-- Quiet error voice (TICK-0133, D-028; one box per line TICK-0247): each of
-- seven voice lines has its own setting. On, that line's files are muted one
-- by one; off unmutes them. No game setting changes, so nothing is left to
-- put back. An old muteErrorVoice moves to the lines it muted (Core.lua
-- migration step 1).

-- A world that records each mute, and fails on any game setting change.
local function World(saved)
	local w = H.world()
	w.muted, w.mutes, w.unmutes = {}, 0, 0
	w.env.MuteSoundFile = function(id) w.muted[id] = true; w.mutes = w.mutes + 1 end
	w.env.UnmuteSoundFile = function(id) w.muted[id] = nil; w.unmutes = w.unmutes + 1 end
	w.env.SetCVar = function(name) error("a game setting changed: " .. tostring(name)) end
	w.env.HUDiniDB = saved
	w:loadAddon()
	return w, w.ns, w.env.HUDiniDB
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

-- The seven keys, and how many files each line has (build 1.60.1.71037).
local SIZES = {
	muteVoiceCooldown = 158, muteVoiceRange = 54, muteVoiceMana = 54, muteVoiceRage = 36,
	muteVoiceEnergy = 36, muteVoiceAttack = 36, muteVoiceNotYet = 18,
}

local function Line(ns, key)
	for _, line in ipairs(ns.ERROR_VOICE_LINES) do
		if line.key == key then return line end
	end
end

-- True when exactly the files of the lines whose keys are in on are muted.
local function MutedAre(w, ns, on, what)
	local want = {}
	for key in pairs(on) do
		for _, id in ipairs(Line(ns, key).files) do want[id] = true end
	end
	H.eq(Count(w.muted), Count(want), what .. ": how many files are muted")
	for id in pairs(want) do H.eq(w.muted[id], true, what .. ": file " .. id .. " muted") end
end

H.test("off at the start: each line is off, no voice file is muted", function()
	local w, _, db = World()
	for key in pairs(SIZES) do H.eq(db[key], false, key .. " starts off") end
	H.eq(db.muteErrorVoice, nil, "the old key is gone")
	H.eq(w.mutes, 0, "nothing muted")
end)

-- The lists (TICK-0247): the Forever client's own tables, build
-- 1.60.1.71037. 392 files for the 8 first races and the skyborne elves.
H.test("the seven lists: their sizes, 392 different file IDs, none in two lists", function()
	local _, ns = World()
	H.eq(#ns.ERROR_VOICE_LINES, 7, "seven lines")
	local seen, total = {}, 0
	for _, line in ipairs(ns.ERROR_VOICE_LINES) do
		H.eq(#line.files, SIZES[line.key], line.key .. ": its files")
		for _, id in ipairs(line.files) do
			H.eq(type(id), "number", "an ID is a number")
			H.eq(seen[id], nil, "file " .. id .. " (" .. line.key .. ") is in one list only")
			seen[id] = line.key
			total = total + 1
		end
	end
	H.eq(total, 392, "every file the client plays for these lines")
	-- The old box's 230 files are the three lines it muted.
	H.eq(SIZES.muteVoiceCooldown + SIZES.muteVoiceRange + SIZES.muteVoiceNotYet, 230, "the old list")
	H.eq(seen[540780], "muteVoiceCooldown", "a human male spell cooldown line")
	H.eq(seen[540795], "muteVoiceNotYet", "the human male potion line")
	H.eq(seen[540759], "muteVoiceRange", "a human male out of range line")
	H.eq(seen[540776], "muteVoiceMana", "a human male mana line")
	H.eq(seen[540760], "muteVoiceRage", "a human male rage line")
	H.eq(seen[540789], "muteVoiceEnergy", "a human male energy line")
	H.eq(seen[540748], "muteVoiceAttack", "a human male attack line")
end)

H.test("each line alone: on mutes only its files; off unmutes only its files", function()
	for key in pairs(SIZES) do
		local w, ns, db = World()
		db[key] = true
		ns.HUDini:Apply()
		MutedAre(w, ns, { [key] = true }, key .. " on")
		db[key] = false
		ns.HUDini:Apply()
		H.eq(Count(w.muted), 0, key .. " off: each file unmuted")
		H.eq(w.unmutes, SIZES[key], key .. " off: one unmute for each of its files")
	end
end)

H.test("one line off leaves the others muted", function()
	local w, ns, db = World()
	db.muteVoiceRage, db.muteVoiceRange = true, true
	ns.HUDini:Apply()
	MutedAre(w, ns, { muteVoiceRage = true, muteVoiceRange = true }, "rage and range on")
	db.muteVoiceRange = false
	ns.HUDini:Apply()
	MutedAre(w, ns, { muteVoiceRage = true }, "range off again")
	H.eq(w.unmutes, SIZES.muteVoiceRange, "only the range files unmuted")
end)

H.test("saved on: the line is muted at login", function()
	local w, ns = World({ schema = 4, muteVoiceMana = true })
	MutedAre(w, ns, { muteVoiceMana = true }, "at PLAYER_LOGIN")
end)

H.test("an Apply with no change mutes nothing twice", function()
	local w, ns, db = World()
	db.muteVoiceCooldown = true
	ns.HUDini:Apply()
	local mutes = w.mutes
	ns.HUDini:Apply()
	H.eq(w.mutes, mutes, "no second round")
end)

H.test("a client without MuteSoundFile: turning a line on is no error", function()
	local w = H.world()
	-- false, not nil: nil falls through to the harness stubs. To the code's
	-- guard the two are the same.
	w.env.MuteSoundFile, w.env.UnmuteSoundFile = false, false
	w:loadAddon()
	w.env.HUDiniDB.muteVoiceRage = true
	w.ns.HUDini:Apply()
	w.env.HUDiniDB.muteVoiceRage = false
	w.ns.HUDini:Apply()
	H.ok(true, "no error")
end)

-- The community file list has other names for the skyborne elf files. One
-- file per line here, from the client's tables.
H.test("a skyborne elf's lines are in their lists", function()
	local _, ns = World()
	local lines = {
		muteVoiceCooldown = { 7744977, 7744962, 7744946, 7744565, 7744550, 7744534 },
		muteVoiceNotYet   = { 7744973, 7744561 },
		muteVoiceRange    = { 7744971, 7744559 },
		muteVoiceMana     = { 7744556 },
		muteVoiceRage     = { 7744546 },
		muteVoiceEnergy   = { 7744554 },
		muteVoiceAttack   = { 7744532 },
	}
	for key, ids in pairs(lines) do
		local set = {}
		for _, id in ipairs(Line(ns, key).files) do set[id] = true end
		for _, id in ipairs(ids) do H.eq(set[id], true, key .. ": skyborne file " .. id) end
	end
end)

-- Core.lua migration step 1 (schema 3 to 4).
H.test("migration: the old box on turns on the three lines it muted", function()
	local w, ns, db = World({ muteErrorVoice = true, barHeight = 12 })
	H.eq(db.schema, ns.FIRST_SCHEMA + #ns.migrations, "schema number")
	H.eq(db.muteErrorVoice, nil, "the old key is gone")
	H.eq(db.barHeight, 12, "another setting is kept")
	local on = { muteVoiceCooldown = true, muteVoiceRange = true, muteVoiceNotYet = true }
	for key in pairs(SIZES) do H.eq(db[key], on[key] or false, key) end
	MutedAre(w, ns, on, "at login")
	H.eq(w.muted[540780], true, "still recharging stays muted")
	H.eq(w.muted[540759], true, "too far away stays muted")
	H.eq(w.muted[540760], nil, "not enough rage speaks")
end)

H.test("migration: the old box off, or never saved, leaves all seven off", function()
	for _, saved in ipairs({ { muteErrorVoice = false }, { barHeight = 12 } }) do
		local w, _, db = World(saved)
		H.eq(db.muteErrorVoice, nil, "the old key is gone")
		for key in pairs(SIZES) do H.eq(db[key], false, key) end
		H.eq(w.mutes, 0, "nothing muted")
	end
end)

H.test("migration: a second run and a second login change nothing", function()
	local w, ns, db = World({ muteErrorVoice = true })
	local snapshot = H.copy(db)
	ns.Migrate(db, false)
	H.eq(H.diff(db, snapshot), nil, "ns.Migrate again")
	local _, _, again = World(db)
	H.eq(H.diff(again, snapshot), nil, "a second login")
	H.eq(w.muted[540780], true, "still muted")
end)

H.test("migration: a line saved after the step is not changed by it", function()
	local _, _, db = World({ schema = 4, muteVoiceCooldown = false, muteVoiceRage = true })
	H.eq(db.muteVoiceCooldown, false, "kept off")
	H.eq(db.muteVoiceRage, true, "kept on")
end)

-- /hud debug modules: how many files each line has muted, and whose voice.
-- The report lines of one run of the command, in order.
local function Debug(w)
	local from = #w.printed
	w:slash("/hud debug modules")
	local out = {}
	for i = from + 1, #w.printed do
		local line = w.printed[i]
		if line:find("files muted", 1, true) or line:find("MuteSoundFile", 1, true) then
			out[#out + 1] = line
		end
	end
	return out
end

H.test("/hud debug modules: a count for each line, and your race and sex", function()
	local w, ns, db = World()
	w.env.UnitRace = function() return "Skyborne", "Skyborne", 95 end
	w.env.UnitSex = function() return 3 end
	local lines = Debug(w)
	H.eq(#lines, 7, "one line for each voice line")
	H.ok(lines[1]:find(" 0 of 158 files muted", 1, true), "off: none muted: " .. lines[1])
	H.ok(lines[1]:find("you: Skyborne, race 95, sex 3", 1, true), "race and sex: " .. lines[1])
	db.muteVoiceRage = true
	ns.HUDini:Apply()
	local text = table.concat(Debug(w), "\n")
	H.ok(text:find("36 of 36 files muted", 1, true), "rage on: its files muted: " .. text)
	H.ok(text:find(" 0 of 54 files muted", 1, true), "range off: none muted")
	db.muteVoiceRage = false
	ns.HUDini:Apply()
	H.eq(table.concat(Debug(w), "\n"):find("36 of 36", 1, true), nil, "off again: none muted")
end)

H.test("/hud debug modules: no MuteSoundFile; a secret race or sex is not printed", function()
	local w = H.world()
	w.secret = {}
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.env.MuteSoundFile, w.env.UnmuteSoundFile = false, false
	w.env.UnitRace = function() return "Orc", "Orc", 2 end
	w.env.UnitSex = function() return 2 end
	w:loadAddon()
	w.env.HUDiniDB.muteVoiceCooldown = true
	w.ns.HUDini:Apply()
	local line = Debug(w)[1]
	H.ok(line:find("no MuteSoundFile on this client", 1, true), "says the call is missing")
	H.ok(line:find("you: Orc, race 2, sex 2", 1, true), "plain: printed: " .. line)
	w.secret.Orc, w.secret[2] = true, true
	line = Debug(w)[1]
	H.ok(line:find("you: nil, race nil, sex nil", 1, true), "secret: not printed: " .. line)
end)
