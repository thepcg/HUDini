-- Missing item icon (TICK-0182, D-047). The class file's missingItem rows
-- (here the test profiles of classes_fixture.lua). Out of a fight, with the
-- health bar on, an icon left of the health bar shows the first row whose
-- spell you know and whose items your bags hold none of. A row you make can
-- wake the HUD; a row you only need for a spell never does. What the player
-- sees needs DK's play.

local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

-- A world of this class that knows these spells. w.bag[id] is the count
-- GetItemCount answers (0 when not set), w.buffs[name] an aura on you,
-- w.usable[id] what IsSpellUsable answers.
local function World(class, known, edit)
	local w = H.world()
	local env = w.env
	w.class, w.className = class, class:sub(1, 1) .. class:sub(2):lower()
	w.bag, w.buffs, w.usable = {}, {}, {}
	local ids, n = {}, 9000
	for _, name in ipairs(known or {}) do
		n = n + 1
		ids[name], ids[n] = n, name
	end
	env.C_Spell.GetSpellInfo = function(name) return ids[name] and { spellID = ids[name] } or nil end
	env.C_Spell.GetSpellName = function(id) return ids[id] end
	env.IsPlayerSpell = function(id) return type(ids[id]) == "string" end
	env.C_Spell.IsSpellUsable = function(id) return w.usable[id] end
	env.C_Item.GetItemCount = function(id) return w.bag[id] or 0 end
	env.C_Item.GetItemIconByID = function(id) return 1000 + id end
	env.C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if w.buffs[name] then return { auraInstanceID = 1, name = name } end
	end
	Classes.Use(w)
	local ns = w:loadAddon()
	if edit then edit(ns.ClassProfiles()[class]) end
	ns.UpdateAlerts()
	-- The harness texture keeps no file: keep the last one here.
	local tex = ns.leftIcons.item.tex
	tex.SetTexture = function(self, file) self.file = file end
	ns.UpdateAlerts()
	return w, ns, ids
end

local function Icon(ns) return ns.leftIcons.item end
local function Shown(ns) return Icon(ns) ~= nil and Icon(ns):IsShown() end

H.test("a Mage who knows Conjure Mana Gem and has no gem sees the icon", function()
	local w, ns = World("MAGE", { "Conjure Mana Gem" })
	H.eq(Shown(ns), true, "no gem: shown")
	H.eq(Icon(ns).tex.file, 1000 + 5514, "the gem's own icon")
	w.bag[5513] = 1
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), false, "any one of the row's items counts: hidden at the bag event")
	w.bag[5513] = 0
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), true, "the gem used: shown again")
end)

H.test("a spell you do not know shows no icon", function()
	local _, ns = World("MAGE", {})
	H.eq(Shown(ns), false)
end)

H.test("a fight hides the icon, and its end shows it again", function()
	local w, ns = World("MAGE", { "Conjure Mana Gem" })
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "in a fight")
	w.combat = false
	ns.UpdateAlerts()
	H.eq(Shown(ns), true, "out of the fight")
end)

H.test("the icon needs the health bar on", function()
	local w, ns = World("MAGE", { "Conjure Mana Gem" })
	w.env.HUDiniDB.showHealth = false
	ns.UpdateAlerts()
	H.eq(Shown(ns), false)
end)

H.test("a count the game will not give counts as having the item", function()
	local w, ns = World("MAGE", { "Conjure Mana Gem" })
	w.env.C_Item.GetItemCount = function() error("no answer") end
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), false, "an error")
	w.secret = { [7] = true }
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.env.C_Item.GetItemCount = function() return 7 end
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), false, "a secret count")
end)

H.test("a saved Off wins over a row that starts on, and On brings it back", function()
	local w, ns = World("MAGE", { "Conjure Mana Gem" })
	H.eq(ns.GetMissingItem("manaGem"), true, "on from the class file")
	H.eq(ns.SetMissingItem("manaGem", false), true, "changed")
	H.eq(ns.SetMissingItem("manaGem", false), false, "same again: no change")
	H.eq(w.env.HUDiniDB.classes.MAGE.missingItem.manaGem, false, "saved per class")
	H.eq(Shown(ns), false, "off: hidden at once")
	ns.SetMissingItem("manaGem", true)
	H.eq(Shown(ns), true, "on: shown at once")
end)

H.test("a row that starts off shows nothing until you turn it on", function()
	local w, ns = World("WARLOCK", { "Create Soulstone" })
	H.eq(ns.GetMissingItem("soulstone"), false, "off from the class file")
	H.eq(Shown(ns), false, "off: hidden")
	ns.SetMissingItem("soulstone", true)
	H.eq(Shown(ns), true, "on, no stone: shown")
	w.buffs["Soulstone Resurrection"] = true
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "the stone's buff on you counts as the stone")
end)

H.test("a key not in the class file is on only when saved on", function()
	local _, ns = World("MAGE", { "Conjure Mana Gem" })
	H.eq(ns.GetMissingItem("nope"), false)
end)

H.test("the first missing row in class file order shows", function()
	local w, ns = World("WARLOCK", { "Create Soulstone", "Summon Voidwalker" })
	ns.SetMissingItem("soulstone", true)
	H.eq(Icon(ns).tex.file, 1000 + 5232, "the stone first")
	w.bag[5232] = 1
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), true, "the shard row next")
	H.eq(Icon(ns).tex.file, 1000 + 6265, "the shard's icon")
end)

-- The wake: Core.lua's ShouldShow.
local function Idle(w)
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	w.ns.HUDini.spells = { { spellID = 1 } }
end

H.test("a missing gem you can make now wakes the HUD, and /hud why says so", function()
	local w, ns, ids = World("MAGE", { "Conjure Mana Gem" })
	Idle(w)
	H.eq((ns.HUDini:ShouldShow()), false, "the game gives no usable answer: idle")
	w.usable[ids["Conjure Mana Gem"]] = true
	local show, why = ns.HUDini:ShouldShow()
	H.eq(show, true, "usable: shows")
	H.eq(why, ns.Text("why.missingItem"))
	w.usable[ids["Conjure Mana Gem"]] = false
	H.eq((ns.HUDini:ShouldShow()), false, "not usable now (no mana): idle")
	w.usable[ids["Conjure Mana Gem"]] = true
	w.bag[5514] = 1
	H.eq((ns.HUDini:ShouldShow()), false, "a gem in the bags: idle")
end)

H.test("a row you only need for a spell never wakes the HUD, but shows its icon", function()
	local w, ns, ids = World("SHAMAN", { "Reincarnation" })
	Idle(w)
	w.usable[ids.Reincarnation] = true
	H.eq(ns.MissingItemWake(), false, "no wake")
	H.eq((ns.HUDini:ShouldShow()), false, "idle")
	H.eq(Shown(ns), true, "the icon still shows when the HUD shows")
end)

H.test("/hud debug aura names the rows and the item counts", function()
	local w, ns = World("MAGE", { "Conjure Mana Gem" })
	w.env.C_Item.GetItemNameByID = function(id) if id == 5514 then return "Mana Agate" end end
	local lines = {}
	ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
	local all = table.concat(lines, "\n")
	H.ok(all:find("Missing item rows%s+1"), "the row count")
	H.ok(all:find("manaGem", 1, true), "the row's key")
	H.ok(all:find("Mana Agate", 1, true), "the item's name")
end)

-- Review nit (TICK-0182): a bag event on the login screen, before
-- PLAYER_ENTERING_WORLD, must not build the health bar before the HUD.
H.test("a bag event before login builds no health bar", function()
	local w = H.world()
	w.class, w.className = "MAGE", "Mage"
	Classes.Use(w)
	local ns = w:load(unpack(H.tocFiles()))
	local asked = 0
	local real = ns.GetBar
	ns.GetBar = function(...) asked = asked + 1 return real(...) end
	w:fire("ADDON_LOADED", "HUDini")
	w:fire("PLAYER_LOGIN")
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(asked, 0, "saved settings loaded, no world yet: no bar asked for")
	w:fire("PLAYER_ENTERING_WORLD", true, false)
	asked = 0
	w:fire("BAG_UPDATE_DELAYED")
	H.ok(asked > 0, "heard after login")
end)

-- TICK-0207: a row with few = N shows under N, with the bag count on it.
local function Few(key, n)
	return function(profile)
		for _, row in ipairs(profile.missingItem) do
			if row.key == key then row.few = n end
		end
	end
end
local function Count(ns) return Icon(ns).count:GetText() end

H.test("few: a Warlock with 2 Soul Shards sees the icon with 2; with 3 it goes", function()
	local w, ns = World("WARLOCK", { "Summon Voidwalker" }, Few("soulShard", 3))
	w.bag[6265] = 2
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), true, "2 of 3: shown")
	H.eq(Icon(ns).tex.file, 1000 + 6265, "the shard's icon")
	H.eq(Count(ns), "2", "the count on it")
	w.bag[6265] = 3
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), false, "3: hidden")
	w.bag[6265] = 0
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), true, "none: shown")
	H.eq(Count(ns), "", "none: no count, as a row with no few")
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "in a fight: hidden, as every row")
end)

H.test("few: a row with no few shows no count, and only at none", function()
	local w, ns = World("MAGE", { "Conjure Mana Gem" })
	H.eq(Count(ns), "", "no gem: no count")
	w.bag[5514] = 1
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), false, "one: hidden")
end)

H.test("few: all the row's items are added, and its buff counts as one", function()
	local w, ns = World("MAGE", { "Conjure Mana Gem" }, Few("manaGem", 2))
	w.bag[5514] = 1
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Count(ns), "1", "1 of 2")
	w.bag[5513] = 1
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), false, "one of each item: 2, hidden")

	local w2, ns2 = World("WARLOCK", { "Create Soulstone" }, function(p)
		Few("soulstone", 2)(p)
		p.missingItem[2] = nil
	end)
	ns2.SetMissingItem("soulstone", true)
	w2.bag[5232] = 1
	w2:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns2), true, "1 of 2")
	w2.buffs["Soulstone Resurrection"] = true
	ns2.UpdateAlerts()
	H.eq(Shown(ns2), false, "one stone and the buff on you: 2, hidden")
end)

-- TICK-0223: the first row at none goes before an earlier row with a few
-- left (dev-warlock: the Soul Shard row hid a missing Healthstone).
H.test("few: a row at none goes before an earlier row with a few left", function()
	local w, ns = World("WARLOCK", { "Create Soulstone", "Summon Voidwalker" }, Few("soulstone", 2))
	ns.SetMissingItem("soulstone", true)
	w.bag[5232] = 1
	w.bag[6265] = 0
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Icon(ns).tex.file, 1000 + 6265, "1 of 2 stones and no shard: the shard's icon")
	H.eq(Count(ns), "", "no count at none")
	w.bag[6265] = 1
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), true, "a shard: the stone row next")
	H.eq(Icon(ns).tex.file, 1000 + 5232, "the stone's icon")
	H.eq(Count(ns), "1", "with its count")
	w.bag[5232] = 0
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Icon(ns).tex.file, 1000 + 5232, "both at none: the first in class file order")
end)

H.test("few: a few left of a row you make shows its icon but never wakes the HUD", function()
	local w, ns, ids = World("MAGE", { "Conjure Mana Gem" }, Few("manaGem", 3))
	Idle(w)
	w.usable[ids["Conjure Mana Gem"]] = true
	w.bag[5514] = 1
	H.eq(ns.MissingItemWake(), false, "1 of 3: no wake")
	H.eq((ns.HUDini:ShouldShow()), false, "idle")
	ns.UpdateAlerts()
	H.eq(Shown(ns), true, "the icon shows when the HUD shows")
	w.bag[5514] = 0
	H.eq(ns.MissingItemWake(), true, "none: the wake, as before")
end)
