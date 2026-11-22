--[[--------------------------------------------------------------------------
	HUDini - Classes

	What differs between classes is data, not logic. Each file under Classes/
	registers one profile: the spells that play a role for that class, by
	their enUS name. A name covers every rank of a spell. On a client in
	another language each name becomes the client's own, from a spell ID
	(TICK-0024): the class file's ids, else SPELL_IDS below. Any rank's ID
	gives the name.

		ns.RegisterClass("MAGE", {
			interrupt = "Counterspell",                -- the kick outline's spell, or
			--          { "Pummel", "Shield Bash" }: the first you can cast now
			dispel    = { Curse = "Remove Lesser Curse" }, -- one spell per debuff type
			purge     = "Purge",                       -- takes any magic buff, or
			--          { spell = "Spellsteal", stealable = true } for stealable only
			keepUp    = { "Ice Barrier" },             -- icon by your health when none is up in a fight
			resource  = { aura = "Name", max = 5 },    -- buff stacks, or
			--          { power = "ComboPoints", onlyWith = "ENERGY" }, or nil
			auraMap   = { ["Spell"] = { "Buff" } },    -- extra buff names per icon
			weaponBuff = { "Rockbiter Weapon" },       -- know one, and each weapon needs one
			powers    = { "MANA" },                    -- every power the class can show
			readyAlert = { "Evocation" },              -- offered for a cooldown ready alert, off
			--          until you turn it on (TICK-0157)
			readyAlertOn = { "Evocation" },            -- these ready alerts start on (the bell)
			--          until you save a choice; any spell the page offers (D-047)
			keepUpSoundOn = true,                      -- the buff-missing sound starts on, with
			--          the default sound, until you save a choice (D-047)
			missingItem = {                            -- an icon by your health bar, out of a
				--     fight, when your bags hold none of the row's items (TICK-0182):
				{ key = "manaGem", make = "Conjure Mana Gem", items = { 5514 }, on = true },
				--     key: the saved choice's name, never renamed. make: the spell that
				--     makes it; it can wake the HUD. Or needs = { "Reincarnation" }: the
				--     spells that use it; it never wakes the HUD. items: item IDs, any
				--     one counts. on: starts on until you save a choice. An optional
				--     buff = "Soulstone Resurrection": that buff on you counts as one.
			},
			ids       = { ["Counterspell"] = 2139 },   -- enUS name -> a spell ID, any rank
		})

	Your own choices (the "Your class" page, or slash commands) live per
	class in HUDiniDB.classes, and win over the class file. So does the grid position: each class keeps its
	own spot.

	To add a class: copy Classes/Mage.lua to Classes/<Class>.lua, change the
	token and the spell names, and list the file in HUDini.toc. Leave out any
	key the class has no spell for; its option then hides itself.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local profiles = {}

function ns.RegisterClass(token, profile)
	profiles[token] = profile
end

function ns.ClassToken()
	return select(2, UnitClass("player"))
end

-- Your saved choices for the class you are playing.
function ns.ClassDB()
	HUDiniDB.classes = HUDiniDB.classes or {}
	local token = ns.ClassToken() or "UNKNOWN"
	HUDiniDB.classes[token] = HUDiniDB.classes[token] or {}
	return HUDiniDB.classes[token]
end

--------------------------------------------------------------------------------
-- Names in the client's language (TICK-0024)
--
-- Data names a spell in enUS, and logic matches buffs by name: a name covers
-- every rank. On an enUS or enGB client that is all. On any other client a
-- name becomes the game's own name for the spell's ID (C_Spell.GetSpellName):
-- the class file's ids, else SPELL_IDS. A name with no ID, or an ID the
-- client has no name for, stays in enUS, as before.
--
-- The IDs are Classic Era ones, not yet proven on Forever: /hud debug ids
-- checks each one on an English client and finds the ID for a wrong one.
--------------------------------------------------------------------------------

-- enUS name -> spell ID, for the names every class shares (Auras.lua's
-- lists, and the pairs and blessings below).
-- locale: skip the game's spell names
local SPELL_IDS = {
	-- Tracking
	["Find Fish"] = 43308, ["Find Herbs"] = 2383, ["Find Minerals"] = 2580,
	["Find Treasure"] = 2481, ["Sense Demons"] = 5500, ["Sense Undead"] = 5502,
	["Track Beasts"] = 1494, ["Track Demons"] = 19878, ["Track Dragonkin"] = 19879,
	["Track Elementals"] = 19880, ["Track Giants"] = 19882, ["Track Hidden"] = 19885,
	["Track Humanoids"] = 19883, ["Track Undead"] = 19884,
	-- States
	["Stealth"] = 1784, ["Prowl"] = 5215, ["Shadowmeld"] = 20580, ["Feign Death"] = 5384,
	["Bear Form"] = 5487, ["Dire Bear Form"] = 9634, ["Cat Form"] = 768,
	["Travel Form"] = 783, ["Aquatic Form"] = 1066, ["Moonkin Form"] = 24858,
	["Tree of Life"] = 33891, ["Flight Form"] = 33943, ["Swift Flight Form"] = 40120,
	["Ghost Wolf"] = 2645, ["Shadowform"] = 15473,
	["Battle Stance"] = 2457, ["Defensive Stance"] = 71, ["Berserker Stance"] = 2458,
	["Summon Warhorse"] = 13819, ["Summon Charger"] = 23214,
	["Summon Felsteed"] = 5784, ["Summon Dreadsteed"] = 23161,
	-- Long buffs for one job
	["Unending Breath"] = 5697, ["Water Walking"] = 546, ["Water Breathing"] = 131,
	["Detect Lesser Invisibility"] = 132, ["Detect Invisibility"] = 2970,
	["Detect Greater Invisibility"] = 11743, ["Righteous Fury"] = 25780,
	["Fear Ward"] = 6346, ["Shadow Protection"] = 976, ["Prayer of Shadow Protection"] = 27683,
	-- Pairs
	["Arcane Intellect"] = 1459, ["Arcane Brilliance"] = 23028,
	["Power Word: Fortitude"] = 1243, ["Prayer of Fortitude"] = 21562,
	["Divine Spirit"] = 14752, ["Prayer of Spirit"] = 27681,
	["Mark of the Wild"] = 1126, ["Gift of the Wild"] = 21849,
	["Blessing of Kings"] = 20217, ["Greater Blessing of Kings"] = 25898,
	["Blessing of Might"] = 19740, ["Greater Blessing of Might"] = 25782,
	["Blessing of Wisdom"] = 19742, ["Greater Blessing of Wisdom"] = 25894,
	["Blessing of Freedom"] = 1044, ["Blessing of Protection"] = 1022,
	["Blessing of Sacrifice"] = 6940,
	-- Food and drink
	["Food"] = 433, ["Drink"] = 430, ["Refreshment"] = 44166, ["Well Fed"] = 19705,
	-- Racial abilities (RACIALS below)
	["Stoneform"] = 20594,
}
-- locale: end
ns.SPELL_IDS = SPELL_IDS

-- An enUS or enGB client: the data's names are its names.
local function EnglishClient()
	local locale = GetLocale and GetLocale()
	return locale == nil or locale == "enUS" or locale == "enGB"
end
ns.EnglishClient = EnglishClient

-- spell ID -> the client's name, or false when the client has no name for
-- it (an ID Forever does not have). A miss is kept, so the aura updates do
-- not ask again each time; ForgetMisses asks again after SPELLS_CHANGED or
-- a loading screen. stale: a miss is kept, or a secret or an error gave
-- the enUS name to a list that was kept (an icon's buff names).
local clientName = {}
local stale = false

-- What is made from the names, kept until a miss is forgotten: the class
-- file values (token .. key), the shared aura map, and each NameSet (gen).
local localized = {}
local sharedAuraMap
local gen = 0

local function ForgetMisses()
	if not stale then return end
	for id, got in pairs(clientName) do
		if got == false then clientName[id] = nil end
	end
	stale = false
	localized, sharedAuraMap, gen = {}, nil, gen + 1
	-- The icons keep their buff names (Auras.lua): build them again.
	if ns.ForgetAuraNames and ns.HUDini and ns.HUDini.spells then ns.ForgetAuraNames() end
end

local namesWatch = CreateFrame("Frame")
namesWatch:RegisterEvent("SPELLS_CHANGED")
namesWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
namesWatch:SetScript("OnEvent", ForgetMisses)

-- The client's name for an enUS name, and true when that is final (no ID,
-- a name, or no name). A secret or an error is not final: it is asked
-- again at the next call. ids is a class file's own table, or nil.
local function LocalName(name, ids)
	if type(name) ~= "string" or EnglishClient() then return name, true end
	local id = (ids and ids[name]) or SPELL_IDS[name]
	if not id then return name, true end
	local known = clientName[id]
	if known then return known, true end
	if known == false then return name, true end
	local ok, got = false, nil
	if C_Spell and C_Spell.GetSpellName then ok, got = pcall(C_Spell.GetSpellName, id) end
	if not ok or ns.IsSecret(got) then
		stale = true
		return name, false
	end
	if type(got) ~= "string" or got == "" then
		clientName[id], stale = false, true
		return name, true
	end
	clientName[id] = got
	return got, true
end

-- Every string in a class file value, keys too, as the client names it.
-- A string with no ID (a power token, a debuff type) stays as it is.
local function Localize(v, ids)
	if type(v) == "string" then return LocalName(v, ids) end
	if type(v) ~= "table" then return v, true end
	local out, final = {}, true
	for k, x in pairs(v) do
		local k2, okK = Localize(k, ids)
		local x2, okX = Localize(x, ids)
		out[k2] = x2
		final = final and okK and okX
	end
	return out, final
end

-- The client's name for a shared enUS name (SPELL_IDS), or the name.
function ns.LocalSpellName(name)
	return (LocalName(name))
end

-- A set for a list of enUS names: each name, and the client's own name for
-- it. Call the result to get the set; it is kept once every name is final,
-- until a miss is forgotten.
function ns.NameSet(names)
	local set, setGen
	return function()
		if set and setGen == gen then return set end
		local out, final = {}, true
		for _, name in ipairs(names) do
			local here, ok = LocalName(name)
			out[name], out[here] = true, true
			final = final and ok
		end
		if final then set, setGen = out, gen end
		return out
	end
end

-- The class file's value for the class you are playing, or nil. Its spell
-- names are the client's (LocalName). On an English client it is the class
-- file's own table.
function ns.ClassDefault(key)
	local token = ns.ClassToken()
	local profile = profiles[token]
	local v = profile and profile[key]
	if v == nil or key == "ids" or EnglishClient() then return v end
	local slot = tostring(token) .. "." .. key
	if localized[slot] then return localized[slot] end
	local out, final = Localize(v, profile.ids)
	if final then localized[slot] = out end
	return out
end

-- Every class file, for /hud debug ids: token -> profile.
function ns.ClassProfiles()
	return profiles
end

-- The class file's dispels, with yours laid over them one type at a time
-- (TICK-0069): a type you set replaces only that type, and false removes it.
-- So a Curse spell of yours keeps the class file's Poison.
local function MergeDispel(default, saved)
	if type(saved) ~= "table" then return default end
	local out = {}
	if type(default) == "table" then
		for dispelType, spell in pairs(default) do out[dispelType] = spell end
	end
	for dispelType, spell in pairs(saved) do
		if spell == false then out[dispelType] = nil else out[dispelType] = spell end
	end
	return out
end

-- A spell's name in lower case, for a match by name. A saved ID counts by
-- its name. A secret name, or no name, gives nil.
local function NameKey(v)
	if type(v) == "number" and C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, v)
		v = ok and name or nil
	end
	if ns.IsSecret(v) or type(v) ~= "string" then return nil end
	return v:lower()
end

-- One value for the class you are playing: your override, else the class
-- file's, else nil. false is your "None": no spell (or no resource).
function ns.ClassValue(key)
	local saved = HUDiniDB and ns.ClassDB()[key]
	local default = ns.ClassDefault(key)
	if key == "dispel" then return MergeDispel(default, saved) end
	if saved == nil then return default end
	-- Picking the class file's own purge keeps "stealable only" (Spellsteal).
	-- Any other purge takes any magic buff.
	if key == "purge" and type(default) == "table" and saved then
		local name = NameKey(saved)
		if name and name == NameKey(default.spell) then return default end
	end
	return saved
end

--------------------------------------------------------------------------------
-- Spells by name
--------------------------------------------------------------------------------

-- A spell name, or an ID typed in by hand, to the ID of the rank you know.
function ns.SpellID(spell)
	if type(spell) == "number" then return spell end
	if type(spell) ~= "string" or spell == "" then return nil end
	local info = C_Spell.GetSpellInfo(spell)
	return info and ns.Plain(info.spellID) or nil
end

-- For chat: "Counterspell" or "2139 (Counterspell)". nil and false (your
-- "None") are "none".
function ns.SpellLabel(spell)
	if spell == nil or spell == false then return "none" end
	if type(spell) == "number" then
		return spell .. " (" .. (C_Spell.GetSpellName(spell) or "unknown") .. ")"
	end
	return tostring(spell)
end

--------------------------------------------------------------------------------
-- Racial abilities (TICK-0099, D-022)
--
-- Per race (the second answer of UnitRace, the same in every language): the
-- ability, by enUS name, and the debuff types it removes. While one of those
-- types is on you and the ability is ready, its HUD icon glows (Alerts.lua).
-- The types are the aura's dispelName: Stoneform's tooltip says poisons,
-- diseases and bleeds, and the client gives a bleed its own dispelName,
-- "Bleed" (AuraUtil.lua:9 and :322-329, wow-ui-source forever 9dc84f0).
--
-- Only races whose ability answers a plain aura field are here. Escape
-- Artist, Will of the Forsaken and Every Man for Himself answer a loss of
-- control, and the client source names no locType but "SCHOOL_INTERRUPT"
-- (LossOfControlFrame.lua:161), so there is nothing proven to match yet.
--------------------------------------------------------------------------------

-- locale: skip the game's spell names
ns.RACIALS = {
	Dwarf = { spell = "Stoneform", types = { Poison = true, Disease = true, Bleed = true } },
}
-- locale: end

-- Your race's ability, by the client's name, and the set of debuff types it
-- removes. nil for a race with none. It runs on every aura change, so it
-- makes no table.
function ns.RacialAlert()
	local unitRace = _G.UnitRace
	if not unitRace then return nil end
	local race = ns.Plain(select(2, unitRace("player")))
	local entry = race and ns.RACIALS[race]
	if not entry then return nil end
	return ns.LocalSpellName(entry.spell), entry.types
end

--------------------------------------------------------------------------------
-- Buff pairings every class shares
--
-- A single-target buff and its group version cover each other, so a group
-- buff from someone else still lights your single-target icon. enUS names.
--------------------------------------------------------------------------------

-- locale: skip the game's spell names
local SHARED_AURA_MAP_EN = {
	-- Eating ends in Well Fed from buff food.
	["Food"]        = { "Well Fed" },
	["Refreshment"] = { "Food", "Drink", "Well Fed" },
}

local PAIRS = {
	{ "Arcane Intellect",      "Arcane Brilliance" },
	{ "Power Word: Fortitude", "Prayer of Fortitude" },
	{ "Divine Spirit",         "Prayer of Spirit" },
	{ "Shadow Protection",     "Prayer of Shadow Protection" },
	{ "Mark of the Wild",      "Gift of the Wild" },
	{ "Blessing of Kings",     "Greater Blessing of Kings", blessing = true },
	{ "Blessing of Might",     "Greater Blessing of Might", blessing = true },
	{ "Blessing of Wisdom",    "Greater Blessing of Wisdom", blessing = true },
	-- WoW Forever took out Salvation, Light and Sanctuary (TICK-0174, TICK-0200).
}
-- locale: end

for _, pair in ipairs(PAIRS) do
	local a, b = pair[1], pair[2]
	SHARED_AURA_MAP_EN[a] = SHARED_AURA_MAP_EN[a] or {}
	SHARED_AURA_MAP_EN[b] = SHARED_AURA_MAP_EN[b] or {}
	tinsert(SHARED_AURA_MAP_EN[a], b)
	tinsert(SHARED_AURA_MAP_EN[b], a)
end

-- The shared map in the client's language: kept once every name is final.
local function SharedAuraMap()
	if sharedAuraMap then return sharedAuraMap end
	local out, final = Localize(SHARED_AURA_MAP_EN)
	if final then sharedAuraMap = out end
	return out
end

-- A paladin's blessings (one per paladin on a target, Alerts.lua): both of
-- each blessing pair, and the short ones (the old match by words caught them).
local BLESSINGS = { "Blessing of Freedom", "Blessing of Protection", "Blessing of Sacrifice" } -- locale: skip the game's spell names
for _, pair in ipairs(PAIRS) do
	if pair.blessing then
		BLESSINGS[#BLESSINGS + 1] = pair[1]
		BLESSINGS[#BLESSINGS + 1] = pair[2]
	end
end
local blessingSet = ns.NameSet(BLESSINGS)

-- Is a buff by this name (the client's) one of a paladin's blessings?
function ns.IsBlessing(name)
	return blessingSet()[name] == true
end

-- Every extra buff name for one source name: shared, then the class file's.
-- Your own /hud auramap entries are added by Auras.lua.
function ns.AuraMapFor(source)
	local out = {}
	for _, name in ipairs(SharedAuraMap()[source] or {}) do out[#out + 1] = name end
	local classMap = ns.ClassValue("auraMap")
	for _, name in ipairs(classMap and classMap[source] or {}) do out[#out + 1] = name end
	return out
end

--------------------------------------------------------------------------------
-- /hud debug ids (TICK-0024)
--
-- On an English client, checks each ID against its enUS name, then looks
-- for the ID of each name that is wrong or has none: first the rank you
-- know, then every spell ID up to SPELL_SCAN.to, a few thousand per frame.
-- The result goes to HUDiniDB.spellIDReport, readable after a /reload.
--------------------------------------------------------------------------------

ns.SPELL_SCAN = { to = 1500000, step = 10000 }

-- Every spell name in a class file. Not the tokens (powers, debuff types).
local function ProfileSpells(p)
	local out, seen = {}, {}
	local function Add(v)
		if type(v) == "string" and v ~= "" and not seen[v] then
			seen[v] = true
			out[#out + 1] = v
		end
	end
	local function AddAll(v)
		if type(v) == "table" then
			for _, x in ipairs(v) do Add(x) end
		else
			Add(v)
		end
	end
	AddAll(p.interrupt)
	if type(p.dispel) == "table" then
		for _, x in pairs(p.dispel) do Add(x) end
	end
	if type(p.purge) == "table" then Add(p.purge.spell) else Add(p.purge) end
	AddAll(p.keepUp)
	if type(p.resource) == "table" then Add(p.resource.aura) end
	if type(p.auraMap) == "table" then
		for k, list in pairs(p.auraMap) do
			Add(k)
			AddAll(list)
		end
	end
	AddAll(p.weaponBuff)
	AddAll(p.readyAlert)
	if type(p.missingItem) == "table" then
		for _, row in ipairs(p.missingItem) do
			if type(row) == "table" then
				Add(row.make)
				AddAll(row.needs)
				Add(row.buff)
			end
		end
	end
	table.sort(out)
	return out
end

-- The client's name for a spell ID, or nil.
local function SpellNameOf(id)
	if not (C_Spell and C_Spell.GetSpellName) then return nil end
	local ok, name = pcall(C_Spell.GetSpellName, id)
	name = ok and ns.Plain(name) or nil
	return type(name) == "string" and name or nil
end

local scanning = false

-- say prints with the HUDini tag, out prints a plain line.
function ns.CheckSpellIDs(say, out)
	if scanning then return say(ns.Text("debug.idsRunning")) end
	if not EnglishClient() then
		return say(ns.Text("debug.idsEnglish"))
	end

	-- { where, name, id }: the shared names, then each class file's own.
	local rows = {}
	for name, id in pairs(SPELL_IDS) do rows[#rows + 1] = { "shared", name, id } end
	for token, p in pairs(profiles) do
		local ids = type(p.ids) == "table" and p.ids or {}
		for _, name in ipairs(ProfileSpells(p)) do
			if ids[name] or not SPELL_IDS[name] then rows[#rows + 1] = { token, name, ids[name] } end
		end
	end
	table.sort(rows, function(a, b)
		if a[1] ~= b[1] then return a[1] < b[1] end
		return a[2] < b[2]
	end)

	local report = {
		at = date("%Y-%m-%d %H:%M:%S"), locale = GetLocale and GetLocale(),
		checked = 0, match = 0, wrong = {}, noID = {}, found = {}, notFound = {},
	}
	local want, left = {}, 0
	local function Want(name)
		if not want[name] then want[name], left = true, left + 1 end
	end
	for _, r in ipairs(rows) do
		local where, name, id = r[1], r[2], r[3]
		local key = where .. ": " .. name
		if id then
			report.checked = report.checked + 1
			local got = SpellNameOf(id)
			if got == name then
				report.match = report.match + 1
			else
				report.wrong[#report.wrong + 1] = ("%s: %d is %s"):format(key, id, got or "no spell") -- locale: skip a debug line
				Want(name)
			end
		else
			report.noID[#report.noID + 1] = key
			Want(name)
		end
	end

	say(("Spell IDs: %d of %d match their enUS name."):format(report.match, report.checked)) -- locale: skip a debug line
	for _, line in ipairs(report.wrong) do out("  " .. line) end
	if #report.noID > 0 then say(("%d class file names have no ID."):format(#report.noID)) end -- locale: skip a debug line

	-- The rank you know, by name: cheap, and the right spell.
	for name in pairs(want) do
		local id = ns.SpellID(name)
		if id and SpellNameOf(id) == name then
			report.found[name] = id
			left = left - 1
		end
	end

	local function Finish()
		scanning = false
		local names = {}
		for name in pairs(want) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local id = report.found[name]
			if id then
				out(("  %s = %d"):format(name, id))
			else
				report.notFound[#report.notFound + 1] = name
			end
		end
		if #report.notFound > 0 then
			say(("No spell ID has these names: %s."):format(table.concat(report.notFound, ", "))) -- locale: skip a debug line
		end
		if HUDiniDB then
			HUDiniDB.spellIDReport = report
			say(ns.Text("debug.saved"))
		end
	end

	if left == 0 then return Finish() end
	say(ns.Text("debug.idsLooking", left))
	scanning = true
	local from = 1
	local function Step()
		local scan = ns.SPELL_SCAN
		local to = math.min(from + scan.step - 1, scan.to)
		for id = from, to do
			local name = SpellNameOf(id)
			if name and want[name] and not report.found[name] then
				report.found[name] = id
				left = left - 1
			end
		end
		from = to + 1
		if left <= 0 or from > scan.to then return Finish() end
		C_Timer.After(0, Step)
	end
	C_Timer.After(0, Step)
end

--------------------------------------------------------------------------------
-- Saved settings
--------------------------------------------------------------------------------

-- Called at every login, once HUDiniDB is loaded, migrated (ns.Migrate) and
-- filled with defaults. It is not a migration: each class gets it the first
-- time you log in on it.
function ns.FillClassSettings()
	local db = HUDiniDB
	local mine = ns.ClassDB()

	-- Each class keeps its own grid position. A class seen for the first time
	-- starts at the account-wide position.
	if mine.point == nil then
		mine.point, mine.relPoint = db.point, db.relPoint
		mine.x, mine.y = db.x, db.y
	end
end

--------------------------------------------------------------------------------
-- Your picks, for the "Your class" page (TICK-0069)
--
-- One pick is a string: ns.PICK_DEFAULT (the class file's choice), ns.PICK_NONE,
-- or a spell name. A page row's getter is ns.GetClassPick, its setter
-- ns.SetClassPick. The setter only writes HUDiniDB.classes[token]; the row's
-- value-changed callback applies once (HUDini:QueueApply), and that refreshes
-- every alert and bar that reads a pick.
--
-- What each pick saves, so ns.ClassValue and the alerts read it as before:
--   interrupt, purge   "Name"            None: false
--   dispel             dispel[Type] = "Name"; None: dispel[Type] = false
--   keepUp             { "Name" }        None: {}
--   resource           { aura = "Name", max = stacks }; None: false
-- Class default clears the choice (nil). A saved dispel type replaces only
-- the class file's spell for that type.
--------------------------------------------------------------------------------

-- Neither can be a spell name.
ns.PICK_DEFAULT = "#default"
ns.PICK_NONE    = "#none"

-- The page's order.
ns.DISPEL_TYPES = { "Curse", "Poison", "Disease", "Magic" }

local PICK_KEYS = { interrupt = true, dispel = true, purge = true, keepUp = true, resource = true }
local IS_DISPEL_TYPE = {}
for _, dispelType in ipairs(ns.DISPEL_TYPES) do IS_DISPEL_TYPE[dispelType] = true end

local MAX_STACKS, DEFAULT_STACKS = 20, 5

-- The spells a row offers, A to Z, each once. Resource offers the buffs
-- HUDini saw stack on you (Auras.lua, TICK-0094): a spell on the action bars
-- says nothing about its buff's stacks, so those picks made bars that never
-- filled. Every other row offers the spells on your action bars.
function ns.ClassPickSpells(key)
	if key ~= "resource" then return ns.ActionBarSpells() end
	local names = {}
	local learned = ns.ClassDB().stackBuffs
	if type(learned) == "table" then
		for name, on in pairs(learned) do
			if type(on) == "number" and on >= 2 and type(name) == "string" then names[#names + 1] = name end
		end
	end
	table.sort(names)
	return names
end

-- Your saved choice for one row, as it is in HUDiniDB. ok is false for a row
-- that does not exist.
local function Saved(key, dispelType)
	if not PICK_KEYS[key] then return false end
	local mine = ns.ClassDB()
	if key ~= "dispel" then return true, mine[key] end
	if not IS_DISPEL_TYPE[dispelType] then return false end
	-- Not "and ... or nil": that would read a saved false (None) as nil.
	if type(mine.dispel) ~= "table" then return true, nil end
	return true, mine.dispel[dispelType]
end

-- A saved value as the string the page shows. A list (an interrupt typed as
-- "Pummel, Shield Bash") shows as it is typed.
local function AsPick(key, value)
	if value == nil then return ns.PICK_DEFAULT end
	if value == false then return ns.PICK_NONE end
	if key == "resource" then
		return type(value) == "table" and value.aura and tostring(value.aura) or ns.PICK_DEFAULT
	end
	if type(value) == "table" then
		if #value == 0 then return ns.PICK_NONE end
		local names = {}
		for i, spell in ipairs(value) do names[i] = tostring(spell) end
		return table.concat(names, ", ")
	end
	return tostring(value)
end

-- The pick for one row of the class you are playing. dispelType is one of
-- ns.DISPEL_TYPES, for key "dispel" only. nil for a row that does not exist.
function ns.GetClassPick(key, dispelType)
	local ok, value = Saved(key, dispelType)
	if not ok then return nil end
	return AsPick(key, value)
end

-- Save a pick. True if it changed what is saved. A pick equal to the row's
-- current value changes nothing, so a list or a typed ID is kept as it is.
function ns.SetClassPick(key, pick, dispelType)
	local ok, old = Saved(key, dispelType)
	if not ok or type(pick) ~= "string" or pick == "" then return false end
	if pick == AsPick(key, old) then return false end

	local value
	if pick == ns.PICK_DEFAULT then
		value = nil
	elseif pick == ns.PICK_NONE then
		value = (key == "keepUp") and {} or false
	else
		local spell = tonumber(pick) or pick
		if key == "keepUp" then
			value = { spell }
		elseif key == "resource" then
			-- A buff HUDini saw stack fills at the most stacks seen (TICK-0094).
			local seen = ns.ClassDB().stackBuffs
			seen = type(seen) == "table" and seen[pick]
			local stacks = type(seen) == "number" and math.max(1, math.min(MAX_STACKS, math.floor(seen)))
				or type(old) == "table" and old.max or DEFAULT_STACKS
			value = { aura = pick, max = stacks }
		else
			value = spell
		end
	end

	local mine = ns.ClassDB()
	if key == "dispel" then
		mine.dispel = type(mine.dispel) == "table" and mine.dispel or {}
		mine.dispel[dispelType] = value
		if next(mine.dispel) == nil then mine.dispel = nil end
	else
		mine[key] = value
	end
	return true
end

--------------------------------------------------------------------------------
-- Cooldown ready alerts (TICK-0157, GitHub #1)
--
-- A spell you turn on plays a sound, and its icon on the HUD glows, when its
-- cooldown ends (Alerts.lua, section 9). Each spell is off until you turn it
-- on, unless the class file's readyAlertOn names it: then it starts on
-- until you save a choice (D-047, TICK-0181). The class file's readyAlert
-- list is what the page offers first, then every other spell you learned
-- that has a cooldown and every readyAlertOn spell you know (TICK-0162,
-- D-042).
-- Saved per class, off as false so it wins over a start of on:
--   HUDiniDB.classes[token].readyAlerts = { ["Name"] = true | false }
-- The name is the one the page offered (the client's language). Before
-- TICK-0181 an Off saved nothing, so it reads as the class file's start.
--------------------------------------------------------------------------------

-- Every spell you learned with a cooldown of its own, A to Z, from your
-- spellbook. A spell counts when its book entry is a learned spell (not a
-- future one, not passive, not of your other spec, not a guild perk) and
-- the game gives it a base cooldown above zero or two or more charges.
-- The book is read only out of a fight: when the list is first asked for,
-- a moment after each SPELLS_CHANGED, and when a fight ends after one. In
-- a fight the last list stands. A secret, missing or failed answer leaves
-- that spell out and marks the list unsure, so the book is read again; a
-- book with no spell in it yet (early at login) is unsure too. When a
-- read changes the list, each function given to ns.WatchLearnedCooldowns
-- runs (the options page rebuilds its rows).
local learnedCooldowns -- the names, A to Z; nil until the book was read
local learnedStale = true
local learnedPending = false -- a read is due a moment after SPELLS_CHANGED
local learnedWatchers = {}

local function BookEnum(enum, key, fallback)
	local t = Enum and Enum[enum]
	local v = t and t[key]
	if type(v) == "number" then return v end
	return fallback
end

-- Whether the game plainly gives the spell a cooldown: a base cooldown
-- above zero (milliseconds), or two or more charges. The second value is
-- true when an answer was secret or failed, so the first may be wrong.
local function HasCooldown(id)
	local unsure = false
	local base = (C_Spell and C_Spell.GetSpellBaseCooldown) or _G.GetSpellBaseCooldown
	if type(base) == "function" then
		local ok, ms = pcall(base, id)
		ms = ok and ns.Plain(ms) or nil
		if type(ms) ~= "number" then
			unsure = true
		elseif ms > 0 then
			return true, false
		end
	end
	local charges = C_Spell and C_Spell.GetSpellCharges
	if type(charges) == "function" then
		local ok, info = pcall(charges, id)
		if not ok or (info ~= nil and type(info) ~= "table") then
			unsure = true
		elseif info then
			-- type() is safe on a secret value; a compare is not.
			local raw = info.maxCharges
			local max = ns.Plain(raw)
			if type(max) == "number" and max >= 2 then return true, false end
			if type(max) ~= "number" and type(raw) ~= "nil" then unsure = true end
		end
	end
	return false, unsure
end

-- A flag of a book entry or line: true, false, or nil when it is missing.
-- A secret flag counts as true, so the entry is left out.
local function Flag(v)
	if ns.IsSecret(v) then return true end
	return v == true
end

-- One spellbook entry. Returns its ID and name (nil, nil when it is not a
-- learned spell you can cast), true when it is a spell entry at all, and
-- true when an answer was secret or missing, so the entry may be wrong.
local function BookSpell(info)
	local itemType = ns.Plain(info.itemType)
	if itemType == nil then return nil, nil, false, true end
	if itemType ~= BookEnum("SpellBookItemType", "Spell", 1) then return nil, nil, false, false end -- locale: skip an enum key
	local secretFlag = ns.IsSecret(info.isPassive) or ns.IsSecret(info.isOffSpec)
	if Flag(info.isPassive) or Flag(info.isOffSpec) then return nil, nil, true, secretFlag end
	local id, name = ns.Plain(info.spellID), ns.Plain(info.name)
	if type(id) ~= "number" or id <= 0 or type(name) ~= "string" or name == "" then
		return nil, nil, true, true
	end
	return id, name, true, false
end

-- The names, A to Z, and true when some part could not be read. nil when
-- this client has no spellbook API.
local function ReadBook()
	local book = _G.C_SpellBook
	if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo
		and book.GetSpellBookItemInfo) then
		return nil
	end
	local bank = BookEnum("SpellBookSpellBank", "Player", 0) -- locale: skip an enum key
	local ok, lines = pcall(book.GetNumSpellBookSkillLines)
	lines = ok and ns.Plain(lines) or nil
	if type(lines) ~= "number" then return nil end
	local names, seen, unsure, spells = {}, {}, false, 0
	for l = 1, lines do
		local okLine, line = pcall(book.GetSpellBookSkillLineInfo, l)
		local offset = okLine and type(line) == "table" and ns.Plain(line.itemIndexOffset) or nil
		local count = okLine and type(line) == "table" and ns.Plain(line.numSpellBookItems) or nil
		if type(offset) ~= "number" or type(count) ~= "number" then
			unsure = true
		elseif not (Flag(line.isGuild) or Flag(line.shouldHide)) then
			for i = offset + 1, offset + count do
				local okItem, info = pcall(book.GetSpellBookItemInfo, i, bank)
				local okRead, id, name, isSpell, odd = false, nil, nil, false, false
				if okItem and type(info) == "table" then
					okRead, id, name, isSpell, odd = pcall(BookSpell, info)
				end
				if not okRead or odd then unsure = true end
				if okRead and isSpell then spells = spells + 1 end
				if okRead and id and not seen[name] then
					local okCd, has, cdUnsure = pcall(HasCooldown, id)
					if not okCd or cdUnsure then unsure = true end
					if not okCd then has = false end
					if has then
						seen[name] = true
						names[#names + 1] = name
					end
				end
			end
		end
	end
	if spells == 0 then unsure = true end
	table.sort(names)
	return names, unsure
end

-- Reads the book when it is due and not in a fight. Returns true when the
-- list changed.
local function Refresh()
	if not learnedStale or InCombatLockdown() then return false end
	local names, unsure = ReadBook()
	if not names then return false end
	local old = learnedCooldowns or {}
	learnedCooldowns = names
	learnedStale = unsure and true or false
	if #old ~= #names then return true end
	for i, name in ipairs(names) do
		if old[i] ~= name then return true end
	end
	return false
end

-- fn() runs after a read out of a fight changes the list. It does not run
-- for the read that ns.LearnedCooldownSpells itself makes.
function ns.WatchLearnedCooldowns(fn)
	if type(fn) == "function" then learnedWatchers[#learnedWatchers + 1] = fn end
end

local function ReadAndTell()
	learnedPending = false
	if not Refresh() then return end
	for _, fn in ipairs(learnedWatchers) do
		local ok, err = pcall(fn)
		if not ok then
			local handler = geterrorhandler and geterrorhandler()
			if handler then handler(err) end
		end
	end
end

-- SPELLS_CHANGED can come many times in a row (login, a new level, a
-- form): one read a moment after the first.
local function ReadSoon()
	if learnedPending then return end
	learnedPending = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, ReadAndTell)
	else
		ReadAndTell()
	end
end

local learnedWatch = CreateFrame("Frame")
learnedWatch:RegisterEvent("SPELLS_CHANGED")
learnedWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
learnedWatch:SetScript("OnEvent", function(_, event)
	if event == "SPELLS_CHANGED" then learnedStale = true end
	if learnedStale then ReadSoon() end
end)

-- A copy of the list, A to Z. Empty before the first read out of a fight.
function ns.LearnedCooldownSpells()
	Refresh()
	local out = {}
	for i, name in ipairs(learnedCooldowns or {}) do out[i] = name end
	return out
end

-- The spells to offer: the class file's list in its order, then every
-- other spell you learned with a cooldown and any other spell you turned
-- on, together A to Z. Each once. The second value is how many of the
-- first are the class file's, for the page to group them.
function ns.ReadyAlertSpells()
	local out, seen = {}, {}
	local list = ns.ClassDefault("readyAlert")
	if type(list) == "table" then
		for _, name in ipairs(list) do
			if type(name) == "string" and name ~= "" and not seen[name] then
				seen[name] = true
				out[#out + 1] = name
			end
		end
	end
	local classCount = #out
	local extra = {}
	local function Add(name)
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			extra[#extra + 1] = name
		end
	end
	for _, name in ipairs(ns.LearnedCooldownSpells()) do Add(name) end
	-- A spell that starts on, when you know it: a class file may name every
	-- race's cooldown (D-047), and another race's is no row of yours.
	local starts = ns.ClassDefault("readyAlertOn")
	if type(starts) == "table" then
		for _, name in ipairs(starts) do
			if not ns.KnownSpell or ns.KnownSpell(name) then Add(name) end
		end
	end
	local saved = HUDiniDB and ns.ClassDB().readyAlerts
	if type(saved) == "table" then
		for name, on in pairs(saved) do
			if on == true then Add(name) end
		end
	end
	table.sort(extra)
	for _, name in ipairs(extra) do out[#out + 1] = name end
	return out, classCount
end

-- True when the ready alert for this spell name is on: your saved choice,
-- else true when the class file's readyAlertOn names it (D-047).
function ns.GetReadyAlert(spell)
	if type(spell) ~= "string" or not HUDiniDB then return false end
	local saved = ns.ClassDB().readyAlerts
	local mine
	if type(saved) == "table" then mine = saved[spell] end
	if mine ~= nil then return mine == true end
	local starts = ns.ClassDefault("readyAlertOn")
	if type(starts) ~= "table" then return false end
	for _, name in ipairs(starts) do
		if name == spell then return true end
	end
	return false
end

-- Turn one spell's ready alert on or off. True if it changed. The watch
-- (Alerts.lua) takes the change at once.
function ns.SetReadyAlert(spell, on)
	if type(spell) ~= "string" or spell == "" or not HUDiniDB then return false end
	on = on and true or false
	if ns.GetReadyAlert(spell) == on then return false end
	local mine = ns.ClassDB()
	mine.readyAlerts = type(mine.readyAlerts) == "table" and mine.readyAlerts or {}
	-- Off saves false, so it wins over the class file's start (D-047).
	mine.readyAlerts[spell] = on
	if ns.RefreshReadyAlerts then ns.RefreshReadyAlerts() end
	return true
end

--------------------------------------------------------------------------------
-- Missing items (TICK-0182, D-047)
--
-- The class file's missingItem rows: an item you make (make) or need for a
-- spell (needs). Alerts.lua shows an icon by your health bar, out of a
-- fight, when your bags hold none. Each row has a choice per class, by its
-- key:
--   HUDiniDB.classes[token].missingItem = { manaGem = false }
-- nil is the class file's on. Off saves false, so it wins over the start.
--------------------------------------------------------------------------------

-- A row HUDini can use: a key, items, and make or needs.
function ns.MissingItemValid(row)
	return type(row) == "table" and type(row.key) == "string" and row.key ~= ""
		and type(row.items) == "table" and (row.make ~= nil or row.needs ~= nil)
end

-- The usable rows of your class file, in its order.
function ns.MissingItemRows()
	local out, list = {}, ns.ClassDefault("missingItem")
	if type(list) ~= "table" then return out end
	for _, row in ipairs(list) do
		if ns.MissingItemValid(row) then out[#out + 1] = row end
	end
	return out
end

-- True when the row's alert is on: your saved choice, else the row's on.
-- Makes no table, so the HUD's poll can ask it (Alerts.lua).
function ns.MissingItemOn(row)
	if not (HUDiniDB and ns.MissingItemValid(row)) then return false end
	local saved = ns.ClassDB().missingItem
	if type(saved) == "table" and saved[row.key] ~= nil then return saved[row.key] == true end
	return row.on == true
end

function ns.GetMissingItem(key)
	for _, row in ipairs(ns.MissingItemRows()) do
		if row.key == key then return ns.MissingItemOn(row) end
	end
	-- A key your class file no longer has: only a saved on counts.
	local saved = HUDiniDB and ns.ClassDB().missingItem
	return type(saved) == "table" and saved[key] == true
end

-- Turn one row's alert on or off. True if it changed. The icon looks again
-- at once.
function ns.SetMissingItem(key, on)
	if type(key) ~= "string" or key == "" or not HUDiniDB then return false end
	on = on and true or false
	if ns.GetMissingItem(key) == on then return false end
	local mine = ns.ClassDB()
	mine.missingItem = type(mine.missingItem) == "table" and mine.missingItem or {}
	mine.missingItem[key] = on
	if ns.UpdateMissingItem then ns.UpdateMissingItem() end
	return true
end

--------------------------------------------------------------------------------
-- Cooldown timer bars (TICK-0158, GitHub #2)
--
-- A spell you turn on gets a bar under the HUD while its cooldown runs
-- (TimerBars.lua). The page offers the same spells as the ready alerts:
-- the class file's readyAlert list, then any other spell turned on here.
-- Saved per class:
--   HUDiniDB.classes[token].timerBars = { ["Name"] = true }
--------------------------------------------------------------------------------

-- The spells to offer: the class file's list in its order, then any other
-- spell with a bar on, A to Z. Each once.
function ns.TimerBarSpells()
	local out, seen = {}, {}
	local list = ns.ClassDefault("readyAlert")
	if type(list) == "table" then
		for _, name in ipairs(list) do
			if type(name) == "string" and name ~= "" and not seen[name] then
				seen[name] = true
				out[#out + 1] = name
			end
		end
	end
	local saved = HUDiniDB and ns.ClassDB().timerBars
	local extra = {}
	if type(saved) == "table" then
		for name, on in pairs(saved) do
			if on == true and type(name) == "string" and name ~= "" and not seen[name] then
				extra[#extra + 1] = name
			end
		end
	end
	table.sort(extra)
	for _, name in ipairs(extra) do out[#out + 1] = name end
	return out
end

-- True when this spell name has a timer bar.
function ns.GetTimerBar(spell)
	if type(spell) ~= "string" or not HUDiniDB then return false end
	local saved = ns.ClassDB().timerBars
	return type(saved) == "table" and saved[spell] == true
end

-- Turn one spell's timer bar on or off. True if it changed. The bars
-- (TimerBars.lua) take the change at once; the first bar turns the part on.
function ns.SetTimerBar(spell, on)
	if type(spell) ~= "string" or spell == "" or not HUDiniDB then return false end
	on = on and true or false
	if ns.GetTimerBar(spell) == on then return false end
	local mine = ns.ClassDB()
	mine.timerBars = type(mine.timerBars) == "table" and mine.timerBars or {}
	mine.timerBars[spell] = on or nil
	if next(mine.timerBars) == nil then mine.timerBars = nil end
	if ns.UpdateModules then ns.UpdateModules() end
	if ns.RefreshTimerBars then ns.RefreshTimerBars() end
	return true
end

-- Stacks to fill: the number for a resource spell you picked, else nil (the
-- slider is gray: the class file or the game sets the number).
function ns.ResourceStacks()
	local r = ns.ClassDB().resource
	if type(r) == "table" and r.aura then return r.max or DEFAULT_STACKS end
	return nil
end

-- True if it changed. Only for a resource spell you picked; 1 to 20.
function ns.SetResourceStacks(n)
	local r = ns.ClassDB().resource
	n = tonumber(n)
	if not (type(r) == "table" and r.aura and n) then return false end
	n = math.max(1, math.min(MAX_STACKS, math.floor(n)))
	if r.max == n then return false end
	r.max = n
	return true
end

-- The game's name for a power, by its Enum.PowerType key ("ComboPoints"):
-- its global string (COMBO_POINTS, "Combo Points"), else the key with
-- spaces ("Combo Points").
function ns.PowerName(key)
	if type(key) ~= "string" then return nil end
	local token = key:gsub("(%l)(%u)", "%1_%2"):upper()
	for _, name in ipairs({ token, token .. "_POWER" }) do
		local text = _G[name]
		if type(text) == "string" and text ~= "" then return text end
	end
	return (key:gsub("(%l)(%u)", "%1 %2"))
end

-- The name after "Class default: " for one row, or nil for none. For the
-- combat buff it is the first spell in the class file's list that you know;
-- when you know none of them yet, the second value is true.
function ns.ClassDefaultName(key, dispelType)
	if not PICK_KEYS[key] then return nil end
	local default = ns.ClassDefault(key)
	if key == "dispel" then
		if not IS_DISPEL_TYPE[dispelType] then return nil end
		default = type(default) == "table" and default[dispelType] or nil
	elseif key == "purge" and type(default) == "table" then
		default = default.spell
	elseif key == "keepUp" then
		if type(default) ~= "table" or #default == 0 then return nil end
		for _, spell in ipairs(default) do
			if ns.KnownSpell and ns.KnownSpell(spell) then return ns.SpellLabel(spell) end
		end
		return nil, true
	elseif key == "resource" then
		if type(default) ~= "table" then return nil end
		if default.power then return ns.PowerName(default.power) end
		return default.aura and tostring(default.aura) or nil
	end
	if default == nil then return nil end
	return AsPick(key, default)
end
