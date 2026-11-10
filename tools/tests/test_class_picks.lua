-- The "Your class" page's saved data (TICK-0069): one pick per row
-- (ns.GetClassPick, ns.SetClassPick), dispel one type at a time, purge that
-- keeps "stealable only" for the class file's spell, the combat buff and the
-- resource as saved choices, the action-bar spell list, and the names after
-- "Class default:".

local D, P = nil, nil -- ns.PICK_DEFAULT and ns.PICK_NONE, once loaded

-- A world for one class. spells: [id] = name, every one known. o.bars:
-- [slot] = { "spell", id } (or "item", "macro"). o.debuff: the player's one
-- harmful aura type. o.targetBuff: the target's one buff. o.secret: the
-- game's issecretvalue (Util.lua reads it at load).
local function World(class, className, spells, o)
	o = o or {}
	local w = H.world()
	w.class, w.className = class, className
	local env = w.env
	env.issecretvalue = o.secret
	env.C_Spell.GetSpellName = function(id) return spells[id] end
	env.C_Spell.GetSpellInfo = function(name)
		if type(name) ~= "string" then return nil end
		for id, n in pairs(spells) do
			if n:lower() == name:lower() then return { spellID = id } end
		end
	end
	env.IsPlayerSpell = function(id) return spells[id] ~= nil end
	env.GetActionInfo = function(slot)
		local a = o.bars and o.bars[slot]
		if a then return a[1], a[2] end
	end
	env.GetMacroSpell = function(id) return o.macros and o.macros[id] end
	env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		if i ~= 1 then return nil end
		if unit == "player" and filter == "HARMFUL|RAID" and o.debuff then
			return { dispelName = o.debuff[1] }
		end
		if unit == "target" and filter == "HELPFUL" and o.targetBuff then
			return o.targetBuff[1]
		end
	end
	local ns = w:loadAddon()
	D, P = ns.PICK_DEFAULT, ns.PICK_NONE
	return ns, w, env.HUDiniDB
end

-- A Paladin: Cleanse for Magic, Purify for Poison and Disease, no Curse.
-- Remove Curse is a druid's spell, known here only to pick it.
local function Paladin(o)
	return World("PALADIN", "Paladin",
		{ [1] = "Cleanse", [2] = "Purify", [3] = "Remove Curse", [4] = "Hammer of Justice" }, o)
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

--------------------------------------------------------------------------------
-- Dispel, one type at a time
--------------------------------------------------------------------------------

H.test("a dispel type you set replaces that type only", function()
	local ns = Paladin()
	H.eq(ns.SetClassPick("dispel", "Remove Curse", "Curse"), true, "saved")
	local d = ns.ClassValue("dispel")
	H.eq(d.Curse, "Remove Curse", "your Curse")
	H.eq(d.Poison, "Purify", "class file's Poison kept")
	H.eq(d.Disease, "Purify", "class file's Disease kept")
	H.eq(d.Magic, "Cleanse", "class file's Magic kept")
	H.eq(ns.GetClassPick("dispel", "Curse"), "Remove Curse")
	H.eq(ns.GetClassPick("dispel", "Poison"), D, "Poison is still Class default")
end)

H.test("None removes one dispel type only, and Class default clears it", function()
	local ns = Paladin()
	H.eq(ns.SetClassPick("dispel", P, "Poison"), true, "None saved")
	H.eq(ns.ClassDB().dispel.Poison, false, "saved as false")
	local d = ns.ClassValue("dispel")
	H.eq(d.Poison, nil, "Poison gone")
	H.eq(d.Disease, "Purify", "Disease kept")
	H.eq(d.Magic, "Cleanse", "Magic kept")
	H.eq(Count(d), 2, "two types left")
	H.eq(ns.GetClassPick("dispel", "Poison"), P)

	H.eq(ns.SetClassPick("dispel", D, "Poison"), true, "Class default saved")
	H.eq(ns.ClassDB().dispel, nil, "an empty choice table goes")
	H.eq(ns.ClassValue("dispel").Poison, "Purify", "the class file's Poison is back")
	H.eq(ns.GetClassPick("dispel", "Poison"), D)
end)

H.test("a saved dispel name and a saved ID both work, and keep the class file's other types", function()
	local ns = Paladin()
	ns.ClassDB().dispel = { Curse = "Remove Curse", Magic = 1 }
	local d = ns.ClassValue("dispel")
	H.eq(d.Curse, "Remove Curse", "the saved name")
	H.eq(d.Magic, 1, "the saved ID")
	H.eq(d.Poison, "Purify", "the class file's Poison")
	H.eq(ns.GetClassPick("dispel", "Magic"), "1", "an ID shows as it is saved")
	H.eq(ns.SetClassPick("dispel", "1", "Magic"), false, "the same pick changes nothing")
	H.eq(ns.ClassDB().dispel.Magic, 1, "the ID stays a number")
end)

H.test("a Paladin with Curse set to None still gets the tint for Poison and Disease, not Curse", function()
	local o = {}
	local ns = Paladin(o)
	ns.SetClassPick("dispel", P, "Curse")
	for _, case in ipairs({ { "Poison", true }, { "Disease", true }, { "Magic", true }, { "Curse", false } }) do
		o.debuff = { case[1] }
		ns.HUDini:Apply()
		H.eq(ns.powerTint ~= nil, case[2], case[1] .. " tint")
	end
end)

H.test("one Apply after a pick refreshes the dispel tint", function()
	local o = { debuff = { "Curse" } }
	local ns = Paladin(o)
	ns.HUDini:Apply()
	H.eq(ns.powerTint, nil, "no Curse spell in the class file: no tint")
	ns.SetClassPick("dispel", "Remove Curse", "Curse")
	ns.HUDini:Apply()
	H.ok(ns.powerTint ~= nil, "your Curse spell: the tint shows")
	o.debuff = { "Poison" }
	ns.HUDini:Apply()
	H.ok(ns.powerTint ~= nil, "and Poison still tints")
end)

-- "Magic", the type a Paladin's Cleanse removes, is the value that would
-- tint. Secret, it gives no tint: only Plain keeps it off.
H.test("a secret debuff type that you can dispel gives no tint", function()
	local hide = false
	local o = { debuff = { "Magic" }, secret = function(v) return hide and v == "Magic" end }
	local ns = Paladin(o)
	ns.HUDini:Apply()
	H.ok(ns.powerTint ~= nil, "plain Magic: the tint shows")
	hide = true
	ns.HUDini:Apply()
	H.eq(ns.powerTint, nil, "secret Magic: no tint")
end)

-- /hud dispel is gone (TICK-0019); what it saved still works.
H.test("a dispel saved by /hud dispel: one type set, the rest kept", function()
	local o = {}
	local ns = Paladin(o)
	o.debuff = { "Curse" }
	ns.ClassDB().dispel = { Curse = "Remove Curse" }
	ns.HUDini:Apply()
	H.eq(ns.ClassValue("dispel").Poison, "Purify", "Poison kept")
	H.eq(ns.GetClassPick("dispel", "Curse"), "Remove Curse", "the page shows it")
	H.ok(ns.powerTint ~= nil, "the Curse tint shows")
	ns.ClassDB().dispel.Poison = false
	H.eq(ns.GetClassPick("dispel", "Poison"), P, "the page shows None")
	H.eq(ns.ClassValue("dispel").Poison, nil, "Poison removed")
end)

--------------------------------------------------------------------------------
-- Purge
--------------------------------------------------------------------------------

-- A Mage: the class file's purge is { spell = "Spellsteal", stealable = true }.
local function Mage(o)
	return World("MAGE", "Mage",
		{ [10] = "Spellsteal", [11] = "Purge", [12] = "Frost Armor", [13] = "Mana Shield",
		  [14] = "Counterspell" }, o)
end

local function PurgeIconsShown(w)
	local bar, n = w.ns.GetBar("targethealth"), 0
	for _, f in ipairs(w.frames) do
		if f.edge and f.tex and f:IsShown() then
			local point, to, rel = f:GetPoint(1)
			if point == "RIGHT" and to == bar and rel == "RIGHT" then n = n + 1 end
		end
	end
	return n
end

H.test("the class file's purge, picked by name, keeps stealable only", function()
	local ns = Mage()
	for _, name in ipairs({ "Spellsteal", "spellsteal" }) do
		ns.SetClassPick("purge", name)
		local purge = ns.ClassValue("purge")
		H.eq(type(purge), "table", name .. ": the class file's rule")
		H.eq(purge.stealable, true, name .. ": stealable only")
	end
	ns.SetClassPick("purge", "Purge")
	H.eq(ns.ClassValue("purge"), "Purge", "another spell: any magic buff")
	ns.SetClassPick("purge", "10")
	H.eq(ns.ClassDB().purge, 10, "saved as an ID")
	H.eq(type(ns.ClassValue("purge")), "table", "Spellsteal by its ID: the class file's rule")
	ns.SetClassPick("purge", "11")
	H.eq(ns.ClassValue("purge"), 11, "Purge by its ID: any magic buff")
end)

H.test("a saved purge ID whose name is secret: the plain rule, no error", function()
	local ns = World("MAGE", "Mage", { [10] = "Spellsteal", [15] = "SECRETNAME" },
		{ secret = function(v) return v == "SECRETNAME" end })
	ns.SetClassPick("purge", "15")
	-- In the game a secret string throws when the addon works on it; here
	-- string.lower does, while this test runs.
	local lower = string.lower
	string.lower = function(s)
		if s == "SECRETNAME" then error("a secret name was worked on") end
		return lower(s)
	end
	local ok, purge = pcall(ns.ClassValue, "purge")
	string.lower = lower
	H.ok(ok, "no error: " .. tostring(purge))
	H.eq(purge, 15, "the plain purge rule")
end)

H.test("a magic buff that cannot be stolen shows for another purge, not for Spellsteal", function()
	local o = { targetBuff = { { dispelName = "Magic", isStealable = false, icon = 5 } } }
	local ns, w = Mage(o)
	w.env.UnitCanAttack = function() return true end
	w.hasTarget = true
	ns.SetClassPick("purge", "Spellsteal")
	ns.HUDini:Apply()
	H.eq(PurgeIconsShown(w), 0, "Spellsteal: stealable only")
	ns.SetClassPick("purge", "Purge")
	ns.HUDini:Apply()
	H.eq(PurgeIconsShown(w), 1, "Purge: any magic buff")
	ns.SetClassPick("purge", P)
	ns.HUDini:Apply()
	H.eq(ns.ClassValue("purge"), false, "None saved as false")
	H.eq(PurgeIconsShown(w), 0, "None: no purge icon")
	ns.SetClassPick("purge", D)
	H.eq(ns.ClassDB().purge, nil, "Class default clears it")
	H.eq(ns.ClassValue("purge").spell, "Spellsteal", "the class file's purge")
end)

-- The values that would show a purge icon: a target you can attack (true)
-- and a "Magic" buff. Either one secret shows no icon: only Plain keeps it.
H.test("a secret attack answer or buff type shows no purge icon", function()
	local hidden = {}
	local o = {
		targetBuff = { { dispelName = "Magic", isStealable = false, icon = 5 } },
		secret = function(v) return v ~= nil and hidden[v] == true end,
	}
	local ns, w = Mage(o)
	w.env.UnitCanAttack = function() return true end
	w.hasTarget = true
	ns.SetClassPick("purge", "Purge")
	ns.HUDini:Apply()
	H.eq(PurgeIconsShown(w), 1, "plain: a magic buff on a foe")
	hidden[true] = true
	ns.HUDini:Apply()
	H.eq(PurgeIconsShown(w), 0, "a secret attack answer")
	hidden[true], hidden.Magic = nil, true
	ns.HUDini:Apply()
	H.eq(PurgeIconsShown(w), 0, "a secret buff type")
end)

--------------------------------------------------------------------------------
-- Combat buff
--------------------------------------------------------------------------------

H.test("a combat buff pick saves a list of one; None an empty list", function()
	local ns = Mage()
	H.eq(ns.GetClassPick("keepUp"), D)
	ns.SetClassPick("keepUp", "Frost Armor")
	local list = ns.ClassValue("keepUp")
	H.eq(#list, 1, "one spell"); H.eq(list[1], "Frost Armor")
	H.eq(ns.GetClassPick("keepUp"), "Frost Armor")
	ns.SetClassPick("keepUp", P)
	H.eq(#ns.ClassValue("keepUp"), 0, "None: an empty list")
	H.eq(ns.GetClassPick("keepUp"), P)
	ns.SetClassPick("keepUp", D)
	H.eq(ns.ClassDB().keepUp, nil, "Class default clears it")
	H.eq(ns.ClassValue("keepUp")[1], "Ice Barrier", "the class file's list")
end)

H.test("the combat buff's class default is the first one you know", function()
	local ns = Mage()
	-- Ice Barrier is a talent this Mage lacks; Mana Shield is known.
	H.eq(ns.ClassDefaultName("keepUp"), "Mana Shield")
	ns = World("MAGE", "Mage", { [10] = "Spellsteal" })
	local name, none = ns.ClassDefaultName("keepUp")
	H.eq(name, nil, "none known yet")
	H.eq(none, true, "the page says 'none known yet'")
end)

H.test("the combat buff alert follows the pick, and None turns it off", function()
	local ns, w = Mage()
	w.combat = true
	ns.SetClassPick("keepUp", "Frost Armor")
	ns.HUDini:Apply()
	local icon
	for _, f in ipairs(w.frames) do
		if f.edge and f.tex and f:IsShown() then icon = f end
	end
	H.ok(icon ~= nil, "Frost Armor is off: its icon shows")
	ns.SetClassPick("keepUp", P)
	ns.HUDini:Apply()
	H.eq(icon:IsShown(), false, "None: no icon")
	w.combat = false
end)

--------------------------------------------------------------------------------
-- Resource
--------------------------------------------------------------------------------

local function Rogue()
	local ns, w, db = World("ROGUE", "Rogue", { [20] = "Slice and Dice", [21] = "Kick" })
	w.env.Enum.PowerType.ComboPoints = 4
	ns.HUDini:Apply()
	return ns, w, db
end

H.test("the resource: a spell pick, its stacks, None and Class default", function()
	local ns = Rogue()
	local bar = ns.GetBar("resource")
	H.eq(bar:IsShown(), true, "Class default: combo points")
	H.eq(ns.ResourceStacks(), nil, "Stacks to fill is gray for Class default")

	ns.SetClassPick("resource", "Slice and Dice")
	local r = ns.ClassValue("resource")
	H.eq(r.aura, "Slice and Dice", "counts the buff"); H.eq(r.max, 5, "5 stacks to start")
	H.eq(ns.ResourceStacks(), 5)
	H.eq(ns.SetResourceStacks(25), true); H.eq(ns.ResourceStacks(), 20, "20 at most")
	H.eq(ns.SetResourceStacks(0), true); H.eq(ns.ResourceStacks(), 1, "1 at least")
	ns.SetResourceStacks(3)
	H.eq(ns.SetResourceStacks(3), false, "the same number changes nothing")
	ns.SetClassPick("resource", "Kick")
	H.eq(ns.ClassValue("resource").max, 3, "another spell keeps the stacks")

	ns.SetClassPick("resource", P)
	H.eq(ns.ClassValue("resource"), false, "None saved as false")
	H.eq(ns.ResourceStacks(), nil, "Stacks to fill is gray for None")
	H.eq(ns.SetResourceStacks(4), false, "and cannot be set")
	ns.HUDini:Apply()
	H.eq(bar:IsShown(), false, "None: no resource bar")

	ns.SetClassPick("resource", D)
	H.eq(ns.ClassDB().resource, nil, "Class default clears it")
	ns.HUDini:Apply()
	H.eq(bar:IsShown(), true, "combo points again")
end)

-- /hud resource is gone (TICK-0019); what it saved still works.
H.test("a resource saved by /hud resource shows on the page", function()
	local ns = Rogue()
	ns.ClassDB().resource = { aura = "Slice and Dice", max = 4 }
	H.eq(ns.GetClassPick("resource"), "Slice and Dice")
	H.eq(ns.ResourceStacks(), 4)
end)

H.test("the resource's class default names the power from the game", function()
	local ns, w = Rogue()
	H.eq(ns.ClassDefaultName("resource"), "Combo Points", "no global string: the key with spaces")
	w.env.COMBO_POINTS = "Points de combo"
	H.eq(ns.ClassDefaultName("resource"), "Points de combo", "the game's own name")
	w.env.HOLY_POWER_POWER = "Holy Power!"
	H.eq(ns.PowerName("HolyPower"), "Holy Power!", "the _POWER form")
	H.eq(ns.PowerName(nil), nil)
	local mage = Mage()
	H.eq(mage.ClassDefaultName("resource"), nil, "a Mage has none")
end)

--------------------------------------------------------------------------------
-- Interrupt, one spell or a list (TICK-0060)
--------------------------------------------------------------------------------

local function Warrior()
	local ns, w = World("WARRIOR", "Warrior", { [30] = "Pummel", [31] = "Shield Bash" })
	w.env.C_Spell.GetSpellCooldown = function() return { isActive = false } end
	w.env.C_Spell.IsSpellUsable = function() return true, false end
	return ns, w
end

H.test("the interrupt list still works next to a pick", function()
	local ns = Warrior()
	H.eq(ns.GetClassPick("interrupt"), D)
	H.eq(ns.ClassDefaultName("interrupt"), "Pummel, Shield Bash", "the class file's list")
	H.eq(ns.ReadyInterrupt(), "Pummel", "the list, first spell")
	ns.SetClassPick("interrupt", "Shield Bash")
	H.eq(ns.ReadyInterrupt(), "Shield Bash", "your pick")
	ns.SetClassPick("interrupt", D)
	H.eq(ns.ClassDB().interrupt, nil, "Class default clears it")
	H.eq(ns.ReadyInterrupt(), "Pummel", "the list again")
end)

-- A list saved by /hud interrupt, which TICK-0019 took out.
H.test("a saved interrupt list shows as typed, and the same pick keeps it", function()
	local ns = Warrior()
	ns.ClassDB().interrupt = { "Shield Bash", "Pummel" }
	H.eq(ns.GetClassPick("interrupt"), "Shield Bash, Pummel")
	H.eq(ns.SetClassPick("interrupt", "Shield Bash, Pummel"), false, "no change")
	H.eq(type(ns.ClassDB().interrupt), "table", "still a list")
	H.eq(ns.ReadyInterrupt(), "Shield Bash", "your list, first spell")
end)

H.test("interrupt None: no outline spell, and chat says none", function()
	local ns = Warrior()
	ns.SetClassPick("interrupt", P)
	H.eq(ns.ClassDB().interrupt, false, "saved as false")
	H.eq(ns.ReadyInterrupt(), nil, "no spell to wait for")
	H.eq(ns.SpellLabel(ns.ClassValue("interrupt")), "none")
	local lines = {}
	ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
	for _, line in ipairs(lines) do H.ok(not line:find("false", 1, true), "report: " .. line) end
end)

--------------------------------------------------------------------------------
-- The action-bar spell list
--------------------------------------------------------------------------------

H.test("the action-bar list: every bar, spells only, A to Z, each once, no secret name", function()
	local spells = { [1] = "Frostbolt", [2] = "Blink", [3] = "Arcane Intellect",
		[4] = "SECRET", [5] = "Counterspell" }
	-- The slots are filled after login, so the icon grid never draws them:
	-- only the list reads them here.
	local fight = false
	local o = { secret = function(v)
		return v == "SECRET" or v == "SECRETID" or (fight and v == "Blink")
	end }
	local ns, w = World("MAGE", "Mage", spells, o)
	-- The game's GetSpellName must never get a secret ID.
	local getName = w.env.C_Spell.GetSpellName
	w.env.C_Spell.GetSpellName = function(id)
		assert(id ~= "SECRETID", "a secret ID reached GetSpellName")
		return getName(id)
	end
	o.bars, o.macros = {
			[1] = { "spell", 1 },          -- Bar 1
			[5] = { "macro", 7 },          -- a macro that casts Frostbolt again
			[9] = { "macro", 8 },          -- a macro whose spell ID is secret
			[13] = { "spell", 5 },         -- Bar 1's second page: not a bar the page reads
			[30] = { "item", 6948 },       -- an item, Bar 4
			[40] = { "spell", 4 },         -- a secret name, Bar 5
			[45] = { "spell", "SECRETID" },-- a secret slot
			[61] = { "spell", 2 },         -- Bar 2
			[180] = { "spell", 3 },        -- Bar 8, last slot
		}, { [7] = 1, [8] = "SECRETID" }
	-- A slot the game refuses to read.
	w.env.GetActionInfo = (function(real)
		return function(slot)
			if slot == 50 then error("refused") end
			return real(slot)
		end
	end)(w.env.GetActionInfo)
	local list = ns.ActionBarSpells()
	H.eq(table.concat(list, "|"), "Arcane Intellect|Blink|Frostbolt")
	-- In a fight Blink's name turns secret: it goes, and the rest come back.
	w.combat, fight = true, true
	H.eq(table.concat(ns.ActionBarSpells(), "|"), "Arcane Intellect|Frostbolt",
		"in a fight, a secret name goes and the list still comes back")
	w.combat, fight = false, false
end)

--------------------------------------------------------------------------------
-- A class with no class file, and input that is not a row
--------------------------------------------------------------------------------

H.test("a class with no class file: every row is Class default: none, and a pick works", function()
	local ns = World("MONK", "Monk", { [40] = "Spear Hand Strike" })
	for _, key in ipairs({ "interrupt", "purge", "keepUp", "resource" }) do
		H.eq(ns.GetClassPick(key), D, key)
		H.eq((ns.ClassDefaultName(key)), nil, key .. ": none")
	end
	for _, t in ipairs(ns.DISPEL_TYPES) do
		H.eq(ns.ClassDefaultName("dispel", t), nil, t .. ": none")
	end
	H.eq(ns.ClassValue("dispel"), nil, "no dispels")
	ns.SetClassPick("interrupt", "Spear Hand Strike")
	H.eq(ns.ClassValue("interrupt"), "Spear Hand Strike")
	ns.SetClassPick("dispel", P, "Magic")
	H.eq(Count(ns.ClassValue("dispel")), 0, "None on a class with none: an empty list")
end)

H.test("a pick for a row that does not exist changes nothing", function()
	local ns, w, db = Paladin()
	H.eq(ns.SetClassPick("weaponBuff", "Purify"), false, "not a row")
	H.eq(ns.SetClassPick("dispel", "Purify", "Bleed"), false, "not a type")
	H.eq(ns.SetClassPick("dispel", "Purify"), false, "no type")
	H.eq(ns.SetClassPick("purge", nil), false, "nil")
	H.eq(ns.SetClassPick("purge", ""), false, "empty")
	H.eq(ns.SetClassPick("purge", 4), false, "a number, not a string")
	H.eq(ns.GetClassPick("weaponBuff"), nil)
	H.eq(ns.GetClassPick("dispel", "Bleed"), nil)
	H.eq(ns.ClassDefaultName("dispel", "Bleed"), nil)
	local mine = db.classes.PALADIN
	for _, key in ipairs({ "weaponBuff", "dispel", "purge" }) do H.eq(mine[key], nil, key) end
	local _ = w
end)

H.test("each class keeps its own picks", function()
	local ns, w, db = Paladin()
	ns.SetClassPick("interrupt", "Purify")
	w.class, w.className = "MAGE", "Mage"
	H.eq(ns.GetClassPick("interrupt"), D, "the Mage's own")
	ns.SetClassPick("interrupt", P)
	H.eq(db.classes.PALADIN.interrupt, "Purify", "the Paladin's kept")
	H.eq(db.classes.MAGE.interrupt, false)
end)
