-- The "+N ilvl" hint on a loot line (TICK-0109): only for gear you can wear
-- now. The game's tooltip paints red what stops you (an armour type you have
-- not learned, a weapon skill, the level); HUDini reads that red. Armour
-- lighter than the type you wear in that slot gets no hint.

-- Item ID -> name, armour subclass (1 cloth .. 4 plate, nil for a weapon),
-- the slot kind, the item level, and a weapon's subclass (2 bow, 3 gun,
-- 19 wand; 1 when not given).
local ITEMS = {
	[101] = { "Flimsy Chain Vest", 3, "INVTYPE_CHEST", 10 },
	[102] = { "Rugged Leather Vest", 2, "INVTYPE_CHEST", 10 },
	[103] = { "Linen Shirt Vest", 1, "INVTYPE_CHEST", 10 },
	[104] = { "Worn Leather Vest", 2, "INVTYPE_CHEST", 5 },     -- worn now
	[105] = { "Heavy Axe", nil, "INVTYPE_2HWEAPON", 10 },
	[106] = { "Iron Mace", nil, "INVTYPE_WEAPON", 30 },
	[107] = { "Oak Shield", nil, "INVTYPE_SHIELD", 20 },
	[108] = { "Bronze Mace", nil, "INVTYPE_WEAPON", 25 },
	[109] = { "Short Bow", nil, "INVTYPE_RANGED", 30, 2 },
	[110] = { "Worn Buckler", nil, "INVTYPE_SHIELD", 15 },
	[111] = { "Tin Dagger", nil, "INVTYPE_WEAPON", 20 },
	[112] = { "Old Gun", nil, "INVTYPE_RANGEDRIGHT", 30, 3 },
	[113] = { "Ash Wand", nil, "INVTYPE_RANGEDRIGHT", 30, 19 },
	[114] = { "Parrying Dagger", nil, "INVTYPE_WEAPONOFFHAND", 20 },
	[115] = { "Apprentice Staff", nil, "INVTYPE_2HWEAPON", 30, 10 },
	[116] = { "Kite Shield", 6, "INVTYPE_SHIELD", 30 },       -- armour, subclass 6 shield
	[117] = { "Bulky Plate Vest", 4, "INVTYPE_CHEST", 10 },
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
		return it[1], Link(id), 2, it[4], 1, "", "", 1, it[3], 134, 0, it[2] and 4 or 2, it[2] or it[5] or 1
	end
	C_Item.GetItemIconByID = function() return 134 end
	C_Item.GetDetailedItemLevelInfo = function(link)
		local id = IdOf(link)
		return id and ITEMS[id] and ITEMS[id][4]
	end
	w.worn = { [5] = 104 }
	w.env.GetInventoryItemLink = function(_, slot) local id = w.worn[slot]; return id and Link(id) end
	w.env.CanDualWield = function() return w.dual == true end
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

-- TICK-0149: a one-hand weapon is compared with the off hand only when the
-- off hand is empty or holds a weapon; a bow, gun or crossbow in the main
-- hand leaves no off hand.

H.test("a shield in the off hand: a one-hand weapon is compared with the main hand only", function()
	local w = UpgradeWorld(40)
	w.dual = true
	w.worn[16], w.worn[17] = 106, 107                    -- a mace at 30, a shield at 20
	H.eq(Hint(Loot(w, 108)), nil, "a mace at 25: below the main hand, so no hint")
	w.worn[17] = 111                                     -- a dagger at 20 in the off hand
	H.eq(Hint(Loot(w, 108)), "5", "a weapon in the off hand: the lower one counts")
	w.worn[17] = nil
	H.eq(Hint(Loot(w, 108)), "25", "an empty off hand counts as 0")
end)

H.test("a bow or gun in the main hand leaves no off hand to compare with", function()
	for _, ranged in ipairs({ 109, 112 }) do
		local w = UpgradeWorld(40)
		w.worn[16] = ranged
		H.eq(Hint(Loot(w, 110)), nil, ITEMS[ranged][1] .. ": a shield is not compared with an empty off hand")
	end
end)

H.test("a two-hand weapon in the main hand leaves no off hand to compare with", function()
	local w = UpgradeWorld(40)
	w.dual = true
	w.worn[16] = 105                                     -- a two-hand axe at 10
	H.eq(Hint(Loot(w, 110)), nil, "a shield: no hint")
	H.eq(Hint(Loot(w, 108)), "15", "a mace at 25: compared with the axe only, not the empty off hand")
end)

H.test("an off-hand weapon in the off hand counts as a weapon to compare with", function()
	local w = UpgradeWorld(40)
	w.dual = true
	w.worn[16], w.worn[17] = 106, 114                    -- a mace at 30, an off-hand dagger at 20
	H.eq(Hint(Loot(w, 108)), "5", "a mace at 25: the lower of the two counts")
end)

H.test("a wand in the main hand leaves the off hand free (D-036)", function()
	local w = UpgradeWorld(40)
	w.worn[16] = 113
	H.eq(Hint(Loot(w, 110)), "15", "a shield beside a wand: better than the empty off hand")
end)

-- TICK-0153 (D-037): the feed uses the bags' class table, so a class never
-- gets the hint on gear it can never wear, even when the tooltip has no red
-- line (DK: "do not light up a mail chest piece for a mage").

H.test("a mage gets no hint on mail, plate, a shield or an axe; cloth and a staff, yes", function()
	local w = UpgradeWorld(40)
	w.class, w.className = "MAGE", "Mage"
	w.worn[5] = nil                                      -- an empty chest
	H.eq(Hint(Loot(w, 101)), nil, "mail, with no red line in the tooltip")
	H.eq(Hint(Loot(w, 117)), nil, "plate")
	H.eq(Hint(Loot(w, 116)), nil, "a shield")
	H.eq(Hint(Loot(w, 105)), nil, "a two-hand axe")
	H.eq(Hint(Loot(w, 103)), "10", "cloth")
	H.eq(Hint(Loot(w, 115)), "30", "a staff")
end)

H.test("a warrior gets the hint on plate, mail, a shield and a staff", function()
	local w = UpgradeWorld(40)
	w.class, w.className = "WARRIOR", "Warrior"
	H.eq(Hint(Loot(w, 117)), "5", "plate over leather")
	H.eq(Hint(Loot(w, 101)), "5", "mail over leather")
	H.eq(Hint(Loot(w, 116)), "30", "a shield, off hand empty")
	H.eq(Hint(Loot(w, 115)), "30", "a staff, hands empty")
	H.eq(Hint(Loot(w, 113)), nil, "a wand: no wand for a warrior")
end)

H.test("a class the game will not name: no hint", function()
	local w = UpgradeWorld(40)
	w.class, w.className = nil, nil
	H.eq(Hint(Loot(w, 102)), nil)
end)

-- A game started before Bags.lua was in the .toc and then reloaded has no
-- ns.Bags: the hint keeps its old rules (the red tooltip line) and throws
-- nothing.
H.test("no bag module loaded: the old hint rules, no error", function()
	local w = UpgradeWorld(40)
	w.class, w.className = "MAGE", "Mage"
	w.worn[5] = nil
	w.ns.Bags = nil
	H.eq(Hint(Loot(w, 101)), "10", "mail, no red line: the class table is not there to stop it")
	w.cannot[117] = true
	H.eq(Hint(Loot(w, 117)), nil, "plate painted red: the tooltip still stops it")
end)
