-- TICK-0061: a spell your pet knows counts as known while the pet is out.
-- Spell Lock is the Felhunter's interrupt and Devour Magic its purge, so a
-- Warlock gets those alerts only with the Felhunter out.

local SPELL_LOCK, DEVOUR = 19244, 19505
local SPELL, FUTURE, PET_ACTION = 1, 2, 3

local function Entry(name, id, itemType)
	return { name = name, spellID = id, actionID = id, itemType = itemType or SPELL }
end

local BOOKS = {
	felhunter = { Entry("Spell Lock", SPELL_LOCK), Entry("Devour Magic", DEVOUR) },
	imp       = { Entry("Firebolt", 3110) },
}

-- A Warlock. o.pet: "felhunter", "imp", nil (no pet out) or a list of
-- entries. o.byName: the game finds a spell's ID by name. o.byID: false
-- makes IsSpellKnown(id, true) say no, so only the spellbook walk is left.
-- o.noBook: no C_SpellBook. o.hide: values issecretvalue calls secret.
-- o.noItemEnum: no Enum.SpellBookItemType. Only a right spell ID gets a
-- cooldown answer, so a wrong ID gives no interrupt.
local function Warlock(o)
	o = o or {}
	local w = H.world()
	w.class, w.className = "WARLOCK", "Warlock"
	local env, state = w.env, { pet = o.pet, walks = 0 }
	local function Spells()
		local pet = state.pet
		return type(pet) == "table" and pet or BOOKS[pet] or {}
	end
	local IDS = { ["Spell Lock"] = SPELL_LOCK, ["Devour Magic"] = DEVOUR }
	env.C_Spell.GetSpellName = function(id)
		for n, i in pairs(IDS) do if i == id then return n end end
	end
	env.C_Spell.GetSpellInfo = function(name)
		if o.byName and IDS[name] then return { spellID = IDS[name] } end
	end
	env.C_Spell.GetSpellCooldown = function(id)
		if id == SPELL_LOCK or id == DEVOUR then return { isActive = false } end
	end
	env.IsPlayerSpell = function() return false end
	env.IsSpellKnown = function(id, isPet)
		if o.petKnown ~= nil then return o.petKnown end
		if o.byID == false or isPet ~= true then return false end
		for _, e in ipairs(Spells()) do
			if e.spellID == id and e.itemType == SPELL then return true end
		end
		return false
	end
	local hide = o.hide or {}
	env.issecretvalue = function(v) return state.loaded and v ~= nil and hide[v] == true end
	env.Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
	if not o.noItemEnum then
		env.Enum.SpellBookItemType = { None = 0, Spell = SPELL, FutureSpell = FUTURE, PetAction = PET_ACTION, Flyout = 4 }
	end
	if not o.noBook then
		env.C_SpellBook = {
			HasPetSpells = function()
				if state.pet then state.walks = state.walks + 1; return #Spells() end
			end,
			GetSpellBookItemInfo = function(i, bank)
				if bank == 1 then return Spells()[i] end
			end,
		}
	end
	local ns = w:loadAddon()
	state.loaded = true
	return ns, w, state
end

-- The /hud debug api lines, as one string.
local function Report(ns)
	local lines = {}
	ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
	return table.concat(lines, "\n")
end

local YES, NO = "|cff33ff33yes|r", "|cffff3333no|r"

H.test("the Felhunter out: Spell Lock by IsSpellKnown(id, true) alone", function()
	local ns = Warlock({ pet = "felhunter", byName = true, noBook = true })
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "no pet spellbook API")
end)

H.test("the Felhunter out: Spell Lock from the pet spellbook alone", function()
	local ns = Warlock({ pet = "felhunter", byName = false })
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "the game cannot find it by name")
end)

local function PetAction(actionID)
	return { name = "Spell Lock", actionID = actionID, itemType = PET_ACTION }
end

H.test("a pet action with no spellID is read from its actionID", function()
	local ns = Warlock({ pet = { PetAction(0x5000000 + SPELL_LOCK) } })
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "petActionID low 24 bits")
	ns = Warlock({ pet = { PetAction(0x5000000 + SPELL_LOCK) }, noItemEnum = true })
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "no Enum.SpellBookItemType")
end)

-- A hidden value is not known now, and is asked again once it is plain,
-- with no pet event in between.
local function HiddenThenPlain(pet, value, what)
	local hide = { [value] = true }
	local ns = Warlock({ pet = pet, hide = hide })
	H.eq(ns.ReadyInterrupt(), nil, what .. " hidden")
	hide[value] = nil
	H.eq(ns.ReadyInterrupt(), "Spell Lock", what .. " plain again")
end

H.test("a secret actionID is not known, and is asked again", function()
	HiddenThenPlain({ PetAction(0x5000000 + SPELL_LOCK) }, 0x5000000 + SPELL_LOCK, "actionID")
end)

H.test("a secret spellID or itemType is not known, and is asked again", function()
	HiddenThenPlain("felhunter", SPELL_LOCK, "spellID")
	HiddenThenPlain("felhunter", SPELL, "itemType")
end)

H.test("only a pet action is read from its actionID", function()
	local entry = { name = "Spell Lock", actionID = SPELL_LOCK, itemType = SPELL }
	H.eq(Warlock({ pet = { entry } }).ReadyInterrupt(), nil, "a spell with no spellID")
end)

H.test("a pet spell not learned yet is not known", function()
	local future = { Entry("Spell Lock", SPELL_LOCK, FUTURE) }
	H.eq(Warlock({ pet = future }).ReadyInterrupt(), nil, "FutureSpell")
	H.eq(Warlock({ pet = future, noItemEnum = true }).ReadyInterrupt(), nil,
		"no Enum.SpellBookItemType")
	H.eq(Warlock({ pet = future, hide = { [FUTURE] = true } }).ReadyInterrupt(), nil,
		"secret itemType")
end)

H.test("no pet out: no interrupt", function()
	H.eq(Warlock({ byName = true }).ReadyInterrupt(), nil, "by ID")
	H.eq(Warlock({}).ReadyInterrupt(), nil, "by name")
end)

H.test("another pet out: no interrupt", function()
	H.eq(Warlock({ pet = "imp", byName = true }).ReadyInterrupt(), nil, "by ID")
	H.eq(Warlock({ pet = "imp" }).ReadyInterrupt(), nil, "by name")
end)

H.test("the Felhunter out, a secret IsSpellKnown answer is not known", function()
	local ns = Warlock({ pet = "felhunter", byName = true, noBook = true,
		petKnown = true, hide = { [true] = true } })
	H.eq(ns.ReadyInterrupt(), nil, "secret true")
end)

H.test("a secret count, name or spellID from the pet spellbook is not known", function()
	H.eq(Warlock({ pet = "felhunter", hide = { [2] = true } }).ReadyInterrupt(), nil, "count")
	H.eq(Warlock({ pet = "felhunter", hide = { ["Spell Lock"] = true } }).ReadyInterrupt(), nil, "name")
	H.eq(Warlock({ pet = "felhunter", hide = { [SPELL_LOCK] = true } }).ReadyInterrupt(), nil, "spellID")
end)

H.test("a throwing pet spellbook does not break the alert", function()
	local ns, w = Warlock({ pet = "felhunter" })
	w.env.C_SpellBook.GetSpellBookItemInfo = function() error("no") end
	w.env.C_SpellBook.HasPetSpells = function() error("no") end
	H.eq(ns.ReadyInterrupt(), nil, "the errors are caught")
end)

H.test("your own spells still count", function()
	local ns, w = Warlock({ byName = true })
	w.env.IsPlayerSpell = function(id) return id == SPELL_LOCK end
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "IsPlayerSpell")
end)

H.test("the Felhunter out: Devour Magic is the purge", function()
	H.ok(Report(Warlock({ pet = "felhunter" })):find("Purge spell known%s+" .. YES:gsub("|", "%%|")),
		"Purge spell known: yes")
	H.ok(Report(Warlock({ pet = "imp" })):find("Purge spell known%s+" .. NO:gsub("|", "%%|")),
		"Purge spell known: no")
end)

H.test("the pet spellbook is walked once until the pet changes", function()
	local ns, w, state = Warlock({ pet = "felhunter" })
	ns.ReadyInterrupt()
	local walks = state.walks
	ns.ReadyInterrupt()
	ns.ReadyInterrupt()
	H.eq(state.walks, walks, "cached")

	state.pet = "imp"
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "no event yet: still the old answer")
	w:fire("PET_BAR_UPDATE")
	H.eq(ns.ReadyInterrupt(), nil, "PET_BAR_UPDATE: the Imp")
	state.pet = "felhunter"
	H.eq(ns.ReadyInterrupt(), nil, "no event yet: the Imp's answer is kept")
	w:fire("SPELLS_CHANGED")
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "SPELLS_CHANGED: the Felhunter")
	state.pet = "imp"
	w:fire("UNIT_PET", "player")
	H.eq(ns.ReadyInterrupt(), nil, "UNIT_PET: the Imp")
end)

H.test("a pet spellbook that could not be read is asked again", function()
	local ns, w = Warlock({ pet = "felhunter" })
	local book = w.env.C_SpellBook
	local HasPetSpells, GetItem = book.HasPetSpells, book.GetSpellBookItemInfo
	book.HasPetSpells = function() error("not loaded") end
	H.eq(ns.ReadyInterrupt(), nil, "HasPetSpells throws")
	book.HasPetSpells = HasPetSpells
	book.GetSpellBookItemInfo = function() error("not loaded") end
	H.eq(ns.ReadyInterrupt(), nil, "GetSpellBookItemInfo throws")
	book.GetSpellBookItemInfo = GetItem
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "no event needed")
end)

H.test("no pet out is asked again, with no event", function()
	local ns, _, state = Warlock({})
	H.eq(ns.ReadyInterrupt(), nil, "no pet")
	state.pet = "felhunter"
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "summoned")
end)

H.test("a secret name is asked again", function()
	local hide = { ["Spell Lock"] = true }
	local ns = Warlock({ pet = "felhunter", hide = hide })
	H.eq(ns.ReadyInterrupt(), nil, "secret name")
	hide["Spell Lock"] = nil
	H.eq(ns.ReadyInterrupt(), "Spell Lock", "plain again")
end)

H.test("/hud debug api says known, off cooldown and usable for each spell", function()
	local ns, w = Warlock({ pet = "felhunter" })
	w.env.C_Spell.IsSpellUsable = function() return false, false end
	local text = Report(ns)
	H.ok(text:find("Spell Lock: known " .. YES:gsub("|", "%%|")
		.. ", off cooldown " .. YES:gsub("|", "%%|")
		.. ", usable now " .. NO:gsub("|", "%%|"), 1, false), text)
	H.eq(ns.ReadyInterrupt(), nil, "not usable: no interrupt")

	text = Report(Warlock({ pet = "imp" }))
	H.ok(text:find("Spell Lock: known " .. NO:gsub("|", "%%|")
		.. ", off cooldown not asked, usable now not asked", 1, false), text)
end)
