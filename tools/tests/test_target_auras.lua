-- The target's aura rows (TargetDebuffs.lua): your debuffs on the target
-- (TICK-0103) and the target's buffs (TICK-0118). The game's own
-- AuraContainer draws each row: HUDini makes it once, gives it its filter
-- ("HARMFUL|PLAYER", "HELPFUL"), the unit "target" and the icons' parts,
-- places it above the HUD, and reads no aura itself. What the rows look
-- like, and that the client has the frame type, needs a test sitting.

-- A logged-in player. The fake container records what HUDini tells it.
-- w.noContainer: CreateFrame("AuraContainer") throws, as on a client
-- without the frame type. w.noGroups: it makes a frame with no
-- AddAuraGroup. w.noGroupLayout: it has no SetAuraGroupLayout.
local function World(setup)
	local w = H.world()
	local env = w.env
	w.containers = {}
	env.AnchorUtil = { FlowDirection = { Right = "RIGHT", Left = "LEFT", Up = "UP", Down = "DOWN" } }
	w.loaded = {}
	env.C_AddOns.LoadAddOn = function(name) w.loaded[#w.loaded + 1] = name; return true end
	local make = env.CreateFrame
	env.CreateFrame = function(kind, name, parent, template)
		if kind ~= "AuraContainer" then return make(kind, name, parent, template) end
		if w.noContainer then error("Unknown frame type 'AuraContainer'") end
		-- Strict: a protected frame, so a move or a show in a fight fails the test.
		local f = w:Frame(name, parent, { protected = true })
		local seen = { template = template, parent = parent, calls = {}, enabled = true }
		f.seen = seen
		local function Note(k, ...) seen.calls[#seen.calls + 1] = { k, ... } end
		rawset(f, "SetEnabled", function(_, v) Note("SetEnabled", v); seen.enabled = v end)
		if not w.noGroups then
			rawset(f, "AddAuraGroup", function(_, key, filter, opts)
				Note("AddAuraGroup", key, filter)
				seen.groups = (seen.groups or 0) + 1
				seen.filter, seen.opts = filter, opts
				-- A group added while on listens for every unit.
				seen.groupWhileOn = seen.groupWhileOn or seen.enabled
			end)
		end
		rawset(f, "SetEditModePreviewEnabled", function(_, v) Note("SetEditModePreviewEnabled", v); seen.preview = v end)
		rawset(f, "SetUnit", function(_, unit) Note("SetUnit", unit); seen.unit = unit end)
		rawset(f, "UpdateAllAuras", function() Note("UpdateAllAuras"); seen.updates = (seen.updates or 0) + 1 end)
		rawset(f, "SetFlowLayoutAnchorPoint", function(_, p) seen.anchor = p end)
		rawset(f, "SetFlowLayoutGrowthDirection", function(_, a, b) seen.growth = { a, b } end)
		rawset(f, "SetFlowLayoutMaximumLineSize", function(_, n) seen.line = n end)
		if not w.noGroupLayout then
			rawset(f, "SetAuraGroupLayout", function(_, key, opts) seen.layoutKey, seen.layout = key, opts end)
		end
		w.containers[#w.containers + 1] = f
		return f
	end
	if setup then setup(w) end
	local ns = w:loadAddon()
	return w, ns
end

-- The container calls initializeFrame on each icon it makes; a fake icon
-- records which setter got which part. It starts with the mouse on, so
-- only HUDini's own calls turn it off.
local function Icon(w)
	local b = w:Frame(nil, w.env.UIParent, { mouse = true })
	local got = {}
	b.got = got
	rawset(b, "SetIcon", function(_, t) got.icon = t end)
	rawset(b, "SetDurationCooldown", function(_, cd) got.cooldown = cd end)
	rawset(b, "SetApplicationCount", function(_, fs, opts) got.count, got.countOpts = fs, opts end)
	return b
end

local function Count(seen, call)
	local n = 0
	for _, c in ipairs(seen.calls) do
		if c[1] == call then n = n + 1 end
	end
	return n
end

H.test("on by default: one row, your debuffs only, on the target", function()
	local w, ns = World()
	H.eq(w.env.HUDiniDB.showTargetDebuffs, true, "on by default")
	H.eq(ns.GetModule("targetdebuffs").enabled, true, "the module is on")
	H.eq(#w.containers, 3, "three containers: your debuffs, the target's buffs, then the debuffs on you")
	local row = ns.TargetDebuffRow()
	H.eq(row, w.containers[1], "the test hook gives it")
	local seen = row.seen
	H.eq(seen.template, "CustomAuraContainerTemplate", "the game's own template")
	H.eq(seen.parent, ns.HUDini, "a child of the HUD's anchor, which never hides")
	H.eq(w.loaded[1], "Blizzard_AuraContainer", "the game's addon is loaded first")
	H.eq(seen.groups, 1, "one group")
	H.eq(seen.filter, "HARMFUL|PLAYER", "harmful auras you cast")
	H.eq(seen.opts.maxFrameCount, 8, "up to 8 icons")
	H.eq(type(seen.opts.initializeFrame), "function", "HUDini dresses each icon")
	H.eq(seen.groupWhileOn, false, "switched off before the group goes in")
	H.eq(seen.preview, false, "no Edit Mode samples")
	H.eq(seen.unit, "target", "on the target")
	H.eq(seen.enabled, true, "switched on after")
	H.eq(row:IsShown(), true, "shown")
end)

H.test("a new target: the row reads it again", function()
	local w, ns = World()
	local seen = ns.TargetDebuffRow().seen
	local before = seen.updates or 0
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(seen.updates, before + 1, "UpdateAllAuras on a new target")
	H.eq(Count(seen, "SetUnit"), 1, "the unit is set once: it is always \"target\"")
end)

H.test("placed above the top left of the HUD, growing right", function()
	local w, ns = World()
	local row = ns.TargetDebuffRow()
	local p, to, rp, x, y = row:GetPoint(1)
	H.eq(p, "BOTTOMLEFT", "its bottom left")
	H.eq(to, ns.HUDini.mover, "on the box that covers the whole HUD")
	H.eq(rp, "TOPLEFT", "at the HUD's top left")
	H.eq(x, 1, "x")
	H.eq(y, 3, "a gap above")
	H.eq(row:GetNumPoints(), 1, "one point")
	H.eq(row.seen.anchor, "BOTTOMLEFT", "icons start at the bottom left")
	H.eq(row.seen.growth[1], "RIGHT", "and grow right")
	H.eq(row.seen.growth[2], "UP", "then up")
	H.eq(row.seen.line, 8 * (30 + 3), "a line holds 8 icons of the health bar's height")
	-- A new layout places it again, not twice.
	ns.HUDini:Layout()
	H.eq(row:GetNumPoints(), 1, "still one point after a layout")
end)

H.test("each icon gets an icon texture, a time and a stack text, the health bar's height", function()
	local w, ns = World()
	local row = ns.TargetDebuffRow()
	local b = Icon(w)
	row.seen.opts.initializeFrame(b)
	H.ok(b.got.icon, "an icon texture")
	H.eq(b.got.icon:GetParent(), b, "the texture is a child of the icon")
	H.ok(b.got.cooldown, "a Cooldown for the time left")
	H.eq(b.got.cooldown:GetParent(), b, "the Cooldown is a child of the icon")
	H.ok(b.got.count, "a stack text")
	H.eq(b.got.count:GetParent(), b, "the stack text is a child of the icon")
	H.eq(next(b.got.countOpts), nil, "no formatter: it would get a secret count")
	H.eq(b:GetWidth(), 30, "the health bar's height")
	H.eq(b:IsMouseClickEnabled(), false, "takes no clicks")
	H.eq(b:IsMouseMotionEnabled(), true, "takes mouse-over, for the game's tooltip")
	-- A new health bar height sizes the icon again.
	w.env.HUDiniDB.healthHeight = 24
	ns.HUDini:Layout()
	H.eq(b:GetWidth(), 24, "resized with the health bar")
	H.eq(row.seen.line, 8 * (24 + 3), "the line too")
end)

-- The game's tooltip for each icon (TICK-0121): the icon's own OnEnter
-- shows it and its OnLeave hides it (AuraButton.lua:80-88). HUDini turns
-- on mouse-over, keeps clicks off, and sets no script, so the game's stay.
-- Each icon starts once with its mouse all on and once all off, so each
-- half is HUDini's own call.
H.test("each icon takes mouse-over for the game's tooltip, no click, and keeps the game's scripts", function()
	local w, ns = World()
	for _, getRow in ipairs({ ns.TargetDebuffRow, ns.TargetBuffRow }) do
		local row = getRow()
		for _, start in ipairs({ true, false }) do
			local b = Icon(w)
			b:EnableMouse(start)
			local enter, leave = function() end, function() end
			b:SetScript("OnEnter", enter)
			b:SetScript("OnLeave", leave)
			row.seen.opts.initializeFrame(b)
			local what = tostring(start)
			H.eq(b:IsMouseMotionEnabled(), true, what .. ": mouse-over on")
			H.eq(b:IsMouseClickEnabled(), false, what .. ": clicks off")
			H.eq(b:GetScript("OnEnter"), enter, what .. ": the game's OnEnter stays")
			H.eq(b:GetScript("OnLeave"), leave, what .. ": the game's OnLeave stays")
			local others = {}
			for name in pairs(b.__h.scripts) do
				if name ~= "OnEnter" and name ~= "OnLeave" then others[#others + 1] = name end
			end
			table.sort(others)
			H.eq(table.concat(others, ", "), "", what .. ": no script from HUDini")
			H.eq(next(b.__h.hooks), nil, what .. ": no script hook from HUDini")
		end
	end
	-- In a fight too: the dress is the same, and nothing waits.
	w.combat = true
	local b = Icon(w)
	ns.TargetDebuffRow().seen.opts.initializeFrame(b)
	H.eq(b:IsMouseMotionEnabled(), true, "in a fight: mouse-over on")
	H.eq(b:IsMouseClickEnabled(), false, "in a fight: clicks off")
	w.combat = false
end)

H.test("an icon that throws while dressed gives no error", function()
	local w, ns = World()
	local b = Icon(w)
	rawset(b, "CreateTexture", function() error("forbidden") end)
	local ok, err = pcall(ns.TargetDebuffRow().seen.opts.initializeFrame, b)
	H.eq(ok, true, "no error from the game's row: " .. tostring(err))
	H.eq(b:GetWidth(), 30, "the parts before the throw are still set")
end)

H.test("an icon with no setters gives no error", function()
	local w, ns = World()
	local b = w:Frame(nil, w.env.UIParent) -- no SetIcon, no SetDurationCooldown, no SetApplicationCount
	ns.TargetDebuffRow().seen.opts.initializeFrame(b)
	H.eq(b:GetWidth(), 30, "it is still sized")
end)

H.test("a client without the frame type: no error, no row, and debug says why", function()
	local w, ns = World(function(w) w.noContainer = true end)
	H.eq(ns.TargetDebuffRow(), false, "no row")
	local found
	for _, m in ipairs(ns.ModuleReport()) do
		if m.name == "targetdebuffs" then found = m end
	end
	H.eq(found.note, "debug.targetDebuffs.missing", "the report has the note")
	w:slash("/hud debug modules")
	H.ok(H.printed(w, ns.TEXT[0]["debug.targetDebuffs.missing"]), "/hud debug modules says why")
	-- Off and on again does not try again, and throws nothing.
	w.env.HUDiniDB.showTargetDebuffs = false
	ns.UpdateModules()
	w.env.HUDiniDB.showTargetDebuffs = true
	ns.UpdateModules()
	w:fire("PLAYER_TARGET_CHANGED")
	ns.HUDini:Layout()
	H.eq(ns.TargetDebuffRow(), false, "still no row")
end)

H.test("a container with no aura groups: no error, no row, hidden", function()
	local w, ns = World(function(w) w.noGroups = true end)
	H.eq(ns.TargetDebuffRow(), false, "no row")
	local f = w.containers[1]
	H.eq(f:IsShown(), false, "the empty frame is hidden")
	H.eq(f.seen.enabled, false, "and switched off")
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(Count(f.seen, "UpdateAllAuras"), 0, "nothing asked of it")
end)

H.test("made once: off and on again keeps the same row", function()
	local w, ns = World()
	local row = ns.TargetDebuffRow()
	w.env.HUDiniDB.showTargetDebuffs = false
	ns.UpdateModules()
	H.eq(ns.GetModule("targetdebuffs").enabled, false, "off")
	H.eq(row.seen.enabled, false, "switched off")
	H.eq(row:IsShown(), false, "hidden")
	local updates = row.seen.updates or 0
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(row.seen.updates or 0, updates, "off: a new target asks nothing")
	w.env.HUDiniDB.showTargetDebuffs = true
	ns.UpdateModules()
	H.eq(#w.containers, 3, "still three containers")
	H.eq(row.seen.groups, 1, "still one group")
	H.eq(row.seen.enabled, true, "on again")
	H.eq(row:IsShown(), true, "shown again")
end)

H.test("Target health bar off: no row", function()
	local w, ns = World()
	w.env.HUDiniDB.showTargetHealth = false
	ns.UpdateModules()
	H.eq(ns.GetModule("targetdebuffs").enabled, false, "off without the target bar")
	H.eq(ns.TargetDebuffRow().seen.enabled, false, "switched off")
end)

H.test("turned on in a fight: built after it, nothing blocked", function()
	local w, ns = World(function(w)
		w.env.HUDiniDB = { showTargetDebuffs = false, showTargetBuffs = false, showPlayerDebuffs = false }
	end)
	H.eq(ns.TargetDebuffRow(), nil, "not built while off")
	w.combat = true
	w.env.HUDiniDB.showTargetDebuffs = true
	ns.UpdateModules()
	H.eq(ns.TargetDebuffRow(), nil, "not built in a fight")
	H.eq(#w.containers, 0, "no frame made in a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	local row = ns.TargetDebuffRow()
	H.ok(row, "built when the fight ends")
	H.eq(row.seen.unit, "target", "on the target")
	H.eq(row.seen.enabled, true, "switched on")
	H.eq(row:IsShown(), true, "shown")
	H.eq(row:GetNumPoints(), 1, "placed")
end)

H.test("a layout or an off in a fight moves nothing until it ends", function()
	local w, ns = World()
	local row = ns.TargetDebuffRow()
	w.combat = true
	w.env.HUDiniDB.healthHeight = 20
	ns.HUDini:Layout()
	H.eq(row.seen.line, 8 * (30 + 3), "not placed again in a fight")
	w.env.HUDiniDB.showTargetDebuffs = false
	ns.UpdateModules()
	H.eq(row.seen.enabled, false, "switched off in a fight: that works")
	H.eq(row:IsShown(), true, "the hide waits")
	w.env.HUDiniDB.showTargetDebuffs = true
	ns.UpdateModules()
	H.eq(row.seen.enabled, true, "on again in the same fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(row.seen.line, 8 * (20 + 3), "placed when the fight ends")
	H.eq(row:IsShown(), true, "shown")
end)

--------------------------------------------------------------------------------
-- The target's buffs (TICK-0118, D-026)
--------------------------------------------------------------------------------

-- The row's y above the HUD's top left: its line, bottom up.
local function Y(row)
	local _, _, _, _, y = row:GetPoint(1)
	return y
end

-- How the game lays out a row (AnchorUtil.ApplyFlowLayout, AnchorUtil.lua
-- :602-747; CustomAuraContainer.lua:790-801): with no padding, a row with
-- icons is one icon cell high (its elementHeight), and a row with none is
-- 1 high. row.seen.icons: the icons the game shows in it now.
local function Height(row)
	local seen = row.seen
	local layout = seen.layout or seen.opts.layout
	if (seen.icons or 0) == 0 then return 1 end
	return layout.elementHeight
end

-- Where the bottom of the row's icons is, above the HUD's top left, as
-- the game's anchors put it: the HUD, or the top of the row it sits on.
local function Bottom(ns, row)
	local p, to, rp, _, y = row:GetPoint(1)
	H.eq(row:GetNumPoints(), 1, "one point")
	H.eq(p, "BOTTOMLEFT", "its bottom left")
	H.eq(rp, "TOPLEFT", "on a top left")
	if to == ns.HUDini.mover then return y end
	return Bottom(ns, to) + Height(to) + y
end

H.test("the target's buffs: on by default, every buff, on the target", function()
	local w, ns = World()
	H.eq(w.env.HUDiniDB.showTargetBuffs, true, "on by default")
	H.eq(ns.GetModule("targetbuffs").enabled, true, "the module is on")
	local row = ns.TargetBuffRow()
	H.eq(row, w.containers[2], "the test hook gives it")
	H.ok(row ~= ns.TargetDebuffRow(), "its own container")
	local seen = row.seen
	H.eq(seen.template, "CustomAuraContainerTemplate", "the game's own template")
	H.eq(seen.parent, ns.HUDini, "a child of the HUD's anchor, which never hides")
	H.eq(seen.groups, 1, "one group")
	H.eq(seen.filter, "HELPFUL", "every helpful aura, not only yours")
	H.eq(seen.opts.maxFrameCount, 8, "up to 8 icons")
	H.eq(seen.groupWhileOn, false, "switched off before the group goes in")
	H.eq(seen.preview, false, "no Edit Mode samples")
	H.eq(seen.unit, "target", "on the target")
	H.eq(seen.enabled, true, "switched on after")
	H.eq(row:IsShown(), true, "shown")
	H.eq(ns.TargetDebuffRow().seen.filter, "HARMFUL|PLAYER", "the debuff row keeps its filter")
end)

H.test("the target's buffs: a new target, the row reads it again", function()
	local w, ns = World()
	local seen = ns.TargetBuffRow().seen
	local before = seen.updates or 0
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(seen.updates, before + 1, "UpdateAllAuras on a new target")
	H.eq(Count(seen, "SetUnit"), 1, "the unit is set once")
end)

H.test("the target's buffs sit one line above your debuffs, and drop down when that row is off", function()
	local w, ns = World()
	local db = w.env.HUDiniDB
	local buffs, debuffs = ns.TargetBuffRow(), ns.TargetDebuffRow()
	debuffs.seen.icons = 2
	H.eq(Bottom(ns, debuffs), 3, "your debuffs: the first line")
	H.eq(Bottom(ns, buffs), 3 + 30 + 3, "the buffs: one icon and a gap higher")
	local _, to, _, x = buffs:GetPoint(1)
	H.eq(to, debuffs, "on the top of your debuffs, so the game's sizes move it")
	H.eq(x, 0, "at its left")
	H.eq(buffs.seen.growth[1], "RIGHT", "grows right")
	H.eq(buffs.seen.line, 8 * (30 + 3), "a line holds 8 icons")
	-- A new health bar height moves the line.
	db.healthHeight = 24
	ns.HUDini:Layout()
	H.eq(Bottom(ns, buffs), 3 + 24 + 3, "the line follows the icon size")
	db.healthHeight = 30
	ns.HUDini:Layout()
	-- Your debuffs off: the buffs take the first line.
	db.showTargetDebuffs = false
	ns.UpdateModules()
	H.eq(Bottom(ns, buffs), 3, "debuffs off: the buffs drop to the first line")
	H.eq(select(2, buffs:GetPoint(1)), ns.HUDini.mover, "on the HUD")
	db.showTargetDebuffs = true
	ns.UpdateModules()
	H.eq(Bottom(ns, buffs), 3 + 30 + 3, "debuffs on again: the buffs go back up")
	H.eq(Bottom(ns, debuffs), 3, "and the debuffs keep the first line")
	-- The buffs off move nothing below them.
	db.showTargetBuffs = false
	ns.UpdateModules()
	H.eq(buffs:IsShown(), false, "buffs off: hidden")
	H.eq(buffs.seen.enabled, false, "and switched off")
end)

H.test("the target's buffs: your debuffs turned off in a fight move the row after it", function()
	local w, ns = World()
	local db = w.env.HUDiniDB
	local buffs = ns.TargetBuffRow()
	w.combat = true
	db.showTargetDebuffs = false
	ns.UpdateModules()
	H.eq(select(2, buffs:GetPoint(1)), ns.TargetDebuffRow(), "nothing moves in a fight")
	H.eq(buffs.seen.enabled, true, "the buffs stay on")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Y(buffs), 3, "placed on the first line when the fight ends")
	H.eq(buffs:GetNumPoints(), 1, "one point")
	H.eq(ns.TargetDebuffRow():IsShown(), false, "the debuff row, off in the fight, is hidden when it ends")
	H.eq(ns.TargetDebuffRow().seen.enabled, false, "and stays switched off")
end)

-- TICK-0124: no debuff of yours on the target leaves no empty line under
-- its buffs.
H.test("the buffs sit right above the HUD when your debuff row is empty, and move with it", function()
	local w, ns = World()
	local buffs, debuffs = ns.TargetBuffRow(), ns.TargetDebuffRow()
	-- On and empty: no line.
	debuffs.seen.icons = 0
	H.eq(Bottom(ns, buffs), 3, "empty: the buffs sit a gap above the HUD")
	-- On with icons: the buffs move up one line. The game's layout does it,
	-- in a fight too: HUDini places nothing again.
	w.combat = true
	debuffs.seen.icons = 1
	H.eq(Bottom(ns, buffs), 3 + 30 + 3, "a debuff: the buffs one icon and a gap higher")
	debuffs.seen.icons = 8
	H.eq(Bottom(ns, buffs), 3 + 30 + 3, "a full row: the same")
	debuffs.seen.icons = 0
	H.eq(Bottom(ns, buffs), 3, "the debuff ends: back down")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	-- The game gets the cell height again at each new icon size.
	w.env.HUDiniDB.healthHeight = 20
	ns.HUDini:Layout()
	for _, row in ipairs({ debuffs, buffs }) do
		H.eq(row.seen.layoutKey, row == buffs and "buffs" or "mine", "its own group")
		H.eq(row.seen.layout.elementHeight, 20 + 3 + 1, "an icon, a gap and the empty 1")
		H.eq(row.seen.layout.elementSpacing, 3, "the gap between icons")
	end
	debuffs.seen.icons = 3
	H.eq(Bottom(ns, buffs), 3 + 20 + 3, "a smaller icon: a smaller line")
	-- Off: as empty, and on the HUD.
	w.env.HUDiniDB.showTargetDebuffs = false
	ns.UpdateModules()
	H.eq(Bottom(ns, buffs), 3, "off: the buffs sit a gap above the HUD")
end)

H.test("a client with no SetAuraGroupLayout gets the cell height when the group goes in", function()
	local _, ns = World(function(w) w.noGroupLayout = true end)
	local buffs, debuffs = ns.TargetBuffRow(), ns.TargetDebuffRow()
	debuffs.seen.icons = 0
	H.eq(Bottom(ns, buffs), 3, "empty: right above the HUD")
	debuffs.seen.icons = 1
	H.eq(Bottom(ns, buffs), 3 + 30 + 3, "a debuff: one line up")
end)

H.test("a row the game will not let sit on another takes a fixed line, as before", function()
	local w, ns = World(function(w)
		local make = w.env.CreateFrame
		w.env.CreateFrame = function(...)
			local f = make(...)
			if select(1, ...) == "AuraContainer" then
				local set = f.SetPoint
				rawset(f, "SetPoint", function(self, p, to, ...)
					if to and to.seen then error("anchor family") end
					return set(self, p, to, ...)
				end)
			end
			return f
		end
	end)
	local buffs = ns.TargetBuffRow()
	local _, to, _, x, y = buffs:GetPoint(1)
	H.eq(buffs:GetNumPoints(), 1, "one point")
	H.eq(to, ns.HUDini.mover, "on the HUD")
	H.eq(x, 1, "x")
	H.eq(y, 3 + 30 + 3, "one line up")
end)

H.test("both rows off in a fight: both hidden when it ends, and on again they show", function()
	local w, ns = World()
	local db = w.env.HUDiniDB
	local buffs, debuffs = ns.TargetBuffRow(), ns.TargetDebuffRow()
	w.combat = true
	db.showTargetDebuffs, db.showTargetBuffs = false, false
	ns.UpdateModules()
	H.eq(debuffs:IsShown(), true, "in the fight: the hide waits")
	H.eq(buffs:IsShown(), true, "in the fight: the hide waits")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(debuffs:IsShown(), false, "the debuff row is hidden after the fight")
	H.eq(buffs:IsShown(), false, "the buff row is hidden after the fight")
	-- On again in a new fight, off again, on again: a start wins over a
	-- waiting hide.
	w.combat = true
	db.showTargetBuffs = true
	ns.UpdateModules()
	db.showTargetBuffs = false
	ns.UpdateModules()
	db.showTargetBuffs = true
	ns.UpdateModules()
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(buffs:IsShown(), true, "on at the end of the fight: shown")
	H.eq(buffs.seen.enabled, true, "and switched on")
	H.eq(Y(buffs), 3, "on the first line: the debuff row is off")
end)

H.test("the target's buffs: each icon gets its parts, and a throw gives no error", function()
	local w, ns = World()
	local row = ns.TargetBuffRow()
	local b = Icon(w)
	row.seen.opts.initializeFrame(b)
	H.ok(b.got.icon, "an icon texture"); H.ok(b.got.cooldown, "a Cooldown"); H.ok(b.got.count, "a stack text")
	H.eq(next(b.got.countOpts), nil, "no formatter: it would get a secret count")
	H.eq(b:GetWidth(), 30, "the health bar's height")
	H.eq(b:IsMouseClickEnabled(), false, "takes no clicks")
	H.eq(b:IsMouseMotionEnabled(), true, "takes mouse-over, for the game's tooltip")
	w.env.HUDiniDB.healthHeight = 24
	ns.HUDini:Layout()
	H.eq(b:GetWidth(), 24, "resized with the health bar")
	local bad = Icon(w)
	rawset(bad, "CreateTexture", function() error("forbidden") end)
	local ok, err = pcall(row.seen.opts.initializeFrame, bad)
	H.eq(ok, true, "no error from the game's row: " .. tostring(err))
end)

H.test("the target's buffs: a client without the frame type gives no error, no row, and debug says why", function()
	local w, ns = World(function(w) w.noContainer = true end)
	H.eq(ns.TargetBuffRow(), false, "no buff row")
	H.eq(ns.TargetDebuffRow(), false, "no debuff row")
	local found
	for _, m in ipairs(ns.ModuleReport()) do
		if m.name == "targetbuffs" then found = m end
	end
	H.eq(found.note, "debug.targetBuffs.missing", "the report has the note")
	w:slash("/hud debug modules")
	H.ok(H.printed(w, ns.TEXT[0]["debug.targetBuffs.missing"]), "/hud debug modules says why")
	w.env.HUDiniDB.showTargetBuffs = false
	ns.UpdateModules()
	w.env.HUDiniDB.showTargetBuffs = true
	ns.UpdateModules()
	w:fire("PLAYER_TARGET_CHANGED")
	ns.HUDini:Layout()
	H.eq(ns.TargetBuffRow(), false, "still no row")
end)

H.test("the target's buffs: made once, off and on again keeps the same row", function()
	local w, ns = World()
	local row = ns.TargetBuffRow()
	w.env.HUDiniDB.showTargetBuffs = false
	ns.UpdateModules()
	H.eq(ns.GetModule("targetbuffs").enabled, false, "off")
	local updates = row.seen.updates or 0
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(row.seen.updates or 0, updates, "off: a new target asks nothing")
	w.env.HUDiniDB.showTargetBuffs = true
	ns.UpdateModules()
	H.eq(#w.containers, 3, "no new container")
	H.eq(row.seen.groups, 1, "still one group")
	H.eq(row.seen.enabled, true, "on again")
	H.eq(row:IsShown(), true, "shown again")
end)

H.test("the target's buffs: Target health bar off, no row", function()
	local w, ns = World()
	w.env.HUDiniDB.showTargetHealth = false
	ns.UpdateModules()
	H.eq(ns.GetModule("targetbuffs").enabled, false, "off without the target bar")
	H.eq(ns.TargetBuffRow().seen.enabled, false, "switched off")
end)

H.test("the target's buffs: turned on in a fight, built after it, nothing blocked", function()
	local w, ns = World(function(w) w.env.HUDiniDB = { showTargetBuffs = false } end)
	H.eq(ns.TargetBuffRow(), nil, "not built while off")
	local made = #w.containers
	w.combat = true
	w.env.HUDiniDB.showTargetBuffs = true
	ns.UpdateModules()
	H.eq(ns.TargetBuffRow(), nil, "not built in a fight")
	H.eq(#w.containers, made, "no frame made in a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	local row = ns.TargetBuffRow()
	H.ok(row, "built when the fight ends")
	H.eq(row.seen.filter, "HELPFUL")
	H.eq(row.seen.enabled, true, "switched on")
	H.eq(row:IsShown(), true, "shown")
	H.eq(select(2, row:GetPoint(1)), ns.TargetDebuffRow(), "placed on your debuffs")
end)

H.test("the target's buffs: off in a fight switches off at once, the hide waits", function()
	local w, ns = World()
	local row = ns.TargetBuffRow()
	w.combat = true
	w.env.HUDiniDB.showTargetBuffs = false
	ns.UpdateModules()
	H.eq(row.seen.enabled, false, "switched off in a fight: that works")
	H.eq(row:IsShown(), true, "the hide waits")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(row:IsShown(), false, "hidden when the fight ends")
	w.env.HUDiniDB.showTargetBuffs = true
	ns.UpdateModules()
	H.eq(row.seen.enabled, true, "on again")
	H.eq(row:IsShown(), true, "shown again")
end)

H.test("reads no aura: the game's row does it", function()
	-- Strip comments first: only code counts.
	local src = H.readFile("TargetDebuffs.lua")
	src = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
	for _, api in ipairs({ "C_UnitAuras", "UnitAura", "UnitDebuff", "UnitBuff", "AuraUtil",
			"GetAuraData", "ForEachAura", "UNIT_AURA" }) do
		H.eq(src:find(api, 1, true), nil, "no " .. api)
	end
end)
