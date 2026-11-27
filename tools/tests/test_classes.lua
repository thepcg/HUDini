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
		local function One(e)
			if type(e) ~= "table" then return false end
			-- TICK-0238: prefer = true, filter = "HARMFUL" (or "HELPFUL").
			if e.prefer ~= nil and e.prefer ~= true then return false end
			if e.filter ~= nil and e.filter ~= "HARMFUL" and e.filter ~= "HELPFUL" then return false end
			if type(e.aura) == "string" and type(e.max) == "number" then return true end
			return type(e.power) == "string" and (e.onlyWith == nil or type(e.onlyWith) == "string")
		end
		if One(v) then return nil end
		-- An ordered list of them (TICK-0199): the first buff on you.
		if #v > 0 and next(v, #v) == nil then
			for _, e in ipairs(v) do
				if not One(e) then return "a list entry is neither { aura, max } nor { power, onlyWith }" end
			end
			return nil
		end
		return "neither { aura, max } nor { power, onlyWith }, nor a list of them"
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
	readyAlert = function(v)
		if not IsList(v) then return "not a list of spell names" end
	end,
	readyAlertOn = function(v)
		if not IsList(v) then return "not a list of spell names" end
	end,
	keepUpSoundOn = function(v)
		if type(v) ~= "boolean" then return "not true or false" end
	end,
	trackBuff = function(v)
		if not IsList(v) then return "not a list of spell names" end
	end,
	-- TICK-0196: each name is also a keep-up name (the icon is a keep-up
	-- name not in this list).
	notInFight = function(v, p)
		if not IsList(v) then return "not a list of spell names" end
		local keep = {}
		for _, name in ipairs(type(p.keepUp) == "table" and p.keepUp or {}) do keep[name] = true end
		for _, name in ipairs(v) do
			if not keep[name] then return name .. " is not in keepUp" end
		end
	end,
	-- TICK-0197: lists of form names; a form is in one of the two only.
	formQuiet = function(v, p)
		if not IsList(v) then return "not a list of form names" end
		local other = {}
		for _, name in ipairs(type(p.formQuietSound) == "table" and p.formQuietSound or {}) do other[name] = true end
		for _, name in ipairs(v) do
			if other[name] then return name .. " is in formQuietSound too" end
		end
	end,
	formQuietSound = function(v)
		if not IsList(v) then return "not a list of form names" end
	end,
	-- TICK-0208: { buff = "Righteous Fury", with = { "Seal of Fury" } }.
	tankBuff = function(v)
		if type(v) ~= "table" then return "not a table" end
		if type(v.buff) ~= "string" or v.buff == "" then return "buff is not a spell name" end
		if not IsList(v.with) then return "with is not a list of spell names" end
	end,
	-- TICK-0182: rows of { key, make | needs, items, buff?, on? }.
	missingItem = function(v)
		if type(v) ~= "table" or #v == 0 then return "not a list of rows" end
		local keys = {}
		for i, row in ipairs(v) do
			local at = "row " .. i
			if type(row) ~= "table" then return at .. " is not a table" end
			if type(row.key) ~= "string" or row.key == "" then return at .. " has no key" end
			if keys[row.key] then return at .. " repeats the key " .. row.key end
			keys[row.key] = true
			if (row.make == nil) == (row.needs == nil) then return at .. " needs one of make or needs" end
			if row.make ~= nil and type(row.make) ~= "string" then return at .. ": make is not a spell name" end
			if row.needs ~= nil and type(row.needs) ~= "string" and not IsList(row.needs) then
				return at .. ": needs is not a spell name or a list"
			end
			if type(row.items) ~= "table" or #row.items == 0 then return at .. " has no items" end
			for _, id in ipairs(row.items) do
				if type(id) ~= "number" or id < 1 or id % 1 ~= 0 then return at .. ": an item is not an item ID" end
			end
			if row.buff ~= nil and type(row.buff) ~= "string" then return at .. ": buff is not a spell name" end
			if row.on ~= nil and type(row.on) ~= "boolean" then return at .. ": on is not true or false" end
			if row.few ~= nil and (type(row.few) ~= "number" or row.few < 1 or row.few % 1 ~= 0) then
				return at .. ": few is not a whole number of 1 or more"
			end
		end
	end,
	-- TICK-0192: { revive?, call?, feed?, sacrifice?, buffs? }, one of the first three.
	pet = function(v)
		if type(v) ~= "table" then return "not a table" end
		for k, x in pairs(v) do
			if k == "revive" or k == "feed" then
				if type(x) ~= "string" or x == "" then return k .. " is not a spell name" end
			elseif k == "call" then
				if type(x) ~= "string" and not (IsList(x) and #x > 0) then
					return "call is not a spell name or a list"
				end
			elseif k == "sacrifice" or k == "buffs" then
				if not (IsList(x) and #x > 0) then return k .. " is not a list of buff names" end
			else
				return "unknown field " .. tostring(k)
			end
		end
		if v.revive == nil and v.call == nil and v.feed == nil then return "no revive, call or feed" end
	end,
	powers = function(v)
		if not IsList(v) then return "not a list of power tokens" end
	end,
	-- Default looks (TICK-0224): resource and timer = { [spell] = look }.
	barLooks = function(v)
		if type(v) ~= "table" then return "not a table" end
		local GRADIENTS = { off = true, darker = true, lighter = true, color = true }
		local function Look(at, look)
			if type(look) ~= "table" then return at .. " is not a look" end
			for k, x in pairs(look) do
				if k == "texture" then
					if type(x) ~= "string" or x == "" then return at .. ": texture is not a name" end
				elseif k == "gradient" then
					if not GRADIENTS[x] then return at .. ": gradient is not off, darker, lighter or color" end
				elseif k == "color" then
					if type(x) ~= "table" or type(x[1]) ~= "number" or type(x[2]) ~= "number"
						or type(x[3]) ~= "number" then return at .. ": color is not { r, g, b }" end
				else
					return at .. ": unknown field " .. tostring(k)
				end
			end
		end
		for k, x in pairs(v) do
			if k == "resource" then
				local bad = Look("resource", x)
				if bad then return bad end
			elseif k == "timer" then
				if type(x) ~= "table" then return "timer is not a table" end
				for spell, look in pairs(x) do
					if type(spell) ~= "string" or spell == "" then return "a timer key is not a spell name" end
					local bad = Look("timer " .. spell, look)
					if bad then return bad end
				end
			else
				return "unknown bar " .. tostring(k)
			end
		end
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

H.test("notInFight: a list of keep-up names", function()
	H.eq(SHAPE.notInFight({ "Aspect of the Cheetah" }, { keepUp = { "Aspect of the Hawk", "Aspect of the Cheetah" } }),
		nil, "a keep-up name")
	H.ok(SHAPE.notInFight({ "Aspect of the Cheetah" }, { keepUp = { "Aspect of the Hawk" } }), "not a keep-up name")
	H.ok(SHAPE.notInFight({ "Aspect of the Cheetah" }, {}), "no keepUp")
	H.ok(SHAPE.notInFight("Aspect of the Cheetah", { keepUp = { "Aspect of the Cheetah" } }), "not a list")
end)

H.test("formQuiet: a list of forms, none also in formQuietSound", function()
	H.eq(SHAPE.formQuiet({ "Travel Form" }, { formQuietSound = { "Bear Form" } }), nil, "two lists")
	H.ok(SHAPE.formQuiet({ "Travel Form" }, { formQuietSound = { "Travel Form" } }), "in both")
	H.ok(SHAPE.formQuiet("Travel Form", {}), "not a list")
	H.ok(SHAPE.formQuietSound({ 783 }), "not a name")
end)

H.test("resource: prefer and filter (TICK-0238)", function()
	H.eq(SHAPE.resource({ { aura = "A", max = 5, prefer = true }, { aura = "B", max = 3 } }), nil, "prefer")
	H.eq(SHAPE.resource({ aura = "A", max = 4, filter = "HARMFUL" }), nil, "a debuff")
	H.ok(SHAPE.resource({ aura = "A", max = 5, prefer = "yes" }), "prefer not true")
	H.ok(SHAPE.resource({ aura = "A", max = 4, filter = "harmful" }), "an unknown filter")
end)

H.test("every key in a class profile is one Classes.lua knows, in its shape", function()
	local keys = KnownKeys()
	for file, regs in pairs(Registered()) do
		for key, value in pairs(regs[1].profile) do
			H.ok(keys[key], file .. ": unknown key " .. tostring(key))
			local err = SHAPE[key](value, regs[1].profile)
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

-- Lines in the class files that no other test reads (review-board, the
-- TICK-0196 and TICK-0238 class branches): removing one must fail here.
local function ProfileOf(token)
	for _, list in pairs(Registered()) do
		for _, r in ipairs(list) do
			if r.token == token then return r.profile end
		end
	end
end

H.test("SHAMAN prefers Maelstrom Weapon on the resource bar (TICK-0238)", function()
	local p = assert(ProfileOf("SHAMAN"), "no SHAMAN profile")
	local found
	for _, e in ipairs(type(p.resource) == "table" and p.resource or {}) do
		if type(e) == "table" and e.aura == "Maelstrom Weapon" then found = e end
	end
	H.ok(found, "a Maelstrom Weapon entry")
	H.eq(found and found.prefer, true, "Maelstrom Weapon has prefer = true")
end)

H.test("HUNTER notInFight: the Cheetah and the Pack, both keep-up aspects (TICK-0196)", function()
	local p = assert(ProfileOf("HUNTER"), "no HUNTER profile")
	local set = function(list)
		local out = {}
		for _, n in ipairs(type(list) == "table" and list or {}) do out[n] = true end
		return out
	end
	local notIn, keepUp = set(p.notInFight), set(p.keepUp)
	for _, name in ipairs({ "Aspect of the Cheetah", "Aspect of the Pack" }) do
		H.ok(notIn[name], name .. " is in notInFight")
		H.ok(keepUp[name], name .. " is a keep-up aspect")
	end
end)

H.test("HUNTER pet: Revive Pet, Call Pet and Feed Pet (TICK-0192)", function()
	local p = assert(ProfileOf("HUNTER"), "no HUNTER profile")
	H.eq(H.diff(p.pet, { revive = "Revive Pet", call = { "Call Pet" }, feed = "Feed Pet" }), nil, "the pet line")
end)

H.test("WARLOCK pet: the five summons, the four sacrifice buffs and Soul Link (TICK-0192)", function()
	local p = assert(ProfileOf("WARLOCK"), "no WARLOCK profile")
	H.eq(H.diff(p.pet, {
		call = { "Summon Imp", "Summon Voidwalker", "Summon Succubus", "Summon Incubus", "Summon Felhunter" },
		sacrifice = { "Burning Wish", "Fel Stamina", "Touch of Shadow", "Fel Energy" },
		buffs = { "Soul Link" },
	}), nil, "the pet line")
end)
