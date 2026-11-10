-- FeedLoot.lua when the game hides an answer (TICK-0112). Each test first
-- runs the value that WOULD change the feed, plain, and checks that it does.
-- Then it flags that same value secret and checks that the feed does what it
-- does for no answer, and throws nothing. So a missing Plain() fails the
-- test (the method of TICK-0110). Each flagged value is used for nothing
-- else in its test.

-- Item ID -> name, the level to wear it, the stack size, the slot kind.
local ITEMS = {
	[105] = { "Heavy Axe", 30, 1, "INVTYPE_2HWEAPON" },
	[2589] = { "Linen Cloth", 1, 20, "" },
}
local function Link(id) return ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(id, ITEMS[id][1]) end
local function IdOf(link) return tonumber(tostring(link):match("item:(%d+)")) end
local BADGE = "|cffffffff|Hcurrency:61|h[Badge]|h|r"

local WHITE = { r = 1, g = 1, b = 1 }

-- A logged-in world with the feed on and its upgrade hint on. w.secret:
-- the values issecretvalue calls secret. w.have: the bag count.
-- w.loot: the loot window's slots, { link, qty, currencyID }.
local function World()
	local w = H.world()
	w.secret, w.loot = {}, {}
	for k, v in pairs({
		LOOT_ITEM_SELF = "You receive loot: %s.",
		CURRENCY_GAINED = "You receive currency: %s.",
		TRADESKILL_LOG_FIRSTPERSON = "You create %s.",
	}) do w.env[k] = v end
	w.env.HUDiniDB = { feedUpgrade = true, feedNewLook = false, feedValue = false }
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	local C_Item = w.env.C_Item
	C_Item.GetItemInfo = function(item)
		local id = type(item) == "number" and item or IdOf(item)
		local it = id and ITEMS[id]
		if not it then return end
		return it[1], Link(id), 2, 10, it[2], "", "", it[3], it[4], 134, 0, 2, 1
	end
	C_Item.GetItemIconByID = function() return 134 end
	C_Item.GetDetailedItemLevelInfo = function() return 10 end
	C_Item.GetItemCount = function() return w.have end
	w.env.C_TooltipInfo = { GetHyperlink = function(link)
		return { lines = {
			{ leftText = ITEMS[IdOf(link)][1], leftColor = WHITE },
			{ leftText = "Two-Hand", leftColor = WHITE },
		} }
	end }
	w.env.C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = w.quantity } end }
	w.env.GetNumLootItems = function() return w.slots or #w.loot end
	w.env.GetLootSlotLink = function(i) return w.loot[i] and w.loot[i][1] end
	w.env.GetLootSlotInfo = function(i)
		local s = w.loot[i]
		if s then return 134, "", s[2], s[3] end
	end
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
	-- A chat line, as the game sends it: arg12 is the sender's GUID.
	function w:Chat(event, msg, guid)
		self:fire(event, msg, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
		self:runTimers()
		return self.shown[#self.shown]
	end
	-- Open the loot window and take slot.
	function w:Take(slot)
		self:fire("LOOT_READY")
		self:fire("LOOT_SLOT_CLEARED", slot)
		self:runTimers()
		return self.shown[#self.shown]
	end
	return w
end

local function Text(L)
	local text = L.text
	if type(text) == "function" then text = text(L) end
	return text
end

--------------------------------------------------------------------------------
-- The loot line's extras
--------------------------------------------------------------------------------

H.test("a secret level does not hide gear above it", function()
	local w = World()
	w.level = 23
	local L = w:Chat("CHAT_MSG_LOOT", "You receive loot: " .. Link(105) .. ".")
	H.eq(Text(L):match("%+(%d+) ilvl"), nil, "plain: level 30 gear, no hint at 23")
	w.secret[23] = true
	L = w:Chat("CHAT_MSG_LOOT", "You receive loot: " .. Link(105) .. ".")
	H.eq(Text(L):match("%+(%d+) ilvl"), "10", "secret: the level is not known to be too low")
end)

H.test("a secret bag count shows no count", function()
	local w = World()
	w.have = 7
	local L = w:Chat("CHAT_MSG_LOOT", "You receive loot: " .. Link(2589) .. ".")
	w:runTimers()
	H.eq(L.have, 7, "plain: 7 in the bags")
	w = World()
	w.have, w.secret[7] = 7, true
	L = w:Chat("CHAT_MSG_LOOT", "You receive loot: " .. Link(2589) .. ".")
	for _ = 1, 4 do w:runTimers() end
	H.eq(L.have, nil, "secret: none")
end)

H.test("a secret currency count shows no count", function()
	local w = World()
	w.quantity = 37
	local L = w:Chat("CHAT_MSG_CURRENCY", "You receive currency: " .. BADGE .. ".")
	H.eq(L.have, 37, "plain: 37 held")
	w = World()
	w.quantity, w.secret[37] = 37, true
	L = w:Chat("CHAT_MSG_CURRENCY", "You receive currency: " .. BADGE .. ".")
	H.eq(L.have, nil, "secret: none")
end)

--------------------------------------------------------------------------------
-- The loot window
--------------------------------------------------------------------------------

H.test("a secret slot count reads no slots", function()
	local w = World()
	w.loot = { { Link(2589), 4 }, { Link(2589), 4 }, { Link(2589), 4 } }
	H.ok(w:Take(2), "plain: slot 2 shows")
	w = World()
	w.loot = { { Link(2589), 4 }, { Link(2589), 4 }, { Link(2589), 4 } }
	w.slots, w.secret[3] = 3, true
	H.eq(w:Take(2), nil, "secret: nothing")
end)

H.test("a secret slot link is no slot", function()
	local w = World()
	w.loot = { { Link(2589), 4 } }
	H.ok(w:Take(1), "plain: it shows")
	w = World()
	w.loot = { { Link(2589), 4 } }
	w.secret[Link(2589)] = true
	H.eq(w:Take(1), nil, "secret: nothing")
end)

H.test("a secret slot count of items counts one", function()
	local w = World()
	w.loot = { { Link(2589), 4 } }
	H.eq(w:Take(1).count, 4, "plain: 4")
	w = World()
	w.loot = { { Link(2589), 4 } }
	w.secret[4] = true
	H.eq(w:Take(1).count, 1, "secret: 1")
end)

H.test("a secret slot currency reads as an item", function()
	local w = World()
	w.loot = { { Link(2589), 3, 61 } }
	H.ok(w:Take(1).key:find("^cur:"), "plain: a currency line")
	w = World()
	w.loot = { { Link(2589), 3, 61 } }
	w.secret[61] = true
	H.ok(w:Take(1).key:find("^loot:"), "secret: an item line")
end)

H.test("a secret slot taken is no slot", function()
	local w = World()
	w.loot = { { Link(2589), 4 }, { Link(2589), 4 } }
	H.ok(w:Take(2), "plain: slot 2 shows")
	w = World()
	w.loot = { { Link(2589), 4 }, { Link(2589), 4 } }
	w:fire("LOOT_READY")
	w.secret[2] = true
	w:fire("LOOT_SLOT_CLEARED", 2)
	w:runTimers()
	H.eq(w.shown[1], nil, "secret: nothing")
end)

--------------------------------------------------------------------------------
-- Secret chat lines
--------------------------------------------------------------------------------

-- Two GUIDs that are equal (==) but each its own value, so one can be
-- flagged secret and the other not.
local GUID = { __eq = function(a, b) return a.id == b.id end }
local function Guid() return setmetatable({ id = "Player-1-0001" }, GUID) end

local function LootFrom(w, sender, mine)
	w.env.UnitGUID = function(unit) if unit == "player" then return mine end end
	local msg = "You receive loot: " .. Link(2589) .. "."
	w.secret[msg] = true
	return w:Chat("CHAT_MSG_LOOT", msg, sender), msg
end

H.test("a secret loot line shows as it came", function()
	local w = World()
	local L = w:Chat("CHAT_MSG_LOOT", "You receive loot: " .. Link(2589) .. ".")
	H.eq(L.raw, nil, "plain: read")
	local me = Guid()
	local msg
	L, msg = LootFrom(w, me, me)
	H.eq(L.raw, msg, "secret: as it came")
end)

H.test("a secret sender GUID is not you", function()
	local w = World()
	H.ok(LootFrom(w, Guid(), Guid()), "plain: from you")
	w = World()
	local from = Guid()
	w.secret[from] = true
	H.eq(LootFrom(w, from, Guid()), nil, "secret: from someone")
end)

-- Its plain case, "from you", is the first half of the test above.
H.test("a secret GUID of yours is not the sender", function()
	local w = World()
	local me = Guid()
	w.secret[me] = true
	H.eq(LootFrom(w, Guid(), me), nil, "secret: not known to be you")
end)

H.test("a secret currency line shows as it came", function()
	local w = World()
	local msg = "You receive currency: " .. BADGE .. "."
	H.eq(w:Chat("CHAT_MSG_CURRENCY", msg).raw, nil, "plain: read")
	w.secret[msg] = true
	H.eq(w:Chat("CHAT_MSG_CURRENCY", msg).raw, msg, "secret: as it came")
end)

H.test("a secret craft line shows nothing", function()
	local w = World()
	H.ok(w:Chat("CHAT_MSG_TRADESKILLS", "You create Light Leather."), "plain: made")
	w = World()
	w.secret["You create Light Leather."] = true
	H.eq(w:Chat("CHAT_MSG_TRADESKILLS", "You create Light Leather."), nil, "secret: may be someone else's")
end)

H.test("a secret reputation line shows as it came", function()
	local w = World()
	H.eq(w:Chat("CHAT_MSG_COMBAT_FACTION_CHANGE", "Odd faction news.").raw, nil, "plain: read")
	w.secret["Odd faction news."] = true
	H.eq(w:Chat("CHAT_MSG_COMBAT_FACTION_CHANGE", "Odd faction news.").raw, "Odd faction news.", "secret")
end)

H.test("a secret skill line shows as it came", function()
	local w = World()
	H.eq(w:Chat("CHAT_MSG_SKILL", "Odd skill news.").raw, nil, "plain: read")
	w.secret["Odd skill news."] = true
	H.eq(w:Chat("CHAT_MSG_SKILL", "Odd skill news.").raw, "Odd skill news.", "secret")
end)
