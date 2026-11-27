-- The game's own watch on each buff to keep up (TICK-0168, second pass).
-- In a fight the game sizes an aura container, filtered to the buff's spell
-- IDs, one element wide while the buff is on and 1 wide when it is off. A
-- clip off the container's right edge covers the red icon's spot while the
-- buff is off, and moves off it while the buff is on. The game also plays
-- a sound file when the buff leaves you (C_UnitAuras.AddAuraSound). No
-- player setup: no Cooldown Manager here.

-- A shaman with Lightning Shield (324) on the grid, learned at 600 s, its
-- ID read out of a fight. w.auras[spellID]: the aura on you. w.inFight:
-- your auras are hidden (reads give nil). w.boxes: each watch container made.
-- w.auraSounds: the game's sound registrations, by ID. The game refuses a
-- new one in a fight, from the fight's first event to its last (w.engaged,
-- the lockdown, or your auras hidden): asked at a fight's start, DK's sound
-- never played (TICK-0168, third pass). A container reads
-- your auras when it is switched on, then only the changes (an aura that
-- comes or goes); a new filter alone reads nothing again (not proven in
-- game either way, so HUDini does not count on it).
local NAMES = { [324] = "Lightning Shield", [11426] = "Ice Barrier", [1463] = "Mana Shield",
	[20154] = "Seal of Righteousness", [168] = "Frost Armor", [7302] = "Ice Armor",
	[52127] = "Water Shield", [13165] = "Aspect of the Hawk", [13163] = "Aspect of the Monkey",
	[5118] = "Aspect of the Cheetah", [13159] = "Aspect of the Pack",
	[467] = "Thorns", [783] = "Travel Form", [5487] = "Bear Form" }

local function World(opts)
	opts = opts or {}
	local w = H.world()
	-- opts.class = { token, name }: the real class file loads.
	if opts.class then w.class, w.className = opts.class[1], opts.class[2] end
	local env = w.env
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		-- w.rank[name]: the rank you know now, when it is not NAMES's.
		if w.rank and w.rank[name] then return { spellID = w.rank[name], name = name } end
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id, name = n } end
		end
	end
	env.C_Spell.GetSpellTexture = function(id) return 1000 + id end
	env.IsPlayerSpell = function(id) return (w.known or { [324] = true })[id] == true end
	env.AnchorUtil = { FlowDirection = { Right = "RIGHT", Left = "LEFT", Up = "UP", Down = "DOWN" } }
	env.Enum.UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 }
	w.auras, w.boxes, w.auraSounds, w.played, w.made = {}, {}, {}, {}, {}
	local nextSound = 0
	env.C_UnitAuras.AddAuraSound = function(trigger, info)
		w.soundCalls = (w.soundCalls or 0) + 1
		if w.soundRefused or w.engaged or w.combat or w.inFight then error("refused") end
		if w.soundNoID then return nil end
		nextSound = nextSound + 1
		w.auraSounds[nextSound] = { trigger = trigger, info = info }
		return nextSound
	end
	env.C_UnitAuras.RemoveAuraSound = function(id)
		w.removeCalls = (w.removeCalls or 0) + 1
		if w.removeRefused then error("refused") end
		w.auraSounds[id] = nil
	end
	env.PlaySound = function(kit) table.insert(w.played, kit) return true end
	local make = env.CreateFrame
	env.CreateFrame = function(kind, name, parent, template)
		if kind ~= "AuraContainer" then
			local f = make(kind, name, parent, template)
			if template == "DisableUntrustedLayoutScriptsTemplate" then table.insert(w.made, f) end
			return f
		end
		if parent and parent == w.hud then w.tries = (w.tries or 0) + 1 end
		if opts.noContainer then error("Unknown frame type 'AuraContainer'") end
		local f = w:Frame(name, parent)
		f.enabled, f.has = true, {}
		rawset(f, "SetEnabled", function(_, v)
			if v and not f.enabled then
				f.has = {}
				for id in pairs(f.ids or {}) do
					if w.auras[id] then f.has[id] = true end
				end
			elseif not v then
				f.has = {}
			end
			f.enabled = v
		end)
		rawset(f, "SetEditModePreviewEnabled", function() end)
		rawset(f, "SetUnit", function(_, unit) f.unit = unit end)
		rawset(f, "AddAuraGroup", function(_, key, filter, o)
			if key == "watch" then
				w.watchTries = (w.watchTries or 0) + 1
				if w.watchLimit and #w.boxes >= w.watchLimit then error("no more") end
			end
			f.group, f.filter, f.ids, f.layout, f.max = key, filter, o.candidateFilters.includeSpellIDs, o.layout, o.maxFrameCount
			if key == "watch" then table.insert(w.boxes, f) end
		end)
		rawset(f, "SetAuraGroupCandidateFilters", function(_, key, filters)
			assert(key == f.group, "a group the container has")
			if w.filterRefused then error("refused") end
			f.ids = filters.includeSpellIDs
		end)
		rawset(f, "SetAuraGroupLayout", function(_, key, layout)
			assert(key == f.group, "a group the container has")
			f.layout = layout
		end)
		return f
	end
	local ns = w:loadAddon()
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.inFight then return nil end
		for id, data in pairs(w.auras) do
			if NAMES[id] == name then return data end
		end
	end
	env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
		if w.inFight then return nil end
		local list = {}
		for _, data in pairs(w.auras) do list[#list + 1] = data end
		return list[i]
	end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.inFight == true end }
	local db = env.HUDiniDB
	db.warnOwnBuff, db.showHealth, db.showBuffTime = true, true, true
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true } }
	local hud = ns.HUDini
	w.hud = hud
	hud.spells = { { spellID = 324, slot = 1, auraNames = { "Lightning Shield" } } }
	hud:GetIcon(1):Show()
	hud:Show()
	hud.body:Show()
	local bar = ns.GetBar("health")
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", hud, "TOPLEFT", 50, -40)
	bar:SetSize(200, 30)
	bar:Show()
	w.time = 100
	return w, ns
end

local function On(w, id)
	w.auras[id] = { auraInstanceID = id, spellId = id, name = NAMES[id], duration = 600,
		expirationTime = w.time + 600 }
end

-- The game sizes each enabled container: one element wide with an aura it
-- holds, 1 wide with none (the flow layout's least). It holds what it read
-- when switched on (the stub's SetEnabled), then follows the changes since
-- the last call: an aura gone leaves, a new aura its filter matches comes.
local function GameSizes(w)
	local before = w.before or {}
	for _, f in ipairs(w.boxes) do
		if f.enabled and f.unit == "player" then
			for id in pairs(f.has) do
				if not w.auras[id] then f.has[id] = nil end
			end
			for id in pairs(w.auras) do
				if not before[id] and (f.ids or {})[id] then f.has[id] = true end
			end
		end
		local present = f.enabled and next(f.has) ~= nil
		f:SetSize(present and f.layout.elementWidth or 1, present and f.layout.elementHeight or 1)
	end
	w.before = {}
	for id in pairs(w.auras) do w.before[id] = true end
end


-- The clip HUDini hung on a container (anchored to it, made with the
-- template the container asks for), and the clip's art.
local function ClipOf(w, box)
	for _, f in ipairs(w.made) do
		local _, rel = f:GetPoint(1)
		if rel == box then
			for _, a in ipairs(w.made) do
				if a:GetParent() == f then return f, a end
			end
			return f
		end
	end
end

-- True when the red icon of this container's watch is seen: its clip shows
-- and covers all of its art. Worked out from the points HUDini set and the
-- size the game gave the container. An inverse watch (TICK-0196) hangs its
-- clip's right edge on the container's right edge.
local function Seen(w, ns, box)
	local hud = ns.HUDini
	local clip, art = ClipOf(w, box)
	H.ok(clip and art, "the watch has its clip and its art")
	local p, rel, rp, bx = box:GetPoint(1)
	H.ok(p == "TOPLEFT" and rel == hud and rp == "TOPLEFT", "the container on the anchor")
	local cp, _, crp, cx = clip:GetPoint(1)
	H.ok((cp == "TOPLEFT" or cp == "TOPRIGHT") and crp == "TOPRIGHT", "the clip on the container's right edge")
	local ap, arel, arp, ax = art:GetPoint(1)
	H.ok(ap == "TOPLEFT" and arel == hud and arp == "TOPLEFT", "the art on the anchor")
	H.eq(clip.__h.clips, true, "the clip cuts its children")
	local left = bx + box:GetWidth() + cx
	if cp == "TOPRIGHT" then left = left - clip:GetWidth() end
	local right = left + clip:GetWidth()
	local covers = left <= ax and right >= ax + art:GetWidth()
	local away = left >= ax + art:GetWidth() or right <= ax
	H.ok(covers or away, "the clip covers all of the art or none of it")
	return clip:IsShown() and covers
end

-- A fight starts and ends as the game does it (test_buff_missing_fight.lua).
local function StartFight(w)
	w.combat, w.engaged = false, true
	w:fire("PLAYER_REGEN_DISABLED")
	w.combat, w.inFight = true, true
	w:runTimers()
	GameSizes(w)
end

-- The game may still refuse a sound in the fight's last event: HUDini asks
-- a frame later.
local function EndFight(w)
	w.combat, w.inFight = false, false
	w:fire("PLAYER_REGEN_ENABLED")
	w.engaged = false
	w:runTimers()
	GameSizes(w)
end

local function Sounds(w)
	local list = {}
	for _, s in pairs(w.auraSounds) do list[#list + 1] = s end
	return list
end

H.test("Lightning Shield: one watch on its read ID, set up out of a fight, invisible", function()
	local w, ns = World()
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one container")
	local box = w.boxes[1]
	H.eq(box.filter, "HELPFUL", "your buffs")
	H.eq(box.max, 1, "room for one aura")
	H.ok(box.ids[324] and next(box.ids, next(box.ids)) == nil, "the read ID only")
	H.eq(box.unit, "player", "on you")
	H.eq(box:GetAlpha(), 0, "the container is not seen")
	H.eq(box.enabled, true, "on out of a fight, so the game has it read when one starts")
	H.eq(box.layout.elementHeight, 30, "the bar's height")
	local clip = ClipOf(w, box)
	H.eq(clip:IsShown(), false, "out of a fight: no icon")
	H.eq(clip:GetParent(), ns.GetBar("health"), "a child of the health bar")
end)

H.test("off in a fight: the icon shows; on: it is cut away; after the fight: gone", function()
	local w, ns = World()
	On(w, 324)
	ns.UpdateBuffMissing()
	StartFight(w)
	local box = w.boxes[1]
	H.eq(Seen(w, ns, box), false, "on at the fight start: no icon")
	w.auras[324] = nil
	GameSizes(w)
	H.eq(Seen(w, ns, box), true, "the charges used up: the icon")
	On(w, 324)
	GameSizes(w)
	H.eq(Seen(w, ns, box), false, "cast again: no icon")
	w.auras[324] = nil
	GameSizes(w)
	EndFight(w)
	H.eq(Seen(w, ns, box), false, "after the fight: no icon")
end)

H.test("the icon sits on the first spot left of the health bar", function()
	local w, ns = World()
	ns.UpdateBuffMissing()
	StartFight(w)
	local _, art = ClipOf(w, w.boxes[1])
	local _, _, _, ax, ay = art:GetPoint(1)
	H.eq(ax, 50 - 3 - 30, "3 pixels left of the bar, one icon wide")
	H.eq(ay, -40 + 30, "level with the bar")
	H.eq(art:GetWidth(), 30, "the bar's height square")
	H.eq(Seen(w, ns, w.boxes[1]), true, "off: seen")
end)

H.test("the bar moves out of a fight: the watch moves with it", function()
	local w, ns = World()
	ns.UpdateBuffMissing()
	local bar = ns.GetBar("health")
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", ns.HUDini, "TOPLEFT", 10, -60)
	bar:SetSize(200, 20)
	ns.SyncBuffWatches()
	StartFight(w)
	local _, art = ClipOf(w, w.boxes[1])
	local _, _, _, ax, ay = art:GetPoint(1)
	H.eq(ax, 10 - 3 - 20, "the new spot")
	H.eq(ay, -60 + 20, "the new spot")
	H.eq(w.boxes[1].layout.elementHeight, 20, "the new height")
	H.eq(Seen(w, ns, w.boxes[1]), true, "off: seen")
end)

H.test("no read ID yet: no watch (the buff on could not hide it)", function()
	local w, ns = World()
	ns.ClassDB().auraSpellIDs = {}
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 0, "no container")
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "seen once out of a fight: the watch")
end)

H.test("the setting off, or the health bar off: no watch", function()
	local w, ns = World()
	w.env.HUDiniDB.warnOwnBuff = false
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 0, "buff alert off: no container")
	w.env.HUDiniDB.warnOwnBuff = true
	ns.UpdateBuffMissing()
	H.eq(w.boxes[1].enabled, true, "on again")
	w.env.HUDiniDB.showHealth = false
	ns.UpdateBuffMissing()
	H.eq(w.boxes[1].enabled, false, "the health bar off: the watch off")
	StartFight(w)
	H.eq(ClipOf(w, w.boxes[1]):IsShown(), false, "no icon in the fight")
	H.eq(#Sounds(w), 0, "no sound")
end)

H.test("the game sounds as the buff ends in a fight: asked out of the fight, kept through it", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	local list = Sounds(w)
	H.eq(#list, 1, "asked out of a fight (the game refuses in one)")
	H.eq(list[1].trigger, 2, "when the buff leaves you")
	H.eq(list[1].info.spellID, 324, "the buff's ID")
	H.eq(list[1].info.unitToken, "player", "on you")
	H.eq(list[1].info.soundFileID, 567397, "the picked sound's file (the default)")
	local calls, removes = w.soundCalls, w.removeCalls
	StartFight(w)
	H.eq(w.soundCalls, calls, "no sound asked for in the fight")
	H.eq(w.removeCalls, removes, "none taken back in the fight")
	H.eq(#Sounds(w), 1, "the sound is still the game's")
	H.eq(ns.GameSounds("Lightning Shield"), true, "HUDini plays none of its own")
	EndFight(w)
	H.eq(#Sounds(w), 1, "after the fight, the buff still on: kept")
	H.eq(ns.GameSounds("Lightning Shield"), false, "HUDini counts on it in a fight only")
	H.eq(w.soundCalls, calls, "not asked again")
	-- The game's charges ran out in the next fight: the sound plays (the
	-- game's), then out of the fight it goes.
	StartFight(w)
	w.auras[324] = nil
	EndFight(w)
	ns.UpdateIconAuras()
	H.eq(#Sounds(w), 1, "the buff off: kept (it sounds only as the buff leaves you again)")
	H.eq(w.soundCalls, calls, "and not asked again")
end)

H.test("a buff that ends soon gets no game sound: it is taken back before the end", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(#Sounds(w), 1, "ten minutes left: asked")
	-- The timer to 5 s before the end (the harness runs it now; the clock
	-- says when).
	w.time = w.auras[324].expirationTime - 6
	w:runTimers()
	H.eq(#Sounds(w), 1, "6 s left: kept")
	w.time = w.auras[324].expirationTime - 4
	w:runTimers()
	H.eq(#Sounds(w), 0, "4 s left: taken back, so it ends out of a fight with no sound (D-033)")
	ns.UpdateBuffMissing()
	H.eq(#Sounds(w), 0, "not asked again while it ends soon")
	StartFight(w)
	H.eq(ns.GameSounds("Lightning Shield"), false, "in a fight now: HUDini's own path")
	EndFight(w)
	w.auras[324] = nil
	ns.UpdateIconAuras()
	H.eq(#Sounds(w), 1, "the buff off: asked again (a cast in a fight is then the game's)")
end)

H.test("the game refuses a sound out of a fight: asked once, again after the next fight", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	w.soundRefused = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	local calls = w.soundCalls
	ns.UpdateBuffMissing()
	ns.UpdateIconAuras()
	H.eq(w.soundCalls, calls, "not asked at each update")
	w.soundRefused = false
	StartFight(w)
	EndFight(w)
	H.eq(#Sounds(w), 1, "asked again after the fight, and taken")
end)

H.test("the sound turned off out of a fight: the game's sound is taken back", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(#Sounds(w), 1, "asked")
	-- Through the options, with no aura change after: a fight could start
	-- next.
	ns.SetKeepUpSound("off")
	H.eq(#Sounds(w), 0, "taken back at once")
	ns.SetKeepUpSound(true)
	H.eq(Sounds(w)[1].info.soundFileID, 567397, "on again: asked again at once")
end)

H.test("a new sound picked: the game plays the new file, one sound even when the old will not go", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(Sounds(w)[1].info.soundFileID, 567397, "the default's file")
	ns.SetKeepUpSound("alarmClock")
	H.eq(#Sounds(w), 1, "one sound, at once")
	H.eq(Sounds(w)[1].info.soundFileID, 567399, "the alarm clock's file (DK's pick)")
	w.removeRefused = true
	ns.SetKeepUpSound(ns.MISSING_SOUND_DEFAULT)
	H.eq(#Sounds(w), 1, "the old will not go: one, not two")
	H.eq(Sounds(w)[1].info.soundFileID, 567399, "the old file still")
	w.removeRefused = false
	ns.UpdateBuffMissing()
	H.eq(#Sounds(w), 1, "one sound")
	H.eq(Sounds(w)[1].info.soundFileID, 567397, "now the new file")
end)

H.test("/hud debug aura: the watch's IDs, the game's sound IDs and the file, saved too", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	local lines = {}
	ns.BuffWatchReport(function(l) lines[#lines + 1] = l end)
	local all = table.concat(lines, "\n")
	H.ok(all:find("Sound file 567397", 1, true), "the file ID")
	H.ok(all:find("Watch 1: Lightning Shield, IDs 324, armed true, game sound true", 1, true), "the watch")
	H.ok(all:find("Sounds the game holds: 1 for 324 (file 567397)", 1, true), "the game's sound ID")
	H.ok(all:find("Last try: asked 324: sound 1", 1, true), "the last try")
	w:slash("/hud debug aura")
	local saved = table.concat(w.env.HUDiniDB.lastReport or {}, "\n")
	H.ok(saved:find("Sounds the game holds: 1 for 324", 1, true), "in the saved report")
end)

H.test("the sound off: the game sounds for nothing", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = false
	ns.UpdateBuffMissing()
	StartFight(w)
	H.eq(#Sounds(w), 0, "no sound")
	H.eq(ns.GameSounds("Lightning Shield"), false, "HUDini's path decides (and is off)")
end)

H.test("off at the fight start: HUDini's own sound plays, not the game's", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	H.eq(ns.GameSounds("Lightning Shield"), false, "the game cannot sound for a buff already off")
	H.eq(#w.played, 1, "HUDini's sound, once")
end)

H.test("off at the fight start, cast in the fight: its next end is the game's to sound", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	H.eq(ns.GameSounds("Lightning Shield"), false, "off: HUDini's")
	On(w, 324)
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 324)
	H.eq(ns.GameSounds("Lightning Shield"), true, "cast: the game's")
end)

-- TICK-0230: a HUDini voice sound is a path; the game takes it as
-- soundFileName. A path it gives no ID for is a refusal of that file only.
H.test("a voice sound picked: the game gets its path as a file name", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	ns.SetKeepUpSound("voiceBuff")
	local list = Sounds(w)
	H.eq(#list, 1, "one sound")
	H.eq(list[1].info.soundFileName, "Interface\\AddOns\\HUDini\\Media\\Sounds\\Buff.ogg", "the voice file's path")
	H.eq(list[1].info.soundFileID, nil, "no file ID")
	ns.SetKeepUpSound("alarmClock")
	list = Sounds(w)
	H.eq(#list, 1, "a game sound again: one")
	H.eq(list[1].info.soundFileID, 567399, "its file ID")
	H.eq(list[1].info.soundFileName, nil, "no file name")
end)

H.test("a voice path with no ID back: HUDini plays it, and the game's sounds still work", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = "voiceBuff"
	w.soundNoID = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	ns.UpdateBuffMissing()
	ns.UpdateBuffMissing()
	H.eq(w.soundCalls, 1, "asked once for that file")
	StartFight(w)
	H.eq(ns.GameSounds("Lightning Shield"), false, "HUDini's own sound decides")
	EndFight(w) -- a refused sound is asked again after a fight
	local calls = w.soundCalls
	ns.SetKeepUpSound("voiceSafe")
	ns.UpdateBuffMissing()
	H.eq(w.soundCalls, calls + 1, "another file: asked once too")
	w.soundNoID = false
	ns.SetKeepUpSound("alarmClock")
	H.eq(#Sounds(w), 1, "a game sound is still asked for")
	H.eq(Sounds(w)[1].info.soundFileID, 567399)
end)

H.test("a sound the game will not take back is tried again, and not asked for twice", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	w.removeRefused = true
	ns.ClassDB().keepUpSound = false
	ns.UpdateBuffMissing()
	H.eq(#Sounds(w), 1, "still there")
	ns.ClassDB().keepUpSound = true
	ns.UpdateBuffMissing()
	H.eq(#Sounds(w), 1, "on again: one, not two")
	w.removeRefused = false
	ns.ClassDB().keepUpSound = false
	ns.UpdateBuffMissing()
	H.eq(#Sounds(w), 0, "taken back")
end)

H.test("the game refuses the sound: no error, HUDini's own path decides", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	w.soundRefused = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	H.eq(#Sounds(w), 0, "none")
	H.eq(ns.GameSounds("Lightning Shield"), false, "HUDini's path")
	H.eq(Seen(w, ns, w.boxes[1]), false, "the icon still works")
end)

-- The spell IDs the game holds a sound for, as one sorted line.
local function SoundIDs(w)
	local ids = {}
	for _, snd in ipairs(Sounds(w)) do ids[#ids + 1] = snd.info.spellID end
	table.sort(ids)
	return table.concat(ids, " ")
end

local function KeepUpList(w, ns, list)
	local value = ns.ClassValue
	ns.ClassValue = function(key)
		if key == "keepUp" then return list end
		return value(key)
	end
end

-- TICK-0194: a watch of more than one name gets the game's sound while at
-- most one of its buffs is on.
H.test("a keep-up list of two buffs: one watch on both; the game sounds while one at most is on", function()
	local w, ns = World()
	w.known = { [11426] = true, [1463] = true }
	local db = w.env.HUDiniDB
	db.warnOwnBuff, db.warnKeepUp = false, true
	ns.ClassDB().keepUpSound = true
	ns.ClassDB().auraSpellIDs = { ["Ice Barrier"] = { [11426] = true }, ["Mana Shield"] = { [1463] = true } }
	KeepUpList(w, ns, { "Ice Barrier", "Mana Shield" })
	On(w, 1463)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one container")
	H.ok(w.boxes[1].ids[11426] and w.boxes[1].ids[1463], "both IDs")
	H.eq(SoundIDs(w), "1463 11426", "one on: the game sounds as either leaves you")
	On(w, 11426)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(#Sounds(w), 0, "both on: one ending does not mean both are off: no game sound")
	StartFight(w)
	H.eq(ns.GameSounds(ns.KEEP_UP_KEY), false, "HUDini's own path")
	H.eq(Seen(w, ns, w.boxes[1]), false, "both on: no icon")
	w.auras[1463] = nil
	GameSizes(w)
	H.eq(Seen(w, ns, w.boxes[1]), false, "one of them on: no icon")
	w.auras[11426] = nil
	GameSizes(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "both off: the icon")
	EndFight(w)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(SoundIDs(w), "1463 11426", "none on after the fight: asked for both again")
end)

H.test("Shaman: Lightning Shield or Water Shield: Water Shield ends in a fight, the game sounds", function()
	local w, ns = World()
	w.known = { [324] = true, [52127] = true }
	local db = w.env.HUDiniDB
	db.warnOwnBuff, db.warnKeepUp = false, true
	ns.ClassDB().keepUpSound = true
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true }, ["Water Shield"] = { [52127] = true } }
	KeepUpList(w, ns, { "Lightning Shield", "Water Shield" })
	On(w, 52127)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(SoundIDs(w), "324 52127", "the game sounds as either shield leaves you")
	local list = Sounds(w)
	H.eq(list[1].trigger, 2, "when it leaves you")
	H.eq(list[1].info.soundFileID, 567397, "the picked sound's file")
	StartFight(w)
	H.eq(ns.GameSounds(ns.KEEP_UP_KEY), true, "on at the fight start: the game's to sound, HUDini plays none")
	w.auras[52127] = nil
	GameSizes(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "Water Shield gone: the icon")
	H.eq(#Sounds(w), 2, "the sounds stay through the fight")
end)

-- TICK-0205: one read ID proves the group; a name not read yet adds the
-- client's ID for its name.
H.test("a keep-up list with a buff not yet read: watched on the client's ID for its name", function()
	local w, ns = World()
	w.known = { [11426] = true, [1463] = true }
	local db = w.env.HUDiniDB
	db.warnOwnBuff, db.warnKeepUp = false, true
	ns.ClassDB().auraSpellIDs = { ["Ice Barrier"] = { [11426] = true } }
	local value = ns.ClassValue
	ns.ClassValue = function(key)
		if key == "keepUp" then return { "Ice Barrier", "Mana Shield" } end
		return value(key)
	end
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one container")
	H.ok(w.boxes[1].ids[11426] and w.boxes[1].ids[1463], "both IDs")
	StartFight(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "none on: the icon")
	On(w, 1463)
	GameSizes(w)
	H.eq(Seen(w, ns, w.boxes[1]), false, "Mana Shield cast in the fight: no icon")
	w.auras[1463] = nil
	GameSizes(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "it breaks: the icon")

	local w2, ns2 = World()
	w2.known = { [11426] = true, [1463] = true }
	w2.env.HUDiniDB.warnOwnBuff, w2.env.HUDiniDB.warnKeepUp = false, true
	ns2.ClassDB().auraSpellIDs = {}
	local value2 = ns2.ClassValue
	ns2.ClassValue = function(key)
		if key == "keepUp" then return { "Ice Barrier", "Mana Shield" } end
		return value2(key)
	end
	ns2.UpdateBuffMissing()
	H.eq(#w2.boxes, 0, "no name read: no container (nothing proves the IDs)")
end)

H.test("a group with one name read: the names you know but never had are watched, others left out", function()
	local w, ns = World()
	w.known = { [168] = true, [7302] = true }
	local db = w.env.HUDiniDB
	db.warnKeepUp = false
	db.auraMap = { ["Frost Armor"] = { "Ice Armor", "Mage Armor" } }
	ns.ClassDB().buffSpells = { ["Frost Armor"] = 1800 }
	ns.ClassDB().auraSpellIDs = { ["Frost Armor"] = { [168] = true } }
	ns.HUDini.spells = {}
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one container")
	local n = 0
	for _ in pairs(w.boxes[1].ids) do n = n + 1 end
	H.ok(w.boxes[1].ids[168] and w.boxes[1].ids[7302], "Frost Armor read, Ice Armor from its name")
	H.eq(n, 2, "Mage Armor: the client has no ID for it, left out")
	StartFight(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "no armor: the icon")
	On(w, 7302)
	GameSizes(w)
	H.eq(Seen(w, ns, w.boxes[1]), false, "Ice Armor cast in the fight: no icon")
end)

-- Review finding 1: the client's ID for a name is the rank you know now.
H.test("a rank trained after the watch formed: its ID joins the watch after SPELLS_CHANGED", function()
	local w, ns = World()
	w.known = { [168] = true, [7302] = true }
	local db = w.env.HUDiniDB
	db.warnKeepUp = false
	db.auraMap = { ["Frost Armor"] = { "Ice Armor" } }
	ns.ClassDB().buffSpells = { ["Frost Armor"] = 1800 }
	ns.ClassDB().auraSpellIDs = { ["Frost Armor"] = { [168] = true } }
	ns.HUDini.spells = {}
	ns.UpdateBuffMissing()
	local function Box() return w.boxes[#w.boxes] end
	H.ok(Box().ids[7302], "Ice Armor rank 1 from its name")
	w.known[7320], w.rank = true, { ["Ice Armor"] = 7320 }
	w:fire("SPELLS_CHANGED")
	ns.UpdateBuffMissing()
	H.ok(Box().ids[7320], "rank 2 trained: its ID is watched")
	H.eq(Box().ids[7302], nil, "rank 1 no longer")
	StartFight(w)
	H.eq(Seen(w, ns, Box()), true, "no armor: the icon")
	On(w, 7320)
	GameSizes(w)
	H.eq(Seen(w, ns, Box()), false, "rank 2 cast in the fight: no icon")
end)

-- TICK-0222: a group where one buff counts for all, with every member
-- learned (a Mage who knows the three armors).
local function ThreeArmors(w, ns)
	w.known = { [168] = true, [7302] = true, [6117] = true }
	w.rank = { ["Mage Armor"] = 6117 }
	w.env.HUDiniDB.warnKeepUp = false -- the group is the Mage class file's own
	ns.ClassDB().buffSpells = { ["Frost Armor"] = 1800, ["Ice Armor"] = 1800, ["Mage Armor"] = 1800 }
	ns.ClassDB().auraSpellIDs = { ["Frost Armor"] = { [168] = true }, ["Ice Armor"] = { [7302] = true } }
end

local function Report(ns)
	local lines = {}
	ns.BuffWatchReport(function(l) lines[#lines + 1] = l end)
	return table.concat(lines, "\n")
end

H.test("three armors learned, one group: one watch, one icon in a fight with none on", function()
	local w, ns = World()
	ThreeArmors(w, ns)
	ns.HUDini.spells = {}
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one container for the group")
	H.ok(w.boxes[1].ids[168] and w.boxes[1].ids[7302] and w.boxes[1].ids[6117], "on all three armors' IDs")
	H.ok(Report(ns):find("Watch 1: Frost Armor,", 1, true), "off the bars: the first by name owns it")
	H.eq(Report(ns):find("Watch 2", 1, true), nil, "no second watch")
	StartFight(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "no armor: the icon")
	H.eq(ns.BuffWatchSpots(), 1, "one spot")
	for _, name in ipairs({ "Frost Armor", "Ice Armor", "Mage Armor" }) do
		H.eq(ns.BuffWatched(name), true, name .. ": the alert's own icon steps aside")
	end
	On(w, 6117)
	GameSizes(w)
	H.eq(Seen(w, ns, w.boxes[1]), false, "Mage Armor cast in the fight: no icon")
end)

H.test("a buff group (three armors) gets the game's sound on every member's ID", function()
	local w, ns = World()
	ThreeArmors(w, ns)
	ns.ClassDB().keepUpSound = true
	ns.HUDini.spells = {}
	On(w, 7302)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(SoundIDs(w), "168 6117 7302", "Ice Armor on: the game sounds as any armor leaves you")
	StartFight(w)
	H.eq(ns.GameSounds("Frost Armor"), true, "the group's owner: the game's to sound")
end)

H.test("three armors learned, one on your bars: it owns the group's one watch", function()
	local w, ns = World()
	ThreeArmors(w, ns)
	ns.HUDini.spells = { { spellID = 7302, slot = 1, auraNames = { "Ice Armor", "Frost Armor", "Mage Armor" } } }
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one container")
	H.ok(Report(ns):find("Watch 1: Ice Armor,", 1, true), "the bar's armor")
	H.eq(Report(ns):find("Watch 2", 1, true), nil, "no second watch")
end)

-- dev-warlock: Demon Skin and Demon Armor are learned as two buffs today,
-- so a Warlock of 20+ who wore both had two watches. The group is the
-- class file's own; the combat buff list (both armors) adds none.
H.test("Warlock: Demon Skin and Demon Armor both learned: one watch, one icon", function()
	local w, ns = World({ class = { "WARLOCK", "Warlock" } })
	w.known = { [687] = true, [706] = true }
	w.rank = { ["Demon Skin"] = 687, ["Demon Armor"] = 706 }
	w.env.HUDiniDB.warnKeepUp = true
	ns.ClassDB().buffSpells = { ["Demon Skin"] = 1800, ["Demon Armor"] = 1800 }
	ns.ClassDB().auraSpellIDs = { ["Demon Skin"] = { [687] = true } }
	ns.HUDini.spells = {}
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one container")
	H.ok(w.boxes[1].ids[687] and w.boxes[1].ids[706], "on both armors' IDs")
	H.ok(Report(ns):find("Watch 1: Demon Armor,", 1, true), "the first by name owns it")
	StartFight(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "no armor: the icon")
	H.eq(ns.BuffWatched("Demon Skin"), true, "the other armor's own icon steps aside")
	H.eq(ns.BuffWatchSpots(), 1, "one spot")
end)

H.test("a buff of a group and a buff of its own: a watch each", function()
	local w, ns = World()
	ThreeArmors(w, ns)
	w.known[324] = true
	ns.ClassDB().buffSpells["Lightning Shield"] = 600
	ns.ClassDB().auraSpellIDs["Lightning Shield"] = { [324] = true }
	ns.HUDini.spells = {}
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 2, "the group and Lightning Shield")
	StartFight(w)
	H.eq(ns.BuffWatched("Lightning Shield"), true, "its own")
	H.eq(ns.BuffWatched(ns.KEEP_UP_KEY), false, "the combat buff list is not in a group")
end)

-- Review of TICK-0222, finding 1: a map one way only (Lightning Shield
-- counts Seal of Righteousness, Seal counts only itself). Seal off is not
-- covered by Lightning Shield's watch: Lightning Shield on hides that one.
local function OneWay(w, ns)
	w.known = { [324] = true, [20154] = true }
	w.env.HUDiniDB.warnKeepUp = false
	w.env.HUDiniDB.auraMap = { ["Lightning Shield"] = { "Seal of Righteousness" } }
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600, ["Seal of Righteousness"] = 1800 }
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true }, ["Seal of Righteousness"] = { [20154] = true } }
end

H.test("a map one way only: the buff that shares a name keeps its own watch", function()
	local w, ns = World()
	OneWay(w, ns)
	ns.HUDini.spells = {}
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 2, "a watch each")
	H.ok(Report(ns):find("Watch 1: Lightning Shield,", 1, true), "Lightning Shield first by name")
	H.ok(Report(ns):find("Watch 2: Seal of Righteousness,", 1, true), "Seal's own")
	On(w, 324)
	StartFight(w)
	H.eq(Seen(w, ns, w.boxes[1]), false, "Lightning Shield on: its icon is cut away")
	H.eq(Seen(w, ns, w.boxes[2]), true, "Seal off: its red icon")
	H.eq(ns.BuffWatched("Seal of Righteousness"), true, "its own watch")
end)

H.test("a map one way only, the narrow buff first: it covers the wide one", function()
	local w, ns = World()
	OneWay(w, ns)
	ns.HUDini.spells = { { spellID = 20154, slot = 1, auraNames = { "Seal of Righteousness" } } }
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "Lightning Shield off means Seal off: one watch")
	H.ok(Report(ns):find("Watch 1: Seal of Righteousness,", 1, true), "the bar's buff owns it")
	StartFight(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "both off: the icon")
	H.eq(ns.BuffWatched("Lightning Shield"), true, "the covered buff's own icon steps aside")
end)

H.test("a covered buff's own icon shows when the owner's watch is not on", function()
	local w, ns = World()
	ThreeArmors(w, ns)
	ns.HUDini.spells = {}
	w.filterRefused = true
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "the container is made")
	StartFight(w)
	H.eq(ns.BuffWatchSpots(), 0, "the game refused its IDs: not on")
	for _, name in ipairs({ "Frost Armor", "Ice Armor", "Mage Armor" }) do
		H.eq(ns.BuffWatched(name), false, name .. ": the alert's own icon shows")
	end
end)

H.test("a group member with no read ID covers nothing: the member with one has the watch", function()
	local w, ns = World()
	w.known = { [11426] = true, [1463] = true }
	w.env.HUDiniDB.warnKeepUp = false
	w.env.HUDiniDB.auraMap = { ["Ice Barrier"] = { "Mana Shield" }, ["Mana Shield"] = { "Ice Barrier" } }
	ns.ClassDB().buffSpells = { ["Ice Barrier"] = 60, ["Mana Shield"] = 60 }
	ns.ClassDB().auraSpellIDs = { ["Mana Shield"] = { [1463] = true } }
	ns.HUDini.spells = {}
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one watch")
	H.ok(Report(ns):find("Watch 1: Ice Barrier,", 1, true), "Ice Barrier first by name: a name of the group is read")
	w.env.HUDiniDB.auraMap = { ["Mana Shield"] = { "Ice Barrier" } }
	ns.UpdateBuffMissing()
	H.ok(Report(ns):find("Watch 1: Mana Shield,", 1, true), "Ice Barrier alone has no read ID: Mana Shield has the watch")
	H.eq(Report(ns):find("Watch 2", 1, true), nil, "and no second")
end)

H.test("a combat buff pick of a covered member adds no watch", function()
	local w, ns = World()
	ThreeArmors(w, ns)
	ns.HUDini.spells = {}
	w.env.HUDiniDB.warnKeepUp = true
	local value = ns.ClassValue
	ns.ClassValue = function(key)
		if key == "keepUp" then return { "Ice Armor" } end
		return value(key)
	end
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "the group's watch only")
	H.ok(Report(ns):find("Watch 1: Frost Armor,", 1, true), "Frost Armor owns it")
	StartFight(w)
	H.eq(ns.BuffWatched(ns.KEEP_UP_KEY), false, "no combat buff watch: the alert decides")
end)

H.test("a buff off the grid: its ID is read out of a fight, then it is watched", function()
	local w, ns = World()
	ns.HUDini.spells = {}
	ns.ClassDB().auraSpellIDs = {}
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 0, "not read yet: no container")
	On(w, 324)
	ns.UpdateBuffMissing()
	H.ok(ns.ClassDB().auraSpellIDs["Lightning Shield"][324], "read off the grid")
	H.eq(#w.boxes, 1, "the watch")
end)

H.test("two buffs: a watch each, the grid's first, each on its own spot", function()
	local w, ns = World()
	w.known = { [324] = true, [11426] = true }
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600, ["Ice Barrier"] = 60 }
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true }, ["Ice Barrier"] = { [11426] = true } }
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 2, "two containers")
	H.ok(w.boxes[1].ids[324], "the grid's buff first")
	H.ok(w.boxes[2].ids[11426], "then the rest")
	local a, artA = ClipOf(w, w.boxes[1])
	local _, artB = ClipOf(w, w.boxes[2])
	H.eq(select(4, artA:GetPoint(1)), 50 - 3 - 30, "the first on the first spot")
	H.eq(select(4, artB:GetPoint(1)), 50 - 3 - 30 - 33, "the second one icon and gap further left")
	H.ok(a:GetFrameLevel() > ns.GetBar("health"):GetFrameLevel() + 3, "above the alerts' own icons")
end)

-- A keep-up buff (Ice Barrier) and your own buff (Lightning Shield), each
-- with a read ID.
local function KeepUpAndOwn(w, ns)
	w.known = { [324] = true, [11426] = true }
	w.env.HUDiniDB.warnKeepUp = true
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true }, ["Ice Barrier"] = { [11426] = true } }
	local value = ns.ClassValue
	ns.ClassValue = function(key)
		if key == "keepUp" then return { "Ice Barrier" } end
		return value(key)
	end
end

H.test("keep-up and own buff both off at the fight start: one icon each, the alerts' icons step aside", function()
	local w, ns = World()
	KeepUpAndOwn(w, ns)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 2, "two watches")
	H.ok(w.boxes[1].ids[11426], "the keep-up list first (Alerts.lua's order)")
	H.ok(w.boxes[2].ids[324], "then your own buff")
	ns.ClassDB().buffSpells["Lightning Shield"] = 3600 -- an hour long: its icon shows out of a fight
	ns.UpdateBuffMissing()
	ns.UpdateAlerts()
	H.eq(ns.leftIcons.ownBuff:IsShown(), true, "out of a fight: the alert's icon (a watch shows only in a fight)")
	H.eq(select(4, ns.leftIcons.ownBuff:GetPoint(1)), -3, "by the bar: no spot held")
	StartFight(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "the keep-up icon")
	H.eq(Seen(w, ns, w.boxes[2]), true, "the own-buff icon")
	local _, artK = ClipOf(w, w.boxes[1])
	local _, artA = ClipOf(w, w.boxes[2])
	H.ok(select(4, artK:GetPoint(1)) ~= select(4, artA:GetPoint(1)), "two spots")
	H.eq(ns.leftIcons.ownBuff:IsShown(), false, "the alert's own-buff icon hides: no second icon")
	H.eq(ns.leftIcons.keepUp:IsShown(), false, "the alert's keep-up icon hides")
	H.eq(ns.missingBuffID, 324, "the HUD still knows (the glow)")
	H.eq(select(4, ns.leftIcons.keepUp:GetPoint(1)), -3 - 2 * 33, "the alerts' icons start left of the two spots")
	EndFight(w)
	H.eq(select(4, ns.leftIcons.keepUp:GetPoint(1)), -3, "after the fight: back by the bar")
	H.eq(ns.BuffWatchSpots(), 0, "no spot held")
end)

H.test("the keep-up buff ends in a fight: the game's sound only, not HUDini's too", function()
	local w, ns = World()
	KeepUpAndOwn(w, ns)
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	On(w, 11426)
	-- A minute long, as in the game: not learned as your own buff.
	w.auras[11426].duration, w.auras[11426].expirationTime = 60, w.time + 60
	ns.UpdateIconAuras()
	ns.UpdateAlerts() -- HUDini sees the list on
	ns.UpdateBuffMissing()
	H.eq(ns.ClassDB().buffSpells["Ice Barrier"], nil, "not your own buff")
	H.eq(#w.boxes, 2, "a watch for each")
	local off = false
	ns.KeepUpState = function() return not off end
	StartFight(w)
	local list = Sounds(w)
	H.eq(#list, 2, "the game sounds for both")
	H.eq(ns.GameSounds(ns.KEEP_UP_KEY), true, "the keep-up list's is the game's")
	local played = #w.played
	-- It ends; the Cooldown Manager path (when set up) sees it too.
	w.auras[11426] = nil
	off = true
	ns.UpdateAlerts()
	H.eq(#w.played, played, "HUDini plays none of its own")
	H.eq(ns.leftIcons.keepUp:IsShown(), false, "the watch shows it: the alert's icon hides")
	EndFight(w)
end)

H.test("with no watch, the alert's own icon shows in the fight (the path above is real)", function()
	local w, ns = World({ noContainer = true })
	KeepUpAndOwn(w, ns)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	H.eq(ns.leftIcons.ownBuff:IsShown(), true, "the alert's icon")
	H.eq(select(4, ns.leftIcons.keepUp:GetPoint(1)), -3, "by the bar")
end)

H.test("a new read ID on a watch that is on: the game reads your auras again", function()
	local w, ns = World()
	NAMES[325] = "Lightning Shield"
	ns.UpdateBuffMissing()
	local box = w.boxes[1]
	H.eq(box.enabled, true, "on, with 324 only")
	On(w, 325)
	GameSizes(w)
	H.eq(next(box.has), nil, "325 came before its filter: the container does not hold it")
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	NAMES[325] = nil
	H.ok(box.ids[325], "the new ID in the filter")
	StartFight(w)
	H.eq(Seen(w, ns, box), false, "the buff on: no icon")
end)

H.test("two buffs that share a spell ID: the game sounds for it once", function()
	local w, ns = World()
	w.known = { [324] = true, [11426] = true }
	ns.ClassDB().keepUpSound = true
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600, ["Ice Barrier"] = 60 }
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true },
		["Ice Barrier"] = { [324] = true, [11426] = true } }
	On(w, 324)
	On(w, 11426)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	local n324 = 0
	for _, s in ipairs(Sounds(w)) do
		if s.info.spellID == 324 then n324 = n324 + 1 end
	end
	H.eq(n324, 1, "324 once")
	H.eq(#Sounds(w), 2, "324 and 11426")
	H.eq(ns.GameSounds("Lightning Shield"), true, "the game's")
	H.eq(ns.GameSounds("Ice Barrier"), true, "the game's")
end)

H.test("your own buff with two names: the game's sound with one on, none with both on", function()
	local w, ns = World()
	w.known = { [324] = true, [1463] = true }
	ns.ClassDB().keepUpSound = true
	w.env.HUDiniDB.warnKeepUp = false -- the class's own list: not this test
	w.env.HUDiniDB.auraMap = { ["Lightning Shield"] = { "Mana Shield" } }
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true }, ["Mana Shield"] = { [1463] = true } }
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one watch")
	H.ok(w.boxes[1].ids[324] and w.boxes[1].ids[1463], "on both names")
	H.eq(SoundIDs(w), "324 1463", "one on: the game sounds as either leaves you")
	On(w, 1463)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	H.eq(SoundIDs(w), "1463", "both on: the pair asks for none (one ending is not both off); Mana Shield keeps its own watch's")
	H.eq(ns.GameSounds("Lightning Shield"), false, "324 not held: HUDini's path, so the last to end still sounds")
end)

-- The game's documentation says the ID may be nil: maybe a "no" in a state
-- HUDini cannot see, maybe a sound it could never take back.
H.test("the game gives no ID back: asked again after the next fight; twice: never again", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	w.soundNoID = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	local calls = w.soundCalls
	ns.UpdateBuffMissing()
	H.eq(w.soundCalls, calls, "not asked at each update")
	StartFight(w)
	H.eq(ns.GameSounds("Lightning Shield"), false, "HUDini's path")
	EndFight(w)
	H.eq(w.soundCalls, calls + 1, "asked again after the fight")
	w.soundNoID = false
	StartFight(w)
	EndFight(w)
	ns.UpdateBuffMissing()
	H.eq(w.soundCalls, calls + 1, "no ID back twice: never asked again")
	H.eq(#Sounds(w), 0, "none")
end)

-- The harness runs a timer at once, whatever its delay: a timer that starts
-- itself again shows as a new one at each run.
H.test("the take-back timer does not start itself again while the game refuses, or a sound will not go", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	local made = 0
	local NewTimer = w.env.C_Timer.NewTimer
	w.env.C_Timer.NewTimer = function(...)
		made = made + 1
		return NewTimer(...)
	end
	StartFight(w)
	w.time = w.auras[324].expirationTime - 4
	w:runTimers()
	w:runTimers()
	H.eq(made, 0, "in a fight, the buff 4 s from its end: no new timer")
	H.eq(#Sounds(w), 1, "and no call: the sound stays")
	EndFight(w)
	H.eq(#Sounds(w), 0, "after the fight: taken back")
	-- Out of a fight, a sound that will not go, its time gone by.
	ns.UpdateIconAuras()
	w.removeRefused = true
	w.auras[324].expirationTime = w.time + 600
	ns.UpdateIconAuras()
	H.eq(#Sounds(w), 1, "a new shield: asked")
	made = 0
	w.time = w.auras[324].expirationTime - 4
	w:runTimers()
	w:runTimers()
	w:runTimers()
	H.eq(#Sounds(w), 1, "it will not go")
	H.ok(made <= 1, "no timer at each run: " .. made)
end)

H.test("a sound that will not go: HUDini does not count on it, a buff off at the next start gets HUDini's", function()
	local w, ns = World()
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	w.removeRefused = true
	EndFight(w)
	H.eq(ns.GameSounds("Lightning Shield"), false, "not counted after the fight")
	w.auras[324] = nil
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	local played = #w.played
	StartFight(w)
	H.eq(ns.GameSounds("Lightning Shield"), false, "not the game's")
	H.eq(#w.played, played + 1, "HUDini's own sound")
end)

H.test("a second watch the client cannot make is not tried again at each update", function()
	local w, ns = World()
	w.watchLimit = 1
	w.known = { [324] = true, [11426] = true }
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600, ["Ice Barrier"] = 60 }
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true }, ["Ice Barrier"] = { [11426] = true } }
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one made")
	local tries = w.watchTries
	for _ = 1, 3 do ns.UpdateBuffMissing() end
	H.eq(w.watchTries, tries, "no new try")
	H.eq(w.boxes[1].enabled, true, "the first still on")
end)

H.test("no aura container on this client: no error, no watch, no game sound", function()
	local w, ns = World({ noContainer = true })
	ns.ClassDB().keepUpSound = true
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	EndFight(w)
	H.eq(#w.boxes, 0, "none")
	H.eq(#Sounds(w), 0, "no game sound")
	H.eq(ns.GameSounds("Lightning Shield"), false, "HUDini's path")
	local tries = w.tries
	for _ = 1, 3 do ns.UpdateBuffMissing() end
	H.eq(w.tries, tries, "tried once, not at every update")
end)

--------------------------------------------------------------------------------
-- TICK-0196: a buff not to have on in a fight (a Hunter's Aspect of the
-- Cheetah or of the Pack). A watch the other way round: its red icon, your
-- last fight aspect, shows while one of them is on. On the keep-up watch's
-- spot when the keep-up list holds them: the two never show at once.
--------------------------------------------------------------------------------

local HAWK, MONKEY, CHEETAH, PACK = 13165, 13163, 5118, 13159

-- A hunter: the class file's keep-up list of four aspects, Cheetah and Pack
-- not for a fight, each read once out of a fight. opts.pick: the player's
-- keep-up pick. opts.notIn: the class file's notInFight.
local function Hunter(w, ns, opts)
	opts = opts or {}
	local db = w.env.HUDiniDB
	db.warnOwnBuff, db.warnKeepUp = false, opts.keepUpOff ~= true
	ns.ClassDB().buffSpells = {}
	w.known = { [HAWK] = true, [MONKEY] = true, [CHEETAH] = true, [PACK] = true }
	ns.ClassDB().auraSpellIDs = opts.ids or { ["Aspect of the Hawk"] = { [HAWK] = true },
		["Aspect of the Cheetah"] = { [CHEETAH] = true }, ["Aspect of the Pack"] = { [PACK] = true } }
	local file = {
		keepUp = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Pack" },
		notInFight = opts.notIn or { "Aspect of the Cheetah", "Aspect of the Pack" },
	}
	local default, value = ns.ClassDefault, ns.ClassValue
	ns.ClassDefault = function(key)
		if file[key] ~= nil then return file[key] end
		return default(key)
	end
	ns.ClassValue = function(key)
		if key == "keepUp" then
			if opts.pick ~= nil then return opts.pick end
			return file.keepUp
		end
		return value(key)
	end
end

-- Hawk as a learned buff of its own: no keep-up watch (one icon is
-- enough), so the Cheetah watch is the first. opts: as Hunter's.
local function OwnHawk(w, ns, opts)
	Hunter(w, ns, opts)
	w.env.HUDiniDB.warnOwnBuff = true
	ns.ClassDB().buffSpells = { ["Aspect of the Hawk"] = 1800 }
end

-- The watch on these IDs, or nil.
local function BoxOn(w, id)
	for _, f in ipairs(w.boxes) do
		if f.enabled and (f.ids or {})[id] and not (f.ids or {})[HAWK] then return f end
	end
end

local function KeepBox(w)
	for _, f in ipairs(w.boxes) do
		if f.enabled and (f.ids or {})[HAWK] then return f end
	end
end

local function ArtX(w, box)
	local _, art = ClipOf(w, box)
	return select(4, art:GetPoint(1)), art
end

-- The picture the watch's art shows: its textures keep what HUDini sets,
-- then HUDini syncs again.
local function Texture(w, ns, box)
	local _, art = ClipOf(w, box)
	local kids = {}
	for _, f in ipairs(w.frames) do
		if f:GetParent() == art then
			kids[#kids + 1] = f
			f.SetTexture = function(self, v) self.shown = v end
		end
	end
	ns.UpdateBuffMissing()
	for _, f in ipairs(kids) do
		if type(f.shown) == "number" then return f.shown end
	end
end

H.test("Hunter: a fight starts with Aspect of the Cheetah on: the red Hawk icon by the health bar", function()
	local w, ns = World()
	Hunter(w, ns)
	On(w, HAWK)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	w.auras[HAWK] = nil
	On(w, CHEETAH)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	local away, keep = BoxOn(w, CHEETAH), KeepBox(w)
	H.ok(away and keep, "two watches: the keep-up list, and the aspects not for a fight")
	H.eq(Texture(w, ns, away), 1000 + HAWK, "the Hawk icon")
	H.ok(away.ids[CHEETAH] and away.ids[PACK], "Cheetah and Pack")
	H.eq(ClipOf(w, away):IsShown(), false, "out of a fight: no icon")
	StartFight(w)
	H.eq(Seen(w, ns, away), true, "Cheetah on in the fight: the icon")
	H.eq(Seen(w, ns, keep), false, "the keep-up icon: an aspect is on")
	local x, art = ArtX(w, away)
	H.eq(x, ArtX(w, keep), "the keep-up icon's spot")
	H.eq(x, 50 - 3 - 30, "by the health bar")
	H.eq(ns.BuffWatchSpots(), 1, "one spot held")
	H.ok(art:GetParent() == ClipOf(w, away), "the art in the clip")
	-- Hawk cast in the fight: Cheetah goes.
	w.auras[CHEETAH] = nil
	On(w, HAWK)
	GameSizes(w)
	H.eq(Seen(w, ns, away), false, "Hawk on: no icon")
	H.eq(Seen(w, ns, keep), false, "and no keep-up icon")
	w.auras[HAWK] = nil
	GameSizes(w)
	H.eq(Seen(w, ns, away), false, "no aspect: not this icon")
	H.eq(Seen(w, ns, keep), true, "the keep-up icon")
	On(w, PACK)
	GameSizes(w)
	H.eq(Seen(w, ns, away), true, "Pack on: the icon")
	EndFight(w)
	H.eq(Seen(w, ns, away), false, "after the fight: gone")
end)

H.test("the icon is the fight aspect seen or cast last, else the first you know", function()
	local w, ns = World()
	Hunter(w, ns)
	On(w, CHEETAH)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(Texture(w, ns, BoxOn(w, CHEETAH)), 1000 + HAWK, "none seen yet: the first you know")
	w.auras[CHEETAH] = nil
	On(w, MONKEY)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(Texture(w, ns, BoxOn(w, CHEETAH)), 1000 + MONKEY, "Monkey seen on you")
	w.auras[MONKEY] = nil
	On(w, CHEETAH)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(Texture(w, ns, BoxOn(w, CHEETAH)), 1000 + MONKEY, "Cheetah on now: still Monkey")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", HAWK)
	ns.UpdateBuffMissing()
	H.eq(Texture(w, ns, BoxOn(w, CHEETAH)), 1000 + HAWK, "Hawk cast")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", PACK)
	ns.UpdateBuffMissing()
	H.eq(Texture(w, ns, BoxOn(w, CHEETAH)), 1000 + HAWK, "Pack is not a fight aspect")
	w.known[HAWK] = nil
	w.known[MONKEY] = nil
	ns.UpdateBuffMissing()
	H.eq(BoxOn(w, CHEETAH), nil, "no fight aspect known: no watch")
end)

H.test("the game plays no sound as Cheetah leaves you", function()
	-- Hawk as a learned buff: no keep-up watch, so the Cheetah watch is
	-- there. Its game sounds, with and without the class's notInFight.
	local function Heard(notIn)
		local w, ns = World()
		OwnHawk(w, ns, { pick = { "Aspect of the Hawk" }, notIn = notIn })
		ns.ClassDB().keepUpSound = true
		On(w, CHEETAH)
		ns.UpdateIconAuras()
		ns.UpdateBuffMissing()
		local ids = {}
		for _, snd in ipairs(Sounds(w)) do ids[#ids + 1] = snd.info.spellID end
		table.sort(ids)
		return table.concat(ids, " "), BoxOn(w, CHEETAH) ~= nil, ns
	end
	local without = Heard({})
	local with, watch, ns = Heard(nil)
	H.eq(watch, true, "the Cheetah watch")
	H.eq(with, without, "it adds no game sound")
	H.eq(ns.GameSounds(ns.NOT_IN_FIGHT_KEY), false, "not the game's")
	local w
	-- In the keep-up pick: the game sounds for Cheetah, for the keep-up
	-- watch only.
	w, ns = World()
	Hunter(w, ns)
	ns.ClassDB().keepUpSound = true
	On(w, CHEETAH)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	StartFight(w)
	H.eq(ns.GameSounds(ns.KEEP_UP_KEY), true, "the keep-up watch's")
	H.eq(ns.GameSounds(ns.NOT_IN_FIGHT_KEY), false, "not this watch's")
	EndFight(w)
end)

H.test("no watch: the keep-up alert off, no read ID, or no notInFight", function()
	local w, ns = World()
	Hunter(w, ns, { keepUpOff = true })
	ns.UpdateBuffMissing()
	H.eq(BoxOn(w, CHEETAH), nil, "the keep-up alert off")
	w, ns = World()
	Hunter(w, ns, { ids = { ["Aspect of the Hawk"] = { [HAWK] = true } } })
	ns.UpdateBuffMissing()
	H.eq(BoxOn(w, CHEETAH), nil, "Cheetah and Pack never seen on you")
	H.ok(KeepBox(w), "the keep-up watch still")
	w, ns = World()
	Hunter(w, ns, { notIn = {} })
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "a class with none: the keep-up watch only")
end)

H.test("a keep-up pick without Cheetah: the keep-up icon alone tells it", function()
	local w, ns = World()
	Hunter(w, ns, { pick = { "Aspect of the Hawk" } })
	On(w, CHEETAH)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	local keep = KeepBox(w)
	H.ok(keep, "the keep-up watch")
	H.eq(BoxOn(w, CHEETAH), nil, "no second watch")
	StartFight(w)
	H.eq(Seen(w, ns, keep), true, "Cheetah on, so Hawk off: the keep-up icon")
	H.eq(ns.BuffWatchSpots(), 1, "one spot held")
	EndFight(w)
end)

-- Review finding 2 (TICK-0196): the "Combat buff to maintain" set to None.
H.test("the combat buff set to None: no icon for Cheetah either", function()
	local w, ns = World()
	Hunter(w, ns, { pick = false })
	On(w, CHEETAH)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(KeepBox(w), nil, "no keep-up watch")
	H.eq(BoxOn(w, CHEETAH), nil, "and no Cheetah watch")
	H.eq(#w.boxes == 0 or not w.boxes[1].enabled, true, "no container on")
end)

-- Review finding 1 (TICK-0196): a container that was a normal watch on a
-- spot and is now the inverse watch on that spot is placed again.
H.test("a container that turns into the Cheetah watch on the same spot hangs its clip again", function()
	local w, ns = World()
	OwnHawk(w, ns, { ids = { ["Aspect of the Hawk"] = { [HAWK] = true } } })
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(BoxOn(w, CHEETAH), nil, "Cheetah's ID not read yet: no Cheetah watch")
	local first = w.boxes[1]
	H.ok(first and first.enabled and first.ids[HAWK], "the Hawk watch on the first container")
	local clip = ClipOf(w, first)
	H.eq((clip:GetPoint(1)), "TOPLEFT", "a normal watch's clip")
	ns.ClassDB().auraSpellIDs["Aspect of the Cheetah"] = { [CHEETAH] = true }
	ns.UpdateBuffMissing()
	On(w, CHEETAH)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.ok(BoxOn(w, CHEETAH) == first, "the first container is the Cheetah watch now, on the same spot")
	H.eq((clip:GetPoint(1)), "TOPRIGHT", "hung again by its right edge")
	w.auras[CHEETAH] = nil
	StartFight(w)
	H.eq(Seen(w, ns, first), false, "Cheetah off: no icon")
	On(w, CHEETAH)
	GameSizes(w)
	H.eq(Seen(w, ns, first), true, "Cheetah on: the icon")
	EndFight(w)
end)

-- TICK-0197: a Druid's forms. Thorns (467) on the grid, learned with no
-- length known (a trackBuff seed: it counts out of a fight too), its ID
-- read. The class file's formQuiet = { "Travel Form" } and formQuietSound
-- = { "Bear Form" }. w.form: the spell ID of the form you are in; the
-- form's aura is on you with it.
local THORNS, TRAVEL, BEAR = 467, 783, 5487

local function Druid(w, ns)
	local db = w.env.HUDiniDB
	db.warnKeepUp = true
	w.known = { [THORNS] = true, [TRAVEL] = true, [BEAR] = true }
	ns.ClassDB().buffSpells = { ["Thorns"] = true }
	ns.ClassDB().auraSpellIDs = { ["Thorns"] = { [THORNS] = true } }
	ns.HUDini.spells = { { spellID = THORNS, slot = 1, auraNames = { "Thorns" } } }
	local file = { formQuiet = { "Travel Form" }, formQuietSound = { "Bear Form" } }
	local default = ns.ClassDefault
	ns.ClassDefault = function(key)
		if file[key] ~= nil then return file[key] end
		return default(key)
	end
	w.env.GetShapeshiftFormID = function() return w.form and 1 or nil end
	w.env.GetShapeshiftForm = function() return w.form and 1 or 0 end
	w.env.GetShapeshiftFormInfo = function(i)
		if i == 1 and w.form then return 1000, true, true, w.form end
	end
end

-- Turn into a form (nil: back to caster form), as the game tells it.
local function Form(w, ns, id)
	if w.form then w.auras[w.form] = nil end
	w.form = id
	if id then On(w, id) end
	ns.UpdateIconAuras()
	GameSizes(w)
end

H.test("Druid: in Travel Form with Thorns off, no buff-missing icon", function()
	local w, ns = World()
	Druid(w, ns)
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, THORNS, "caster form, Thorns off: the icon")
	Form(w, ns, TRAVEL)
	H.eq(ns.missingBuffID, nil, "Travel Form: no icon")
	H.eq(ns.buffMissing, false, "nothing missing: the HUD can hide")
	Form(w, ns, BEAR)
	H.eq(ns.missingBuffID, THORNS, "Bear Form keeps the icon")
	Form(w, ns, nil)
	H.eq(ns.missingBuffID, THORNS, "caster form again: the icon")
end)

H.test("Druid in a fight: Travel Form cuts the watch's icon away; the sound stays on Thorns", function()
	local w, ns = World()
	Druid(w, ns)
	ns.ClassDB().keepUpSound = true
	On(w, THORNS)
	ns.UpdateIconAuras()
	local box = w.boxes[1]
	H.ok(box and box.enabled, "a watch for Thorns")
	H.ok(box.ids[THORNS] and box.ids[TRAVEL], "on Thorns and Travel Form")
	H.eq(box.ids[BEAR], nil, "not Bear Form: its icon stays")
	local ids = {}
	for _, snd in ipairs(Sounds(w)) do ids[#ids + 1] = snd.info.spellID end
	H.eq(table.concat(ids, " "), tostring(THORNS), "the game sounds for Thorns only")
	StartFight(w)
	w.auras[THORNS] = nil
	GameSizes(w)
	H.eq(Seen(w, ns, box), true, "Thorns off: the icon")
	Form(w, ns, TRAVEL)
	H.eq(Seen(w, ns, box), false, "Travel Form: no icon")
	Form(w, ns, nil)
	H.eq(Seen(w, ns, box), true, "caster form: the icon again")
	EndFight(w)
end)

H.test("Druid in Bear Form: no buff-missing sound in a fight; the icon stays", function()
	local w, ns = World()
	Druid(w, ns)
	ns.ClassDB().keepUpSound = true
	On(w, THORNS)
	ns.UpdateIconAuras()
	H.eq(#Sounds(w), 1, "caster form: the game sounds for Thorns")
	Form(w, ns, BEAR)
	H.eq(#Sounds(w), 0, "Bear Form: taken back, so a fight started in it has none")
	w.auras[THORNS] = nil
	ns.UpdateIconAuras()
	StartFight(w)
	H.eq(ns.missingBuffID, THORNS, "the icon stays")
	H.eq(Seen(w, ns, w.boxes[1]), true, "the watch shows it")
	H.eq(#w.played, 0, "HUDini plays no sound either")
	Form(w, ns, nil)
	H.eq(#w.played, 1, "caster form in the fight, Thorns off: the sound now")
	EndFight(w)
	On(w, THORNS)
	ns.UpdateIconAuras()
	H.eq(#Sounds(w), 1, "caster form after the fight: the game's sound again")
end)

H.test("Druid: the keep-up watch takes Travel Form too", function()
	local w, ns = World()
	Druid(w, ns)
	w.env.HUDiniDB.warnOwnBuff = false
	ns.ClassDB().buffSpells = {}
	local value = ns.ClassValue
	ns.ClassValue = function(key)
		if key == "keepUp" then return { "Thorns" } end
		return value(key)
	end
	ns.UpdateBuffMissing()
	local box
	for _, f in ipairs(w.boxes) do if f.enabled and (f.ids or {})[THORNS] then box = f end end
	H.ok(box and box.ids[TRAVEL], "on Thorns and Travel Form")
	H.eq(box.ids[BEAR], nil, "not Bear Form")
end)

H.test("a quiet form never joins an inverse watch: a travel aspect's red icon is not the form's", function()
	local w, ns = World()
	Hunter(w, ns)
	local default = ns.ClassDefault
	ns.ClassDefault = function(key)
		if key == "formQuiet" then return { "Travel Form" } end
		return default(key)
	end
	w.known[TRAVEL] = true
	ns.UpdateBuffMissing()
	local inv = BoxOn(w, CHEETAH)
	H.ok(inv, "the inverse watch")
	H.eq(inv.ids[TRAVEL], nil, "not on Travel Form")
	H.ok(KeepBox(w).ids[TRAVEL], "the keep-up watch is")
end)

-- TICK-0192: the class file's pet.buffs (the Warlock's Soul Link).
-- Lightning Shield stands in for it, learned at 3600 s so it counts out of
-- a fight too. w.pet: "alive", "dead" or nil (none out). w.petThrows: the
-- game will not answer for the pet; w.deadThrows: nor for its death.
-- w.secretRead = "exists" or "dead": that read's answer is secret. Util.lua
-- takes issecretvalue at load, so the next ns.IsSecret after that read
-- (PetOut's own check, right after it) says secret. The answer itself is
-- the one that would hold the buff if it were read plain: no pet, or dead.
local function PetBuff(w, ns)
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 3600 }
	local default = ns.ClassDefault
	ns.ClassDefault = function(key)
		if key == "pet" then return { buffs = { "Lightning Shield" } } end
		return default(key)
	end
	w.env.UnitExists = function(u)
		if u == "pet" and w.petThrows then error("no answer") end
		if u == "pet" and w.secretRead == "exists" then
			w.secretNext = true
			return false
		end
		return u == "player" or (u == "pet" and w.pet ~= nil)
	end
	w.env.UnitIsDead = function(u)
		if u == "pet" and w.deadThrows then error("no answer") end
		if u == "pet" and w.secretRead == "dead" then
			w.secretNext = true
			return true
		end
		return u == "pet" and w.pet == "dead"
	end
	local isSecret = ns.IsSecret
	ns.IsSecret = function(v)
		if w.secretNext then
			w.secretNext = false
			return true
		end
		return isSecret(v)
	end
	local update, n = ns.UpdateBuffMissing, 0
	ns.UpdateBuffMissing = function(...)
		n = n + 1
		return update(...)
	end
	return function() local was = n n = 0 return was end
end

H.test("TICK-0192: a pet buff off with no live pet out: no icon and no watch; a pet out: both", function()
	local w, ns = World()
	local checks = PetBuff(w, ns)
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "no pet out: no icon")
	H.eq(ns.buffMissing, false, "nothing missing: the HUD can hide")
	H.eq(BoxOn(w, 324), nil, "no watch for it")
	checks()
	w.pet = "alive"
	w:fire("UNIT_PET", "player")
	H.eq(checks(), 1, "a pet comes: one check")
	H.eq(ns.missingBuffID, 324, "a pet out: the icon")
	H.ok(BoxOn(w, 324), "and its watch")
	w:fire("UNIT_FLAGS", "pet")
	H.eq(checks(), 0, "the same pet: no check")
	w.pet = "dead"
	w:fire("UNIT_FLAGS", "pet")
	H.eq(checks(), 1, "the pet dies: one check")
	H.eq(ns.missingBuffID, nil, "a dead pet: no icon")
	H.eq(BoxOn(w, 324), nil, "no watch")
	w.pet = nil
	w:fire("UNIT_PET", "player")
	H.eq(ns.missingBuffID, nil, "its corpse gone: still no icon")
end)

H.test("TICK-0192: a pet the game will not answer for counts as out; off the grid too; a buff not in the list is not held", function()
	local w, ns = World()
	PetBuff(w, ns)
	w.petThrows = true
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 324, "no answer: the buff counts, as before")
	w.petThrows = false
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "no pet: held")
	ns.HUDini.spells = {}
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "off the grid, no pet: held too")
	w.pet = "alive"
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 324, "off the grid, a pet out: the icon")
	w.pet = nil
	local default = ns.ClassDefault
	ns.ClassDefault = function(key)
		if key == "pet" then return { buffs = { "Soul Link" } } end
		return default(key)
	end
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 324, "Lightning Shield is not a pet buff: the icon")
	H.ok(BoxOn(w, 324), "and its watch")
end)

H.test("TICK-0192: a secret pet answer, or a death the game will not tell, counts as a live pet out", function()
	local w, ns = World()
	PetBuff(w, ns)
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "plain: no pet, held")
	w.secretRead = "exists"
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 324, "UnitExists secret: the buff counts")
	H.ok(BoxOn(w, 324), "and its watch")
	-- Another reader of the pet (the pet icon) can leave the flag up.
	w.secretRead, w.secretNext, w.pet = nil, false, "dead"
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "plain: a dead pet, held")
	w.secretRead = "dead"
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 324, "UnitIsDead secret: the buff counts")
	w.secretRead, w.secretNext, w.deadThrows = nil, false, true
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 324, "UnitIsDead throws: the buff counts")
end)

H.test("TICK-0192: the pet's answer at login is the one the next pet event compares with", function()
	local w, ns = World()
	local checks = PetBuff(w, ns)
	w.pet = "alive"
	w:fire("PLAYER_ENTERING_WORLD")
	checks()
	w:fire("UNIT_FLAGS", "pet")
	H.eq(checks(), 0, "the same pet as at login: no check")
end)

H.test("TICK-0192: a class with no pet buffs does not check again on a pet event", function()
	local w, ns = World()
	local update, n = ns.UpdateBuffMissing, 0
	ns.UpdateBuffMissing = function(...) n = n + 1 return update(...) end
	w.env.UnitExists = function(u) return u == "player" or u == "pet" end
	w:fire("UNIT_PET", "player")
	H.eq(n, 0, "no check")
end)

-- The client gives no ID for a name while w.noName[name] (a spell you do not
-- know yet, or a loading screen).
local function HideName(w, name)
	if not w.noName then
		w.noName = {}
		local info = w.env.C_Spell.GetSpellInfo
		w.env.C_Spell.GetSpellInfo = function(n)
			if w.noName[n] then return nil end
			return info(n)
		end
	end
	w.noName[name] = true
end

local function ThornsBox(w)
	for _, f in ipairs(w.boxes) do
		if f.enabled and (f.ids or {})[THORNS] then return f end
	end
end

H.test("Travel Form learned after the Thorns watch: the watch takes it after SPELLS_CHANGED", function()
	local w, ns = World()
	Druid(w, ns)
	w.known[TRAVEL] = nil
	HideName(w, "Travel Form")
	On(w, THORNS)
	ns.UpdateIconAuras()
	H.eq(ThornsBox(w).ids[TRAVEL], nil, "not known yet: not on Travel Form")
	w.known[TRAVEL], w.noName["Travel Form"] = true, nil
	w:fire("SPELLS_CHANGED")
	ns.UpdateBuffMissing()
	H.ok(ThornsBox(w).ids[TRAVEL], "learned: on Travel Form too")
	StartFight(w)
	w.auras[THORNS] = nil
	Form(w, ns, TRAVEL)
	H.eq(Seen(w, ns, ThornsBox(w)), false, "in a fight in Travel Form: no icon")
	EndFight(w)
end)

H.test("one lookup of Travel Form with no answer: the watch keeps it", function()
	local w, ns = World()
	Druid(w, ns)
	On(w, THORNS)
	ns.UpdateIconAuras()
	local box = ThornsBox(w)
	H.ok(box.ids[TRAVEL], "on Travel Form")
	HideName(w, "Travel Form")
	ns.UpdateBuffMissing()
	H.ok(ThornsBox(w) and ThornsBox(w).ids[TRAVEL], "a loading screen: still on Travel Form")
end)

H.test("the form read throws: Thorns still counts as missing, and the next pass reads the form again", function()
	local w, ns = World()
	Druid(w, ns)
	ns.UpdateBuffMissing()
	local name = w.env.C_Spell.GetSpellName
	w.env.C_Spell.GetSpellName = function(id)
		if id == TRAVEL then error("no name now") end
		return name(id)
	end
	w.form = TRAVEL
	local okU, errU = pcall(ns.UpdateBuffMissing); H.ok(okU, "no Lua error out of the update: " .. tostring(errU))
	H.eq(ns.missingBuffID, THORNS, "the form unknown: the icon stays")
	w.env.C_Spell.GetSpellName = name
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "the form read again: Travel Form, no icon")
end)
