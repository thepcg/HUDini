-- Quiet error voice (TICK-0133, D-028): with it on, the cooldown and
-- out-of-range voice files are muted one by one; off unmutes them. No game
-- setting changes, so nothing is left to put back.

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

H.test("off at the start: no voice file is muted", function()
	local w, _, db = World()
	H.eq(db.muteErrorVoice, false, "the default is off")
	H.eq(w.mutes, 0, "nothing muted")
end)

H.test("turn it on: every voice file is muted; off again: every one comes back", function()
	local w, ns, db = World()
	local files = ns.ERROR_VOICE_FILES
	db.muteErrorVoice = true
	ns.HUDini:Apply()
	H.eq(Count(w.muted), #files, "each file muted")
	for _, id in ipairs(files) do H.eq(w.muted[id], true, "file " .. id .. " muted") end
	db.muteErrorVoice = false
	ns.HUDini:Apply()
	H.eq(Count(w.muted), 0, "each file unmuted")
	H.eq(w.unmutes, #files, "one unmute for each file")
end)

H.test("saved on: the files are muted at login", function()
	local w, ns = World({ muteErrorVoice = true })
	H.eq(Count(w.muted), #ns.ERROR_VOICE_FILES, "muted at PLAYER_LOGIN")
end)

H.test("an Apply with no change mutes nothing twice", function()
	local w, ns, db = World()
	db.muteErrorVoice = true
	ns.HUDini:Apply()
	local mutes = w.mutes
	ns.HUDini:Apply()
	H.eq(w.mutes, mutes, "no second round")
end)

H.test("a client without MuteSoundFile: turning it on is no error", function()
	local w = H.world()
	-- false, not nil: nil falls through to the harness stubs. To the code's
	-- guard the two are the same.
	w.env.MuteSoundFile, w.env.UnmuteSoundFile = false, false
	w:loadAddon()
	w.env.HUDiniDB.muteErrorVoice = true
	w.ns.HUDini:Apply()
	w.env.HUDiniDB.muteErrorVoice = false
	w.ns.HUDini:Apply()
	H.ok(true, "no error")
end)

-- The list (TICK-0133): the Forever client's own tables, build
-- 1.60.1.70862. 230 files for the 8 first races and the skyborne elves.
H.test("the file list: 230 different file IDs", function()
	local _, ns = World()
	local files, seen = ns.ERROR_VOICE_FILES, {}
	H.eq(#files, 230, "the files the client plays for these errors")
	for _, id in ipairs(files) do
		H.eq(type(id), "number", "an ID is a number")
		H.eq(seen[id], nil, "file " .. id .. " is listed once")
		seen[id] = true
	end
end)

-- The community file list has no skyborne elf files. One file per line
-- here, from the client's tables: spell, ability, item and potion on
-- cooldown, and out of range, for each sex.
H.test("a skyborne elf's cooldown and range lines are muted", function()
	local w, ns, db = World()
	db.muteErrorVoice = true
	ns.HUDini:Apply()
	local lines = {
		[7744977] = "female spell", [7744962] = "female ability", [7744946] = "female item",
		[7744973] = "female potion", [7744971] = "female out of range",
		[7744565] = "male spell", [7744550] = "male ability", [7744534] = "male item",
		[7744561] = "male potion", [7744559] = "male out of range",
	}
	for id, what in pairs(lines) do H.eq(w.muted[id], true, what .. " (" .. id .. ") muted") end
	H.eq(w.muted[540780], true, "a human male spell line still muted")
end)

-- /hud debug modules: how many files are muted, and whose voice it is.
local function DebugLine(w)
	for i = #w.printed, 1, -1 do
		if w.printed[i]:find("files muted", 1, true) or w.printed[i]:find("MuteSoundFile", 1, true) then
			return w.printed[i]
		end
	end
end

H.test("/hud debug modules: the count and your race and sex", function()
	local w, ns, db = World()
	w.env.UnitRace = function() return "Skyborne", "Skyborne", 95 end
	w.env.UnitSex = function() return 3 end
	w:slash("/hud debug modules")
	H.ok(DebugLine(w):find(" 0 of 230 files muted", 1, true), "off: none muted")
	db.muteErrorVoice = true
	ns.HUDini:Apply()
	w:slash("/hud debug modules")
	local line = DebugLine(w)
	H.ok(line:find("230 of 230 files muted", 1, true), "on: all muted")
	H.ok(line:find("you: Skyborne, race 95, sex 3", 1, true), "race and sex: " .. line)
	db.muteErrorVoice = false
	ns.HUDini:Apply()
	w:slash("/hud debug modules")
	H.ok(DebugLine(w):find(" 0 of 230 files muted", 1, true), "off again: none muted")
end)

H.test("/hud debug modules: no MuteSoundFile; a secret race or sex is not printed", function()
	local w = H.world()
	w.secret = {}
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.env.MuteSoundFile, w.env.UnmuteSoundFile = false, false
	w.env.UnitRace = function() return "Orc", "Orc", 2 end
	w.env.UnitSex = function() return 2 end
	w:loadAddon()
	w.env.HUDiniDB.muteErrorVoice = true
	w.ns.HUDini:Apply()
	w:slash("/hud debug modules")
	local line = DebugLine(w)
	H.ok(line:find("no MuteSoundFile on this client", 1, true), "says the call is missing")
	H.ok(line:find("you: Orc, race 2, sex 2", 1, true), "plain: printed: " .. line)
	w.secret.Orc, w.secret[2] = true, true
	w:slash("/hud debug modules")
	line = DebugLine(w)
	H.ok(line:find("you: nil, race nil, sex nil", 1, true), "secret: not printed: " .. line)
end)
