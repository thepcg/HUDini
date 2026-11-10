-- States (TICK-0062): Stealth, a druid form, Shadowform, Ghost Wolf, a
-- stance, a mount. Each is a no-end buff that you leave on purpose, so out
-- of it is never "missing". A paladin aura is a buff to keep up: it stays.

local NAMES = {
	[1] = "Stealth",
	[2] = "Bear Form",
	[3] = "Shadowform",
	[4] = "Ghost Wolf",
	[5] = "Devotion Aura",
	[6] = "Bärengestalt",      -- Bear Form on a German client: not on the list
	[7] = "Swift Gray Wolf",   -- a mount
	[8] = "Arcane Intellect",
	[9] = "Feign Death",       -- 6 min in Classic: over the long-buff line
	[10] = "Summon Warhorse",  -- a class mount
}

local function IDOf(name)
	for id, n in pairs(NAMES) do
		if n == name then return id end
	end
end

-- A world for one class: the grid holds spell IDs, w.auras[name] = duration
-- (0 = no end). w.form is the spell ID of the form you are in (nil = none);
-- w.formID is what GetShapeshiftFormID gives.
local function World(opts)
	local w = H.world()
	w.class, w.className = opts.class, opts.className
	if opts.secret then
		w.env.issecretvalue = type(opts.secret) == "function" and opts.secret
			or function(v) return v == "SECRET" end
	end
	local env = w.env
	env.HUDiniDB = opts.db
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		-- A journal mount is not in your spellbook: a lookup by name can fail.
		if opts.noLookup and opts.noLookup[name] then return nil end
		local id = IDOf(name)
		if id then return { spellID = id } end
	end
	env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end

	w.auras = opts.auras or {}
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		local d = w.auras[name]
		if d then return { auraInstanceID = 7, duration = d, expirationTime = d > 0 and 2000 or 0 } end
	end
	env.C_UnitAuras.GetAuraDataByIndex = function() return nil end

	w.formReads = 0
	if opts.forms then
		env.GetShapeshiftFormID = function() w.formReads = w.formReads + 1 return w.formID end
		env.GetShapeshiftForm = function() return w.form and 1 or 0 end
		env.GetShapeshiftFormInfo = function(i)
			if i == 1 and w.form then return 136116, true, true, w.form end
		end
	end
	if opts.mounts then
		env.C_MountJournal = {
			GetMountFromSpell = function(id) return opts.mounts[id] end,
		}
	end

	w:loadAddon()
	local hud = w.ns.HUDini
	hud.spells = {}
	for _, id in ipairs(opts.grid or {}) do hud.spells[#hud.spells + 1] = { spellID = id, row = 0, col = 0 } end
	return w, w.ns
end

local function Learned(ns)
	return ns.ClassDB().buffSpells or {}
end

-- Use the state from the grid, check, leave it, check again.
local function InAndOut(w, ns, name, duration)
	w.auras[name] = duration or 0
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)[name], nil, name .. ": not learned while on")
	w.auras[name] = nil
	w.form, w.formID = nil, nil
	ns.UpdateBuffMissing()
	H.eq(ns.buffMissing, false, name .. ": not missing after you leave it")
	H.eq(ns.missingBuffID, nil, name .. ": no icon to cast it")
end

for _, case in ipairs({
	{ "ROGUE", "Rogue", "Stealth" },
	{ "DRUID", "Druid", "Bear Form" },
	{ "PRIEST", "Priest", "Shadowform" },
	{ "SHAMAN", "Shaman", "Ghost Wolf" },
}) do
	local class, className, name = case[1], case[2], case[3]
	H.test("a " .. className .. " uses " .. name .. " from the grid, then leaves it: nothing is missing", function()
		local w, ns = World({ class = class, className = className, grid = { IDOf(name) } })
		InAndOut(w, ns, name)
	end)
end

H.test("a state learned before is dropped at login; a paladin aura stays", function()
	local db = { classes = {} }
	local w, ns = World({ class = "ROGUE", className = "Rogue", db = db })
	ns.ClassDB().buffSpells = { ["Stealth"] = true, ["Devotion Aura"] = true }
	local w2, ns2 = World({ class = "ROGUE", className = "Rogue", db = w.env.HUDiniDB, grid = { 1 } })
	H.eq(Learned(ns2)["Stealth"], nil, "Stealth dropped")
	H.eq(Learned(ns2)["Devotion Aura"], true, "Devotion Aura stays")
	ns2.UpdateBuffMissing()
	H.eq(ns2.missingBuffID, 5, "Devotion Aura is still missing when off")
	H.eq(w2.blocked and #w2.blocked or 0, 0)
end)

H.test("a form with a name not on the list is a state while you are in it", function()
	local w, ns = World({ class = "DRUID", className = "Druid", grid = { 6 }, forms = true })
	w.form, w.formID = 6, 5
	InAndOut(w, ns, "Bärengestalt")
end)

H.test("a paladin aura on the stance bar has no form ID: it is learned and can be missing", function()
	local w, ns = World({ class = "PALADIN", className = "Paladin", grid = { 5 }, forms = true })
	w.form, w.formID = 5, nil
	w.auras["Devotion Aura"] = 0
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Devotion Aura"], true, "learned")
	w.auras["Devotion Aura"] = nil
	w.form = nil
	ns.UpdateBuffMissing()
	H.eq(ns.buffMissing, true, "missing when off")
	H.eq(ns.missingBuffID, 5)
end)

H.test("a secret form ID is not a form, and throws nothing", function()
	local w, ns = World({ class = "PALADIN", className = "Paladin", grid = { 5 }, forms = true, secret = true })
	w.form, w.formID = 5, "SECRET"
	w.auras["Devotion Aura"] = 0
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Devotion Aura"], true, "still learned")
end)

-- Spell 60 names the form you are in: the value that would make
-- Bärengestalt a form. Secret, the form is not known: only Plain keeps it so.
H.test("a secret form spell is not a form, and throws nothing", function()
	local hide = false
	local w, ns = World({ class = "DRUID", className = "Druid", grid = { 6 }, forms = true,
		secret = function(v) return hide and v == 60 end })
	local name = w.env.C_Spell.GetSpellName
	w.env.C_Spell.GetSpellName = function(id) if id == 60 then return "Bärengestalt" end return name(id) end
	w.env.GetShapeshiftFormInfo = function() return 136116, true, true, 60 end
	w.form, w.formID = 6, 5
	w.auras["Bärengestalt"] = 0
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Bärengestalt"], nil, "plain: the form you are in is never learned")
	hide = true
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Bärengestalt"], true, "secret: the form is not known, so it is learned")
end)

H.test("a mount on the grid is never learned", function()
	local w, ns = World({ class = "SHAMAN", className = "Shaman", grid = { 7 }, mounts = { [7] = 42 } })
	InAndOut(w, ns, "Swift Gray Wolf")
end)

H.test("a long timed buff is still learned with forms and mounts known", function()
	local w, ns = World({ class = "MAGE", className = "Mage", grid = { 8 }, forms = true, mounts = {} })
	w.auras["Arcane Intellect"] = 3600
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Arcane Intellect"], true, "learned")
end)

H.test("a Hunter uses Feign Death (6 min) from the grid, then stands up: nothing is missing", function()
	local w, ns = World({ class = "HUNTER", className = "Hunter", grid = { 9 } })
	InAndOut(w, ns, "Feign Death", 360)
end)

H.test("a mount whose name lookup fails is found by its grid spell ID", function()
	local w, ns = World({ class = "SHAMAN", className = "Shaman", grid = { 7 }, mounts = { [7] = 42 },
		noLookup = { ["Swift Gray Wolf"] = true } })
	InAndOut(w, ns, "Swift Gray Wolf")
end)

H.test("a mount learned before is dropped by its grid spell ID", function()
	local w, ns = World({ class = "SHAMAN", className = "Shaman", mounts = { [7] = 42 },
		noLookup = { ["Swift Gray Wolf"] = true } })
	ns.ClassDB().buffSpells = { ["Swift Gray Wolf"] = true }
	ns.HUDini.spells = { { spellID = 7, row = 0, col = 0 } }
	ns.UpdateBuffMissing()
	H.eq(Learned(ns)["Swift Gray Wolf"], nil, "dropped")
	H.eq(ns.buffMissing, false, "not missing")
end)

H.test("a class mount the journal does not know is a state by its name", function()
	local w, ns = World({ class = "PALADIN", className = "Paladin", grid = { 10 }, mounts = {} })
	InAndOut(w, ns, "Summon Warhorse")
end)

H.test("one update reads the form once, however many buffs it checks", function()
	local w, ns = World({ class = "MAGE", className = "Mage", grid = { 8, 5 }, forms = true })
	ns.ClassDB().buffSpells = { ["Arcane Intellect"] = true, ["Devotion Aura"] = true, ["Bärengestalt"] = true }
	ns.UpdateBuffMissing()
	H.eq(w.formReads, 1, "read once")
	ns.UpdateBuffMissing()
	H.eq(w.formReads, 2, "and again next update")
end)
