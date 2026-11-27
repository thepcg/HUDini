-- The class resource: a preferred entry, and a debuff entry (TICK-0238).
-- An entry with prefer = true wins while it is on you or yours to get,
-- before the first buff on you: an Enhancement Shaman in Lightning Shield
-- counts Maelstrom Weapon. Yours to get: you know its spell, else its
-- talent has a rank, else (no talent answer) it was on you since login.
-- Never before its spell ID is known: the slot counts in a fight by ID.
-- An entry with filter = "HARMFUL" counts the stacks of a debuff on you.
-- What the player sees needs DK's play.

-- Maelstrom Weapon has no spell ID by name here, as on Forever.
local IDS = { ["Water Shield"] = 52127, ["Lightning Shield"] = 324, ["Arcane Blast"] = 30451 }
-- The spell ID a read on you answers.
local AURA_IDS = { ["Lightning Shield"] = 324, ["Maelstrom Weapon"] = 53817, ["Arcane Blast"] = 36032 }
local LIST = {
	{ aura = "Lightning Shield", max = 3 },
	{ aura = "Maelstrom Weapon", max = 5, prefer = true },
}

-- A Shaman with this resource. w.known[name]: you know the spell;
-- w.auras[name]: the buff on you; w.debuffs[name]: the debuff on you;
-- talents: { name, rank } rows of Classic's talent API in its second tab
-- (Enhancement), or nil for no talent API. The first tab has one talent
-- of another name. w.noTalentData: the API answers no tab yet. hide: your
-- auras are hidden from login on.
local function World(resource, known, talents, hide)
	local w = H.world()
	w.hide = hide
	local env = w.env
	w.class, w.className = "SHAMAN", "Shaman"
	w.known, w.auras, w.debuffs = known or {}, {}, {}
	w.asked = {}
	env.C_Spell.GetSpellInfo = function(name)
		if IDS[name] then return { spellID = IDS[name] } end
	end
	env.IsPlayerSpell = function(id)
		for name, n in pairs(IDS) do
			if n == id then return w.known[name] == true end
		end
		return false
	end
	if talents then
		local tabs = { { { "Convection", 5 } }, talents }
		env.GetNumTalentTabs = function() return w.noTalentData and 0 or #tabs end
		env.GetNumTalents = function(tab) return #tabs[tab] end
		env.GetTalentInfo = function(tab, i)
			local t = tabs[tab][i]
			return t[1], 0, 1, i, t[2], 5
		end
	end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.hide == true end }
	-- Set before the load: the harness's own answer would find every buff.
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name, filter)
		w.asked[#w.asked + 1] = name .. "/" .. tostring(filter)
		if w.hide then return nil end
		if filter == "HARMFUL" then return w.debuffs[name] end
		return w.auras[name]
	end
	local ns = w:loadAddon()
	ns.RegisterClass("SHAMAN", { resource = resource })
	ns.HUDini.body:Show()
	ns.UpdateResource()
	return w, ns
end

local function Bar(ns) return ns.GetBar("resource") end
local function Pick(ns) return (ns.ClassResource() or {}).aura end
local function On(w, name, n, kind)
	local t = kind == "HARMFUL" and w.debuffs or w.auras
	t[name] = n and { applications = n, spellId = AURA_IDS[name] } or nil
	w:fire("UNIT_AURA", "player")
	w.ns.UpdateResource()
end

H.test("a preferred entry you know wins over an earlier one on you", function()
	IDS["Maelstrom Weapon"] = 51530
	local w, ns = World(LIST, { ["Lightning Shield"] = true, ["Maelstrom Weapon"] = true })
	On(w, "Lightning Shield", 3)
	H.eq(Pick(ns), "Maelstrom Weapon", "known: preferred, though Lightning Shield is on you")
	H.eq(select(2, Bar(ns):GetMinMaxValues()), 5, "its pips")
	H.eq(Bar(ns):GetValue(), 0, "no stack yet")
	On(w, "Maelstrom Weapon", 4)
	H.eq(Bar(ns):GetValue(), 4, "its stacks")
	IDS["Maelstrom Weapon"] = nil
end)

H.test("a preferred entry you do not know: the one on you, as before", function()
	local w, ns = World(LIST, { ["Lightning Shield"] = true }, {})
	On(w, "Lightning Shield", 2)
	H.eq(Pick(ns), "Lightning Shield")
	H.eq(Bar(ns):GetValue(), 2)
end)

H.test("a preferred entry with no spell ID: its talent rank decides", function()
	local talents = { { "Shamanistic Focus", 1 }, { "Maelstrom Weapon", 0 } }
	local w, ns = World(LIST, { ["Lightning Shield"] = true }, talents)
	On(w, "Lightning Shield", 3)
	H.eq(Pick(ns), "Lightning Shield", "rank 0: not yours")
	talents[2][2] = 3
	ns.UpdateResource()
	H.eq(Pick(ns), "Lightning Shield", "asked once, until a talent point changes")
	w:fire("CHARACTER_POINTS_CHANGED")
	H.eq(Pick(ns), "Lightning Shield", "a talent point spent, its spell ID not known yet")
	On(w, "Maelstrom Weapon", 1)
	On(w, "Maelstrom Weapon", nil)
	H.eq(Pick(ns), "Maelstrom Weapon", "read once: its ID known, and yours")
	talents[2][2] = 0
	w:fire("SPELLS_CHANGED")
	H.eq(Pick(ns), "Lightning Shield", "taken back")
end)

H.test("a preferred entry with an ID Auras.lua keeps: its talent rank decides at once", function()
	local w, ns = World(LIST, { ["Lightning Shield"] = true }, { { "Maelstrom Weapon", 3 } })
	On(w, "Lightning Shield", 3)
	H.eq(Pick(ns), "Lightning Shield", "no ID")
	ns.ClassDB().auraSpellIDs = { ["Maelstrom Weapon"] = { [53817] = true } }
	ns.UpdateResource()
	H.eq(Pick(ns), "Maelstrom Weapon", "the kept ID")
end)

H.test("talent data not loaded yet: asked again, with no event", function()
	local w, ns = World(LIST, { ["Lightning Shield"] = true }, { { "Maelstrom Weapon", 3 } })
	ns.ClassDB().auraSpellIDs = { ["Maelstrom Weapon"] = { [53817] = true } }
	w.noTalentData = true
	On(w, "Lightning Shield", 3)
	H.eq(Pick(ns), "Lightning Shield", "no tab yet")
	w.noTalentData = false
	ns.UpdateResource()
	H.eq(Pick(ns), "Maelstrom Weapon", "the talent loaded")
end)

H.test("no talent answer: a respec forgets the buffs seen before", function()
	local w, ns = World(LIST, { ["Lightning Shield"] = true })
	On(w, "Maelstrom Weapon", 2)
	On(w, "Maelstrom Weapon", nil)
	On(w, "Lightning Shield", 3)
	H.eq(Pick(ns), "Maelstrom Weapon", "seen before")
	w:fire("SPELLS_CHANGED")
	H.eq(Pick(ns), "Maelstrom Weapon", "a new spell is not a respec")
	w:fire("CHARACTER_POINTS_CHANGED")
	H.eq(Pick(ns), "Lightning Shield", "a talent point changed: seen again first")
end)

H.test("your auras hidden from login: the pick reads no aura", function()
	-- In a fight the laid entry is held, and a pass that reads holds a
	-- pick. Hidden from login, no pick is held: the prefer loop runs.
	local w, ns = World(LIST, { ["Lightning Shield"] = true }, nil, true)
	w:fire("UNIT_AURA", "player")
	ns.UpdateResource()
	for _, a in ipairs(w.asked) do
		H.ok(not a:find("Maelstrom Weapon", 1, true), "no read for the preferred entry: " .. a)
	end
	H.eq(Pick(ns), "Lightning Shield", "the first you know")
end)

H.test("a talent rank of 0 wins over a buff seen before", function()
	local talents = { { "Maelstrom Weapon", 0 } }
	local w, ns = World(LIST, { ["Lightning Shield"] = true }, talents)
	On(w, "Maelstrom Weapon", 1)
	H.eq(Pick(ns), "Maelstrom Weapon", "on you: it wins")
	On(w, "Maelstrom Weapon", nil)
	On(w, "Lightning Shield", 3)
	H.eq(Pick(ns), "Lightning Shield", "the talent says no")
end)

H.test("no talent answer: a preferred buff seen on you stays the pick", function()
	local w, ns = World(LIST, { ["Lightning Shield"] = true })
	On(w, "Lightning Shield", 3)
	H.eq(Pick(ns), "Lightning Shield", "never seen: the one on you")
	On(w, "Maelstrom Weapon", 2)
	H.eq(Pick(ns), "Maelstrom Weapon", "on you")
	On(w, "Maelstrom Weapon", nil)
	H.eq(Pick(ns), "Maelstrom Weapon", "gone, seen before: still the pick")
	H.eq(Bar(ns):GetValue(), 0, "an empty bar, not Lightning Shield's 3")
end)

H.test("a fight: the preferred pick stays while your auras are hidden", function()
	local w, ns = World(LIST, { ["Lightning Shield"] = true })
	On(w, "Lightning Shield", 3)
	On(w, "Maelstrom Weapon", 1)
	w.combat, w.hide = true, true
	w:fire("PLAYER_REGEN_DISABLED")
	w:runTimers()
	H.eq(Pick(ns), "Maelstrom Weapon")
end)

H.test("a debuff entry counts the stacks of the debuff on you", function()
	local w, ns = World({ aura = "Arcane Blast", max = 4, filter = "HARMFUL" }, { ["Arcane Blast"] = true })
	H.eq(Pick(ns), "Arcane Blast")
	On(w, "Arcane Blast", 2, "HELPFUL")
	H.eq(Bar(ns):GetValue(), 0, "a buff of that name is not it")
	On(w, "Arcane Blast", 3, "HARMFUL")
	H.eq(Bar(ns):GetValue(), 3, "the debuff's stacks")
	local helpful = 0
	for _, a in ipairs(w.asked) do
		if a == "Arcane Blast/HELPFUL" then helpful = helpful + 1 end
	end
	H.eq(helpful, 0, "never read as a buff")
end)

H.test("a list: a debuff entry on you is picked, read as a debuff", function()
	local w, ns = World({ { aura = "Lightning Shield", max = 3 }, { aura = "Arcane Blast", max = 4, filter = "HARMFUL" } })
	On(w, "Arcane Blast", 2, "HARMFUL")
	H.eq(Pick(ns), "Arcane Blast")
	H.eq(Bar(ns):GetValue(), 2)
end)

H.test("/hud debug aura names the filter it read with", function()
	local w, ns = World({ aura = "Arcane Blast", max = 4, filter = "HARMFUL" }, { ["Arcane Blast"] = true })
	On(w, "Arcane Blast", 1, "HARMFUL")
	local lines = {}
	ns.ProbeAura(function(line) lines[#lines + 1] = line end)
	local text = table.concat(lines, "\n")
	H.ok(text:find("read as HARMFUL", 1, true), "the filter: " .. text)
	w, ns = World(LIST, { ["Lightning Shield"] = true })
	On(w, "Maelstrom Weapon", 1)
	lines = {}
	ns.ProbeAura(function(line) lines[#lines + 1] = line end)
	text = table.concat(lines, "\n")
	H.ok(text:find("read as HELPFUL, preferred", 1, true), "a buff, preferred: " .. text)
end)
