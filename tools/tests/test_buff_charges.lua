-- A buff's charges on its icon, with its time left (TICK-0148). The count
-- is the aura's stack count ("applications"), as the game's own buff icons
-- show it, bottom right. The game makes the text
-- (C_UnitAuras.GetAuraApplicationDisplayCount); a secret one goes to the
-- text as it is. An item's icon keeps that spot for the item count.

-- A shaman with Lightning Shield on the first icon. w.auras[name]: the buff
-- on you. The display call works as the game's: "" under the minimum, the
-- count as text, or w.hidden (a secret string) when w.restricted is set.
-- w.inFight: the game hides your auras, so no read finds them.
-- The fake AuraContainer records what HUDini tells it (TICK-0159), and is
-- protected, so a move or a show in a fight fails the test. w.noContainer:
-- the client has no such frame type; w.noSlots: it has no AddAuraSlot.
local function World(setup)
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_Spell.GetSpellName = function(id) return id == 324 and "Lightning Shield" or nil end
	w.containers = {}
	env.AnchorUtil = { FlowDirection = { Right = "RIGHT", Left = "LEFT", Up = "UP", Down = "DOWN" } }
	local make = env.CreateFrame
	env.CreateFrame = function(kind, name, parent, template)
		if kind ~= "AuraContainer" then return make(kind, name, parent, template) end
		if w.noContainer then error("Unknown frame type 'AuraContainer'") end
		local f = w:Frame(name, parent, { protected = true })
		local seen = { template = template, parent = parent, enabled = true }
		f.seen = seen
		rawset(f, "SetEnabled", function(_, v) seen.enabled = v end)
		rawset(f, "SetEditModePreviewEnabled", function(_, v) seen.preview = v end)
		rawset(f, "SetUnit", function(_, unit) seen.unit = unit end)
		rawset(f, "UpdateAllAuras", function() seen.updates = (seen.updates or 0) + 1 end)
		rawset(f, "AddAuraGroup", function() end)
		local function Filters(opts)
			seen.ids = {}
			for id in pairs(opts and opts.includeSpellIDs or {}) do seen.ids[id] = true end
		end
		if not w.noSlots then
			rawset(f, "AddAuraSlot", function(_, key, filter, opts)
				seen.slotKey, seen.slotFilter, seen.slotOpts = key, filter, opts
				seen.slotWhileOn = seen.enabled
				Filters(opts.candidateFilters)
				-- The game makes the slot's button at once and dresses it.
				local b = w:Frame(nil, f)
				opts.initializeFrame(b)
				return b
			end)
			rawset(f, "SetAuraSlotCandidateFilters", function(_, key, filters)
				assert(key == "buff", "the slot's key")
				if not seen.enabled then seen.filtersBeforeOn = true end
				Filters(filters)
			end)
		end
		w.containers[#w.containers + 1] = f
		return f
	end
	if setup then setup(w) end
	local ns = w:loadAddon()
	w.auras, w.calls = {}, 0
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.inFight then return nil end
		return w.auras[name]
	end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.inFight == true end }
	env.C_UnitAuras.GetAuraDuration = function(_, id)
		for _, data in pairs(w.auras) do
			if data.auraInstanceID == id then return {} end
		end
		error("no aura with that instance")
	end
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
	-- Where Layout puts an icon: its center on the anchor's top left.
	f:SetPoint("CENTER", hud, "TOPLEFT", 20, -20)
	f:SetSize(36, 36)
	f:Show()
	-- The HUD shows (a fight shows it; the hide when idle is not under test).
	hud.body:Show()
	-- The time takes the game's DurationObject, or a cast's start and length.
	rawset(f.buff, "SetCooldownFromDurationObject", function() end)
	rawset(f.buff, "SetCooldown", function() end)
	return w, ns, f
end

-- The slot's button, as the game makes it; it records which setter got
-- which part. It starts with the mouse on, so only HUDini turns it off.
local function Button(w)
	local b = w:Frame(nil, w.env.UIParent, { mouse = true })
	local got = {}
	b.got = got
	rawset(b, "SetIcon", function(_, x) got.icon = x end)
	rawset(b, "SetDurationCooldown", function(_, cd) got.cooldown = cd end)
	rawset(b, "SetApplicationCount", function(_, fs, opts) got.count, got.countOpts = fs, opts end)
	return b
end

local function Charges(f)
	return f.charges and f.charges:GetText()
end

local function Shield(w, n)
	w.auras["Lightning Shield"] = { auraInstanceID = 77, spellId = 324, duration = 600, expirationTime = 700,
		applications = n }
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

-- TICK-0159: DK, 2026-11-21: "sometimes it says I still have stacks when my
-- in-game buff bar shows that I've already run out." DK's probe showed that
-- a fight hides your own auras from every read. So in a fight the game's own
-- aura container draws the buff on the icon: one per spell icon, with one
-- aura slot matched by spell ID. What it draws needs a test in the game.

-- The container made for the icon (the one with an aura slot).
local function Box(w)
	for _, c in ipairs(w.containers) do
		if c.seen.slotKey then return c end
	end
end

-- Start a fight: the lockdown, and your auras hidden.
local function Fight(w, ns, on)
	w.combat, w.inFight = on, on
	ns.UpdateIconAuras()
end

H.test("in a fight the game's container draws the buff, and HUDini's own number goes", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	H.eq(Charges(f), "3", "out of a fight: HUDini's own number")
	local box = Box(w)
	H.ok(box, "a container is made, out of a fight")
	local seen = box.seen
	H.eq(seen.parent, ns.HUDini, "a child of the HUD's anchor, not of the icon")
	H.eq(seen.template, "CustomAuraContainerTemplate", "the game's template")
	H.eq(seen.slotKey, "buff", "one aura slot")
	H.eq(seen.slotFilter, "HELPFUL", "for a buff")
	H.eq(seen.slotWhileOn, false, "switched off before the slot goes in")
	H.eq(seen.unit, "player", "on you")
	H.eq(seen.preview, false, "no Edit Mode samples")
	H.ok(seen.ids[324], "matches the icon's spell")
	H.eq(seen.enabled, false, "off while your auras read")

	Fight(w, ns, true)
	H.eq(seen.enabled, true, "on in the fight")
	H.eq(Charges(f), "", "HUDini's own number goes")
	H.eq(f.buff:IsShown(), false, "HUDini's own time goes")

	Fight(w, ns, false)
	H.eq(seen.enabled, false, "off after the fight")
	H.eq(Charges(f), "3", "HUDini draws its own number again")
	H.eq(f.buff:IsShown(), true, "and its own time")
end)

H.test("the container sits on the icon, above its own time, the same size", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	local box = Box(w)
	local point, rel, relPoint, x, y = box:GetPoint(1)
	H.eq(point, "CENTER", "by its center")
	H.eq(rel, ns.HUDini, "on the anchor, not on the icon")
	H.eq(relPoint, "TOPLEFT", "on the anchor's top left")
	H.eq(x, 20, "the icon's x")
	H.eq(y, -20, "the icon's y")
	H.eq(box:GetWidth(), 36, "the icon's size")
	H.ok(box:GetFrameLevel() > f.buff:GetFrameLevel(), "above the icon's own time")
end)

H.test("a new layout moves the container with its icon, out of a fight", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	local box = Box(w)
	ns.HUDini.spells[1].col, ns.HUDini.spells[1].row = 2, 0
	ns.HUDini:Layout()
	H.eq(select(4, f:GetPoint(1)) > 20, true, "the icon moved")
	local fp, frel, frelPoint, fx, fy = f:GetPoint(1)
	local bp, brel, brelPoint, bx, by = box:GetPoint(1)
	H.eq(bp, fp, "the same point")
	H.eq(brel, frel, "on the same frame")
	H.eq(brelPoint, frelPoint, "the same corner")
	H.eq(bx, fx, "the same x")
	H.eq(by, fy, "the same y")
	H.eq(box:GetWidth(), f:GetWidth(), "the same size")
end)

H.test("the slot's button gets its parts from HUDini: time, charges, no picture, no mouse", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	local seen = Box(w).seen
	local b = Button(w)
	seen.slotOpts.initializeFrame(b)
	H.ok(b.got.cooldown, "a cooldown for the time")
	H.ok(b.got.count, "a text for the charges")
	H.eq(type(b.got.countOpts), "table", "count options")
	H.eq(b.got.countOpts.formatter, nil, "no formatter: it would get a count that can be secret")
	H.eq(b.got.icon, nil, "no picture: the icon's own stays")
	H.eq(b:IsMouseMotionEnabled(), false, "no mouse: the icon's tooltip shows under it")
	H.eq(b:IsMouseClickEnabled(), false, "no clicks")
	local point, rel = b:GetPoint(1)
	H.eq(point, "CENTER", "on the container's center")
	H.eq(rel, Box(w), "on its container")
	H.eq(b:GetWidth(), 36, "the icon's size")
end)

H.test("an item's icon gets no container", function()
	local w, ns, f = World()
	ns.HUDini.spells[1] = { itemID = 5, slot = 1, auraNames = { "Lightning Shield" } }
	Shield(w, 3)
	ns.UpdateIconAuras()
	H.eq(Box(w), nil, "no container")
	Fight(w, ns, true)
	H.eq(Box(w), nil, "none in a fight either")
	H.eq(Charges(f) or "", "", "no charges on an item")
end)

H.test("an icon made in a fight gets its container after it, and the icon is left as it was", function()
	local w, ns, f = World()
	Shield(w, 3)
	w.combat, w.inFight = true, true
	ns.UpdateIconAuras()
	H.eq(Box(w), nil, "no container made in a fight")
	Fight(w, ns, false)
	H.ok(Box(w), "made after the fight")
	H.eq(Charges(f), "3", "the number reads again")
end)

H.test("a client with no container: the icon is left as it was in a fight", function()
	local w, ns, f = World(function(w0) w0.noContainer = true end)
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	H.eq(Charges(f), "3", "the last number stays")
	H.eq(f.buff:IsShown(), true, "the last time stays")
end)

H.test("a client whose container has no aura slot: none is used, and none is asked again", function()
	local w, ns, f = World(function(w0) w0.noSlots = true end)
	Shield(w, 3)
	ns.UpdateIconAuras()
	local made = #w.containers
	ns.UpdateIconAuras()
	H.eq(#w.containers, made, "not made again")
	Fight(w, ns, true)
	H.eq(Charges(f), "3", "the icon keeps its own")
end)

H.test("a spell ID read from the buff joins the slot's filter, and is kept for the class", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	local seen = Box(w).seen
	H.ok(seen.ids[324], "made with the ID read first")
	-- One fight first, so the slot has worked its IDs out once.
	Fight(w, ns, true)
	Fight(w, ns, false)
	w.auras["Lightning Shield"].spellId = 10432
	ns.UpdateIconAuras()
	H.eq(seen.ids[10432], nil, "a new ID waits for the fight")
	Fight(w, ns, true)
	H.ok(seen.ids[324] and seen.ids[10432], "both IDs before it switches on")
	H.ok(seen.filtersBeforeOn, "the filter changes before it switches on")
	local known = w.env.HUDiniDB.classes[ns.ClassToken() or "UNKNOWN"].auraSpellIDs
	H.ok(known["Lightning Shield"][10432], "kept for the class")
end)

H.test("a secret spell ID is not kept", function()
	local w, ns = World()
	Shield(w, 3)
	w.auras["Lightning Shield"].spellId = 10433
	w.secret[10433] = true
	ns.UpdateIconAuras()
	local known = w.env.HUDiniDB.classes[ns.ClassToken() or "UNKNOWN"].auraSpellIDs
	H.eq(known["Lightning Shield"], nil, "nothing kept")
end)

H.test("a Bar 1 page change in a fight: the slot takes the new spell's ID", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	local seen = Box(w).seen
	ns.HUDini.spells[1] = { spellID = 325, slot = 1, auraNames = { "Water Shield" } }
	ns.UpdateIconAuras()
	H.ok(seen.ids[325], "the new spell's ID")
	H.eq(seen.ids[324], nil, "not the old one")
	H.eq(seen.enabled, true, "still on")
end)

H.test("a filter the container will not take switches it off", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	local box = Box(w)
	rawset(box, "SetAuraSlotCandidateFilters", function() error("refused") end)
	Fight(w, ns, true)
	H.eq(box.seen.enabled, true, "on: the filter did not change")
	ns.HUDini.spells[1] = { spellID = 325, slot = 1, auraNames = { "Water Shield" } }
	ns.UpdateIconAuras()
	H.eq(box.seen.enabled, false, "off: it would draw the old spell's buff")
	H.eq(f.buff:IsShown(), false, "no time either way")
end)

H.test("the turn to an item in a fight switches the container off", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	ns.HUDini.spells[1] = { itemID = 5, slot = 1, auraNames = { "Lightning Shield" } }
	ns.UpdateIconAuras()
	H.eq(Box(w).seen.enabled, false, "off")
end)

H.test("Buff time off: the container stays off in a fight", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	w.env.HUDiniDB.showBuffTime = false
	Fight(w, ns, true)
	H.eq(Box(w).seen.enabled, false, "off")
	H.eq(Charges(f), "", "no number")
end)

H.test("a hidden icon or body switches it off; shown again, on", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	local seen = Box(w).seen
	local body = ns.HUDini.body
	body:Hide()
	w:Run(body, "OnHide")
	H.eq(seen.enabled, false, "the body hides: off")
	body:Show()
	w:Run(body, "OnShow")
	H.eq(seen.enabled, true, "the body shows: on")
	f:Hide() -- a Bar 1 page change hides the icon
	ns.UpdateIconAuras()
	H.eq(seen.enabled, false, "the icon hides: off")
end)

H.test("the container takes the body's alpha as it fades", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	ns.HUDini.body:SetAlpha(0.4)
	H.eq(Box(w):GetAlpha(), 0.4, "the body's alpha")
end)

H.test("a cast in a fight puts no time of its own on an icon the game draws", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	local set = 0
	rawset(f.buff, "SetCooldown", function() set = set + 1 end)
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 324)
	H.eq(set, 0, "no cast time")
	H.eq(f.buff:IsShown(), false, "the game's time only")
end)

H.test("a cast in a fight still times an icon with no container (TICK-0135)", function()
	local w, ns, f = World(function(w0) w0.noContainer = true end)
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	local set = 0
	rawset(f.buff, "SetCooldown", function() set = set + 1 end)
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 324)
	H.eq(set, 1, "the cast's time")
end)

H.test("the start of a fight checks again a frame later, so the container switches on", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	local seen = Box(w).seen
	-- The event comes before the game hides your auras.
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(seen.enabled, false, "not yet")
	w.combat, w.inFight = true, true
	w:runTimers()
	H.eq(seen.enabled, true, "on a frame later")
end)

H.test("a restriction that starts checks again a frame later", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	local seen = Box(w).seen
	w:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
	H.eq(seen.enabled, false, "not yet")
	w.inFight = true
	w:runTimers()
	H.eq(seen.enabled, true, "on a frame later")
end)

H.test("a payload from the game is not read: a secret one is no error", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	w.combat, w.inFight = true, true
	local ok, err = pcall(w.fire, w, "UNIT_AURA", "player", w.hidden)
	H.ok(ok, "no error: " .. tostring(err))
	H.eq(Charges(f), "", "the game draws it")
end)

H.test("a spell with no buff of yours gets no container (Fireball)", function()
	local w, ns = World()
	ns.HUDini.spells[1] = { spellID = 133, slot = 1, auraNames = { "Fireball" } }
	ns.UpdateIconAuras()
	H.eq(Box(w), nil, "none out of a fight")
	Fight(w, ns, false)
	H.eq(Box(w), nil, "none after a fight")
end)

H.test("a buff never seen out of a fight: no container yet, the icon works as before", function()
	local w, ns, f = World()
	ns.UpdateIconAuras()
	H.eq(Box(w), nil, "no ID read: none")
	Shield(w, 3)
	ns.UpdateIconAuras()
	H.ok(Box(w), "made on the first read")
	H.eq(Charges(f), "3", "and the number shows")
end)

H.test("Buff time off: no container is made, even for a buff whose ID is kept", function()
	local w, ns = World()
	w.env.HUDiniDB.showBuffTime = false
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true } }
	Shield(w, 3)
	ns.UpdateIconAuras()
	H.eq(Box(w), nil, "none")
end)

H.test("a buff whose ID is kept from an earlier session gets its container at once", function()
	local w, ns = World()
	ns.ClassDB().auraSpellIDs = { ["Lightning Shield"] = { [324] = true } }
	ns.UpdateIconAuras()
	H.ok(Box(w), "made with no read")
end)

H.test("fewer icons (a form change): the container of an icon not used now switches off", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	local seen = Box(w).seen
	H.eq(seen.enabled, true, "on in the fight")
	ns.HUDini.spells = {}
	ns.UpdateIconAuras()
	H.eq(seen.enabled, false, "off: its icon is not used")
end)

H.test("fewer icons after a fight: the next layout switches the spare container off", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	local seen = Box(w).seen
	ns.HUDini.spells = {}
	w.combat = false
	ns.HUDini:Layout()
	H.eq(seen.enabled, false, "off")
end)

H.test("a body that hides with fewer icons: the spare container switches off", function()
	local w, ns = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	local seen = Box(w).seen
	ns.HUDini.spells = {}
	ns.HUDini.body:Hide()
	w:Run(ns.HUDini.body, "OnHide")
	H.eq(seen.enabled, false, "off")
end)

H.test("a switch on that fails: HUDini keeps its own number and time", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	rawset(Box(w), "SetEnabled", function() error("refused") end)
	Fight(w, ns, true)
	H.eq(Charges(f), "3", "the last number stays")
	H.eq(f.buff:IsShown(), true, "the last time stays")
end)

H.test("a paired buff the slot cannot match keeps the time from its cast (TICK-0135)", function()
	local w, ns, f = World()
	local names = { [324] = "Lightning Shield", [325] = "Water Shield" }
	w.env.C_Spell.GetSpellName = function(id) return names[id] end
	ns.HUDini.spells[1].auraNames = { "Lightning Shield", "Water Shield" }
	Shield(w, 3)
	ns.UpdateIconAuras()
	H.ok(Box(w), "a container, for Lightning Shield")
	-- Water Shield is seen once, with no spell ID: HUDini learns its length.
	w.auras["Lightning Shield"] = nil
	w.auras["Water Shield"] = { auraInstanceID = 78, duration = 300, expirationTime = 400, applications = 0 }
	ns.UpdateIconAuras()
	Fight(w, ns, true)
	local set = 0
	rawset(f.buff, "SetCooldown", function() set = set + 1 end)
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 325)
	H.eq(set, 1, "Water Shield: the cast's time")
	H.eq(f.buff:IsShown(), true, "shown")
	ns.UpdateIconAuras()
	H.eq(f.buff:IsShown(), true, "the next aura change keeps it")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 324)
	H.eq(set, 1, "Lightning Shield: the game draws it")
end)

H.test("a button that will not take a new size keeps its container off until it does", function()
	local w, ns, f = World()
	Shield(w, 3)
	ns.UpdateIconAuras()
	local s = f.auraBox
	local size = s.button.SetSize
	rawset(s.button, "SetSize", function() error("Auras cannot be accessed when secret while tainted") end)
	ns.HUDini.spells[1].col, ns.HUDini.spells[1].row = 0, 0
	w.env.HUDiniDB.iconSize = 40
	ns.HUDini:Layout()
	Fight(w, ns, true)
	H.eq(Box(w).seen.enabled, false, "off: it does not fit the icon")
	H.eq(Charges(f), "3", "HUDini keeps its own")
	Fight(w, ns, false)
	rawset(s.button, "SetSize", size)
	ns.HUDini:Layout()
	Fight(w, ns, true)
	H.eq(Box(w).seen.enabled, true, "on once it is sized")
	H.eq(s.button:GetWidth(), 40, "the new size")
end)
