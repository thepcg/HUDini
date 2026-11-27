-- Core.lua (TICK-0256, D-053): Hide objective list. HUDini hides the game's
-- objective list (ObjectiveTrackerFrame) while hideBlizzardObjectives is on:
-- alpha 0 on the list and the mouse off under it, again after each layout,
-- in a fight too; back at once when off, and shown while Edit Mode is open.

-- The list as the game makes it (Blizzard_ObjectiveTracker.xml,
-- ObjectiveTrackerContainer.xml; wow-ui-source forever): its header with
-- the collapse button, one module, and a quest block in the module's
-- contents. Nothing in it is protected; the header and the block take the
-- mouse.
local function Child(w, parent, opts)
	local f = w:Frame(nil, parent, opts)
	table.insert(parent.__h.children, f)
	return f
end

local function MakeList(w)
	local list = w:Frame("ObjectiveTrackerFrame")
	w.header = Child(w, list)
	w.collapse = Child(w, w.header, { mouse = true })
	w.module = Child(w, list)
	w.contents = Child(w, w.module)
	w.block = Child(w, w.contents, { mouse = true })
	return list
end

-- A layout that needs one more block: the pool makes it with the mouse on
-- (ObjectiveTrackerManager.lua:61-80).
local function NewBlock(w)
	return Child(w, w.contents, { mouse = true })
end

local function ListWorld(saved)
	local w = H.world()
	MakeList(w)
	w.env.HUDiniDB = saved
	w:loadAddon()
	w:runTimers()
	return w
end

local function List(w) return w.env.ObjectiveTrackerFrame end

-- H: hidden by HUDini (alpha 0, no mouse on the block or the collapse
-- button). S: as the game shows it (alpha 1, both take the mouse).
local function State(w)
	local list = List(w)
	local mouse = w.block:IsMouseEnabled() or w.collapse:IsMouseEnabled()
	if list.__h.alpha == 0 and not mouse then return "H" end
	if list.__h.alpha == 1 and w.block:IsMouseEnabled() and w.collapse:IsMouseEnabled() then
		return "S"
	end
	return ("alpha %s, mouse %s"):format(tostring(list.__h.alpha), tostring(mouse))
end

local function Apply(w)
	w.ns.HUDini:ApplyBlizzardFrames()
	return State(w)
end

H.test("the objective list shows by default", function()
	local w = ListWorld(nil)
	H.eq(w.ns.defaults.hideBlizzardObjectives, false, "default off")
	H.eq(w.env.HUDiniDB.hideBlizzardObjectives, false, "saved off")
	H.eq(State(w), "S", "after login")
	w:runTickers()
	H.eq(Apply(w), "S")
end)

H.test("on hides the list; off brings it back at once", function()
	local w = ListWorld({ hideBlizzardObjectives = true })
	H.eq(State(w), "H", "after login")
	local db = w.env.HUDiniDB
	db.hideBlizzardObjectives = false
	w.ns.HUDini:Apply()
	H.eq(State(w), "S", "off: back at once")
	db.hideBlizzardObjectives = true
	w.ns.HUDini:Apply()
	H.eq(State(w), "H", "on again")
end)

H.test("the hide holds through a layout: new blocks and mouse turned back on", function()
	local w = ListWorld({ hideBlizzardObjectives = true })
	local made = NewBlock(w)
	H.eq(made:IsMouseEnabled(), true, "a new block takes the mouse")
	-- A bonus block's layout turns its mouse back on (BonusObjectiveTracker
	-- .lua:318).
	w.block:EnableMouse(true)
	w:runTickers()
	H.eq(made:IsMouseEnabled(), false, "the next look turns it off")
	H.eq(State(w), "H", "and the block Blizzard turned back on")
	-- Off: the new block gets its mouse back too.
	w.env.HUDiniDB.hideBlizzardObjectives = false
	w.ns.HUDini:Apply()
	H.eq(State(w), "S")
	H.eq(made:IsMouseEnabled(), true, "the new block takes the mouse again")
end)

-- The tickers not cancelled.
local function Live(w)
	local n = 0
	for _, t in ipairs(w.tickers) do
		if not t.cancelled then n = n + 1 end
	end
	return n
end

H.test("the look runs only while the list is hidden", function()
	local base = Live(ListWorld(nil))
	local w = ListWorld({ hideBlizzardObjectives = true })
	H.eq(Live(w), base + 1, "on: one look more")
	w.env.HUDiniDB.hideBlizzardObjectives = false
	w.ns.HUDini:Apply()
	H.eq(Live(w), base, "off: the look stops")
	local made = NewBlock(w)
	w:runTickers()
	H.eq(made:IsMouseEnabled(), true, "off: HUDini leaves a new block alone")
	H.eq(List(w).__h.alpha, 1)

	-- Blizzard hides the empty list: nothing to look at until it shows.
	w.env.HUDiniDB.hideBlizzardObjectives = true
	w.ns.HUDini:Apply()
	List(w):Hide()
	local later = NewBlock(w)
	w:runTickers()
	H.eq(later:IsMouseEnabled(), true, "not looked at while Blizzard hides the list")
	List(w):Show()
	w:runTickers()
	H.eq(later:IsMouseEnabled(), false, "looked at once it shows")
end)

H.test("Edit Mode shows the list, and the hide comes back after it", function()
	local w = ListWorld({ hideBlizzardObjectives = true })
	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	H.eq(State(w), "S", "Edit Mode: shown, so it can be moved")
	local made = NewBlock(w)
	w:runTickers()
	H.eq(made:IsMouseEnabled(), true, "no look in Edit Mode")
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	w:runTimers()
	H.eq(State(w), "H", "after Edit Mode")
	H.eq(made:IsMouseEnabled(), false)
end)

H.test("the hide works in a fight: on, a layout, and off", function()
	local w = ListWorld(nil)
	local db = w.env.HUDiniDB
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	db.hideBlizzardObjectives = true
	H.eq(Apply(w), "H", "on in a fight")
	local made = NewBlock(w)
	w:runTickers()
	H.eq(made:IsMouseEnabled(), false, "a layout in a fight")
	db.hideBlizzardObjectives = false
	H.eq(Apply(w), "S", "off in a fight")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits for the fight to end")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
end)

-- The list is an Edit Mode system frame and a managed frame: HUDini calls
-- on it only C methods no Lua replaces, and writes no field on it
-- (TICK-0089).
H.test("the hide runs no Edit Mode code on the list and writes no field on it", function()
	local w = H.world()
	local list = MakeList(w)
	local calls, keys = {}, {}
	for _, method in ipairs({ "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints",
			"SetAllPoints", "SetScale", "SetParent", "SetAttribute", "Update", "UpdateHeight" }) do
		list[method] = function() calls[#calls + 1] = method end
	end
	for k in pairs(list) do keys[k] = true end
	w.env.HUDiniDB = { hideBlizzardObjectives = true }
	w:loadAddon()
	w:runTimers()
	NewBlock(w)
	w:runTickers()
	w.env.EventRegistry:TriggerEvent("EditMode.Enter")
	w.env.EventRegistry:TriggerEvent("EditMode.Exit")
	w:runTimers()
	w.env.HUDiniDB.hideBlizzardObjectives = false
	w.ns.HUDini:Apply()
	H.eq(table.concat(calls, ","), "", "no Lua method of the list")
	local added = {}
	for k in pairs(list) do
		if not keys[k] then added[#added + 1] = tostring(k) end
	end
	H.eq(table.concat(added, ","), "", "no new field on the list")
end)

-- The managed frame system fades the list back to alpha 1 when UIParent
-- shows again (ManagedFrameSystem.lua:79-87, :130-134): the next look hides
-- it again.
H.test("the next look hides the list again after the game sets its alpha", function()
	local w = ListWorld({ hideBlizzardObjectives = true })
	List(w):SetAlpha(1)
	w:runTickers()
	H.eq(State(w), "H")
end)

-- The intervals of the tickers made at login with saved as HUDiniDB.
local function Intervals(saved)
	local w = H.world()
	MakeList(w)
	local every = {}
	local make = w.env.C_Timer.NewTicker
	w.env.C_Timer.NewTicker = function(s, fn, ...)
		every[#every + 1] = s
		return make(s, fn, ...)
	end
	w.env.HUDiniDB = saved
	w:loadAddon()
	w:runTimers()
	return every
end

H.test("the look comes often", function()
	local left = Intervals({ hideBlizzardObjectives = true })
	for _, s in ipairs(Intervals(nil)) do
		for k, t in ipairs(left) do
			if t == s then table.remove(left, k); break end
		end
	end
	H.eq(#left, 1, "one look more")
	H.ok((left[1] or 99) <= 0.5, "every 0.5 s or less: " .. tostring(left[1]))
end)

H.test("the look stops when the setting goes off before an apply", function()
	local base = Live(ListWorld(nil))
	local w = ListWorld({ hideBlizzardObjectives = true })
	w.env.HUDiniDB.hideBlizzardObjectives = false
	w:runTickers()
	H.eq(State(w), "S", "the look shows the list")
	H.eq(Live(w), base, "and stops")
end)

H.test("the look still works when IsShown throws", function()
	local w = ListWorld({ hideBlizzardObjectives = true })
	List(w).IsShown = function() error("no") end
	local made = NewBlock(w)
	w:runTickers()
	H.eq(made:IsMouseEnabled(), false)
end)

-- A protected block in a fight: its mouse waits for the fight to end.
H.test("a part the look cannot hide in a fight waits for the fight to end", function()
	local w = ListWorld({ hideBlizzardObjectives = true })
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	local locked = Child(w, w.contents, { mouse = true, protected = true })
	w:runTickers()
	H.eq(w.ns.HUDini.needBlizzFrames, true, "waits")
	w:takeBlocked()
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.eq(locked:IsMouseEnabled(), false, "after the fight")
	H.eq(w.ns.HUDini.needBlizzFrames, false)
end)
