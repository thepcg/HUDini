-- Feed.lua: F.Pattern turns Blizzard's chat strings into Lua patterns, so
-- the loot feed can read the lines the game prints. The strings here are the
-- enUS ones, plus the grammar codes other languages use.

local STRINGS = {
	LOOT_ITEM_SELF = "You receive loot: %s.",
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
	COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience.",
	SKILL_RANK_UP = "Your skill in %s has increased to %d.",
	FACTION_STANDING_INCREASED = "Reputation with %s increased by %d.",
	-- Word order swapped with positions, as in some languages.
	TEST_POSITIONS = "%2$d x %1$s (100%%)",
	-- A German-style word ending and a singular/plural pick.
	TEST_GRAMMAR = "Ihr erhaltet |3-1(%s) und %d |1Punkt;Punkte;.",
	TEST_DECIMAL = "Rested %.1f%%",
}

local function Feed()
	local w = H.world()
	for k, v in pairs(STRINGS) do w.env[k] = v end
	w:loadAddon()
	return w.ns.Feed
end

local F = Feed()

H.test("a loot line gives the item link", function()
	local link = "|cffffffff|Hitem:2589::::::::10:::::|h[Linen Cloth]|h|r"
	H.eq(("You receive loot: %s."):format(link):match(F.Pattern("LOOT_ITEM_SELF")), link)
end)

H.test("a stack line gives the link and the count", function()
	local link, n = ("You receive loot: [Linen Cloth]x4."):match(F.Pattern("LOOT_ITEM_SELF_MULTIPLE"))
	H.eq(link, "[Linen Cloth]", "link")
	H.eq(n, "4", "count")
end)

H.test("the single loot pattern also takes a stack line, so stacks go first", function()
	-- The count stays in the link. FeedLoot.lua tries the _MULTIPLE strings
	-- first for this reason; this test says why that order matters.
	local link = ("You receive loot: [Linen Cloth]x4."):match(F.Pattern("LOOT_ITEM_SELF"))
	H.eq(link, "[Linen Cloth]x4")
end)

H.test("an XP line: closed pattern wants the end, open allows more", function()
	local line = "Kobold Vermin dies, you gain 45 experience. (+45 exp Rested bonus)"
	H.eq(line:match(F.Pattern("COMBATLOG_XPGAIN_FIRSTPERSON")), nil, "closed")
	local who, xp = line:match(F.Pattern("COMBATLOG_XPGAIN_FIRSTPERSON", true))
	H.eq(who, "Kobold Vermin", "open: who")
	H.eq(xp, "45", "open: XP")
end)

H.test("skill and reputation lines", function()
	local skill, rank = ("Your skill in Tailoring has increased to 75."):match(F.Pattern("SKILL_RANK_UP"))
	H.eq(skill, "Tailoring"); H.eq(rank, "75")
	local who, n = ("Reputation with Stormwind increased by 250."):match(F.Pattern("FACTION_STANDING_INCREASED"))
	H.eq(who, "Stormwind"); H.eq(n, "250")
end)

H.test("numbered places, a literal percent sign, and magic characters", function()
	local n, what = ("3 x Linen Cloth (100%)"):match(F.Pattern("TEST_POSITIONS"))
	H.eq(n, "3", "count")
	H.eq(what, "Linen Cloth", "item")
end)

H.test("grammar codes stand for any text", function()
	local who, n = ("Ihr erhaltet Leinenstoffs und 5 Punkte."):match(F.Pattern("TEST_GRAMMAR"))
	H.eq(who, "Leinenstoffs", "word with ending")
	H.eq(n, "5", "count")
end)

H.test("a decimal number", function()
	H.eq(("Rested 1.5%"):match(F.Pattern("TEST_DECIMAL")), "1.5")
end)

H.test("a string this client does not have gives no pattern", function()
	H.eq(F.Pattern("NO_SUCH_STRING"), false)
end)

--------------------------------------------------------------------------------
-- F.Coins and a line that wraps (TICK-0227): a coin of size 0 was drawn a
-- line too high on a wrapped line, its room left empty, and the text ran
-- under the line's icon. Each coin now has the feed's font size.
--------------------------------------------------------------------------------

-- Every coin in a string: { kind, height, width }.
local function CoinsIn(s)
	local found = {}
	for kind, h, wd in s:gmatch("UI%-(%a+)Icon:(%-?%d+):(%-?%d+)") do
		found[#found + 1] = { kind, tonumber(h), tonumber(wd) }
	end
	return found
end

H.test("coins: each coin is as tall as the feed's text, in pixels", function()
	local w = H.world()
	w:loadAddon()
	w.env.HUDiniDB.feedFontSize = 18
	local coins = CoinsIn(w.ns.Feed.Coins(10733))
	H.eq(#coins, 3, "gold, silver and copper")
	for _, c in ipairs(coins) do
		H.eq(c[2], 18, c[1] .. ": the font's height, not 0")
		H.eq(c[3], 18, c[1] .. ": as wide as tall")
	end
	H.eq(w.ns.Feed.Coins(733):find("^7|T"), 1, "the silver count first")
end)

H.test("coins: a new font size gives new coins", function()
	local w = H.world()
	w:loadAddon()
	w.env.HUDiniDB.feedFontSize = 12
	H.eq(CoinsIn(w.ns.Feed.Coins(5))[1][2], 12, "12 px")
	w.env.HUDiniDB.feedFontSize = 22
	H.eq(CoinsIn(w.ns.Feed.Coins(5))[1][2], 22, "22 px")
end)

H.test("a line keeps a clear gap to its icon, on either side, in either outline", function()
	-- The game draws a full line of a wrapped text a few px past the
	-- string's width (TICK-0229): 4 px left no gap. 8, and 10 with the
	-- thick outline.
	local w = H.world()
	w:loadAddon()
	w.time = w.time + 10
	local db, F = w.env.HUDiniDB, w.ns.Feed
	for _, thick in ipairs({ false, true }) do
		for _, side in ipairs({ "RIGHT", "LEFT" }) do
			local name = side .. (thick and ", thick" or "")
			db.feedAlign, db.feedThickOutline = side, thick
			w.ns.ApplyFeed()
			local gap = thick and 10 or 8
			local L = F.Line({ kind = "money", key = "wrap" .. name, icon = 133784,
				text = "Sold for " .. F.Coins(733) .. ". A little room in the bags, a little coin in hand." })
			H.eq(L ~= nil, true, name .. ": the line shows")
			local icon = L.tex:GetWidth()
			H.eq(L.fs:GetWidth() + gap + icon, db.feedWidth, name .. ": text, gap and icon fill the feed")
			local p, rel, relP, x = L.tex:GetPoint(1)
			H.eq(rel, L.fs, name .. ": the icon hangs on the text")
			w:Run(w.env.HUDiniFeed, "OnUpdate", 0.1)
			local fp, _, _, fx = L.fs:GetPoint(1)
			if side == "RIGHT" then
				H.eq(p .. " " .. relP .. " " .. x, "TOPLEFT TOPRIGHT " .. gap, name .. ": right of the text")
				H.eq(fp .. " " .. fx, "BOTTOMRIGHT " .. -(icon + gap), name .. ": the text leaves the icon's room")
			else
				H.eq(p .. " " .. relP .. " " .. x, "TOPRIGHT TOPLEFT " .. -gap, name .. ": left of the text")
				H.eq(fp .. " " .. fx, "BOTTOMLEFT " .. (icon + gap), name .. ": the text leaves the icon's room")
			end
		end
	end
end)

H.test("coins: the big highlight's coins follow its own font", function()
	local w = H.world()
	w:loadAddon()
	w.time = w.time + 10
	local db, F = w.env.HUDiniDB, w.ns.Feed
	db.feedFontSize = 14
	w.ns.ApplyFeed()
	F.Highlight({ text = "[Epic Sword]  " .. F.Coins(10733) })
	local coins = CoinsIn(w.env.HUDiniFeedHighlight.text:GetText() or "")
	H.eq(#coins, 3, "the line's coins in the highlight")
	for _, c in ipairs(coins) do
		H.eq(c[2], math.floor(14 * 1.6 + 0.5), c[1] .. ": the highlight's size, not the line's")
	end
end)

H.test("coins: the session summary in chat keeps chat's own size", function()
	local w = H.world()
	w:loadAddon()
	w.time = w.time + 10
	local F = w.ns.Feed
	w.env.HUDiniDB.feedFontSize = 17
	F.session = F.session or { start = w.time }
	F.session.coin, F.session.value = 733, 10733
	w.ns.FeedSession()
	local n = 0
	for _, line in ipairs(w.printed) do
		for _, c in ipairs(CoinsIn(line)) do
			n = n + 1
			H.eq(c[2], 0, c[1] .. ": size 0, as tall as chat's text")
		end
	end
	H.eq(n, 5, "the money's 2 coins and the loot's 3")
end)

H.test("coins: a feed line is set up like a chat line, so its coins sit level", function()
	-- DK's check (TICK-0227): chat's coins sat level; the feed's, in the same
	-- font, sat high. A feed line had BOTTOM and a cap of 2 lines; chat has
	-- neither.
	local w = H.world()
	w:loadAddon()
	w.time = w.time + 10
	local F = w.ns.Feed
	local L = F.Line({ kind = "money", key = "test:jv", icon = 133784, text = "+ " .. F.Coins(733) })
	H.ok(L and L.fs, "the line's font string")
	local fs = L.fs
	local seen = {}
	rawset(fs, "SetJustifyV", function(_, v) seen.v = v end)
	rawset(fs, "SetMaxLines", function(_, n) seen.lines = n end)
	w.ns.ApplyFeed()
	H.eq(seen.v, "MIDDLE", "centered, as chat")
	H.eq(seen.lines, 0, "no line cap, as chat")
end)
