-- TestMode.lua (TICK-0021): /hud test shows every part with sample values;
-- /hud test again or the fight's start ends it, and puts every part back.

-- ns.FeedTest is the feed's own sample (FeedWatch.lua). The harness has no
-- item API for it, so a world counts the calls instead.
local function Logged()
	local w = H.world()
	w:loadAddon()
	w.printed = {}
	w.feedTests = 0
	w.ns.FeedTest = function() w.feedTests = w.feedTests + 1 end
	return w
end

-- What test mode may change, as plain values.
local function State(w)
	local ns = w.ns
	local bar, power = ns.GetBar("targethealth"), ns.GetBar("targetpower")
	local tc, pc = ns.casts.targetcast, ns.casts.playercast
	local show, why = ns.HUDini:ShouldShow()
	return {
		testing    = ns.testing,
		show       = show,
		why        = why,
		body       = w.env.HUDiniBody:IsShown(),
		target     = bar:IsShown(),
		name       = bar.name:GetText() or "",
		level      = bar.level:GetText() or "",
		info       = bar.info:GetText() or "",
		power      = power:IsShown(),
		targetCast = tc.holder:IsShown(),
		castText   = power.castName:GetText() or "",
		ownCast    = pc.holder:IsShown(),
		samples    = (tc.sample or pc.sample) and true or false,
	}
end

-- Secure hooks test mode put on the addon's namespace.
local function NsHooks(w)
	local n = 0
	for _, h in ipairs(w.secureHooks) do
		if h.tbl == w.ns then n = n + 1 end
	end
	return n
end

H.test("off at login: no hook on the namespace, nothing shown", function()
	local w = Logged()
	H.eq(w.ns.testing, false, "testing")
	H.eq(NsHooks(w), 0, "namespace hooks")
	local s = State(w)
	H.eq(s.target, false, "sample target")
	H.eq(s.targetCast, false, "target cast")
end)

H.test("/hud test shows the HUD, a sample target and both cast bars", function()
	local w = Logged()
	w:slash("/hud test")
	local s = State(w)
	H.eq(s.testing, true, "testing")
	H.eq(s.show, true, "ShouldShow")
	H.eq(s.why, "HUD visible: test mode.", "/hud why reason")
	H.eq(s.body, true, "HUD body")
	H.eq(s.target, true, "target bar")
	H.eq(s.name, "Sample target", "target name")
	H.eq(s.level, "10", "target level")
	H.eq(s.power, true, "target power")
	H.eq(s.targetCast, true, "target cast bar")
	H.eq(s.castText, "Sample cast", "target cast text")
	H.eq(s.ownCast, true, "your cast bar")
	H.eq(w.feedTests, 1, "feed lines asked for")
	H.eq(NsHooks(w), 3, "namespace hooks")
	H.ok(H.printed(w, w.ns.TEXT[0]["test.on"]), "on line")
end)

H.test("a bar the player turned off stays off in test mode", function()
	local w = Logged()
	local db = w.env.HUDiniDB
	db.showTargetHealth, db.showPlayerCast, db.showTargetCast = false, false, false
	w:slash("/hud test")
	w:runTickers()
	w.ns.RefreshBars()
	local s = State(w)
	H.eq(s.body, true, "HUD body")
	H.eq(s.target, false, "target bar")
	H.eq(s.name, "", "target name")
	H.eq(s.ownCast, false, "your cast bar")
	H.eq(s.targetCast, false, "target cast bar")
end)

H.test("the sample stays through the poll and the real updates", function()
	local w = Logged()
	w:slash("/hud test")
	for _ = 1, 3 do w:runTickers() end
	w.ns.HUDini:UpdateVisibility()
	w.ns.RefreshBars()
	w:fire("PLAYER_TARGET_CHANGED")
	local s = State(w)
	H.eq(s.body, true, "HUD body")
	H.eq(s.target, true, "target bar")
	H.eq(s.name, "Sample target", "target name")
	H.eq(s.targetCast, true, "target cast bar")
	H.eq(s.ownCast, true, "your cast bar")
end)

H.test("/hud test again puts every part back", function()
	local w = Logged()
	local before = State(w)
	w:slash("/hud test")
	w:runTickers()
	w:slash("/hud test")
	H.eq(H.diff(State(w), before), nil, "state after test mode")
	H.ok(H.printed(w, "Preview off."), "off line")

	-- The hooks stay, as hooks cannot come out, and do nothing now.
	w:runTickers()
	w.ns.RefreshBars()
	H.eq(H.diff(State(w), before), nil, "state after more updates")
end)

H.test("the fight's start ends it and puts every part back", function()
	local w = Logged()
	local before = State(w)
	w:slash("/hud test")
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	H.eq(w.ns.testing, false, "testing")
	H.ok(H.printed(w, "Preview ended: combat began."), "fight line")
	local s = State(w)
	H.eq(s.target, false, "target bar")
	H.eq(s.targetCast, false, "target cast")
	H.eq(s.ownCast, false, "your cast bar")
	H.eq(s.name, before.name, "target name")
	H.eq(s.samples, false, "sample flags")
end)

H.test("it cannot start in a fight", function()
	local w = Logged()
	w.combat = true
	w:slash("/hud test")
	H.eq(w.ns.testing, false, "testing")
	H.eq(NsHooks(w), 0, "namespace hooks")
	H.ok(H.printed(w, w.ns.TEXT[0]["test.inCombat"]), "fight line")
end)

H.test("a real target wins over the sample, and the sample comes back after it", function()
	local w = Logged()
	w.env.UnitName = function(unit)
		if unit == "player" then return "Tester" end
		if unit == "target" and w.hasTarget then return "Real Wolf" end
		return nil
	end
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	w:slash("/hud test")
	w:runTickers()
	local s = State(w)
	H.eq(s.target, true, "target bar")
	H.eq(s.name, "Real Wolf", "target name")
	H.eq(s.targetCast, false, "target cast: the wolf casts nothing")
	H.eq(w.ns.casts.targetcast.sample, nil, "target cast sample")

	w.hasTarget = false
	w:fire("PLAYER_TARGET_CHANGED")
	w:runTickers()
	s = State(w)
	H.eq(s.name, "Sample target", "sample after the target is gone")
	H.eq(s.targetCast, true, "sample target cast")

	-- Ending it with a real target leaves that target's text alone.
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	w:slash("/hud test")
	H.eq(State(w).name, "Real Wolf", "target name after test mode")
end)

H.test("a real cast of yours wins over the sample", function()
	local w = Logged()
	local casting = true
	w.env.UnitCastingDuration = function(unit)
		if unit == "player" and casting then return {} end
		return nil
	end
	w.env.UnitCastingInfo = function(unit)
		if unit == "player" and casting then return "Fireball" end
		return nil
	end
	-- The fake StatusBar has no timer: give the player's bar one that
	-- takes a duration and refuses nil, as the game does.
	local base = w.ns.casts.playercast.base
	base.SetTimerDuration = function(_, d) assert(d ~= nil) end
	w.ns.UpdateCastBars()   -- the cast is on before test mode starts

	w:slash("/hud test")
	w:runTickers()
	local pc = w.ns.casts.playercast
	H.eq(pc.holder:IsShown(), true, "your cast bar")
	H.eq(pc.sample, nil, "sample on your cast bar")
	H.ok(pc.base:GetValue() ~= 0.3, "sample value on your cast bar")

	-- The cast ends: the sample takes the bar at the next update.
	casting = false
	w:runTickers()
	H.eq(pc.holder:IsShown(), true, "your cast bar")
	H.eq(pc.sample, true, "sample on your cast bar")
	H.eq(pc.base:GetValue(), 0.3, "sample value")

	-- A new cast while the sample is up: the next cast-bar update gives the
	-- bar back to it.
	casting = true
	w:runTickers()
	H.eq(pc.holder:IsShown(), true, "your cast bar")
	H.eq(pc.sample, nil, "sample on your cast bar, new cast")
end)

H.test("while on, with no target, nothing asks the game about the target", function()
	-- The sample is all plain values. Ending it runs the real updates,
	-- which ask as they always do, so the count stops before that.
	local w = Logged()
	local asked = 0
	for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax",
			"UnitName", "UnitLevel", "UnitCastingInfo", "UnitChannelInfo" }) do
		local real = w.env[name]
		w.env[name] = function(unit, ...)
			if unit == "target" then asked = asked + 1 end
			return real(unit, ...)
		end
	end
	w:slash("/hud test")
	w:runTickers()
	w.ns.RefreshBars()
	H.eq(asked, 0, "target values asked for")
end)
