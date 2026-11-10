-- /hud unlock (TICK-0053): the blue box sits above the icons and bars and
-- covers all of them, so a full grid still has something to see and grab.

local function Unlocked()
	local w = H.world()
	w:loadAddon()
	w:slash("/hud unlock")
	return w, w.ns.HUDini
end

-- A full grid of rows x cols, laid out the way db says.
local function Grid(hud, rows, cols)
	hud.spells = {}
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			hud.spells[#hud.spells + 1] = { row = r, col = c }
		end
	end
	hud:Layout()
end

-- The box as left, right, top, bottom, from the anchor's top left.
local function Box(hud)
	local tl, br = { hud.mover:GetPoint(1) }, { hud.mover:GetPoint(2) }
	H.eq(tl[1], "TOPLEFT"); H.eq(tl[2], hud); H.eq(tl[3], "TOPLEFT")
	H.eq(br[1], "BOTTOMRIGHT"); H.eq(br[2], hud); H.eq(br[3], "TOPLEFT")
	return tl[4], br[4], tl[5], br[5]
end

-- The top edge of the bar stack, read off the bars themselves.
local function BarsTop(w, hud)
	local top
	for _, f in ipairs(w.frames) do
		local p = f.__h.points[1]
		if p and p[1] == "BOTTOMLEFT" and p[2] == hud and p[3] == "TOPLEFT" then
			local edge = p[5] + f.__h.height
			if not top or edge > top then top = edge end
		end
	end
	return top
end

H.test("unlock shows the box, takes the drag; lock hides it", function()
	local w = H.world()
	w:loadAddon()
	local hud = w.ns.HUDini
	H.eq(hud.mover:IsShown(), false, "a new install is locked: no box")
	w:slash("/hud unlock")
	H.eq(hud.mover:IsShown(), true, "unlocked: the box shows")
	H.eq(hud.mover:IsMouseEnabled(), true, "the box takes the mouse")
	H.eq(hud:IsMovable(), true, "the HUD can move")
	H.ok(hud.mover:GetFrameLevel() > hud:GetFrameLevel() + 10, "the box is above the icons and bars")
	w:slash("/hud lock")
	H.eq(hud.mover:IsShown(), false, "locked: the box hides, the icons get the mouse back")
	H.eq(hud:IsMovable(), false, "locked: the HUD cannot move")
end)

H.test("a drag on the box moves the HUD and keeps the spot per class", function()
	local w, hud = Unlocked()
	local moved = 0
	hud.StartMoving = function() moved = moved + 1 end
	w:Run(hud.mover, "OnDragStart")
	H.eq(moved, 1, "the drag moves the anchor")
	hud:ClearAllPoints()
	hud:SetPoint("CENTER", w.env.UIParent, "CENTER", 12, -34)
	w:Run(hud.mover, "OnDragStop")
	local mine = w.ns.ClassDB()
	H.eq(mine.point, "CENTER"); H.eq(mine.x, 12); H.eq(mine.y, -34)
end)

H.test("a full grid growing down and right: the box covers every icon and bar", function()
	local w, hud = Unlocked()
	local db = w.env.HUDiniDB
	db.growDown, db.growRight, db.minIcons = true, true, 1
	Grid(hud, 2, 3)
	local s, g = db.iconSize, db.spacing
	local left, right, top, bottom = Box(hud)
	H.eq(left, 0, "left")
	H.eq(right, 3 * s + 2 * g, "right")
	H.eq(bottom, -(2 * s + g), "bottom")
	H.ok(BarsTop(w, hud), "some bars are on")
	H.eq(top, BarsTop(w, hud), "top is the top bar's edge")
end)

H.test("a full grid growing up and left: the box follows the icons", function()
	local w, hud = Unlocked()
	local db = w.env.HUDiniDB
	db.growDown, db.growRight, db.minIcons = false, false, 1
	db.showHealth, db.showPower, db.showTargetHealth, db.showTargetCast = false, false, false, false
	w.ns.ShowXP = function() return false end
	Grid(hud, 3, 3)
	local s, g = db.iconSize, db.spacing
	local left, right, top, bottom = Box(hud)
	H.eq(left, -2 * (s + g), "left: two columns out to the left")
	-- The bars line up over the grid (TICK-0054), so nothing reaches right
	-- past the first column.
	H.eq(right, s, "right: the first column's right edge")
	H.eq(top, 2 * (s + g), "top: two rows up")
	H.eq(bottom, -s, "bottom")
end)

H.test("an empty grid still has a box over the bars", function()
	local w, hud = Unlocked()
	Grid(hud, 0, 0)
	local left, right, top, bottom = Box(hud)
	H.ok(right > left and top > bottom, "the box has a size")
	H.eq(top, BarsTop(w, hud), "it reaches the top bar")
end)
