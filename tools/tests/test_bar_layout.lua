-- Which action slots each of the eight bars reads (TICK-0070). Blizzard's
-- MultiActionBars.xml (live 12.x) gives each bar frame an action page of
-- 12 slots: page 1 is Bar 1, pages 6, 5, 3 and 4 are Bars 2 to 5, and pages
-- 13, 14 and 15 are Bars 6 to 8. Pages 7 to 10 (slots 73-120) are the bonus
-- bars (Druid forms, Rogue stealth): no bar reads them.

local FIRST = { 1, 61, 49, 25, 37, 145, 157, 169 } -- Bar 1 to Bar 8
local BINDING = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON",
	"MULTIACTIONBAR3BUTTON", "MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON",
	"MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON" }

local function Expected()
	local slots = {}
	for _, first in ipairs(FIRST) do
		for i = 0, 11 do slots[#slots + 1] = first + i end
	end
	table.sort(slots)
	return table.concat(slots, ",")
end

-- A world with every bar turned on. read: each slot GetActionInfo was asked for.
local function World()
	local w = H.world()
	local ns = w:loadAddon()
	local db = w.env.HUDiniDB
	db.autoBars, db.layoutMode, db.maxIcons = false, "wrap", 100
	for n = 2, 8 do db.bars["bar" .. n] = true end
	local read, bars = {}, {}
	w.env.GetActionInfo = function(slot)
		read[slot] = true
		local a = bars[slot]
		if a then return a[1], a[2] end
	end
	return ns, w, read, bars
end

local function Slots(read)
	local slots = {}
	for slot in pairs(read) do slots[#slots + 1] = slot end
	table.sort(slots)
	return table.concat(slots, ",")
end

H.test("the icon grid reads each bar's own 12 slots, and no bonus bar", function()
	local ns, _, read = World()
	ns.HUDini:Scan()
	H.eq(Slots(read), Expected())
	for slot = 73, 120 do H.eq(read[slot], nil, "bonus slot " .. slot .. " not read") end
end)

H.test("the action-bar spell list reads the same slots", function()
	local ns, _, read = World()
	ns.ActionBarSpells()
	H.eq(Slots(read), Expected())
end)

H.test("a spell on each bar's first and last button shows, with that bar's key", function()
	local ns, w, _, bars = World()
	local spells, keys = {}, {}
	for n, first in ipairs(FIRST) do
		bars[first] = { "spell", 100 + n }
		bars[first + 11] = { "spell", 200 + n }
		spells[100 + n], spells[200 + n] = "First " .. n, "Last " .. n
		keys[BINDING[n] .. "1"], keys[BINDING[n] .. "12"] = "F" .. n, "L" .. n
	end
	bars[73] = { "spell", 999 } -- a Druid's Cat Form bar
	w.env.C_Spell.GetSpellName = function(id) return spells[id] or (id == 999 and "Shred") end
	w.env.GetBindingKey = function(name) return keys[name] end
	local shown = {}
	for _, e in ipairs(ns.HUDini:Scan()) do shown[e.spellID] = e end
	for n = 1, 8 do
		local name = "Action Bar " .. n
		H.eq(shown[100 + n] and shown[100 + n].barName, name, name .. ": first button")
		H.eq(shown[100 + n] and shown[100 + n].key, "F" .. n, name .. ": first button's key")
		H.eq(shown[200 + n] and shown[200 + n].barName, name, name .. ": last button")
		H.eq(shown[200 + n] and shown[200 + n].key, "L" .. n, name .. ": last button's key")
	end
	H.eq(shown[999], nil, "the Cat Form bar is not read")
	local list = table.concat(ns.ActionBarSpells(), "|")
	H.eq(list:find("Shred", 1, true), nil, "no bonus-bar spell in the list")
	H.eq(list:find("First 6", 1, true) ~= nil, true, "Bar 6's spell in the list")
end)
