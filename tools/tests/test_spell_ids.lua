-- Spells in the client's language (TICK-0024). Data names spells in enUS;
-- on another client each name becomes the game's own, from a spell ID
-- (Classes.lua SPELL_IDS, or a class file's ids). An English client does
-- not change. Also the fishing pole by its weapon kind, the creature type
-- "Not specified" by its type ID, and /hud debug ids.

-- German names for some IDs in SPELL_IDS and one class file ID.
local DE = {
	[1784]  = "Verstohlenheit",           -- Stealth
	[2383]  = "Kräutersuche",             -- Find Herbs
	[5697]  = "Unendlicher Atem",         -- Unending Breath
	[1459]  = "Arkane Intelligenz",       -- Arcane Intellect
	[23028] = "Arkane Brillanz",          -- Arcane Brilliance
	[19740] = "Segen der Macht",          -- Blessing of Might
	[25782] = "Großer Segen der Macht",   -- Greater Blessing of Might
	[1044]  = "Segen der Freiheit",       -- Blessing of Freedom
	[433]   = "Essen",                    -- Food
	[19705] = "Satt",                     -- Well Fed
	[2139]  = "Gegenzauber",              -- Counterspell (a class file's ids)
}

-- A world on a client in locale, whose GetSpellName answers from names.
local function World(locale, names, setup)
	local w = H.world()
	w.env.GetLocale = function() return locale end
	w.env.C_Spell.GetSpellName = function(id) return names[id] end
	if setup then setup(w) end
	w:loadAddon()
	return w, w.ns
end

local function Has(list, name)
	for _, x in ipairs(list) do
		if x == name then return true end
	end
	return false
end

H.test("on a German client the shared names match by the German name, and the enUS ones still do", function()
	local _, ns = World("deDE", DE)
	H.eq(ns.IsStateBuff("Verstohlenheit"), true, "Stealth by its German name")
	H.eq(ns.IsStateBuff("Stealth"), true, "and by its enUS name")
	H.eq(ns.IsTrackingBuff("Kräutersuche"), true, "Find Herbs by its German name")
	H.eq(ns.IsStateBuff("Arkane Intelligenz"), false, "a buff to keep up is no state")
	H.eq(ns.LocalSpellName("Unending Breath"), "Unendlicher Atem")
	H.eq(ns.LocalSpellName("Prowl"), "Prowl", "no German name from the client: enUS")
end)

H.test("on a German client the buff pairs and Food map to the German names", function()
	local _, ns = World("deDE", DE)
	local map = ns.AuraMapFor("Arkane Intelligenz")
	H.ok(Has(map, "Arkane Brillanz"), "Arcane Intellect is covered by Arcane Brilliance")
	H.ok(Has(ns.AuraMapFor("Arkane Brillanz"), "Arkane Intelligenz"), "and the other way")
	H.ok(Has(ns.AuraMapFor("Essen"), "Satt"), "Food ends in Well Fed")
	H.eq(#ns.AuraMapFor("Arcane Intellect"), 0, "the enUS key is not the client's")
end)

H.test("a paladin's blessing is known by its German name; another buff is not", function()
	local _, ns = World("deDE", DE)
	H.eq(ns.IsBlessing("Segen der Macht"), true)
	H.eq(ns.IsBlessing("Großer Segen der Macht"), true)
	H.eq(ns.IsBlessing("Segen der Freiheit"), true, "the short ones count, as before")
	H.eq(ns.IsBlessing("Blessing of Might"), true, "the enUS name too")
	H.eq(ns.IsBlessing("Arkane Intelligenz"), false)
	H.eq(ns.IsBlessing("Blessing of the Ancients"), false, "a name is no blessing for its words")
end)

-- A world for a German player whose buffs are by name: w.auras[name] =
-- duration (on you, cast by you). Each name in DE is a spell you know.
local function BuffWorld(class, className)
	local w = H.world()
	w.class, w.className = class, className
	local env = w.env
	env.GetLocale = function() return "deDE" end
	env.C_Spell.GetSpellName = function(id) return DE[id] end
	env.C_Spell.GetSpellInfo = function(n)
		for id, name in pairs(DE) do
			if name == n then return { spellID = id, name = n } end
		end
	end
	env.IsPlayerSpell = function(id) return DE[id] ~= nil end
	env.SpellHasRange = function() return true end
	w.auras = {}
	local function Aura(n)
		local d = w.auras[n]
		if not d then return nil end
		local id
		for k, name in pairs(DE) do
			if name == n then id = k end
		end
		return { auraInstanceID = 7, name = n, spellId = id, duration = d, expirationTime = 2000 }
	end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(unit, n)
		if unit == "player" then return Aura(n) end
	end
	env.C_UnitAuras.GetAuraDataByIndex = function(unit, i)
		if unit ~= "player" then return nil end
		local list = {}
		for n in pairs(w.auras) do list[#list + 1] = n end
		table.sort(list)
		return list[i] and Aura(list[i]) or nil
	end
	w:loadAddon()
	w.ns.HUDini.spells = {}
	return w, w.ns
end

H.test("a one-job buff with a German name is not learned; a buff to keep up is", function()
	local w, ns = BuffWorld("WARLOCK", "Warlock")
	w.auras["Unendlicher Atem"] = 600
	w.auras["Arkane Intelligenz"] = 3600
	ns.UpdateBuffMissing()
	local learned = ns.ClassDB().buffSpells or {}
	H.eq(learned["Unendlicher Atem"], nil, "Unending Breath is for one job")
	H.eq(learned["Arkane Intelligenz"], true, "Arcane Intellect is learned")
end)

H.test("a German paladin's blessing on the target counts as theirs: no target buff icon", function()
	local w, ns = BuffWorld("PALADIN", "Paladin")
	ns.ClassDB().buffSpells = { ["Segen der Macht"] = true }
	w.env.UnitIsPlayer = function() return true end
	local mine = nil   -- your blessing on the target, by name
	w.env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		if unit == "target" and i == 1 and mine and filter == "HELPFUL|PLAYER" then
			return { auraInstanceID = 9, name = mine, duration = 600, expirationTime = 2000 }
		end
	end
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	local function Shown()
		local bar = ns.GetBar("targethealth")
		for _, f in ipairs(w.frames) do
			local point, to, rel = f:GetPoint(1)
			if f:GetParent() == bar and f.tex and point == "RIGHT" and to == bar and rel == "LEFT" then
				return f:IsShown()
			end
		end
		return false
	end
	H.eq(Shown(), true, "no blessing of yours: Blessing of Might is missing")
	mine = "Segen der Freiheit"
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(Shown(), false, "your Blessing of Freedom on them: one blessing each")
end)

H.test("a class file's ids give its spells the client's name", function()
	local _, ns = World("deDE", DE, function(w)
		w.class, w.className = "TESTER", "Tester"
	end)
	ns.RegisterClass("TESTER", {
		interrupt = "Counterspell",
		dispel = { Curse = "Remove Lesser Curse" },
		auraMap = { ["Counterspell"] = { "Arcane Intellect" } },
		powers = { "MANA" },
		ids = { ["Counterspell"] = 2139 },
	})
	H.eq(ns.ClassDefault("interrupt"), "Gegenzauber")
	H.eq(ns.ClassDefault("dispel").Curse, "Remove Lesser Curse", "no ID: enUS; the type token stays")
	H.eq(ns.ClassDefault("auraMap")["Gegenzauber"][1], "Arkane Intelligenz", "keys and values")
	H.eq(ns.ClassDefault("powers")[1], "MANA", "a power token stays")
	H.eq(ns.ClassValue("interrupt"), "Gegenzauber", "the value the alerts use")
end)

H.test("an ID the client has no name for keeps the enUS name, and is asked again after SPELLS_CHANGED", function()
	local names = {}
	local w, ns = World("deDE", names)
	H.eq(ns.IsStateBuff("Verstohlenheit"), false, "no name yet")
	H.eq(ns.IsStateBuff("Stealth"), true, "the enUS name works meanwhile")
	names[1784] = "Verstohlenheit"
	w:fire("SPELLS_CHANGED")
	H.eq(ns.IsStateBuff("Verstohlenheit"), true, "the name once the client has it")
end)

H.test("an ID with no name is asked once, not at each aura update", function()
	local asked = 0
	local w, ns = World("deDE", DE, function(w0)
		w0.class, w0.className = "TESTER", "Tester"
	end)
	w.env.C_Spell.GetSpellName = function(id) asked = asked + 1; return DE[id] end
	ns.RegisterClass("TESTER", { interrupt = "Counterspell", ids = { ["Counterspell"] = 99999 } })
	for _ = 1, 3 do
		ns.IsStateBuff("Verstohlenheit")
		ns.IsTrackingBuff("Kräutersuche")
		ns.IsBlessing("Segen der Macht")
		ns.AuraMapFor("Arkane Intelligenz")
		ns.ClassDefault("interrupt")
		ns.LocalSpellName("Prowl")
	end
	local once = asked
	H.ok(once > 0, "the names were asked")
	local set = ns.NameSet({ "Stealth", "Shadowmeld" })
	H.ok(rawequal(set(), set()), "a set with a kept miss is kept, not built at each call")
	ns.IsStateBuff("Verstohlenheit")
	ns.IsTrackingBuff("Kräutersuche")
	ns.IsBlessing("Segen der Macht")
	ns.AuraMapFor("Arkane Intelligenz")
	H.eq(ns.LocalSpellName("Prowl"), "Prowl", "a miss asked by itself")
	H.eq(ns.ClassDefault("interrupt"), "Counterspell", "no name: enUS")
	H.eq(asked, once, "GetSpellName calls after the first pass")
	w:fire("SPELLS_CHANGED")
	ns.ClassDefault("interrupt")
	H.ok(asked > once, "a miss is asked again after SPELLS_CHANGED")
end)

H.test("a name that comes after a miss or a secret reaches the icons' buff names and the aura map", function()
	for _, how in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "secret" }) do
		local names = {}
		for id, name in pairs(DE) do names[id] = name end
		names[23028] = how == "secret" and "SECRET" or nil
		local w, ns = World("deDE", names, function(w0)
			w0.env.issecretvalue = function(v) return v == "SECRET" end
		end)
		local e = { spellID = 1459 }
		ns.HUDini.spells = { e }
		H.eq(table.concat(ns.AuraNames(e), ","), "Arkane Intelligenz,Arcane Brilliance", how .. ": enUS for now")
		names[23028] = "Arkane Brillanz"
		w:fire(how == "PLAYER_ENTERING_WORLD" and how or "SPELLS_CHANGED")
		-- A loading screen scans the bars again: new icons, new names.
		if how ~= "PLAYER_ENTERING_WORLD" then
			H.eq(table.concat(ns.AuraNames(e), ","), "Arkane Intelligenz,Arkane Brillanz", how .. ": the icon")
		end
		H.ok(Has(ns.AuraMapFor("Arkane Intelligenz"), "Arkane Brillanz"), how .. ": the aura map")
	end
end)

H.test("a secret is the only gap: the icons still get the name at the next SPELLS_CHANGED", function()
	local names = {}
	local w, ns = World("deDE", names, function(w0)
		w0.env.issecretvalue = function(v) return v == "SECRET" end
	end)
	for name, id in pairs(ns.SPELL_IDS) do names[id] = DE[id] or name end
	names[23028] = "SECRET"
	w:fire("SPELLS_CHANGED")
	local e = { spellID = 1459 }
	ns.HUDini.spells = { e }
	H.eq(table.concat(ns.AuraNames(e), ","), "Arkane Intelligenz,Arcane Brilliance", "a secret: enUS for now")
	names[23028] = "Arkane Brillanz"
	w:fire("SPELLS_CHANGED")
	H.eq(table.concat(ns.AuraNames(e), ","), "Arkane Intelligenz,Arkane Brillanz")
end)

H.test("at SPELLS_CHANGED the icons are built again at once, from the new names", function()
	for _, how in ipairs({ "miss", "secret" }) do
		local names = {}
		local w, ns = World("deDE", names, function(w0)
			w0.env.issecretvalue = function(v) return v == "SECRET" end
		end)
		for name, id in pairs(ns.SPELL_IDS) do names[id] = DE[id] or name end
		names[23028] = how == "secret" and "SECRET" or nil
		w:fire("SPELLS_CHANGED")
		local e = { spellID = 1459 }
		ns.HUDini.spells = { e }
		-- In the game the icons read their buff names at once (the harness
		-- has no GetAuraDuration, so the real one returns early).
		local seen
		ns.UpdateIconAuras = function() seen = table.concat(ns.AuraNames(e), ",") end
		ns.UpdateIconAuras()
		H.eq(seen, "Arkane Intelligenz,Arcane Brilliance", how .. ": enUS for now")
		if how == "secret" then
			w:fire("SPELLS_CHANGED")
			H.eq(seen, "Arkane Intelligenz,Arcane Brilliance", "still secret at the rebuild")
		end
		names[23028] = "Arkane Brillanz"
		w:fire("SPELLS_CHANGED")
		H.eq(seen, "Arkane Intelligenz,Arkane Brillanz", how .. ": built again at the event")
	end
end)

H.test("a secret name is not kept: the class file value and the aura map take the name when it comes", function()
	local names = { [2139] = "SECRET", [1459] = "SECRET", [23028] = "Arkane Brillanz" }
	local _, ns = World("deDE", names, function(w)
		w.class, w.className = "TESTER", "Tester"
		w.env.issecretvalue = function(v) return v == "SECRET" end
	end)
	ns.RegisterClass("TESTER", { interrupt = "Counterspell", ids = { ["Counterspell"] = 2139 } })
	H.eq(ns.ClassDefault("interrupt"), "Counterspell", "a secret: enUS for now")
	H.ok(Has(ns.AuraMapFor("Arcane Intellect"), "Arkane Brillanz"), "a secret key: enUS for now")
	names[2139], names[1459] = "Gegenzauber", "Arkane Intelligenz"
	H.eq(ns.ClassDefault("interrupt"), "Gegenzauber", "the plain name at the next call")
	H.ok(Has(ns.AuraMapFor("Arkane Intelligenz"), "Arkane Brillanz"), "the aura map too")
end)

H.test("a secret name from the client is never used", function()
	local names = { [1784] = "SECRET" }
	local _, ns = World("deDE", names, function(w)
		w.env.issecretvalue = function(v) return v == "SECRET" end
	end)
	H.eq(ns.LocalSpellName("Stealth"), "Stealth")
	H.eq(ns.IsStateBuff("SECRET"), false)
end)

for _, locale in ipairs({ "enUS", "enGB" }) do
	H.test("an " .. locale .. " client uses the enUS names and never asks for a spell's name", function()
		local asked = 0
		local w, ns = World(locale, DE)
		w.env.C_Spell.GetSpellName = function(id) asked = asked + 1; return DE[id] end
		H.eq(ns.IsStateBuff("Verstohlenheit"), false)
		H.eq(ns.IsStateBuff("Stealth"), true)
		H.eq(ns.IsBlessing("Segen der Macht"), false)
		H.ok(Has(ns.AuraMapFor("Arcane Intellect"), "Arcane Brilliance"))
		H.eq(ns.ClassDefault("interrupt"), "Counterspell", "the Mage's own")
		H.eq(asked, 0, "GetSpellName calls")
	end)
end

--------------------------------------------------------------------------------
-- The fishing pole and the creature type
--------------------------------------------------------------------------------

H.test("a fishing pole is known by its weapon kind, in any language", function()
	local w, ns = World("deDE", DE)
	w:holdItem(16, 6256, 2, 20, "Angelrute")
	H.eq(ns.HoldsFishingPole(), true, "a pole with a German name")
	w:holdItem(16, 9999, 2, 15, "Fishing Knife")
	H.eq(ns.HoldsFishingPole(), false, "a dagger with Fishing in its name")
	w:holdItem(16, nil)
	H.eq(ns.HoldsFishingPole(), false, "empty hands")
end)

-- The main hand's tooltip shows these lines.
local function Tooltip(w, lines)
	local rows = {}
	for i, text in ipairs(lines) do rows[i] = { leftText = text } end
	w.env.C_TooltipInfo = { GetInventoryItem = function() return { lines = rows } end }
end

-- A pole in the main hand on a client whose time-left formats are fmts
-- (ITEM_ENCHANT_TIME_LEFT_<key>, nil for none). Call the result with the
-- tooltip's lines to get ns.BaitMissing().
local function PoleWorld(locale, fmts)
	local w, ns = World(locale, DE, function(w0)
		for key, fmt in pairs(fmts or {}) do w0.env["ITEM_ENCHANT_TIME_LEFT_" .. key] = fmt end
	end)
	w:holdItem(16, 6256, 2, 20, "Pole")
	return function(lines)
		Tooltip(w, lines)
		return ns.BaitMissing()
	end
end

-- The enUS formats, with their plural marks.
local EN = { DAYS = "%s (%d |4day:days;)", HOURS = "%s (%d |4hour:hrs;)", MIN = "%s (%d min)", SEC = "%s (%d sec)" }

-- What a bare pole's tooltip can show: none of it is bait.
local BARE = {
	"Fishing Pole", "Main Hand", "1 - 2 Damage", "(0.7 damage per second)",
	"Requires Fishing (100)", "Angler's Set (1/4)", "Use: Summon a fish. (1 Hour Cooldown)",
}

local function With(lines, extra)
	local out = {}
	for i, x in ipairs(lines) do out[i] = x end
	out[#out + 1] = extra
	return out
end

H.test("a bare pole whose tooltip has other lines in brackets has no bait", function()
	local enUS = PoleWorld("enUS", EN)
	H.eq(enUS(BARE), true, "the client's enUS formats")
	H.eq(enUS(With(BARE, "Lure +75 (10 min)")), false, "and bait is seen")
	H.eq(enUS(With(BARE, "Lure +75 (1 hour)")), false, "one form of a plural mark")
	H.eq(enUS(With(BARE, "Lure +75 (2 hrs)")), false, "the other form")
	H.eq(enUS(With(BARE, "Lure +75 (1 |4hour:hrs;)")), false, "the mark kept in the line")
	H.eq(enUS(With(BARE, "Lure +75 (2 |4day:days;)")), false, "the mark kept, days")
	local none = PoleWorld("enUS")
	H.eq(none(BARE), true, "no format from the client: the enUS one")
	H.eq(none(With(BARE, "Lure +75 (10 min)")), false, "and bait is seen")
	local deDE = PoleWorld("deDE", { MIN = "%s (%d Min.)" })
	H.eq(deDE({ "Angelrute", "(0,7 Schaden pro Sekunde)", "Benötigt Angeln (100)" }), true, "German")
end)

H.test("bait on the pole is seen in German, Russian and Chinese, from the client's formats", function()
	local deDE = PoleWorld("deDE", { MIN = "%s (%d Min.)" })
	H.eq(deDE({ "Angelrute" }), true, "no timed line: no bait")
	H.eq(deDE({ "Angelrute", "Köder +75 (10 Min.)" }), false, "German")
	local ruRU = PoleWorld("ruRU", { MIN = "%s (%d мин.)" })
	H.eq(ruRU({ "Удочка", "Приманка +75 (10 мин.)" }), false, "Russian")
	local ru3 = PoleWorld("ruRU", { HOURS = "%s (%d |4час:часа:часов;)" })
	H.eq(ru3({ "Удочка", "Приманка +75 (1 час)" }), false, "a mark with three forms: the first")
	H.eq(ru3({ "Удочка", "Приманка +75 (2 часа)" }), false, "the second")
	H.eq(ru3({ "Удочка", "Приманка +75 (5 часов)" }), false, "the third")
	H.eq(ru3({ "Удочка" }), true, "no timed line: no bait")
	local zhCN = PoleWorld("zhCN", { MIN = "%s（%d分钟）", HOURS = "%s（%d|4小时:小时;）" })
	H.eq(zhCN({ "鱼竿", "鱼饵 +75（10分钟）" }), false, "Chinese")
	H.eq(zhCN({ "鱼竿", "鱼饵 +75（1小时）" }), false, "a format with a plural mark")
	H.eq(zhCN({ "鱼竿" }), true, "no timed line: no bait")
end)

H.test("a fishing pole needs no weapon buff; another weapon does", function()
	local w, ns = World("enUS", {}, function(w0)
		w0.class, w0.className = "TESTER", "Tester"
		w0.env.IsPlayerSpell = function(id) return id == 8017 end
		w0.env.C_Spell.GetSpellInfo = function(n)
			if n == "Rockbiter Weapon" then return { spellID = 8017, name = n } end
		end
		w0.env.GetWeaponEnchantInfo = function() return false end
	end)
	ns.RegisterClass("TESTER", { weaponBuff = { "Rockbiter Weapon" } })
	Tooltip(w, { "Some Item" })
	w:holdItem(16, 2000, 2, 7, "Sword")
	H.eq(ns.WeaponBuffMissing(), true, "a sword with no buff")
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	H.eq(ns.WeaponBuffMissing(), false, "a pole needs none")
end)

-- The target's info line for an enemy of this creature type.
local function InfoFor(w, ns, kind)
	w.hasTarget = true
	w.env.UnitCanAttack = function() return true end
	w.env.UnitCreatureType = function() return kind end
	ns.UpdateTargetText()
	return ns.GetBar("targethealth").info:GetText() or ""
end

H.test("the creature type Not specified shows nothing, in the client's language", function()
	local w, ns = World("deDE", DE, function(w0)
		w0.env.C_CreatureInfo = { GetCreatureTypeInfo = function(id)
			if id == 10 then return { name = "Nicht spezifiziert" } end
		end }
	end)
	H.ok(not InfoFor(w, ns, "Nicht spezifiziert"):find("Nicht spezifiziert", 1, true), "hidden")
	H.ok(InfoFor(w, ns, "Wildtier"):find("Wildtier", 1, true), "a real type shows")
	local w2, ns2 = World("enUS", DE)
	H.ok(not InfoFor(w2, ns2, "Not specified"):find("Not specified", 1, true),
		"no C_CreatureInfo: the enUS name")
end)

H.test("a secret creature type name is not kept: the plain one is used when it comes", function()
	local name = "SECRET"
	local w, ns = World("deDE", DE, function(w0)
		w0.env.issecretvalue = function(v) return v == "SECRET" end
		w0.env.C_CreatureInfo = { GetCreatureTypeInfo = function() return { name = name } end }
	end)
	InfoFor(w, ns, "Wildtier")
	name = "Nicht spezifiziert"
	H.ok(not InfoFor(w, ns, "Nicht spezifiziert"):find("Nicht spezifiziert", 1, true), "hidden")
end)

H.test("the enUS Not specified is hidden even when the client names type 10 otherwise", function()
	local w, ns = World("enUS", DE, function(w0)
		w0.env.C_CreatureInfo = { GetCreatureTypeInfo = function() return { name = "Unspecified" } end }
	end)
	H.ok(not InfoFor(w, ns, "Not specified"):find("Not specified", 1, true), "hidden")
	H.ok(not InfoFor(w, ns, "Unspecified"):find("Unspecified", 1, true), "the client's name too")
end)

--------------------------------------------------------------------------------
-- /hud debug ids
--------------------------------------------------------------------------------

-- An English client whose spell names are SPELL_IDS's, but for wrong:
-- [name] = the ID that really has that name.
local function EnglishWorld(wrong)
	local names = {}
	local w, ns = World("enUS", names)
	for name, id in pairs(ns.SPELL_IDS) do names[id] = name end
	for name, real in pairs(wrong) do
		names[ns.SPELL_IDS[name]] = nil
		names[real] = name
	end
	-- A class file name with no ID, found by the scan: the rank you know
	-- has another name, so it is not taken.
	names[2139] = "Counterspell"
	w.env.C_Spell.GetSpellInfo = function(n)
		if n == "Counterspell" then return { spellID = 2140 } end
		if n == "Shadowmeld" then return { spellID = 58984 } end
	end
	names[58984] = "Shadowmeld"
	names[ns.SPELL_IDS["Shadowmeld"]] = nil
	ns.SPELL_SCAN = { to = 30000, step = 10000 }
	return w, ns
end

local function RunAll(w)
	for _ = 1, 20 do
		if #w.timers == 0 then return end
		w:runTimers()
	end
end

H.test("/hud debug ids checks each ID, finds the right one, and saves the result", function()
	local w, ns = EnglishWorld({ ["Stealth"] = 25000 })
	w:slash("/hud debug ids")
	local total = 0
	for _ in pairs(ns.SPELL_IDS) do total = total + 1 end
	H.ok(H.printed(w, ("Spell IDs: %d of %d match their enUS name."):format(total - 2, total)))
	H.ok(H.printed(w, "shared: Stealth: 1784 is no spell"))
	H.ok(H.printed(w, w.ns.TEXT[0]["debug.idsLooking"]:match("^[^%%]*")))
	H.eq(w.env.HUDiniDB.spellIDReport, nil, "saved only at the end")
	RunAll(w)
	local report = w.env.HUDiniDB.spellIDReport
	H.ok(report, "saved")
	H.eq(report.found["Stealth"], 25000)
	H.eq(report.found["Counterspell"], 2139, "a class file name with no ID")
	H.eq(report.found["Shadowmeld"], 58984, "the rank you know, past the scan")
	H.eq(report.match, total - 2)
	H.ok(Has(report.noID, "MAGE: Counterspell"))
	H.ok(H.printed(w, "  Stealth = 25000"))
	H.ok(H.printed(w, "Diagnostic report saved. Reload or log out to write it to SavedVariables."))
end)

H.test("/hud debug ids names a spell no ID has, and runs once at a time", function()
	local w, ns = EnglishWorld({})
	ns.SPELL_SCAN = { to = 30000, step = 10000 }
	w:slash("/hud debug ids")
	w:slash("/hud debug ids")
	H.ok(H.printed(w, "Spell ID check already running."))
	RunAll(w)
	local report = w.env.HUDiniDB.spellIDReport
	H.ok(#report.notFound > 0, "the class file names the stub does not know")
	H.ok(not Has(report.notFound, "Counterspell"))
	H.ok(H.printed(w, "No spell ID has these names:"))
	w.env.HUDiniDB.spellIDReport = nil
	w:slash("/hud debug ids")
	RunAll(w)
	H.ok(w.env.HUDiniDB.spellIDReport, "a second check runs once the first is done")
end)

H.test("/hud debug ids never compares a secret name", function()
	local names = {}
	local w, ns = World("enUS", names, function(w0)
		w0.env.issecretvalue = function(v) return v == "SECRET" end
	end)
	for name, id in pairs(ns.SPELL_IDS) do names[id] = name end
	names[ns.SPELL_IDS["Stealth"]] = "SECRET"
	ns.SPELL_SCAN = { to = 10000, step = 10000 }
	w:slash("/hud debug ids")
	H.ok(H.printed(w, "shared: Stealth: 1784 is no spell"), "a secret counts as no name")
	H.ok(not H.printed(w, "SECRET"), "the secret is never shown")
end)

H.test("/hud debug ids on a German client says to run it on an English one", function()
	local w = World("deDE", DE)
	w:slash("/hud debug ids")
	H.ok(H.printed(w, w.ns.TEXT[0]["debug.idsEnglish"]))
	H.eq(w.env.HUDiniDB.spellIDReport, nil)
end)
