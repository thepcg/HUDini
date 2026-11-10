--[[--------------------------------------------------------------------------
	HUDini - Test mode (/hud test)

	Shows each part of the HUD with sample values, so you can see and place
	it without a fight: the HUD itself, a sample target (health, power,
	name, level), your cast bar and the target cast bar, and one feed line
	of each kind (ns.FeedTest). The alerts join in through
	ns.ShowAlertSamples once Alerts.lua has it (TICK-0067).

	/hud test again ends it, and so does the start of a fight
	(PLAYER_REGEN_DISABLED). It cannot start in a fight.

	Sample values only: test mode reads no unit, aura or cast value, so it
	reads no secret one. It touches no secure frame.

	The bars fill themselves from the game on every update, and with no
	target they hide. So test mode post-hooks the three public updates in
	Bars.lua (hooksecurefunc on ns, no line of Bars.lua changed): after the
	real update has run, the sample goes back on. The hooks go in the first
	time test mode starts, and do nothing while it is off. A real target
	wins: with one, its own bars show, not the sample. A real cast wins the
	same way: a cast bar that ns.UpdateCastBars showed is left alone. A cast
	that starts between two of its runs (Bars.lua handles the cast events
	itself) can sit under the sample until the next run, a poll beat.

	Ending it clears what the samples wrote, then runs the real updates,
	which put every part back the way the game says it is.

	HUDini setup's step 1 (TICK-0115) shows the sample target alone, with
	the same hooks, through ns.SampleTargetOnly: no cast bar, feed line or
	alert sample, and no "test mode" line in chat. Setup ends it on every
	way out of the step, and before a fight starts.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local Text = ns.Text

ns.testing = false

local targetOnly = false -- setup's step 1: the sample target alone

-- The sample. Fill is a fraction of the bar.
local SAMPLE = {
	name     = Text("test.sampleName"),
	level    = "10",
	info     = Text("test.sampleInfo"),
	health   = 0.65,
	power    = 0.4,
	cast     = Text("test.sampleCast"),
	castFill = 0.6,
	ownFill  = 0.3,
}
local HOSTILE = { 0.85, 0.2, 0.2 }
local MANA    = { 0.0, 0.55, 1.0 }

-- Plain numbers only, so a plain SetValue is safe.
local function SampleFill(bar, fraction)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(fraction)
end

-- A sample colour, and a cleared cache: the next real fill sets its own
-- colour again (Bars.lua sets the colour only when shownColor changes).
local function SampleColor(bar, color)
	bar:SetStatusBarColor(unpack(color))
	bar.shownColor = nil
end

--------------------------------------------------------------------------------
-- Putting the sample on
--------------------------------------------------------------------------------

local function SampleTarget(db)
	local bar = ns.GetBar("targethealth")
	if not db.showTargetHealth then return end

	SampleFill(bar, SAMPLE.health)
	SampleColor(bar, HOSTILE)
	bar.name:SetText(SAMPLE.name)
	bar.level:SetText(SAMPLE.level)
	bar.info:SetText(SAMPLE.info)
	bar:Show()

	-- The target's power has its own bar under its health (TICK-0126).
	local power = ns.GetBar("targetpower")
	if db.showTargetPower then
		SampleFill(power, SAMPLE.power)
		SampleColor(power, MANA)
		power:Show()
	else
		power:Hide()
	end
end

-- The target's cast name sits on the target's power bar, as on a real cast.
local function CastName(set)
	if set.key ~= "targetcast" then return nil end
	return ns.GetBar("targetpower").castName
end

-- A hidden cast bar gets the sample, and so does one that shows the
-- sample already. One that shows without it holds a real cast: that stays.
local function SampleCast(set, fraction)
	if set.holder:IsShown() and not set.sample then return end
	SampleFill(set.base, fraction)
	if set.hot then
		SampleFill(set.hot, fraction)
		-- Yellow, as for a cast you can interrupt (Bars.lua RefreshCast).
		set.hot:SetAlpha(1)
		set.base:SetAlpha(0)
	end
	local name = CastName(set)
	if name then
		name:SetText(SAMPLE.cast)
		name:Show()
	end
	set.sample = true
	set.holder:Show()
end

-- Runs after each real update while test mode, or the sample target
-- alone, is on.
local function Reapply()
	if not (ns.testing or targetOnly) then return end
	local db = HUDiniDB
	if not db then return end
	local full = ns.testing

	if full and db.showPlayerCast and db.showPower then
		SampleCast(ns.casts.playercast, SAMPLE.ownFill)
	end

	if UnitExists("target") then return end
	SampleTarget(db)
	if full and db.showTargetCast then
		SampleCast(ns.casts.targetcast, SAMPLE.castFill)
	end
end

-- ns.UpdateCastBars decides every cast bar from the game: it hides one with
-- no cast, so a cast bar it left showing holds a real cast.
local function AfterCastBars()
	for _, set in pairs(ns.casts) do
		if set.holder:IsShown() then set.sample = nil end
	end
	Reapply()
end

local hooked = false

local function Hook()
	if hooked then return end
	hooked = true
	hooksecurefunc(ns, "UpdateBarVisibility", Reapply)
	hooksecurefunc(ns, "UpdateBars", Reapply)
	hooksecurefunc(ns, "UpdateCastBars", AfterCastBars)
end

--------------------------------------------------------------------------------
-- Taking it off
--------------------------------------------------------------------------------

-- Clear what the samples wrote. The real updates in Stop then set every
-- part from the game.
local function Clear()
	local bar = ns.GetBar("targethealth")
	if not UnitExists("target") then
		bar.name:SetText("")
		bar.level:SetText("")
		bar.info:SetText("")
	end
	bar.shownColor = nil
	ns.GetBar("targetpower").shownColor = nil

	for _, set in pairs(ns.casts) do
		if set.sample then
			set.sample = nil
			local name = CastName(set)
			if name then
				name:SetText("")
				name:Hide()
			end
			-- The real update shows it again if a real cast is on.
			set.holder:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function Alerts(on)
	if ns.ShowAlertSamples then ns.ShowAlertSamples(on) end
end

local function Start()
	if ns.InCombat() then
		ns.Say(Text("test.inCombat"))
		return
	end
	ns.testing = true
	Hook()
	-- No event while off: the fight's start is only watched while it is on.
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	ns.HUDini:UpdateVisibility()
	ns.RefreshBars()
	Alerts(true)
	if ns.FeedTest then ns.FeedTest() end
	ns.Say(Text("test.on"))
end

local function Stop(why)
	ns.testing = false
	events:UnregisterEvent("PLAYER_REGEN_DISABLED")
	Clear()
	Alerts(false)
	ns.HUDini:UpdateVisibility()
	ns.RefreshBars()
	-- RefreshBars fills the target power only with a target; with none,
	-- this hides it.
	ns.UpdateTargetPower()
	ns.Say(why)
end

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" and ns.testing then
		Stop(Text("test.offFight"))
	end
end)

-- HUDini setup's step 1 (TICK-0115): the sample target alone, on or off.
-- Out of a fight only, like test mode. Off leaves a running test mode's
-- sample as it is.
function ns.SampleTargetOnly(on)
	on = on and not ns.InCombat() and true or false
	if on == targetOnly then return end
	targetOnly = on
	if on then
		Hook()
		ns.RefreshBars()
	elseif not ns.testing then
		Clear()
		ns.RefreshBars()
		ns.UpdateTargetPower()
	end
end

-- /hud test
function ns.TestMode()
	if ns.testing then
		Stop(Text("test.off"))
	else
		Start()
	end
end
