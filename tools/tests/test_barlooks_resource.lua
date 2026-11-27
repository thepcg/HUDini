-- The looks list offers the resource bar only when the bar can show for
-- you (TICK-0199 follow-up): a buff you cannot cast yet gets no look row,
-- and a Druid's combo points keep theirs out of Cat Form.

local IDS = { ["Lightning Shield"] = 324 }

local function World(class, resource, known)
	local w = H.world()
	local env = w.env
	w.class, w.className = class, class:sub(1, 1) .. class:sub(2):lower()
	w.known = known or {}
	env.C_Spell.GetSpellInfo = function(name)
		if IDS[name] then return { spellID = IDS[name] } end
	end
	env.IsPlayerSpell = function(id)
		for name, n in pairs(IDS) do
			if n == id then return w.known[name] == true end
		end
		return false
	end
	env.Enum.PowerType.ComboPoints = env.Enum.PowerType.ComboPoints or 4
	local ns = w:loadAddon()
	ns.RegisterClass(class, { resource = resource })
	return w, ns
end

local function Has(ns, id)
	for _, v in ipairs(ns.ClassBarLookIds()) do
		if v == id then return true end
	end
	return false
end

H.test("a resource buff you cannot cast yet: no look row; once known: the row", function()
	local w, ns = World("SHAMAN", { aura = "Lightning Shield", max = 3 })
	H.eq(Has(ns, "resource"), false, "not known")
	w.known["Lightning Shield"] = true
	H.eq(Has(ns, "resource"), true, "known")
end)

H.test("a Druid out of Cat Form keeps the combo points look row", function()
	local _, ns = World("DRUID", { power = "ComboPoints", onlyWith = "ENERGY" })
	H.eq(ns.ClassResource(), nil, "the bar shows nothing out of the form")
	H.eq(Has(ns, "resource"), true, "the row stays")
end)

H.test("a class with no resource: no look row", function()
	local _, ns = World("WARRIOR", nil)
	H.eq(Has(ns, "resource"), false)
end)
