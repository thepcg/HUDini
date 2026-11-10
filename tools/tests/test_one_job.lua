-- Long buffs for one job (TICK-0064): Unending Breath, Water Walking, Water
-- Breathing, the Warlock's Detect Invisibility group, Righteous Fury, the
-- priest's Fear Ward and Shadow Protection pair. You cast one when the job
-- comes, so after it ends nothing is missing. Arcane Intellect (1 hour) is
-- a buff to keep up: it is still learned, and missing when it ends.

local NAMES = {
	[1] = "Unending Breath",
	[2] = "Water Walking",
	[3] = "Water Breathing",
	[4] = "Detect Invisibility",
	[5] = "Righteous Fury",
	[6] = "Detect Lesser Invisibility",
	[7] = "Arcane Intellect",
	[8] = "Detect Greater Invisibility",
	[9] = "Fear Ward",
	[10] = "Shadow Protection",
	[11] = "Prayer of Shadow Protection",
}

local CLASS = {
	["Unending Breath"] = { "WARLOCK", "Warlock" },
	["Detect Lesser Invisibility"] = { "WARLOCK", "Warlock" },
	["Water Walking"] = { "SHAMAN", "Shaman" },
	["Water Breathing"] = { "SHAMAN", "Shaman" },
	["Detect Invisibility"] = { "WARLOCK", "Warlock" },
	["Detect Greater Invisibility"] = { "WARLOCK", "Warlock" },
	["Righteous Fury"] = { "PALADIN", "Paladin" },
	["Arcane Intellect"] = { "MAGE", "Mage" },
	["Fear Ward"] = { "PRIEST", "Priest" },
	["Shadow Protection"] = { "PRIEST", "Priest" },
	["Prayer of Shadow Protection"] = { "PRIEST", "Priest" },
}

local function IDOf(name)
	for id, n in pairs(NAMES) do
		if n == name then return id end
	end
end

-- A world for the class that casts name. w.auras[name] = duration: the buff
-- is on you, cast by you, and a lookup by name or by index finds it.
local function World(name, opts)
	opts = opts or {}
	local w = H.world()
	w.class, w.className = CLASS[name][1], CLASS[name][2]
	local env = w.env
	env.HUDiniDB = opts.db
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(n)
		local id = IDOf(n)
		if id then return { spellID = id } end
	end
	env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end

	w.auras = {}
	local function Aura(n)
		local d = w.auras[n]
		if d then
			return { auraInstanceID = 7, name = n, spellId = IDOf(n), duration = d,
				expirationTime = 2000 }
		end
	end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, n) return Aura(n) end
	env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
		local list = {}
		for n in pairs(w.auras) do list[#list + 1] = n end
		table.sort(list)
		return list[i] and Aura(list[i]) or nil
	end

	w:loadAddon()
	local hud = w.ns.HUDini
	hud.spells = {}
	if opts.grid then hud.spells[1] = { spellID = IDOf(name), row = 0, col = 0 } end
	return w, w.ns
end

local function Learned(ns)
	return ns.ClassDB().buffSpells or {}
end

-- Cast it, let it end, look again.
local function CastAndEnd(w, ns, name, duration)
	w.auras[name] = duration
	ns.UpdateBuffMissing()
	local learned = Learned(ns)[name]
	w.auras[name] = nil
	ns.UpdateBuffMissing()
	return learned, ns.buffMissing, ns.missingBuffID
end

for _, case in ipairs({
	{ "Unending Breath", 600 },
	{ "Water Walking", 600 },
	{ "Water Breathing", 600 },
	{ "Detect Invisibility", 600 },
	{ "Detect Lesser Invisibility", 600 },
	{ "Detect Greater Invisibility", 600 },
	{ "Righteous Fury", 1800 },
	{ "Fear Ward", 600 },
	{ "Shadow Protection", 600 },
	{ "Prayer of Shadow Protection", 1200 },
}) do
	local name, duration = case[1], case[2]
	for _, grid in ipairs({ false, true }) do
		local where = grid and "from the grid" or "off the grid"
		H.test(name .. ", cast " .. where .. " and ended, is not learned or missing", function()
			local w, ns = World(name, { grid = grid })
			local learned, missing, icon = CastAndEnd(w, ns, name, duration)
			H.eq(learned, nil, name .. ": learned")
			H.eq(missing, false, name .. ": missing after it ends")
			H.eq(icon, nil, name .. ": an icon to cast it")
		end)
	end
end

H.test("Arcane Intellect, cast and ended, is still learned and missing", function()
	local w, ns = World("Arcane Intellect")
	local learned, missing = CastAndEnd(w, ns, "Arcane Intellect", 3600)
	H.eq(learned, true, "Arcane Intellect learned")
	H.eq(missing, true, "Arcane Intellect missing after it ends")
end)

H.test("a one-job buff learned before is dropped at login; a buff to keep up stays", function()
	local w, ns = World("Unending Breath")
	ns.ClassDB().buffSpells = { ["Unending Breath"] = true, ["Arcane Intellect"] = true }
	local _, ns2 = World("Unending Breath", { db = w.env.HUDiniDB })
	ns2.UpdateBuffMissing()
	H.eq(Learned(ns2)["Unending Breath"], nil, "Unending Breath dropped")
	H.eq(Learned(ns2)["Arcane Intellect"], true, "Arcane Intellect stays")
	H.eq(ns2.missingBuffID, 7, "the icon is for Arcane Intellect, not the dropped buff")
end)
