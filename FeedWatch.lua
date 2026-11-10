--[[--------------------------------------------------------------------------
	HUDini - Feed: bags, gear, merchants, spells, collections, quest progress

	Lines that come from watching the game, not from chat:

		bags          5, 2 and 0 free slots left (each once, until you
		              make room again)
		gear          your most worn item at 50%, 25%, 10%, and broken
		merchant      at a vendor: what a repair costs, what your junk sells for
		spells        a new spell or recipe
		collections   a new look, mount, pet or toy
		progress      quest objectives as they move (a hint, off by default)
		resting       you start or stop resting (an inn, a city)

	The first seconds after a login or a spec change teach the game a pile
	of spells it already knew. Those stay quiet.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local Text = ns.Text

local Plain = ns.Plain
local F = ns.Feed

-- A module of its own (Modules.lua), on with the feed: while the feed is
-- off it has no events and no timers.
local M = ns.NewModule("feedWatch", { label = "Feed (bags, gear, collections)", setting = "showFeed" }) -- locale: skip a debug name (/hud debug modules)
local C = F.COLOR

local quietUntil = 0   -- GetTime() before which spells and collections stay quiet

local function Quiet(secs)
	quietUntil = math.max(quietUntil, GetTime() + secs)
end

local function Loud()
	return GetTime() >= quietUntil
end

-- The lowest step a value has reached, or nil when above them all.
local function Step(value, steps)
	local hit
	for _, s in ipairs(steps) do
		if value <= s then hit = s end
	end
	return hit
end

-- Warn once per step on the way down; climbing back up arms it again.
-- state = { ready, warned }. Returns true when a warning is due.
local function Crossed(state, step)
	if not state.ready then
		state.ready, state.warned = true, step
		return false
	end
	if step == nil then
		state.warned = nil
	elseif state.warned == nil or step < state.warned then
		state.warned = step
		return true
	elseif step > state.warned then
		state.warned = step
	end
	return false
end

--------------------------------------------------------------------------------
-- Bags
--------------------------------------------------------------------------------

local bagState = {}

local function FreeSlots()
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then return end
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local n, family = C_Container.GetContainerNumFreeSlots(bag)
		-- A secret count or bag kind is no answer: no line, not a false
		-- "bags full", and not a profession bag's slots counted as loot space.
		if ns.IsSecret(n) or ns.IsSecret(family) then return end
		if n and (family == nil or family == 0) then free = free + n end
	end
	return free
end

local function CheckBags()
	local free = FreeSlots()
	if not free then return end
	if Crossed(bagState, Step(free, { 5, 2, 0 })) then
		if free == 0 then
			F.Line({ kind = "bags", key = "bags", text = Text("feed.bagsFull"), color = C.bad, icon = F.ICON.bags })
		else
			F.Line({ kind = "bags", key = "bags",
				text = free == 1 and Text("feed.bagSlot", free) or Text("feed.bagSlots", free),
				color = C.warn, icon = F.ICON.bags })
		end
	end
end

--------------------------------------------------------------------------------
-- Gear
--------------------------------------------------------------------------------

local gearState = {}

local function Durability()
	local low, broken
	for slot = 1, 19 do
		local cur, most = GetInventoryItemDurability(slot)
		cur, most = Plain(cur), Plain(most)
		if cur and most and most > 0 then
			local pct = cur / most * 100
			if not low or pct < low then low = pct end
			if cur == 0 then broken = (broken or 0) + 1 end
		end
	end
	return low, broken
end

local function CheckGear()
	local low, broken = Durability()
	if not low then return end
	if Crossed(gearState, Step(low, { 50, 25, 10, 0 })) then
		if broken then
			F.Line({ kind = "gear", key = "gear",
				text = broken == 1 and Text("feed.gearBroken", broken) or Text("feed.gearBrokenMany", broken),
				color = C.bad, icon = F.ICON.gear })
		else
			F.Line({ kind = "gear", key = "gear", text = Text("feed.gearAt", math.floor(low)),
				color = low <= 25 and C.bad or C.warn, icon = F.ICON.gear })
		end
	end
end

--------------------------------------------------------------------------------
-- At a merchant
--------------------------------------------------------------------------------

local function JunkValue()
	if not (C_Container and C_Container.GetContainerNumSlots) then return 0 end
	local total = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == 0 and not info.hasNoValue and info.hyperlink then
				local price = select(11, C_Item.GetItemInfo(info.hyperlink))
				if price and price > 0 then total = total + price * (info.stackCount or 1) end
			end
		end
	end
	return total
end

local function AtMerchant()
	M:After(0.2, function()
		if F.On("gear") and CanMerchantRepair and CanMerchantRepair() then
			local cost = Plain(GetRepairAllCost())
			if cost and cost > 0 then
				F.Line({ kind = "gear", key = "repair", text = Text("feed.repair", F.Coins(cost)), icon = F.ICON.gear })
			end
		end
		if HUDiniDB.feedValue and F.On("loot") then
			local ok, junk = pcall(JunkValue)
			if ok and junk > 0 then
				F.Line({ kind = "loot", key = "junk", text = Text("feed.junk", F.Coins(junk)),
					color = C.gray, icon = F.ICON.money })
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Spells and recipes
--------------------------------------------------------------------------------

local seenSpell = {}

local function SpellLink(id)
	if C_Spell then
		local link = C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)
		if link then return link end
		local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
		if name then return name end
	end
	return GetSpellLink and GetSpellLink(id)
end

local function SpellIcon(id)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
	return GetSpellTexture and GetSpellTexture(id)
end

local function OnSpell(spellID, _, isGuildPerk)
	spellID = Plain(spellID)
	if not spellID or isGuildPerk or not Loud() then return end
	if seenSpell[spellID] and GetTime() - seenSpell[spellID] < 3 then return end
	seenSpell[spellID] = GetTime()
	local link = SpellLink(spellID)
	if not link then return end
	F.Line({ kind = "spell", text = Text("feed.newSpell", link), color = C.spell, icon = SpellIcon(spellID) })
end

-- A trainer can teach twenty recipes at once: more than three in a burst
-- become one line.
local recipes, recipeTimer = {}, false

local function FlushRecipes()
	recipeTimer = false
	if #recipes > 3 then
		F.Line({ kind = "spell", text = Text("feed.newRecipes", #recipes), color = C.spell,
			icon = SpellIcon(recipes[1]) })
	else
		for _, id in ipairs(recipes) do
			local link = SpellLink(id)
			if link then F.Line({ kind = "spell", text = Text("feed.newRecipe", link), color = C.spell, icon = SpellIcon(id) }) end
		end
	end
	wipe(recipes)
end

local function OnRecipe(recipeID)
	recipeID = Plain(recipeID)
	if not recipeID or not Loud() then return end
	if seenSpell[recipeID] and GetTime() - seenSpell[recipeID] < 3 then return end
	seenSpell[recipeID] = GetTime()
	recipes[#recipes + 1] = recipeID
	if not recipeTimer then
		recipeTimer = true
		M:After(0.5, FlushRecipes)
	end
end

--------------------------------------------------------------------------------
-- Collections
--------------------------------------------------------------------------------

local looks, lookTimer = {}, false

local function FlushLooks()
	lookTimer = false
	if #looks > 3 then
		F.Line({ kind = "collection", text = Text("feed.newLooks", #looks), color = C.collection,
			icon = looks[1].icon })
	else
		for _, l in ipairs(looks) do
			F.Line({ kind = "collection", text = Text("feed.newLookLine", l.link), color = C.collection, icon = l.icon,
				big = true })
		end
	end
	wipe(looks)
end

-- A loot line for the same item takes a waiting look (FeedLoot.lua, TICK-0059).
function F.TakeLook(itemID)
	for i, l in ipairs(looks) do
		if l.itemID == itemID then
			table.remove(looks, i)
			return true
		end
	end
	return false
end

local function OnLook(sourceID)
	sourceID = Plain(sourceID)
	local T = C_TransmogCollection
	if not (sourceID and Loud() and T and T.GetSourceInfo) then return end
	local ok, info = pcall(T.GetSourceInfo, sourceID)
	if not (ok and type(info) == "table") then return end
	-- Compared and used as a key below, so never a secret. A secret one
	-- joins no loot line: the look still shows, by name.
	local itemID = Plain(info.itemID)
	-- Not every source the game names is a look: on Forever Rough Arrow
	-- came here (TICK-0123). The source's own flags, then the item's.
	if Plain(info.isHideVisual) == true or Plain(info.categoryID) == 0 then return end
	if not F.CanBeLook(itemID) then return end
	-- Looted a moment ago: the loot line says "New look" (F.JoinLook).
	if itemID and F.JoinLook and F.JoinLook(itemID) then return end
	local link = itemID and select(2, C_Item.GetItemInfo(itemID)) or Plain(info.name)
	if not link then return end
	looks[#looks + 1] = { link = link, icon = itemID and C_Item.GetItemIconByID(itemID), itemID = itemID }
	if not lookTimer then
		lookTimer = true
		M:After(0.5, FlushLooks)
	end
end

local function NewThing(text, icon)
	if not (text and Loud()) then return end
	F.Line({ kind = "collection", text = text, color = C.collection,
		icon = icon, big = true })
end

local function OnMount(mountID)
	mountID = Plain(mountID)
	if not (mountID and C_MountJournal and C_MountJournal.GetMountInfoByID) then return end
	local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
	NewThing(name and Text("feed.newMount", name), icon)
end

local function OnPet(guid)
	guid = Plain(guid)
	if not (guid and C_PetJournal and C_PetJournal.GetPetInfoByPetID) then return end
	local _, customName, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(guid)
	NewThing((customName or name) and Text("feed.newPet", customName or name), icon)
end

local function OnToy(itemID)
	itemID = Plain(itemID)
	if not (itemID and C_ToyBox and C_ToyBox.GetToyInfo) then return end
	local _, name, icon = C_ToyBox.GetToyInfo(itemID)
	NewThing(name and Text("feed.newToy", name), icon)
end

--------------------------------------------------------------------------------
-- Quest log: titles for turn-ins, and objective progress
--------------------------------------------------------------------------------

local objectives = {}   -- [questID] = { [i] = numFulfilled, complete = bool }
local scanning = false

local function ScanQuests()
	scanning = false
	local Q = C_QuestLog
	if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then return end
	local tell = F.On("progress")
	local seen = {}
	for i = 1, Q.GetNumQuestLogEntries() do
		local info = Q.GetInfo(i)
		local id = info and not info.isHeader and Plain(info.questID)
		if id then
			seen[id] = true
			if info.title then F.questTitles[id] = Plain(info.title) end
			local old, new = objectives[id], {}
			local list = Q.GetQuestObjectives and Q.GetQuestObjectives(id) or {}
			for j, o in ipairs(list) do
				local got = Plain(o.numFulfilled) or 0
				new[j] = got
				if tell and old and old[j] and got > old[j] then
					local text = Plain(o.text)
					if text and text ~= "" then
						if o.type == "progressbar" then text = ("%s %d%%"):format(text, got) end
						F.Line({ kind = "progress", key = ("qp:%d:%d"):format(id, j), text = text,
							color = o.finished and C.up or nil, icon = F.ICON.quest })
					end
				end
			end
			new.complete = Q.IsComplete and Q.IsComplete(id) or false
			if tell and old and new.complete and not old.complete then
				F.Line({ kind = "progress", key = "qd:" .. id,
					text = Text("feed.readyTurnIn", F.questTitles[id] or Text("feed.questNameless")),
					color = C.quest, icon = F.ICON.quest })
			end
			objectives[id] = new
		end
	end
	for id in pairs(objectives) do
		if not seen[id] then objectives[id] = nil end
	end
end

local function SoonScan()
	if scanning then return end
	scanning = true
	M:After(0.2, ScanQuests)
end

--------------------------------------------------------------------------------
-- Resting: a line when it starts and when it stops (TICK-0097)
--
-- A login, a /reload or the feed coming back on notes the state without a
-- line, so only a change you made gives one. A loading screen (a hearth to
-- an inn) can change it with no PLAYER_UPDATE_RESTING of its own: the
-- PLAYER_ENTERING_WORLD after it looks, and tells. IsResting is not in the
-- 12.x API docs, so it is guarded, and a secret or a throw counts as "not
-- known": no line, and the last plain state stays.
--------------------------------------------------------------------------------

local resting   -- the last plain state: true, false, or nil (not noted yet)
-- GetTime() before which a resting change is noted with no line. The client
-- may say "not resting" at the login and "resting" a moment later; the
-- first seconds after a login, a /reload or the feed coming on stay quiet.
local settleUntil = 0
local SETTLE = 5

local function RestingNow()
	if not IsResting then return nil end
	local ok, v = pcall(IsResting)
	if not ok then return nil end
	v = Plain(v)
	if v == nil then return nil end
	return v and true or false
end

local function CheckResting(tell)
	local now = RestingNow()
	if now == nil then return end
	local was = resting
	resting = now
	if not tell or was == nil or was == now or not F.On("resting") then return end
	F.Line({ kind = "resting", text = now and Text("feed.restStart") or Text("feed.restStop"),
		color = C.info, icon = F.ICON.rest })
end

--------------------------------------------------------------------------------
-- A look at every kind, for placing the box: /hud test (TestMode.lua)
--------------------------------------------------------------------------------

function ns.FeedTest()
	local db = HUDiniDB
	if not db.showFeed then
		ns.Say(Text("feed.offForTest"))
		return
	end
	local link = select(2, C_Item.GetItemInfo(2318)) or "|cffffffff[" .. Text("feedTest.leather") .. "]|r"
	local gear = select(2, C_Item.GetItemInfo(2575)) or "|cffffffff[" .. Text("feedTest.shirt") .. "]|r"
	local L = F.Line({ kind = "loot", key = "test:loot", link = link, count = 3, price = 15,
		icon = F.IconFor(link), text = F.LootText })
	if L then L.have = 47; F.Refresh(L) end
	F.Line({ kind = "loot", key = "test:look", link = gear, count = 1, tag = "|cffff80ff" .. Text("feed.newLook") .. "|r",
		icon = F.IconFor(gear), text = F.LootText })
	F.Line({ kind = "money", text = "+ " .. F.Coins(1234), icon = F.ICON.money })
	F.Line({ kind = "xp", text = "+1,350 XP " .. F.Gray("(" .. table.concat({ "4.2%",
		Text("feed.rested", "45"), Text("feed.killsToLevel", "31") }, " · ") .. ")"),
		color = C.xp, icon = F.ICON.xp })
	F.Line({ kind = "quest", text = Text("feed.turnedIn", Text("feedTest.quest")) .. "  |cffc78cff+450 XP|r  " .. F.Coins(4500),
		color = C.quest, icon = F.ICON.quest })
	F.Line({ kind = "rep", text = "+25 " .. Text("feedTest.faction") .. " "
		.. F.Gray("(" .. Text("feed.toStanding", "1,200", Text("feedTest.standing")) .. ")"), color = C.up,
		icon = F.ICON.rep })
	F.Line({ kind = "skill", text = Text("feedTest.skill") .. " 42/75", color = C.skill,
		icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" })
	F.Line({ kind = "craft", text = Text("feed.made") .. link, icon = F.IconFor(link) })
	F.Line({ kind = "discovery", text = Text("feed.discovered", Text("feedTest.place")), color = C.discovery, icon = F.ICON.map })
	F.Line({ kind = "spell", text = Text("feed.newSpell", Text("feedTest.spell")), color = C.spell, icon = F.ICON.info })
	F.Line({ kind = "bags", text = Text("feed.bagSlots", 2), color = C.warn, icon = F.ICON.bags })
	F.Line({ kind = "gear", text = Text("feed.gearAt", 25), color = C.bad, icon = F.ICON.gear })
	F.Line({ kind = "level", text = Text("feed.level", 8), color = C.level, icon = F.ICON.level })
	F.Line({ kind = "summary", text = table.concat({ Text("feed.levelTook", 7, "47m"), Text("feed.quests", 14),
		Text("feed.kills", 212) }, " · "), color = C.gray,
		icon = F.ICON.level })
	F.Highlight({ text = Text("feed.levelBig", 8), icon = F.ICON.level, color = C.level })
end

--------------------------------------------------------------------------------
-- Sample lines while HUDini setup's feed step is open (TICK-0096, TICK-0116)
--------------------------------------------------------------------------------

local SAMPLE = "sample:"
local forever = math.huge

-- Each sample: its key, and a draw that makes its line. F.Line draws
-- nothing while the line's kind is off, so each follows its own checkbox.
-- The two leveling hints show only while their hint is on: "On" shows five
-- lines, "On, with leveling hints" seven.
local SAMPLES = {
	{ key = "sample:loot", draw = function(key)
		local info = C_Item.GetItemInfo or GetItemInfo
		local link = select(2, info(2318)) or "|cffffffff[" .. Text("feedTest.leather") .. "]|r"
		F.Line({ kind = "loot", key = key, link = link, count = 3, price = 15, have = 47,
			icon = F.IconFor(link), text = F.LootText, life = forever, replace = true })
	end },
	{ key = "sample:money", draw = function(key)
		F.Line({ kind = "money", key = key, text = "+ " .. F.Coins(1234), icon = F.ICON.money,
			life = forever, replace = true })
	end },
	{ key = "sample:xp", draw = function(key)
		F.Line({ kind = "xp", key = key, text = "+1,350 XP " .. F.Gray("(" .. table.concat({ "4.2%",
			Text("feed.rested", "45"), Text("feed.killsToLevel", "31") }, " · ") .. ")"),
			color = C.xp, icon = F.ICON.xp, life = forever, replace = true })
	end },
	{ key = "sample:quest", draw = function(key)
		F.Line({ kind = "quest", key = key, text = Text("feed.turnedIn", Text("feedTest.quest")),
			color = C.quest, icon = F.ICON.quest, life = forever, replace = true })
	end },
	{ key = "sample:rep", draw = function(key)
		F.Line({ kind = "rep", key = key, text = "+25 " .. Text("feedTest.faction") .. " "
			.. F.Gray("(" .. Text("feed.toStanding", "1,200", Text("feedTest.standing")) .. ")"), color = C.up,
			icon = F.ICON.rep, life = forever, replace = true })
	end },
	-- Quest progress (a hint): drawn as the real line is, the game's goal
	-- text in the feed's own color (ScanQuests above).
	{ key = "sample:goal", draw = function(key)
		F.Line({ kind = "progress", key = key, text = Text("feedTest.questGoal"),
			icon = F.ICON.quest, life = forever, replace = true })
	end },
	-- The upgrade hint: a loot line with "+N ilvl", as FeedLoot.lua draws it.
	-- It is a loot line, so it also needs Loot on.
	{ key = "sample:upgrade", hint = "feedUpgrade", draw = function(key)
		local link = "|cff1eff00[" .. Text("feedTest.upgrade") .. "]|r"
		F.Line({ kind = "loot", key = key, link = link, count = 1, upgrade = 4,
			icon = "Interface\\Icons\\INV_Chest_Leather_01", text = F.LootText, life = forever, replace = true })
	end },
}

-- The live sample line with this key, if one shows.
local function Live(key)
	for _, L in ipairs(F.Keyed(SAMPLE)) do
		if L.key == key then return L end
	end
end

-- On: each sample whose kind (and hint) is on shows once; one whose kind
-- went off fades. So a choice on the feed step redraws at once, and on
-- again while they show adds none. They do not fade by themselves (life
-- math.huge) and make no highlight. Off: they all fade now.
function ns.FeedSamples(on)
	if not on then
		for _, L in ipairs(F.Keyed(SAMPLE)) do F.Fade(L) end
		return
	end
	local db = HUDiniDB
	for _, sample in ipairs(SAMPLES) do
		local L = Live(sample.key)
		local want = not sample.hint or db[sample.hint]
		if not want then
			F.Fade(L)
		elseif not L then
			sample.draw(sample.key)
		end
	end
	-- A kind that went off: F.Line drew nothing new, so fade what shows.
	for _, L in ipairs(F.Keyed(SAMPLE)) do
		if not F.On(L.kind) then F.Fade(L) end
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local HANDLERS = {
	BAG_UPDATE_DELAYED                = function() CheckBags() end,
	UPDATE_INVENTORY_DURABILITY       = function() CheckGear() end,
	MERCHANT_SHOW                     = function() AtMerchant() end,
	LEARNED_SPELL_IN_SKILL_LINE       = OnSpell,
	NEW_RECIPE_LEARNED                = OnRecipe,
	TRANSMOG_COLLECTION_SOURCE_ADDED  = OnLook,
	NEW_MOUNT_ADDED                   = OnMount,
	NEW_PET_ADDED                     = OnPet,
	NEW_TOY_ADDED                     = OnToy,
	QUEST_LOG_UPDATE                  = function() SoonScan() end,
	QUEST_WATCH_UPDATE                = function() SoonScan() end,
	QUEST_ACCEPTED                    = function() SoonScan() end,
	PLAYER_SPECIALIZATION_CHANGED     = function() Quiet(2) end,
	ACTIVE_TALENT_GROUP_CHANGED       = function() Quiet(2) end,
	ACTIVE_PLAYER_SPECIALIZATION_CHANGED = function() Quiet(2) end,
	PLAYER_UPDATE_RESTING             = function() CheckResting(GetTime() >= settleUntil) end,
	-- The third value is Modules.lua's own: the module just came on.
	PLAYER_ENTERING_WORLD             = function(isLogin, isReload, isEnable)
		local fresh = isLogin or isReload or isEnable
		if fresh then settleUntil = GetTime() + SETTLE end
		CheckResting(not fresh)
		Quiet(5)
		-- Note where things stand, without a line.
		M:After(2, function()
			CheckBags()
			CheckGear()
			ScanQuests()
		end)
	end,
}

for event, fn in pairs(HANDLERS) do
	M:On(event, function(_, ...)
		if HUDiniDB then fn(...) end
	end)
end

-- Off: lines waiting to join up are dropped with their timers, and what
-- was noted of bags, gear and quests is forgotten. On again,
-- PLAYER_ENTERING_WORLD runs at once and notes where things stand, so a
-- change made while the feed was off gives no line.
function M:OnDisable()
	wipe(recipes)
	recipeTimer = false
	wipe(looks)
	lookTimer = false
	scanning = false
	wipe(bagState)
	wipe(gearState)
	wipe(objectives)
	resting = nil
end
