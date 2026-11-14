-- A macro on a bar shows as the spell it casts or the item it uses
-- (TICK-0146). The 12.x client reads a macro slot as "macro", id, subType:
-- with the subType "spell", id is the spell's ID, not the macro's number
-- (Blizzard_ActionBar ActionButton.lua compares it with a spell ID). With
-- another subType the macro's number comes from the name on the button.

-- A shaman with a Lightning Bolt macro. bars[slot] = { type, id, subType }.
-- macros[index] = { name, spellID, itemLink }. The values "SECRET" and 999
-- (a secret number, as the game has) are secret.
local function World()
	local w = H.world()
	w.env.issecretvalue = function(v) return v == "SECRET" or v == 999 end
	local ns = w:loadAddon()
	local bars, macros = {}, {}
	w.env.GetActionInfo = function(slot)
		local a = bars[slot]
		if a then return a[1], a[2], a[3] end
	end
	w.env.GetActionText = function(slot)
		local a = bars[slot]
		return a and a.name
	end
	w.env.GetMacroIndexByName = function(name)
		for i, m in pairs(macros) do
			if m[1] == name then return i end
		end
		return 0
	end
	w.env.GetMacroSpell = function(i) return macros[i] and macros[i][2] end
	w.env.GetMacroItem = function(i)
		local m = macros[i]
		if m and m[3] then return "Hearthstone", m[3] end
	end
	local names = { [403] = "Lightning Bolt", [8071] = "Stoneskin Totem" }
	w.env.C_Spell.GetSpellName = function(id) return names[id] end
	w.env.IsPlayerSpell = function(id) return names[id] ~= nil end
	return ns, w, bars, macros
end

local function Shown(ns)
	local spells, items = {}, {}
	for _, e in ipairs(ns.HUDini:Scan()) do
		if e.spellID then spells[e.spellID] = e end
		if e.itemID then items[e.itemID] = e end
	end
	return spells, items
end

H.test("DK's Bar 1: a totem in slot 1, a Lightning Bolt macro in slot 2: both show", function()
	local ns, _, bars, macros = World()
	bars[1] = { "spell", 8071 }
	-- The 12.x shape: the spell's ID, not the macro's number 121.
	bars[2] = { "macro", 403, "spell", name = "Attack" }
	macros[121] = { "Attack", 403 }
	local spells = Shown(ns)
	H.ok(spells[8071], "the totem shows")
	H.ok(spells[403], "the macro shows as Lightning Bolt")
	H.eq(spells[403] and spells[403].slot, 2, "from slot 2")
	H.eq(spells[403] and spells[403].button, 2, "Bar 1's button 2")
end)

H.test("a macro with the subType spell never asks the macro calls", function()
	local ns, w, bars = World()
	bars[2] = { "macro", 403, "spell", name = "Attack" }
	w.env.GetMacroSpell = function() error("GetMacroSpell got a spell ID") end
	w.env.GetMacroItem = function() error("GetMacroItem got a spell ID") end
	H.ok(Shown(ns)[403], "the macro shows as Lightning Bolt")
end)

H.test("a /use macro: the item it uses shows", function()
	local ns, _, bars, macros = World()
	bars[3] = { "macro", 6948, "item", name = "Home" }
	macros[5] = { "Home", nil, "|cffffffff|Hitem:6948::::::::7:::::|h[Hearthstone]|h|r" }
	local _, items = Shown(ns)
	H.ok(items[6948], "the item shows")
	H.eq(items[6948] and items[6948].slot, 3, "from slot 3")
end)

H.test("a macro that casts and uses nothing shows nothing", function()
	local ns, _, bars, macros = World()
	bars[4] = { "macro", 0, "", name = "Startattack" }
	macros[7] = { "Startattack" }
	local spells, items = Shown(ns)
	H.eq(next(spells), nil, "no spell")
	H.eq(next(items), nil, "no item")
end)

H.test("an older client with no subType: id is the macro's number", function()
	local ns, _, bars, macros = World()
	bars[2] = { "macro", 121 }
	macros[121] = { "Attack", 403 }
	H.ok(Shown(ns)[403], "the macro shows as Lightning Bolt")
end)

H.test("a secret name on a macro button: the slot is left out, no error", function()
	local ns, _, bars, macros = World()
	bars[3] = { "macro", 6948, "item", name = "SECRET" }
	macros[5] = { "SECRET", nil, "|Hitem:6948|h" }
	local _, items = Shown(ns)
	H.eq(next(items), nil, "no item")
end)

H.test("a new macro on a bar shows at the next rebuild, with no /reload", function()
	local ns, w, bars, macros = World()
	ns.HUDini:Scan()
	bars[2] = { "macro", 403, "spell", name = "Attack" }
	macros[121] = { "Attack", 403 }
	w:fire("ACTIONBAR_SLOT_CHANGED", 2)
	w:runTimers()
	local found
	for _, e in ipairs(ns.HUDini.spells) do
		if e.spellID == 403 then found = e end
	end
	H.ok(found, "Lightning Bolt is on the HUD")
end)

-- Review of TICK-0146: a secret macro number is a number, so only the
-- secret check keeps it from the compare; and a spell macro with no spell.
H.test("a secret macro number: the slot is left out, never compared", function()
	local ns, w, bars, macros = World()
	w.env.GetMacroIndexByName = function() return 999 end
	bars[3] = { "macro", 6948, "item", name = "Home" }
	macros[999] = { "Home", nil, "|Hitem:6948|h" }
	local _, items = Shown(ns)
	H.eq(next(items), nil, "no item")
end)

H.test("a spell macro with the spell ID 0 shows nothing", function()
	local ns, _, bars = World()
	bars[2] = { "macro", 0, "spell", name = "Attack" }
	H.eq(next((Shown(ns))), nil, "no spell")
end)
