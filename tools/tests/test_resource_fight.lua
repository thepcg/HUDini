-- The resource bar in a fight (TICK-0220). A fight hides your auras, so the
-- read finds no Lightning Shield and the bar drew 0. The game's own aura
-- container fills a bar HUDini makes on its slot's button
-- (SetApplicationBar), in a fight too.

-- A level 15 Shaman (resource: Lightning Shield, 3 pips). w.auras[name]:
-- the buff on you; w.hide: your auras are hidden (a fight), so no read
-- finds them. The fake AuraContainer records what HUDini tells it and is
-- protected, so a move in a fight fails the test. w:draw(n) is the game:
-- with the container on and the slot matching the buff, the button shows
-- and the bar it was given fills to n (up to its max); at 0 the button
-- hides. w.noContainer: the client has no such frame type. w:box() is the
-- resource bar's container.
local SHIELD = 324

local function World(setup)
	local w = H.world()
	local env = w.env
	w.class, w.className = "SHAMAN", "Shaman"
	w.secret, w.auras, w.containers = {}, {}, {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_Spell.GetSpellInfo = function(name)
		if name == "Lightning Shield" and not w.unknownSpell then return { spellID = SHIELD } end
	end
	-- You know Lightning Shield (TICK-0199: a class file's buff needs it).
	env.IsPlayerSpell = function(id) return id == SHIELD and not w.unlearned end
	env.C_Secrets = { ShouldAurasBeSecret = function() return w.hide == true end }
	local make = env.CreateFrame
	-- The game's buttons, and the fills HUDini makes on them (TICK-0221).
	-- HUDini may not touch a fill in a fight or while your auras are
	-- hidden: a call then goes in w.blocked, which fails the test.
	w.buttons, w.fills = {}, {}
	local function Guard(what)
		if w.hide or w.combat then w:Block("resource fill:" .. what) end
	end
	env.CreateFrame = function(kind, name, parent, template)
		if kind ~= "AuraContainer" then
			if w.fills[parent] then
				Guard("CreateFrame()")
				if w.refuseArt then error("the fill refuses") end
			end
			local f = make(kind, name, parent, template)
			if w.buttons[parent] then
				w.fills[f] = true
				local own = f.GetStatusBarTexture
				rawset(f, "GetStatusBarTexture", function(...)
					Guard("GetStatusBarTexture()")
					if w.refuseTex then error("the fill refuses") end
					return own(...)
				end)
			elseif w.fills[parent] then
				local own = f.CreateTexture
				rawset(f, "CreateTexture", function(...)
					if w.refuseStrips then
						w.stripTries = (w.stripTries or 0) + 1
						error("the fill refuses")
					end
					return own(...)
				end)
			end
			return f
		end
		if w.noContainer then error("Unknown frame type 'AuraContainer'") end
		local f = w:Frame(name, parent, { protected = true })
		local seen = { template = template, parent = parent, enabled = true, ids = {} }
		f.seen = seen
		rawset(f, "SetEnabled", function(_, v) seen.enabled = v end)
		rawset(f, "SetEditModePreviewEnabled", function(_, v) seen.preview = v end)
		rawset(f, "SetUnit", function(_, unit) seen.unit = unit end)
		local function Filters(opts)
			seen.ids = {}
			for id in pairs(opts and opts.includeSpellIDs or {}) do seen.ids[id] = true end
		end
		rawset(f, "AddAuraSlot", function(_, key, filter, opts)
			seen.slotKey, seen.slotFilter, seen.slotWhileOn = key, filter, seen.enabled
			Filters(opts.candidateFilters)
			local b = w:Frame(nil, f)
			w.buttons[b] = true
			-- The game's button refuses HUDini while your auras are hidden
			-- or in a fight. A refusal goes in w.blocked (the test fails) as
			-- well as being thrown: HUDini's pcall must not hide it.
			local function Refuse(m)
				if w.hide or w.combat then
					w:Block("resource button:" .. m .. "()")
					error("the button refuses")
				end
			end
			for _, m in ipairs({ "SetSize", "SetPoint", "ClearAllPoints" }) do
				local own = b[m]
				rawset(b, m, function(...)
					Refuse(m)
					return own(...)
				end)
			end
			seen.barCalls = 0
			rawset(b, "SetApplicationBar", function(_, bar, o)
				seen.barCalls = seen.barCalls + 1
				Refuse("SetApplicationBar")
				if w.refuseBar then error("bad object") end
				assert(bar:GetParent() == b, "the bar is the button's own child")
				seen.bar, seen.barOpts = bar, o
			end)
			b:Hide()
			seen.button = b
			opts.initializeFrame(b)
			return b
		end)
		rawset(f, "SetAuraSlotCandidateFilters", function(_, key, filters)
			assert(key == "resource", "the slot's key")
			Filters(filters)
		end)
		w.containers[#w.containers + 1] = f
		return f
	end
	-- The resource bar's container (Auras.lua makes the icons' own).
	function w:box()
		for _, f in ipairs(self.containers) do
			if f.seen.slotKey == "resource" then return f end
		end
	end
	function w:draw(n)
		local f = self:box()
		if not (f and f.seen.enabled and f.seen.bar and f.seen.ids[SHIELD]) then return end
		if n > 0 then
			f.seen.button:Show()
			f.seen.bar:SetValue(math.min(n, f.seen.barOpts.maxApplications))
		else
			f.seen.button:Hide()
		end
	end
	if setup then setup(w) end
	local ns = w:loadAddon()
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.hide then return nil end
		return w.auras[name]
	end
	ns.HUDini.body:Show()
	return w, ns
end

-- Lightning Shield with n charges (none at 0), as the game changes it.
local function Shield(w, ns, n)
	w.auras["Lightning Shield"] = n > 0 and { spellId = SHIELD, applications = n } or nil
	w:draw(n)
	w:fire("UNIT_AURA", "player")
	return ns.GetBar("resource")
end

-- What the player sees on the bar: the game's fill while its button shows
-- over the bar, else the bar's own fill.
local function Seen(w, ns)
	local f = w:box()
	if f and f.seen.enabled and f.seen.button:IsShown() then return f.seen.bar:GetValue() end
	return ns.GetBar("resource"):GetValue()
end

local function StartFight(w)
	w.combat, w.hide = true, true
	w:fire("PLAYER_REGEN_DISABLED")
	w:runTimers()
end

local function EndFight(w)
	w.combat, w.hide = false, false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
end

H.test("resource in a fight: the bar follows the charges, 3, 2, 1, empty, and a recast", function()
	local w, ns = World()
	Shield(w, ns, 3)
	H.eq(Seen(w, ns), 3, "out of a fight: the read")
	StartFight(w)
	local f = w:box()
	H.eq(f.seen.enabled, true, "the container is on in the fight")
	for _, n in ipairs({ 3, 2, 1, 0, 3 }) do
		Shield(w, ns, n)
		H.eq(Seen(w, ns), n, "in the fight: " .. n .. " charges")
	end
	H.eq(ns.GetBar("resource"):GetValue(), 0, "the bar's own fill stays empty under the game's")
	EndFight(w)
	H.eq(f.seen.enabled, false, "off after the fight")
	Shield(w, ns, 2)
	H.eq(Seen(w, ns), 2, "and the read draws again")
end)

H.test("resource in a fight: the container is made right, out of a fight", function()
	local w, ns = World()
	local f = w:box()
	H.eq(f ~= nil, true, "made at login")
	H.eq(f.seen.template, "CustomAuraContainerTemplate", "the game's template")
	H.eq(f.seen.parent, ns.HUDini, "on the anchor, not the body")
	H.eq(f.seen.unit, "player", "your auras")
	H.eq(f.seen.slotWhileOn, false, "off before the slot goes in")
	H.eq(f.seen.slotFilter, "HELPFUL", "a buff")
	H.eq(f.seen.ids[SHIELD], true, "the slot matches Lightning Shield")
	H.eq(f.seen.barOpts.maxApplications, 3, "filled to the class's 3 pips")
	H.eq(f.seen.enabled, false, "off while your auras read")
	local bar = ns.GetBar("resource")
	local _, rel, _, x, y = bar:GetPoint(1)
	local fpoint, frel, _, fx, fy = f:GetPoint(1)
	H.eq(frel == rel, true, "on the bar's anchor")
	H.eq(fpoint, "CENTER", "by its center (the flow layout may size it)")
	H.eq(fx, x + bar:GetWidth() / 2, "at the bar's center, across")
	H.eq(fy, y + bar:GetHeight() / 2, "at the bar's center, up")
	H.eq(f:GetWidth(), bar:GetWidth(), "as wide as the bar")
	H.eq(f:GetHeight(), bar:GetHeight(), "as high as the bar")
	H.eq(f.seen.button:GetWidth(), bar:GetWidth(), "the button as wide as the bar")
	H.eq(f.seen.button:GetHeight(), bar:GetHeight(), "the button as high as the bar")
	H.eq(#w.blocked, 0, "nothing blocked")
end)

H.test("resource in a fight: a spell ID read later joins the slot", function()
	local w, ns = World()
	local f = w:box()
	w.auras["Lightning Shield"] = { spellId = 325, applications = 3 }
	w:fire("UNIT_AURA", "player")
	StartFight(w)
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.ids[325], true, "the rank read from the buff")
	H.eq(f.seen.ids[SHIELD], true, "and the spell's own ID")
end)

H.test("resource in a fight: no spell ID known at login, the container waits", function()
	local w, ns = World(function(w2) w2.unknownSpell = true end)
	H.eq(w:box(), nil, "no container without an ID")
	Shield(w, ns, 3)
	H.eq(w:box() ~= nil, true, "made once a read gave the ID")
	H.eq(w:box().seen.ids[SHIELD], true)
end)

H.test("resource in a fight: the hidden HUD switches the container off", function()
	local w, ns = World()
	local f = w:box()
	StartFight(w)
	H.eq(f.seen.enabled, true, "on")
	ns.HUDini.body:Hide()
	w:Run(ns.HUDini.body, "OnHide")
	H.eq(f.seen.enabled, false, "off with the body")
	ns.HUDini.body:Show()
	w:Run(ns.HUDini.body, "OnShow")
	H.eq(f.seen.enabled, true, "on again")
	ns.HUDini.body:SetAlpha(0.4)
	H.eq(f:GetAlpha(), 0.4, "follows the body's alpha")
	w.env.HUDiniDB.showResource = false
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.enabled, false, "off with the bar's switch")
end)

H.test("resource in a fight: with no container the last count stays, not 0", function()
	local w, ns = World(function(w2) w2.noContainer = true end)
	Shield(w, ns, 2)
	StartFight(w)
	local bar = Shield(w, ns, 2)
	H.eq(bar:GetValue(), 2, "the count from before the fight")
	EndFight(w)
	Shield(w, ns, 0)
	H.eq(bar:GetValue(), 0, "a read that finds no buff: empty")
end)

H.test("resource in a fight: a refused fill leaves the old way", function()
	local w, ns = World(function(w2) w2.refuseBar = true end)
	local f = w:box()
	H.eq(f.seen.enabled, false, "the container stays off")
	Shield(w, ns, 3)
	StartFight(w)
	H.eq(f.seen.enabled, false, "in the fight too")
	H.eq(Shield(w, ns, 3):GetValue(), 3, "the last count stays")
end)

-- This pins the hand-over only: a secret count reaches SetValue. It cannot
-- pin "never compared": the stub cannot make 2 throw on a compare
-- (harness.lua, Secret values).
H.test("resource in a fight: a secret count goes to the bar, kept unread", function()
	local w, ns = World()
	local bar = ns.GetBar("resource")
	local count = 2
	w.secret[count] = true
	w.auras["Lightning Shield"] = { spellId = SHIELD, applications = count }
	w:fire("UNIT_AURA", "player")
	H.eq(bar:GetValue(), 2, "the bar takes it")
end)

-- The resource the Your class page picks (w.pick), over the class file's.
local function Pick(w, ns, r)
	if not w.pickHooked then
		local own = ns.ClassValue
		ns.ClassValue = function(key)
			if key == "resource" and w.pick then return w.pick end
			return own(key)
		end
		w.pickHooked = true
	end
	w.pick = r
	-- Saved as a pick on the Your class page is: no known spell needed.
	ns.ClassDB().resource = r
end

H.test("resource in a fight: other stacks picked out of a fight, the fill follows", function()
	local w, ns = World()
	local f = w:box()
	Pick(w, ns, { aura = "Lightning Shield", max = 5 })
	Shield(w, ns, 3)
	H.eq(f.seen.barOpts.maxApplications, 5, "filled to the 5 pips picked now")
	StartFight(w)
	H.eq(f.seen.enabled, true, "on in the fight")
	Shield(w, ns, 4)
	H.eq(Seen(w, ns), 4, "4 of 5")
end)

H.test("resource in a fight: another buff picked out of a fight, the slot follows", function()
	local w, ns = World(function(w2)
		local spell = w2.env.C_Spell.GetSpellInfo
		w2.env.C_Spell.GetSpellInfo = function(name)
			if name == "Water Shield" then return { spellID = 52127 } end
			return spell(name)
		end
	end)
	local f = w:box()
	Shield(w, ns, 3)
	w:fire("UNIT_AURA", "player") -- the IDs worked out after the read
	Pick(w, ns, { aura = "Water Shield", max = 3 })
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.ids[52127], true, "the slot matches the new buff")
	H.eq(f.seen.ids[SHIELD], nil, "and not the old one")
	StartFight(w)
	H.eq(f.seen.enabled, true, "on in the fight")
	H.eq(ns.GetBar("resource"):GetValue(), 0, "no count of the old buff on the bar")
end)

H.test("resource in a fight: another buff picked, no container: the old count does not stay", function()
	local w, ns = World(function(w2) w2.noContainer = true end)
	Shield(w, ns, 3)
	Pick(w, ns, { aura = "Water Shield", max = 3 })
	StartFight(w)
	w:fire("UNIT_AURA", "player")
	H.eq(ns.GetBar("resource"):GetValue(), 0, "the Lightning Shield count is not drawn for Water Shield")
end)

H.test("resource in a fight: a /reload in a fight waits, then makes the container", function()
	local w, ns = World(function(w2) w2.combat, w2.hide = true, true end)
	w:takeBlocked() -- the click bars wait for the fight's end (not this test)
	H.eq(w:box(), nil, "not made in a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:fire("UNIT_AURA", "player")
	H.eq(w:box(), nil, "not made while your auras are still hidden")
	w.hide = false
	w:fire("ADDON_RESTRICTION_STATE_CHANGED")
	w:runTimers()
	Shield(w, ns, 3)
	local f = w:box()
	H.eq(f ~= nil, true, "made once your auras read")
	H.eq(f.seen.barOpts.maxApplications, 3, "with its fill")
	StartFight(w)
	H.eq(f.seen.enabled, true, "and on in the next fight")
	Shield(w, ns, 2)
	H.eq(Seen(w, ns), 2, "drawing the charges")
end)

H.test("resource in a fight: a refused fill is tried again, a few times only", function()
	local w, ns = World(function(w2) w2.refuseBar = true end)
	local f = w:box()
	H.eq(f ~= nil, true, "the container is kept")
	H.eq(f.seen.enabled, false, "off with no fill")
	w.refuseBar = false
	Shield(w, ns, 3)
	H.eq(f.seen.barOpts.maxApplications, 3, "the fill taken on a later try")
	StartFight(w)
	H.eq(f.seen.enabled, true, "on in the fight")

	local w2, ns2 = World(function(w3) w3.refuseBar = true end)
	for _ = 1, 20 do Shield(w2, ns2, 3) end
	H.eq(w2:box().seen.barCalls <= 6, true, "a client that never takes it is left alone")
end)

H.test("resource in a fight: a layout in a fight moves nothing and switches it off", function()
	local w, ns = World()
	local f = w:box()
	StartFight(w)
	H.eq(f.seen.enabled, true, "on")
	local _, _, _, fx, fy = f:GetPoint(1)
	local fw = f:GetWidth()
	w.env.HUDiniDB.barHeight = (w.env.HUDiniDB.barHeight or 10) + 6
	ns.HUDini:Layout()
	w:fire("UNIT_AURA", "player")
	local _, _, _, gx, gy = f:GetPoint(1)
	H.eq(gx == fx and gy == fy and f:GetWidth() == fw, true, "the container did not move")
	H.eq(f.seen.enabled, false, "off: it no longer fits the bar")
	EndFight(w)
	ns.HUDini:Layout()
	local bar = ns.GetBar("resource")
	H.eq(f:GetHeight(), bar:GetHeight(), "placed again after the fight")
	StartFight(w)
	H.eq(f.seen.enabled, true, "and on in the next fight")
end)

H.test("resource in a fight: a restriction with no fight switches it on", function()
	local w = World()
	local f = w:box()
	w.hide = true
	w:fire("ADDON_RESTRICTION_STATE_CHANGED")
	w:runTimers()
	H.eq(f.seen.enabled, true, "on with no fight")
	w.hide = false
	w:fire("ADDON_RESTRICTION_STATE_CHANGED")
	w:runTimers()
	H.eq(f.seen.enabled, false, "off when your auras read again")
end)

H.test("resource in a fight: a restriction enforced after its event is seen a frame later", function()
	local w = World()
	local f = w:box()
	w:fire("ADDON_RESTRICTION_STATE_CHANGED")
	H.eq(f.seen.enabled, false, "not yet hidden at the event")
	w.hide = true
	w:runTimers()
	H.eq(f.seen.enabled, true, "on at the frame-later pass")
end)

H.test("resource in a fight: a new texture in a fight waits for the fight's end", function()
	local w, ns = World()
	local f = w:box()
	local calls = 0
	rawset(f.seen.bar, "SetStatusBarTexture", function() calls = calls + 1 end)
	StartFight(w)
	ns.ApplyTexture()
	H.eq(calls, 0, "the fill is not touched in the fight")
	EndFight(w)
	w:fire("UNIT_AURA", "player")
	H.eq(calls, 1, "out of the fight it follows, with no new pick")
end)

H.test("resource in a fight: a refused switch is tried again", function()
	local w, ns = World()
	local f = w:box()
	local set = rawget(f, "SetEnabled")
	rawset(f, "SetEnabled", function() error("refused") end)
	StartFight(w)
	H.eq(f.seen.enabled, false, "refused")
	rawset(f, "SetEnabled", set)
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.enabled, true, "taken on the next aura change")
end)

H.test("resource in a fight: the hidden bar switches it off", function()
	local w, ns = World()
	local f = w:box()
	StartFight(w)
	H.eq(f.seen.enabled, true, "on")
	ns.GetBar("resource"):Hide()
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.enabled, false, "off with the bar hidden")
end)

H.test("resource in a fight: a new texture while your auras are hidden waits too", function()
	local w, ns = World()
	local f = w:box()
	local calls = 0
	rawset(f.seen.bar, "SetStatusBarTexture", function() calls = calls + 1 end)
	w.hide = true
	ns.ApplyTexture()
	H.eq(calls, 0, "not touched while hidden")
	w.hide = false
	w:fire("UNIT_AURA", "player")
	H.eq(calls, 1, "done once your auras read")
end)

H.test("resource in a fight: back to a power resource, the container goes off", function()
	local w, ns = World()
	local f = w:box()
	StartFight(w)
	H.eq(f.seen.enabled, true, "on")
	w.env.Enum.PowerType.Maelstrom = w.env.Enum.PowerType.Maelstrom or 11
	Pick(w, ns, { power = "Maelstrom" })
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.enabled, false, "off with a power resource")
	EndFight(w)
	H.eq(f.seen.enabled, false, "and stays off")
end)

H.test("resource in a fight: a buff with no known spell ID keeps the container off", function()
	local w, ns = World()
	local f = w:box()
	Shield(w, ns, 3)
	Pick(w, ns, { aura = "Maelstrom Weapon", max = 5 })
	w:fire("UNIT_AURA", "player")
	StartFight(w)
	H.eq(f.seen.enabled, false, "off: an empty list may match any buff")
	H.eq(f.seen.ids[SHIELD], true, "the slot keeps its old IDs")
end)

H.test("resource in a fight: other stacks picked in a fight switch it off", function()
	local w, ns = World()
	local f = w:box()
	Shield(w, ns, 3)
	StartFight(w)
	H.eq(f.seen.enabled, true, "on")
	Pick(w, ns, { aura = "Lightning Shield", max = 5 })
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.enabled, false, "off: its fill has 3 pips, the bar 5")
	H.eq(f.seen.barOpts.maxApplications, 3, "the fill not touched in the fight")
	H.eq(ns.GetBar("resource"):GetValue(), 3, "the count from before the fight")
	EndFight(w)
	H.eq(f.seen.barOpts.maxApplications, 5, "set after the fight")
end)

H.test("resource in a fight: another buff picked in a fight switches it off", function()
	local w, ns = World(function(w2)
		local spell = w2.env.C_Spell.GetSpellInfo
		w2.env.C_Spell.GetSpellInfo = function(name)
			if name == "Water Shield" then return { spellID = 52127 } end
			return spell(name)
		end
	end)
	local f = w:box()
	StartFight(w)
	H.eq(f.seen.enabled, true, "on")
	Pick(w, ns, { aura = "Water Shield", max = 3 })
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.enabled, false, "off: the slot matches the old buff")
end)

H.test("resource in a fight: other stacks picked while your auras are hidden wait", function()
	local w, ns = World()
	local f = w:box()
	w.hide = true
	w:fire("ADDON_RESTRICTION_STATE_CHANGED")
	Pick(w, ns, { aura = "Lightning Shield", max = 5 })
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.barOpts.maxApplications, 3, "the button not touched")
	H.eq(f.seen.enabled, false, "and off")
end)

H.test("resource in a fight: an ID Auras.lua keeps later joins the slot", function()
	local w, ns = World()
	local f = w:box()
	w:fire("UNIT_AURA", "player")
	local cdb = ns.ClassDB()
	cdb.auraSpellIDs = cdb.auraSpellIDs or {}
	cdb.auraSpellIDs["Lightning Shield"] = { [999] = true }
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.ids[999], true, "the kept ID")
end)

H.test("resource in a fight: the spell's own ID known later joins at the fight's start", function()
	local w = World(function(w2) w2.unknownSpell = true end)
	w.auras["Lightning Shield"] = { spellId = 325, applications = 3 }
	w:fire("UNIT_AURA", "player")
	local f = w:box()
	H.eq(f.seen.ids[325], true, "made with the rank read")
	w.unknownSpell = false
	StartFight(w)
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.ids[SHIELD], true, "the spell's ID joins")
end)

H.test("resource in a fight: no container is made in a lockdown, auras readable or not", function()
	local w = World(function(w2) w2.unknownSpell = true end)
	w.combat = true
	w.auras["Lightning Shield"] = { spellId = 325, applications = 3 }
	w:fire("UNIT_AURA", "player")
	H.eq(w:box(), nil, "waits for the fight's end")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:fire("UNIT_AURA", "player")
	H.eq(w:box() ~= nil, true, "made after it")
end)

H.test("resource in a fight: a layout while your auras are hidden leaves the button alone", function()
	local w, ns = World()
	local f = w:box()
	w.hide = true
	w.env.HUDiniDB.barHeight = (w.env.HUDiniDB.barHeight or 10) + 6
	ns.HUDini:Layout()
	w:fire("ADDON_RESTRICTION_STATE_CHANGED")
	H.eq(f.seen.enabled, false, "off: the button has the old size")
	w.hide = false
	ns.HUDini:Layout()
	H.eq(f.seen.button:GetHeight(), ns.GetBar("resource"):GetHeight(), "sized once your auras read")
end)

H.test("resource in a fight: a refused fill gets its tries again at each fight", function()
	local w = World(function(w2) w2.refuseBar = true end)
	local f = w:box()
	for _ = 1, 20 do w:fire("UNIT_AURA", "player") end
	local calls = f.seen.barCalls
	StartFight(w)
	EndFight(w)
	w.refuseBar = false
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.barCalls > calls, true, "tried again after the fight")
	H.eq(f.seen.barOpts.maxApplications, 3, "and taken")
end)

-- The hidden read's fall-back with a secret count: the kept count goes
-- back to the bar as it is. Like the test above, it pins the hand-over.
H.test("resource in a fight: a secret count kept while your auras are hidden goes back to the bar", function()
	local w, ns = World(function(w2) w2.noContainer = true end)
	local bar = ns.GetBar("resource")
	local count = 2
	w.secret[count] = true
	w.auras["Lightning Shield"] = { spellId = SHIELD, applications = count }
	w:fire("UNIT_AURA", "player")
	bar:SetValue(0)
	w.hide = true
	w:fire("UNIT_AURA", "player")
	H.eq(bar:GetValue(), 2, "the kept count")
end)

H.test("resource in a fight: a refused max is tried a few times, not at every update", function()
	local w, ns = World()
	local f = w:box()
	w.refuseBar = true
	Pick(w, ns, { aura = "Lightning Shield", max = 5 })
	local calls = f.seen.barCalls
	for _ = 1, 20 do w:fire("UNIT_AURA", "player") end
	H.eq(f.seen.barCalls - calls, 5, "five tries")
	StartFight(w)
	EndFight(w)
	w.refuseBar = false
	w:fire("UNIT_AURA", "player")
	H.eq(f.seen.barOpts.maxApplications, 5, "tried again after the next fight's start")
end)

H.test("resource in a fight: a refused change of IDs is tried a few times, not at every update", function()
	local w, ns = World(function(w2)
		local spell = w2.env.C_Spell.GetSpellInfo
		w2.env.C_Spell.GetSpellInfo = function(name)
			if name == "Water Shield" then return { spellID = 52127 } end
			return spell(name)
		end
	end)
	local f = w:box()
	local calls = 0
	rawset(f, "SetAuraSlotCandidateFilters", function()
		calls = calls + 1
		error("refused")
	end)
	Pick(w, ns, { aura = "Water Shield", max = 3 })
	for _ = 1, 20 do w:fire("UNIT_AURA", "player") end
	H.eq(calls, 5, "five tries")
end)

--------------------------------------------------------------------------------
-- Lightning Shield's look (TICK-0221): one lightning strip per charge, cut
-- at the fill's end, on the bar's own fill and on the game's fill in a
-- fight. Other resources keep the color fill.
--------------------------------------------------------------------------------

-- The client knows a name for Lightning Shield's ID.
local function Named(w)
	w.env.C_Spell.GetSpellName = function(id)
		if id == SHIELD then return "Lightning Shield" end
	end
end

-- How many strips a fill shows.
local function Strips(fill)
	local art, n = fill.art, 0
	if not (art and art.clip and art.clip:IsShown()) then return 0 end
	for _, strip in ipairs(art.strips) do
		if strip:IsShown() then n = n + 1 end
	end
	return n
end

H.test("lightning: three strips over the bar, cut at the fill's end, the fill see-through", function()
	local w, ns = World()
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	local width = bar:GetWidth()
	H.eq(Strips(bar), 3, "a strip per pip")
	local tex = bar:GetStatusBarTexture()
	H.eq(tex:GetAlpha(), 0, "the fill's color hidden")
	local clip = bar.art.clip
	local point, rel, relPoint = clip:GetPoint(2)
	H.eq(point .. " " .. relPoint, "BOTTOMRIGHT BOTTOMRIGHT", "the cut follows the fill's end")
	H.eq(rel, tex, "on the fill texture")
	local _, _, _, x = bar.art.strips[2]:GetPoint(1)
	H.eq(x, math.floor(width / 3 + 0.5), "strip 2 starts at its segment")
	local _, _, _, x2 = bar.art.strips[2]:GetPoint(2)
	H.eq(x2, math.floor(width * 2 / 3 + 0.5), "and ends at the next")
end)

H.test("lightning: a client with no name for the ID keeps the color fill", function()
	local w, ns = World()
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	H.eq(Strips(bar), 0, "no strips")
	H.eq(bar:GetStatusBarTexture():GetAlpha() ~= 0, true, "the color shows")
	H.eq(bar.art, nil, "no frames made for a look that is off")
end)

-- A power resource has no buff name: with no name for the ID either, the
-- two must not match.
H.test("lightning: a power resource on a client with no name for the ID keeps the color fill", function()
	local w, ns = World()
	w.env.Enum.PowerType.Maelstrom = w.env.Enum.PowerType.Maelstrom or 11
	Pick(w, ns, { power = "Maelstrom" })
	w:fire("UNIT_AURA", "player")
	ns.HUDini:Layout()
	local bar = ns.GetBar("resource")
	H.eq(Strips(bar), 0, "no strips")
	H.eq(bar.art, nil, "no frames made")
end)

H.test("lightning: another resource picked gets the color fill back", function()
	local w, ns = World(function(w2)
		local spell = w2.env.C_Spell.GetSpellInfo
		w2.env.C_Spell.GetSpellInfo = function(name)
			if name == "Water Shield" then return { spellID = 52127 } end
			return spell(name)
		end
	end)
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	H.eq(Strips(bar), 3, "lightning first")
	Pick(w, ns, { aura = "Water Shield", max = 3 })
	w:fire("UNIT_AURA", "player")
	H.eq(Strips(bar), 0, "another buff: no strips")
	H.eq(bar:GetStatusBarTexture():GetAlpha(), 1, "its color shows")
	local f = w:box()
	H.eq(Strips(f.seen.bar), 0, "none on the game's fill")
	H.eq(f.seen.bar:GetStatusBarTexture():GetAlpha(), 1, "its color shows too")
	w.env.Enum.PowerType.Maelstrom = w.env.Enum.PowerType.Maelstrom or 11
	Pick(w, ns, { aura = "Lightning Shield", max = 3 })
	w:fire("UNIT_AURA", "player")
	H.eq(Strips(bar), 3, "lightning again")
	Pick(w, ns, { power = "Maelstrom" })
	w:fire("UNIT_AURA", "player")
	H.eq(Strips(bar), 0, "a power resource: no strips")
end)

-- The Options tooltip asks ns.ResourceIsLightning (TICK-0231): it gives the
-- same answer as the bar's art, each time. The test keeps the first one
-- defined, Bars.lua's (it loads before Options.lua), so a copy defined
-- later cannot hide a wrong answer from it.
H.test("lightning: ns.ResourceIsLightning agrees with the bar's art", function()
	local w, ns = World(function(w2)
		local first
		setmetatable(w2.ns, {
			__index = function(_, k) if k == "ResourceIsLightning" then return first end end,
			__newindex = function(t, k, v)
				if k == "ResourceIsLightning" then first = first or v else rawset(t, k, v) end
			end,
		})
	end)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	H.eq(ns.ResourceIsLightning(), false, "no name for the ID: no art, no lightning")
	H.eq(Strips(bar), 0)
	Named(w)
	w:fire("UNIT_AURA", "player")
	H.eq(ns.ResourceIsLightning(), true, "named: lightning")
	H.eq(Strips(bar), 3)
	w.env.Enum.PowerType.Maelstrom = w.env.Enum.PowerType.Maelstrom or 11
	Pick(w, ns, { power = "Maelstrom" })
	w:fire("UNIT_AURA", "player")
	H.eq(ns.ResourceIsLightning(), false, "a power resource")
	H.eq(Strips(bar), 0)
end)

H.test("lightning: in a fight the game's fill shows the strips", function()
	local w, ns = World()
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	w:fire("UNIT_AURA", "player")
	local f = w:box()
	local fill = f.seen.bar
	H.eq(Strips(fill), 3, "a strip per pip, made out of the fight")
	H.eq(fill:GetStatusBarTexture():GetAlpha(), 0, "the game's fill color hidden")
	local _, rel = fill.art.clip:GetPoint(2)
	H.eq(rel, fill:GetStatusBarTexture(), "cut at the game's fill end")
	local _, _, _, x = fill.art.strips[3]:GetPoint(1)
	H.eq(x, math.floor(bar:GetWidth() * 2 / 3 + 0.5), "strip 3 at the bar's last third")
	StartFight(w)
	w:draw(2)
	H.eq(f.seen.enabled, true, "the game's fill draws")
	H.eq(Strips(fill), 3, "the strips stay; the fill's end cuts the third")
end)

H.test("lightning: other stacks give more strips, on both fills", function()
	local w, ns = World()
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	Pick(w, ns, { aura = "Lightning Shield", max = 5 })
	ns.HUDini:Layout()
	w:fire("UNIT_AURA", "player")
	H.eq(Strips(bar), 5, "five on the bar")
	H.eq(Strips(w:box().seen.bar), 5, "five on the game's fill")
	Pick(w, ns, { aura = "Lightning Shield", max = 3 })
	ns.HUDini:Layout()
	w:fire("UNIT_AURA", "player")
	H.eq(Strips(bar), 3, "back to three")
end)

H.test("lightning: a new bar texture gets the look too", function()
	local w, ns = World()
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	local tex = w:Frame(nil, bar)
	rawset(bar, "GetStatusBarTexture", function() return tex end)
	ns.ApplyTexture()
	H.eq(tex:GetAlpha(), 0, "the new fill texture see-through")
	local _, rel = bar.art.clip:GetPoint(2)
	H.eq(rel, tex, "the cut on the new one")
end)

H.test("lightning: a new width moves the strips", function()
	local w, ns = World()
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	ns.LayoutBars(0, 400, 0)
	local _, _, _, x = bar.art.strips[2]:GetPoint(1)
	H.eq(x, math.floor(400 / 3 + 0.5), "strip 2 at a third of the new width")
end)

-- The plain name draws the strips (the tests above); a secret one does not.
H.test("lightning: a secret name for the ID keeps the color fill", function()
	local w, ns = World()
	Named(w)
	w.secret["Lightning Shield"] = true
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	H.eq(Strips(bar), 0, "no strips")
end)

H.test("lightning: a name made secret in a fight keeps the strips", function()
	local w, ns = World()
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	H.eq(Strips(bar), 3, "three out of the fight")
	w.secret["Lightning Shield"] = true
	StartFight(w)
	Shield(w, ns, 2)
	H.eq(Strips(bar), 3, "the name read before the fight is kept")
	H.eq(bar:GetStatusBarTexture():GetAlpha(), 0, "the fill stays see-through")
end)

-- The game's fill is never touched in a fight or while your auras are
-- hidden (World puts any call in w.blocked): only Retarget dresses it.
H.test("lightning: the game's fill is left alone in a fight", function()
	local w, ns = World()
	Named(w)
	Shield(w, ns, 3)
	ns.HUDini:Layout()
	StartFight(w)
	Shield(w, ns, 2)
	w:fire("UNIT_POWER_FREQUENT", "player")
	Pick(w, ns, { aura = "Lightning Shield", max = 5 })
	w:fire("UNIT_AURA", "player")
	ns.HUDini:Layout()
	ns.ApplyTexture()
	EndFight(w)
	w.hide = true
	w:fire("ADDON_RESTRICTION_STATE_CHANGED")
	Pick(w, ns, { aura = "Lightning Shield", max = 3 })
	w:fire("UNIT_AURA", "player")
	ns.HUDini:Layout()
	H.eq(Strips(ns.GetBar("resource")), 3, "the bar's own strips follow")
end)

H.test("lightning: a game's fill that refuses the strips keeps its color, with no error", function()
	local w, ns = World(function(w2) w2.refuseArt = true end)
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	w:fire("UNIT_AURA", "player")
	local fill = w:box().seen.bar
	H.eq(Strips(fill), 0, "no strips on the game's fill")
	H.eq(fill:GetStatusBarTexture():GetAlpha(), 1, "its color shows")
	H.eq(Strips(bar), 3, "the bar's own strips")
	H.eq(ns.GetBar("resource"):GetValue(), 3, "the count still set")
end)

H.test("lightning: a game's fill that hides its texture gets no strips, with no error", function()
	local w, ns = World(function(w2) w2.refuseTex = true end)
	Named(w)
	local bar = Shield(w, ns, 3)
	ns.HUDini:Layout()
	w:fire("UNIT_AURA", "player")
	H.eq(Strips(w:box().seen.bar), 0, "no strips on the game's fill")
	H.eq(Strips(bar), 3, "the bar's own strips")
	H.eq(bar:GetValue(), 3, "the count still set")
end)

-- A refusal halfway: three strips made, the fourth refused. The fill must
-- not stay see-through with no strips (an empty bar in every fight).
H.test("lightning: a strip refused halfway gives the game's fill its color back", function()
	local w, ns = World()
	Named(w)
	Shield(w, ns, 3)
	ns.HUDini:Layout()
	w:fire("UNIT_AURA", "player")
	local fill = w:box().seen.bar
	H.eq(fill:GetStatusBarTexture():GetAlpha(), 0, "lightning first")
	w.refuseStrips = true
	Pick(w, ns, { aura = "Lightning Shield", max = 5 })
	ns.HUDini:Layout()
	w:fire("UNIT_AURA", "player")
	H.eq(fill:GetStatusBarTexture():GetAlpha(), 1, "its color shows")
	H.eq(Strips(fill), 0, "no strips")
	H.eq(w.stripTries, 1, "refused once")
	for _ = 1, 5 do w:fire("UNIT_AURA", "player") end
	H.eq(w.stripTries, 1, "not tried again")
	H.eq(fill:GetStatusBarTexture():GetAlpha(), 1, "and the color stays")
end)

-- TICK-0238: a resource entry with filter = "HARMFUL" counts a debuff. The
-- slot's filter is set when the container is made, once.
H.test("resource in a fight: a debuff resource gets a debuff slot", function()
	local w, ns = World(function(w2) w2.unknownSpell = true end)
	H.eq(w:box(), nil, "no spell ID yet: no container")
	Pick(w, ns, { aura = "Lightning Shield", max = 3, filter = "HARMFUL" })
	w.unknownSpell = false
	w:fire("UNIT_AURA", "player")
	local f = w:box()
	H.ok(f, "made now")
	H.eq(f.seen.slotFilter, "HARMFUL", "a debuff slot")
	StartFight(w)
	H.eq(f.seen.enabled, true, "on in the fight")
end)

H.test("resource in a fight: a debuff picked after a buff slot was made: the container stays off", function()
	local w, ns = World()
	local f = w:box()
	Shield(w, ns, 3)
	Pick(w, ns, { aura = "Lightning Shield", max = 3, filter = "HARMFUL" })
	w:fire("UNIT_AURA", "player")
	StartFight(w)
	H.eq(f.seen.slotFilter, "HELPFUL", "the slot made for the buff")
	H.eq(f.seen.enabled, false, "a buff slot does not count the debuff")
end)

-- TICK-0238: a preferred entry yours by its talent rank, never read on you:
-- its slot would have no spell ID and count 0 for the whole fight. The
-- earlier pick stays until a read learns the ID.
H.test("resource in a fight: a preferred entry never read keeps the earlier count", function()
	local w, ns = World(function(w2)
		w2.env.GetNumTalentTabs = function() return 2 end
		w2.env.GetNumTalents = function(tab) return tab == 2 and 1 or 0 end
		w2.env.GetTalentInfo = function(tab) if tab == 2 then return "Maelstrom Weapon", 0, 1, 1, 3, 5 end end
	end)
	Pick(w, ns, { { aura = "Lightning Shield", max = 3 }, { aura = "Maelstrom Weapon", max = 5, prefer = true } })
	-- The class default, not a pick saved on the Your class page: the list
	-- picks its entry.
	ns.ClassDB().resource = nil
	Shield(w, ns, 3)
	H.eq(Seen(w, ns), 3, "no ID for Maelstrom Weapon yet: the charges")
	StartFight(w)
	Shield(w, ns, 2)
	H.eq(Seen(w, ns), 2, "the fight counts the charges")
	EndFight(w)
end)
