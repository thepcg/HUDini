-- Tracking buffs (TICK-0056): Sense Undead, Find Herbs and the like say what
-- the minimap shows. They are never buffs to keep up.

local NAMES = {
	[1] = "Devotion Aura",     -- a no-end buff to keep up
	[2] = "Sense Undead",      -- tracking, on the English list
	[3] = "Kräuter suchen",    -- tracking, known only from the minimap list
	[4] = "Track Beasts",
	[5] = "Arcane Intellect",  -- a long timed buff to keep up
}

-- A world with buffs on you: auras[name] = duration (0 = no end). The grid
-- holds the spell IDs in grid; your own timed buffs are timed (names).
local function World(opts)
	local w = H.world()
	if opts.secret then
		w.env.issecretvalue = type(opts.secret) == "function" and opts.secret
			or function(v) return v == "SECRET" end
	end
	local env = w.env
	env.HUDiniDB = opts.db
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id } end
		end
	end
	env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end

	local auras = opts.auras or {}
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		local d = auras[name]
		if d then return { auraInstanceID = 7, duration = d, expirationTime = d > 0 and 2000 or 0 } end
	end
	local timed = opts.timed or {}
	env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
		local name = timed[i]
		if not name then return nil end
		local id
		for k, n in pairs(NAMES) do if n == name then id = k end end
		return { name = name, spellId = id, duration = auras[name] }
	end

	-- An entry is a table (12.x) or a function that gives the older
	-- multi-return shape: name, texture, active, kind.
	local list = opts.minimap or {}
	w.minimap = list
	w.reads = 0
	env.C_Minimap = {
		GetNumTrackingTypes = function()
			if w.count ~= nil then return w.count end
			return #list
		end,
		GetTrackingInfo = function(i)
			w.reads = w.reads + 1
			local e = list[i]
			if type(e) == "function" then return e() end
			return e
		end,
	}

	w:loadAddon()
	local hud = w.ns.HUDini
	hud.spells = {}
	for _, id in ipairs(opts.grid or {}) do hud.spells[#hud.spells + 1] = { spellID = id, row = 0, col = 0 } end
	return w, w.ns
end

local function Learned(ns)
	return ns.ClassDB().buffSpells or {}
end

H.test("a tracking buff on the grid is never learned; a paladin aura is", function()
	local w, ns = World({
		grid = { 1, 2, 4 },
		auras = { ["Devotion Aura"] = 0, ["Sense Undead"] = 0, ["Track Beasts"] = 0 },
	})
	ns.UpdateBuffMissing()
	local learned = Learned(ns)
	H.eq(learned["Devotion Aura"], true, "the paladin aura is learned")
	H.eq(learned["Sense Undead"], nil, "Sense Undead")
	H.eq(learned["Track Beasts"], nil, "Track Beasts")
end)

H.test("a timed tracking buff is never learned; a long timed buff is", function()
	local w, ns = World({
		auras = { ["Track Beasts"] = 3600, ["Arcane Intellect"] = 1800 },
		timed = { "Track Beasts", "Arcane Intellect" },
	})
	ns.UpdateBuffMissing()
	local learned = Learned(ns)
	H.eq(learned["Arcane Intellect"], true, "Arcane Intellect is learned")
	H.eq(learned["Track Beasts"], nil, "Track Beasts")
end)

H.test("the minimap's tracking list counts, in the client's own language", function()
	local w, ns = World({
		grid = { 3 },
		auras = { ["Kräuter suchen"] = 0 },
		minimap = {
			{ name = "Kräuter suchen", type = "spell" },
			{ name = "Devotion Aura", type = "other" },   -- a town service kind never counts
			function() return "Erze suchen", 136025, false, "spell" end,   -- the older shape
			function() return "Bankier", 136026, true, "other" end,
			{ name = "Frost Armor" },                     -- no kind: never counts
			{ name = "Frost Ward", type = "toy" },          -- only kind "spell" counts
		},
	})
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Kräuter suchen"], nil, "the minimap's tracking spell")
	H.eq(ns.IsTrackingBuff("Erze suchen"), true, "the older shape's tracking spell")
	H.eq(ns.IsTrackingBuff("Bankier"), false, "the older shape's \"other\" entry")
	H.eq(ns.IsTrackingBuff("Frost Armor"), false, "an entry with no kind")
	H.eq(ns.IsTrackingBuff("Frost Ward"), false, "a kind other than \"spell\"")

	-- The "other" kind is not a tracking spell, so the paladin aura still counts.
	ns.HUDini.spells = { { spellID = 1, row = 0, col = 0 } }
	w.env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if name == "Devotion Aura" then return { auraInstanceID = 8, duration = 0, expirationTime = 0 } end
	end
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Devotion Aura"], true, "an \"other\" entry is not tracking")
end)

H.test("a tracking buff learned before is dropped at login; the rest stay", function()
	local db = { classes = {} }
	local w, ns = World({ db = db })
	local mine = ns.ClassDB()
	mine.buffSpells = { ["Sense Undead"] = true, ["Find Herbs"] = true, ["Frost Armor"] = true }

	-- The next login, the same saved settings.
	local w2, ns2 = World({ db = w.env.HUDiniDB })
	local learned = Learned(ns2)
	H.eq(learned["Sense Undead"], nil, "Sense Undead dropped")
	H.eq(learned["Find Herbs"], nil, "Find Herbs dropped")
	H.eq(learned["Frost Armor"], true, "Frost Armor stays")

	-- Nothing missing for it, and nothing left to drop after that.
	ns2.UpdateBuffMissing()
	H.eq(ns2.buffMissing, false, "no missing buff for tracking")
	H.eq(learned["Frost Armor"], true, "Frost Armor still stays")
end)

H.test("a secret tracking name in a fight is skipped, never looked up", function()
	local w, ns = World({
		secret = true,
		grid = { 2 },
		auras = { ["Sense Undead"] = 0 },
		minimap = {
			{ name = "SECRET", type = "spell" },
			"SECRET",
			function() return "SECRET", 136025, false, "spell" end,
			{ name = "Kräuter suchen", type = "SECRET" },
		},
	})
	w.combat = true
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Sense Undead"], nil, "still not learned")
	H.eq(Learned(ns)["SECRET"], nil, "nothing secret learned")
	H.eq(ns.IsTrackingBuff("SECRET"), false, "no secret name in the minimap list")
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), false, "a secret kind never counts")
end)

-- The whole entry secret, with the fields that would make it a tracking
-- spell: only the IsSecret check on the entry keeps it out of the list.
H.test("a secret tracking entry is not read, even when its fields would be", function()
	local entry = { name = "Kräuter suchen", type = "spell" }
	local hide = false
	local w, ns = World({
		secret = function(v) return hide and v == entry end,
		minimap = { entry },
	})
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), true, "plain: a tracking spell")
	hide = true
	w.combat = true
	w:fire("SPELLS_CHANGED")
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), false, "secret: not read")
end)

H.test("the minimap list is read again after SPELLS_CHANGED and a loading screen", function()
	local w, ns = World({ minimap = { { name = "Kräuter suchen", type = "spell" } } })
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), true, "read at login")

	-- You learn a new tracking spell.
	w.minimap[2] = { name = "Erze suchen", type = "spell" }
	H.eq(ns.IsTrackingBuff("Erze suchen"), false, "kept until something changes")
	w:fire("SPELLS_CHANGED")
	H.eq(ns.IsTrackingBuff("Erze suchen"), true, "read again after SPELLS_CHANGED")

	w.minimap[3] = { name = "Schätze suchen", type = "spell" }
	w:fire("PLAYER_ENTERING_WORLD")
	H.eq(ns.IsTrackingBuff("Schätze suchen"), true, "read again after a loading screen")
end)

H.test("a list read in a fight with secret names is not kept", function()
	local w, ns = World({
		secret = true,
		grid = { 3 },
		auras = { ["Kräuter suchen"] = 0 },
		minimap = { { name = "Kräuter suchen", type = "spell" } },
	})
	ns.UpdateBuffMissing()

	-- A spell swap in a fight: the names are secret now.
	w.combat = true
	w.minimap[1] = { name = "SECRET", type = "spell" }
	w:fire("SPELLS_CHANGED")
	w.reads = 0
	ns.UpdateBuffMissing()
	H.eq(w.reads, 1, "one update reads the list with a gap once")
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), false, "unknown while the name is secret")

	-- After the fight the name reads again, and the buff is still not learned.
	w.combat = false
	w.minimap[1] = { name = "Kräuter suchen", type = "spell" }
	ns.UpdateBuffMissing()
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), true, "read again after the fight")
	H.eq(Learned(ns)["Kräuter suchen"], nil, "never learned")
end)

H.test("an entry with no kind is read once and kept", function()
	local db = { classes = {} }
	local w, ns = World({ db = db })
	ns.ClassDB().buffSpells = {
		["Devotion Aura"] = true, ["Arcane Intellect"] = true, ["Frost Armor"] = true,
		["Ice Barrier"] = true, ["Mage Armor"] = true,
	}
	local w2, ns2 = World({
		db = w.env.HUDiniDB,
		grid = { 1, 5 },
		auras = { ["Devotion Aura"] = 0, ["Arcane Intellect"] = 1800 },
		minimap = {
			{ name = "Kräuter suchen", type = "spell" },
			{ name = "Frost Armor" },   -- no kind: read, but it does not count
			function() return "Bankier", 136026, true, nil end,
		},
	})
	w2.reads = 0
	ns2.UpdateBuffMissing()
	ns2.UpdateBuffMissing()
	H.eq(w2.reads, 0, "the list read at login is kept")
	H.eq(ns2.IsTrackingBuff("Frost Armor"), false, "no kind never counts")
	H.eq(ns2.IsTrackingBuff("Kräuter suchen"), true, "the tracking spell counts")
	H.eq(w2.reads, 0, "still kept")
end)

H.test("an entry that throws, or a field that throws, is not kept and throws nothing", function()
	local broken = setmetatable({}, { __index = function() error("not ready") end })
	local w, ns = World({
		grid = { 3 },
		auras = { ["Kräuter suchen"] = 0 },
		minimap = {
			{ name = "Kräuter suchen", type = "spell" },
			function() error("not ready") end,
			broken,
		},
	})
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), true, "the entry that reads counts")
	H.eq(Learned(ns)["Kräuter suchen"], nil, "never learned")

	-- Ready now: the list is read again, as it was never kept.
	w.minimap[2] = { name = "Erze suchen", type = "spell" }
	w.minimap[3] = { name = "Schätze suchen", type = "spell" }
	H.eq(ns.IsTrackingBuff("Erze suchen"), true, "read again: the entry that threw")
	H.eq(ns.IsTrackingBuff("Schätze suchen"), true, "read again: the field that threw")
end)

H.test("a secret count reads no entry", function()
	local w, ns = World({
		secret = function(v) return v == "SECRET" or v == 99 end,
		minimap = { { name = "Kräuter suchen", type = "spell" } },
	})
	w:fire("SPELLS_CHANGED")
	w.count = 99
	w.reads = 0
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), false, "unknown while the count is secret")
	H.eq(w.reads, 0, "no entry read")
end)

H.test("an empty list at login is not kept", function()
	local w, ns = World({ minimap = {} })
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), false, "nothing yet")
	w.minimap[1] = { name = "Kräuter suchen", type = "spell" }
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), true, "read when the list fills in")
end)

H.test("a list with a gap is read once for each update, not once for each buff", function()
	local db = { classes = {} }
	local w, ns = World({ db = db })
	ns.ClassDB().buffSpells = { ["Devotion Aura"] = true, ["Frost Armor"] = true, ["Ice Barrier"] = true }
	local w2, ns2 = World({
		db = w.env.HUDiniDB,
		secret = true,
		grid = { 1, 5 },
		auras = { ["Devotion Aura"] = 0, ["Arcane Intellect"] = 1800 },
		minimap = {
			{ name = "Kräuter suchen", type = "spell" },
			{ name = "SECRET", type = "spell" },
			{ name = "Erze suchen", type = "spell" },
		},
	})
	w2.combat = true
	w2.reads = 0
	ns2.UpdateBuffMissing()
	H.eq(w2.reads, 3, "one read of the 3 entries")
	ns2.UpdateBuffMissing()
	H.eq(w2.reads, 6, "the next update reads it again, once")
end)

H.test("a secret kind is not kept as read", function()
	local w, ns = World({ secret = true, minimap = { { name = "Kräuter suchen", type = "SECRET" } } })
	w.combat = true
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), false, "unknown while the kind is secret")
	-- After the fight the kind reads, with no SPELLS_CHANGED between.
	w.combat = false
	w.minimap[1] = { name = "Kräuter suchen", type = "spell" }
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), true, "read again: it was never kept")
end)

H.test("a nameless spell entry, in either shape, throws nothing and is not kept", function()
	local w, ns = World({
		grid = { 3 },
		auras = { ["Kräuter suchen"] = 0 },
		minimap = {
			{ name = "Kräuter suchen", type = "spell" },
			{ type = "spell" },                                    -- 12.x shape, no name
			function() return nil, 136026, true, "spell" end,      -- older shape, no name
		},
	})
	H.ok(pcall(ns.UpdateBuffMissing), "an update throws nothing")
	H.eq(ns.IsTrackingBuff("Kräuter suchen"), true, "the entry with a name counts")
	H.eq(Learned(ns)["Kräuter suchen"], nil, "never learned")

	-- Named now: the list is read again, as it was never kept.
	w.minimap[2] = { name = "Erze suchen", type = "spell" }
	w.minimap[3] = { name = "Schätze suchen", type = "spell" }
	H.eq(ns.IsTrackingBuff("Erze suchen"), true, "read again: the 12.x shape")
	H.eq(ns.IsTrackingBuff("Schätze suchen"), true, "read again: the older shape")
end)
