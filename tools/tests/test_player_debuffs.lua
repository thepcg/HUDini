-- The row of debuffs on you (TargetDebuffs.lua, TICK-0128, D-027): the
-- game's own AuraContainer, unit "player", filter "HARMFUL", right of your
-- health bar, growing right. It is a child of the HUD's anchor and follows
-- the HUD's body: on while the body shows, off while it hides, with the
-- body's alpha. What it looks like, and that the game lets it be placed
-- and switched like this, needs a test sitting.

-- A logged-in player. The fake container records what HUDini tells it,
-- and is protected, so a move or a show in a fight fails the test.
-- w.noContainer: CreateFrame("AuraContainer") throws.
local function World(setup)
	local w = H.world()
	local env = w.env
	w.containers = {}
	env.AnchorUtil = { FlowDirection = { Right = "RIGHT", Left = "LEFT", Up = "UP", Down = "DOWN" } }
	local make = env.CreateFrame
	env.CreateFrame = function(kind, name, parent, template)
		if kind ~= "AuraContainer" then return make(kind, name, parent, template) end
		if w.noContainer then error("Unknown frame type 'AuraContainer'") end
		local f = w:Frame(name, parent, { protected = true })
		local seen = { template = template, parent = parent, calls = {}, enabled = true }
		f.seen = seen
		local function Note(k, ...) seen.calls[#seen.calls + 1] = { k, ... } end
		rawset(f, "SetEnabled", function(_, v) Note("SetEnabled", v); seen.enabled = v end)
		rawset(f, "AddAuraGroup", function(_, key, filter, opts)
			Note("AddAuraGroup", key, filter)
			seen.groups = (seen.groups or 0) + 1
			seen.filter, seen.opts = filter, opts
			seen.groupWhileOn = seen.groupWhileOn or seen.enabled
		end)
		rawset(f, "SetEditModePreviewEnabled", function(_, v) seen.preview = v end)
		rawset(f, "SetUnit", function(_, unit) Note("SetUnit", unit); seen.unit = unit end)
		rawset(f, "UpdateAllAuras", function() Note("UpdateAllAuras"); seen.updates = (seen.updates or 0) + 1 end)
		rawset(f, "SetFlowLayoutAnchorPoint", function(_, p) seen.anchor = p end)
		rawset(f, "SetFlowLayoutGrowthDirection", function(_, a, b) seen.growth = { a, b } end)
		rawset(f, "SetFlowLayoutMaximumLineSize", function(_, n) seen.line = n end)
		rawset(f, "SetAuraGroupLayout", function(_, key, opts) seen.layoutKey, seen.layout = key, opts end)
		w.containers[#w.containers + 1] = f
		return f
	end
	if setup then setup(w) end
	local ns = w:loadAddon()
	-- As in the game, the body runs its OnShow when it goes from hidden to
	-- shown, and its OnHide the other way (the fake frames run neither).
	local body = ns.HUDini.body
	local show, hide = body.Show, body.Hide
	local function Run(what)
		local fn = body:GetScript(what)
		if fn then fn(body) end
		for _, hook in ipairs(body.__h.hooks[what] or {}) do hook(body) end
	end
	rawset(body, "Show", function(self)
		local was = self:IsShown()
		show(self)
		if not was then Run("OnShow") end
	end)
	rawset(body, "Hide", function(self)
		local was = self:IsShown()
		hide(self)
		if was then Run("OnHide") end
	end)
	return w, ns
end

local function Count(seen, call)
	local n = 0
	for _, c in ipairs(seen.calls) do
		if c[1] == call then n = n + 1 end
	end
	return n
end

-- Where the row must be: a gap right of the health bar's right end, its
-- bottom on the bar's bottom, both on the HUD's anchor.
local function Want(ns)
	local bar = ns.GetBar("health")
	local p, to, rp, x, y = bar:GetPoint(1)
	H.eq(p, "BOTTOMLEFT", "the bar: its bottom left")
	H.eq(to, ns.HUDini, "the bar: on the anchor")
	H.eq(rp, "TOPLEFT", "the bar: at its top left")
	return x + bar:GetWidth() + 3, y
end

local function Check(ns, row, what)
	local wantX, wantY = Want(ns)
	local p, to, rp, x, y = row:GetPoint(1)
	H.eq(row:GetNumPoints(), 1, what .. ": one point")
	H.eq(p, "BOTTOMLEFT", what .. ": its bottom left")
	H.eq(to, ns.HUDini, what .. ": on the anchor, not on the bar")
	H.eq(rp, "TOPLEFT", what .. ": at the anchor's top left")
	H.eq(x, wantX, what .. ": a gap right of the bar")
	H.eq(y, wantY, what .. ": on the bar's bottom")
end

H.test("on by default: every debuff on you, the game's row, a child of the anchor", function()
	local w, ns = World()
	H.eq(w.env.HUDiniDB.showPlayerDebuffs, true, "on by default")
	H.eq(ns.GetModule("playerdebuffs").enabled, true, "the module is on")
	local row = ns.PlayerDebuffRow()
	H.eq(row, w.containers[3], "the third container, after the target's rows")
	local seen = row.seen
	H.eq(seen.template, "CustomAuraContainerTemplate", "the game's own template")
	H.eq(seen.parent, ns.HUDini, "a child of the anchor")
	H.ok(seen.parent ~= ns.HUDini.body, "not of the body: it hides in a fight")
	H.eq(seen.groups, 1, "one group")
	H.eq(seen.filter, "HARMFUL", "every harmful aura, not only yours")
	H.eq(seen.opts.maxFrameCount, 8, "up to 8 icons")
	H.eq(type(seen.opts.initializeFrame), "function", "HUDini dresses each icon")
	H.eq(seen.groupWhileOn, false, "switched off before the group goes in")
	H.eq(seen.preview, false, "no Edit Mode samples")
	H.eq(seen.unit, "player", "on you")
	H.eq(Count(seen, "SetUnit"), 1, "the unit is set once")
	H.eq(row:IsShown(), true, "shown")
	H.eq(ns.TargetDebuffRow().seen.unit, "target", "the target's rows keep their unit")
	H.eq(ns.TargetBuffRow().seen.unit, "target", "both")
end)

H.test("placed right of your health bar, growing right, one line of 8", function()
	local w, ns = World()
	local row = ns.PlayerDebuffRow()
	Check(ns, row, "at load")
	H.eq(row.seen.anchor, "BOTTOMLEFT", "icons start at the bottom left")
	H.eq(row.seen.growth[1], "RIGHT", "and grow right")
	H.eq(row.seen.line, 8 * (30 + 3), "a line holds 8 icons of the health bar's height")
	H.eq(row.seen.opts.maxFrameCount * (30 + 3), row.seen.line, "8 icons fill one line: it never wraps")
	H.eq(row.seen.layoutKey, "onyou", "its own group's layout")
	-- A new bar height, more icons or a new place: the row follows.
	local db = w.env.HUDiniDB
	db.healthHeight = 24
	db.minIcons = (db.minIcons or 1) + 4
	ns.HUDini:Layout()
	Check(ns, row, "after a layout")
	H.eq(row.seen.line, 8 * (24 + 3), "the line follows the icon size")
	db.growRight = not db.growRight
	ns.HUDini:Layout()
	Check(ns, row, "growing the other way")
end)

H.test("its icons are the health bar's height and take mouse-over, not clicks", function()
	local w, ns = World()
	local row = ns.PlayerDebuffRow()
	local b = w:Frame(nil, w.env.UIParent, { mouse = true })
	local got = {}
	rawset(b, "SetIcon", function(_, t) got.icon = t end)
	rawset(b, "SetDurationCooldown", function(_, cd) got.cooldown = cd end)
	rawset(b, "SetApplicationCount", function(_, fs, opts) got.count, got.countOpts = fs, opts end)
	row.seen.opts.initializeFrame(b)
	H.ok(got.icon and got.cooldown and got.count, "an icon, a time and a stack text")
	H.eq(next(got.countOpts), nil, "no formatter: it would get a secret count")
	H.eq(b:GetWidth(), 30, "the health bar's height")
	H.eq(b:IsMouseMotionEnabled(), true, "mouse-over, for the game's tooltip")
	H.eq(b:IsMouseClickEnabled(), false, "no click")
	w.env.HUDiniDB.healthHeight = 22
	ns.HUDini:Layout()
	H.eq(b:GetWidth(), 22, "resized with the health bar")
end)

H.test("a new target asks it nothing: it is always on you", function()
	local w, ns = World()
	local seen = ns.PlayerDebuffRow().seen
	local before = seen.updates or 0
	w:fire("PLAYER_TARGET_CHANGED")
	H.eq(seen.updates or 0, before, "no read on a new target")
	H.eq(Count(seen, "SetUnit"), 1, "the unit is set once")
end)

H.test("it follows the body: off while hidden, on and read again when it shows, its alpha as it fades", function()
	local w, ns = World()
	local row, body = ns.PlayerDebuffRow(), ns.HUDini.body
	for _, fight in ipairs({ false, true }) do
		w.combat = fight
		local what = fight and "in a fight" or "out of one"
		body:Show()
		H.eq(row.seen.enabled, true, what .. ": on while the body shows")
		local before = row.seen.updates or 0
		body:Hide()
		H.eq(row.seen.enabled, false, what .. ": off while the body is hidden")
		H.eq(row:IsShown(), true, what .. ": the frame itself is not hidden")
		body:Show()
		H.eq(row.seen.enabled, true, what .. ": on again")
		H.eq(row.seen.updates, before + 1, what .. ": and it reads your auras again")
		body:SetAlpha(0.4)
		H.eq(row:GetAlpha(), 0.4, what .. ": the body's alpha")
		body:SetAlpha(1)
		H.eq(row:GetAlpha(), 1, what .. ": back to full")
	end
	w.combat = false
end)

H.test("the HUD fades out when idle: the row fades with it, then goes", function()
	local w, ns = World()
	local row, body = ns.PlayerDebuffRow(), ns.HUDini.body
	body:Show()
	body.fadeLeft, body.fadeTotal = 1, 1
	body:GetScript("OnUpdate")(body, 0.5)
	H.eq(row:GetAlpha(), 0.5, "half way")
	H.eq(row.seen.enabled, true, "still on while it fades")
	body:GetScript("OnUpdate")(body, 0.6)
	H.eq(body:IsShown(), false, "the body is hidden")
	H.eq(row.seen.enabled, false, "the row is off: no icon, no mouse-over")
	H.eq(row:GetAlpha(), 1, "and at full alpha for the next show")
end)

H.test("turned on while the body is hidden: it waits off, and comes on with the body", function()
	local w, ns = World(function(w) w.env.HUDiniDB = { showPlayerDebuffs = false } end)
	local body = ns.HUDini.body
	body:Hide()
	w.env.HUDiniDB.showPlayerDebuffs = true
	ns.UpdateModules()
	local row = ns.PlayerDebuffRow()
	H.ok(row, "built")
	H.eq(row.seen.enabled, false, "off: the body is hidden")
	H.eq(Count(row.seen, "UpdateAllAuras"), 0, "nothing read while off")
	H.eq(row:IsShown(), true, "the frame is shown and placed")
	body:Show()
	H.eq(row.seen.enabled, true, "on with the body")
	H.eq(Count(row.seen, "UpdateAllAuras"), 1, "and it reads your auras")
end)

H.test("turned on while the body fades: it starts at the body's alpha", function()
	local w, ns = World(function(w) w.env.HUDiniDB = { showPlayerDebuffs = false } end)
	local body = ns.HUDini.body
	body:Show()
	body:SetAlpha(0.3)
	w.env.HUDiniDB.showPlayerDebuffs = true
	ns.UpdateModules()
	H.eq(ns.PlayerDebuffRow():GetAlpha(), 0.3, "the body's alpha")
end)

H.test("a row that is off stays off when the body shows", function()
	local w, ns = World()
	local row, body = ns.PlayerDebuffRow(), ns.HUDini.body
	w.env.HUDiniDB.showPlayerDebuffs = false
	ns.UpdateModules()
	H.eq(row.seen.enabled, false, "off")
	H.eq(row:IsShown(), false, "hidden")
	local updates = Count(row.seen, "UpdateAllAuras")
	body:Hide()
	body:Show()
	H.eq(row.seen.enabled, false, "still off")
	H.eq(Count(row.seen, "UpdateAllAuras"), updates, "nothing read")
	w.env.HUDiniDB.showPlayerDebuffs = true
	ns.UpdateModules()
	H.eq(row.seen.enabled, true, "on again")
	H.eq(row:IsShown(), true, "shown again")
	H.eq(#w.containers, 3, "the same row")
end)

H.test("only with Health bar on; Target health bar does not matter", function()
	local w, ns = World()
	local db = w.env.HUDiniDB
	db.showTargetHealth = false
	ns.UpdateModules()
	H.eq(ns.GetModule("playerdebuffs").enabled, true, "on without the target bar")
	H.eq(ns.GetModule("targetdebuffs").enabled, false, "the target's rows go")
	db.showTargetHealth = true
	db.showHealth = false
	ns.UpdateModules()
	H.eq(ns.GetModule("playerdebuffs").enabled, false, "off without your health bar")
	H.eq(ns.PlayerDebuffRow().seen.enabled, false, "switched off")
	H.eq(ns.GetModule("targetdebuffs").enabled, true, "the target's rows stay")
end)

H.test("off in a fight: switched off at once, the hide waits; on again in it: placed after", function()
	local w, ns = World()
	local row = ns.PlayerDebuffRow()
	local db = w.env.HUDiniDB
	w.combat = true
	db.showPlayerDebuffs = false
	ns.UpdateModules()
	H.eq(row.seen.enabled, false, "off at once")
	H.eq(row:IsShown(), true, "the hide waits")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(row:IsShown(), false, "hidden when the fight ends")
	w.combat = true
	db.showPlayerDebuffs = true
	db.healthHeight = 20
	ns.UpdateModules()
	ns.HUDini:Layout()
	H.eq(row.seen.enabled, true, "on in the fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(row:IsShown(), true, "shown when it ends")
	H.eq(row.seen.line, 8 * (20 + 3), "placed when it ends")
end)

H.test("turned on in a fight: built after it, nothing blocked", function()
	local w, ns = World(function(w) w.env.HUDiniDB = { showPlayerDebuffs = false } end)
	local made = #w.containers
	w.combat = true
	w.env.HUDiniDB.showPlayerDebuffs = true
	ns.UpdateModules()
	H.eq(ns.PlayerDebuffRow(), nil, "not built in a fight")
	H.eq(#w.containers, made, "no frame made in a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	local row = ns.PlayerDebuffRow()
	H.ok(row, "built when the fight ends")
	H.eq(row.seen.unit, "player", "on you")
	Check(ns, row, "placed")
end)

H.test("the target's rows do not stack on it", function()
	local w, ns = World()
	local db = w.env.HUDiniDB
	local function Where(row)
		local _, to, _, x, y = row:GetPoint(1)
		return to, x, y
	end
	local to, x, y = Where(ns.TargetDebuffRow())
	H.eq(to, ns.HUDini.mover, "your debuffs on the target: on the HUD")
	H.eq(x, 1, "x")
	H.eq(y, 3, "the first line")
	H.eq((Where(ns.TargetBuffRow())), ns.TargetDebuffRow(), "the target's buffs on that row")
	db.showTargetDebuffs = false
	ns.UpdateModules()
	to, x, y = Where(ns.TargetBuffRow())
	H.eq(to, ns.HUDini.mover, "your debuffs off: the buffs on the HUD, not on the row beside the bars")
	H.eq(y, 3, "the first line")
end)

H.test("a client without the frame type: no error, no row, and debug says why", function()
	local w, ns = World(function(w) w.noContainer = true end)
	H.eq(ns.PlayerDebuffRow(), false, "no row")
	local found
	for _, m in ipairs(ns.ModuleReport()) do
		if m.name == "playerdebuffs" then found = m end
	end
	H.eq(found.note, "debug.playerDebuffs.missing", "the report has the note")
	w:slash("/hud debug modules")
	H.ok(H.printed(w, ns.TEXT[0]["debug.playerDebuffs.missing"]), "/hud debug modules says why")
	ns.HUDini.body:Hide()
	ns.HUDini.body:Show()
	ns.HUDini.body:SetAlpha(0.5)
	ns.HUDini:Layout()
	H.eq(ns.PlayerDebuffRow(), false, "still no row, and nothing threw")
end)

H.test("the option: under Bars, after Target buffs, grey without Health bar", function()
	local src = H.readFile("Options.lua")
	local buffs = src:find('"showTargetBuffs"', 1, true)
	local mine = src:find('"showPlayerDebuffs"', 1, true)
	H.ok(buffs and mine and mine > buffs, "after Target buffs")
	local after = src:sub(mine, mine + 200)
	H.ok(after:find('On("showHealth"), "showHealth")', 1, true), "greyed by Health bar")
	H.eq(select(2, src:gsub('"showPlayerDebuffs"', "")), 1, "one checkbox")
end)
