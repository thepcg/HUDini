-- The gryphons at both ends of Action Bar 1 (D-024, TICK-0089). On WoW
-- Forever each gryphon is an Edit Mode system frame
-- (Blizzard_ActionBar/Camelot/MainMenuBarEndCaps.xml), with its own Hide
-- check box in Edit Mode. HUDini's old Hide gryphons set the alpha of
-- MainActionBar.EndCaps, and Edit Mode then threw a taint error. HUDini now
-- never touches EndCaps or either gryphon: no read, no call, no write.

-- A spy frame: every field read or write on it is logged in touched. A
-- read of a key in children logs too, and gives that child.
local function Spy(touched, name, children)
	return setmetatable({}, {
		__index = function(_, k)
			touched[#touched + 1] = name .. "." .. tostring(k)
			if children and children[k] then return children[k] end
			return function() end
		end,
		__newindex = function(_, k)
			touched[#touched + 1] = name .. "." .. tostring(k) .. "="
		end,
	})
end

-- A world with Action Bar 1 as barName, its EndCaps and the two gryphons
-- as spies, logged in with saved.
local function World(saved, barName)
	local w = H.world()
	w.touched = {}
	local bar = w:Frame(barName or "MainActionBar", nil, { protected = true })
	-- The gryphons are EndCaps' parentKey children, with no global name
	-- (Camelot/MainMenuBarEndCaps.xml:8, :20), so code reaches them only
	-- through EndCaps. Each read on the way is logged, and so is any call
	-- on a gryphon.
	local gryphons = {
		LeftEndCap = Spy(w.touched, "LeftEndCap"),
		RightEndCap = Spy(w.touched, "RightEndCap"),
	}
	rawset(bar, "EndCaps", Spy(w.touched, "EndCaps", gryphons))
	w.env.HUDiniDB = saved
	local ns = w:loadAddon()
	w:runTimers()
	return w, ns
end

local function Touched(w) return table.concat(w.touched, ",") end

H.test("an old save with Hide gryphons on leaves the gryphons alone at login", function()
	for _, barName in ipairs({ "MainActionBar", "MainMenuBar" }) do
		local w = World({ hideGryphons = true }, barName)
		H.eq(Touched(w), "", barName .. ": nothing read, called or written")
	end
end)

H.test("no setting, fight or test mode touches the gryphons", function()
	local w, ns = World({ hideGryphons = true })
	local db, hud = w.env.HUDiniDB, ns.HUDini
	for i, on in ipairs({ true, false, true, false }) do
		db.hideGryphons = on
		db.bagBarMouseover, db.menuBarMouseover = on, on
		hud:Apply()
		H.eq(Touched(w), "", "Apply " .. i)
	end
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	hud:Apply()
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.eq(Touched(w), "", "a fight")
	ns.FeedTest = function() end -- the harness has no item API for it
	w:slash("/hud test")
	w:slash("/hud test")
	H.eq(Touched(w), "", "test mode")
end)

H.test("the saved key is gone from the defaults", function()
	local _, ns = World(nil)
	H.eq(ns.defaults.hideGryphons, nil)
end)

H.test("the Edit Mode box is named in the game's own words", function()
	local w, ns = World(nil)
	w.env.HUD_EDIT_MODE_SETTING_END_CAP_HIDDEN = "Hide Gryphon"
	H.eq(ns.GryphonBoxName(), "Hide Gryphon")
	-- A client with no such string gets HUDini's own word.
	w.env.HUD_EDIT_MODE_SETTING_END_CAP_HIDDEN = nil
	H.eq(ns.GryphonBoxName(), ns.TEXT[0]["gryphons.box"])
end)
