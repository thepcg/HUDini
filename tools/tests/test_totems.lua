-- Totem timers (TICK-0108). A shaman sees each totem that is down, with
-- its icon and its time left, in a row under the HUD; it goes when the
-- totem ends. Only a plain answer shows or hides a spot: a secret "a totem
-- is down" goes to SetAlphaFromBoolean, and a secret time goes to the
-- Cooldown as it is. What it looks like needs a test sitting.

local ORDER = { 2, 1, 3, 4 } -- earth, fire, water, air: the game's order

-- A logged-in shaman. w.totems[slot] = { have, start, duration, icon }
-- is what GetTotemInfo says; w.durations[slot] is the duration object
-- GetTotemDuration gives. w.secret: values the game hides. A secret test
-- flags the very value that WOULD show the wrong thing without its guard.
local function World(class)
	local w = H.world()
	local env = w.env
	w.class, w.className = class or "SHAMAN", class and "Other" or "Shaman"
	w.secret, w.totems, w.durations = {}, {}, {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.MAX_TOTEMS = 4
	env.SHAMAN_TOTEM_PRIORITIES = ORDER
	env.GetTotemInfo = function(slot)
		if w.infoThrows then error("restricted") end
		local t = w.totems[slot]
		if not t then return false, "", 0, 0, 0 end
		return t.have, "Totem " .. slot, t.start, t.duration, t.icon
	end
	env.GetTotemDuration = function(slot)
		if w.durationThrows then error("restricted") end
		return w.durations[slot]
	end
	local ns = w:loadAddon()
	return w, ns
end

-- Record what each spot is told: the fake frames keep none of it.
local function Watch(ns)
	for i = 1, 4 do
		local f = ns.TotemSpot(i)
		local seen = {}
		f.seen = seen
		rawset(f, "SetAlphaFromBoolean", function(_, v, yes, no) seen.fromBoolean = { v, yes, no } end)
		rawset(f.icon, "SetTexture", function(_, tex) seen.icon = tex end)
		rawset(f.cd, "SetCooldownFromDurationObject", function(_, d) seen.object = d end)
		rawset(f.cd, "SetCooldown", function(_, s, d) seen.cooldown = { s, d } end)
		rawset(f.cd, "Clear", function() seen.cleared = true end)
	end
end

local function Reset(ns)
	for i = 1, 4 do
		local seen = ns.TotemSpot(i).seen
		for k in pairs(seen) do seen[k] = nil end
	end
end

-- The spot that holds a slot, left to right.
local function SpotOf(ns, slot)
	for i, s in ipairs(ORDER) do
		if s == slot then return ns.TotemSpot(i) end
	end
end

local function Drop(w, slot)
	w.totems[slot] = { have = true, start = 100, duration = 120, icon = 1000 + slot }
	w.durations[slot] = { slot = slot } -- a duration object: any table
	w:fire("PLAYER_TOTEM_UPDATE", slot)
end

local function Ends(w, slot)
	w.totems[slot], w.durations[slot] = nil, nil
	w:fire("PLAYER_TOTEM_UPDATE", slot)
end

H.test("a shaman: on by default, four spots, all hidden with no totem down", function()
	local w, ns = World()
	H.eq(w.env.HUDiniDB.showTotems, true, "on by default")
	H.eq(ns.GetModule("totems").enabled, true, "the module is on")
	for i = 1, 4 do
		H.ok(ns.TotemSpot(i), "spot " .. i)
		H.eq(ns.TotemSpot(i):IsShown(), false, "spot " .. i .. " hidden")
		H.eq(ns.TotemSpot(i):IsMouseEnabled(), false, "spot " .. i .. " takes no clicks")
	end
	H.eq(ns.TotemSpot(5), nil, "four slots, four spots")
end)

H.test("another class: no module, no spots, a totem changes nothing", function()
	local w, ns = World("MAGE")
	H.eq(ns.GetModule("totems").enabled, false, "off on a mage")
	w.totems[1] = { have = true, start = 1, duration = 2, icon = 3 }
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(ns.TotemSpot(1), nil, "no frames made")
end)

H.test("each slot shows its totem, its icon and its time, then goes", function()
	local w, ns = World()
	Watch(ns)
	for _, slot in ipairs(ORDER) do
		Reset(ns)
		local f = SpotOf(ns, slot)
		Drop(w, slot)
		H.eq(f:IsShown(), true, "slot " .. slot .. " shows")
		H.eq(f.seen.icon, 1000 + slot, "slot " .. slot .. ": its icon")
		H.eq(f.seen.object, w.durations[slot], "slot " .. slot .. ": its time, from the game")
		H.eq(f:GetAlpha(), 1, "slot " .. slot .. ": plain, full alpha")
		H.eq(f.seen.fromBoolean, nil, "slot " .. slot .. ": plain, no SetAlphaFromBoolean")
		Ends(w, slot)
		H.eq(f:IsShown(), false, "slot " .. slot .. " goes")
		H.eq(f.seen.cleared, true, "slot " .. slot .. ": its time cleared")
	end
end)

H.test("earth is at the left, then fire, water and air", function()
	local w, ns = World()
	Watch(ns)
	Drop(w, 2)
	H.eq(ns.TotemSpot(1):IsShown(), true, "earth: the first spot")
	H.eq(ns.TotemSpot(1).seen.icon, 1002, "earth's icon")
	H.eq(ns.TotemSpot(2):IsShown(), false, "fire's spot stays empty")
	Drop(w, 4)
	H.eq(ns.TotemSpot(4):IsShown(), true, "air: the last spot")
	H.eq(ns.TotemSpot(3):IsShown(), false, "water's spot stays empty")
end)

H.test("a secret time goes to the Cooldown as it is", function()
	-- Plain first, then the same duration object flagged secret.
	local w, ns = World()
	Watch(ns)
	Drop(w, 1)
	local f = SpotOf(ns, 1)
	H.eq(f.seen.object, w.durations[1], "plain")
	Reset(ns)
	w.secret[w.durations[1]] = true
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(f.seen.object, w.durations[1], "secret: the same object, unchanged")
	H.eq(f.seen.cooldown, nil, "secret: no plain fallback")
	H.eq(f:IsShown(), true, "secret: still shown")
end)

H.test("a secret totem-down true goes to SetAlphaFromBoolean, not an if", function()
	local w, ns = World()
	Watch(ns)
	Drop(w, 3)
	local f = SpotOf(ns, 3)
	H.eq(f.seen.fromBoolean, nil, "plain: no SetAlphaFromBoolean")
	Reset(ns)
	w.secret[true] = true
	w:fire("PLAYER_TOTEM_UPDATE", 3)
	H.ok(f.seen.fromBoolean, "secret: SetAlphaFromBoolean")
	H.eq(f.seen.fromBoolean[1], true, "the secret goes as it is")
	H.eq(f.seen.fromBoolean[2], 255, "shown when true")
	H.eq(f.seen.fromBoolean[3], 0, "hidden when false")
	H.eq(f:IsShown(), true, "the frame is up; the game sets its alpha")
end)

H.test("a secret totem-down false goes to SetAlphaFromBoolean too", function()
	-- The false that would hide the spot, flagged secret: only the game
	-- may hide it, through the alpha.
	local w, ns = World()
	Watch(ns)
	Drop(w, 4)
	local f = SpotOf(ns, 4)
	w.totems[4].have = false
	w:fire("PLAYER_TOTEM_UPDATE", 4)
	H.eq(f:IsShown(), false, "plain false: hidden")
	Reset(ns)
	w.secret[false] = true
	w:fire("PLAYER_TOTEM_UPDATE", 4)
	H.ok(f.seen.fromBoolean, "secret false: SetAlphaFromBoolean")
	H.eq(f.seen.fromBoolean[1], false, "the secret goes as it is")
end)

H.test("a secret totem-down with no SetAlphaFromBoolean: hidden, no throw", function()
	local w, ns = World()
	Watch(ns)
	Drop(w, 1)
	local f = SpotOf(ns, 1)
	w.secret[true] = true
	rawset(f, "SetAlphaFromBoolean", nil)
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(f:IsShown(), false, "missing: hidden")
	Drop(w, 1)
	rawset(f, "SetAlphaFromBoolean", function() error("restricted") end)
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(f:IsShown(), false, "throws: hidden")
end)

H.test("no duration object: the plain start and length; secret ones: none", function()
	local w, ns = World()
	Watch(ns)
	w.env.GetTotemDuration = nil
	Drop(w, 2)
	local f = SpotOf(ns, 2)
	H.eq(f.seen.object, nil, "no object")
	H.ok(f.seen.cooldown, "plain start and length")
	H.eq(f.seen.cooldown[1], 100, "start")
	H.eq(f.seen.cooldown[2], 120, "length")
	Reset(ns)
	w.secret[100] = true
	w:fire("PLAYER_TOTEM_UPDATE", 2)
	H.eq(f.seen.cooldown, nil, "secret start: not used")
	H.eq(f.seen.cleared, true, "secret start: the time is cleared")
	H.eq(f:IsShown(), true, "the totem still shows")
	Reset(ns)
	w.secret[100], w.secret[120] = nil, true
	w:fire("PLAYER_TOTEM_UPDATE", 2)
	H.eq(f.seen.cooldown, nil, "secret length: not used")
	H.eq(f.seen.cleared, true, "secret length: the time is cleared")
end)

H.test("a secret false, then a plain true: the spot is back at full alpha", function()
	-- The game's alpha from a secret false stays on the frame, so a plain
	-- true must set it back, or the totem shows at alpha 0.
	local w, ns = World()
	Watch(ns)
	Drop(w, 3)
	local f = SpotOf(ns, 3)
	rawset(f, "SetAlphaFromBoolean", function(self, v, yes, no) self:SetAlpha((v and yes or no) / 255) end)
	w.totems[3].have = false
	w.secret[false] = true
	w:fire("PLAYER_TOTEM_UPDATE", 3)
	H.eq(f:GetAlpha(), 0, "secret false: the game hides it")
	w.secret[false] = nil
	Drop(w, 3)
	H.eq(f:IsShown(), true, "plain true: shown")
	H.eq(f:GetAlpha(), 1, "plain true: full alpha")
end)

H.test("a Cooldown that refuses the duration object: the plain time, no throw", function()
	local w, ns = World()
	Watch(ns)
	local f = SpotOf(ns, 2)
	rawset(f.cd, "SetCooldownFromDurationObject", function() error("bad object") end)
	H.ok(pcall(Drop, w, 2), "no throw")
	H.ok(f.seen.cooldown, "the plain start and length")
	H.eq(f.seen.cooldown[1], 100, "start")
	H.eq(f:IsShown(), true, "the totem shows")
end)

H.test("a Cooldown that refuses the plain time: cleared, no throw", function()
	local w, ns = World()
	Watch(ns)
	w.env.GetTotemDuration = nil
	local f = SpotOf(ns, 4)
	rawset(f.cd, "SetCooldown", function() error("bad time") end)
	H.ok(pcall(Drop, w, 4), "no throw")
	H.eq(f.seen.cleared, true, "the time is cleared")
	H.eq(f:IsShown(), true, "the totem shows")
end)

H.test("no duration object from the game, or a plain length of 0", function()
	local w, ns = World()
	Watch(ns)
	local f = SpotOf(ns, 1)
	w.totems[1] = { have = true, start = 100, duration = 120, icon = 1001 }
	w:fire("PLAYER_TOTEM_UPDATE", 1) -- GetTotemDuration answers nil
	H.eq(f.seen.object, nil, "nil: no object to the Cooldown")
	H.ok(f.seen.cooldown, "nil: the plain start and length")
	Reset(ns)
	w.totems[1].duration = 0
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(f.seen.cooldown, nil, "length 0: no time")
	H.eq(f.seen.cleared, true, "length 0: the time is cleared")
end)

H.test("no icon keeps the last one; an icon that throws still shows the totem", function()
	local w, ns = World()
	Watch(ns)
	local f = SpotOf(ns, 2)
	local calls = 0
	rawset(f.icon, "SetTexture", function(_, tex) calls = calls + 1; f.seen.icon = tex end)
	Drop(w, 2)
	H.eq(calls, 1, "an icon: set")
	w.totems[2].icon = nil
	w:fire("PLAYER_TOTEM_UPDATE", 2)
	H.eq(calls, 1, "no icon: not set")
	rawset(f.icon, "SetTexture", function() error("bad texture") end)
	H.ok(pcall(Drop, w, 2), "no throw")
	H.eq(f:IsShown(), true, "the totem shows")
end)

H.test("a throw shows nothing and throws nothing", function()
	local w, ns = World()
	Watch(ns)
	Drop(w, 1)
	local f = SpotOf(ns, 1)
	w.durationThrows = true
	Reset(ns)
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(f.seen.cooldown[1], 100, "GetTotemDuration throws: the plain time")
	H.eq(f:IsShown(), true, "GetTotemDuration throws: still shown")
	w.infoThrows = true
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(f:IsShown(), false, "GetTotemInfo throws: hidden")
	w.env.GetTotemInfo = nil
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(f:IsShown(), false, "no GetTotemInfo: hidden")
end)

H.test("the switch off hides the row and stops it; on brings it back", function()
	local w, ns = World()
	Watch(ns)
	Drop(w, 1)
	local f = SpotOf(ns, 1)
	w.env.HUDiniDB.showTotems = false
	ns.HUDini:Apply()
	H.eq(ns.GetModule("totems").enabled, false, "off")
	H.eq(f:IsShown(), false, "off: hidden")
	w:fire("PLAYER_TOTEM_UPDATE", 1)
	H.eq(f:IsShown(), false, "off: a totem update changes nothing")
	w.env.HUDiniDB.showTotems = true
	ns.HUDini:Apply()
	H.eq(f:IsShown(), true, "on again: the totem that is down shows")
end)

H.test("the row sits under the HUD's left end and follows the icon size", function()
	local w, ns = World()
	local hud = ns.HUDini
	local first, second = ns.TotemSpot(1), ns.TotemSpot(2)
	local point, to, toPoint = first:GetPoint(1)
	H.eq(point, "TOPLEFT", "its top left")
	H.eq(to, hud.mover, "against the box that covers the HUD")
	H.eq(toPoint, "BOTTOMLEFT", "at the HUD's bottom left")
	H.eq(first:GetWidth(), 30, "three quarters of a 40 icon")
	local _, _, _, x1 = first:GetPoint(1)
	local _, _, _, x2 = second:GetPoint(1)
	H.eq(x2 - x1, 33, "one spot and a gap apart")
	w.env.HUDiniDB.iconSize = 20
	hud:Layout()
	H.eq(first:GetWidth(), 15, "a new icon size")
	H.eq(first:GetNumPoints(), 1, "placed again, not added to")
end)
