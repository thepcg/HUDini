-- "New appearance" once per item (TICK-0059): gear with a look you lack gets the
-- tag on its loot line, and the game may also add the look to your
-- collection. The loot line keeps the "New appearance"; the collection's own line
-- joins it, whichever comes first.

local PANTS = "|cffffffff|Hitem:1234::::::::1:::::::|h[Frayed Pants]|h|r"
local SOURCE = 77

-- A logged-in world with the feed on, one pair of pants, and a
-- collection that has its look once w.collected is true.
-- secretID: the collection gives the item ID as a secret.
-- secret: a set of values the game flags secret (harness.lua, step 1:
-- set before load). The set is w.secret, so a test can flag a value later.
local function LookWorld(saved, secretID, secret)
	local w = H.world()
	w.env.LOOT_ITEM_SELF = "You receive loot: %s."
	w.env.HUDiniDB = saved
	w.secret = secret or {}
	if secretID or secret then
		w.env.issecretvalue = function(v)
			if secretID and v == "SECRET" then return true end
			return v ~= nil and w.secret[v] == true
		end
	end
	w.collected = false
	local C_Item = w.env.C_Item
	C_Item.GetItemInfo = function(item)
		if item == PANTS or item == 1234 then
			return "Frayed Pants", PANTS, w.quality or 1, 5, 1, "Armor", "Cloth", 1, "INVTYPE_LEGS", 134, 7
		end
	end
	C_Item.GetItemIconByID = function() return 134 end
	w.env.C_TransmogCollection = {
		GetItemInfo = function(link) if link == PANTS then return 500, SOURCE end end,
		PlayerCanCollectSource = function() return true, true end,
		GetAppearanceInfoBySource = function() return { appearanceIsCollected = w.collected } end,
		GetSourceInfo = function(id)
			if id == SOURCE then return { itemID = secretID and "SECRET" or 1234, name = "Frayed Pants" } end
		end,
	}
	w:loadAddon()
	w.time = w.time + 10                       -- past the quiet time after login
	-- Every line the feed shows.
	local F, shown = w.ns.Feed, {}
	local Line = F.Line
	F.Line = function(spec)
		local L = Line(spec)
		if L then shown[#shown + 1] = L end
		return L
	end
	w.shown = shown
	-- Every big highlight asked for.
	local Highlight, lit = F.Highlight, {}
	F.Highlight = function(item)
		lit[#lit + 1] = item
		return Highlight(item)
	end
	w.lit = lit
	return w
end

-- The text of each line still on screen, as it reads now.
local function Texts(w)
	local out = {}
	for _, L in ipairs(w.shown) do
		if L.alive then
			local text = L.text
			if type(text) == "function" then text = text(L) end
			out[#out + 1] = text
		end
	end
	return out
end

-- The copy of D-029 (TICK-0134): the loot tag ("New appearance") and the
-- collection's line ("Appearance collected: ...") have different words, so
-- each counts as one New look.
local function NewLooks(texts)
	local n = 0
	for _, s in ipairs(texts) do
		for _ in s:gmatch("New appearance") do n = n + 1 end
		if s:find("Appearance collected: ", 1, true) == 1 then n = n + 1 end
	end
	return n
end

local function Loot(w) w:fire("CHAT_MSG_LOOT", "You receive loot: " .. PANTS .. ".") end
local function Learn(w)
	w.collected = true
	w:fire("TRANSMOG_COLLECTION_SOURCE_ADDED", SOURCE)
end

H.test("loot, then the collection: one line, with New look once", function()
	local w = LookWorld(nil)
	Loot(w)
	Learn(w)
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 1, "lines: " .. table.concat(t, " | "))
	H.ok(t[1]:find(PANTS, 1, true), "the loot line")
	H.eq(NewLooks(t), 1, "New appearance")
	H.eq(#w.lit, 1, "one big highlight")
	H.eq(w.lit[1].line, w.shown[1], "for the loot line")
	H.eq(w.lit[1].color, w.ns.Feed.COLOR.collection, "in the collection's color")
end)

H.test("the collection, then loot: one line, with New look once", function()
	local w = LookWorld(nil)
	Learn(w)
	Loot(w)                                    -- the look is collected now: the tag comes from the join
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 1, "lines: " .. table.concat(t, " | "))
	H.ok(t[1]:find(PANTS, 1, true), "the loot line")
	H.eq(NewLooks(t), 1, "New appearance")
	H.eq(#w.lit, 1, "one big highlight")
	H.eq(w.lit[1].line, w.shown[1], "for the loot line")
end)

H.test("epic loot that takes a look keeps its one highlight", function()
	local w = LookWorld(nil)
	w.quality = 4
	Loot(w)
	Learn(w)
	w:runTimers()
	H.eq(#Texts(w), 1, "one line")
	H.eq(#w.lit, 1, "one big highlight, the epic loot's")
end)

H.test("loot the game does not add yet keeps its New look", function()
	local w = LookWorld(nil)
	Loot(w)
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 1, "one line")
	H.eq(NewLooks(t), 1, "New look on the loot line")
	H.eq(#w.lit, 0, "no highlight, as before")
end)

H.test("a look learned later, as when you equip a Bind on Equip item, gets its own line", function()
	local w = LookWorld(nil)
	Loot(w)
	w.time = w.time + 30
	Learn(w)
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 2, "lines: " .. table.concat(t, " | "))
	H.eq(t[2], "Appearance collected: " .. PANTS, "the collection's line")
end)

H.test("with the loot tag off, the collection's line is the one New look", function()
	local w = LookWorld({ feedNewLook = false })
	Loot(w)
	Learn(w)
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 2, "lines: " .. table.concat(t, " | "))
	H.eq(NewLooks(t), 1, "New appearance")
	H.eq(t[2], "Appearance collected: " .. PANTS, "on the collection's line")
end)

H.test("with the loot tag off, the collection then loot: the collection's line is the one New look", function()
	local w = LookWorld({ feedNewLook = false })
	Learn(w)
	Loot(w)                                    -- inside the collection line's 0.5 s wait
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 2, "lines: " .. table.concat(t, " | "))
	H.eq(NewLooks(t), 1, "New appearance")
	H.eq(t[2], "Appearance collected: " .. PANTS, "on the collection's line")
end)

H.test("a secret item ID from the collection is never used: the look shows by name", function()
	local w = LookWorld(nil, true)
	local JoinLook, TakeLook, asked = w.ns.Feed.JoinLook, w.ns.Feed.TakeLook, {}
	w.ns.Feed.JoinLook = function(id) asked[#asked + 1] = id return JoinLook(id) end
	Learn(w)
	w:runTimers()
	H.eq(#asked, 0, "no join asked with a secret")
	local t = Texts(w)
	H.eq(t[#t], "Appearance collected: Frayed Pants", "the collection's line, by name")
	H.eq(TakeLook(1234), false, "and nothing waits under the secret")
end)

H.test("a look with no loot line still gets its line", function()
	local w = LookWorld(nil)
	Learn(w)
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 1, "one line")
	H.eq(t[1], "Appearance collected: " .. PANTS)
end)

-- Feed off: its lines go (and lootLines is wiped, which only frees memory:
-- a line table is never used again, Feed.lua F.Line). Asked inside the
-- 5 s window, so the window does not answer.
H.test("a loot line gone with the feed takes no look", function()
	local w = LookWorld(nil)
	Loot(w)
	w.env.HUDiniDB.showFeed = false
	w.ns.HUDini:Apply()
	w.env.HUDiniDB.showFeed = true
	w.ns.HUDini:Apply()
	H.eq(w.ns.Feed.JoinLook(1234), false, "no loot line to join")
end)

H.test("a loot line pushed out by a burst takes no look, and the look gets its own line", function()
	local w = LookWorld(nil)
	Loot(w)
	local F = w.ns.Feed
	for i = 1, 20 do F.Line({ kind = "loot", key = "burst" .. i, text = "burst " .. i }) end
	H.eq(w.shown[1].alive, false, "the loot line is gone")
	Learn(w)
	w:runTimers()
	local last = Texts(w)
	H.eq(last[#last], "Appearance collected: " .. PANTS, "the collection's line")
end)

-- Ammo is never a look (TICK-0123). On Forever, when a hunter's arrows ran out,
-- the collection told of a new look for Rough Arrow, and the feed said
-- "New look: [Rough Arrow]". The game's own answers rule it out: the
-- item's class and slot (GetItemInfoInstant), whether it can be dressed
-- (C_Item.IsDressableItemByID), and the source's own flags.

local ARROW = "|cffffffff|Hitem:2512::::::::1:::::::|h[Rough Arrow]|h|r"
local ARROW_SOURCE = 78
local CLOAK_SOURCE = 79   -- a source for an item the game cannot dress you in

-- LookWorld, with the arrow, the item answers a Forever client gives, and
-- sources for the arrow and the cloak. dressable: what IsDressableItemByID
-- says for the pants. secret: as for LookWorld.
local function AmmoWorld(saved, dressable, secret)
	local w = LookWorld(saved, nil, secret)
	local C_Item, T = w.env.C_Item, w.env.C_TransmogCollection
	local GetItemInfo = C_Item.GetItemInfo
	C_Item.GetItemInfo = function(item)
		if item == ARROW or item == 2512 then
			return "Rough Arrow", ARROW, 1, 5, 1, "Projectile", "Arrow", 1000, "INVTYPE_AMMO", 132382, 0, 6, 2
		end
		return GetItemInfo(item)
	end
	C_Item.GetItemInfoInstant = function(item)
		if w.instantThrows then error("item data not ready") end
		if item == ARROW or item == 2512 then
			local slot, class = w.arrowSlot or "INVTYPE_AMMO", w.arrowClass or 6
			return 2512, "Projectile", "Arrow", slot, 132382, class, 2
		end
		if item == PANTS or item == 1234 then return 1234, "Armor", "Cloth", "INVTYPE_LEGS", 134, 4, 1 end
		if item == 4000 then return 4000, "Armor", "Cloth", "INVTYPE_CLOAK", 135, 4, 1 end
	end
	C_Item.GetItemCount = function() return 200 end
	C_Item.IsDressableItemByID = function(item)
		if w.dressThrows then error("item data not ready") end
		if item == 4000 then return false end
		if item == PANTS or item == 1234 then
			if dressable == nil then return true end
			return w.dressable
		end
		return true
	end
	-- The collection would give the arrow a source of its own, not yet
	-- collected: the case the game must not show.
	local ItemSource, SourceInfo = T.GetItemInfo, T.GetSourceInfo
	T.GetItemInfo = function(link)
		if link == ARROW then return 501, ARROW_SOURCE end
		return ItemSource(link)
	end
	T.GetSourceInfo = function(id)
		if id == ARROW_SOURCE then return { itemID = 2512, name = "Rough Arrow", categoryID = 25 } end
		if id == CLOAK_SOURCE then return { itemID = 4000, name = "Odd Cloak", categoryID = 3 } end
		local info = SourceInfo(id)
		if info then info.categoryID = 10 end
		return info
	end
	w.dressable = dressable
	return w
end

H.test("the collection names an arrow: no New look line", function()
	local w = AmmoWorld(nil)
	w:fire("TRANSMOG_COLLECTION_SOURCE_ADDED", ARROW_SOURCE)
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 0, "lines: " .. table.concat(t, " | "))
end)

-- The arrow's look is not collected (w.collected is false), so without
-- the ammo rule its loot line would get the tag, as the pants' does.
H.test("looted arrows get no New look tag, and the collection's word adds none", function()
	local w = AmmoWorld(nil)
	H.eq(w.collected, false, "the arrow's look is not collected")
	w:fire("CHAT_MSG_LOOT", "You receive loot: " .. ARROW .. ".")
	w:fire("TRANSMOG_COLLECTION_SOURCE_ADDED", ARROW_SOURCE)
	w:runTimers()
	local t = Texts(w)
	H.eq(#t, 1, "lines: " .. table.concat(t, " | "))
	H.ok(t[1]:find(ARROW, 1, true), "the loot line")
	H.eq(NewLooks(t), 0, "no New look")
	H.eq(#w.lit, 0, "no highlight")
end)

H.test("an item the game cannot dress you in gets no New look line", function()
	local w = AmmoWorld(nil)
	w:fire("TRANSMOG_COLLECTION_SOURCE_ADDED", CLOAK_SOURCE)
	w:runTimers()
	H.eq(#Texts(w), 0)
end)

H.test("a source with no look category, or the hidden look, gets no line", function()
	for _, flags in ipairs({ { categoryID = 0 }, { isHideVisual = true, categoryID = 1 } }) do
		local w = AmmoWorld(nil)
		local SourceInfo = w.env.C_TransmogCollection.GetSourceInfo
		w.env.C_TransmogCollection.GetSourceInfo = function(id)
			local info = SourceInfo(id)
			if info then for k, v in pairs(flags) do info[k] = v end end
			return info
		end
		Learn(w)
		w:runTimers()
		H.eq(#Texts(w), 0, "flags: categoryID " .. tostring(flags.categoryID))
	end
end)

H.test("armor with the game's item answers still gets its New look, line and tag", function()
	local w = AmmoWorld(nil)
	Learn(w)
	w:runTimers()
	H.eq(Texts(w)[1], "Appearance collected: " .. PANTS, "the collection's line")
	local w2 = AmmoWorld(nil)
	Loot(w2)
	w2:runTimers()
	H.eq(NewLooks(Texts(w2)), 1, "the loot tag")
end)

-- Harness steps 2 and 3: a plain false drops the look; the same false,
-- flagged secret, rules nothing out and the look shows.
H.test("a secret Can it be dressed answer rules nothing out", function()
	local w = AmmoWorld(nil, false, {})
	Learn(w)
	w:runTimers()
	H.eq(#Texts(w), 0, "a plain false: no line")
	local w2 = AmmoWorld(nil, false, { [false] = true })
	Learn(w2)
	w2:runTimers()
	H.eq(Texts(w2)[1], "Appearance collected: " .. PANTS, "the same false, secret: the line")
end)

-- Each of the two ammo answers alone is enough: a client may give the
-- slot and not the class, or the class and not the slot.
H.test("the ammo slot alone, or the ammo class alone, rules the arrow out", function()
	for _, case in ipairs({ { slot = "INVTYPE_AMMO", class = 15 }, { slot = "", class = 6 } }) do
		local w = AmmoWorld(nil)
		w.arrowSlot, w.arrowClass = case.slot, case.class
		w:fire("TRANSMOG_COLLECTION_SOURCE_ADDED", ARROW_SOURCE)
		w:runTimers()
		H.eq(#Texts(w), 0, "slot " .. case.slot .. ", class " .. case.class)
	end
end)

-- An item answer that throws (its data not loaded yet) rules nothing out.
H.test("an item answer that throws changes nothing: the look still shows", function()
	for _, which in ipairs({ "instantThrows", "dressThrows" }) do
		local w = AmmoWorld(nil)
		w[which] = true
		Learn(w)
		w:runTimers()
		H.eq(Texts(w)[1], "Appearance collected: " .. PANTS, which)
	end
end)
