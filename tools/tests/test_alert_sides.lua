-- The sides of the health bars (D-027, TICK-0127). What is missing shows
-- left of a health bar: keep-up (2), your buff off (7) and No bait (5) left
-- of yours, growing left in that order with no gap for a hidden one, and
-- "target needs your buff" (6) left of the target's. Nothing of these sits
-- right of your health bar: that side is for the debuffs on you.

local AI, IB = 7, 8   -- Arcane Intellect, Ice Barrier

-- Make every alert icon once: test mode shows them all, then puts them back.
local function ShowAll(ns)
	ns.ShowAlertSamples(true)
	ns.ShowAlertSamples(false)
end

-- A Mage who knows Arcane Intellect and Ice Barrier, with no aura on.
local function World()
	local w = H.world()
	w.class, w.className = "MAGE", "Mage"
	local env = w.env
	local names = { [AI] = "Arcane Intellect", [IB] = "Ice Barrier" }
	local ids = { ["Arcane Intellect"] = AI, ["Ice Barrier"] = IB }
	env.C_Spell.GetSpellName = function(id) return names[id] end
	env.C_Spell.GetSpellInfo = function(n)
		local id = ids[n] or (names[n] and n)
		if id then return { spellID = id, name = names[id] } end
	end
	env.C_Spell.GetSpellTexture = function(id) return "tex" .. id end
	env.IsPlayerSpell = function(id) return names[id] ~= nil end
	env.SpellHasRange = function() return true end
	env.UnitIsPlayer = function() return true end
	w:loadAddon()
	w.ns.ClassDB().buffSpells = { ["Arcane Intellect"] = true }
	w.ns.HUDini.spells = {}
	-- Every alert icon is made by now. Keep the texture each one is given,
	-- so a test can tell them apart; No bait is the one with the words.
	ShowAll(w.ns)
	for _, f in ipairs(w.frames) do
		if f.tex and f.edge then
			rawset(f.tex, "SetTexture", function(t, v) rawset(t, "shows", v) end)
		end
		if f:GetText() == "No bait" then rawset(f:GetParent(), "isBait", true) end
	end
	return w, w.ns
end

local function Point(f)
	local point, to, rel, x, y = f:GetPoint(1)
	return point, to, rel, x, y
end

-- The shown alert icons left of the bar, from the bar out: each one's
-- RIGHT on the LEFT of the one before, 3 apart, on the same middle line.
local function LeftChain(w, bar)
	local list, after = {}, bar
	while true do
		local found
		for _, f in ipairs(w.frames) do
			local point, to, rel, x, y = Point(f)
			if f.tex and f.edge and f:IsShown() and to == after and rel == "LEFT" then
				H.eq(point, "RIGHT", "anchored by its right")
				H.eq(x, -3, "3 apart")
				H.eq(y, 0, "on the bar's middle line")
				H.ok(found == nil, "one icon on each place")
				found = f
			end
		end
		if not found then return list end
		list[#list + 1] = found
		after = found
	end
end

-- Which alert each icon is: its texture, or "bait".
local function Names(list)
	local out = {}
	for i, f in ipairs(list) do
		local t = rawget(f.tex, "shows")
		local function Sample(name) return tostring(t):find(name, 1, true) ~= nil end
		out[i] = (rawget(f, "isBait") and "bait")
			or ((t == "tex" .. AI or Sample("Spell_Holy_MagicalSentry")) and "ownBuff")
			or ((t == "tex" .. IB or Sample("Ability_Warrior_BattleShout")) and "keepUp")
			or tostring(t)
	end
	return table.concat(out, ",")
end

-- No shown alert icon touches the right of the bar.
local function NothingRight(w, bar)
	for _, f in ipairs(w.frames) do
		local point, to, rel = Point(f)
		if f.tex and f.edge and f:IsShown() and to == bar then
			H.ok(not (rel == "RIGHT" and point == "LEFT"), "nothing right of the bar")
		end
	end
end

local function BarePole(w)
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	w.env.C_TooltipInfo = { GetInventoryItem = function()
		return { lines = { { leftText = "Fishing Pole" } } }
	end }
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
end

local function OwnBuffOff(ns, on)
	ns.missingBuffID = on and AI or nil
	ns.UpdateOwnBuffIcon()
end

local function Fight(w, on)
	w.combat = on
	w:fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
	w:runTimers()
end

H.test("your buff off shows left of your health bar", function()
	local w, ns = World()
	local bar = ns.GetBar("health")
	OwnBuffOff(ns, true)
	H.eq(Names(LeftChain(w, bar)), "ownBuff")
	NothingRight(w, bar)
	OwnBuffOff(ns, false)
	H.eq(Names(LeftChain(w, bar)), "")
end)

H.test("No bait shows left of your health bar, and its words left of it", function()
	local w, ns = World()
	local bar = ns.GetBar("health")
	BarePole(w)
	local chain = LeftChain(w, bar)
	H.eq(Names(chain), "bait")
	for _, f in ipairs(w.frames) do
		if f:GetText() == "No bait" then
			local point, to, rel = f:GetPoint(1)
			H.eq(point, "RIGHT"); H.eq(to, chain[1]); H.eq(rel, "LEFT")
		end
	end
	NothingRight(w, bar)
end)

H.test("two or three missing: keep-up, your buff, then No bait, growing left", function()
	local w, ns = World()
	local bar = ns.GetBar("health")
	OwnBuffOff(ns, true)
	BarePole(w)
	H.eq(Names(LeftChain(w, bar)), "ownBuff,bait", "out of a fight")

	Fight(w, true)
	H.eq(Names(LeftChain(w, bar)), "keepUp,ownBuff,bait", "in a fight: keep-up goes next to the bar")

	OwnBuffOff(ns, false)
	H.eq(Names(LeftChain(w, bar)), "keepUp,bait", "your buff back: the others move in")

	w:holdItem(16, nil)
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	H.eq(Names(LeftChain(w, bar)), "keepUp", "the pole put away")

	OwnBuffOff(ns, true)
	H.eq(Names(LeftChain(w, bar)), "keepUp,ownBuff", "your buff off again: past keep-up")

	Fight(w, false)
	H.eq(Names(LeftChain(w, bar)), "ownBuff", "the fight ends: keep-up goes, your buff moves in")
	OwnBuffOff(ns, false)
	H.eq(Names(LeftChain(w, bar)), "", "nothing missing")
	NothingRight(w, bar)
end)

H.test("target needs your buff shows left of the target's health bar", function()
	local w, ns = World()
	local bar = ns.GetBar("targethealth")
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(Names(LeftChain(w, bar)), "ownBuff", "the Arcane Intellect icon")
	NothingRight(w, bar)
end)

H.test("the test mode samples take the same places", function()
	local w, ns = World()
	ns.ShowAlertSamples(true)
	local chain = LeftChain(w, ns.GetBar("health"))
	H.eq(Names(chain), "keepUp,ownBuff,bait", "three samples left of your health bar")
	H.eq(rawget(chain[3], "isBait"), true, "No bait last")
	H.eq(#LeftChain(w, ns.GetBar("targethealth")), 1, "the target's buff sample")
	NothingRight(w, ns.GetBar("health"))
end)
