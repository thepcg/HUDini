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
	[20154] = "Seal of Righteousness" }

local function World(opts)
	opts = opts or {}
	local w = H.world()
	local env = w.env
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
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
-- size the game gave the container.
local function Seen(w, ns, box)
	local hud = ns.HUDini
	local clip, art = ClipOf(w, box)
	H.ok(clip and art, "the watch has its clip and its art")
	local p, rel, rp, bx = box:GetPoint(1)
	H.ok(p == "TOPLEFT" and rel == hud and rp == "TOPLEFT", "the container on the anchor")
	local cp, _, crp, cx = clip:GetPoint(1)
	H.ok(cp == "TOPLEFT" and crp == "TOPRIGHT", "the clip off the container's right edge")
	local ap, arel, arp, ax = art:GetPoint(1)
	H.ok(ap == "TOPLEFT" and arel == hud and arp == "TOPLEFT", "the art on the anchor")
	H.eq(clip.__h.clips, true, "the clip cuts its children")
	local left = bx + box:GetWidth() + cx
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

H.test("a keep-up list of two buffs: one watch on both, no game sound", function()
	local w, ns = World()
	w.known = { [11426] = true, [1463] = true }
	local db = w.env.HUDiniDB
	db.warnOwnBuff, db.warnKeepUp = false, true
	ns.ClassDB().keepUpSound = true
	ns.ClassDB().auraSpellIDs = { ["Ice Barrier"] = { [11426] = true }, ["Mana Shield"] = { [1463] = true } }
	local value = ns.ClassValue
	ns.ClassValue = function(key)
		if key == "keepUp" then return { "Ice Barrier", "Mana Shield" } end
		return value(key)
	end
	On(w, 1463)
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one container")
	H.ok(w.boxes[1].ids[11426] and w.boxes[1].ids[1463], "both IDs")
	StartFight(w)
	H.eq(Seen(w, ns, w.boxes[1]), false, "one of them on: no icon")
	w.auras[1463] = nil
	GameSizes(w)
	H.eq(Seen(w, ns, w.boxes[1]), true, "both off: the icon")
	H.eq(#Sounds(w), 0, "one ending does not mean both are off: no game sound")
end)

H.test("a keep-up list with a buff not yet read: no watch (that buff on could not hide it)", function()
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
	H.eq(#w.boxes, 0, "no container")
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

H.test("your own buff with two names: no game sound (one ending is not both off)", function()
	local w, ns = World()
	w.known = { [324] = true, [1463] = true }
	ns.ClassDB().keepUpSound = true
	w.env.HUDiniDB.auraMap = { ["Lightning Shield"] = { "Mana Shield" } }
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true }, ["Mana Shield"] = { [1463] = true } }
	On(w, 324)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.eq(#w.boxes, 1, "one watch")
	H.ok(w.boxes[1].ids[324] and w.boxes[1].ids[1463], "on both names")
	StartFight(w)
	H.eq(#Sounds(w), 0, "no game sound")
	H.eq(ns.GameSounds("Lightning Shield"), false, "HUDini's path")
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
