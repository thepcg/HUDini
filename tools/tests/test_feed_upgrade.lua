-- The "+N ilvl" hint on a loot line (TICK-0109): only for gear you can wear
-- now. The game's tooltip paints red what stops you (an armour type you have
-- not learned, a weapon skill, the level); HUDini reads that red. Armour
-- lighter than the type you wear in that slot gets no hint.

-- Item ID -> name, armour subclass (1 cloth .. 4 plate, nil for a weapon),
-- the slot kind and the item level.
local ITEMS = {
	[101] = { "Flimsy Chain Vest", 3, "INVTYPE_CHEST", 10 },
	[102] = { "Rugged Leather Vest", 2, "INVTYPE_CHEST", 10 },
	[103] = { "Linen Shirt Vest", 1, "INVTYPE_CHEST", 10 },
	[104] = { "Worn Leather Vest", 2, "INVTYPE_CHEST", 5 },     -- worn now
	[105] = { "Heavy Axe", nil, "INVTYPE_2HWEAPON", 10 },
}
local function Link(id) return ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(id, ITEMS[id][1]) end
local function IdOf(link) return tonumber(tostring(link):match("item:(%d+)")) end

local RED = { r = 1, g = 0.125, b = 0.125 }
local WHITE = { r = 1, g = 1, b = 1 }

-- A shaman at w.level with the feed's hint on, in the leather vest.
-- w.cannot[id] = true: the tooltip paints that item's type red.
-- w.secret[color] = true: issecretvalue calls that color secret.
local function UpgradeWorld(level)
	local w = H.world()
	w.class, w.className, w.level = "SHAMAN", "Shaman", level
	w.cannot, w.secret = {}, {}
	w.env.LOOT_ITEM_SELF = "You receive loot: %s."
	w.env.HUDiniDB = { feedUpgrade = true }
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	local C_Item = w.env.C_Item
	C_Item.GetItemInfo = function(item)
		local id = type(item) == "number" and item or IdOf(item)
		local it = id and ITEMS[id]
		if not it then return end
		return it[1], Link(id), 2, it[4], 1, "", "", 1, it[3], 134, 0, it[2] and 4 or 2, it[2] or 1
	end
	C_Item.GetItemIconByID = function() return 134 end
	C_Item.GetDetailedItemLevelInfo = function(link)
		local id = IdOf(link)
		return id and ITEMS[id] and ITEMS[id][4]
	end
	w.env.GetInventoryItemLink = function(_, slot) if slot == 5 then return Link(104) end end
	w.env.C_TooltipInfo = { GetHyperlink = function(link)
		local id = IdOf(link)
		local color = w.color or (w.cannot[id] and RED or WHITE)
		return { lines = {
			{ leftText = ITEMS[id][1], leftColor = WHITE },
			{ leftText = "Chest", leftColor = WHITE, rightText = "Mail", rightColor = color },
		} }
	end }
	w:loadAddon()
	w.time = w.time + 10                       -- past the quiet time after login
	local F, shown = w.ns.Feed, {}
	local Line = F.Line
	F.Line = function(spec)
		local L = Line(spec)
		if L then shown[#shown + 1] = L end
		return L
	end
	w.shown = shown
	return w
end

-- Loot item id; the text its line reads.
local function Loot(w, id)
	local n = #w.shown
	w:fire("CHAT_MSG_LOOT", "You receive loot: " .. Link(id) .. ".")
	local L = w.shown[n + 1]
	H.ok(L ~= nil, "a loot line for " .. ITEMS[id][1])
	local text = L.text
	if type(text) == "function" then text = text(L) end
	return text
end

local function Hint(text) return text:match("%+(%d+) ilvl") end

H.test("a shaman below the mail level gets no upgrade hint for mail", function()
	local w = UpgradeWorld(10)
	w.cannot[101] = true
	H.eq(Hint(Loot(w, 101)), nil, "mail, painted red by the game")
	H.eq(Hint(Loot(w, 102)), "5", "leather of a higher item level")
end)

H.test("the same mail gets the hint once the game lets the shaman wear it", function()
	local w = UpgradeWorld(40)
	H.eq(Hint(Loot(w, 101)), "5", "mail, not red: a heavier type than the leather worn")
end)

H.test("armour lighter than the type you wear there gets no hint", function()
	local w = UpgradeWorld(40)
	H.eq(Hint(Loot(w, 103)), nil, "cloth over leather")
end)

H.test("a weapon the game paints red gets no hint; one it does not, gets it", function()
	local w = UpgradeWorld(10)
	w.cannot[105] = true
	H.eq(Hint(Loot(w, 105)), nil, "an axe you have not learned")
	w.cannot[105] = nil
	H.eq(Hint(Loot(w, 105)), "10", "learned: better than the empty hand")
end)

H.test("a tooltip not loaded yet (the name line only): no hint", function()
	local w = UpgradeWorld(40)
	w.env.C_TooltipInfo = { GetHyperlink = function() return { lines = { { leftText = "Rugged Leather Vest", leftColor = WHITE } } } end }
	H.eq(Hint(Loot(w, 102)), nil)
end)

H.test("no tooltip from the game: no hint", function()
	local w = UpgradeWorld(40)
	w.env.C_TooltipInfo = nil
	H.eq(Hint(Loot(w, 102)), nil)
	w.env.C_TooltipInfo = { GetHyperlink = function() error("not ready") end }
	H.eq(Hint(Loot(w, 102)), nil, "a tooltip call that throws")
end)

-- TICK-0110 method: the secret is the value that WOULD pass (white, "you can
-- wear it"), so the test fails if the IsSecret guard is taken out.
H.test("a secret tooltip color: no hint, no error", function()
	local w = UpgradeWorld(40)
	-- Three channels that differ, so a secret one marks that channel alone.
	local hidden = { r = 0.95, g = 0.96, b = 0.97 }
	w.color = hidden
	w.secret[hidden] = true
	H.eq(Hint(Loot(w, 102)), nil, "a secret color table")
	w.secret[hidden] = nil
	for _, ch in ipairs({ "r", "g", "b" }) do
		w.secret[hidden[ch]] = true
		H.eq(Hint(Loot(w, 102)), nil, "a secret " .. ch .. " channel")
		w.secret[hidden[ch]] = nil
	end
	H.eq(Hint(Loot(w, 102)), "5", "the same color, plain: the hint shows")
end)
