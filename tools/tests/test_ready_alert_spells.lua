-- Ready alerts for any learned spell with a cooldown (TICK-0162, D-042).
-- The page offers the class file's readyAlert list first, then every spell
-- in your spellbook with a cooldown of its own, A to Z, each off until you
-- turn it on. The book is read only out of a fight. What the page looks
-- like, and that this client gives each answer, needs DK's play.

-- Test class profiles, not the live class files (classes_fixture.lua).
local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

local EARTH, FLAME, FROST, BOLT, SHIELD = 8042, 8050, 8056, 403, 324
local REINC, PERK, PASSIVE, OFFSPEC, CHARGED = 20608, 83958, 16176, 51490, 61295

-- A level 13 Shaman's spellbook. One entry each: its name, ID, base
-- cooldown in ms, and flags. Frost Shock is not learned yet (a future
-- spell). The guild line holds a perk with a cooldown.
local function Book()
	return {
		{ name = "General", items = {
			{ name = "Lightning Bolt", id = BOLT, cd = 0 },
			{ name = "Reincarnation", id = REINC, cd = 1800000 },
		} },
		{ name = "Elemental", items = {
			{ name = "Earth Shock", id = EARTH, cd = 6000 },
			{ name = "Flame Shock", id = FLAME, cd = 6001 },
			{ name = "Frost Shock", id = FROST, cd = 6002, future = true },
			{ name = "Lightning Shield", id = SHIELD, cd = 0 },
			{ name = "Ancestral Healing", id = PASSIVE, cd = 5000, passive = true },
			{ name = "Thunderstorm", id = OFFSPEC, cd = 45000, offSpec = true },
			{ name = "Riptide", id = CHARGED, cd = 0, charges = 2 },
		} },
		{ name = "Guild", guild = true, items = {
			{ name = "Mass Resurrection", id = PERK, cd = 600000 },
		} },
	}
end

-- w.book is the spellbook (Book()). w.cd[id] is what GetSpellCooldown
-- answers. w.sounds logs each PlaySound. w.secret holds the values the
-- game hides. w.bookReads counts reads of a book entry.
local function World(setup)
	local w = H.world()
	local env = w.env
	w.class, w.className = "SHAMAN", "Shaman"
	w.secret, w.sounds, w.book, w.cd, w.bookReads = {}, {}, Book(), {}, 0
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
	env.Enum.SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 }
	-- Each entry by its place in the book, as the game numbers them.
	local function Entries()
		local all = {}
		for _, line in ipairs(w.book) do
			for _, e in ipairs(line.items) do all[#all + 1] = e end
		end
		return all
	end
	local function ByName(name)
		for _, e in ipairs(Entries()) do
			if e.name == name then return e end
		end
	end
	local function ByID(id)
		for _, e in ipairs(Entries()) do
			if e.id == id then return e end
		end
	end
	env.C_SpellBook = {
		GetNumSpellBookSkillLines = function() return #w.book end,
		GetSpellBookSkillLineInfo = function(l)
			local offset = 0
			for i = 1, l - 1 do offset = offset + #w.book[i].items end
			local line = w.book[l]
			return { name = line.name, itemIndexOffset = offset, numSpellBookItems = #line.items,
				isGuild = line.guild or false, shouldHide = false }
		end,
		GetSpellBookItemInfo = function(i, bank)
			w.bookReads = w.bookReads + 1
			if bank ~= 0 then return nil end
			local e = Entries()[i]
			if not e then return nil end
			if e.throws then error("not loaded") end
			return { name = e.name, spellID = e.id, isPassive = e.passive or false,
				isOffSpec = e.offSpec or false, itemType = e.future and 2 or 1 }
		end,
	}
	env.GetSpellBaseCooldown = function(id)
		local e = ByID(id)
		if e then return e.cd, 1500 end -- nil: no answer yet
		return 0, 1500
	end
	env.C_Spell.GetSpellInfo = function(name)
		local e = ByName(name)
		if e then return { spellID = e.id, name = e.name } end
	end
	env.C_Spell.GetSpellName = function(id)
		local e = ByID(id)
		return e and e.name
	end
	env.C_Spell.GetSpellCooldown = function(id)
		return w.cd[id] or { isEnabled = true, isActive = false, isOnGCD = false }
	end
	env.C_Spell.GetSpellCharges = function(id)
		local e = ByID(id)
		if e and e.charges then return { maxCharges = e.charges, isActive = false } end
	end
	env.C_Spell.GetOverrideSpell = function(id) return id end
	env.IsPlayerSpell = function(id)
		local e = ByID(id)
		return e ~= nil and not e.future
	end
	env.PlaySound = function(kit) table.insert(w.sounds, kit) return true end
	if setup then setup(w) end
	Classes.Use(w)
	local ns = w:loadAddon()
	return ns, w
end

local function Index(list, name)
	for i, n in ipairs(list) do
		if n == name then return i end
	end
end

H.test("ready alert spells: the class list first, then each learned spell with a cooldown, A to Z", function()
	local ns = World()
	local list, classCount = ns.ReadyAlertSpells()
	H.eq(classCount, 4, "the Shaman class file offers four")
	H.eq(table.concat(list, ", "), "Heroism, Bloodlust, Mana Tide Totem, Reincarnation, "
		.. "Earth Shock, Flame Shock, Riptide", "the class list, then the rest A to Z")
	H.eq(Index(list, "Lightning Bolt"), nil, "no cooldown: not offered")
	H.eq(Index(list, "Lightning Shield"), nil, "no cooldown: not offered")
	H.eq(Index(list, "Frost Shock"), nil, "not learned yet: not offered")
	H.eq(Index(list, "Ancestral Healing"), nil, "passive: not offered")
	H.eq(Index(list, "Thunderstorm"), nil, "your other spec: not offered")
	H.eq(Index(list, "Mass Resurrection"), nil, "a guild perk: not offered")
	H.eq(Index(list, "Riptide"), 7, "two charges count as a cooldown")
end)

H.test("ready alert spells: every row is off until you turn it on", function()
	local ns = World()
	for _, name in ipairs((ns.ReadyAlertSpells())) do
		H.eq(ns.GetReadyAlert(name), false, name .. " is off")
	end
	H.eq(ns.SetReadyAlert("Earth Shock", true), true, "turned on")
	H.eq(ns.GetReadyAlert("Earth Shock"), true, "on")
	H.eq(ns.GetReadyAlert("Flame Shock"), false, "the other shock stays off")
end)

H.test("ready alert spells: a spell turned on but not in the book stays on the list, A to Z", function()
	local ns = World(function(w)
		w.env.HUDiniDB = { classes = { SHAMAN = { readyAlerts = { ["Astral Recall"] = true } } } }
	end)
	local list = ns.ReadyAlertSpells()
	H.eq(table.concat(list, ", ", 5), "Astral Recall, Earth Shock, Flame Shock, Riptide", "merged A to Z")
end)

-- A watcher that counts each time the list changes.
local function Watch(ns, w)
	w:runTimers() -- any read the login itself started
	local seen = { n = 0 }
	ns.WatchLearnedCooldowns(function() seen.n = seen.n + 1 end)
	return seen
end

H.test("ready alert spells: the book is read only out of a fight, and again after SPELLS_CHANGED", function()
	local ns, w = World(function(w) w.combat = true end)
	w:takeBlocked() -- a /reload in a fight: the click bars wait, as in the game
	local seen = Watch(ns, w)
	local list = ns.ReadyAlertSpells()
	H.eq(#list, 4, "first ask in a fight (a /reload in a fight): the class list only")
	H.eq(w.bookReads, 0, "the book is not read in a fight")
	-- The fight ends: the book is read, and the page is told.
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.ok(w.bookReads > 0, "read when the fight ends")
	H.eq(seen.n, 1, "the page is told once")
	H.eq(#ns.ReadyAlertSpells(), 7, "the book's spells now")
	local reads = w.bookReads
	ns.ReadyAlertSpells()
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.eq(w.bookReads, reads, "kept: not read again with no change")
	-- Level 20: Frost Shock is learned, in a fight.
	w.book[2].items[3].future = nil
	w.combat = true
	w:fire("SPELLS_CHANGED")
	w:runTimers()
	H.eq(Index(ns.ReadyAlertSpells(), "Frost Shock"), nil, "in the fight: the last list")
	H.eq(w.bookReads, reads, "still not read in the fight")
	H.eq(seen.n, 1, "the page is not told in the fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.eq(seen.n, 2, "after it: the page is told")
	H.eq(Index(ns.ReadyAlertSpells(), "Frost Shock"), 7, "Frost Shock, A to Z")
end)

H.test("ready alert spells: SPELLS_CHANGED out of a fight reads the book once, a moment later", function()
	local ns, w = World()
	local seen = Watch(ns, w)
	ns.ReadyAlertSpells()
	local reads = w.bookReads
	-- Many events in a row (a new level): one read.
	w.book[2].items[3].future = nil
	for _ = 1, 5 do w:fire("SPELLS_CHANGED") end
	H.eq(w.bookReads, reads, "not read at the event itself")
	w:runTimers()
	H.eq(w.bookReads, reads + #w.book[1].items + #w.book[2].items, "one read of the book")
	H.eq(seen.n, 1, "the page is told: Frost Shock is new")
	-- A form change: SPELLS_CHANGED, same spells.
	w:fire("SPELLS_CHANGED")
	w:runTimers()
	H.eq(seen.n, 1, "the same list: the page is not told")
end)

H.test("ready alert spells: an empty book at login is read again, and Earth Shock is offered", function()
	-- At ADDON_LOADED the game may not have filled the book yet.
	local full
	local ns, w = World(function(w)
		full = w.book
		w.book = { { name = "General", items = {} } }
	end)
	local seen = Watch(ns, w)
	H.eq(#ns.ReadyAlertSpells(), 4, "an empty book: the class list")
	w.book = full
	H.eq(Index(ns.ReadyAlertSpells(), "Earth Shock"), 5, "an empty book is unsure: read again when asked")
	-- The same, with the page built at load and only the event after it.
	ns, w = World(function(w)
		full = w.book
		w.book = {}
	end)
	seen = Watch(ns, w)
	H.eq(#ns.ReadyAlertSpells(), 4, "no lines: the class list")
	w.book = full
	w:fire("SPELLS_CHANGED")
	w:runTimers()
	H.eq(seen.n, 1, "the page is told to build its rows again")
	H.eq(Index(ns.ReadyAlertSpells(), "Earth Shock"), 5, "Earth Shock is offered")
end)

-- A World with one answer hidden or broken by setup(w); clear(w) mends it.
-- The spell is left out with no error, and offered at the next ask.
local function Unsure(setup, clear, what)
	local ns, w = World(setup)
	local ok, list = pcall(ns.ReadyAlertSpells)
	H.eq(ok, true, what .. ": no error: " .. tostring(list))
	H.eq(Index(list, "Earth Shock"), nil, what .. ": left out")
	H.ok(Index(list, "Flame Shock"), what .. ": the other shock still offered")
	clear(w)
	H.ok(Index(ns.ReadyAlertSpells(), "Earth Shock"), what .. ": read again, now offered")
end

H.test("ready alert spells: a secret or failed answer leaves that spell out and reads the book again", function()
	local ns = World()
	H.ok(Index(ns.ReadyAlertSpells(), "Earth Shock"), "plain: offered")
	local earth = function(w) return w.book[2].items[1] end
	Unsure(function(w) w.secret[6000] = true end,
		function(w) w.secret[6000] = nil end, "a secret base cooldown")
	Unsure(function(w) earth(w).cd = nil end,
		function(w) earth(w).cd = 6000 end, "no base cooldown answer")
	Unsure(function(w) w.secret["Earth Shock"] = true end,
		function(w) w.secret["Earth Shock"] = nil end, "a secret name")
	Unsure(function(w) earth(w).id = 0.25; w.secret[0.25] = true end,
		function(w) earth(w).id = EARTH end, "a secret spell ID")
	Unsure(function(w) earth(w).passive = 0.5; w.secret[0.5] = true end,
		function(w) earth(w).passive = nil end, "a secret flag")
	Unsure(function(w) earth(w).throws = true end,
		function(w) earth(w).throws = nil end, "an entry that throws")
	-- Riptide's charges secret (it has no base cooldown).
	local ns2, w2 = World(function(w) w.secret[2] = true end)
	local ok, list = pcall(ns2.ReadyAlertSpells)
	H.eq(ok, true, "secret charges: no error: " .. tostring(list))
	H.eq(Index(list, "Riptide"), nil, "secret charges: left out")
	w2.secret[2] = nil
	H.ok(Index(ns2.ReadyAlertSpells(), "Riptide"), "secret charges: read again, now offered")
	-- GetSpellCharges throws: the book is still read, Earth Shock offered.
	ns2, w2 = World(function(w) w.env.C_Spell.GetSpellCharges = function() error("not loaded") end end)
	ok, list = pcall(ns2.ReadyAlertSpells)
	H.eq(ok, true, "charges throw: no error: " .. tostring(list))
	H.ok(Index(list, "Earth Shock"), "charges throw: a base cooldown still counts")
	H.eq(Index(list, "Riptide"), nil, "charges throw: Riptide left out")
	-- A plain 0 is a real answer: kept, not read again.
	local w
	ns, w = World()
	ns.ReadyAlertSpells()
	local reads = w.bookReads
	ns.ReadyAlertSpells()
	H.eq(w.bookReads, reads, "plain answers: not read again")
end)

H.test("ready alert spells: a client with no spellbook API offers the class list, no error", function()
	local ns = World(function(w) w.env.C_SpellBook = nil end)
	local list, classCount = ns.ReadyAlertSpells()
	H.eq(#list, 4, "the class list")
	H.eq(classCount, 4, "all of it the class file's")
end)

-- Cast: the game starts the spell's own cooldown and says so in the event.
local function Cast(w, id)
	w.cd[id] = { isEnabled = true, isActive = true, isOnGCD = false }
	w:fire("SPELL_UPDATE_COOLDOWN", id, id)
end

H.test("ready alert spells: Earth Shock turned on rings when it is ready again, in a fight", function()
	local ns, w = World()
	ns.SetReadyAlert("Earth Shock", true)
	w.combat = true
	Cast(w, EARTH)
	H.eq(#w.sounds, 0, "no sound while it cools down")
	w.time = w.time + 6
	w.cd[EARTH].isActive = false
	w:runTickers()
	H.eq(#w.sounds, 1, "the bell when it is ready")
end)

H.test("ready alert spells: the shocks' shared cooldown rings once per spell turned on, not once per shock", function()
	-- Only Earth Shock on. Flame Shock is cast; the shared cooldown lands
	-- on all three shocks one frame later.
	local ns, w = World()
	w.book[2].items[3].future = nil
	ns.SetReadyAlert("Earth Shock", true)
	w.cd[FLAME] = { isEnabled = true, isActive = true, isOnGCD = false }
	w:fire("SPELL_UPDATE_COOLDOWN", FLAME, FLAME)
	w.cd[EARTH] = { isEnabled = true, isActive = true, isOnGCD = false }
	w.cd[FROST] = { isEnabled = true, isActive = true, isOnGCD = false }
	w:runTimers()
	w.time = w.time + 6
	for _, id in ipairs({ EARTH, FLAME, FROST }) do w.cd[id].isActive = false end
	w:runTickers()
	H.eq(#w.sounds, 1, "one bell: only Earth Shock is on")
	-- Earth Shock and Flame Shock on: one bell each.
	ns.SetReadyAlert("Flame Shock", true)
	Cast(w, EARTH)
	w.cd[FLAME] = { isEnabled = true, isActive = true, isOnGCD = false }
	w:runTimers()
	w.time = w.time + 6
	for _, id in ipairs({ EARTH, FLAME, FROST }) do w.cd[id].isActive = false end
	w:runTickers()
	H.eq(#w.sounds, 3, "two more: one for each spell turned on")
end)
