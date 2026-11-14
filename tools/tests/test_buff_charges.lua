-- A buff's charges on its icon, with its time left (TICK-0148). The count
-- is the aura's stack count ("applications"), as the game's own buff icons
-- show it, bottom right. The game makes the text
-- (C_UnitAuras.GetAuraApplicationDisplayCount); a secret one goes to the
-- text as it is. An item's icon keeps that spot for the item count.

-- A shaman with Lightning Shield on the first icon. w.auras[name]: the buff
-- on you. The display call works as the game's: "" under the minimum, the
-- count as text, or w.hidden (a secret string) when w.restricted is set.
local function World()
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_Spell.GetSpellName = function(id) return id == 324 and "Lightning Shield" or nil end
	local ns = w:loadAddon()
	w.auras, w.calls = {}, 0
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name) return w.auras[name] end
	env.C_UnitAuras.GetAuraDuration = function() return {} end
	env.C_UnitAuras.GetAuraApplicationDisplayCount = function(unit, id, min)
		w.calls = w.calls + 1
		assert(unit == "player", "the player's aura")
		if w.restricted then return w.hidden end
		for _, data in pairs(w.auras) do
			if data.auraInstanceID == id then
				return data.applications >= (min or 2) and tostring(data.applications) or ""
			end
		end
		error("no aura with that instance")
	end
	local Throw = function() error("a secret value was used") end
	w.hidden = setmetatable({}, { __lt = Throw, __le = Throw, __concat = Throw, __index = Throw,
		__eq = Throw, __len = Throw })
	w.secret[w.hidden] = true
	env.HUDiniDB.showBuffTime = true
	local hud = ns.HUDini
	hud.spells = { { spellID = 324, slot = 1, auraNames = { "Lightning Shield" } } }
	local f = hud:GetIcon(1)
	return w, ns, f
end

local function Charges(f)
	return f.charges and f.charges:GetText()
end

local function Shield(w, n)
	w.auras["Lightning Shield"] = { auraInstanceID = 77, duration = 600, expirationTime = 700, applications = n }
end

H.test("Lightning Shield: its charges show, down to the last one, and go with the buff", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	H.eq(Charges(f), "3", "three charges")
	Shield(w, 2)
	ns.UpdateIconAuras()
	H.eq(Charges(f), "2", "a hit uses one")
	Shield(w, 1)
	ns.UpdateIconAuras()
	H.eq(Charges(f), "1", "the last charge shows too")
	w.auras["Lightning Shield"] = nil
	ns.UpdateIconAuras()
	H.eq(Charges(f), "", "the buff ends: no number")
end)

H.test("a buff with no charges shows no number", function()
	local w, ns, f = World()
	Shield(w, 0)
	ns.UpdateIconAuras()
	H.eq(Charges(f) or "", "", "no number")
end)

H.test("a secret count goes to the text as it is, never compared", function()
	local w, ns, f = World()
	Shield(w, 3)
	w.restricted = true
	ns.UpdateIconAuras()
	H.ok(rawequal(Charges(f), w.hidden), "the secret text is on the icon")
end)

H.test("a count the game will not give leaves the last number", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	w.env.C_UnitAuras.GetAuraApplicationDisplayCount = function() error("refused") end
	ns.UpdateIconAuras()
	H.eq(Charges(f), "3", "the last number stays")
end)

H.test("Buff time off: no charges either", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	w.env.HUDiniDB.showBuffTime = false
	ns.UpdateIconAuras()
	H.eq(Charges(f), "", "no number")
end)

H.test("a client with no display call: the plain count, and no number for a secret one", function()
	local w, ns, f = World()
	w.env.C_UnitAuras.GetAuraApplicationDisplayCount = nil
	Shield(w, 3)
	ns.UpdateIconAuras()
	H.eq(Charges(f), "3", "plain: the count")
	w.auras["Lightning Shield"].applications = w.hidden
	ns.UpdateIconAuras()
	H.eq(Charges(f), "", "secret: no number, and no compare")
end)

H.test("an item keeps its count; a buff from it adds no charges", function()
	local w, ns, f = World()
	ns.HUDini.spells[1] = { itemID = 5, slot = 1, auraNames = { "Lightning Shield" } }
	w.env.C_ActionBar.GetActionDisplayCount = function() return "12" end
	Shield(w, 3)
	ns.UpdateIconAuras()
	ns.HUDini:UpdateCounts()
	H.eq(f.count:GetText(), "12", "the item count")
	H.eq(Charges(f) or "", "", "no charges")
	H.eq(w.calls, 0, "the display call is not asked")
end)

H.test("an icon that turns from a spell to an item drops the old charges", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	H.eq(Charges(f), "3", "the spell's charges")
	-- The item's buff is on you (food, an elixir), so only the item's own
	-- clear takes the number away (review of TICK-0148, item 1).
	ns.HUDini.spells[1] = { itemID = 5, slot = 1, auraNames = { "Lightning Shield" } }
	ns.UpdateIconAuras()
	H.eq(Charges(f), "", "gone on the item")
end)

-- Review of TICK-0148: the paths the first tests did not reach.

H.test("no display call: a secret count that is a number is not compared (Plain first)", function()
	local w, ns, f = World()
	w.env.C_UnitAuras.GetAuraApplicationDisplayCount = nil
	Shield(w, 4321)
	w.secret[4321] = true
	ns.UpdateIconAuras()
	H.eq(Charges(f), "", "no number")
end)

H.test("no display call: one charge shows \"1\", none shows nothing", function()
	local w, ns, f = World()
	w.env.C_UnitAuras.GetAuraApplicationDisplayCount = nil
	Shield(w, 1)
	ns.UpdateIconAuras()
	H.eq(Charges(f), "1", "the last charge")
	Shield(w, 0)
	ns.UpdateIconAuras()
	H.eq(Charges(f), "", "no charges")
end)

H.test("a text the icon will not take is no error", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	f.charges.SetText = function() error("a secret value was used") end
	Shield(w, 2)
	local ok, err = pcall(ns.UpdateIconAuras)
	H.ok(ok, "no error: " .. tostring(err))
end)
