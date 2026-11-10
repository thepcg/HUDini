-- Mover.lua (TICK-0004): with the window mover off, HUDini touches no window.
-- Ported from the TICK-0004 scratch test.

-- A world with Mover.lua loaded and three windows, one of them protected.
local function MoverWorld(on)
	local w = H.world()
	w.env.HUDiniDB = { moveWindows = on }
	w:Frame("CharacterFrame")
	w:Frame("SpellBookFrame", nil, { protected = true })
	w:Frame("GameMenuFrame")
	w.env.UIPanelWindows = { CharacterFrame = {}, SpellBookFrame = {} }
	w:load("Modules.lua", "Mover.lua")
	return w
end

local function Hooked(w, name)
	return w.env[name].__h.hooks.OnMouseDown ~= nil
end

local function Registered(w, event)
	for _, f in ipairs(w.frames) do
		if f.__h.events[event] then return true end
	end
	return false
end

H.test("off at login: no hook, no secure hook, no flag, no extra event", function()
	local w = MoverWorld(false)
	w:fire("PLAYER_LOGIN"); w:fire("ADDON_LOADED"); w:fire("PLAYER_REGEN_ENABLED")
	w.ns.UpdateModules()
	H.eq(w.log.hookScript, 0, "HookScript calls")
	H.eq(w.log.secure, 0, "secure hooks")
	H.eq(w.env.CharacterFrame.__h.mouse, false, "mouse flag")
	H.ok(not Registered(w, "ADDON_LOADED"), "ADDON_LOADED registered")
	H.ok(not Registered(w, "PLAYER_REGEN_ENABLED"), "PLAYER_REGEN_ENABLED registered")
end)

H.test("turned on in combat: plain windows hooked, the protected one waits", function()
	local w = MoverWorld(false)
	w:fire("PLAYER_LOGIN")
	w.combat = true
	w.env.HUDiniDB.moveWindows = true
	w.ns.UpdateModules()
	H.ok(Hooked(w, "CharacterFrame"), "CharacterFrame")
	H.ok(not Hooked(w, "SpellBookFrame"), "SpellBookFrame waits")
	H.eq(w.log.secure, 1, "ShowUIPanel hook")

	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.ok(Hooked(w, "SpellBookFrame"), "fight ends: SpellBookFrame hooked")

	w.ns.UpdateModules(); w.ns.UpdateModules()
	H.eq(w.log.secure, 1, "Apply again adds no second ShowUIPanel hook")
end)

H.test("turned off: a window that opens or loads is not hooked", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local before = w.log.hookScript
	w.env.HUDiniDB.moveWindows = false
	w.ns.UpdateModules()
	w:Frame("LateFrame")
	w.env.ShowUIPanel(w.env.LateFrame)
	w.env.UIPanelWindows.LateFrame = {}
	w:fire("ADDON_LOADED")
	H.eq(w.log.hookScript, before, "HookScript calls")
	H.ok(not Hooked(w, "LateFrame"), "LateFrame")

	w.env.HUDiniDB.moveWindows = true
	w.env.ShowUIPanel(w.env.LateFrame)
	H.ok(Hooked(w, "LateFrame"), "on again: an opened window is hooked")
end)

H.test("on again while a skipped window is open: it is hooked at once", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	w.env.HUDiniDB.moveWindows = false
	w.ns.UpdateModules()
	w:Frame("TalentFrame")
	w.env.UIPanelWindows.TalentFrame = {}
	w:fire("ADDON_LOADED")
	w.env.ShowUIPanel(w.env.TalentFrame)
	H.ok(not Hooked(w, "TalentFrame"), "skipped while off")
	w.env.HUDiniDB.moveWindows = true
	w.ns.UpdateModules()
	H.ok(Hooked(w, "TalentFrame"), "hooked when turned on")
end)

H.test("a fight ends while off: the waiting window stays unhooked until on", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	w.combat = true
	w:Frame("ProtFrame", nil, { protected = true })
	w.env.UIPanelWindows.ProtFrame = {}
	w.ns.UpdateModules()
	w.env.HUDiniDB.moveWindows = false
	w.ns.UpdateModules()
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.ok(not Hooked(w, "ProtFrame"), "still waiting")
	w.env.HUDiniDB.moveWindows = true
	w.ns.UpdateModules()
	H.ok(Hooked(w, "ProtFrame"), "hooked when turned on")
	H.eq(w.log.secure, 1, "ShowUIPanel hooks")
end)

H.test("on at login: windows hooked at login", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	H.ok(Hooked(w, "CharacterFrame"), "CharacterFrame")
	H.ok(w.env.GameMenuFrame.__h.hooks.OnHide ~= nil, "GameMenuFrame OnHide")
	H.eq(w.log.secure, 1, "ShowUIPanel hooks")
	H.ok(Registered(w, "ADDON_LOADED"), "ADDON_LOADED registered")
end)

H.test("Apply before login hooks nothing", function()
	local w = MoverWorld(true)
	w.ns.UpdateModules()
	H.eq(w.log.secure, 0, "secure hooks")
	H.eq(w.log.hookScript, 0, "HookScript calls")
end)

H.test("a moved window goes back to its place when it closes", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f = w.env.CharacterFrame
	f:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	w:Run(f, "OnMouseDown", "LeftButton")
	f.__h.points = { { "TOPLEFT", w.env.UIParent, "TOPLEFT", 50, -50 } }
	w:Run(f, "OnMouseUp", "LeftButton")
	w.keys.ctrl = true
	w:Run(f, "OnMouseWheel", 1)
	H.ok(math.abs(f.__h.scale - 1.05) < 1e-9, "Ctrl + wheel scales up")
	w:Run(f, "OnHide")
	H.eq(f.__h.points[1][1], "CENTER", "point after close")
	H.eq(f.__h.scale, 1, "scale after close")
end)

-- TICK-0063: StopMovingOrSizing is blocked on a protected window in a fight.
-- The fight's start (PLAYER_REGEN_DISABLED, before the lock) ends the drag;
-- a drag it missed ends when the fight does.
H.test("the start of a fight ends the drag of a protected window, where it is", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f, plain = w.env.SpellBookFrame, w.env.CharacterFrame
	f:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	w:Run(f, "OnMouseDown", "LeftButton")
	w:Run(plain, "OnMouseDown", "LeftButton")
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(f.__h.moving, false, "the drag ends before the lock")
	H.eq(w.ns.mover.IsMoving(f), false, "and HUDini knows")
	H.eq(f.__h.movable, false, "movable as before")
	H.eq(f.__h.points[1][1], "CURSOR", "it stays where the fight began")
	H.ok(w.ns.mover.HasHome(f), "and goes home when it closes")
	H.eq(plain.__h.moving, true, "a plain window can still move in a fight: its drag goes on")
	w.combat = true
	w:Run(f, "OnMouseUp", "LeftButton")
	w:Run(plain, "OnMouseUp", "LeftButton")
	H.eq(plain.__h.moving, false, "and ends when you let go")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(#w.blocked, 0, "nothing blocked")
end)

H.test("a drag the fight's start missed, let go of in the fight, ends when the fight ends", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f = w.env.SpellBookFrame
	H.ok(Hooked(w, "SpellBookFrame"), "hooked out of combat")
	f:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	w:Run(f, "OnMouseDown", "LeftButton")
	H.eq(f.__h.moving, true, "the drag starts")

	w.combat = true
	w:Run(f, "OnMouseUp", "LeftButton")
	H.eq(f.__h.moving, true, "let go in the fight: it still follows the mouse")
	H.eq(#w.blocked, 0, "nothing blocked")

	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.moving, false, "fight over: the drag ends")
	H.eq(w.ns.mover.IsMoving(f), false, "and HUDini knows")
	H.eq(f.__h.movable, false, "movable as before")
	H.eq(f.__h.points[1][1], "CURSOR", "still open: it stays where it is until it closes")
	H.ok(w.ns.mover.HasHome(f), "and goes home when it closes")

	-- The next fight finds nothing to finish.
	f:SetMovable(true)
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.movable, true, "a second fight end does nothing")
end)

H.test("a window closed in the fight after a stuck drag goes back to its place when the fight ends", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f = w.env.SpellBookFrame
	f:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	w:Run(f, "OnMouseDown", "LeftButton")
	w.combat = true
	w:Run(f, "OnMouseUp", "LeftButton")
	f.__h.shown = false
	w:Run(f, "OnHide")
	H.eq(f.__h.moving, true, "closed in the fight: the lock keeps the drag")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.moving, false, "the drag ends")
	-- The drag ends first: ended after GoHome, it would leave the window
	-- where the mouse is.
	H.eq(f.__h.points[1][1], "CENTER", "and it goes back to its place")
	H.eq(w.ns.mover.HasHome(f), false)
end)

H.test("a window moved before a fight and closed in it goes back to its place when the fight ends", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f = w.env.SpellBookFrame
	f:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	w:Run(f, "OnMouseDown", "LeftButton")
	w:Run(f, "OnMouseUp", "LeftButton")
	w.combat = true
	f.__h.shown = false
	w:Run(f, "OnHide")
	H.eq(#w.blocked, 0, "nothing blocked")
	H.eq(f.__h.points[1][1], "CURSOR", "closed in the fight: not moved back yet")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.points[1][1], "CENTER", "fight over: back in its place")
	-- Opened again in the fight: it stays where it is until it closes.
	w:Run(f, "OnMouseDown", "LeftButton")
	w:Run(f, "OnMouseUp", "LeftButton")
	w.combat = true
	f.__h.shown = false
	w:Run(f, "OnHide")
	f.__h.shown = true
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.points[1][1], "CURSOR", "open again when the fight ends: not moved")
	H.ok(w.ns.mover.HasHome(f), "and it goes home when it closes")
	f.__h.shown = false
	w:Run(f, "OnHide")
	H.eq(f.__h.points[1][1], "CENTER", "closed out of combat: home")
end)

-- "Move windows" turned off in a fight drops the module's events, so the
-- fight's end does not finish a stuck drag. Letting go later ends it, and
-- leaves nothing behind for a later fight.
H.test("a stuck drag ended by hand leaves nothing for a later fight", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f = w.env.SpellBookFrame
	w:Run(f, "OnMouseDown", "LeftButton")
	w.combat = true
	w:Run(f, "OnMouseUp", "LeftButton")
	w.env.HUDiniDB.moveWindows = false
	w.ns.UpdateModules()
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.moving, true, "off: the fight's end does nothing")
	w:Run(f, "OnMouseUp", "LeftButton")
	H.eq(f.__h.moving, false, "you let go: the drag ends")
	w.env.HUDiniDB.moveWindows = true
	w.ns.UpdateModules()
	-- A second drag that the fight's start misses, still held at its end.
	w:Run(f, "OnMouseDown", "LeftButton")
	w.combat = true
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.moving, true, "the mouse is still down: the drag goes on")
	w:Run(f, "OnMouseUp", "LeftButton")
	H.eq(f.__h.moving, false, "and ends when you let go")
end)

H.test("a window closed in a fight with the option off goes home when it next closes, once", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f = w.env.SpellBookFrame
	f:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	w:Run(f, "OnMouseDown", "LeftButton")
	w:Run(f, "OnMouseUp", "LeftButton")
	w.combat = true
	w.env.HUDiniDB.moveWindows = false
	w.ns.UpdateModules()
	f.__h.shown = false
	w:Run(f, "OnHide")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.points[1][1], "CURSOR", "off: the fight's end does nothing")
	f.__h.shown = true
	w:Run(f, "OnHide")
	H.eq(f.__h.points[1][1], "CENTER", "closed again: home")
	-- Moved again with the option on, then hidden without a fight: the old
	-- entry is gone, so a fight's end does not move it.
	w.env.HUDiniDB.moveWindows = true
	w.ns.UpdateModules()
	w:Run(f, "OnMouseDown", "LeftButton")
	w:Run(f, "OnMouseUp", "LeftButton")
	f.__h.shown = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.points[1][1], "CURSOR", "hidden but never closed by a fight: not moved")
end)

-- TICK-0066: a window is marked hooked before its hooks go in. If a later
-- HookScript throws, OnMouseDown is already in and can start a drag.
H.test("a window whose hooks fail part way is still seen, and hooked once", function()
	local w = H.world()
	w.env.HUDiniDB = { moveWindows = true }
	local f = w:Frame("BrokenFrame", nil, { protected = true })
	local HookScript = f.HookScript
	f.HookScript = function(self, what, fn)
		if what == "OnMouseUp" then error("blocked") end
		return HookScript(self, what, fn)
	end
	w.env.UIPanelWindows = { BrokenFrame = {} }
	w:load("Modules.lua", "Mover.lua")
	w:fire("PLAYER_LOGIN")
	H.eq(#f.__h.hooks.OnMouseDown, 1, "OnMouseDown went in")
	w:fire("ADDON_LOADED")
	w.ns.UpdateModules()
	H.eq(#f.__h.hooks.OnMouseDown, 1, "a second Sweep does not hook it again")

	w:Run(f, "OnMouseDown", "LeftButton")
	H.eq(f.__h.moving, true, "it can start a drag")
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(f.__h.moving, false, "the fight's start ends the drag")
	H.eq(w.ns.mover.IsMoving(f), false, "and HUDini knows")
end)

H.test("a window closed in the middle of a drag ends the drag and goes home", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f = w.env.CharacterFrame
	f:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	w:Run(f, "OnMouseDown", "LeftButton")
	H.eq(f.__h.moving, true, "the drag starts")
	f.__h.shown = false
	w:Run(f, "OnHide")
	H.eq(f.__h.moving, false, "closed: the drag ends")
	H.eq(w.ns.mover.IsMoving(f), false, "and HUDini knows")
	H.eq(f.__h.movable, false, "movable as before")
	H.eq(f.__h.points[1][1], "CENTER", "back in its place")
end)

-- A window you never moved, closed in a fight, waits for the fight's end;
-- that end has nothing to undo, but must still drop the wait. A stale wait
-- would send the window home at a later fight's end, after you moved it.
H.test("a never-moved window closed in a fight leaves no wait behind", function()
	local w = MoverWorld(true)
	w:fire("PLAYER_LOGIN")
	local f = w.env.SpellBookFrame
	f:SetPoint("CENTER", w.env.UIParent, "CENTER", 0, 0)
	w.combat = true
	f.__h.shown = false
	w:Run(f, "OnHide")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.points[1][1], "CENTER", "nothing to undo")

	f.__h.shown = true
	w:Run(f, "OnMouseDown", "LeftButton")
	w:Run(f, "OnMouseUp", "LeftButton")
	f.__h.shown = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(f.__h.points[1][1], "CURSOR", "moved later: a fight's end does not move it")
end)

-- A throw before OnMouseDown goes in leaves no hook at all, so the window
-- must not be marked: the next Sweep tries it again.
H.test("a window whose hooks fail before any goes in is tried again", function()
	local w = H.world()
	w.env.HUDiniDB = { moveWindows = true }
	local f = w:Frame("ClampFrame", nil, { protected = true })
	local SetClampedToScreen, failed = f.SetClampedToScreen, false
	f.SetClampedToScreen = function(self, on)
		if not failed then failed = true; error("blocked") end
		return SetClampedToScreen(self, on)
	end
	w.env.UIPanelWindows = { ClampFrame = {} }
	w:load("Modules.lua", "Mover.lua")
	w:fire("PLAYER_LOGIN")
	H.eq(f.__h.hooks.OnMouseDown, nil, "the first try put no hook in")
	w:fire("ADDON_LOADED")
	H.eq(#f.__h.hooks.OnMouseDown, 1, "the next Sweep hooks it")
end)
