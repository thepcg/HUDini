-- Bar 1 turns its page (TICK-0071). Blizzard's main bar shows page 1, a
-- Shift page 2-6, or, while it is on page 1, a bonus bar 1-4 (Druid forms,
-- Rogue Stealth) as page 7-10: slots 73-120. Out of combat the grid is built
-- again from the new page. In a fight there is no new layout: each Bar 1
-- icon keeps its spot and shows what its button holds on the new page.

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })

-- A world with Bar 1 and Bar 2 on, every icon shown, in bar order.
-- state.page and state.offset are what the game's two APIs answer.
-- bars: [slot] = { kind, id }. o.secret: the game's issecretvalue (Util.lua
-- reads it at load). o.offsetIn: "C_ActionBar" puts GetBonusBarOffset
-- there, not in _G.
local function World(o)
	o = o or {}
	local w = H.world()
	local env = w.env
	env.issecretvalue = o.secret
	local state = { page = 1, offset = 0 }
	local bars, keys, textures, usable, registered = {}, {}, {}, {}, {}
	env.C_ActionBar.GetActionBarPage = function() return state.page end
	local function Offset() return state.offset end
	if o.offsetIn == "C_ActionBar" then
		env.C_ActionBar.GetBonusBarOffset = Offset
	else
		env.GetBonusBarOffset = Offset
	end
	env.C_ActionBar.GetActionTexture = function(slot) return textures[slot] end
	env.C_ActionBar.IsUsableAction = function(slot) usable[#usable + 1] = slot; return true end
	env.C_ActionBar.RegisterActionUIButton = function(_, slot) registered[#registered + 1] = slot end
	env.C_ActionBar.UnregisterActionUIButton = function() end
	env.GetActionInfo = function(slot)
		local a = bars[slot]
		if a then return a[1], a[2] end
	end
	env.GetBindingKey = function(name) return keys[name] end
	env.C_Item.GetItemIconByID = function() return nil end
	for i = 1, 12 do keys["ACTIONBUTTON" .. i] = tostring(i) end
	keys.MULTIACTIONBAR1BUTTON1 = "F1"

	local ns = w:loadAddon()
	local db = env.HUDiniDB
	db.autoBars, db.layoutMode, db.maxIcons, db.showUsable = false, "wrap", 100, true
	db.sortMode = "actionbar" -- grid order by bar and button, not by key
	db.bars.bar1, db.bars.bar2 = true, true
	return ns, w, {
		state = state, bars = bars, textures = textures,
		usable = usable, registered = registered,
	}
end

-- The icon grid as "slot:spellID" in grid order.
local function Grid(ns)
	local out = {}
	for _, e in ipairs(ns.HUDini.spells) do
		out[#out + 1] = e.slot .. ":" .. tostring(e.spellID)
	end
	return table.concat(out, " ")
end

local function Has(list, v)
	for _, x in ipairs(list) do if x == v then return true end end
	return false
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

H.test("Bar 1's page: page 1, a Shift page, bonus bars 1-4 on page 1 only", function()
	local ns, _, t = World()
	for _, c in ipairs({
		{ 1, 0, 1 }, { 1, 1, 7 }, { 1, 2, 8 }, { 1, 3, 9 }, { 1, 4, 10 },
		{ 2, 1, 2 }, { 6, 0, 6 }, { 6, 3, 6 },
		-- Not a page, or not a bonus bar 1-4: page 1.
		{ 1, 5, 1 }, { 7, 0, 1 }, { 0, 0, 1 }, { 1.5, 0, 1 }, { 1, 2.5, 1 },
		{ nil, 2, 8 }, { 1, nil, 1 }, { "2", 0, 1 },
	}) do
		t.state.page, t.state.offset = c[1], c[2]
		H.eq(ns.Bar1Page(), c[3], ("page %s, bonus bar %s"):format(tostring(c[1]), tostring(c[2])))
	end
end)

H.test("a secret page or bonus bar, or an API that throws, counts as page 1", function()
	local ns, w, t = World({ secret = function(v) return v == SECRET end })
	t.state.page, t.state.offset = SECRET, 0
	H.eq(ns.Bar1Page(), 1, "secret page")
	t.state.page, t.state.offset = 1, SECRET
	H.eq(ns.Bar1Page(), 1, "secret bonus bar")
	w.env.C_ActionBar.GetActionBarPage = function() error("no page") end
	t.state.offset = 2
	H.eq(ns.Bar1Page(), 8, "a page API that throws counts as page 1")
	w.env.GetBonusBarOffset = function() error("no bonus bar") end
	H.eq(ns.Bar1Page(), 1, "a bonus bar API that throws")
end)

H.test("GetBonusBarOffset is found in C_ActionBar too; no API at all is page 1", function()
	local ns, w, t = World({ offsetIn = "C_ActionBar" })
	t.state.offset = 1
	H.eq(ns.Bar1Page(), 7, "C_ActionBar.GetBonusBarOffset")
	w.env.C_ActionBar.GetActionBarPage = nil
	w.env.C_ActionBar.GetBonusBarOffset = nil
	H.eq(ns.Bar1Page(), 1, "no API")
end)

--------------------------------------------------------------------------------
-- Out of combat: the grid is built again
--------------------------------------------------------------------------------

H.test("Cat Form out of combat: the grid reads slots 73-84 with Bar 1's keys", function()
	local ns, w, t = World()
	t.bars[1] = { "spell", 1 }   -- Wrath
	t.bars[73] = { "spell", 73 } -- Shred
	t.bars[84] = { "spell", 84 } -- Ferocious Bite, Bar 1 button 12
	t.bars[61] = { "spell", 61 } -- Bar 2
	ns.HUDini:Refresh()
	H.eq(Grid(ns), "1:1 61:61", "caster form")

	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	H.eq(Grid(ns), "73:73 84:84 61:61", "Cat Form")
	local e = ns.HUDini.spells[1]
	H.eq(e.key, "1", "Shred has button 1's key")
	H.eq(e.barName, "Action Bar 1")
	H.eq(e.button, 1)
	H.eq(ns.HUDini.spells[2].key, "12", "button 12's key")
	H.eq(ns.HUDini.icons[1].slot, 73, "the icon shows slot 73")
	H.ok(Has(t.registered, 73), "the icon is handed to the game for slot 73")

	t.state.offset = 0
	w:fire("UPDATE_SHAPESHIFT_FORM")
	w:runTimers()
	H.eq(Grid(ns), "1:1 61:61", "back in caster form")
end)

H.test("a Shift page: Bar 1 reads slots 13-24, with Bar 1's keys", function()
	local ns, w, t = World()
	t.bars[1] = { "spell", 1 }
	t.bars[13] = { "spell", 13 }
	ns.HUDini:Refresh()
	t.state.page = 2
	w:fire("ACTIONBAR_PAGE_CHANGED")
	w:runTimers()
	H.eq(Grid(ns), "13:13", "page 2")
	H.eq(ns.HUDini.spells[1].key, "1")
end)

--------------------------------------------------------------------------------
-- In a fight: a swap in place
--------------------------------------------------------------------------------

-- Wrath, Moonfire and Rejuvenation on Bar 1 buttons 1-3; Bar 2 button 1.
-- The Cat Form bar has Shred on button 1, nothing on button 2, Rake on 3.
local function Druid(o)
	local ns, w, t = World(o)
	t.bars[1], t.bars[2], t.bars[3] = { "spell", 1 }, { "spell", 2 }, { "spell", 3 }
	t.bars[61] = { "spell", 61 }
	t.bars[73], t.bars[75] = { "spell", 73 }, { "spell", 75 }
	t.textures[73] = 7300
	ns.HUDini:Refresh()
	H.eq(Grid(ns), "1:1 2:2 3:3 61:61", "caster form, out of combat")
	local hud = ns.HUDini
	local real, layouts = hud.Layout, { n = 0 }
	hud.Layout = function(self, ...)
		layouts.n = layouts.n + 1
		return real(self, ...)
	end
	return ns, w, t, layouts
end

-- Where each icon sits, as text.
local function Spots(ns)
	local out = {}
	for i = 1, #ns.HUDini.spells do
		local p = { ns.HUDini.icons[i]:GetPoint(1) }
		out[#out + 1] = tostring(p[4]) .. "," .. tostring(p[5])
	end
	return table.concat(out, " ")
end

H.test("Bear or Cat Form in a fight: Bar 1's icons swap in place, no layout, nothing blocked", function()
	local ns, w, t, layouts = Druid()
	local hud = ns.HUDini
	local spots = Spots(ns)
	local registered = #t.registered
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")

	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:fire("UPDATE_SHAPESHIFT_FORM")
	w:runTimers()

	H.eq(Grid(ns), "73:73 74:nil 75:75 61:61", "same icons, Bar 1's on the Cat Form slots")
	H.eq(layouts.n, 0, "no layout in a fight")
	H.eq(Spots(ns), spots, "every icon keeps its spot")
	H.eq(hud.icons[1].slot, 73)
	H.eq(hud.icons[1].spellID, 73, "the icon has Shred")
	H.eq(hud.icons[2]:IsShown(), false, "button 2 is empty in Cat Form: its icon hides")
	H.eq(hud.icons[3]:IsShown(), true)
	H.eq(hud.icons[4].slot, 61, "Bar 2 is not touched")
	H.ok(Has(t.usable, 73), "the usable check reads the new slot")
	H.eq(#t.registered, registered, "no registration in a fight")
	H.eq(hud.needRefresh, true, "the fight's end builds the grid again")

	-- Out of Cat Form, same fight: back to the caster spells.
	t.state.offset = 0
	w:fire("UPDATE_SHAPESHIFT_FORM")
	w:runTimers()
	H.eq(Grid(ns), "1:1 2:2 3:3 61:61", "caster form, same fight")
	H.eq(hud.icons[2]:IsShown(), true, "button 2's icon shows again")

	-- Into Cat Form again, then the fight ends: a full rebuild.
	t.state.offset = 1
	w:fire("UPDATE_SHAPESHIFT_FORM")
	w:runTimers()
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Grid(ns), "73:73 75:75 61:61", "the fight's end: the Cat Form grid, no empty icon")
	H.eq(layouts.n, 1, "one layout at the fight's end")
	H.eq(hud.needRefresh, false)
	H.ok(Has(t.registered, 73), "the fight's end hands slot 73 to the game")
end)

H.test("in a fight, no swap while Bar 1's page stays the same", function()
	local ns, w, t = Druid()
	w.combat = true
	t.bars[1] = { "spell", 9 } -- a slot change mid fight, same page
	w:fire("ACTIONBAR_SLOT_CHANGED", 1)
	w:runTimers()
	H.eq(Grid(ns), "1:1 2:2 3:3 61:61", "nothing swapped")
	H.eq(ns.HUDini.needRefresh, true, "it waits for the fight's end")
end)

H.test("in a fight, a secret action on the new page keeps its slot's picture", function()
	local ns, w, t = Druid({ secret = function(v) return v == SECRET end })
	-- A secret ID: comparing it throws, as SlotAction's "id > 0" would.
	t.bars[73] = { "spell", SECRET }
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	local hud = ns.HUDini
	H.eq(hud.spells[1].slot, 73)
	H.eq(hud.spells[1].spellID, nil, "no secret in the grid's data")
	H.eq(hud.icons[1]:IsShown(), true, "the slot has a picture: the icon shows")
end)

H.test("the bonus bar event is heard", function()
	local _, w = World()
	local heard = false
	for _, f in ipairs(w.frames) do
		if f:IsEventRegistered("UPDATE_BONUS_ACTIONBAR") then heard = true end
	end
	H.ok(heard, "UPDATE_BONUS_ACTIONBAR is registered")
end)

H.test("in a fight, the swap drops the old spell's buff names and buff timer", function()
	local ns, w, t = Druid()
	w.env.C_Spell.GetSpellName = function(id) return ({ [1] = "Thorns", [73] = "Shred" })[id] end
	w.env.C_UnitAuras.GetAuraDuration = function() return {} end
	local hud = ns.HUDini
	local e, f = hud.spells[1], hud.icons[1]
	H.eq(ns.AuraNames(e)[1], "Thorns", "button 1 has Thorns before the swap")
	f.buff:Show() -- Thorns' time left
	w.combat = true
	-- In a fight the buff read cannot tell (a secret): it leaves the icon alone.
	w.env.C_UnitAuras.GetAuraDataBySpellName = function() error("secret") end
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	H.eq(e.spellID, 73)
	H.eq(ns.AuraNames(e)[1], "Shred", "the buff names are Shred's")
	H.eq(f.buff:IsShown(), false, "Thorns' timer is gone from the Shred icon")
end)

H.test("in a fight, a swapped spell already on the grid shows once; the lower bar's copy stays", function()
	local ns, w, t = World()
	t.bars[1], t.bars[61] = { "spell", 1 }, { "spell", 1 }    -- Wrath on Bar 1 and Bar 2
	t.bars[62], t.bars[73] = { "spell", 73 }, { "spell", 73 } -- Shred on Bar 2 and Cat Form
	local hud = ns.HUDini
	hud:Refresh()
	H.eq(Grid(ns), "1:1 62:73", "Scan keeps Bar 1's Wrath")
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	H.eq(Grid(ns), "73:73 62:73")
	H.eq(hud.icons[1]:IsShown(), true, "Bar 1's Shred shows")
	H.eq(hud.icons[2]:IsShown(), false, "Bar 2's Shred hides: it is on the grid already")
	t.state.offset = 0
	w:fire("UPDATE_SHAPESHIFT_FORM")
	w:runTimers()
	H.eq(hud.icons[2]:IsShown(), true, "back in caster form, Bar 2's Shred shows again")
	t.state.offset = 1
	w:fire("UPDATE_SHAPESHIFT_FORM")
	w:runTimers()
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Grid(ns), "73:73 61:1", "the fight's end: each spell once, Bar 2's Wrath back")
end)

H.test("in a fight, in Bar row mode, a spell on two rows shows on both", function()
	local ns, w, t = World()
	w.env.HUDiniDB.layoutMode = "bar"
	t.bars[1], t.bars[62], t.bars[73] = { "spell", 1 }, { "spell", 73 }, { "spell", 73 }
	local hud = ns.HUDini
	hud:Refresh()
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	H.eq(Grid(ns), "73:73 62:73")
	H.eq(hud.icons[1]:IsShown(), true, "row 1")
	H.eq(hud.icons[2]:IsShown(), true, "row 2 keeps its own copy")
end)

-- Plain numbers the fake game calls secret: a secret has the type "number"
-- in the game, so every range check would pass it.
local MARKED = { [5] = true, [7474] = true, [9100] = true }

H.test("a secret page, spell ID or picture is never used", function()
	local ns, w, t = Druid({ secret = function(v) return MARKED[v] == true end })
	t.state.page = 5
	H.eq(ns.Bar1Page(), 1, "a secret page 5 counts as page 1")
	t.state.page = 1
	t.bars[74] = { "spell", 7474 }                     -- button 2: a secret spell ID
	t.bars[75], t.textures[75] = { "spell", 7474 }, 9100 -- button 3: secret ID and picture
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	local hud = ns.HUDini
	H.eq(hud.spells[2].slot, 74)
	H.eq(hud.spells[2].spellID, nil, "no secret spell ID in the grid's data")
	H.eq(hud.icons[2]:IsShown(), false, "nothing readable: the icon hides")
	H.eq(hud.spells[3].slot, 75)
	H.eq(hud.icons[3]:IsShown(), false, "a secret picture counts as none")
end)

H.test("in a fight, a secret item ID with a plain picture keeps its picture", function()
	local ns, w, t = Druid({ secret = function(v) return MARKED[v] == true end })
	-- A secret item ID does not throw in SlotAction: only IsSecret catches it.
	t.bars[74], t.textures[74] = { "item", 7474 }, 7400
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	local hud = ns.HUDini
	H.eq(hud.spells[2].slot, 74)
	H.eq(hud.spells[2].itemID, nil, "no secret item ID in the grid's data")
	H.eq(hud.icons[2]:IsShown(), true, "the slot has a picture: the icon shows")
end)

H.test("in a fight, a slot that cannot be read and has no picture hides", function()
	local ns, w, t = Druid({ secret = function(v) return v == SECRET end })
	t.bars[74] = { "spell", SECRET } -- SlotAction throws; no picture
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	local hud = ns.HUDini
	H.eq(hud.spells[2].slot, 74)
	H.eq(hud.spells[2].spellID, nil)
	H.eq(hud.icons[2]:IsShown(), false, "nothing to show: the icon hides")
end)

H.test("in a fight, a slot with a picture but no spell or item hides, as Scan leaves it out", function()
	local ns, w, t = Druid()
	t.bars[74], t.textures[74] = { "flyout", 9 }, 7400 -- button 2: a flyout
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	H.eq(ns.HUDini.icons[2]:IsShown(), false, "the flyout's icon hides")
end)

H.test("in a fight, in key order, Bar 1's copy of a spell shows and the other bar's copy hides", function()
	local ns, w, t = World()
	w.env.HUDiniDB.sortMode = "keybind"
	w.env.GetBindingKey = function(name)
		if name == "ACTIONBUTTON9" then return nil end -- button 9 has no key
		if name == "MULTIACTIONBAR1BUTTON1" then return "F1" end
		return name:match("^ACTIONBUTTON(%d+)$")
	end
	t.bars[9] = { "spell", 9 }    -- Bar 1 button 9, caster form
	t.bars[61] = { "spell", 81 }  -- Bar 2 button 1 (F1)
	t.bars[81] = { "spell", 81 }  -- Bar 1 button 9, Cat Form
	local hud = ns.HUDini
	hud:Refresh()
	H.eq(Grid(ns), "61:81 9:9", "in key order, F1 comes before the button with no key")
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	H.eq(Grid(ns), "61:81 81:81")
	H.eq(hud.icons[2]:IsShown(), true, "Bar 1's copy shows")
	H.eq(hud.icons[1]:IsShown(), false, "Bar 2's copy hides")
end)

H.test("in a fight, a swapped item already on the grid shows once", function()
	local ns, w, t = World()
	t.bars[1] = { "spell", 1 }
	t.bars[62], t.bars[73] = { "item", 600 }, { "item", 600 } -- a potion on Bar 2 and Cat Form
	local hud = ns.HUDini
	hud:Refresh()
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	H.eq(hud.spells[1].itemID, 600)
	H.eq(hud.icons[1]:IsShown(), true, "Bar 1's potion shows")
	H.eq(hud.icons[2]:IsShown(), false, "Bar 2's potion hides")
end)

H.test("in a fight, a spell and an item with the same ID both show", function()
	local ns, w, t = World()
	t.bars[1] = { "spell", 1 }
	t.bars[62], t.bars[73] = { "item", 73 }, { "spell", 73 }
	local hud = ns.HUDini
	hud:Refresh()
	w.combat = true
	t.state.offset = 1
	w:fire("UPDATE_BONUS_ACTIONBAR")
	w:runTimers()
	H.eq(hud.spells[1].spellID, 73)
	H.eq(hud.spells[2].itemID, 73)
	H.eq(hud.icons[1]:IsShown(), true, "spell 73 shows")
	H.eq(hud.icons[2]:IsShown(), true, "item 73 shows too")
end)
