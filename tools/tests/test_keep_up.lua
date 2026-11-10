-- The keep-up icon (Alerts.lua, alert 2) in a fight (TICK-0130). The icon
-- shows only in a fight, and a fight hides your auras from addons: a hidden
-- aura is not found by name, with no error (RequiresNonSecretAura,
-- SecretPredicatesDocumentation.lua:28-30, wow-ui-source forever 9dc84f0).
-- So "not found" must not read as "no seal": the keep-up list goes by what
-- HUDini last saw, as your buffs do (Auras.lua, TICK-0125).

local SOR, SOTC = 20154, 21082

-- A Paladin who knows two seals, with no aura on. w.auras[name] is the
-- aura's data; w.hidden hides every aura, as a fight does.
local function World(before, class, className, spells)
	local w = H.world()
	w.class, w.className = class or "PALADIN", className or "Paladin"
	spells = spells or { [SOR] = "Seal of Righteousness", [SOTC] = "Seal of the Crusader" }
	local ids = {}
	for id, name in pairs(spells) do ids[name] = id end
	local env = w.env
	w.auras, w.hidden = {}, false
	env.C_Spell.GetSpellName = function(id) return spells[id] end
	env.C_Spell.GetSpellInfo = function(n)
		local id = ids[n] or (spells[n] and n)
		if id then return { spellID = id, name = spells[id] } end
	end
	env.C_Spell.GetSpellTexture = function(id) return "tex" .. id end
	env.IsPlayerSpell = function(id) return spells[id] ~= nil end
	env.C_UnitAuras.GetAuraDataBySpellName = function(unit, name, filter)
		if unit ~= "player" or filter ~= "HELPFUL" then return nil end
		if w.hidden then return nil end
		return w.auras[name]
	end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.hidden end }
	if before then before(w) end
	w:loadAddon()
	w.ns.HUDini.spells = {}
	-- Make every alert icon, then keep the texture each one is given.
	w.ns.ShowAlertSamples(true)
	w.ns.ShowAlertSamples(false)
	for _, f in ipairs(w.frames) do
		if f.tex and f.edge then
			rawset(f.tex, "SetTexture", function(t, v) rawset(t, "shows", v) end)
		end
	end
	return w, w.ns, ids
end

-- The texture of the shown alert icon, or nil when none shows.
local function Shown(w)
	for _, f in ipairs(w.frames) do
		if f.tex and f.edge and f:IsShown() then return rawget(f.tex, "shows") end
	end
	return nil
end

local function Aura(w, name, left)
	w.auras[name] = { auraInstanceID = 9, expirationTime = w.time + left }
	w:fire("UNIT_AURA", "player")
end

local function NoAura(w, name)
	w.auras[name] = nil
	w:fire("UNIT_AURA", "player")
end

-- A fight hides your auras; its end shows them again.
local function Fight(w, on)
	w.combat, w.hidden = on, on
	w:fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
	w:runTimers()
end

H.test("a seal on before the fight: no keep-up icon in the fight while it is on", function()
	local w = World()
	Aura(w, "Seal of Righteousness", 30)
	H.eq(Shown(w), nil, "out of a fight: nothing")
	Fight(w, true)
	H.eq(Shown(w), nil, "the fight hides the seal: still on")
	w.time = w.time + 6
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), nil, "6 s on, 24 s left: still on")
end)

H.test("the seal's end time passes in the fight: the icon shows", function()
	local w = World()
	Aura(w, "Seal of Righteousness", 30)
	Fight(w, true)
	w.time = w.time + 31
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), "tex" .. SOR, "the seal is over: cast one")
	Fight(w, false)
	H.eq(Shown(w), nil, "the fight ends: the icon goes")
end)

H.test("no seal before the fight: the icon shows in the fight", function()
	local w = World()
	Aura(w, "Seal of Righteousness", 30)
	NoAura(w, "Seal of Righteousness")   -- it ran out
	Fight(w, true)
	H.eq(Shown(w), "tex" .. SOR, "seen off: cast one")
end)

H.test("any seal of the list counts", function()
	local w = World()
	Aura(w, "Seal of the Crusader", 30)
	Fight(w, true)
	H.eq(Shown(w), nil, "the second seal is on")
end)

H.test("a seal cast in the fight counts as on, with no aura event", function()
	local w = World()
	Fight(w, true)
	H.eq(Shown(w), "tex" .. SOR, "no seal: cast one")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", SOTC)
	H.eq(Shown(w), nil, "cast: on")
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), nil, "and the aura event keeps it on")
end)

H.test("a spell you cast that is not on the list changes nothing", function()
	local w = World(nil, nil, nil, { [SOR] = "Seal of Righteousness", [7] = "Holy Light" })
	Fight(w, true)
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 7)
	H.eq(Shown(w), "tex" .. SOR, "Holy Light is no seal")
end)

H.test("never seen, and the fight hides your auras: no icon", function()
	local w = World(function(w) w.hidden = true end)   -- hidden since login
	Fight(w, true)
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), nil, "never seen: not missing")
end)

H.test("not found while your auras are hidden out of a fight is not off", function()
	local w = World()
	Aura(w, "Seal of Righteousness", 30)
	w.hidden = true                      -- the gap around a fight (TICK-0125)
	w:fire("UNIT_AURA", "player")
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	w:runTimers()
	H.eq(Shown(w), nil, "the last answer, on")
end)

H.test("a seal picked by spell ID reads by its name", function()
	local w, ns = World()
	ns.ClassDB().keepUp = { SOR }
	Aura(w, "Seal of Righteousness", 30)
	Fight(w, true)
	H.eq(Shown(w), nil, "on")
	w.time = w.time + 31
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), "tex" .. SOR, "over: cast it")
end)

-- Review finding 2: with both of the Mage's list on, the one that ends
-- last keeps the list on.
H.test("two of the list on: the later end time counts", function()
	local IB, MS = 11426, 1463
	local w = World(nil, "MAGE", "Mage", { [IB] = "Ice Barrier", [MS] = "Mana Shield" })
	w.auras["Ice Barrier"] = { auraInstanceID = 1, expirationTime = w.time + 30 }
	w.auras["Mana Shield"] = { auraInstanceID = 2, expirationTime = w.time + 60 }
	w:fire("UNIT_AURA", "player")
	Fight(w, true)
	w.time = w.time + 31
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), nil, "Ice Barrier over, Mana Shield on: not missing")
	w.time = w.time + 30
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), "tex" .. IB, "both over: cast the first one you know")
end)

H.test("two of the list on, one with no end: it counts as on", function()
	local IB, MS = 11426, 1463
	local w = World(nil, "MAGE", "Mage", { [IB] = "Ice Barrier", [MS] = "Mana Shield" })
	w.auras["Ice Barrier"] = { auraInstanceID = 1, expirationTime = 0 }
	w.auras["Mana Shield"] = { auraInstanceID = 2, expirationTime = w.time + 60 }
	w:fire("UNIT_AURA", "player")
	Fight(w, true)
	w.time = w.time + 61
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), nil, "no end: still on")
end)

-- Every class with a keep-up list: its buff seen on before a fight is not
-- "missing" in the fight, and seen off it is.
for _, c in ipairs({ { "PALADIN", "Paladin" }, { "MAGE", "Mage" }, { "WARRIOR", "Warrior" } }) do
	H.test(c[2] .. ": a hidden keep-up buff is not missing", function()
		local probe = H.world()
		probe.class, probe.className = c[1], c[2]
		probe:loadAddon()
		local list = probe.ns.ClassDefault("keepUp")
		H.ok(type(list) == "table" and #list > 0, "the class file has a keep-up list")
		local spells = {}
		for i, name in ipairs(list) do spells[100 + i] = name end
		local w = World(nil, c[1], c[2], spells)
		Aura(w, list[1], 600)
		Fight(w, true)
		H.eq(Shown(w), nil, list[1] .. " on, hidden: not missing")
		Fight(w, false)
		NoAura(w, list[1])
		Fight(w, true)
		H.eq(Shown(w), "tex101", list[1] .. " seen off: cast it")
	end)
end

--------------------------------------------------------------------------------
-- A seal cast in the fight, on its button (TICK-0135)
--
-- The fight hides the aura, so the button cannot read a new seal's time.
-- A cast while your auras are hidden counts the buff's time from the cast,
-- with the length HUDini last read, and the keep-up memory gets that end
-- too.
--------------------------------------------------------------------------------

-- Seal of Righteousness on the grid's first icon. Its time is a fake that
-- keeps the end it counts down to. GetAuraDuration answers in a fight too
-- (it is not secret when your auras are hidden): it hands the end of the
-- aura with that instance ID, as the game's duration object does.
local function Grid(w)
	local ns = w.ns
	local buff = { shown = false }
	function buff:SetCooldown(start, length) self.ends = start + length end
	function buff:SetCooldownFromDurationObject(d) self.ends = d.ends end
	function buff:Clear() self.ends = nil end
	function buff:Show() self.shown = true end
	function buff:Hide() self.shown = false end
	w.env.C_UnitAuras.GetAuraDuration = function(unit, id)
		for _, data in pairs(w.auras) do
			if unit == "player" and data.auraInstanceID == id then return { ends = data.expirationTime } end
		end
	end
	ns.HUDini.spells[1] = { spellID = SOR }
	ns.HUDini.icons[1] = { buff = buff }
	return buff
end

-- The time the button shows, or nil when it shows none.
local function TimeLeft(w, buff)
	if not (buff.shown and buff.ends and buff.ends > w.time) then return nil end
	return buff.ends - w.time
end

-- A new seal: a new instance, 30 s from now. Hidden or not, the game has it.
local nextID = 100
local function Seal(w, name, length)
	nextID = nextID + 1
	w.auras[name] = { auraInstanceID = nextID, duration = length or 30, expirationTime = w.time + (length or 30) }
end

-- The cast, then its UNIT_AURA; or the other way round.
local function Cast(w, id, auraFirst)
	if auraFirst then w:fire("UNIT_AURA", "player") end
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
	if not auraFirst then w:fire("UNIT_AURA", "player") end
end

for _, auraFirst in ipairs({ false, true }) do
	local order = auraFirst and " (the aura event first)" or ""
	H.test("a seal cast in the fight shows its time on its button" .. order, function()
		local w = World()
		local buff = Grid(w)
		Seal(w, "Seal of Righteousness")
		w:fire("UNIT_AURA", "player")
		H.eq(TimeLeft(w, buff), 30, "out of a fight: the aura's own time")
		Fight(w, true)
		w.time = w.time + 20
		Seal(w, "Seal of Righteousness")    -- cast again in the fight
		Cast(w, SOR, auraFirst)
		w.time = w.time + 16
		w:fire("UNIT_AURA", "player")
		H.eq(TimeLeft(w, buff), 14, "16 s after the cast: 14 s left, as in the buff row")
		H.eq(Shown(w), nil, "no keep-up icon while the seal is on")
		w.time = w.time + 15
		w:fire("UNIT_AURA", "player")
		H.eq(TimeLeft(w, buff), nil, "the seal is over: no time")
		H.eq(Shown(w), "tex" .. SOR, "and the keep-up icon asks for a seal")
	end)
end

H.test("a seal cast in the fight with none before it: its time from the cast", function()
	local w = World()
	local buff = Grid(w)
	Seal(w, "Seal of Righteousness")
	w:fire("UNIT_AURA", "player")
	w.time = w.time + 40                 -- the seal ran out before the fight
	w.auras["Seal of Righteousness"] = nil
	w:fire("UNIT_AURA", "player")
	H.eq(TimeLeft(w, buff), nil, "no seal: no time")
	Fight(w, true)
	H.eq(Shown(w), "tex" .. SOR, "no seal in the fight: cast one")
	Seal(w, "Seal of Righteousness")
	Cast(w, SOR)
	H.eq(TimeLeft(w, buff), 30, "cast: 30 s")
	H.eq(Shown(w), nil, "and the keep-up icon goes")
end)

H.test("your auras read: the aura's own time wins over the cast's", function()
	local w = World()
	local buff = Grid(w)
	Seal(w, "Seal of Righteousness")
	w:fire("UNIT_AURA", "player")
	w.time = w.time + 5
	w.auras["Seal of Righteousness"].expirationTime = w.time + 27   -- the game's own end
	Cast(w, SOR, true)                   -- the cast's event last
	H.eq(TimeLeft(w, buff), 27, "readable: the time the game gives")
end)

H.test("a seal never read before the fight: no time, and on until the fight ends", function()
	local w = World()
	local buff = Grid(w)
	Fight(w, true)
	Seal(w, "Seal of Righteousness")
	Cast(w, SOR)
	H.eq(TimeLeft(w, buff), nil, "no length known: no time")
	w.time = w.time + 600
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), nil, "still counts as on, as before (TICK-0130)")
end)

H.test("Show active buff timers off: a cast in the fight puts no time on it", function()
	local w, ns = World()
	local buff = Grid(w)
	Seal(w, "Seal of Righteousness")
	w:fire("UNIT_AURA", "player")
	ns.HUDini.icons[1].buff.ends, buff.shown = nil, false
	w.env.HUDiniDB.showBuffTime = false
	Fight(w, true)
	Seal(w, "Seal of Righteousness")
	Cast(w, SOR, true)                   -- the cast's event last
	H.eq(TimeLeft(w, buff), nil, "off: no time")
end)

-- With two of the Mage's list on, a cast of the shorter one must not cut the
-- longer one's end.
H.test("a cast in the fight keeps a later end of the list", function()
	local IB, MS = 11426, 1463
	local w = World(nil, "MAGE", "Mage", { [IB] = "Ice Barrier", [MS] = "Mana Shield" })
	Seal(w, "Ice Barrier", 30)
	Seal(w, "Mana Shield", 60)
	w:fire("UNIT_AURA", "player")
	Fight(w, true)
	w.time = w.time + 10
	Seal(w, "Ice Barrier", 30)
	Cast(w, IB)                          -- Ice Barrier to +40, Mana Shield to +60
	w.time = w.time + 35
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), nil, "Ice Barrier over, Mana Shield on: not missing")
	w.time = w.time + 20
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), "tex" .. IB, "both over: cast one")
end)

H.test("a cast in the fight moves an earlier end of the list later", function()
	local IB, MS = 11426, 1463
	local w = World(nil, "MAGE", "Mage", { [IB] = "Ice Barrier", [MS] = "Mana Shield" })
	Seal(w, "Ice Barrier", 30)
	w:fire("UNIT_AURA", "player")
	Fight(w, true)
	w.time = w.time + 25
	Seal(w, "Ice Barrier", 30)
	Cast(w, IB)
	w.time = w.time + 20
	w:fire("UNIT_AURA", "player")
	H.eq(Shown(w), nil, "45 s on, the new Ice Barrier has 10 s left: on")
end)

H.test("a buff with no end, cast in the fight: on, not over at once", function()
	local IB, MS = 11426, 1463
	local w = World(nil, "MAGE", "Mage", { [IB] = "Ice Barrier", [MS] = "Mana Shield" })
	w.auras["Mana Shield"] = { auraInstanceID = 7, duration = 0, expirationTime = 0 }
	w:fire("UNIT_AURA", "player")
	w.auras["Mana Shield"] = nil
	w:fire("UNIT_AURA", "player")       -- seen off before the fight
	Fight(w, true)
	H.eq(Shown(w), "tex" .. IB, "off: cast one")
	w.auras["Mana Shield"] = { auraInstanceID = 8, duration = 0, expirationTime = 0 }
	Cast(w, MS)
	H.eq(Shown(w), nil, "cast: on, with no end")
end)

H.test("a secret length teaches nothing: a cast in the fight puts no new time on", function()
	local w = World(function(w)
		w.secret = {}
		w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	end)
	local buff = Grid(w)
	w.auras["Seal of Righteousness"] = { auraInstanceID = 50, duration = 29.5, expirationTime = w.time + 29.5 }
	w.secret[29.5] = true
	w:fire("UNIT_AURA", "player")
	Fight(w, true)
	w.time = w.time + 10
	Seal(w, "Seal of Righteousness")
	Cast(w, SOR)
	H.eq(TimeLeft(w, buff), 19.5, "no length read: the old time stays, not 30 s from the cast")
end)
