-- Core.lua and Classes.lua: the defaults a new install gets, and what a
-- saved table keeps at login.

local function Login(saved)
	local w = H.world()
	w.env.HUDiniDB = saved
	w:loadAddon()
	return w, w.env.HUDiniDB
end

H.test("a new install gets every default", function()
	local w, db = Login(nil)
	for k, v in pairs(w.ns.defaults) do
		if type(v) == "table" then
			for k2, v2 in pairs(v) do H.eq(db[k][k2], v2, k .. "." .. tostring(k2)) end
		else
			H.eq(db[k], v, k)
		end
	end
end)

H.test("a saved value is kept, and a missing one gets its default", function()
	local w, db = Login({ barHeight = 14, colors = { health = { 1, 0, 0 } } })
	H.eq(db.barHeight, 14, "barHeight")
	H.eq(db.showHealth, w.ns.defaults.showHealth, "showHealth")
	H.eq(db.colors.health[1], 1, "saved color")
	for k in pairs(w.ns.defaults.colors) do
		H.ok(db.colors[k] ~= nil, "color " .. tostring(k) .. " filled in")
	end
end)

H.test("a class seen for the first time starts at the account-wide position", function()
	local _, db = Login({ point = "CENTER", relPoint = "CENTER", x = 12, y = -80 })
	local mage = db.classes.MAGE
	H.eq(mage.point, "CENTER", "point")
	H.eq(mage.x, 12, "x")
	H.eq(mage.y, -80, "y")

	-- A class that has its own position keeps it.
	_, db = Login({ x = 12, y = -80, classes = { MAGE = { point = "TOP", x = 1, y = 2 } } })
	H.eq(db.classes.MAGE.x, 1, "own x kept")
	H.eq(db.classes.MAGE.point, "TOP", "own point kept")
end)

H.test("a second login changes nothing", function()
	local saved = { barHeight = 12, healthHeight = 24, showPower = false, warnDispel = false,
		x = 5, y = 6, point = "CENTER", relPoint = "CENTER" }
	local _, first = Login(saved)
	local snapshot = H.copy(first)
	local _, second = Login(first)
	H.eq(H.diff(second, snapshot), nil)
end)
