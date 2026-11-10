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
