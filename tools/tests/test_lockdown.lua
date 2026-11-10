-- The harness's combat lockdown (TICK-0052): in a fight, a protected frame
-- that is shown, hidden, moved, dragged, scaled or reparented is a blocked action,
-- and a test that leaves one in the log fails. Then the whole addon through
-- a fight, with every part that hides Blizzard frames or owns secure ones on.

local function Protected(w, name)
	return w:Frame(name, nil, { protected = true })
end

H.test("a test that shows a protected frame in combat fails", function()
	local ok, err = H.run(function()
		local w = H.world()
		local f = Protected(w, "HUDiniLockTest")
		f:Hide()
		w.combat = true
		f:Show()
	end)
	H.eq(ok, false, "the test fails")
	H.ok(tostring(err):find("blocked in combat: HUDiniLockTest:Show()", 1, true), "and names the call: " .. tostring(err))
end)

H.test("each locked call on a protected frame in combat is blocked and does nothing", function()
	local w = H.world()
	local f = Protected(w, "HUDiniLockTest")
	local parent = w:Frame("HUDiniLockParent")
	f:Hide()
	w.combat = true
	f:Show()
	f:Hide()
	f:SetShown(true)
	f:ClearAllPoints()
	f:SetPoint("CENTER")
	f:SetAllPoints(parent)
	f:SetParent(parent)
	f:SetScale(2)
	f:SetSize(10, 10)
	f:SetWidth(10)
	f:SetHeight(10)
	f:SetFrameStrata("HIGH")
	f:SetFrameLevel(5)
	f:SetAttribute("unit", "target")
	f:EnableMouse(true)
	f:StartMoving()
	f:StopMovingOrSizing()
	H.eq(#w:takeBlocked(), 17, "17 calls blocked")
	H.eq(f:IsShown(), false, "still hidden")
	H.eq(f:GetParent(), nil, "not reparented")
	H.eq(f:GetScale(), 1, "not scaled")
	H.eq(f:GetWidth(), 0, "not sized")
	H.eq(f:GetFrameStrata(), "MEDIUM", "not layered")
	H.eq(f:GetAttribute("unit"), nil, "no attribute")
	H.eq(f:IsMouseEnabled(), false, "no mouse")
	H.eq(f.__h.moving, nil, "no drag")
	H.eq(#w.blocked, 0, "takeBlocked clears the log")
end)

H.test("a plain frame in combat, or a protected one out of it, is not blocked", function()
	local w = H.world()
	local plain, prot = w:Frame("HUDiniPlain"), Protected(w, "HUDiniProt")
	prot:Hide()
	prot:Show()
	H.eq(prot:IsShown(), true, "protected, out of combat: shown")
	w.combat = true
	plain:Hide()
	H.eq(plain:IsShown(), false, "plain, in combat: hidden")
	prot:IsShown()
	prot:GetPoint()
	H.eq(#w.blocked, 0, "reading a protected frame is fine")
end)

H.test("a frame from a Secure template is protected", function()
	local w = H.world()
	local b = w.env.CreateFrame("Button", "HUDiniSecureTest", nil, "SecureUnitButtonTemplate")
	local c = w.env.CreateFrame("Cooldown", nil, nil, "CooldownFrameTemplate")
	H.eq(b:IsProtected(), true, "secure template")
	H.eq(c:IsProtected(), false, "other template")
end)

H.test("a state or attribute driver registered in combat is blocked, on any frame", function()
	local w = H.world()
	local f = w:Frame("HUDiniDriven")
	w.combat = true
	w.env.RegisterAttributeDriver(f, "state-visibility", "hide")
	w.env.UnregisterAttributeDriver(f, "state-visibility")
	w.env.RegisterStateDriver(f, "visibility", "hide")
	local b = w:takeBlocked()
	H.eq(#b, 3, "three blocked")
	H.eq(b[1], "RegisterAttributeDriver(HUDiniDriven)")
	H.eq(f.__h.driver, nil, "no driver set")
	w.combat = false
	w.env.RegisterAttributeDriver(f, "state-visibility", "hide")
	H.eq(f.__h.driver, "hide", "out of combat: set")
end)

-- The whole addon, every Risk: high part on: Blizzard frames hidden, click
-- bars on secure buttons, the XP bar, the window mover with a protected
-- window. The HUD anchor gets a real corner, so the click buttons are placed
-- over their bars (the GetLeft and GetTop stubs give nil).
local function FightWorld()
	local w = H.world()
	-- The unit frames are protected buttons that take the mouse.
	w:Frame("PlayerFrame", nil, { protected = true, mouse = true })
	w:Frame("TargetFrame", nil, { protected = true, mouse = true })
	w:Frame("PlayerCastingBarFrame")
	w:Frame("MainStatusTrackingBarContainer")
	Protected(w, "SpellBookFrame")
	w:Frame("CharacterFrame")
	w.env.UIPanelWindows = { SpellBookFrame = {}, CharacterFrame = {} }
	w.env.HUDiniDB = {
		hideBlizzardPlayer = true, hideBlizzardTarget = true, hideBlizzardCastBar = true, hideBlizzardXP = true,
		clickBars = true, moveWindows = true, showXP = true, locked = true,
	}
	w:loadAddon()
	local hud = w.ns.HUDini
	hud.GetLeft = function() return 500 end
	hud.GetTop = function() return 400 end
	w:fire("UI_SCALE_CHANGED")
	w:runTimers()
	return w
end

H.test("a fight with every part on touches no protected frame, and what waited is done after", function()
	local w = FightWorld()
	local click = w.env.HUDiniClick_health
	H.ok(click:IsProtected(), "the click button is protected")
	H.eq(click:GetNumPoints(), 1, "the click button is over its bar")
	H.ok(click.__h.states.visibility ~= "hide", "and has its driver: " .. tostring(click.__h.states.visibility))
	H.eq(w.env.PlayerFrame.__h.alpha, 0, "the player frame is hidden by alpha")
	H.eq(w.env.PlayerFrame.__h.mouse, false, "and takes no click")
	local book = w.env.SpellBookFrame
	H.ok(book.__h.hooks.OnMouseDown, "the protected window has the mover's hooks")

	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	w:fire("UNIT_HEALTH", "player")
	w:fire("UNIT_HEALTH", "target")
	w:fire("ACTIONBAR_SLOT_CHANGED", 1)
	-- Drag, scale and close the protected window mid-fight.
	w:Run(book, "OnMouseDown", "LeftButton")
	w:Run(book, "OnMouseUp", "LeftButton")
	w.keys.ctrl = true
	w:Run(book, "OnMouseWheel", 1)
	w.keys.ctrl = false
	w:Run(book, "OnHide")
	-- Every setting that moves a Blizzard or secure frame, changed mid-fight.
	local db = w.env.HUDiniDB
	db.hideBlizzardPlayer, db.hideBlizzardTarget = false, false
	db.clickBars, db.moveWindows = false, false
	w.ns.HUDini:Apply()
	for _, cmd in ipairs({ "/hud unlock", "/hud lock", "/hud clicks", "/hud clicks",
			"/hud health", "/hud health", "/hud xp", "/hud xp" }) do
		w:slash(cmd)
	end
	-- The paths that skip Refresh: a level-up, a new UI scale.
	w:fire("PLAYER_LEVEL_UP", 2)
	w:fire("UI_SCALE_CHANGED")
	w:runTimers()
	w:runTickers()
	w:runTimers()
	H.eq(#w.blocked, 0, "nothing blocked in the fight: " .. tostring(w.blocked[1]))
	H.eq(w.env.PlayerFrame.__h.alpha, 1, "the player frame is back at once: alpha is not protected")
	H.eq(w.env.PlayerFrame.__h.mouse, false, "its mouse waits")
	H.ok(click.__h.states.visibility ~= "hide", "the click button waits")

	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	w:runTimers()
	H.eq(w.env.PlayerFrame.__h.mouse, true, "fight over: the player frame takes clicks again")
	H.eq(w.env.TargetFrame.__h.mouse, true, "and the target frame")
	H.eq(click.__h.states.visibility, "hide", "and the click button is off")
	H.eq(w.ns.HUDini.needBlizzFrames, false, "nothing waits")
end)
