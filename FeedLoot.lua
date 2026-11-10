--[[--------------------------------------------------------------------------
	HUDini - Feed: loot, currency, crafts, reputation, skill-ups

	All of these come from chat events that also carry other people's lines
	("Osmandes creates Light Leather"), so only lines that match one of
	Blizzard's own "you" strings (LOOT_ITEM_SELF and kin) pass.

	A loot line can carry extras, each with its own switch:

		x3 (47)      the count, then how many are now in your bags
		12s          what the stack sells for at a vendor
		New look     an appearance you have not collected yet
		+8 ilvl      better than what you wear (a hint, off by default)

	Secrets: in 12.x a chat line can arrive secret, mostly in instances. A
	secret cannot be matched. For loot there are two ways round it:

	  - The loot window. Each slot you take is noted, and when no readable
	    chat line names it within half a second, the slot itself is shown.
	  - The chat line's sender. When it is plainly you, the secret line goes
	    to the screen as it came, unless the loot window already covered it.

	Rep, skill and currency lines are always about you, so a secret one is
	shown as it came.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local Text = ns.Text

local Plain = ns.Plain
local Number = ns.Number
local F = ns.Feed

-- A module of its own (Modules.lua), on with the feed: while the feed is
-- off it has no events and no timers.
local M = ns.NewModule("feedLoot", { label = "Feed (loot, crafts, reputation)", setting = "showFeed" }) -- locale: skip a debug name (/hud debug modules)
local C = F.COLOR

local NEW_LOOK = "|cffff80ff" .. Text("feed.newLook") .. "|r"

-- One "New look" per item (TICK-0059). When you loot gear with a look you
-- lack, the game may also add the look to your collection, and FeedWatch.lua
-- hears that as a second "New look". The loot line keeps it: the
-- collection's line joins a fresh loot line for the same item, in either
-- order. lootLines[itemID] is the loot line each item showed last; weak, so
-- a line that is gone is not kept.
local lootLines = setmetatable({}, { __mode = "v" })
local LOOK_WINDOW = 5   -- seconds a loot line can still take its look

local function ItemID(link) return tonumber(link:match("item:(%d+)")) end
local function CurrencyID(link) return tonumber(link:match("currency:(%d+)")) end

-- name, link, quality, ilvl, minLevel, type, subType, maxStack, equipLoc,
-- icon, sellPrice, classID, subClassID
local function Info(link)
	if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(link) end
	return GetItemInfo(link)
end

local function ItemLevel(link)
	if C_Item and C_Item.GetDetailedItemLevelInfo then return C_Item.GetDetailedItemLevelInfo(link) end
	return GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)
end

--------------------------------------------------------------------------------
-- Extras
--------------------------------------------------------------------------------

local PROJECTILE = 6   -- Enum.ItemClass.Projectile: arrows, bullets

-- False when the game says item can never be a look (TICK-0123): ammo,
-- or an item the game cannot dress you in. On Forever the collection told
-- of a new look for Rough Arrow, so its word alone is not enough. True
-- when nothing says no: an answer the client does not give, or gives as
-- a secret, rules nothing out. item: an item ID or link.
function F.CanBeLook(item)
	if not item then return true end
	local Instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	if Instant then
		local ok, _, _, _, equipLoc, _, classID = pcall(Instant, item)
		local ammoClass = Enum and Enum.ItemClass and Enum.ItemClass.Projectile or PROJECTILE
		if ok and (Plain(equipLoc) == "INVTYPE_AMMO" or Plain(classID) == ammoClass) then return false end
	end
	if C_Item and C_Item.IsDressableItemByID then
		local ok, dressable = pcall(C_Item.IsDressableItemByID, item)
		if ok and Plain(dressable) == false then return false end
	end
	return true
end

-- True for gear whose look you can learn and have not.
local function NewLook(link)
	if not F.CanBeLook(link) then return false end
	local T = C_TransmogCollection
	if not (T and T.GetItemInfo) then return false end
	local ok, _, sourceID = pcall(T.GetItemInfo, link)
	if not (ok and sourceID) then return false end
	local ok2, _, canCollect = pcall(T.PlayerCanCollectSource, sourceID)
	if not (ok2 and canCollect) then return false end
	local ok3, info = pcall(T.GetAppearanceInfoBySource, sourceID)
	if ok3 and type(info) == "table" and info.appearanceIsCollected ~= nil then
		return not info.appearanceIsCollected
	end
	if T.PlayerHasTransmogByItemInfo then
		local ok4, has = pcall(T.PlayerHasTransmogByItemInfo, link)
		if ok4 then return not has end
	end
	return false
end

-- Where each kind of gear goes.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}

-- Armour slots that take one armour type: cloth, leather, mail or plate.
local ARMOR_SLOTS = {
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
	INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true,
	INVTYPE_HAND = true,
}
local ARMOR_CLASS = 4   -- Enum.ItemClass.Armor; subclass 1 cloth, 2 leather, 3 mail, 4 plate

-- The armour type (1-4) of link, or 0 for none.
local function ArmorType(link)
	if not link then return 0 end
	local classID, subClassID = select(12, Info(link))
	if classID == ARMOR_CLASS and subClassID and subClassID >= 1 and subClassID <= 4 then return subClassID end
	return 0
end

-- The game's red text (RED_FONT_COLOR, 1 / 0.125 / 0.125). Nil when the
-- game hides the color.
local function IsRed(color)
	if color == nil then return false end
	if ns.IsSecret(color) then return nil end
	local ok, r, g, b = pcall(function() return color.r, color.g, color.b end)
	if not ok or ns.IsSecret(r) or ns.IsSecret(g) or ns.IsSecret(b) then return nil end
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
	return r > 0.9 and g < 0.3 and b < 0.3
end

-- True when you can wear link now, by the game's own answer: its tooltip
-- paints red what stops you (an armour or weapon type you have not learned,
-- the level, the class). Nil when the game will not say; then no hint shows
-- (TICK-0109: a shaman below the mail level saw "+5 ilvl" on mail).
local function Wearable(link)
	local T = C_TooltipInfo
	if not (T and T.GetHyperlink) then return nil end
	local ok, data = pcall(T.GetHyperlink, link)
	if not (ok and type(data) == "table") then return nil end
	local okLines, rows = pcall(function() return data.lines end)
	if not (okLines and type(rows) == "table") then return nil end
	-- Gear always has its name and its slot line; fewer is a tooltip the
	-- game has not loaded yet, which may still lack the red line.
	if #rows < 2 then return nil end
	for _, row in ipairs(rows) do
		local okRow, left, right = pcall(function() return row.leftColor, row.rightColor end)
		if not okRow then return nil end
		local redLeft, redRight = IsRed(left), IsRed(right)
		if redLeft == nil or redRight == nil then return nil end
		if redLeft or redRight then return false end
	end
	return true
end

-- How many item levels better than what you wear, or nil. Only for gear you
-- can wear now, and armour of the type you wear in that slot or a heavier
-- one: leather is no upgrade to a shaman in mail.
local function Upgrade(link)
	local _, _, _, _, minLevel, _, _, _, equipLoc = Info(link)
	local slots = equipLoc and SLOTS[equipLoc]
	if not slots then return end
	local myLevel = Plain(UnitLevel("player"))
	if minLevel and myLevel and minLevel > myLevel then return end
	if not Wearable(link) then return end
	if ARMOR_SLOTS[equipLoc] then
		local kind = ArmorType(link)
		if kind > 0 and kind < ArmorType(GetInventoryItemLink("player", slots[1])) then return end
	end
	local ilvl = ItemLevel(link)
	if not ilvl then return end

	local mainHand = GetInventoryItemLink("player", 16)
	local twoHanded = mainHand and select(9, Info(mainHand)) == "INVTYPE_2HWEAPON"
	local worst
	for _, slot in ipairs(slots) do
		local fits = true
		if slot == 17 then
			if twoHanded then fits = false end
			if equipLoc == "INVTYPE_WEAPON" and not (CanDualWield and CanDualWield()) then fits = false end
		end
		if fits then
			local have = GetInventoryItemLink("player", slot)
			local level = have and ItemLevel(have) or 0
			if not worst or level < worst then worst = level end
		end
	end
	if worst and ilvl > worst then return ilvl - worst end
end

--------------------------------------------------------------------------------
-- How an item or currency line reads
--------------------------------------------------------------------------------

-- A loot line that takes the collection's look: the tag, and the big
-- highlight the collection's own line would have had (designer, TICK-0059).
-- A line that is big already (epic loot) had its highlight.
local function TakeTag(L)
	if L.tag ~= NEW_LOOK then
		L.tag = NEW_LOOK
		F.Refresh(L)
	end
	if not L.big then
		L.big = true
		F.Highlight({ icon = L.icon, color = C.collection, line = L })
	end
end

-- The collection just learned the look of itemID (FeedWatch.lua). True if a
-- fresh loot line for that item takes it, with the "New look" tag: then the
-- collection shows no line of its own. With the tag off, the collection's
-- line is the only "New look", so nothing joins.
function F.JoinLook(itemID)
	local L = itemID and lootLines[itemID]
	if not (L and L.alive and HUDiniDB.feedNewLook) then return false end
	if GetTime() - L.updated > LOOK_WINDOW then return false end
	TakeTag(L)
	return true
end

function F.LootText(L)
	local db = HUDiniDB
	local s = (L.prefix or "") .. L.link
	if L.count and L.count > 1 then s = s .. " x" .. L.count end
	if db.feedBagCount and L.have then s = s .. F.Gray(" (" .. Number(L.have) .. ")") end
	if L.tag then s = s .. " " .. L.tag end
	if L.upgrade then s = s .. (" |cff40ff40+%d ilvl|r"):format(L.upgrade) end
	if db.feedValue and L.price and L.price > 0 then
		s = s .. "  " .. F.Coins(L.price * (L.count or 1))
	end
	return s
end

-- The extras that need the item's data, which may not be loaded yet.
local function Dress(L, link)
	local db = HUDiniDB
	local _, _, quality, _, _, _, _, maxStack, _, _, price = Info(link)
	if quality == nil then return false end
	L.quality = quality
	L.stacks = maxStack and maxStack > 1
	if price and price > 0 then L.price = price end
	if db.feedNewLook and NewLook(link) then L.tag = NEW_LOOK end
	if db.feedUpgrade then L.upgrade = Upgrade(link) end
	return true
end

-- One item line. how: kind ("loot" or "craft"), prefix ("Made ").
local function ShowItem(link, count, how)
	local db = HUDiniDB
	count = tonumber(count) or 1
	local id = ItemID(link)
	if id and db.feedIgnore and db.feedIgnore[id] then return end

	local quality = select(3, Info(link))
	if quality == nil and id and C_Item and C_Item.GetItemQualityByID then
		quality = C_Item.GetItemQualityByID(id)
	end
	if db.feedHideGray and quality == 0 then return end

	local spec = {
		kind = how.kind, key = how.kind .. ":" .. link, link = link, count = count,
		prefix = how.prefix, icon = F.IconFor(link), text = F.LootText,
	}
	local loaded = Dress(spec, link)
	if loaded and (spec.quality or 0) >= 4 then spec.big = true end

	local L = F.Line(spec)
	if not L then return end
	if loaded and spec.price then F.Count("value", spec.price * count) end

	-- The collection learned this look a moment ago and waits to show it:
	-- this line takes it instead (F.JoinLook, the other order).
	if id then
		lootLines[id] = L
		if db.feedNewLook and F.TakeLook and F.TakeLook(id) then TakeTag(L) end
	end

	-- Not loaded yet: fill the extras in when it is.
	if not loaded and Item and Item.CreateFromItemLink then
		local item = Item:CreateFromItemLink(link)
		if item and not item:IsItemEmpty() then
			item:ContinueOnItemLoad(function()
				if Dress(L, link) then
					if L.price then F.Count("value", L.price * count) end
					F.Refresh(L)
				end
			end)
		end
	end

	-- How many you now hold, once the bags have caught up. The item can be
	-- slow to land, so a 0 tries again, and is never shown.
	if db.feedBagCount and id then
		local tries = 0
		local function Look()
			if not (L.alive and L.stacks) then return end
			local have = Plain(C_Item.GetItemCount(id, false, false, true))
			if have and have > 0 then
				L.have = have
				F.Refresh(L)
			elseif tries < 3 then
				tries = tries + 1
				M:After(1, Look)
			end
		end
		M:After(0.5, Look)
	end
end

-- how: lost (died), max (at the cap).
local function ShowCurrency(link, count, how)
	count = tonumber(count) or 1
	local id = CurrencyID(link)
	local spec = {
		kind = "loot", key = "cur:" .. (id or link) .. (how.lost and ":lost" or ""),
		link = link, count = count, icon = F.IconFor(link), text = F.LootText,
		prefix = how.lost and Text("feed.lost") or nil, color = how.lost and C.down or nil,
		tag = how.max and F.Gray(Text("feed.max")) or nil,
	}
	local L = F.Line(spec)
	if L and id and HUDiniDB.feedBagCount and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		M:After(0.5, function()
			local info = C_CurrencyInfo.GetCurrencyInfo(id)
			if L.alive and info then
				L.have = Plain(info.quantity)
				F.Refresh(L)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- The loot window, for when chat goes secret
--------------------------------------------------------------------------------

local slots = {}        -- [slot] = { link, count, currency }
local waiting = {}      -- slots taken, not yet shown or claimed
local named = {}        -- bare name -> when a readable chat line showed it
local covered = {}      -- times the loot window showed a slot

local function Snapshot()
	wipe(slots)
	local n = Plain(GetNumLootItems and GetNumLootItems()) or 0
	for i = 1, n do
		local link = Plain(GetLootSlotLink(i))
		local _, _, qty, currencyID = GetLootSlotInfo(i)
		if type(link) == "string" then
			slots[i] = { link = link, count = Plain(qty) or 1, currency = Plain(currencyID) }
		end
	end
end

-- A readable chat line named this: the slot need not show.
local function Claim(link)
	local name = F.Bare(link)
	named[name] = GetTime()
	for _, s in ipairs(waiting) do
		if not s.claimed and F.Bare(s.link) == name then
			s.claimed = true
			return
		end
	end
end

local function SlotTaken(slot)
	local s = slots[Plain(slot) or -1]
	if not s then return end
	slots[slot] = nil
	waiting[#waiting + 1] = s
	M:After(0.5, function()
		for i, w in ipairs(waiting) do
			if w == s then table.remove(waiting, i) break end
		end
		if s.claimed then return end
		local at = named[F.Bare(s.link)]
		if at and GetTime() - at < 1.5 then return end
		covered[#covered + 1] = GetTime()
		if s.currency or s.link:find("currency:") then
			ShowCurrency(s.link, s.count, {})
		else
			ShowItem(s.link, s.count, { kind = "loot" })
		end
	end)
end

-- A secret loot line from you. Show it as it came, unless the loot window
-- showed something at about the same time.
local function SecretLoot(msg)
	local t = GetTime()
	M:After(0.6, function()
		local now = GetTime()
		for i = #covered, 1, -1 do
			if now - covered[i] > 3 then table.remove(covered, i) end
		end
		for i, at in ipairs(covered) do
			if math.abs(at - t) < 1.2 then
				table.remove(covered, i)
				return
			end
		end
		F.Line({ kind = "loot", raw = msg })
	end)
end

--------------------------------------------------------------------------------
-- Chat rules
--------------------------------------------------------------------------------

-- A craft can show twice: "You create: [Light Leather]." (loot) and "You
-- create Light Leather." (tradeskill). The bare name, and when, settles it.
local made = {}

-- A _MULTIPLE string comes before its single version, or the single one
-- would swallow the "x3".
local LOOT_RULES = {
	{ "LOOT_ITEM_SELF_MULTIPLE",            "loot" },
	{ "LOOT_ITEM_PUSHED_SELF_MULTIPLE",     "pushed" },
	{ "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "loot" },
	{ "LOOT_ITEM_CREATED_SELF_MULTIPLE",    "craft" },
	{ "LOOT_ITEM_SELF",                     "loot" },
	{ "LOOT_ITEM_PUSHED_SELF",              "pushed" },
	{ "LOOT_ITEM_BONUS_ROLL_SELF",          "loot" },
	{ "LOOT_ITEM_CREATED_SELF",             "craft" },
}

local function OnLoot(msg, guid)
	local text = Plain(msg)
	if not text then
		local from, me = Plain(guid), Plain(UnitGUID("player"))
		if from and me and from == me then SecretLoot(msg) end
		return
	end
	for _, rule in ipairs(LOOT_RULES) do
		local pat = F.Pattern(rule[1])
		local link, count
		if pat then link, count = text:match(pat) end
		if link then
			Claim(link)
			local kind = rule[2]
			if kind == "craft" then
				made[F.Bare(link)] = GetTime()
				ShowItem(link, count, { kind = "craft", prefix = Text("feed.made") })
			elseif kind == "pushed" and HUDiniDB.feedHideBuys and F.Open(F.MERCHANT) then
				-- Bought at a vendor: you know already.
			else
				ShowItem(link, count, { kind = "loot" })
			end
			return
		end
	end
end

local CURRENCY_RULES = {
	{ "CURRENCY_GAINED_MULTIPLE_OVERFLOW", { max = true } },
	{ "CURRENCY_GAINED_MULTIPLE_BONUS",    {} },
	{ "CURRENCY_GAINED_MULTIPLE",          {} },
	{ "CURRENCY_LOST_FROM_DEATH",          { lost = true } },
	{ "CURRENCY_GAINED",                   {} },
}

local function OnCurrency(msg)
	local text = Plain(msg)
	if not text then
		F.Line({ kind = "loot", raw = msg })
		return
	end
	for _, rule in ipairs(CURRENCY_RULES) do
		local pat = F.Pattern(rule[1])
		local link, count
		if pat then link, count = text:match(pat) end
		if link then
			Claim(link)
			ShowCurrency(link, count, rule[2])
			return
		end
	end
	-- No rule fits: not worth a line.
end

local function OnTradeskill(msg)
	local text = Plain(msg)
	if not text then return end   -- may be someone else's: cannot tell
	local pat = F.Pattern("TRADESKILL_LOG_FIRSTPERSON")
	local what = pat and text:match(pat)
	if not what then return end
	-- Give the loot line a moment to arrive and win.
	M:After(0.3, function()
		local at = made[F.Bare(what)]
		if at and GetTime() - at < 2 then return end
		if what:find("|H") then
			ShowItem(what, 1, { kind = "craft", prefix = Text("feed.made") })
		else
			F.Line({ kind = "craft", key = "craft:" .. what, count = 1, name = what,
				text = function(L)
					return Text("feed.made") .. L.name .. ((L.count or 1) > 1 and (" x" .. L.count) or "")
				end })
		end
	end)
end

--------------------------------------------------------------------------------
-- Reputation
--------------------------------------------------------------------------------

-- { string, sign, generic }. sign 0 is a new standing. generic has no number.
local REP_RULES = {
	{ "FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE", 1 },
	{ "FACTION_STANDING_INCREASED_ACH_BONUS",              1 },
	{ "FACTION_STANDING_INCREASED_DOUBLE_BONUS",           1 },
	{ "FACTION_STANDING_INCREASED_BONUS",                  1 },
	{ "FACTION_STANDING_INCREASED_ACCOUNT_WIDE",           1 },
	{ "FACTION_STANDING_INCREASED",                        1 },
	{ "FACTION_STANDING_INCREASED_GENERIC_ACCOUNT_WIDE",   1, true },
	{ "FACTION_STANDING_INCREASED_GENERIC",                1, true },
	{ "FACTION_STANDING_DECREASED_ACCOUNT_WIDE",          -1 },
	{ "FACTION_STANDING_DECREASED",                       -1 },
	{ "FACTION_STANDING_DECREASED_GENERIC_ACCOUNT_WIDE",  -1, true },
	{ "FACTION_STANDING_DECREASED_GENERIC",               -1, true },
	{ "FACTION_STANDING_CHANGED_ACCOUNT_WIDE",             0 },
	{ "FACTION_STANDING_CHANGED",                          0 },
	{ "FACTION_STANDING_CHANGED_GUILD",                    0 },
}

-- Faction name -> ID, from the rows the reputation panel shows.
local factionIDs = {}

local function FactionID(name)
	if factionIDs[name] then return factionIDs[name] end
	local R = C_Reputation
	if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then return end
	for i = 1, R.GetNumFactions() do
		local d = R.GetFactionDataByIndex(i)
		if d and d.name and d.factionID and d.factionID > 0 then factionIDs[d.name] = d.factionID end
	end
	local w = R.GetWatchedFactionData and R.GetWatchedFactionData()
	if w and w.name and w.factionID and w.factionID > 0 then factionIDs[w.name] = w.factionID end
	return factionIDs[name]
end

local function Paragon(id)
	local R = C_Reputation
	if not (R.IsFactionParagon and R.IsFactionParagon(id)) then return end
	local value, threshold, _, rewardReady = R.GetFactionParagonInfo(id)
	if rewardReady then return Text("feed.rewardReady") end
	if value and threshold and threshold > 0 then
		return Text("feed.toReward", Number(threshold - value % threshold))
	end
end

-- "1,200 to Honored", or the like for renown, friends and paragon.
local function RepDetail(name)
	local id = FactionID(name)
	if not id then return end
	local R = C_Reputation

	if R.IsMajorFaction and R.IsMajorFaction(id) and C_MajorFactions then
		if C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(id) then
			return Paragon(id)
		end
		local m = C_MajorFactions.GetMajorFactionData(id)
		if m and m.renownLevelThreshold and m.renownReputationEarned then
			return Text("feed.toRenown", Number(m.renownLevelThreshold - m.renownReputationEarned),
				(m.renownLevel or 0) + 1)
		end
		return
	end

	if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
		local f = C_GossipInfo.GetFriendshipReputation(id)
		if f and f.friendshipFactionID and f.friendshipFactionID > 0 then
			if f.nextThreshold and f.standing then
				return Text("feed.toNextRank", Number(f.nextThreshold - f.standing))
			end
			return Paragon(id)
		end
	end

	local d = R.GetFactionDataByID and R.GetFactionDataByID(id)
	if not d then return end
	if d.reaction and d.reaction < 8 and d.nextReactionThreshold and d.currentStanding then
		local label = _G["FACTION_STANDING_LABEL" .. (d.reaction + 1)]
		if label then
			return Text("feed.toStanding", Number(d.nextReactionThreshold - d.currentStanding), label)
		end
	end
	return Paragon(id)
end

local function RepText(L)
	local s
	if not L.amount then
		s = (L.sign > 0 and "+ " or "- ") .. L.name
	else
		s = (L.sign > 0 and "+" or "-") .. Number(L.amount) .. " " .. L.name
	end
	if L.detail then s = s .. " " .. F.Gray("(" .. L.detail .. ")") end
	return s
end

local function OnRep(msg)
	local text = Plain(msg)
	if not text then
		F.Line({ kind = "rep", raw = msg, icon = F.ICON.rep })
		return
	end
	for _, rule in ipairs(REP_RULES) do
		local pat = F.Pattern(rule[1])
		local a, b
		if pat then a, b = text:match(pat) end
		if a then
			local sign, generic = rule[2], rule[3]
			if sign == 0 then
				-- "You are now Honored with Stormwind."
				local name = b or GUILD or Text("feed.guild")
				F.Line({ kind = "rep", text = ("%s: %s"):format(name, a), color = C.level,
					icon = F.ICON.rep, big = true })
				return
			end
			local L = F.Line({
				kind = "rep", key = "rep:" .. a .. ":" .. sign, name = a, sign = sign,
				amount = not generic and tonumber(b) or nil, text = RepText,
				color = sign > 0 and C.up or C.down, icon = F.ICON.rep,
			})
			if L and sign > 0 and HUDiniDB.feedRepDetail then
				M:After(0.3, function()
					local ok, detail = pcall(RepDetail, a)
					if ok and detail and L.alive then
						L.detail = detail
						F.Refresh(L)
					end
				end)
			end
			return
		end
	end
	F.Line({ kind = "rep", text = text, icon = F.ICON.rep })
end

-- New factions show up in the panel: look again next time.
local function ForgetFactions() wipe(factionIDs) end

--------------------------------------------------------------------------------
-- Skill-ups
--------------------------------------------------------------------------------

-- The profession's icon, and its top rank when the name is an exact match.
local function Profession(name)
	if not (GetProfessions and GetProfessionInfo) then return end
	local list = { GetProfessions() }
	for i = 1, 5 do
		local index = list[i]
		if index then
			local pname, icon, _, maxRank = GetProfessionInfo(index)
			if pname == name then return icon, maxRank end
			if pname and name:find(pname, 1, true) then return icon end
		end
	end
end

local function OnSkill(msg)
	local text = Plain(msg)
	if not text then
		F.Line({ kind = "skill", raw = msg, color = C.skill })
		return
	end
	local pat = F.Pattern("SKILL_RANK_UP")
	local name, rank
	if pat then name, rank = text:match(pat) end
	if not name then
		F.Line({ kind = "skill", text = text, color = C.skill })
		return
	end
	local icon, maxRank = Profession(name)
	F.Line({
		kind = "skill", key = "skill:" .. name, replace = true, amount = tonumber(rank),
		name = name, maxRank = maxRank, icon = icon, color = C.skill,
		text = function(L)
			local s = L.name .. " " .. (L.amount or "?")
			if L.maxRank and L.maxRank > 0 then s = s .. "/" .. L.maxRank end
			return s
		end,
	})
end

--------------------------------------------------------------------------------
-- Ignore list: /hud feedignore
--------------------------------------------------------------------------------

function ns.FeedIgnore(rest)
	local db = HUDiniDB
	db.feedIgnore = db.feedIgnore or {}
	local say = ns.Say
	rest = rest or ""
	if rest:lower() == "clear" then
		wipe(db.feedIgnore)
		say(Text("feed.ignoreClear"))
		return
	end
	local id = tonumber(rest:match("item:(%d+)") or rest:match("^%s*(%d+)%s*$"))
	if id then
		db.feedIgnore[id] = not db.feedIgnore[id] or nil
		local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or Text("feed.itemID", id)
		say(db.feedIgnore[id] and Text("feed.ignoreOn", name) or Text("feed.ignoreOff", name))
		return
	end
	local names = {}
	for itemID in pairs(db.feedIgnore) do
		names[#names + 1] = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or tostring(itemID)
	end
	if #names == 0 then
		say(Text("feed.ignoreNone"))
	else
		table.sort(names)
		say(Text("feed.ignoreList", table.concat(names, ", ")))
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local CHAT = {
	CHAT_MSG_LOOT                  = OnLoot,
	CHAT_MSG_CURRENCY              = OnCurrency,
	CHAT_MSG_TRADESKILLS           = OnTradeskill,
	CHAT_MSG_COMBAT_FACTION_CHANGE = OnRep,
	CHAT_MSG_SKILL                 = OnSkill,
}

local EVENTS = { "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "UPDATE_FACTION" }
for event in pairs(CHAT) do EVENTS[#EVENTS + 1] = event end

-- Off: a loot window read half way is forgotten. Its timers are gone.
function M:OnDisable()
	wipe(slots)
	wipe(waiting)
	wipe(lootLines)
end

M:On(EVENTS, function(event, ...)
	if not HUDiniDB then return end
	local chat = CHAT[event]
	if chat then
		-- arg1 is the text, arg12 the sender's GUID.
		local msg = ...
		chat(msg, (select(12, ...)))
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		Snapshot()
	elseif event == "LOOT_SLOT_CLEARED" then
		SlotTaken((...))
	elseif event == "LOOT_CLOSED" then
		wipe(slots)
	elseif event == "UPDATE_FACTION" then
		ForgetFactions()
	end
end)
