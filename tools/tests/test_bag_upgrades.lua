-- Bag upgrade numbers (TICK-0145, D-034). With the setting on, an item in
-- your bags whose item level is above what you wear in that slot shows a
-- green "+N" on its icon in the game's own bag windows. The rules are the
-- loot feed's (TICK-0109). Off, nothing of it runs: no hooks, no events, no
-- numbers. What it looks like needs DK's play.

-- Item ID -> name, slot kind, class, subclass (1 cloth .. 4 plate), and the
-- level its link gives. w.cur[key] is the real level where the item is
-- (C_Item.GetCurrentItemLevel), which wins over the link's.
local ITEMS = {
	[101] = { "Worn Leather Vest", "INVTYPE_CHEST", 4, 2, 10 },
	[102] = { "Rugged Leather Vest", "INVTYPE_CHEST", 4, 2, 15 },
	[103] = { "Linen Vest", "INVTYPE_CHEST", 4, 1, 30 },
	[104] = { "Chain Vest", "INVTYPE_CHEST", 4, 3, 30 },
	[110] = { "Copper Band", "INVTYPE_FINGER", 4, 0, 10 },
	[111] = { "Silver Band", "INVTYPE_FINGER", 4, 0, 20 },
	[112] = { "Gold Band", "INVTYPE_FINGER", 4, 0, 15 },
	[120] = { "Lucky Charm", "INVTYPE_TRINKET", 4, 0, 12 },
	[121] = { "Old Charm", "INVTYPE_TRINKET", 4, 0, 30 },
	[122] = { "New Charm", "INVTYPE_TRINKET", 4, 0, 20 },
	[130] = { "Short Sword", "INVTYPE_WEAPON", 2, 7, 10 },
	[131] = { "Long Sword", "INVTYPE_WEAPON", 2, 7, 20 },
	[132] = { "Great Axe", "INVTYPE_2HWEAPON", 2, 1, 25 },
	[133] = { "Buckler", "INVTYPE_SHIELD", 4, 6, 30 },
	[134] = { "Wooden Shield", "INVTYPE_SHIELD", 4, 6, 5 },
	[135] = { "Glass Orb", "INVTYPE_HOLDABLE", 4, 0, 5 },
	[136] = { "Fine Sword", "INVTYPE_WEAPON", 2, 7, 25 },
	[137] = { "Parrying Dagger", "INVTYPE_WEAPONOFFHAND", 2, 15, 8 },
	[138] = { "Hunting Bow", "INVTYPE_RANGED", 2, 2, 15 },
	[139] = { "Oak Wand", "INVTYPE_RANGEDRIGHT", 2, 19, 15 },
	[140] = { "Plain Shirt", "INVTYPE_BODY", 4, 0, 1 },
	[150] = { "Linen Cloth", "", 7, 5, 5 },
	-- DK's screenshot, 2026-11-14 (TICK-0152): same item level, more armor.
	[160] = { "Rugged Mail Vest", "INVTYPE_CHEST", 4, 3, 5 },
	[161] = { "Ragged Leather Vest", "INVTYPE_CHEST", 4, 2, 5 },
	[162] = { "Padded Leather Vest", "INVTYPE_CHEST", 4, 2, 5 },
}
local function Link(id) return ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(id, ITEMS[id][1]) end
local function IdOf(link) return tonumber(tostring(link):match("item:(%d+)")) end

local RED = { r = 1, g = 0.125, b = 0.125 }
local WHITE = { r = 1, g = 1, b = 1 }
local GOLD = { r = 1, g = 0.82, b = 0 } -- the game's "Item Level" line: not red

-- A level 40 character with the bag windows of the game.
-- w.bag["bag:slot"] = item ID in your bags; w.worn[slot] = item ID you wear.
-- w.cur["bag:slot"] or w.cur["worn:slot"]: the real level there.
-- w.red[id]: the tooltip paints that item red. w.secret: values the game hides.
local function World(on, opts)
	opts = opts or {}
	local w = H.world()
	local env = w.env
	w.level = 40
	-- A warrior can wear every item here (TICK-0152 checks the class).
	w.class, w.className = "WARRIOR", "Warrior"
	w.bag, w.worn, w.cur, w.red, w.secret, w.minLevel = {}, {}, {}, {}, {}, {}
	-- w.stats[id]: the item's stats (C_Item.GetItemStats); the game's stat
	-- compare is the difference of two of them. w.delta, when set, is what
	-- the compare returns instead.
	w.stats = {}
	w.dual = false
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.HUDiniDB = { showBagUpgrades = on and true or false }
	env.CanDualWield = function() return w.dual end
	env.ItemLocation = {
		CreateFromBagAndSlot = function(_, bag, slot) return { key = bag .. ":" .. slot } end,
		CreateFromEquipmentSlot = function(_, slot) return { key = "worn:" .. slot } end,
	}
	local C_Item = env.C_Item
	C_Item.GetItemInfoInstant = function(item)
		local id = type(item) == "number" and item or IdOf(item)
		local it = id and ITEMS[id]
		if not it then return end
		return id, "", "", it[2], 134, it[3], it[4]
	end
	C_Item.GetItemInfo = function(item)
		local id = IdOf(item)
		local it = id and ITEMS[id]
		if not it then return end
		return it[1], Link(id), 2, it[5], w.minLevel[id] or 1, "", "", 1, it[2], 134, 0, it[3], it[4]
	end
	C_Item.GetDetailedItemLevelInfo = function(link)
		local id = IdOf(link)
		if w.levelOf and w.levelOf[id] ~= nil then return w.levelOf[id] end
		return id and ITEMS[id] and ITEMS[id][5]
	end
	C_Item.GetCurrentItemLevel = function(location)
		if w.curThrows then error("no item there") end
		return w.cur[location.key]
	end
	C_Item.GetItemStats = function(link)
		return w.stats[IdOf(link)]
	end
	C_Item.GetItemStatDelta = function(new, old)
		if w.delta ~= nil then return w.delta end
		local a, b = w.stats[IdOf(new)], w.stats[IdOf(old)]
		if not (a or b) then return nil end
		local out = {}
		for k, v in pairs(a or {}) do out[k] = (out[k] or 0) + v end
		for k, v in pairs(b or {}) do out[k] = (out[k] or 0) - v end
		for k, v in pairs(out) do if v == 0 then out[k] = nil end end
		return out
	end
	env.C_Container.GetContainerItemLink = function(bag, slot)
		local v = w.bag[bag .. ":" .. slot]
		if type(v) == "number" then return Link(v) end
		return v
	end
	env.GetInventoryItemLink = function(_, slot)
		local v = w.worn[slot]
		if type(v) == "number" then return Link(v) end
		return v
	end
	-- w.tooltips counts the tooltips built: the costly part of a paint.
	w.tooltips = 0
	env.C_TooltipInfo = { GetBagItem = function(bag, slot)
		w.tooltips = w.tooltips + 1
		local v = w.bag[bag .. ":" .. slot]
		local id = type(v) == "number" and v or IdOf(v)
		if w.tooltip then return w.tooltip(id) end
		local color = w.color or (w.red[id] and RED or WHITE)
		return { lines = {
			{ leftText = ITEMS[id][1], leftColor = WHITE },
			{ leftText = "Item Level " .. ITEMS[id][5], leftColor = GOLD },
			{ leftText = "Slot", leftColor = WHITE, rightText = "Type", rightColor = color },
		} }
	end }

	-- The game's bag windows: the combined one and one per bag. Each has
	-- UpdateItems and lists its item buttons; w.buttons["bag:slot"] is one.
	w.updates = 0
	w.buttons = {}
	local function Window(name)
		local f = w:Frame(name, nil)
		f.Items = {}
		f.UpdateItems = function() w.updates = w.updates + 1 end
		f.EnumerateValidItems = function(self)
			local i = 0
			return function()
				i = i + 1
				if self.Items[i] then return i, self.Items[i] end
			end
		end
		return f
	end
	w.combined = Window("ContainerFrameCombinedBags")
	w.single = Window("ContainerFrame1")
	env.NUM_CONTAINER_FRAMES = 13
	for _, at in ipairs(opts.slots or { "0:1", "0:2", "1:1", "6:1", "-1:1" }) do
		local bag, slot = at:match("^(-?%d+):(%d+)$")
		local b = w:Frame(nil, w.combined)
		b.GetBagID = function() return tonumber(bag) end
		b.GetID = function() return tonumber(slot) end
		w.combined.Items[#w.combined.Items + 1] = b
		w.buttons[at] = b
	end
	w:loadAddon()
	return w
end

-- The game updates a bag window (a loot, a move, opening it).
local function Update(w, window) (window or w.combined):UpdateItems() end

-- HUDini's marker in one corner of a button: its text, or nil when none
-- shows. The number is top right; the stat marker bottom left.
local function Corner(w, button, corner)
	for _, f in ipairs(w.frames) do
		if f.__h.parent == button and f.__h.text ~= nil and f:GetPoint(1) == corner then
			if not f:IsShown() or f:GetText() == "" then return nil end
			return f:GetText()
		end
	end
end
local function Number(w, button) return Corner(w, button, "TOPRIGHT") end

local function At(w, at) return Number(w, w.buttons[at]) end
local function Gain(w, at) return Corner(w, w.buttons[at], "BOTTOMLEFT") end

H.test("an item 5 levels above what you wear shows +5; at or below shows nothing", function()
	local w = World(true)
	w.worn[5] = 101                      -- level 10
	w.bag["0:1"] = 102                   -- level 15
	Update(w)
	H.eq(At(w, "0:1"), "+5", "higher")
	w.bag["0:1"] = 101
	Update(w)
	H.eq(At(w, "0:1"), nil, "the same item level")
	w.worn[5] = 102
	w.bag["0:1"] = 101
	Update(w)
	H.eq(At(w, "0:1"), nil, "lower")
end)

H.test("the real item level where the item is wins over the link's", function()
	local w = World(true)
	w.worn[5] = 101                      -- link 10
	w.bag["0:1"] = 102                   -- link 15
	w.cur["0:1"] = 18
	Update(w)
	H.eq(At(w, "0:1"), "+8", "the bag item's real level")
	w.cur["worn:5"] = 18
	Update(w)
	H.eq(At(w, "0:1"), nil, "what you wear is really 18 too")
	w.cur["worn:5"] = nil
	w.curThrows = true
	Update(w)
	H.eq(At(w, "0:1"), "+5", "the game throws: the link levels")
end)

H.test("rings and trinkets compare with the lower of your two", function()
	local w = World(true)
	w.worn[11], w.worn[12] = 110, 111     -- 10 and 20
	w.bag["0:1"] = 112                   -- 15
	w.worn[13], w.worn[14] = 121, 120     -- 30 and 12
	w.bag["0:2"] = 122                   -- 20
	Update(w)
	H.eq(At(w, "0:1"), "+5", "a ring above the lower ring")
	H.eq(At(w, "0:2"), "+8", "a trinket above the lower trinket")
	w.worn[11] = 111                      -- both rings 20 now
	Update(w)
	H.eq(At(w, "0:1"), nil, "a ring below both")
end)

H.test("an empty slot counts as item level 0", function()
	local w = World(true)
	w.bag["0:1"] = 102                   -- 15, nothing worn on the chest
	w.bag["0:2"] = 112                   -- 15, one ring of 20 and one empty
	w.worn[11] = 111
	Update(w)
	H.eq(At(w, "0:1"), "+15")
	H.eq(At(w, "0:2"), "+15", "the empty ring slot is the lower")
end)

H.test("equipping the item removes its number", function()
	local w = World(true)
	w.worn[5] = 101
	w.bag["0:1"] = 102
	Update(w)
	H.eq(At(w, "0:1"), "+5")
	-- The game swaps them: the old vest goes to the bag.
	w.worn[5], w.bag["0:1"] = 102, 101
	w:fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
	w:runTimers()
	H.eq(At(w, "0:1"), nil, "painted again after the gear change, with no bag update")
end)

H.test("a gear change paints the open windows again, only after a short wait", function()
	local w = World(true)
	w.worn[5] = 102
	w.bag["0:1"] = 102
	Update(w)
	H.eq(At(w, "0:1"), nil)
	w.worn[5] = nil                       -- you take the vest off
	w.tooltips = 0
	w:fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
	w:fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
	w:fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
	H.eq(At(w, "0:1"), nil, "not yet: one paint after the burst")
	w:runTimers()
	H.eq(At(w, "0:1"), "+15")
	H.eq(w.tooltips, 1, "three events, one paint")
	w.worn[5] = 102
	w.combined:Hide()
	w:fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
	w:runTimers()
	H.eq(At(w, "0:1"), "+15", "a closed window is not painted; its next update does it")
end)

H.test("gear the tooltip paints red, or a tooltip the game will not give, shows nothing", function()
	local w = World(true)
	w.bag["0:1"] = 104                   -- mail over nothing
	w.red[104] = true
	Update(w)
	H.eq(At(w, "0:1"), nil, "red: you cannot wear it")
	w.red[104] = nil
	Update(w)
	H.eq(At(w, "0:1"), "+30", "the same mail, not red")
	w.tooltip = function() return { lines = { { leftText = "Chain Vest", leftColor = WHITE } } } end
	Update(w)
	H.eq(At(w, "0:1"), nil, "a tooltip not loaded yet")
	w.tooltip = function() error("not ready") end
	Update(w)
	H.eq(At(w, "0:1"), nil, "a tooltip call that throws")
	w.tooltip = nil
	w.env.C_TooltipInfo = nil
	Update(w)
	H.eq(At(w, "0:1"), nil, "no tooltip API")
end)

H.test("a level the item needs above yours shows nothing", function()
	local w = World(true)
	w.bag["0:1"] = 102
	w.minLevel[102] = 41
	Update(w)
	H.eq(At(w, "0:1"), nil)
	w.minLevel[102] = 40
	Update(w)
	H.eq(At(w, "0:1"), "+15")
end)

H.test("armour lighter than what you wear there shows nothing", function()
	local w = World(true)
	w.worn[5] = 101                      -- leather, 10
	w.bag["0:1"] = 103                   -- cloth, 30
	w.bag["0:2"] = 104                   -- mail, 30
	Update(w)
	H.eq(At(w, "0:1"), nil, "cloth over leather")
	H.eq(At(w, "0:2"), "+20", "mail over leather")
end)

H.test("weapons: one hand, two hand, off hand", function()
	local w = World(true)
	w.worn[16], w.worn[17] = 131, 133     -- a sword of 20, a shield of 30
	w.bag["0:1"] = 132                   -- a two-hand axe of 25
	w.bag["0:2"] = 130                   -- a one-hand sword of 10
	Update(w)
	H.eq(At(w, "0:1"), "+5", "a two-hand weapon compares with the main hand only")
	H.eq(At(w, "0:2"), nil)

	w.worn[16], w.worn[17] = 130, nil     -- a sword of 10, an empty off hand
	w.bag["0:2"] = 131                   -- a sword of 20
	Update(w)
	H.eq(At(w, "0:2"), "+10", "no dual wield: the main hand only, not the empty off hand")
	w.dual = true
	Update(w)
	H.eq(At(w, "0:2"), "+20", "dual wield: the empty off hand is the lower")

	w.worn[16] = 132                      -- a two-hand axe of 25
	Update(w)
	H.eq(At(w, "0:2"), nil, "a two-hand weapon worn: the main hand only")
end)

H.test("not gear, or gear with no item level slot, shows nothing", function()
	local w = World(true)
	w.bag["0:1"] = 150                   -- cloth to craft with
	w.bag["0:2"] = 140                   -- a shirt
	Update(w)
	H.eq(At(w, "0:1"), nil)
	H.eq(At(w, "0:2"), nil)
	for _, f in ipairs(w.frames) do
		local p = f.__h.parent
		H.ok(p ~= w.buttons["0:1"] and p ~= w.buttons["0:2"], "a number is made only for a button that shows one")
	end
end)

H.test("the game gives no item level for what you wear: no number", function()
	local w = World(true)
	w.worn[5] = 101
	w.bag["0:1"] = 102
	w.levelOf = { [101] = 0 }
	Update(w)
	H.eq(At(w, "0:1"), nil, "a level of 0 is no answer, not an empty slot")
	w.levelOf = { [101] = false }
	Update(w)
	H.eq(At(w, "0:1"), nil, "no level")
	w.levelOf = nil
	Update(w)
	H.eq(At(w, "0:1"), "+5")
end)

H.test("a window whose list of buttons throws falls back to its Items", function()
	local w = World(true)
	w.bag["0:1"] = 102
	w.combined.EnumerateValidItems = function() error("not ready") end
	Update(w)
	H.eq(At(w, "0:1"), "+15")
end)

H.test("only your own bags: the bank's buttons show nothing", function()
	local w = World(true)
	w.bag["1:1"] = 102
	w.bag["6:1"] = 102
	w.bag["-1:1"] = 102
	Update(w)
	H.eq(At(w, "1:1"), "+15", "bag 1")
	H.eq(At(w, "6:1"), nil, "a bank bag")
	H.eq(At(w, "-1:1"), nil, "the bank")
end)

H.test("one window per bag works too", function()
	local w = World(true)
	local b = w:Frame(nil, w.single)
	b.GetBagID = function() return 2 end
	b.GetID = function() return 4 end
	w.single.Items[1] = b
	w.bag["2:4"] = 102
	w.single:UpdateItems()
	H.eq(Number(w, b), "+15")
end)

H.test("a window shows its numbers when it opens", function()
	local w = World(true)
	w.bag["0:1"] = 102
	w.combined:Hide()
	w.combined:Show()
	w:Run(w.combined, "OnShow")
	H.eq(At(w, "0:1"), "+15")
end)

H.test("a button that gets another item loses or changes its number", function()
	local w = World(true)
	w.bag["0:1"] = 102
	Update(w)
	H.eq(At(w, "0:1"), "+15")
	w.bag["0:1"] = nil
	Update(w)
	H.eq(At(w, "0:1"), nil, "the slot is empty now")
	w.bag["0:1"] = 104
	Update(w)
	H.eq(At(w, "0:1"), "+30")
end)

H.test("the number sits at the top right, clear of the stack count", function()
	local w = World(true)
	w.bag["0:1"] = 102
	Update(w)
	for _, f in ipairs(w.frames) do
		if f.__h.parent == w.buttons["0:1"] then
			local point, to, rel = f:GetPoint(1)
			H.eq(point, "TOPRIGHT")
			H.ok(to == w.buttons["0:1"], "on the button")
			H.eq(rel, "TOPRIGHT")
		end
	end
end)

H.test("off from the start: no hooks, no events, no numbers", function()
	local w = World(false)
	w.bag["0:1"] = 102
	local hooks = 0
	for _, h in ipairs(w.secureHooks) do
		if h.tbl == w.combined or h.tbl == w.single then hooks = hooks + 1 end
	end
	H.eq(hooks, 0, "no hook on the game's bag windows")
	H.eq(#(w.combined.__h.hooks.OnShow or {}), 0, "no OnShow hook")
	local M = w.ns.GetModule("bags")
	H.ok(M.frame == nil, "no event frame")
	Update(w)
	w:Run(w.combined, "OnShow")
	H.eq(At(w, "0:1"), nil)
	for _, f in ipairs(w.frames) do
		H.ok(f.__h.parent ~= w.buttons["0:1"], "no FontString made on the button")
	end
end)

H.test("on, then off: the numbers go and the hooks do nothing", function()
	local w = World(false)
	w.bag["0:1"] = 102
	w.env.HUDiniDB.showBagUpgrades = true
	w.ns.UpdateModules()
	H.eq(At(w, "0:1"), "+15", "on: an open window is painted at once")
	w.bag["0:1"] = 104
	Update(w)
	H.eq(At(w, "0:1"), "+30", "and after each update")
	w.env.HUDiniDB.showBagUpgrades = false
	w.ns.UpdateModules()
	H.eq(At(w, "0:1"), nil, "off: hidden")
	local M = w.ns.GetModule("bags")
	H.ok(not M.frame:IsEventRegistered("PLAYER_EQUIPMENT_CHANGED"), "no events while off")
	Update(w)
	w:fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
	w:runTimers()
	H.eq(At(w, "0:1"), nil, "the hook returns at once while off")
	H.eq(w.updates, 2, "the game's own UpdateItems still runs")
end)

H.test("the setting is off by default", function()
	local w = H.world()
	w:loadAddon()
	H.eq(w.ns.defaults.showBagUpgrades, false)
	H.eq(w.env.HUDiniDB.showBagUpgrades, false)
end)

-- TICK-0110 method: the secret is the value that WOULD show a number.
H.test("secret values: no number from them, no error", function()
	local w = World(true)
	w.bag["0:1"] = 102
	local link = Link(102)
	w.bag["0:1"] = link
	w.secret[link] = true
	Update(w)
	H.eq(At(w, "0:1"), nil, "a secret bag link")
	w.secret[link] = nil
	Update(w)
	H.eq(At(w, "0:1"), "+15", "the same link, plain")

	-- A secret worn link is a worn item the game will not show, not an
	-- empty slot (which would give +15 here).
	local worn = Link(101)               -- leather, 10
	w.worn[5] = worn
	w.secret[worn] = true
	Update(w)
	H.eq(At(w, "0:1"), nil, "a secret worn link")
	w.secret[worn] = nil
	Update(w)
	H.eq(At(w, "0:1"), "+5", "the same link, plain")

	-- A secret main hand: one hand or two decides the off hand.
	w.bag["0:2"] = 131                   -- a sword of 20
	w.dual = true
	local main = Link(132)               -- a two-hand axe of 25
	w.worn[16] = main
	w.secret[main] = true
	Update(w)
	H.eq(At(w, "0:2"), nil, "a secret main hand")
	w.secret[main] = nil
	w.worn[16] = Link(130)               -- a sword of 10, the off hand empty
	Update(w)
	H.eq(At(w, "0:2"), "+20", "plain: the empty off hand")
	w.bag["0:2"] = 133                   -- a shield of 30, the off hand empty
	w.worn[16] = main                    -- secret: one hand or two?
	w.secret[main] = true
	Update(w)
	H.eq(At(w, "0:2"), nil, "a shield beside a secret main hand")
	w.secret[main] = nil
	Update(w)
	H.eq(At(w, "0:2"), nil, "a two-hand weapon worn: no off hand")
	w.worn[16] = Link(130)
	Update(w)
	H.eq(At(w, "0:2"), "+30", "a one-hand weapon worn: the empty off hand")

	w.worn[5] = nil
	w.cur["0:1"] = 99
	w.secret[99] = true
	Update(w)
	H.eq(At(w, "0:1"), "+15", "a secret real level: the link's level instead")

	w.levelOf = { [102] = 77 }
	w.secret[77] = true
	w.cur["0:1"] = nil
	Update(w)
	H.eq(At(w, "0:1"), nil, "secret levels everywhere: no number")
	w.secret[77] = nil
	Update(w)
	H.eq(At(w, "0:1"), "+77")

	local hidden = { r = 0.95, g = 0.96, b = 0.97 }
	w.color = hidden
	w.secret[hidden] = true
	Update(w)
	H.eq(At(w, "0:1"), nil, "a secret tooltip color")
	w.secret[hidden] = nil
	Update(w)
	H.eq(At(w, "0:1"), "+77", "the same color, plain")
end)

-- The button gives 3 and 9, but the game says they are secret: a number
-- that shows would mean the code read a secret value. (No other value in
-- this world is 3 or 9.)
H.test("a secret bag ID or slot shows nothing", function()
	local w = World(true, { slots = { "3:9" } })
	w.bag["3:9"] = 102
	w.secret[3] = true
	Update(w)
	H.eq(At(w, "3:9"), nil, "a secret bag ID")
	w.secret[3] = nil
	w.secret[9] = true
	Update(w)
	H.eq(At(w, "3:9"), nil, "a secret slot")
	w.secret[9] = nil
	Update(w)
	H.eq(At(w, "3:9"), "+15", "both plain")
end)

H.test("a one-hand weapon compares with the off hand only when it holds a weapon or nothing", function()
	local w = World(true)
	w.dual = true
	w.bag["0:1"] = 136                   -- a sword of 25
	w.worn[16] = 131                      -- a sword of 20
	w.worn[17] = 134                      -- a shield of 5
	Update(w)
	H.eq(At(w, "0:1"), "+5", "beside a shield: the main hand only")
	w.worn[17] = 135                      -- a held orb of 5
	Update(w)
	H.eq(At(w, "0:1"), "+5", "beside a held item: the main hand only")
	w.worn[17] = 130                      -- a sword of 10
	Update(w)
	H.eq(At(w, "0:1"), "+15", "beside a one-hand weapon: the lower of the two")
	w.worn[17] = 137                      -- an off-hand dagger of 8
	Update(w)
	H.eq(At(w, "0:1"), "+17", "beside an off-hand weapon: the lower of the two")
	local off = Link(134)
	w.worn[17] = off
	w.secret[off] = true
	Update(w)
	H.eq(At(w, "0:1"), nil, "a secret off hand: no number")
	w.secret[off] = nil
	w.dual = false
	w.worn[17] = 137
	Update(w)
	H.eq(At(w, "0:1"), "+5", "no dual wield: the main hand only")
end)

H.test("a bow or gun in the main hand leaves no off hand; a wand does", function()
	local w = World(true)
	w.dual = true
	w.bag["0:1"] = 136                   -- a sword of 25
	w.bag["0:2"] = 134                   -- a shield of 5, the off hand empty
	w.worn[16] = 138                      -- a bow of 15
	Update(w)
	H.eq(At(w, "0:1"), "+10", "a bow: the main hand only, not the empty off hand")
	H.eq(At(w, "0:2"), nil, "a bow: no shield")
	w.worn[16] = 139                      -- a wand of 15
	Update(w)
	H.eq(At(w, "0:1"), "+25", "a wand: the empty off hand is the lower")
	H.eq(At(w, "0:2"), "+5", "a wand: a shield fits")
end)

H.test("the tooltip is built only for an item that would show a number", function()
	local w = World(true)
	w.worn[5] = 102                       -- 15
	w.bag["0:1"] = 101                   -- 10: lower
	w.bag["0:2"] = 150                   -- not gear
	Update(w)
	H.eq(w.tooltips, 0, "no tooltip for gear below what you wear, or for no gear")
	w.bag["0:1"] = 103                   -- cloth of 30 over leather of 15
	w.worn[5] = 101
	w.tooltips = 0
	Update(w)
	H.eq(w.tooltips, 0, "no tooltip for lighter armour")
	w.bag["0:1"] = 104                   -- mail of 30
	Update(w)
	H.eq(w.tooltips, 1, "one tooltip for the one that shows")
	H.eq(At(w, "0:1"), "+20")
end)

H.test("loot, a new item's data and a level up paint the open windows again", function()
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP" }) do
		local w = World(true)
		w.bag["0:1"] = 102
		w.minLevel[102] = 41
		Update(w)
		H.eq(At(w, "0:1"), nil, event .. ": not yet")
		w.minLevel[102] = 40
		w:fire(event)
		w:runTimers()
		H.eq(At(w, "0:1"), "+15", event)
	end
end)

H.test("the number is green", function()
	local w = World(true)
	w.bag["0:1"] = 102
	local color
	local b = w.buttons["0:1"]
	local make = b.CreateFontString
	b.CreateFontString = function(...)
		local fs = make(...)
		fs.SetTextColor = function(_, r, g, bl) color = { r, g, bl } end
		return fs
	end
	Update(w)
	H.eq(At(w, "0:1"), "+15")
	H.ok(color and color[1] < 0.5 and color[2] > 0.9 and color[3] < 0.5, "green")
end)

--------------------------------------------------------------------------------
-- TICK-0152 (D-037): only gear your class can wear; the stat marker
--------------------------------------------------------------------------------

H.test("the stat sum rule: a gain, a loss, a mix, no data", function()
	local w = World(true)
	local B = w.ns.Bags
	H.eq(B.StatSum({ RESISTANCE0_NAME = 36 }), 36, "a gain")
	H.eq(B.StatSum({ RESISTANCE0_NAME = -36, ITEM_MOD_STAMINA_SHORT = -2 }), -38, "a loss")
	H.eq(B.StatSum({ RESISTANCE0_NAME = 36, ITEM_MOD_STAMINA_SHORT = -1 }), 35, "a mix")
	H.eq(B.StatSum({ RESISTANCE0_NAME = 2, ITEM_MOD_STAMINA_SHORT = -2 }), 0, "a mix that sums to zero")
	H.eq(B.StatSum({}), 0, "no changes")
	H.eq(B.StatSum(nil), nil, "no data")
	H.eq(B.StatSum("36"), nil, "not a table")
	w.secret[777] = true
	H.eq(B.StatSum({ RESISTANCE0_NAME = 777 }), nil, "a secret value")
	w.secret.SECRET_KEY = true
	H.eq(B.StatSum({ SECRET_KEY = 1 }), nil, "a secret key")
	local hidden = { RESISTANCE0_NAME = 5 }
	w.secret[hidden] = true
	H.eq(B.StatSum(hidden), nil, "a secret table")
end)

H.test("DK's paladin: a mail vest with more armor over a leather vest shows the stat marker", function()
	local w = World(true)
	w.class, w.className = "PALADIN", "Paladin"
	w.worn[5] = 161                       -- Ragged Leather Vest, 31 armor
	w.bag["0:1"] = 160                   -- Rugged Mail Vest, 67 armor, same item level
	w.stats[161] = { RESISTANCE0_NAME = 31 }
	w.stats[160] = { RESISTANCE0_NAME = 67 }
	Update(w)
	H.eq(Gain(w, "0:1"), "+", "+36 Armor: a net gain")
	H.eq(At(w, "0:1"), nil, "the same item level: no number")
end)

H.test("a compare that sums to zero or less shows no stat marker; a mix that sums above zero does", function()
	local w = World(true)
	w.worn[5] = 160                       -- mail, 67 armor
	w.stats[160] = { RESISTANCE0_NAME = 67 }
	w.bag["0:1"] = 161                   -- leather, 31 armor
	w.stats[161] = { RESISTANCE0_NAME = 31 }
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "a loss")
	w.stats[161] = { RESISTANCE0_NAME = 67 }
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "no change")
	w.stats[161] = { RESISTANCE0_NAME = 60, ITEM_MOD_STAMINA_SHORT = 7 }
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "a mix that sums to zero")
	w.stats[161] = { RESISTANCE0_NAME = 60, ITEM_MOD_STAMINA_SHORT = 9 }
	Update(w)
	H.eq(Gain(w, "0:1"), "+", "a mix that sums to +2: lighter armour has no rule here")
	H.eq(At(w, "0:1"), nil, "and no number: same item level")
	w.stats[161], w.stats[160] = nil, nil
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "no stat data")
end)

H.test("the stat marker: an empty slot, rings, and a two-hand weapon over an off hand", function()
	local w = World(true)
	w.bag["0:1"] = 161                   -- a vest, nothing worn on the chest
	w.stats[161] = { RESISTANCE0_NAME = 31 }
	Update(w)
	H.eq(Gain(w, "0:1"), "+", "an empty slot: the item's own stats")
	w.stats[161] = {}
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "an empty slot, an item with no stats")

	w.worn[11], w.worn[12] = 110, 111
	w.stats[110] = { ITEM_MOD_STAMINA_SHORT = 1 }
	w.stats[111] = { ITEM_MOD_STAMINA_SHORT = 9 }
	w.stats[112] = { ITEM_MOD_STAMINA_SHORT = 5 }
	w.bag["0:2"] = 112
	Update(w)
	H.eq(Gain(w, "0:2"), "+", "a ring: a gain over one of your two")
	w.stats[110] = { ITEM_MOD_STAMINA_SHORT = 6 }
	Update(w)
	H.eq(Gain(w, "0:2"), nil, "a ring below both")

	w.worn[16], w.worn[17] = 131, 133     -- a sword and a shield
	w.stats[131] = { ITEM_MOD_STRENGTH_SHORT = 5 }
	w.stats[133] = { RESISTANCE0_NAME = 50 }
	w.stats[132] = { ITEM_MOD_STRENGTH_SHORT = 20 }
	w.bag["0:2"] = 132                   -- a two-hand axe
	Update(w)
	H.eq(Gain(w, "0:2"), nil, "+15 over the sword, but the shield's 50 goes too")
	w.stats[133] = { RESISTANCE0_NAME = 5 }
	Update(w)
	H.eq(Gain(w, "0:2"), "+", "+15 - 5: a gain")
end)

H.test("the stat marker: a secret or missing compare shows none", function()
	local w = World(true)
	w.worn[5] = 161
	w.bag["0:1"] = 160
	w.stats[161] = { RESISTANCE0_NAME = 31 }
	w.stats[160] = { RESISTANCE0_NAME = 67 }
	w.delta = { RESISTANCE0_NAME = 888 }
	w.secret[888] = true
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "a secret value in the compare")
	w.secret[888] = nil
	Update(w)
	H.eq(Gain(w, "0:1"), "+", "the same value, plain")
	w.delta = nil
	w.env.C_Item.GetItemStatDelta = function() error("not ready") end
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "a compare that throws")
	w.env.C_Item.GetItemStatDelta = nil
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "no compare API")

	local worn = Link(161)
	w.env.C_Item.GetItemStatDelta = function() return { RESISTANCE0_NAME = 36 } end
	w.worn[5] = worn
	w.secret[worn] = true
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "a secret worn link")
	w.secret[worn] = nil
	Update(w)
	H.eq(Gain(w, "0:1"), "+", "the same link, plain")
	w.red[160] = true
	Update(w)
	H.eq(Gain(w, "0:1"), nil, "red in the tooltip: you cannot wear it now")
end)

H.test("a mage sees neither marker on mail; a mage's own gear still shows", function()
	local w = World(true)
	w.class, w.className = "MAGE", "Mage"
	w.bag["0:1"] = 104                   -- a mail vest of 30, nothing worn, no red line
	w.stats[104] = { RESISTANCE0_NAME = 60 }
	Update(w)
	H.eq(At(w, "0:1"), nil, "no number on mail")
	H.eq(Gain(w, "0:1"), nil, "no stat marker on mail")
	H.eq(w.tooltips, 0, "not even a tooltip is built")
	w.bag["0:1"] = 103                   -- a cloth vest of 30
	w.stats[103] = { RESISTANCE0_NAME = 10 }
	Update(w)
	H.eq(At(w, "0:1"), "+30", "cloth")
	H.eq(Gain(w, "0:1"), "+", "cloth")
	w.bag["0:1"] = 132                   -- a two-hand axe
	Update(w)
	H.eq(At(w, "0:1"), nil, "no axe for a mage")
	w.bag["0:1"] = 133                   -- a shield
	Update(w)
	H.eq(At(w, "0:1"), nil, "no shield for a mage")
	w.bag["0:1"] = 131                   -- a one-hand sword
	Update(w)
	H.eq(At(w, "0:1"), "+20", "a sword")
	w.bag["0:1"] = 112                   -- a ring: any class
	Update(w)
	H.eq(At(w, "0:1"), "+15", "a ring")
end)

H.test("each class wears its own armour, shields and weapons", function()
	local w = World(true)
	local B = w.ns.Bags
	local function can(class, equipLoc, classID, sub)
		w.class = class
		return B.ClassCanWear(equipLoc, classID, sub)
	end
	H.eq(can("WARRIOR", "INVTYPE_CHEST", 4, 4), true, "warrior: plate")
	H.eq(can("HUNTER", "INVTYPE_CHEST", 4, 4), false, "hunter: no plate")
	H.eq(can("HUNTER", "INVTYPE_CHEST", 4, 3), true, "hunter: mail")
	H.eq(can("ROGUE", "INVTYPE_FEET", 4, 3), false, "rogue: no mail")
	H.eq(can("DRUID", "INVTYPE_FEET", 4, 2), true, "druid: leather")
	H.eq(can("PRIEST", "INVTYPE_HAND", 4, 2), false, "priest: no leather")
	H.eq(can("WARLOCK", "INVTYPE_CLOAK", 4, 1), true, "a cloak: any class")
	H.eq(can("SHAMAN", "INVTYPE_SHIELD", 4, 6), true, "shaman: a shield")
	H.eq(can("ROGUE", "INVTYPE_SHIELD", 4, 6), false, "rogue: no shield")
	H.eq(can("PRIEST", "INVTYPE_HOLDABLE", 4, 0), true, "a held item: any class")
	H.eq(can("PRIEST", "INVTYPE_RANGEDRIGHT", 2, 19), true, "priest: a wand")
	H.eq(can("WARRIOR", "INVTYPE_RANGEDRIGHT", 2, 19), false, "warrior: no wand")
	H.eq(can("PALADIN", "INVTYPE_WEAPON", 2, 15), false, "paladin: no dagger")
	H.eq(can("ROGUE", "INVTYPE_WEAPON", 2, 15), true, "rogue: a dagger")
	H.eq(can("MAGE", "INVTYPE_2HWEAPON", 2, 20), true, "a fishing pole: any class")
	H.eq(can("DRUID", "INVTYPE_2HWEAPON", 2, 6), true, "druid: a polearm")
	H.eq(can("MAGE", "INVTYPE_FINGER", 4, 0), true, "a ring: any class")
	H.eq(can(nil, "INVTYPE_FINGER", 4, 0), false, "the game names no class: nothing")
	H.eq(can("DEMONHUNTER", "INVTYPE_FINGER", 4, 0), false, "a class HUDini does not know: nothing")
	w.secret.PRIEST = true
	H.eq(can("PRIEST", "INVTYPE_FINGER", 4, 0), false, "a secret class: nothing")
end)

H.test("the stat marker is gold, bottom left; off hides it", function()
	local w = World(false)
	w.bag["0:1"] = 161
	w.stats[161] = { RESISTANCE0_NAME = 31 }
	w.levelOf = { [161] = 0 }             -- no item level: the stat marker alone
	w.env.HUDiniDB.showBagUpgrades = true
	local color
	local b = w.buttons["0:1"]
	local make = b.CreateFontString
	b.CreateFontString = function(...)
		local fs = make(...)
		fs.SetTextColor = function(_, r, g, bl) color = { r, g, bl } end
		return fs
	end
	w.ns.UpdateModules()
	H.eq(Gain(w, "0:1"), "+")
	H.eq(At(w, "0:1"), nil, "no number")
	H.ok(color and color[1] > 0.9 and color[2] > 0.7 and color[3] < 0.2, "gold, not the number's green")
	for _, f in ipairs(w.frames) do
		if f.__h.parent == b then
			local point, to, rel = f:GetPoint(1)
			H.eq(point, "BOTTOMLEFT")
			H.ok(to == b, "on the button")
			H.eq(rel, "BOTTOMLEFT")
		end
	end
	w.env.HUDiniDB.showBagUpgrades = false
	w.ns.UpdateModules()
	H.eq(Gain(w, "0:1"), nil, "off: hidden")
end)
