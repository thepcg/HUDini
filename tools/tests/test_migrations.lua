-- Core.lua ns.Migrate (TICK-0011): the schema number and the numbered steps
-- that change a saved table to today's shape, once. Saved tables start at
-- ns.FIRST_SCHEMA; the steps (ns.migrations) come after it.

local function Login(saved)
	local w = H.world()
	w.env.HUDiniDB = saved
	w:loadAddon()
	return w, w.env.HUDiniDB
end

-- The number after the last step.
local function Last(ns) return ns.FIRST_SCHEMA + #ns.migrations end

H.test("a new install starts at the last number and sees setup", function()
	local w, db = Login(nil)
	H.eq(db.schema, Last(w.ns), "schema number")
	H.eq(db.welcomeSeen, nil, "setup not marked seen")
	local _, again = Login(db)
	H.eq(again.welcomeSeen, nil, "still not seen at the next login")
end)

H.test("a saved table at the first number keeps every setting", function()
	local w = H.world()
	w:loadAddon()
	local saved = { schema = w.ns.FIRST_SCHEMA, welcomeSeen = true, barHeight = 12,
		healthHeight = 30, showPower = false, warnDispel = false, hideBlizzardTarget = true,
		barNumbers = "percent", flair = 2, classes = { MAGE = { point = "BOTTOM", x = 4, y = 77 } } }
	local _, db = Login(H.copy(saved))
	for k, v in pairs(saved) do
		if type(v) ~= "table" then H.eq(db[k], v, k) end
	end
	H.eq(db.classes.MAGE.x, 4, "the class position")
	H.eq(db.classes.MAGE.point, "BOTTOM", "the class point")
end)

H.test("running the migrations twice changes nothing", function()
	local w, first = Login({ barHeight = 12, showPower = false })
	local snapshot = H.copy(first)
	w.ns.Migrate(first, false)
	H.eq(H.diff(first, snapshot), nil, "ns.Migrate again")
	local _, second = Login(first)
	H.eq(H.diff(second, snapshot), nil, "a second login")
end)

H.test("a table with no number, a lower one or not a number counts as the first", function()
	for _, schema in ipairs({ false, 1, "x" }) do
		local w, db = Login({ schema = schema or nil, barHeight = 12 })
		H.eq(db.schema, Last(w.ns), tostring(schema) .. ": schema number")
		H.eq(db.barHeight, 12, tostring(schema) .. ": barHeight kept")
	end
end)

H.test("a number from a newer HUDini is left alone", function()
	local w = H.world()
	w:loadAddon()
	local _, db = Login({ schema = Last(w.ns) + 5 })
	H.eq(db.schema, Last(w.ns) + 5, "not lowered")
end)

H.test("a class seen for the first time gets the position, after the migrations", function()
	local w = H.world()
	w:loadAddon()
	local _, db = Login({ schema = Last(w.ns), point = "TOP", relPoint = "TOP", x = 9, y = 8 })
	H.eq(db.classes.MAGE.point, "TOP", "point")
	H.eq(db.classes.MAGE.x, 9, "x")
	H.eq(db.classes.MAGE.y, 8, "y")
end)

-- Log in with test-only steps added after the shipped ones.
local function LoginWith(saved, steps, handler)
	local w = H.world()
	w.env.HUDiniDB = saved
	if handler then w.env.geterrorhandler = function() return handler end end
	w:load(unpack(H.tocFiles()))
	for _, step in ipairs(steps) do w.ns.migrations[#w.ns.migrations + 1] = step end
	w:fire("ADDON_LOADED", "HUDini")
	w:fire("PLAYER_LOGIN")
	w:fire("PLAYER_ENTERING_WORLD", true, false)
	return w, w.env.HUDiniDB
end

H.test("the first step runs on a table at the first number, once", function()
	local function count(db) db.ran = (db.ran or 0) + 1 end
	local w = H.world()
	w:loadAddon()
	local first = w.ns.FIRST_SCHEMA + #w.ns.migrations
	local w2, db = LoginWith({ schema = first }, { count })
	H.eq(db.ran, 1, "the step ran")
	H.eq(db.schema, Last(w2.ns), "schema number")
	local _, again = LoginWith(db, { count })
	H.eq(again.ran, 1, "not again")
end)

H.test("a table part way runs only the steps after its number", function()
	local w = H.world()
	w:loadAddon()
	local first = w.ns.FIRST_SCHEMA + #w.ns.migrations
	local _, db = LoginWith({ schema = first + 1 },
		{ function(t) t.one = true end, function(t) t.two = true end })
	H.eq(db.one, nil, "the step it had did not run again")
	H.eq(db.two, true, "the next step ran")
	H.eq(db.schema, first + 2, "schema number")
end)

H.test("a step that throws is reported, and the login goes on", function()
	local errors = {}
	local function count(db) db.ran = (db.ran or 0) + 1 end
	local function boom() error("step broke") end
	local function after(db) db.after = true end
	local w, db = LoginWith({}, { count, boom, after }, function(e) errors[#errors + 1] = e end)
	local shipped = Last(w.ns) - 3
	H.eq(#errors, 1, "reported once")
	H.ok(tostring(errors[1]):find("step broke", 1, true), "with its error")
	H.eq(db.schema, shipped + 1, "the number stays at the step before")
	H.eq(db.after, nil, "the steps after it do not run")
	H.eq(db.barHeight, w.ns.defaults.barHeight, "defaults filled in")
	H.eq(db.classes.MAGE.point, "CENTER", "class position filled in")

	local _, again = LoginWith(db, { count, boom, after }, function(e) errors[#errors + 1] = e end)
	H.eq(again.ran, 1, "the steps before it do not run twice")
	H.eq(#errors, 2, "tried again, and reported again")
	local _, fixed = LoginWith(again, { count, function(t) t.fixed = true end, after })
	H.eq(fixed.fixed, true, "a fixed step runs")
	H.eq(fixed.ran, 1, "the one before it still not twice")
	H.eq(fixed.after, true, "and the steps after it run")
	H.eq(fixed.schema, shipped + 3, "the number reaches the last step")
end)

H.test("a step sees only the saved table, not the defaults", function()
	local _, db = LoginWith({}, { function(t) t.sawBarHeight = t.barHeight or "none" end })
	H.eq(db.sawBarHeight, "none", "barHeight not filled in yet")
end)
