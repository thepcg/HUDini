-- Ammo alert (TICK-0193, D-047). With a bow, gun or crossbow: "Low ammo",
-- with the ammo's icon and count, while you carry under 200, out of a fight
-- only; "No ammo" with a red edge at 0 or with an empty ammo slot, in and
-- out of a fight. On for Hunters, off for other classes until turned on.
-- The ammo slot (0) gives the count on this client. "Low ammo" is for a
-- Hunter only; another class gets "No ammo" only, and either wakes the
-- hidden HUD for a few seconds when it starts and at a fight's start and
-- end (TICK-0236). What the player sees needs DK's play.

local BOW, ARROWS = 2504, 2512

-- A world of this class with a bow in the ranged slot and n arrows in the
-- ammo slot (nil: an empty slot). w.ammo is the slot's count, w.bagAmmo
-- the bags' count of the arrows.
local function World(class, n, edit)
	local w = H.world()
	local env = w.env
	w.class, w.className = class, class:sub(1, 1) .. class:sub(2):lower()
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w:holdItem(18, BOW, 2, 2)                    -- a bow
	w:holdItem(0, n and ARROWS or nil, 6, 2)     -- arrows, or none
	w.ammo, w.bagAmmo = n or 0, n or 0
	env.GetInventoryItemCount = function(_, slot) return slot == 0 and w.ammo or 0 end
	env.GetInventoryItemTexture = function(_, slot) return slot == 0 and 132381 or nil end
	env.C_Item.GetItemCount = function(id) return id == ARROWS and w.bagAmmo or 0 end
	if edit then edit(w) end
	local ns = w:loadAddon()
	-- The harness keeps no texture file or colour: keep the last ones here.
	local icon = ns.leftIcons.ammo
	icon.tex.SetTexture = function(self, file) self.file = file end
	icon.edge.SetColorTexture = function(self, r) self.r = r end
	ns.UpdateAlerts()
	return w, ns
end

local function Icon(ns) return ns.leftIcons.ammo end
local function Shown(ns) return Icon(ns) ~= nil and Icon(ns):IsShown() end
local function Label(ns) return Icon(ns).label:GetText() end

H.test("a Hunter with 150 arrows, out of a fight, sees Low ammo with the count", function()
	local _, ns = World("HUNTER", 150)
	H.eq(Shown(ns), true, "shown")
	H.eq(Label(ns), "Low ammo", "the words")
	H.eq(Icon(ns).count:GetText(), "150", "the count on the icon")
	H.eq(Icon(ns).tex.file, 132381, "the ammo's own icon")
	H.eq(Icon(ns).edge.r, 1, "an amber edge, not the red one")
end)

H.test("Low ammo: 199 shows, 200 does not", function()
	local w, ns = World("HUNTER", 199)
	H.eq(Shown(ns), true, "199")
	w.ammo, w.bagAmmo = 200, 200
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), false, "200: hidden at the bag event")
end)

H.test("the bags' count wins when it is more than the slot's", function()
	local w, ns = World("HUNTER", 150)
	w.bagAmmo = 400
	w:fire("BAG_UPDATE_DELAYED")
	H.eq(Shown(ns), false, "400 in the bags")
end)

H.test("the slot's count wins when it is more than the bags'", function()
	local w, ns = World("HUNTER", 150)
	H.eq(Shown(ns), true, "150 in both")
	w.ammo = 400
	w:fire("UNIT_INVENTORY_CHANGED", "player")
	H.eq(Shown(ns), false, "400 in the slot, 150 in the bags")
end)

H.test("one source the game will not give: the other one counts", function()
	-- The slot's count is secret: the bags' 150 counts.
	local w, ns = World("HUNTER", 137, function(w)
		w.bagAmmo = 150
		w.secret[137] = true
	end)
	H.eq(Shown(ns), true, "a secret slot count")
	H.eq(Icon(ns).count:GetText(), "150", "the bags' count")
	-- The slot's count errors: the bags' 150 counts.
	w.env.GetInventoryItemCount = function() error("no") end
	ns.UpdateAlerts()
	H.eq(Icon(ns).count:GetText(), "150", "a slot count error")
	-- The bags' count errors: the slot's 160 counts.
	w.ammo = 160
	w.env.GetInventoryItemCount = function(_, slot) return slot == 0 and w.ammo or 0 end
	w.env.C_Item.GetItemCount = function() error("no") end
	ns.UpdateAlerts()
	H.eq(Icon(ns).count:GetText(), "160", "a bags count error")
	-- A plain 0 from the slot with no answer from the bags: no false alarm.
	w.ammo = 0
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "0 and no answer")
end)

H.test("a fight hides Low ammo, and its end shows it again", function()
	local w, ns = World("HUNTER", 150)
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "in a fight")
	w.combat = false
	ns.UpdateAlerts()
	H.eq(Shown(ns), true, "out of the fight")
end)

H.test("an empty ammo slot shows No ammo with a red edge, in a fight too", function()
	local w, ns = World("HUNTER", nil)
	H.eq(Shown(ns), true, "shown")
	H.eq(Label(ns), "No ammo", "the words")
	H.eq(Icon(ns).count:GetText(), "", "no count")
	H.eq(Icon(ns).edge.r, 0.85, "the red edge")
	w.combat = true
	ns.UpdateAlerts()
	H.eq(Shown(ns), true, "in a fight")
end)

H.test("the last arrow shot shows No ammo at the slot event", function()
	local w, ns = World("HUNTER", 250)
	H.eq(Shown(ns), false, "250")
	w:holdItem(0, nil)
	w:fire("UNIT_INVENTORY_CHANGED", "player")
	H.eq(Shown(ns), true, "the slot is empty")
	H.eq(Label(ns), "No ammo")
end)

H.test("no bow, gun or crossbow: no alert", function()
	local w, ns = World("HUNTER", nil)
	H.eq(Shown(ns), true, "a bow: shown")
	w:holdItem(18, 3107, 2, 16) -- a thrown weapon
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "thrown")
	w:holdItem(18, 5240, 2, 18) -- a crossbow
	ns.UpdateAlerts()
	H.eq(Shown(ns), true, "a crossbow")
	w:holdItem(18, nil)
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "nothing in the ranged slot")
end)

H.test("a Warrior has it off until turned on, and the choice is per class", function()
	local w, ns = World("WARRIOR", 150)
	H.eq(ns.GetAmmoWarn(), false, "off for a Warrior")
	H.eq(Shown(ns), false, "hidden")
	H.eq(ns.SetAmmoWarn(true), true, "turned on")
	H.eq(Shown(ns), false, "150: no Low ammo for a Warrior")
	ns.SetAmmoWarn(false)
	w:holdItem(0, nil)
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "an empty slot, the alert off")
	H.eq(ns.SetAmmoWarn(true), true, "on again")
	H.eq(Shown(ns), true, "No ammo, shown at once")
	H.eq(Label(ns), "No ammo")
	H.eq(w.env.HUDiniDB.classes.WARRIOR.warnAmmo, true, "saved for the Warrior")
	H.eq(ns.SetAmmoWarn(true), false, "no change")
	w.class = "HUNTER"
	H.eq(ns.GetAmmoWarn(), true, "a Hunter keeps its own start")
	H.eq(ns.SetAmmoWarn(false), true, "a Hunter turns it off")
	H.eq(Shown(ns), false, "hidden")
	H.eq(w.env.HUDiniDB.classes.HUNTER.warnAmmo, false, "saved off")
end)

H.test("the alert needs the health bar on", function()
	local w, ns = World("HUNTER", 150)
	w.env.HUDiniDB.showHealth = false
	ns.UpdateAlerts()
	H.eq(Shown(ns), false)
end)

H.test("a secret ammo slot shows nothing", function()
	local w, ns = World("HUNTER", 0)
	H.eq(Label(ns), "No ammo", "plain: 0 arrows in the slot")
	H.eq(Shown(ns), true)
	w.secret[ARROWS] = true
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "the slot's item is secret")
end)

H.test("a secret count shows nothing", function()
	local w, ns = World("HUNTER", 137)
	H.eq(Shown(ns), true, "plain: 137 arrows")
	w.secret[137] = true
	ns.UpdateAlerts()
	H.eq(Shown(ns), false, "the count is secret")
end)

H.test("test mode: the Low ammo sample, and No bait sits left of its words", function()
	local w, ns = World("HUNTER", 500)
	H.eq(Shown(ns), false, "500: no alert")
	w.env.HUDiniDB.warnNoBait = true
	ns.ShowAlertSamples(true)
	H.eq(Shown(ns), true, "the sample")
	H.eq(Label(ns), "Low ammo")
	local bait = ns.leftIcons.bait
	H.eq(bait:IsShown(), true, "the bait sample")
	local _, rel = bait:GetPoint(1)
	H.eq(rel, Icon(ns).label, "No bait sits left of the words, not on them")
	ns.ShowAlertSamples(false)
	H.eq(Shown(ns), false, "back to the game's answer")
end)

H.test("/hud debug aura: the ammo slot's item and count", function()
	local _, ns = World("HUNTER", 150)
	local lines = {}
	ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
	local text = table.concat(lines, "\n")
	H.ok(text:find("item " .. ARROWS .. ", count 150, alert now low", 1, true), "the slot line")
	H.ok(text:find("Ammo alert on", 1, true), "the on line")
end)

H.test("/hud debug aura: an empty slot says empty, a secret one cannot tell", function()
	local w, ns = World("HUNTER", nil)
	local function Report()
		local lines = {}
		ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
		return table.concat(lines, "\n")
	end
	H.ok(Report():find("item empty, count 0, alert now no", 1, true), "empty")
	w:holdItem(0, ARROWS, 6, 2)
	w.secret[ARROWS] = true
	H.ok(Report():find("item cannot tell,", 1, true), "secret")
	w.env.GetInventoryItemID = function() error("no") end
	H.ok(Report():find("item cannot tell,", 1, true), "an error")
end)

-- TICK-0236: the wake (Core.lua's ShouldShow), and Low ammo only for Hunters.
local function Idle(w)
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	w.ns.HUDini.spells = { { spellID = 1 } }
end

H.test("a Hunter under 200 arrows wakes the hidden HUD, and /hud why names the ammo", function()
	local w, ns = World("HUNTER", 250)
	Idle(w)
	H.eq((ns.HUDini:ShouldShow()), false, "250: idle")
	w.ammo, w.bagAmmo = 150, 150
	w:fire("BAG_UPDATE_DELAYED")
	local show, why = ns.HUDini:ShouldShow()
	H.eq(show, true, "150: shows")
	H.eq(why, ns.Text("why.ammo"))
	w:holdItem(0, nil)
	ns.UpdateAlerts()
	show, why = ns.HUDini:ShouldShow()
	H.eq(show, true, "no ammo: shows")
	H.eq(why, ns.Text("why.ammo"))
	ns.SetAmmoWarn(false)
	H.eq((ns.HUDini:ShouldShow()), false, "the alert off: no wake")
end)

H.test("the ammo wake ends after a few seconds, and comes back at a fight's end", function()
	local w, ns = World("HUNTER", 150)
	Idle(w)
	H.eq((ns.HUDini:ShouldShow()), true, "150: the wake")
	w.time = w.time + 11
	H.eq((ns.HUDini:ShouldShow()), false, "11 s on: the HUD can hide, Low ammo or not")
	H.eq(Shown(ns), true, "the icon is still there for the next show")
	w.combat = true
	ns.UpdateAlerts()
	w.time = w.time + 30
	w.combat = false
	ns.UpdateAlerts()
	H.eq((ns.HUDini:ShouldShow()), true, "the fight's end: the wake again")
	w.time = w.time + 11
	H.eq((ns.HUDini:ShouldShow()), false, "and its end")
	w:holdItem(0, nil)
	ns.UpdateAlerts()
	H.eq((ns.HUDini:ShouldShow()), true, "low to none: the wake again")
	w.time = w.time + 11
	H.eq((ns.HUDini:ShouldShow()), false, "No ammo too ends: a wrong slot read cannot hold the HUD")
end)

H.test("No ammo stays through a fight: its end wakes the HUD again", function()
	local w, ns = World("HUNTER", nil)
	Idle(w)
	w.time = w.time + 11
	H.eq((ns.HUDini:ShouldShow()), false, "11 s on")
	w.combat = true
	ns.UpdateAlerts()
	w.time = w.time + 30
	w.combat = false
	ns.UpdateAlerts()
	H.eq((ns.HUDini:ShouldShow()), true, "the fight's end")
end)

H.test("a dead or ghost Hunter with no ammo: no wake", function()
	local w, ns = World("HUNTER", nil)
	Idle(w)
	w.env.UnitIsDeadOrGhost = function() return true end
	H.eq((ns.HUDini:ShouldShow()), false, "a ghost")
	w.env.UnitIsDeadOrGhost = function() return false end
	H.eq((ns.HUDini:ShouldShow()), true, "alive again, in the wake's time")
end)

H.test("a Rogue with the alert on gets No ammo only, as a Warrior does", function()
	local w, ns = World("ROGUE", 100)
	ns.SetAmmoWarn(true)
	H.eq(ns.AmmoState(), nil, "100: no low state")
	H.eq(Shown(ns), false, "no Low ammo")
	w:holdItem(0, nil)
	ns.UpdateAlerts()
	H.eq(ns.AmmoState(), "no")
	H.eq(Label(ns), "No ammo")
end)

H.test("a Warrior with the alert on: 100 arrows give nothing, 0 give No ammo and the wake", function()
	local w, ns = World("WARRIOR", 100)
	Idle(w)
	ns.SetAmmoWarn(true)
	H.eq(ns.AmmoState(), nil, "no low state for a Warrior")
	H.eq(Shown(ns), false, "no Low ammo")
	H.eq((ns.HUDini:ShouldShow()), false, "no wake")
	w.ammo, w.bagAmmo = 0, 0
	ns.UpdateAlerts()
	H.eq(ns.AmmoState(), "no")
	H.eq(Shown(ns), true, "No ammo")
	H.eq(Label(ns), "No ammo")
	local show, why = ns.HUDini:ShouldShow()
	H.eq(show, true, "the wake")
	H.eq(why, ns.Text("why.ammo"))
end)

H.test("test mode: a Warrior's sample is No ammo", function()
	local _, ns = World("WARRIOR", 500)
	ns.SetAmmoWarn(true)
	ns.ShowAlertSamples(true)
	H.eq(Shown(ns), true, "the sample")
	H.eq(Label(ns), "No ammo")
	H.eq(Icon(ns).count:GetText(), "", "no count")
	ns.ShowAlertSamples(false)
	H.eq(Shown(ns), false, "back to the game's answer")
end)
