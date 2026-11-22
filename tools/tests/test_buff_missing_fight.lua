-- The buff-missing icon in a fight (TICK-0164). A learned buff you keep up
-- for a fight (Lightning Shield, under 30 minutes) shows the icon left of
-- your health bar while it is off in a fight. A fight hides your auras:
-- every read gives nil or throws (DK's probe, 2026-11-21). A read that will
-- not say never clears the icon.

-- A shaman with Lightning Shield on the grid, learned at 600 s.
-- w.auras[name]: the buff on you. w.inFight: your auras are hidden; then
-- the name lookup gives nil, or throws with w.throw.
local function World()
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_Spell.GetSpellName = function(id) return id == 324 and "Lightning Shield" or nil end
	env.C_Spell.GetSpellInfo = function(name)
		if name == "Lightning Shield" then return { spellID = 324, name = name } end
	end
	env.IsPlayerSpell = function(id) return id == 324 end
	env.CreateFrame = (function(make)
		return function(kind, ...)
			if kind == "AuraContainer" then error("Unknown frame type 'AuraContainer'") end
			return make(kind, ...)
		end
	end)(env.CreateFrame)
	local ns = w:loadAddon()
	w.auras = {}
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.inFight then
			if w.throw then error("Auras cannot be accessed when secret while tainted") end
			return nil
		end
		return w.auras[name]
	end
	env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
		if w.inFight then
			if w.throw then error("Auras cannot be accessed when secret while tainted") end
			return nil
		end
		local list = {}
		for _, data in pairs(w.auras) do list[#list + 1] = data end
		return list[i]
	end
	env.C_UnitAuras.GetAuraDuration = function() return nil end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.inFight == true end }
	local db = env.HUDiniDB
	db.warnOwnBuff, db.showHealth, db.showBuffTime = true, true, true
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	local hud = ns.HUDini
	hud.spells = { { spellID = 324, slot = 1, auraNames = { "Lightning Shield" } } }
	hud:GetIcon(1):Show()
	hud.body:Show()
	w.time = 100
	return w, ns
end

-- w.viewerReads: the game's buff viewer reads it too (AddViewer).
local function Shield(w)
	w.auras["Lightning Shield"] = { auraInstanceID = 77, spellId = 324, name = "Lightning Shield",
		duration = 600, expirationTime = w.time + 600, applications = 3 }
	if w.viewerReads then w.viewerReads(w) end
end

-- A fight starts as the game starts it: PLAYER_REGEN_DISABLED while your
-- auras still read and before the lockdown (Alerts.lua's fight-start
-- comment), the lockdown and the restriction just after it, then the
-- restriction's event, then a frame later. Returns the icon's spell ID at
-- each step.
local function StartFight(w, ns)
	local steps = {}
	w.combat = false
	w:fire("PLAYER_REGEN_DISABLED")
	w.combat = true
	steps[#steps + 1] = ns.missingBuffID
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
	steps[#steps + 1] = ns.missingBuffID
	w.inFight = true
	w:runTimers()
	steps[#steps + 1] = ns.missingBuffID
	return steps
end

local function EndFight(w)
	w.combat, w.inFight = false, false
	w:fire("PLAYER_REGEN_ENABLED")
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
	w:runTimers()
end

for _, throw in ipairs({ false, true }) do
	local how = throw and " (reads throw)" or " (reads give nil)"

	H.test("off at the fight start: the icon shows at every step and stays" .. how, function()
		local w, ns = World()
		w.throw = throw
		ns.UpdateIconAuras()
		H.eq(ns.missingBuffID, nil, "out of a fight: no icon")
		for i, id in ipairs(StartFight(w, ns)) do
			H.eq(id, 324, "fight start, step " .. i)
		end
		for i = 1, 5 do
			w.time = w.time + 1
			w:fire("UNIT_AURA", "player")
			H.eq(ns.missingBuffID, 324, "UNIT_AURA " .. i .. " in the fight")
		end
		w:fire("UNIT_AURA", "target")
		H.eq(ns.missingBuffID, 324, "a target UNIT_AURA")
	end)

	H.test("ten fights in a row without it: the icon in every one" .. how, function()
		local w, ns = World()
		w.throw = throw
		ns.UpdateIconAuras()
		for n = 1, 10 do
			StartFight(w, ns)
			w:fire("UNIT_AURA", "player")
			H.eq(ns.missingBuffID, 324, "fight " .. n)
			EndFight(w)
			H.eq(ns.missingBuffID, nil, "after fight " .. n)
			w.time = w.time + 30
		end
	end)

	H.test("on at the fight start: no icon" .. how, function()
		local w, ns = World()
		w.throw = throw
		Shield(w)
		ns.UpdateIconAuras()
		for i, id in ipairs(StartFight(w, ns)) do
			H.eq(id, nil, "fight start, step " .. i)
		end
		w:fire("UNIT_AURA", "player")
		H.eq(ns.missingBuffID, nil, "in the fight")
	end)
end

--------------------------------------------------------------------------------
-- The sign of a buff that ends in a fight (TICK-0168): the game's Cooldown
-- Manager. Its buff viewer has an item frame for each buff the player
-- tracks there; the game sets the frame's auraInstanceID while the buff is
-- on you (secret in a fight) and clears it to nil when the buff ends. The
-- game does it in its own UNIT_AURA, maybe after HUDini's (ViewerReads).
-- The icon's aura container (TICK-0159) is still made, for the red layer:
-- the game shows its slot's button while the buff is on and hides it when
-- the buff ends. In a fight the button is closed to HUDini.
--------------------------------------------------------------------------------

-- A secret aura ID: any compare or join throws.
local function SecretID(w)
	local id = setmetatable({}, {
		__eq = function() error("compared a secret") end,
		__tostring = function() error("joined a secret") end,
	})
	w.secret[id] = true
	return id
end

local ViewerReads

-- The game's buff viewer with Lightning Shield (spell 324) in its tracked
-- buffs. info: the item's cooldown info. w.viewer.shown: the viewer shows;
-- w.viewer.parentShown: its parent shows (false: Alt-Z).
local function AddViewer(w, info)
	local item = { cooldownID = 5, cooldownInfo = info or { spellID = 324, linkedSpellIDs = {} } }
	local viewer = { shown = true, parentShown = true, itemFramePool = {} }
	function viewer:IsShown() return self.shown end
	function viewer:IsVisible() return self.shown and self.parentShown end
	function viewer.itemFramePool.EnumerateActive()
		if w.viewerThrows then error("viewer broken") end
		return pairs({ [item] = true })
	end
	w.env.BuffIconCooldownViewer = viewer
	w.item, w.viewer = item, viewer
	w.viewerReads = ViewerReads
end

-- The game's viewer reads your auras: the ID is secret in a fight.
ViewerReads = function(w)
	if not w.item then return end
	local a = w.auras["Lightning Shield"]
	w.item.auraInstanceID = a and (w.inFight and SecretID(w) or a.auraInstanceID) or nil
	w.item.auraDataCached = a
end

-- The game shows or hides the slot's button.
local function Game(b, shown)
	b.__h.shown = shown
end

-- As World, with the game's container and its buff viewer (none with
-- noViewer). Switched on, the container shows its button (a frame later)
-- while Lightning Shield is on you; switched off, it hides it. w.slot: the
-- slot's button.
local function ContainerWorld(noViewer)
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	-- w.spellNames: more spell names, by ID.
	env.C_Spell.GetSpellName = function(id)
		if id == 324 then return "Lightning Shield" end
		return w.spellNames and w.spellNames[id] or nil
	end
	env.C_Spell.GetSpellInfo = function(name)
		if name == "Lightning Shield" then return { spellID = 324, name = name } end
	end
	env.IsPlayerSpell = function(id) return id == 324 end
	env.AnchorUtil = { FlowDirection = { Right = "RIGHT", Left = "LEFT", Up = "UP", Down = "DOWN" } }
	w.auras = {}
	local make = env.CreateFrame
	env.CreateFrame = function(kind, name, parent, template)
		if kind ~= "AuraContainer" then return make(kind, name, parent, template) end
		local f = w:Frame(name, parent)
		-- The icon slot's container (AddAuraSlot); the buff watches have their own.
		f.enabled = true
		rawset(f, "SetEnabled", function(_, v)
			f.enabled = v
			env.C_Timer.After(0, function()
				if w.slot then Game(w.slot, f.enabled and w.auras["Lightning Shield"] ~= nil) end
			end)
		end)
		rawset(f, "SetEditModePreviewEnabled", function() end)
		rawset(f, "SetUnit", function() end)
		rawset(f, "AddAuraGroup", function() end)
		rawset(f, "SetAuraSlotCandidateFilters", function() end)
		rawset(f, "AddAuraSlot", function(_, _, _, opts)
			local b = w:Frame(nil, f)
			b.__h.shown = false
			if w.noCover then rawset(b, "CreateTexture", function() error("denied") end) end
			opts.initializeFrame(b)
			-- Closed to HUDini while your auras are hidden.
			for _, m in ipairs({ "IsShown", "IsVisible", "GetAlpha", "GetParent", "HookScript" }) do
				local real = b[m]
				rawset(b, m, function(...)
					if w.inFight then error("access denied: auras are secret") end
					return real(...)
				end)
			end
			w.slot, w.box = b, f
			return b
		end)
		return f
	end
	local ns = w:loadAddon()
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.inFight then return nil end
		return w.auras[name]
	end
	env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
		if w.inFight then return nil end
		local list = {}
		for _, data in pairs(w.auras) do list[#list + 1] = data end
		return list[i]
	end
	env.C_UnitAuras.GetAuraDuration = function() return {} end
	env.C_UnitAuras.GetAuraApplicationDisplayCount = function() return "" end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.inFight == true end }
	local db = env.HUDiniDB
	db.warnOwnBuff, db.showHealth, db.showBuffTime = true, true, true
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	local hud = ns.HUDini
	hud.spells = { { spellID = 324, slot = 1, auraNames = { "Lightning Shield" } } }
	local f = hud:GetIcon(1)
	-- The icon's picture (Paint sets it; the fake texture keeps none).
	w.picture = 136051
	rawset(f.icon, "GetTexture", function() return w.picture end)
	f:SetPoint("CENTER", hud, "TOPLEFT", 20, -20)
	f:SetSize(36, 36)
	f:Show()
	hud:Show()
	hud.body:Show()
	rawset(f.buff, "SetCooldownFromDurationObject", function() end)
	rawset(f.buff, "SetCooldown", function() end)
	w.time = 100
	if not noViewer then AddViewer(w) end
	return w, ns
end

-- Lightning Shield on, read out of a fight (its ID is learned), then a
-- fight: the container switches on and, a frame later, shows its button.
local function ShieldedFight(noViewer)
	local w, ns = ContainerWorld(noViewer)
	Shield(w)
	ns.UpdateIconAuras()
	ns.UpdateBuffMissing()
	H.ok(ns.ClassDB().auraSpellIDs["Lightning Shield"][324], "the ID is read out of a fight")
	StartFight(w, ns)
	w:runTimers()
	w:runTimers()
	H.ok(w.slot, "the container has its slot")
	H.ok(w.box.enabled, "the container is on in the fight")
	H.ok(w.slot.__h.shown, "the game shows the button: the buff is on")
	H.eq(ns.missingBuffID, nil, "on at the fight start: no icon")
	return w, ns
end

-- The charges are used up: the game takes the buff off, hides the button
-- and sends UNIT_AURA. Its viewer reads the change in its own UNIT_AURA,
-- after HUDini's.
local function UsedUp(w)
	w.auras["Lightning Shield"] = nil
	if w.slot then Game(w.slot, false) end
	w:fire("UNIT_AURA", "player")
	ViewerReads(w)
end

-- Cast again in the fight: the buff is on, the button shows.
local function Again(w)
	Shield(w)
	if w.slot then Game(w.slot, true) end
	w:fire("UNIT_AURA", "player")
end

H.test("its charges used up in a fight: the icon shows a frame later, and goes when it is on again", function()
	local w, ns = ShieldedFight()
	w.time = w.time + 20
	UsedUp(w)
	H.eq(ns.missingBuffID, nil, "the viewer reads after HUDini's UNIT_AURA: not yet")
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "a frame later: the icon shows")
	H.ok(ns.leftIcons.ownBuff and ns.leftIcons.ownBuff:IsShown(), "the red icon by the health bar")
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "a UNIT_AURA keeps it")
	Again(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "on again: the icon goes")
	w.time = w.time + 599
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "on to its known length")
	EndFight(w)
	H.eq(ns.missingBuffID, nil, "after the fight: it reads on")
end)

H.test("the viewer's aura ID is secret in a fight: it counts as on, never compared", function()
	local w, ns = ShieldedFight()
	ViewerReads(w)
	H.ok(w.secret[w.item.auraInstanceID], "the ID is secret")
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "on: no icon, no error")
end)

H.test("a cast in the fight: the viewer says on, to the buff's known length", function()
	local w, ns = ShieldedFight()
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "used up")
	Again(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "on again")
	w.time = w.time + 601
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "the viewer still says on past the length")
	w.item.auraInstanceID, w.item.auraDataCached = nil, nil
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, 324, "and off when it says off")
end)

H.test("the viewer hidden, or none: HUDini keeps what it saw", function()
	local w, ns = ShieldedFight()
	w.viewer.shown = false
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "a hidden viewer goes stale: not read")
	local w2, ns2 = ShieldedFight(true)
	UsedUp(w2)
	w2:runTimers()
	H.eq(ns2.missingBuffID, nil, "no viewer: as before")
end)

H.test("a buff the viewer does not track: HUDini keeps what it saw", function()
	local w, ns = ContainerWorld(true)
	AddViewer(w, { spellID = 8042 })
	Shield(w)
	ns.UpdateIconAuras()
	StartFight(w, ns)
	w:runTimers()
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "another buff's item says nothing of this one")
end)

H.test("the viewer finds the buff by a linked spell, or by the game's cooldown info", function()
	local w, ns = ContainerWorld(true)
	AddViewer(w, { spellID = 8042, linkedSpellIDs = { 324 } })
	Shield(w)
	ns.UpdateIconAuras()
	StartFight(w, ns)
	w:runTimers()
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "a linked spell")
	local w2, ns2 = ContainerWorld(true)
	AddViewer(w2)
	w2.item.cooldownInfo = nil
	w2.env.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id)
		if id == 5 then return { spellID = 324 } end
	end }
	Shield(w2)
	ns2.UpdateIconAuras()
	StartFight(w2, ns2)
	w2:runTimers()
	UsedUp(w2)
	w2:runTimers()
	H.eq(ns2.missingBuffID, 324, "the game's cooldown info")
end)

H.test("two buff names, one not in the viewer: off only when each says off", function()
	local w, ns = ShieldedFight()
	ns.HUDini.spells[1].auraNames = { "Lightning Shield", "Water Shield" }
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "Water Shield has no item: it could be on")
end)

H.test("the viewer's parent hidden (Alt-Z): its frames go stale, HUDini keeps what it saw", function()
	local w, ns = ShieldedFight()
	w.viewer.parentShown = false
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "shown but not visible: not read")
end)

H.test("the buff from another caster: the viewer counts only yours, its off is not trusted", function()
	local w, ns = ContainerWorld()
	-- Another caster's Lightning Shield: on you, never in the viewer.
	w.viewerReads = nil
	Shield(w)
	ns.UpdateIconAuras()
	StartFight(w, ns)
	w:runTimers()
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "on from another caster: no icon")
end)

H.test("a recast in the frame the charges run out: the viewer's old off does not win", function()
	local w, ns = ShieldedFight()
	local sounds = {}
	w.env.PlaySound = function(kit) table.insert(sounds, kit) return true end
	ns.SetKeepUpSound(true)
	w.auras["Lightning Shield"] = nil
	Game(w.slot, false)
	w:fire("UNIT_AURA", "player")
	ViewerReads(w)
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 324)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "the cast wins: no icon")
	H.eq(#sounds, 0, "and no sound")
	Again(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "the new aura: still none")
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "the viewer said on again: its off counts")
end)

H.test("an item that links another buff: on for that one says nothing of this one", function()
	local w, ns = ContainerWorld(true)
	w.spellNames = { [8042] = "Flame Shock" }
	AddViewer(w, { spellID = 8042, linkedSpellIDs = { 324 } })
	Shield(w)
	ns.UpdateIconAuras()
	StartFight(w, ns)
	w:runTimers()
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "never seen on alone: its off is not trusted")
	-- Lightning Shield off; the item on for the other buff.
	local w2, ns2 = ShieldedFight()
	UsedUp(w2)
	w2:runTimers()
	H.eq(ns2.missingBuffID, 324, "used up")
	w2.spellNames = { [8042] = "Flame Shock" }
	w2.item.cooldownInfo.linkedSpellIDs = { 8042 }
	w2:fire("SPELLS_CHANGED")
	w2.item.auraInstanceID = 99
	w2:fire("UNIT_AURA", "player")
	w2:runTimers()
	H.eq(ns2.missingBuffID, 324, "on for Flame Shock: the icon stays")
end)

H.test("an item name that does not read is not kept: a later read gets it whole", function()
	local w, ns = ContainerWorld(true)
	AddViewer(w, { spellID = 324, linkedSpellIDs = { 8042 } })
	Shield(w)
	ns.UpdateIconAuras()
	StartFight(w, ns)
	w:runTimers()
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "used up")
	-- Flame Shock's name reads now; the item is on for it.
	w.spellNames = { [8042] = "Flame Shock" }
	w.item.auraInstanceID = 99
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "the item is two buffs: its on says nothing")
end)

H.test("your auras hidden between fights: the check a frame later reads the viewer too", function()
	local w, ns = ContainerWorld()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 3600 }
	Shield(w)
	-- A long buff: missing out of a fight too.
	local a = w.auras["Lightning Shield"]
	a.duration, a.expirationTime = 3600, w.time + 3600
	ns.UpdateIconAuras()
	w.inFight = true
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
	w:runTimers()
	ns.UpdateBuffMissing()
	H.eq(ns.missingBuffID, nil, "on")
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "no fight, auras hidden: the icon a frame later")
end)

H.test("your auras hide with no event, and the first aura change is the end: the icon", function()
	local w, ns = ContainerWorld()
	Shield(w)
	ns.UpdateIconAuras()
	-- The fight starts; your auras still read plain a frame later.
	w.combat = false
	w:fire("PLAYER_REGEN_DISABLED")
	w.combat = true
	w:runTimers()
	-- They hide later, with no event. The charges run out; the game's
	-- viewer reads it before HUDini's UNIT_AURA.
	w.inFight = true
	w.auras["Lightning Shield"] = nil
	ViewerReads(w)
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "the viewer said on at the plain read: its off counts")
end)

H.test("a viewer that throws: no error, HUDini keeps what it saw", function()
	local w, ns = ShieldedFight()
	w.viewerThrows = true
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "kept")
end)

H.test("the old slot probe is cleared at login", function()
	local w = ContainerWorld()
	w.env.HUDiniDB.slotProbe = { calls = 0 }
	w:fire("PLAYER_ENTERING_WORLD", false, true)
	H.eq(w.env.HUDiniDB.slotProbe, nil, "gone")
end)

--------------------------------------------------------------------------------
-- The fight's end (TICK-0168): the icon and the sound came for a moment as
-- the fight ended. ns.InCombat() runs on past PLAYER_REGEN_ENABLED, and your
-- auras read again while it is true.
--------------------------------------------------------------------------------

H.test("the fight's end: a combat flag that runs on shows no icon and plays no sound", function()
	local w, ns = World()
	local sounds = {}
	w.env.PlaySound = function(kit) table.insert(sounds, kit) return true end
	ns.SetKeepUpSound(true)
	Shield(w)
	ns.UpdateIconAuras()
	StartFight(w, ns)
	w.auras["Lightning Shield"] = nil
	-- The lockdown ends and your auras read; then the combat flag is on a
	-- moment more.
	w.combat, w.inFight = false, false
	w:fire("PLAYER_REGEN_ENABLED")
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
	H.eq(ns.missingBuffID, nil, "out of the fight: no icon")
	w.combat = true
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "after PLAYER_REGEN_ENABLED: no icon")
	H.eq(#sounds, 0, "and no sound")
	-- The next fight counts again.
	StartFight(w, ns)
	H.eq(ns.missingBuffID, 324, "the next fight: the icon")
end)

H.test("the fight's end, in a fight whose auras never hide: a combat flag that runs on shows no icon", function()
	local w, ns = World()
	Shield(w)
	ns.UpdateIconAuras()
	w:fire("PLAYER_REGEN_DISABLED")
	w.combat = true
	w:runTimers()
	w.auras["Lightning Shield"] = nil
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(ns.missingBuffID, nil, "out of the fight: no icon")
	w.combat = true
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "the combat flag a moment more: no icon")
end)

H.test("the fight's end: a combat flag that runs on takes the red edge down too", function()
	local w, ns = ShieldedFight()
	local under = ns.HUDini:GetIcon(1).auraBox.under
	UsedUp(w)
	w:runTimers()
	H.eq(under:IsShown(), true, "up in the fight")
	-- The lockdown ends; your auras are still hidden, the flag still on.
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.eq(under:IsShown(), false, "after PLAYER_REGEN_ENABLED: down, as the icon")
	H.eq(ns.missingBuffID, nil, "no icon")
end)

H.test("the fight's end: your auras read again before PLAYER_REGEN_ENABLED, the icon goes", function()
	local w, ns = ShieldedFight()
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "used up in the fight")
	-- The restriction ends while the lockdown is still on.
	w.inFight = false
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "the fight ends: no icon")
end)

H.test("a fight whose auras never hide: a plain read in it counts", function()
	local w, ns = World()
	ns.UpdateIconAuras()
	w:fire("PLAYER_REGEN_DISABLED")
	w.combat = true
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "off in the fight, auras plain: the icon")
end)

--------------------------------------------------------------------------------
-- The red layer under the slot's button (TICK-0168, option B). The game's
-- button covers it while the buff is on and hides when the buff ends, so
-- the layer shows through with no read. HUDini only puts it up or down.
--------------------------------------------------------------------------------

local function Under(ns)
	local s = ns.HUDini:GetIcon(1).auraBox
	return s.under, s
end

H.test("the red layer sits under the button while the container is on in a fight", function()
	local w, ns = ShieldedFight()
	local under, s = Under(ns)
	local f = ns.HUDini:GetIcon(1)
	H.ok(under, "the container has its red layer")
	H.eq(under:IsShown(), true, "up in the fight, under the button")
	H.ok(under:GetFrameLevel() > f.cd:GetFrameLevel(), "above the icon's cooldown")
	H.ok(under:GetFrameLevel() < f.buff:GetFrameLevel(), "below the icon's own buff time")
	H.ok(under:GetFrameLevel() < f.glow:GetFrameLevel(), "below the proc glow")
	H.ok(under:GetFrameLevel() < s.box:GetFrameLevel(), "below the game's button")
	H.eq(#s.cover, 4, "the button has its cover: one strip for each side")
	H.eq(s.covered, true, "the cover took a picture")
	H.eq(s.coverTex, 136051, "the icon's own picture")
	H.eq(under:GetWidth(), 36, "the icon's size")
	UsedUp(w)
	w:runTimers()
	H.eq(under:IsShown(), true, "the buff ends: it stays up, and the hidden button shows it")
	w.env.HUDiniDB.showBuffTime = false
	ns.UpdateIconAuras()
	H.eq(under:IsShown(), false, "buff time off: the container goes off, and so does the layer")
	w.env.HUDiniDB.showBuffTime = true
	ns.UpdateIconAuras()
	H.eq(under:IsShown(), true, "on again")
	EndFight(w)
	H.eq(under:IsShown(), false, "after the fight: the container is off, no layer")
end)

H.test("the red layer follows the body's alpha", function()
	local _, ns = ShieldedFight()
	ns.HUDini.body:SetAlpha(0.5)
	H.eq(Under(ns).__h.alpha, 0.5, "the body's alpha")
end)

H.test("no red layer with the red icon off, for a buff not learned, or with no read ID", function()
	local w, ns = ShieldedFight()
	local under = Under(ns)
	local db = ns.ClassDB()
	ns.HUDini.body:Show()
	w.env.HUDiniDB.warnOwnBuff = false
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), false, "the red icon off in the options")
	w.env.HUDiniDB.warnOwnBuff = true
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), true, "on again")
	w.env.HUDiniDB.showHealth = false
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), false, "no health bar: no red icon")
	w.env.HUDiniDB.showHealth = true
	db.buffSpells = {}
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), false, "not a learned buff")
	db.buffSpells = { ["Lightning Shield"] = 600 }
	db.auraSpellIDs = {}
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), false, "the slot has no read ID: the button could stay hidden with the buff on")
end)

H.test("your auras hidden out of a fight: a short buff gives no red layer, a long one does", function()
	local w, ns = ShieldedFight()
	local under = Under(ns)
	w.combat = false -- a keystone between pulls: out of a fight, auras still hidden
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), false, "600 s: missing only in a fight")
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 3600 }
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), true, "3600 s: missing out of a fight too")
end)

H.test("a red layer that cannot be checked goes down and throws nothing", function()
	local _, ns = ShieldedFight()
	local under = Under(ns)
	local classDB = ns.ClassDB
	ns.ClassDB = function() error("broken") end
	pcall(ns.UpdateIconAuras)
	ns.ClassDB = classDB
	H.eq(under:IsShown(), false, "down")
end)

-- Fight again, as ShieldedFight does: the container on, the button shown.
local function FightAgain(w, ns)
	Shield(w)
	ns.UpdateIconAuras()
	StartFight(w, ns)
	w:runTimers()
	w:runTimers()
end

H.test("a new picture on the icon in a fight keeps the red edge down until a paint out of one", function()
	local w, ns = ShieldedFight()
	local under, s = Under(ns)
	w.picture = 135824 -- a Bar 1 page change: the cover keeps the old picture
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), false, "the cover would not match: down")
	ns.HUDini:Paint()
	H.eq(s.coverTex, 136051, "no copy in a fight: the button is closed")
	w.combat = false -- between keystone pulls: auras still hidden, no lockdown
	ns.HUDini:Paint()
	ns.HUDini.spells[1].col, ns.HUDini.spells[1].row = 0, 0
	ns.HUDini:Layout()
	H.eq(s.coverTex, 136051, "no copy while your auras are hidden, by a paint or a layout")
	EndFight(w)
	ns.HUDini:Paint()
	H.eq(s.coverTex, 135824, "after the fight the paint copies it, with no other check")
	FightAgain(w, ns)
	H.eq(under:IsShown(), true, "the next fight: up")
end)

H.test("a cover is written only for a new picture or size", function()
	local w, ns = ShieldedFight()
	local _, s = Under(ns)
	EndFight(w)
	local writes = 0
	rawset(s.cover[1], "SetTexture", function() writes = writes + 1 end)
	ns.HUDini:Paint()
	ns.UpdateBuffMissing()
	H.eq(writes, 0, "the same picture: not written again")
	w.picture = 135824
	ns.HUDini:Paint()
	H.eq(writes, 1, "a new picture: written once")
end)

H.test("a cover that fails to take the picture keeps the red edge down", function()
	local w, ns = ShieldedFight()
	local under, s = Under(ns)
	EndFight(w)
	rawset(s.cover[3], "SetTexture", function() error("denied") end)
	w.picture = 135824
	ns.HUDini:Paint()
	H.eq(s.covered, false, "noted as not covered")
	FightAgain(w, ns)
	H.eq(under:IsShown(), false, "down: part of the cover has the old picture")
end)

H.test("the cover shows only on an icon whose red edge a fight could put up", function()
	local w, ns = ShieldedFight()
	local under, s = Under(ns)
	H.eq(s.coverOn, true, "the red icon on, a learned buff: the cover is on")
	H.eq(s.cover[1].__h.alpha, 1, "and seen")
	EndFight(w)
	w.env.HUDiniDB.warnOwnBuff = false
	ns.UpdateBuffMissing()
	H.eq(s.coverOn, false, "the red icon off: the cover goes off")
	for i = 1, 4 do H.eq(s.cover[i].__h.alpha, 0, "strip " .. i .. " not seen") end
	FightAgain(w, ns)
	w.env.HUDiniDB.warnOwnBuff = true -- turned on in the fight: the cover cannot change
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), false, "no red edge with the cover off")
	EndFight(w)
	ns.UpdateBuffMissing()
	H.eq(s.coverOn, true, "on again after the fight")
	w.auras["Lightning Shield"] = nil -- on you, it would be learned again
	ns.ClassDB().buffSpells = {}
	ns.UpdateBuffMissing()
	H.eq(s.coverOn, false, "a buff not learned: off")
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 600 }
	ns.ClassDB().auraSpellIDs = {}
	ns.UpdateBuffMissing()
	H.eq(s.coverOn, false, "no read ID for the slot: off")
end)

H.test("a cover that fails to switch off is switched off at the next check", function()
	local w, ns = ShieldedFight()
	local _, s = Under(ns)
	EndFight(w)
	local real, fails = s.cover[2].SetAlpha, 1
	rawset(s.cover[2], "SetAlpha", function(self, a)
		if fails > 0 then fails = fails - 1 error("denied") end
		return real(self, a)
	end)
	w.env.HUDiniDB.warnOwnBuff = false
	ns.UpdateBuffMissing()
	H.ok(not s.coverOn, "not on")
	H.eq(s.cover[2].__h.alpha, 1, "the strip kept alpha 1")
	ns.UpdateBuffMissing()
	for i = 1, 4 do H.eq(s.cover[i].__h.alpha, 0, "strip " .. i .. " off at the next check") end
end)

H.test("a cover made while your auras are hidden stays off", function()
	local w, ns = ContainerWorld()
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true } } -- read in an earlier session
	w.inFight = true -- between keystone pulls: no lockdown, auras hidden
	ns.UpdateIconAuras()
	local _, s = Under(ns)
	H.ok(s.cover, "the container and its cover are made")
	for i = 1, 4 do H.eq(s.cover[i].__h.alpha, 0, "strip " .. i .. " not seen") end
	H.ok(not s.coverOn, "not on")
end)

H.test("a cover that fails to switch keeps the red edge down", function()
	local w, ns = ShieldedFight()
	local under, s = Under(ns)
	EndFight(w)
	w.env.HUDiniDB.warnOwnBuff = false
	ns.UpdateBuffMissing()
	rawset(s.cover[2], "SetAlpha", function() error("denied") end)
	w.env.HUDiniDB.warnOwnBuff = true
	ns.UpdateBuffMissing()
	H.ok(not s.coverOn, "not on")
	FightAgain(w, ns)
	H.eq(under:IsShown(), false, "down")
end)

H.test("an icon moved by a layout in a fight takes the red edge down", function()
	local w, ns = ShieldedFight()
	local under, s = Under(ns)
	local f = ns.HUDini:GetIcon(1)
	ns.HUDini.spells[1].col, ns.HUDini.spells[1].row = 1, 0 -- one column on
	ns.HUDini:Layout()
	local _, _, _, x = f:GetPoint(1)
	H.ok(x ~= 20, "the layout moved the icon")
	H.eq(under:IsShown(), false, "the edge cannot follow: down")
	ns.UpdateBuffMissing()
	H.eq(under:IsShown(), false, "and stays down in the fight")
	H.eq(s.underPlaced, false, "until a layout out of a fight")
	w.combat = false
	ns.HUDini:Layout()
	H.eq(s.underPlaced, true, "placed again out of a fight")
end)

H.test("a switch off that fails keeps no red edge", function()
	local w, ns = ShieldedFight()
	local under, s = Under(ns)
	rawset(w.box, "SetEnabled", function() error("denied") end)
	w.env.HUDiniDB.showBuffTime = false
	ns.UpdateIconAuras()
	H.eq(s.on, true, "the container stays on")
	H.eq(under:IsShown(), false, "the red edge goes down all the same")
end)

H.test("a button that takes no cover gives no red edge", function()
	local w, ns = ContainerWorld()
	w.noCover = true
	Shield(w)
	ns.UpdateIconAuras()
	StartFight(w, ns)
	w:runTimers()
	w:runTimers()
	local under, s = Under(ns)
	H.eq(s.cover, nil, "no cover")
	H.ok(w.box.enabled, "the container still works")
	UsedUp(w)
	w:runTimers()
	H.eq(under:IsShown(), false, "no red edge: it would show with the buff on")
end)

--------------------------------------------------------------------------------
-- A sound when a red icon turns on in a fight (TICK-0163). One sound for each
-- time it goes missing, none out of a fight, none with the setting off, and
-- none for a read that will not say.
--------------------------------------------------------------------------------

local MISSING_SOUND = 8959 -- the raid warning, the default (TICK-0167)

-- Logs each PlaySound in w.sounds and turns the setting on (on ~= false).
local function Sounds(w, ns, on)
	w.sounds = {}
	w.env.PlaySound = function(kit) table.insert(w.sounds, kit) return true end
	if on ~= false then H.eq(ns.SetKeepUpSound(true), true, "the setting changes") end
end

local function Heard(w)
	local n = 0
	for _, kit in ipairs(w.sounds) do
		H.eq(kit, MISSING_SOUND, "Synth Error, not the cooldown bell")
		n = n + 1
	end
	return n
end

H.test("sound: the setting is saved per class, off by default", function()
	local w, ns = World()
	H.eq(ns.GetKeepUpSound(), false, "off by default")
	H.eq(ns.SetKeepUpSound(true), true, "on: changed")
	H.eq(ns.SetKeepUpSound(true), false, "on again: no change")
	H.eq(w.env.HUDiniDB.classes[ns.ClassToken()].keepUpSound, true, "saved for the class")
	H.eq(ns.GetKeepUpSound(), true, "reads on")
	H.eq(ns.SetKeepUpSound(false), true, "off: changed")
	H.eq(w.env.HUDiniDB.classes[ns.ClassToken()].keepUpSound, false, "off saves false, so it sticks (TICK-0181)")
	local db = w.env.HUDiniDB
	w.env.HUDiniDB = nil
	H.eq(ns.GetKeepUpSound(), false, "no saved settings yet: off")
	H.eq(ns.SetKeepUpSound(true), false, "and no change")
	w.env.HUDiniDB = db
end)

for _, throw in ipairs({ false, true }) do
	local how = throw and " (reads throw)" or " (reads give nil)"

	H.test("sound: off at the fight start, heard once" .. how, function()
		local w, ns = World()
		w.throw = throw
		Sounds(w, ns)
		ns.UpdateIconAuras()
		ns.UpdateAlerts()
		H.eq(Heard(w), 0, "out of a fight: no sound")
		StartFight(w, ns)
		w:fire("UNIT_AURA", "player")
		w:runTimers()
		w:fire("UNIT_AURA", "player")
		w:runTimers()
		H.eq(Heard(w), 1, "one sound for the fight, not one per UNIT_AURA")
		EndFight(w)
		H.eq(Heard(w), 1, "the fight ends: no sound")
		StartFight(w, ns)
		w:runTimers()
		H.eq(Heard(w), 2, "the next fight without it: heard again")
	end)

	H.test("sound: on at the fight start, or the setting off, no sound" .. how, function()
		local w, ns = World()
		w.throw = throw
		Sounds(w, ns)
		Shield(w)
		ns.UpdateIconAuras()
		StartFight(w, ns)
		w:fire("UNIT_AURA", "player")
		w:runTimers()
		H.eq(Heard(w), 0, "the shield on, then hidden: no sound")
		local w2, ns2 = World()
		w2.throw = throw
		Sounds(w2, ns2, false)
		ns2.UpdateIconAuras()
		StartFight(w2, ns2)
		w2:runTimers()
		H.eq(ns2.missingBuffID, 324, "the icon shows")
		H.eq(Heard(w2), 0, "the setting off: no sound")
	end)
end

H.test("sound: the last charge goes in a fight, heard; on again, then gone again, heard again", function()
	local w, ns = ShieldedFight()
	Sounds(w, ns)
	UsedUp(w)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "the icon shows")
	H.eq(Heard(w), 1, "the charges used up: heard")
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(Heard(w), 1, "a UNIT_AURA: no second sound")
	Again(w)
	w:runTimers()
	H.eq(Heard(w), 1, "cast again: no sound")
	UsedUp(w)
	w:runTimers()
	H.eq(Heard(w), 2, "used up again: heard again")
end)

-- As World, with Water Shield on the class keep-up list ("Combat buff");
-- keepUpOff() says it is surely off.
local function KeepUpWorld(keepUpOff)
	local w, ns = World()
	local env = w.env
	local info = env.C_Spell.GetSpellInfo
	env.C_Spell.GetSpellInfo = function(name)
		if name == "Water Shield" then return { spellID = 52127, name = name } end
		return info(name)
	end
	env.IsPlayerSpell = function(id) return id == 324 or id == 52127 end
	local value = ns.ClassValue
	ns.ClassValue = function(key, ...)
		if key == "keepUp" then return { "Water Shield" } end
		return value(key, ...)
	end
	ns.KeepUpState = function() return not keepUpOff() end
	return w, ns
end

H.test("sound: the keep-up icon alone, heard once", function()
	local w, ns = KeepUpWorld(function() return true end)
	Shield(w)
	Sounds(w, ns)
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	H.eq(Heard(w), 0, "out of a fight: no sound")
	StartFight(w, ns)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "Lightning Shield is on")
	H.eq(Heard(w), 1, "Water Shield off in the fight: heard")
	w:fire("UNIT_AURA", "player")
	w:runTimers()
	H.eq(Heard(w), 1, "once")
end)

H.test("sound: both red icons on at once, heard once", function()
	local keepUpOff = false
	local w, ns = KeepUpWorld(function() return keepUpOff end)
	Sounds(w, ns)
	ns.UpdateIconAuras()
	keepUpOff = true
	StartFight(w, ns)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "the own buff icon shows")
	H.eq(Heard(w), 1, "the keep-up icon too: one sound")
	keepUpOff = false
	ns.UpdateAlerts()
	H.eq(Heard(w), 1, "one icon goes, the other stays: no sound")
	keepUpOff = true
	ns.UpdateAlerts()
	H.eq(Heard(w), 1, "it comes back while the other is still on: no sound")
end)

H.test("sound: a long buff's icon out of a fight is silent; the fight start sounds", function()
	local w, ns = World()
	ns.ClassDB().buffSpells = { ["Lightning Shield"] = 3600 }
	Sounds(w, ns)
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	H.eq(ns.missingBuffID, 324, "an hour-long buff: the icon shows out of a fight")
	H.eq(Heard(w), 0, "but no sound")
	StartFight(w, ns)
	w:runTimers()
	H.eq(Heard(w), 1, "the fight starts with it off: heard")
end)

-- TICK-0167 (D-043): the player picks the buff-missing sound. keepUpSound
-- saved: nil or false off, true the default (TICK-0163 saves), a key.
local function FightStart(w, ns)
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	StartFight(w, ns)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "off at the fight start")
end

H.test("sound: the picked buff sound plays; an old save of true plays the default", function()
	local w, ns = World()
	Sounds(w, ns, false)
	local db = ns.ClassDB()
	H.eq(ns.GetKeepUpSoundChoice(), "off", "off by default")
	H.eq(ns.SetKeepUpSound("whisper"), true, "picking a sound turns it on")
	H.eq(ns.SetKeepUpSound("whisper"), false, "same again: no change")
	H.eq(db.keepUpSound, "whisper", "saved per class")
	H.eq(ns.GetKeepUpSound(), true, "on, for the old check box")
	FightStart(w, ns)
	H.eq(table.concat(w.sounds, " "), "3081", "the whisper tone")

	local w2, ns2 = World()
	Sounds(w2, ns2, false)
	ns2.ClassDB().keepUpSound = true
	H.eq(ns2.GetKeepUpSoundChoice(), "raidWarning", "true: the default")
	FightStart(w2, ns2)
	H.eq(table.concat(w2.sounds, " "), tostring(MISSING_SOUND), "the raid warning")
end)

H.test("sound: the buff sound choice: off, a key, true keeps the key", function()
	local w, ns = World()
	local db = ns.ClassDB()
	H.eq(ns.SetKeepUpSound("nope"), false, "not in the list: no change")
	H.eq(db.keepUpSound, nil, "nothing saved")
	ns.SetKeepUpSound("coins")
	H.eq(ns.SetKeepUpSound(true), false, "the old check box on: the pick stays")
	H.eq(db.keepUpSound, "coins")
	H.eq(ns.SetKeepUpSound("off"), true, "off")
	H.eq(db.keepUpSound, false, "off saves false (TICK-0181)")
	H.eq(ns.GetKeepUpSound(), false)
	H.eq(ns.SetKeepUpSound(true), true, "on again")
	H.eq(ns.GetKeepUpSoundChoice(), "raidWarning", "the default")
	H.eq(ns.SetKeepUpSound("raidWarning"), false, "the default is the same as true")
	ns.SetKeepUpSound(false)
	H.eq(db.keepUpSound, false, "false: off")
	db.keepUpSound = "synthError" -- a key a later build dropped
	H.eq(ns.GetKeepUpSoundChoice(), "raidWarning", "on, with the default")
end)

-- WoW Forever's PlaySound returns nothing for a kit its data lacks.
H.test("sound: a buff sound the client cannot play plays the raid warning", function()
	local w, ns = World()
	Sounds(w, ns, false)
	ns.SetKeepUpSound("bossEmote")
	w.env.PlaySound = function(kit)
		table.insert(w.sounds, kit)
		if kit ~= 12197 then return true end
	end
	FightStart(w, ns)
	H.eq(table.concat(w.sounds, " "), "12197 " .. MISSING_SOUND, "the boss emote, then the raid warning")
end)

-- TICK-0165: the keep-up icon as the game runs it, with no stub. As World,
-- with Water Shield on the class keep-up list ("Combat buff").
local function RealKeepUpWorld()
	local w, ns = World()
	local env = w.env
	local info = env.C_Spell.GetSpellInfo
	env.C_Spell.GetSpellInfo = function(name)
		if name == "Water Shield" then return { spellID = 52127, name = name } end
		return info(name)
	end
	env.IsPlayerSpell = function(id) return id == 324 or id == 52127 end
	local value = ns.ClassValue
	ns.ClassValue = function(key, ...)
		if key == "keepUp" then return { "Water Shield" } end
		return value(key, ...)
	end
	return w, ns
end

-- In a fight the keep-up icon sits right of nothing: its right edge on the
-- health bar's left edge (Alerts.lua, left icons). Lightning Shield is on in
-- these tests, so no other icon takes that place.
local function KeepUpShown(w, ns)
	local bar = ns.GetBar("health")
	for _, f in ipairs(w.frames) do
		if f:IsShown() then
			local point, to, rel = f:GetPoint(1)
			if point == "RIGHT" and to == bar and rel == "LEFT" then return true end
		end
	end
	return false
end

H.test("the fight start: the keep-up icon shows a frame after PLAYER_REGEN_DISABLED", function()
	local w, ns = RealKeepUpWorld()
	Shield(w)
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	H.eq(KeepUpShown(w, ns), false, "out of a fight: no icon")
	-- The game fires the event before the lockdown starts.
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(KeepUpShown(w, ns), false, "at the event: not a fight yet")
	w.combat, w.inFight = true, true
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "Lightning Shield is on")
	H.eq(KeepUpShown(w, ns), true, "a frame later: the fight, and Water Shield is off")
end)

H.test("a Combat buff seen on runs out in a fight: the keep-up icon shows", function()
	local w, ns = RealKeepUpWorld()
	Shield(w)
	w.auras["Water Shield"] = { auraInstanceID = 78, spellId = 52127, name = "Water Shield",
		duration = 60, expirationTime = w.time + 60, applications = 3 }
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	StartFight(w, ns)
	w:runTimers()
	H.eq(KeepUpShown(w, ns), false, "seen on before the fight: on while it lasts")
	w.time = w.time + 30
	ns.UpdateAlerts()
	H.eq(KeepUpShown(w, ns), false, "half way: still on")
	w.time = w.time + 31
	ns.UpdateAlerts()
	H.eq(ns.missingBuffID, nil, "Lightning Shield is still on")
	H.eq(KeepUpShown(w, ns), true, "past its end: off, the icon shows")
end)

-- TICK-0166: the shown red icons left of the health bar, counted along the
-- chain SlotLeft makes (each shown icon's right edge on the last one's
-- left edge, the first on the bar).
local function LeftShown(w, ns)
	local after, n = ns.GetBar("health"), 0
	repeat
		local next
		for _, f in ipairs(w.frames) do
			if f:IsShown() and f ~= after then
				local point, to, rel = f:GetPoint(1)
				if point == "RIGHT" and to == after and rel == "LEFT" then next = f break end
			end
		end
		if next then n, after = n + 1, next end
	until not next
	return n
end

-- DK's Shaman (TICK-0166): Lightning Shield picked as the Combat buff, and
-- learned as your buff (600 s) too.
local function PickedShieldWorld(pick)
	local w, ns = World()
	local value = ns.ClassValue
	ns.ClassValue = function(key, ...)
		if key == "keepUp" then return { pick or "Lightning Shield" } end
		return value(key, ...)
	end
	return w, ns
end

-- Which red icons show: "keepUp", "ownBuff", or both joined by "+".
local function Which(ns)
	local on = {}
	for _, key in ipairs({ "keepUp", "ownBuff" }) do
		local icon = ns.leftIcons[key]
		if icon and icon:IsShown() then on[#on + 1] = key end
	end
	return table.concat(on, "+")
end

H.test("the Combat buff is a buff you keep up too: it ends in a fight, your buff's icon alone, one sound", function()
	local w, ns = PickedShieldWorld()
	Shield(w)
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	Sounds(w, ns)
	StartFight(w, ns)
	w:runTimers()
	H.eq(LeftShown(w, ns), 0, "on in the fight: no icon")
	w.time = w.time + 601
	ns.UpdateBuffMissing()
	ns.UpdateAlerts()
	H.eq(ns.missingBuffID, 324, "past its 10 minutes: your buff's icon shows")
	H.eq(Which(ns), "ownBuff", "your buff's icon, not the Combat buff icon")
	H.eq(LeftShown(w, ns), 1, "one icon, not two")
	H.eq(Heard(w), 1, "one sound")
	-- The other order: Alerts.lua looks first when it runs out (both look
	-- on UNIT_AURA), while missingBuffID is still from before.
	local w2, ns2 = PickedShieldWorld()
	Shield(w2)
	ns2.UpdateIconAuras()
	ns2.UpdateAlerts()
	Sounds(w2, ns2)
	StartFight(w2, ns2)
	w2:runTimers()
	w2.time = w2.time + 601
	ns2.UpdateAlerts()
	H.eq(Which(ns2), "keepUp", "Alerts first: the Combat buff icon")
	ns2.UpdateBuffMissing()
	H.eq(ns2.missingBuffID, 324, "then Auras: your buff's icon")
	H.eq(Which(ns2), "ownBuff", "it steps aside")
	H.eq(Heard(w2), 1, "one sound in all")
end)

H.test("the Combat buff is a buff you keep up too: recast in the fight, no icon and no sound", function()
	local w, ns = PickedShieldWorld()
	Shield(w)
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	Sounds(w, ns)
	StartFight(w, ns)
	w:runTimers()
	w.time = w.time + 601
	ns.UpdateBuffMissing()
	ns.UpdateAlerts()
	H.eq(Heard(w), 1, "it ran out: one sound")
	-- The cast event, with your auras still hidden.
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 324)
	w:runTimers()
	H.eq(ns.missingBuffID, nil, "cast: your buff's icon goes")
	H.eq(Which(ns), "", "no Combat buff icon either")
	H.eq(Heard(w), 1, "no sound for the fix")
end)

H.test("the Combat buff is a buff you keep up too: off at the fight start, your buff's icon alone", function()
	local w, ns = PickedShieldWorld()
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	Sounds(w, ns)
	StartFight(w, ns)
	w:runTimers()
	H.eq(ns.missingBuffID, 324, "off: your buff's icon shows")
	H.eq(Which(ns), "ownBuff", "your buff's icon, not the Combat buff icon")
	H.eq(LeftShown(w, ns), 1, "one icon, not two")
	H.eq(Heard(w), 1, "one sound")
	-- A list entry can be a spell ID.
	local w2, ns2 = PickedShieldWorld(324)
	ns2.UpdateIconAuras()
	ns2.UpdateAlerts()
	StartFight(w2, ns2)
	w2:runTimers()
	H.eq(Which(ns2), "ownBuff", "picked by ID: your buff's icon alone")
end)

H.test("the Combat buff icon still shows when your buff's icon is off or shows another spell", function()
	local w, ns = PickedShieldWorld()
	w.env.HUDiniDB.warnOwnBuff = false
	ns.UpdateIconAuras()
	ns.UpdateAlerts()
	StartFight(w, ns)
	w:runTimers()
	H.eq(Which(ns), "keepUp", "Your buff off: the Combat buff icon shows it")
	-- Water Shield on the list, Lightning Shield learned: two spells, two icons.
	local w2, ns2 = RealKeepUpWorld()
	ns2.UpdateIconAuras()
	ns2.UpdateAlerts()
	StartFight(w2, ns2)
	w2:runTimers()
	H.eq(ns2.missingBuffID, 324, "Lightning Shield off: your buff's icon")
	H.eq(Which(ns2), "keepUp+ownBuff", "Water Shield off too: its own icon")
	H.eq(LeftShown(w2, ns2), 2, "two icons")
end)
