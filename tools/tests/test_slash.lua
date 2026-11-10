-- Core.lua: /hud version, /hud debug and /hud reset (TICK-0005, TICK-0006,
-- TICK-0047). Ported from those tickets' scratch tests.

-- The copy of D-029 (TICK-0134): the tests read each line from the locale,
-- at level 0, so a change of words does not break them.
local function L(w, key, ...)
	return w.ns.TEXT[0][key]:format(...)
end

local function Logged()
	local w = H.world()
	w:loadAddon()
	w.printed = {}
	return w
end

H.test("/hud version says the version from the toc", function()
	local w = Logged()
	w:slash("/hud version")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "about.versionLine", "9.9.9")), "version line")
end)

H.test("no line at login", function()
	local w = H.world()
	w:loadAddon()
	H.eq(#w.printed, 0, "lines printed at login")
end)

-- How many SLASH_ globals say /rl (any case).
local function ReloadOwners(w)
	local n = 0
	for k, v in pairs(w.env) do
		if type(k) == "string" and k:find("^SLASH_") and type(v) == "string"
				and v:lower() == "/rl" then
			n = n + 1
		end
	end
	return n
end

H.test("/rl reloads when no other addon has it, and /hud help names it", function()
	local w = Logged()
	H.eq(ReloadOwners(w), 1, "owners of /rl")
	w:slash("/rl")
	H.eq(w.log.reload, 1, "reloads")
	w:slash("/hud help")
	H.ok(H.printed(w, "Shortcut:|r " .. L(w, "help.rl")), "help line")
end)

H.test("another addon's /rl is left alone, and /hud help does not name it", function()
	local w = H.world()
	-- An addon that loads before HUDini, or after it but before login.
	local theirs = 0
	w.env.SLASH_OTHERRELOAD1 = "/RL"
	w.env.SlashCmdList.OTHERRELOAD = function() theirs = theirs + 1 end
	w:loadAddon()
	H.eq(w.env.SlashCmdList.HUDINIRELOAD, nil, "HUDini's /rl")
	H.eq(ReloadOwners(w), 1, "owners of /rl")
	w:slash("/rl")
	H.eq(theirs, 1, "their /rl ran")
	H.eq(w.log.reload, 0, "HUDini did not reload")
	w.printed = {}
	w:slash("/hud help")
	H.ok(not H.printed(w, "/rl"), "help names /rl")
end)

H.test("/hud debug list runs its tool", function()
	local w = Logged()
	w:slash("/hud debug list")
	H.ok(#w.printed > 0, "/hud debug list printed nothing")
end)

H.test("/hud debug alone, or with an unknown word, lists the tools", function()
	local w = Logged()
	w:slash("/hud debug")
	H.ok(H.printed(w, "Diagnostic tools:"), "title line")
	H.ok(H.printed(w, L(w, "debug.helpLine", "aura", L(w, "debug.aura"))), "aura row")
	w.printed = {}
	w:slash("/hud debug foo")
	H.ok(H.printed(w, L(w, "debug.noTool", "foo")), "unknown tool")
	H.ok(H.printed(w, L(w, "debug.helpLine", "list", L(w, "debug.list"))), "list row")
end)

H.test("an unknown command says so", function()
	local w = Logged()
	w:slash("/hud frobnicate")
	H.ok(H.printed(w, L(w, "command.unknownHint", "frobnicate")), "no command line")
	-- TICK-0129: the setting went, so its word did too.
	w:slash("/hud castheight 20")
	H.ok(H.printed(w, L(w, "command.unknownHint", "castheight")), "castheight")
	H.eq(w.env.HUDiniDB.castHeight, nil, "nothing saved")
end)

H.test("/hud reset settings asks first, then keeps class data and hand-built lists", function()
	local w = Logged()
	local db = w.env.HUDiniDB
	local colors = db.colors
	db.barHeight = 99
	db.classes.MAGE.x = 42
	db.auraMap = { ["Arcane Intellect"] = "Arcane Brilliance" }

	w:slash("/hud reset settings")
	H.eq(db.barHeight, 99, "asking changes nothing")
	H.ok(H.printed(w, L(w, "reset.confirm", 30)), "ask line")

	w:slash("/hud reset yes")
	H.eq(db.barHeight, w.ns.defaults.barHeight, "barHeight back to default")
	H.eq(db.classes.MAGE.x, 42, "class position kept")
	H.eq(db.auraMap["Arcane Intellect"], "Arcane Brilliance", "buff pairs kept")
	H.ok(db.colors == colors, "the colors table is emptied in place, not swapped")
	H.ok(H.printed(w, "Shared settings reset."), "done line")
end)

H.test("/hud reset yes after 30 seconds, or after no, does nothing", function()
	local w = Logged()
	local db = w.env.HUDiniDB
	db.barHeight = 99
	w:slash("/hud reset settings")
	w.time = w.time + 31
	w:slash("/hud reset yes")
	H.eq(db.barHeight, 99, "too late")
	H.ok(H.printed(w, L(w, "reset.nothing")), "too late line")

	w:slash("/hud reset settings")
	w:slash("/hud reset no")
	w:slash("/hud reset yes")
	H.eq(db.barHeight, 99, "canceled")
end)

H.test("/hud reset class clears only this class", function()
	local w = Logged()
	local db = w.env.HUDiniDB
	db.classes.MAGE.x = 42
	db.classes.SHAMAN = { x = 7 }
	db.barHeight = 99
	w:slash("/hud reset class")
	w:slash("/hud reset yes")
	H.eq(db.classes.MAGE.x, nil, "mage cleared")
	H.eq(db.classes.SHAMAN.x, 7, "shaman kept")
	H.eq(db.barHeight, 99, "settings kept")
	H.ok(H.printed(w, L(w, "reset.doneClass", "Mage")), "done line")
end)

-- TICK-0019: /hud keeps only the commands with no row in the options.

H.test("/hud help lists the HUD, your lists and help", function()
	local w = Logged()
	w:slash("/hud help")
	H.ok(H.printed(w, L(w, "help.section.hud") .. ":|r options, setup, why, lock, unlock, test"), "HUD and setup")
	H.ok(H.printed(w, L(w, "help.section.lists") .. ":|r buffs [forget Name|clear], auramap [Spell = Buff], feedignore [item|clear], feedsession [reset], xp reset"), "Lists and session totals")
	H.ok(H.printed(w, L(w, "help.section.help") .. ":|r help [command], version, debug list|api|aura|modules|ids|weapon, reset settings|class|yes|no"), "Help and troubleshooting")
end)

H.test("a word with no command changes nothing", function()
	local w = Logged()
	local before = H.copy(w.env.HUDiniDB)
	w:slash("/hud size 99")
	w:slash("/hud show off")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "command.unknownHint", "size")), "says so")
	H.eq(H.diff(w.env.HUDiniDB, before), nil, "the saved settings")
end)

H.test("/hud xp reset starts a new session; /hud xp alone says how", function()
	local w = H.world()
	local ns = w:loadAddon()
	local resets = 0
	ns.ResetXPSession = function() resets = resets + 1 end
	w:slash("/hud xp")
	H.eq(resets, 0, "no reset without the word")
	H.ok(H.printed(w, L(w, "command.xp")), "how")
	w:slash("/hud xp RESET")
	H.eq(resets, 1, "reset")
	H.ok(H.printed(w, "Experience-rate session reset."))
end)

H.test("/hud, /hud options and /hud config open the options", function()
	local w = H.world()
	local ns = w:loadAddon()
	local opened = 0
	ns.OpenOptions = function() opened = opened + 1 end
	w:slash("/hud")
	w:slash("/hud options")
	w:slash("/hud config")
	H.eq(opened, 3)
end)

-- The copy pass (TICK-0027): chat lines in the glossary's format.

H.test("/hud alone opens the options and says nothing; in a fight it says why, then the way to the commands", function()
	local w = Logged()
	local ns = w.ns
	local opened = 0
	w.env.Settings.OpenToCategory = function() opened = opened + 1 end
	ns.category = { GetID = function() return 7 end }
	w:slash("/hud")
	H.eq(opened, 1, "opened")
	H.eq(#w.printed, 0, "no line when the options open")
	w.env.InCombatLockdown = function() return true end
	w:slash("/hud")
	H.eq(opened, 1, "not in a fight")
	H.ok(H.printed(w, "Options cannot open during combat. Try /hud afterward."), "fight line")
	H.ok(H.printed(w, "Use /hud help for commands."), "the way to the commands")
end)

H.test("/hud lock and /hud unlock say the Lock the HUD setting", function()
	local w = Logged()
	w:slash("/hud unlock")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "lock.off")), "unlock line")
	w:slash("/hud lock")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "lock.on")), "lock line")
end)

H.test("/hud why prints one line; /hud debug weapon prints the weapon buff report", function()
	local w = H.world()
	w.class = "SHAMAN"
	local ns = w:loadAddon()
	ns.WeaponBuffDetail = function() return { "Weapon buff on you: none", "Main hand: Axe. Needs a weapon buff: yes." } end
	w.printed = {}
	w:slash("/hud why")
	H.eq(#w.printed, 1, "one line")
	w.printed = {}
	w:slash("/hud debug weapon")
	H.eq(w.printed[1], "|cff33ccffHUDini|r: " .. L(w, "debug.weaponTitle"), "title")
	H.eq(w.printed[2], "  Weapon buff on you: none", "indented line")
	H.eq(w.printed[3], "  Main hand: Axe. Needs a weapon buff: yes.", "indented line")
end)

H.test("/hud buffs: the list, forget one, a name that is not tracked, clear", function()
	local w = Logged()
	local ns = w.ns
	ns.ClassDB().buffSpells = { ["Arcane Intellect"] = true, ["Frost Armor"] = true }
	w:slash("/hud buffs")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "buffs.list", "Arcane Intellect, Frost Armor")), "list")
	w:slash("/hud buffs forget Ice Armor")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "buffs.notTracked", "Ice Armor")), "not tracked")
	H.eq(ns.ClassDB().buffSpells["Frost Armor"], true, "nothing forgotten")
	w:slash("/hud buffs forget Frost Armor")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "buffs.stopped", "Frost Armor")), "forget")
	H.eq(ns.ClassDB().buffSpells["Frost Armor"], nil, "forgotten")
	w:slash("/hud buffs clear")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "buffs.cleared")), "clear")
	w:slash("/hud buffs")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "buffs.none")), "empty")
end)

H.test("/hud auramap: add, list, remove, empty", function()
	local w = Logged()
	w:slash("/hud auramap Conjure Mana Gem = Mana Gem")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "auramap.added", "Conjure Mana Gem", "Mana Gem")), "add")
	w:slash("/hud auramap")
	H.ok(H.printed(w, "HUDini|r: Conjure Mana Gem: Mana Gem."), "list")
	w:slash("/hud auramap Conjure Mana Gem =")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "auramap.removed", "Conjure Mana Gem")), "remove")
	w:slash("/hud auramap")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "auramap.none")), "empty")
end)

H.test("/hud feedignore: hide an item, show it again, the list, clear", function()
	local w = Logged()
	w.env.C_Item.GetItemNameByID = function(id) return id == 2589 and "Linen Cloth" or nil end
	w:slash("/hud feedignore 2589")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "feed.ignoreOn", "Linen Cloth")), "hide")
	w:slash("/hud feedignore")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "feed.ignoreList", "Linen Cloth")), "list")
	w:slash("/hud feedignore 2589")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "feed.ignoreOff", "Linen Cloth")), "show again")
	w:slash("/hud feedignore")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "feed.ignoreNone")), "empty")
	w:slash("/hud feedignore 2589")
	w:slash("/hud feedignore clear")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "feed.ignoreClear")), "clear")
end)

H.test("an unknown word in /hud help", function()
	local w = Logged()
	w:slash("/hud help frobnicate")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "command.unknown", "frobnicate")), "help line")
	H.ok(not H.printed(w, L(w, "command.unknownHint", "frobnicate")), "no second sentence when the list follows")
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "help.intro")), "help title")
end)

H.test("/hud debug aura: the title has the HUDini prefix, the lines under it do not; the saved report holds the title", function()
	local w = Logged()
	w:slash("/hud debug aura")
	H.eq(w.printed[1], "|cff33ccffHUDini|r: " .. L(w, "debug.resourceTitle"), "title through Say")
	H.eq(w.printed[2], "  Live aura check:", "line through Detail")
	for i = 2, #w.printed - 1 do
		H.ok(not w.printed[i]:find("HUDini|r:", 1, true), "no prefix on line " .. i .. ": " .. w.printed[i])
	end
	H.ok(H.printed(w, "HUDini|r: " .. L(w, "debug.saved")), "saved line")
	local saved = w.env.HUDiniDB.lastReport
	H.eq(saved[1], L(w, "debug.resourceTitle"), "title in the saved report")
	H.eq(saved[2], "  Live aura check:", "line in the saved report")
end)
