-- The minimap button and the addons button on the minimap (TICK-0020,
-- D-009): its place, the drag, the clicks,
-- the tooltip, the option that hides it, and the .toc fields. How it looks
-- on the minimap is for the test sitting.

local function Button(w) return w.env.HUDiniMinimapButton end

-- Where the button sits: x, y from the minimap's center.
local function Spot(w)
	local point, to, rel, x, y = Button(w):GetPoint(1)
	H.eq(point, "CENTER")
	H.eq(to, w.env.Minimap)
	H.eq(rel, "CENTER")
	return x, y
end

local function Near(a, b, what) H.ok(math.abs(a - b) < 0.01, ("%s: %s, want %s"):format(what, a, b)) end

-- The harness minimap: 198 px across, so the button's radius is 99 + 5.
local R = 104

local function Tip(w)
	local tip = w.env.GameTooltip
	local out = { tip.__h.text }
	for _, line in ipairs(tip.__h.lines) do out[#out + 1] = line end
	return table.concat(out, " / ")
end

-- Spy on the two things a click opens.
local function Spy(ns)
	local got = {}
	ns.OpenOptions = function() got[#got + 1] = "options" end
	ns.OpenSetup = function() got[#got + 1] = "setup" end
	return got
end

H.test("a new install shows the button on the minimap edge, at the bottom left", function()
	local w = H.world()
	w:loadAddon()
	local b = Button(w)
	H.ok(b, "made at login")
	H.ok(b:IsShown())
	H.eq(b:GetParent(), w.env.Minimap, "a child of the minimap: it fades and hides with it")
	H.eq(b:IsProtected(), false, "a plain button: it works in a fight")
	H.eq(w.env.HUDiniDB.minimapButton, true)
	H.eq(w.env.HUDiniDB.minimapAngle, 225)
	local x, y = Spot(w)
	Near(x, -R * math.sqrt(0.5), "x")
	Near(y, -R * math.sqrt(0.5), "y")
end)

H.test("left-click opens the options, right-click runs HUDini setup", function()
	local w = H.world()
	local ns = w:loadAddon()
	local got = Spy(ns)
	w:Run(Button(w), "OnClick", "LeftButton")
	w:Run(Button(w), "OnClick", "RightButton")
	H.eq(table.concat(got, ","), "options,setup")
end)

H.test("the addons button on the minimap: the same two clicks", function()
	local w = H.world()
	local ns = w:loadAddon()
	local got = Spy(ns)
	w.env.HUDini_OnAddonCompartmentClick("HUDini", "LeftButton")
	w.env.HUDini_OnAddonCompartmentClick("HUDini", "RightButton")
	H.eq(table.concat(got, ","), "options,setup")
end)

H.test("a drag moves the button around the edge; its place is saved and kept after /reload", function()
	local w = H.world()
	w:loadAddon()
	local b = Button(w)
	w:Run(b, "OnDragStart")
	H.ok(b:GetScript("OnUpdate"), "follows the cursor while dragging")
	w.cursor = { 1000, 700 }          -- straight above the minimap's center
	w:Run(b, "OnUpdate", 0.01)
	local x, y = Spot(w)
	Near(x, 0, "x at the top")
	Near(y, R, "y at the top")
	w.cursor = { 900, 600 }           -- straight left
	w:Run(b, "OnUpdate", 0.01)
	w:Run(b, "OnDragStop")
	H.eq(b:GetScript("OnUpdate"), nil, "stops after the drag")
	Near(w.env.HUDiniDB.minimapAngle, 180, "saved")
	x, y = Spot(w)
	Near(x, -R, "x at the left")
	Near(y, 0, "y at the left")
	-- A /reload: a new session with the same table.
	local w2 = H.world()
	w2.env.HUDiniDB = w.env.HUDiniDB
	w2:loadAddon()
	x, y = Spot(w2)
	Near(x, -R, "kept after /reload")
	Near(y, 0, "kept after /reload")
end)

H.test("a drag stops when the minimap hides (Minimap only on mouseover)", function()
	local w = H.world()
	w:loadAddon()
	local b = Button(w)
	w:Run(b, "OnDragStart")
	w.cursor = { 1000, 700 }
	w:Run(b, "OnUpdate", 0.01)
	-- The mouse leaves the minimap mid-drag: it hides, and the game runs
	-- the button's OnHide (the harness does not pass a hide to children,
	-- so the test does). No OnDragStop comes.
	w.env.Minimap:Hide()
	w:Run(b, "OnHide")
	w.env.Minimap:Show()
	H.eq(b:GetScript("OnUpdate"), nil, "does not follow the cursor after")
	Near(w.env.HUDiniDB.minimapAngle, 90, "kept where the drag left it")
	w:Run(b, "OnEnter")
	H.ok(w.env.GameTooltip:IsOwned(b), "the tooltip shows again")
end)

H.test("the drag reads the cursor at the minimap's scale", function()
	local w = H.world()
	w:loadAddon()
	w.env.Minimap:SetScale(2)
	local b = Button(w)
	w:Run(b, "OnDragStart")
	w.cursor = { 2000, 1400 }         -- (1000, 700) at scale 2: straight above
	w:Run(b, "OnUpdate", 0.01)
	w:Run(b, "OnDragStop")
	Near(w.env.HUDiniDB.minimapAngle, 90, "the top")
end)

H.test("on a square minimap the button goes out to the corners", function()
	local w = H.world()
	w.env.GetMinimapShape = function() return "SQUARE" end
	w.env.HUDiniDB = { schema = 99, welcomeSeen = true, minimapAngle = 30 }
	w:loadAddon()
	local x, y = Spot(w)
	local d = math.sqrt(2) * R - 10
	Near(x, R, "x held at the edge")
	Near(y, 0.5 * d, "y")
end)

H.test("the option hides the button and shows it again", function()
	local w = H.world()
	local ns = w:loadAddon()
	local db = w.env.HUDiniDB
	db.minimapButton = false
	ns.HUDini:Apply()
	H.ok(not Button(w):IsShown(), "hidden")
	db.minimapButton = true
	ns.HUDini:Apply()
	H.ok(Button(w):IsShown(), "shown")
	-- Off at login: the button is never made.
	local w2 = H.world()
	w2.env.HUDiniDB = { schema = 99, welcomeSeen = true, minimapButton = false }
	w2:loadAddon()
	H.eq(Button(w2), nil)
end)

H.test("the tooltip: HUDini, the two clicks, and the drag line on the button only", function()
	local w = H.world()
	w:loadAddon()
	local b = Button(w)
	w:Run(b, "OnEnter")
	H.ok(w.env.GameTooltip:IsOwned(b))
	local T = w.ns.TEXT[0]
	H.eq(Tip(w), table.concat({ "HUDini", T["minimap.left"], T["minimap.right"], T["minimap.drag"] }, " / "))
	w:Run(b, "OnLeave")
	H.ok(not w.env.GameTooltip:IsShown())
	local entry = w:Frame()
	w.env.HUDini_OnAddonCompartmentEnter("HUDini", entry)
	H.ok(w.env.GameTooltip:IsOwned(entry))
	H.eq(Tip(w), table.concat({ "HUDini", T["minimap.left"], T["minimap.right"] }, " / "))
	w.env.HUDini_OnAddonCompartmentLeave("HUDini", entry)
	H.ok(not w.env.GameTooltip:IsShown())
	-- No tooltip while dragging.
	w:Run(b, "OnDragStart")
	w.env.GameTooltip:Show()
	w:Run(b, "OnEnter")
	H.ok(not w.env.GameTooltip:IsOwned(b), "not while dragging")
	w:Run(b, "OnDragStop")
end)

H.test("in a fight the options say they cannot open; setup waits for the fight's end", function()
	local w = H.world()
	local ns = w:loadAddon()
	local opened = 0
	ns.category = { GetID = function() return 7 end }
	w.env.Settings.OpenToCategory = function(id) H.eq(id, 7); opened = opened + 1 end
	w.combat = true
	w:Run(Button(w), "OnClick", "LeftButton")
	H.eq(opened, 0, "the panel is not opened in a fight")
	H.ok(H.printed(w, "|cff33ccffHUDini|r: " .. ns.TEXT[0]["options.inCombat"]))
	w:Run(Button(w), "OnClick", "RightButton")
	H.ok(H.printed(w, "Setup will open after combat."))
	-- A drag in a fight is a plain button moving.
	w:Run(Button(w), "OnDragStart")
	w.cursor = { 1000, 700 }
	w:Run(Button(w), "OnUpdate", 0.01)
	w:Run(Button(w), "OnDragStop")
	H.eq(#w:takeBlocked(), 0, "nothing is blocked")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	ns.OpenOptions()
	H.eq(opened, 1, "after the fight it opens")
end)

H.test("the .toc names the top-hat icon and the three menu functions", function()
	local w = H.world()
	w:loadAddon()
	local toc = H.readFile("HUDini.toc")
	H.ok(toc:find("## IconTexture: Interface\\AddOns\\HUDini\\Media\\icon\n", 1, true), "the icon")
	local n = 0
	for field, fn in toc:gmatch("## (AddonCompartmentFunc%a*): (%S+)") do
		n = n + 1
		H.eq(type(w.env[fn]), "function", field .. " -> " .. fn)
	end
	H.eq(n, 3, "click, enter and leave")
end)
