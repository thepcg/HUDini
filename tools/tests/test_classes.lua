-- Class files (TICK-0023): each one in the .toc registers its own class, with
-- only keys that Classes.lua knows, in the shape Classes.lua describes.

-- The class files the .toc lists, as { file, token }: Classes/Mage.lua, MAGE.
local function ClassFiles()
	local out = {}
	for _, rel in ipairs(H.tocFiles()) do
		local name = rel:match("^Classes/(%a+)%.lua$")
		if name then out[#out + 1] = { file = rel, token = name:upper() } end
	end
	return out
end

-- The keys in the profile example at the top of Classes.lua. The header is
-- the list a class file is checked against, so a new key goes there first.
local function KnownKeys()
	local fh = assert(io.open(H_ROOT .. "/Classes.lua", "rb"))
	local src = fh:read("*a")
	fh:close()
	local example = assert(src:match('ns%.RegisterClass%("MAGE", {(.-)\n%s*}%)'),
		"no profile example in the Classes.lua header")
	local keys = {}
	for line in example:gmatch("[^\n]+") do
		local key = line:match("^%s*(%a+)%s*=")
		if key then keys[key] = true end
	end
	return keys
end

-- Every profile a class file registers, by the file that registered it.
local function Registered()
	local w = H.world()
	local ns = w:load("Util.lua", "Classes.lua")
	local byFile, current = {}, nil
	ns.RegisterClass = function(token, profile)
		byFile[current] = byFile[current] or {}
		table.insert(byFile[current], { token = token, profile = profile })
	end
	for _, c in ipairs(ClassFiles()) do
		current = c.file
		w:load(c.file)
	end
	return byFile
end

local function IsList(v)
	if type(v) ~= "table" then return false end
	for i, name in ipairs(v) do
		if type(name) ~= "string" or name == "" then return false end
	end
	return next(v) == nil or #v > 0
end

local DISPEL_TYPES = { Magic = true, Curse = true, Poison = true, Disease = true }

-- The shape of each key, from the Classes.lua header. Returns an error or nil.
local SHAPE = {
	interrupt = function(v)
		if type(v) == "string" then return nil end
		if type(v) ~= "table" or #v == 0 then return "not a spell name or a list" end
		for _, spell in pairs(v) do
			if type(spell) ~= "string" then return "a list item is not a spell name" end
		end
	end,
	dispel = function(v)
		if type(v) ~= "table" then return "not a table" end
		for kind, spell in pairs(v) do
			if not DISPEL_TYPES[kind] then return "unknown debuff type " .. tostring(kind) end
			if type(spell) ~= "string" then return kind .. " is not a spell name" end
		end
	end,
	purge = function(v)
		if type(v) == "string" then return nil end
		if type(v) == "table" and type(v.spell) == "string" then return nil end
		return "not a spell name or { spell = ... }"
	end,
	keepUp = function(v)
		if not IsList(v) then return "not a list of spell names" end
	end,
	resource = function(v)
		if type(v) ~= "table" then return "not a table" end
		if type(v.aura) == "string" and type(v.max) == "number" then return nil end
		if type(v.power) == "string" and (v.onlyWith == nil or type(v.onlyWith) == "string") then
			return nil
		end
		return "neither { aura, max } nor { power, onlyWith }"
	end,
	auraMap = function(v)
		if type(v) ~= "table" then return "not a table" end
		for spell, names in pairs(v) do
			if type(spell) ~= "string" or not IsList(names) then return "bad entry " .. tostring(spell) end
		end
	end,
	weaponBuff = function(v)
		if not IsList(v) then return "not a list of spell names" end
	end,
	powers = function(v)
		if not IsList(v) then return "not a list of power tokens" end
	end,
	ids = function(v)
		if type(v) ~= "table" then return "not a table" end
		for name, id in pairs(v) do
			if type(name) ~= "string" or name == "" then return "a key is not a spell name" end
			if type(id) ~= "number" or id < 1 or id % 1 ~= 0 then return name .. " is not a spell ID" end
		end
	end,
}

H.test("the Classes.lua header names every key the check knows", function()
	local keys = KnownKeys()
	for key in pairs(keys) do H.ok(SHAPE[key], "no shape check for header key " .. key) end
	for key in pairs(SHAPE) do H.ok(keys[key], "shape check for " .. key .. " is not in the header") end
end)

H.test("each class file registers one profile, for the class it is named after", function()
	local byFile = Registered()
	H.ok(#ClassFiles() > 0, "no class files in the .toc")
	for _, c in ipairs(ClassFiles()) do
		local got = byFile[c.file] or {}
		H.eq(#got, 1, c.file .. " registrations")
		H.eq(got[1].token, c.token, c.file .. " token")
		H.eq(type(got[1].profile), "table", c.file .. " profile")
	end
end)

H.test("every key in a class profile is one Classes.lua knows, in its shape", function()
	local keys = KnownKeys()
	for file, regs in pairs(Registered()) do
		for key, value in pairs(regs[1].profile) do
			H.ok(keys[key], file .. ": unknown key " .. tostring(key))
			local err = SHAPE[key](value)
			H.ok(err == nil, file .. ": " .. key .. " " .. tostring(err))
		end
	end
end)

H.test("each class logs in with no Lua error, and its class file answers", function()
	local byFile = Registered()
	for _, c in ipairs(ClassFiles()) do
		local w = H.world()
		w.class, w.className = c.token, c.token:sub(1, 1) .. c.token:sub(2):lower()
		local ns = w:loadAddon()
		H.eq(#w.printed, 0, c.token .. " lines printed at login")
		H.eq(ns.ClassToken(), c.token, "class token")
		for key, value in pairs(byFile[c.file][1].profile) do
			H.ok(H.diff(ns.ClassValue(key), value) == nil, c.token .. " " .. key .. " from the class file")
		end
		H.ok(type(ns.ClassPowerKeys()) == "table", c.token .. " power keys")
	end
end)

-- A Hunter with two aspects learned, in one of them. Only one aspect can be
-- on, so the other must not count as missing, or the HUD never hides.
H.test("a hunter in one aspect misses no other aspect", function()
	local NAMES = { [1] = "Aspect of the Hawk", [2] = "Aspect of the Monkey" }
	local w = H.world()
	w.class, w.className = "HUNTER", "Hunter"
	local env = w.env
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id } end
		end
	end
	env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end
	local auras = { ["Aspect of the Hawk"] = 0, ["Aspect of the Monkey"] = 0 }
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		local d = auras[name]
		if d then return { auraInstanceID = 7, duration = d, expirationTime = 0 } end
	end
	local ns = w:loadAddon()
	ns.HUDini.spells = { { spellID = 1, row = 0, col = 0 }, { spellID = 2, row = 0, col = 1 } }

	ns.UpdateBuffMissing()
	local learned = ns.ClassDB().buffSpells or {}
	H.ok(learned["Aspect of the Hawk"] and learned["Aspect of the Monkey"], "both aspects learned")

	auras["Aspect of the Hawk"] = nil
	ns.UpdateBuffMissing()
	H.eq(ns.buffMissing, false, "in Monkey, Hawk is not missing")

	auras["Aspect of the Hawk"], auras["Aspect of the Monkey"] = 0, nil
	ns.UpdateBuffMissing()
	H.eq(ns.buffMissing, false, "in Hawk, Monkey is not missing")

	auras["Aspect of the Hawk"] = nil
	ns.UpdateBuffMissing()
	H.eq(ns.buffMissing, true, "in no aspect, one is missing")
end)

-- A spell name to its ID (TICK-0112): plain first, then the same ID secret.
H.test("a secret spell ID from a name is no ID", function()
	local w = H.world()
	w.secret = {}
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.env.C_Spell.GetSpellInfo = function(name)
		if name == "Counterspell" then return { spellID = 4242 } end
	end
	local ns = w:loadAddon()
	H.eq(ns.SpellID("Counterspell"), 4242, "plain")
	w.secret[4242] = true
	H.eq(ns.SpellID("Counterspell"), nil, "secret: none")
end)
