-- FeedWatch.lua when the game hides an answer (TICK-0112). Each test first
-- runs the value that WOULD change the feed, plain, and checks that it does.
-- Then it flags that same value secret and checks that the feed does what it
-- does for no answer, and throws nothing. So a missing Plain() or IsSecret()
-- fails the test (the method of TICK-0110). Each flagged value is used for
-- nothing else in its test.

local QUEST = 4001

-- A logged-in world with the feed on and quest progress on. w.secret: the
-- values issecretvalue calls secret. What the game says now:
--   w.free, w.free2, w.family2   free slots in bag 0, and in bag 1 and its kind
--   w.cur, w.most                slot 1's durability
--   w.repair                     what a repair costs
--   w.lookItem                   the item ID a new look gives (nil: none)
--   w.quest                      the quest log's one quest: { title, got, text }
local function World()
	local w = H.world()
	w.secret = {}
	w.env.HUDiniDB = { feedQuestProgress = true, feedValue = false }
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.free, w.free2, w.family2 = 20, 4, 8
	w.cur, w.most, w.repair, w.lookItem = 80, 100, 0, 1234
	w.quest = { title = "Wolves", got = 2, text = "Wolves slain: 2/8" }
	local env = w.env
	-- Two bags, the backpack and bag 1, so no other bag answers 0 (a
	-- secret test flags the loot-bag kind 0).
	env.NUM_BAG_SLOTS = 1
	env.C_Container.GetContainerNumFreeSlots = function(bag)
		if bag == 0 then return w.free, 0 end
		if bag == 1 then return w.free2, w.family2 end
		return 0, 0
	end
	env.GetInventoryItemDurability = function(slot)
		if slot == 1 then return w.cur, w.most end
	end
	env.CanMerchantRepair = function() return true end
	env.GetRepairAllCost = function() return w.repair end
	env.C_Spell.GetSpellLink = function(id)
		return ({ [5308] = "[Execute]", [2329] = "[Elixir of Lion's Strength]" })[id]
	end
	env.C_Item.GetItemInfo = function(id)
		if id == 1234 then return "Frayed Pants", "[Frayed Pants]" end
	end
	env.C_Item.GetItemIconByID = function() return 134 end
	env.C_TransmogCollection = { GetSourceInfo = function(id)
		if id == 77 then return { itemID = w.lookItem, name = "Frayed Pants" } end
	end }
	env.C_MountJournal = { GetMountInfoByID = function(id)
		if id == 6 then return "Brown Horse", 0, 132 end
	end }
	env.C_PetJournal = { GetPetInfoByPetID = function(guid)
		if guid == "BattlePet-0-0001" then return 0, nil, 0, 0, 0, 0, 0, "Snowshoe Rabbit", 133 end
	end }
	env.C_ToyBox = { GetToyInfo = function(id)
		if id == 1973 then return id, "Orb of Deception", 135 end
	end }
	env.C_QuestLog = {
		GetNumQuestLogEntries = function() return 1 end,
		GetInfo = function() return { questID = QUEST, title = w.quest.title } end,
		GetQuestObjectives = function()
			return { { numFulfilled = w.quest.got, text = w.quest.text, type = "monster" } }
		end,
		IsComplete = function() return false end,
	}
	w:loadAddon()
	w:runTimers()                              -- notes bags, gear and quests
	w.time = w.time + 10                       -- past the quiet time after login
	local F, shown = w.ns.Feed, {}
	local Line = F.Line
	F.Line = function(spec)
		local L = Line(spec)
		if L then shown[#shown + 1] = L end
		return L
	end
	w.shown = shown
	-- Fire event, let the feed show it; the new line of kind, or nil.
	function w:Show(kind, event, ...)
		local n = #self.shown
		self:fire(event, ...)
		self:runTimers()
		for i = n + 1, #self.shown do
			if self.shown[i].kind == kind then return self.shown[i] end
		end
	end
	return w
end

local function Text(L)
	local text = L.text
	if type(text) == "function" then text = text(L) end
	return text
end

--------------------------------------------------------------------------------
-- Bags and gear
--------------------------------------------------------------------------------

H.test("a secret free-slot count gives no bag line", function()
	local w = World()
	w.free = 3
	H.eq(Text(w:Show("bags", "BAG_UPDATE_DELAYED")), w.ns.TEXT[0]["feed.bagSlots"]:format(3), "plain")
	w = World()
	w.free, w.secret[3] = 3, true
	H.eq(w:Show("bags", "BAG_UPDATE_DELAYED"), nil, "secret: not a false \"bags full\"")
end)

H.test("a secret bag kind gives no answer", function()
	-- Bag 1 holds 4 free slots. As a profession bag (kind 8) they are not
	-- loot space; as a loot bag (kind 0) they count. A count above 5 arms
	-- the line again, so a kind read as 0 brings "3 slots left" back.
	local w = World()
	w.free = 3
	H.eq(Text(w:Show("bags", "BAG_UPDATE_DELAYED")), w.ns.TEXT[0]["feed.bagSlots"]:format(3), "plain: the first line")
	w.family2 = 0
	H.eq(w:Show("bags", "BAG_UPDATE_DELAYED"), nil, "plain: 7 loot slots, no line")
	w.family2 = 8
	H.eq(Text(w:Show("bags", "BAG_UPDATE_DELAYED")), w.ns.TEXT[0]["feed.bagSlots"]:format(3), "plain: armed again")
	-- Flagged secret, kind 0 is no answer (the backpack's kind is 0 too):
	-- nothing counts, so nothing arms the line again.
	w = World()
	w.free = 3
	H.ok(w:Show("bags", "BAG_UPDATE_DELAYED"), "secret: the first line")
	w.family2, w.secret[0] = 0, true
	H.eq(w:Show("bags", "BAG_UPDATE_DELAYED"), nil, "secret: no answer")
	w.family2, w.secret[0] = 8, nil
	H.eq(w:Show("bags", "BAG_UPDATE_DELAYED"), nil, "secret: not armed again")
end)

H.test("a secret durability skips the item", function()
	local w = World()
	w.cur = 41
	H.ok(w:Show("gear", "UPDATE_INVENTORY_DURABILITY"), "plain: 41%")
	w = World()
	w.cur, w.secret[41] = 41, true
	H.eq(w:Show("gear", "UPDATE_INVENTORY_DURABILITY"), nil, "secret: none")
end)

H.test("a secret most durability skips the item", function()
	local w = World()
	w.cur, w.most = 41, 101
	H.ok(w:Show("gear", "UPDATE_INVENTORY_DURABILITY"), "plain: 40%")
	w = World()
	w.cur, w.most, w.secret[101] = 41, 101, true
	H.eq(w:Show("gear", "UPDATE_INVENTORY_DURABILITY"), nil, "secret: none")
end)

H.test("a secret repair cost shows no cost", function()
	local w = World()
	w.repair = 250
	H.ok(w:Show("gear", "MERCHANT_SHOW"), "plain: a repair line")
	w = World()
	w.repair, w.secret[250] = 250, true
	H.eq(w:Show("gear", "MERCHANT_SHOW"), nil, "secret: none")
end)

--------------------------------------------------------------------------------
-- Spells and collections
--------------------------------------------------------------------------------

-- event, its value, the line's kind.
local NEW = {
	{ "a secret new spell", "LEARNED_SPELL_IN_SKILL_LINE", 5308, "spell" },
	{ "a secret new recipe", "NEW_RECIPE_LEARNED", 2329, "spell" },
	{ "a secret new look", "TRANSMOG_COLLECTION_SOURCE_ADDED", 77, "collection" },
	{ "a secret new mount", "NEW_MOUNT_ADDED", 6, "collection" },
	{ "a secret new pet", "NEW_PET_ADDED", "BattlePet-0-0001", "collection" },
	{ "a secret new toy", "NEW_TOY_ADDED", 1973, "collection" },
}

for _, t in ipairs(NEW) do
	local name, event, value, kind = t[1], t[2], t[3], t[4]
	H.test(name .. " shows no line", function()
		local w = World()
		H.ok(w:Show(kind, event, value), "plain")
		w = World()
		w.secret[value] = true
		H.eq(w:Show(kind, event, value), nil, "secret: none")
	end)
end

H.test("a secret look name with no item shows no line", function()
	local w = World()
	w.lookItem = nil
	H.ok(Text(w:Show("collection", "TRANSMOG_COLLECTION_SOURCE_ADDED", 77)):find("Frayed Pants", 1, true), "plain: by name")
	w = World()
	w.lookItem, w.secret["Frayed Pants"] = nil, true
	H.eq(w:Show("collection", "TRANSMOG_COLLECTION_SOURCE_ADDED", 77), nil, "secret: none")
end)

--------------------------------------------------------------------------------
-- The quest log
--------------------------------------------------------------------------------

-- One more wolf: the progress line, or nil.
local function Kill(w)
	w.quest.got, w.quest.text = 3, "Wolves slain: 3/8"
	return w:Show("progress", "QUEST_LOG_UPDATE")
end

H.test("a secret quest ID is no quest", function()
	local w = World()
	H.eq(Text(Kill(w)), "Wolves slain: 3/8", "plain")
	w = World()
	w.secret[QUEST] = true
	H.eq(Kill(w), nil, "secret: none")
end)

H.test("a secret quest title is no title", function()
	local w = World()
	H.eq(w.ns.Feed.questTitles[QUEST], "Wolves", "plain")
	w = World()
	w.secret.Wolves = true
	w:fire("QUEST_LOG_UPDATE")
	w:runTimers()
	H.eq(w.ns.Feed.questTitles[QUEST], nil, "secret: none")
end)

-- Their plain case, "Wolves slain: 3/8", is the first half of the quest ID test.
H.test("a secret objective count is no progress", function()
	local w = World()
	w.secret[3] = true
	H.eq(Kill(w), nil, "secret: none")
end)

H.test("a secret objective text shows no line", function()
	local w = World()
	w.secret["Wolves slain: 3/8"] = true
	H.eq(Kill(w), nil, "secret: none")
end)
