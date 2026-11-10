-- The bars line up over the icon grid in all four grow directions
-- (TICK-0054). Before, they always hung right of the anchor, so with "grow
-- left" they sat to the right of the icons, not over them.

local function World(growDown, growRight, minIcons)
	local w = H.world()
	w:loadAddon()
	local db = w.env.HUDiniDB
	db.growDown, db.growRight, db.minIcons = growDown, growRight, minIcons or 1
	return w, w.ns.HUDini, db
end

-- A full grid of rows x cols.
local function Grid(hud, rows, cols)
	hud.spells = {}
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			hud.spells[#hud.spells + 1] = { row = r, col = c }
		end
	end
	hud:Layout()
end

-- The icons' left and right edges, from the anchor's top left.
local function IconEdges(hud)
	local left, right
	for i = 1, #hud.spells do
		local f = hud.icons[i]
		local point, to, rel, x = f:GetPoint(1)
		H.eq(point, "CENTER"); H.eq(to, hud); H.eq(rel, "TOPLEFT")
		local half = f.__h.width / 2
		if not left or x - half < left then left = x - half end
		if not right or x + half > right then right = x + half end
	end
	return left, right
end

-- Every bar in the stack, as { left, right }, from the anchor's top left.
local function Bars(w, hud)
	local list = {}
	for _, f in ipairs(w.frames) do
		local p = f.__h.points[1]
		if p and p[1] == "BOTTOMLEFT" and p[2] == hud and p[3] == "TOPLEFT" then
			list[#list + 1] = { p[4], p[4] + f.__h.width }
		end
	end
	return list
end

local DIRECTIONS = {
	{ "down and right", true, true },
	{ "up and right", false, true },
	{ "down and left", true, false },
	{ "up and left", false, false },
}

for _, d in ipairs(DIRECTIONS) do
	H.test("growing " .. d[1] .. ", the bars sit over the icons", function()
		local w, hud = World(d[2], d[3])
		Grid(hud, 2, 4)
		local left, right = IconEdges(hud)
		local bars = Bars(w, hud)
		H.ok(#bars >= 3, "some bars are on")
		for i, bar in ipairs(bars) do
			H.eq(bar[1], left, "bar " .. i .. ": left edge on the leftmost icon's")
			H.eq(bar[2], right, "bar " .. i .. ": right edge on the rightmost icon's")
		end
	end)
end

-- A short grid still spans minIcons. The bars start at the first column and
-- reach out the way the grid grows.
H.test("a short grid: the bars start at the first column and grow its way", function()
	local w, hud, db = World(true, true, 6)
	Grid(hud, 1, 2)
	local s, g = db.iconSize, db.spacing
	local left = IconEdges(hud)
	for i, bar in ipairs(Bars(w, hud)) do
		H.eq(bar[1], left, "grow right, bar " .. i .. ": left edge on the first column's")
		H.eq(bar[2] - bar[1], 6 * s + 5 * g, "grow right, bar " .. i .. ": six icons wide")
	end
	local br = { hud.mover:GetPoint(2) }
	H.eq(br[4], Bars(w, hud)[1][2], "grow right: the box reaches the bars' right edge")

	db.growRight = false
	hud:Layout()
	local _, right = IconEdges(hud)
	for i, bar in ipairs(Bars(w, hud)) do
		H.eq(bar[2], right, "grow left, bar " .. i .. ": right edge on the first column's")
		H.eq(bar[2] - bar[1], 6 * s + 5 * g, "grow left, bar " .. i .. ": six icons wide")
	end
end)

H.test("growing left, the blue box covers the bars and nothing to their right", function()
	local w, hud, db = World(true, false, 6)
	w:slash("/hud unlock")
	Grid(hud, 1, 2)
	local s = db.iconSize
	local tl, br = { hud.mover:GetPoint(1) }, { hud.mover:GetPoint(2) }
	local bar = Bars(w, hud)[1]
	H.eq(tl[4], bar[1], "the box starts at the bars' left edge")
	H.eq(br[4], s, "the box ends at the first column's right edge")
end)
