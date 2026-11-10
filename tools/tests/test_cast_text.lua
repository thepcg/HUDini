-- The words on your cast bar (TICK-0122): the spell name, the time left,
-- and Failed or Interrupted when a cast does not finish. The game's
-- duration object gives the time left (GetRemainingDuration) and drives
-- the fill (SetTimerDuration). In a fight the name, the time left and the
-- cast ID can be secret. A secret one here is a tripwire: a table whose
-- every Lua operation (sum, compare, join, index, length, call) records a
-- violation and throws. A tripwire cannot see a truth test or an == with
-- a value of another type, so the tests also check that each secret
-- reaches the game call as the very same table. What the words look like
-- needs the game.

-- A logged-in world. w.cast and w.channel: the cast the game has now
-- (nil: none), each { name, id, left, ni }. w.notSecret: what
-- C_Secrets.ShouldUnitSpellCastingBeSecret answers the player (false:
-- not secret); w.noAsk: the client has no such question.
local function World(o)
	o = o or {}
	local w = H.world()
	local env = w.env
	w.violations = {}
	w.secret = {}
	w.timerCalls = {}
	w.secretCasting = false
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.FAILED = "Failed (game)"
	-- Your power number, so a test can see the cast hide it and give it back.
	env.CurveConstants = { ScaleTo100 = {} }
	env.UnitHealthPercent = function() return 50 end
	env.UnitPowerPercent = function() return 99.7 end
	env.AbbreviateNumbers = function(v) return tostring(v) end
	env.INTERRUPTED = "Interrupted (game)"

	local trip = { __tostring = function() return "<secret>" end }
	for _, mm in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm",
			"__lt", "__le", "__eq", "__concat", "__len", "__call", "__index", "__newindex" }) do
		trip[mm] = function()
			table.insert(w.violations, mm)
			error("Lua touched a secret value: " .. mm, 2)
		end
	end
	function w.Secret()
		local t = setmetatable({}, trip)
		w.secret[t] = true
		return t
	end

	-- One duration object per cast, so a test can see the same one reach
	-- the bar's timer.
	local function Duration(c)
		c.duration = c.duration or { GetRemainingDuration = function() return c.left end }
		return c.duration
	end
	env.UnitCastingDuration = function(unit)
		if unit == "player" and w.cast then return Duration(w.cast) end
		if unit == "target" and w.targetCast then return Duration(w.targetCast) end
	end
	env.UnitChannelDuration = function(unit)
		if unit == "player" and w.channel then return Duration(w.channel) end
	end
	env.UnitCastingInfo = function(unit)
		local c = (unit == "player" and w.cast) or (unit == "target" and w.targetCast)
		if c then return c.name, c.name, 136116, 0, 0, false, c.id, c.ni, 133 end
	end
	env.UnitChannelInfo = function(unit)
		local c = unit == "player" and w.channel
		if c then return c.name, c.name, 136116, 0, 0, false, c.ni, 5143 end
	end
	if not o.noAsk then
		env.C_Secrets = {
			ShouldUnitSpellCastingBeSecret = function(unit)
				if w.askThrows then error("no answer here") end
				return w.secretCasting
			end,
		}
	end
	if o.before then o.before(w) end
	local ns = w:loadAddon()

	-- The fake StatusBar has no timer: these record what the bar is
	-- given, and refuse nil, as the game does.
	local set = ns.casts.playercast
	for _, bar in ipairs({ set.base, ns.casts.targetcast.base, ns.casts.targetcast.hot }) do
		bar.SetTimerDuration = function(self, d, interp, dir)
			assert(d ~= nil)
			table.insert(w.timerCalls, { bar = self, d = d, dir = dir })
		end
	end
	set.base.SetStatusBarColor = function(self, r, g, b) self.__h.color = { r, g, b } end

	-- The time left goes through SetFormattedText: keep what it was given.
	local p = ns.GetBar("power")
	p.castTime.SetFormattedText = function(self, f, v)
		self.__h.format, self.__h.arg = f, v
		self.__h.text = f:format(v)
	end
	return w, ns, set, p
end

-- The same all the way down (H.eq compares tables by identity).
local function Same(got, want, msg)
	local d = H.diff(got, want)
	H.ok(d == nil, (msg or "") .. ": " .. tostring(d))
end

local function NoViolation(w, msg)
	H.eq(#w.violations, 0, (msg or "") .. ": Lua touched a secret (" .. table.concat(w.violations, ", ") .. ")")
end

local function Tick(set) set.holder.__h.world:Run(set.holder, "OnUpdate", 0.016) end

-- Start a cast of yours: the game has it, then says so.
local function Cast(w, name, id, left)
	w.cast = { name = name or "Fireball", id = id or "Cast-1", left = left or 2.43 }
	w:fire("UNIT_SPELLCAST_START", "player", w.cast.id, 133)
	return w.cast
end

local function Words(p)
	return p.castName:IsShown(), p.castTime:IsShown(), p.castWord:IsShown()
end

--------------------------------------------------------------------------------
-- Place
--------------------------------------------------------------------------------

H.test("the words sit on the power bar's text layer, above the see-through cast bar", function()
	local w, ns, set, p = World()
	H.eq(p.castName:GetParent(), p.textLayer, "the name's layer")
	H.eq(p.castTime:GetParent(), p.textLayer, "the timer's layer")
	H.eq(p.castWord:GetParent(), p.textLayer, "the word's layer")
	H.ok(p.textLayer:GetFrameLevel() > set.holder:GetFrameLevel(), "the layer is above the cast bar")
	H.ok(p.textLayer:GetFrameLevel() > set.base:GetFrameLevel(), "and above its fill")
	-- In the game the fill is one level above its holder.
	H.ok(p.textLayer:GetFrameLevel() > set.holder:GetFrameLevel() + 1, "above the fill's level in the game")
	-- Each point, one value at a time: a frame is compared by identity.
	local function At(fs, i, want, msg)
		local got = { fs:GetPoint(i) }
		for k = 1, #want do H.eq(got[k], want[k], msg .. " " .. k) end
	end
	At(p.castName, 1, { "LEFT", p, "LEFT", 6, 0 }, "the name starts at the left")
	At(p.castName, 2, { "RIGHT", p.castTime, "LEFT", -5, 0 }, "the name stops 5 px left of the timer")
	At(p.castTime, 1, { "RIGHT", p, "RIGHT", -6, 0 }, "the timer at the right")
	At(p.castWord, 1, { "CENTER", p, "CENTER", 0, 0 }, "the word at the middle")
	H.eq(p.castName:GetNumPoints(), 2, "the name has two points")
	Same({ Words(p) }, { false, false, false }, "no cast: no words")
end)

--------------------------------------------------------------------------------
-- A cast and a channel
--------------------------------------------------------------------------------

H.test("a cast shows its name and the time left, and both go when it ends", function()
	local w, ns, set, p = World()
	local c = Cast(w)
	H.eq(set.holder:IsShown(), true, "the cast bar shows")
	Same({ Words(p) }, { true, true, false }, "the name and the timer")
	H.eq(p.castName:GetText(), "Fireball", "the name")
	H.eq(p.castTime:GetText(), "2.4", "one decimal under 10 s")
	c.left = 12.7
	Tick(set)
	H.eq(p.castTime:GetText(), "12", "whole seconds from 10 s up")
	c.left = 9.97
	Tick(set)
	H.eq(p.castTime:GetText(), "10", "never 10.0, and never 9 before 9.9")
	c.left = 0.04
	Tick(set)
	H.eq(p.castTime:GetText(), "0.0", "the last moment")
	w.cast = nil
	w:fire("UNIT_SPELLCAST_STOP", "player", c.id, 133)
	H.eq(set.holder:IsShown(), false, "the bar goes")
	Same({ Words(p) }, { false, false, false }, "the words go")
	H.eq(set.duration, nil, "no time left kept")
	H.eq(p.numbers:GetText(), "99%", "the power number is back")
end)

H.test("the timer counts down from the game's own duration object", function()
	local w, ns, set, p = World()
	local c = Cast(w)
	local last = w.timerCalls[#w.timerCalls]
	H.ok(last and rawequal(last.d, c.duration), "the fill takes the game's duration")
	H.ok(rawequal(set.duration, c.duration), "the timer reads the same one")
	c.left = 1.05
	Tick(set)
	H.eq(p.castTime:GetText(), "1.1", "each frame asks it again")
end)

H.test("a channel shows its name and counts down too", function()
	local w, ns, set, p = World()
	w.channel = { name = "Arcane Missiles", left = 3.21 }
	w:fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 5143)
	Same({ Words(p) }, { true, true, false }, "the name and the timer")
	H.eq(p.castName:GetText(), "Arcane Missiles", "the name")
	H.eq(p.castTime:GetText(), "3.2", "the time left")
	H.ok(rawequal(set.duration, w.channel.duration), "the channel's duration")
	w.channel = nil
	w:fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 5143)
	H.eq(set.holder:IsShown(), false, "the bar goes")
end)

H.test("a cast in a fight shows its words too", function()
	local w, ns, set, p = World()
	w.combat = true
	w:fire("PLAYER_REGEN_DISABLED")
	Cast(w)
	Same({ Words(p) }, { true, true, false }, "the name and the timer")
	H.eq(#w:takeBlocked(), 0, "nothing blocked")
end)

--------------------------------------------------------------------------------
-- Secret values
--------------------------------------------------------------------------------

H.test("a secret name goes to the game as it is", function()
	local w, ns, set, p = World()
	local name = w.Secret()
	local seen
	p.castName.SetText = function(self, v) seen = v; self.__h.text = v end
	Cast(w, name)
	Tick(set)
	H.ok(rawequal(seen, name), "SetText got the secret name itself")
	NoViolation(w, "secret name")
end)

H.test("a secret time left is formatted by the game, never compared", function()
	local w, ns, set, p = World()
	w.secretCasting = true
	local left = w.Secret()
	Cast(w, "Fireball", "Cast-1", left)
	Tick(set)
	H.ok(rawequal(p.castTime.__h.arg, left), "SetFormattedText got the secret itself")
	H.eq(p.castTime.__h.format, "%.1f", "one decimal")
	NoViolation(w, "secret time left")
end)

H.test("the game says the cast is secret: one decimal even for a plain number", function()
	local w, ns, set, p = World()
	w.secretCasting = true
	Cast(w, "Fireball", "Cast-1", 12.7)
	H.eq(p.castTime:GetText(), "12.7", "no compare: one decimal")
end)

H.test("no answer from the game counts as secret", function()
	local w, ns, set, p = World()
	w.askThrows = true
	Cast(w, "Fireball", "Cast-1", 12.7)
	H.eq(p.castTime:GetText(), "12.7", "an error: one decimal")
	w.askThrows = false
	w.secretCasting = w.Secret()
	Cast(w, "Fireball", "Cast-2", 12.7)
	H.eq(p.castTime:GetText(), "12.7", "a secret answer: one decimal")
	NoViolation(w, "secret answer")
end)

H.test("a client with no such question leaves it to the number", function()
	local w, ns, set, p = World({ noAsk = true })
	local c = Cast(w, "Fireball", "Cast-1", 12.7)
	H.eq(p.castTime:GetText(), "12", "plain: whole seconds")
	c.left = w.Secret()
	Tick(set)
	H.ok(rawequal(p.castTime.__h.arg, c.left), "secret: to the game as it is")
	NoViolation(w, "no question")
end)

H.test("a duration object that throws leaves the timer empty", function()
	local w, ns, set, p = World()
	local c = Cast(w)
	c.duration.GetRemainingDuration = function() error("gone") end
	Tick(set)
	H.eq(p.castTime:GetText(), "", "no time left")
end)

--------------------------------------------------------------------------------
-- Failed and Interrupted
--------------------------------------------------------------------------------

H.test("Interrupted: red, full, the word alone; it holds 1 s, fades 0.5 s, then goes", function()
	local w, ns, set, p = World()
	local alpha = set.holder:GetAlpha()
	local c = Cast(w)
	w.cast = nil
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", c.id, 133)
	w:fire("UNIT_SPELLCAST_STOP", "player", c.id, 133)
	H.eq(set.holder:IsShown(), true, "the bar stays after the stop")
	Same({ Words(p) }, { false, false, true }, "the word alone, no timer")
	H.eq(p.castWord:GetText(), "Interrupted (game)", "the game's word")
	Same(set.base.__h.color, { 1, 0, 0 }, "red")
	H.eq(set.base.stateShown, true, "a texture swap keeps the red")
	Same(set.base.shownColor, { 1, 0, 0 }, "the red to keep")
	Same({ set.base:GetValue(), select(2, set.base:GetMinMaxValues()) }, { 1, 1 }, "full")
	H.eq(p.numbers:GetText(), "", "no power number under the word")

	w.time = w.time + 0.9
	Tick(set)
	H.eq(set.holder:GetAlpha(), alpha, "held at full")
	H.eq(p.castWord:GetAlpha(), 1, "the word held")
	w.time = w.time + 0.35 -- 1.25 s
	Tick(set)
	H.ok(math.abs(set.holder:GetAlpha() - alpha / 2) < 1e-9, "half faded")
	H.ok(math.abs(p.castWord:GetAlpha() - 0.5) < 1e-9, "the word half faded")
	w.time = w.time + 0.25 -- 1.5 s
	Tick(set)
	H.eq(set.holder:IsShown(), false, "gone")
	Same({ Words(p) }, { false, false, false }, "no words")
	H.eq(set.holder:GetAlpha(), alpha, "its see-through back")
	H.eq(p.castWord:GetAlpha(), 1, "the word at full for next time")
	Same(set.base.__h.color, ns.BarColor("playercast"), "its colour back")
	H.eq(set.base.stateShown, nil, "a texture swap keeps its colour again")
	H.eq(p.numbers:GetText(), "99%", "the power number is back")
end)

H.test("Failed shows the game's word, or HUDini's when the client has none", function()
	local w, ns, set, p = World()
	local c = Cast(w)
	w.cast = nil
	w:fire("UNIT_SPELLCAST_FAILED", "player", c.id, 133)
	H.eq(p.castWord:GetText(), "Failed (game)", "the game's word")
	Same({ Words(p) }, { false, false, true }, "the word alone")

	w.env.FAILED, w.env.INTERRUPTED = nil, nil
	c = Cast(w, "Frostbolt", "Cast-2")
	w.cast = nil
	w:fire("UNIT_SPELLCAST_FAILED", "player", c.id, 116)
	H.eq(p.castWord:GetText(), ns.Text("bars.cast.failed"), "HUDini's Failed")
	H.eq(ns.Text("bars.cast.failed"), "Failed", "the level 0 text")
	c = Cast(w, "Frostbolt", "Cast-3")
	w.cast = nil
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", c.id, 116)
	H.eq(p.castWord:GetText(), "Interrupted", "HUDini's Interrupted")
end)

H.test("a new cast ends Failed or Interrupted at once", function()
	local w, ns, set, p = World()
	local alpha = set.holder:GetAlpha()
	local c = Cast(w)
	w.cast = nil
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", c.id, 133)
	w.time = w.time + 1.2
	Tick(set)
	Cast(w, "Frostbolt", "Cast-2", 1.5)
	Same({ Words(p) }, { true, true, false }, "the new cast's words")
	H.eq(p.castName:GetText(), "Frostbolt", "its name")
	H.eq(set.flash, nil, "the flash is over")
	H.eq(set.holder:GetAlpha(), alpha, "its see-through back")
	Same(set.base.__h.color, ns.BarColor("playercast"), "its colour back")
	w.time = w.time + 1
	Tick(set)
	H.eq(set.holder:IsShown(), true, "the old fade does not hide the new cast")
end)

H.test("a spell that fails while another casts does not stop the bar", function()
	local w, ns, set, p = World()
	Cast(w)
	w:fire("UNIT_SPELLCAST_FAILED", "player", "Cast-9", 116)
	Same({ Words(p) }, { true, true, false }, "the cast's words stay")
	H.eq(set.flash, nil, "no flash")
	Same(set.base.__h.color, nil, "no red")
end)

H.test("a failed spell with no cast on the bar shows nothing", function()
	local w, ns, set, p = World()
	w:fire("UNIT_SPELLCAST_FAILED", "player", "Cast-9", 116)
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-9", 116)
	H.eq(set.holder:IsShown(), false, "no bar")
	Same({ Words(p) }, { false, false, false }, "no words")
end)

H.test("a channel: Failed does nothing, Interrupted shows", function()
	local w, ns, set, p = World()
	w.channel = { name = "Arcane Missiles", left = 3 }
	w:fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 5143)
	w:fire("UNIT_SPELLCAST_FAILED", "player", "Cast-9", 116)
	Same({ Words(p) }, { true, true, false }, "a failed try does not stop the channel")
	w.channel = nil
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", nil, 5143)
	w:fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 5143)
	Same({ Words(p) }, { false, false, true }, "Interrupted")
	H.eq(p.castWord:GetText(), "Interrupted (game)", "the word")
end)

H.test("secret cast IDs are never compared: the game's cast decides", function()
	local w, ns, set, p = World()
	local id = w.Secret()
	Cast(w, "Fireball", id)
	-- Another spell fails while this one still casts: no flash.
	w:fire("UNIT_SPELLCAST_FAILED", "player", w.Secret(), 116)
	H.eq(set.flash, nil, "still casting: no flash")
	-- The cast is gone when Interrupted comes: that is the bar's cast.
	w.cast = nil
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", w.Secret(), 133)
	Same({ Words(p) }, { false, false, true }, "Interrupted")
	NoViolation(w, "secret cast IDs")
end)

H.test("the stop first ends the cast: a word after it shows nothing, as on the game's bar", function()
	local w, ns, set, p = World()
	local c = Cast(w)
	w.cast = nil
	w:fire("UNIT_SPELLCAST_STOP", "player", c.id, 133)
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", c.id, 133)
	H.eq(set.holder:IsShown(), false, "no bar")
	H.eq(set.flash, nil, "no flash")
	Same({ Words(p) }, { false, false, false }, "no words")
	c = Cast(w, "Frostbolt", "Cast-2")
	w.cast = nil
	w:fire("UNIT_SPELLCAST_STOP", "player", c.id, 116)
	w:fire("UNIT_SPELLCAST_FAILED", "player", c.id, 116)
	H.eq(set.flash, nil, "Failed after the stop: no flash")
end)

H.test("a channel cut short: the stop's interruptedBy shows Interrupted", function()
	local w, ns, set, p = World()
	w.channel = { name = "Arcane Missiles", left = 3 }
	w:fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 5143)
	w.channel = nil
	w:fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 5143, "Creature-0-1")
	Same({ Words(p) }, { false, false, true }, "Interrupted")
	H.eq(p.castWord:GetText(), "Interrupted (game)", "the word")
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", nil, 5143)
	H.eq(set.flash ~= nil, true, "a second word changes nothing")

	-- A secret interruptedBy counts as set, never compared.
	w.time = w.time + 2
	Tick(set)
	w.channel = { name = "Arcane Missiles", left = 3 }
	w:fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 5143)
	w.channel = nil
	w:fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 5143, w.Secret())
	Same({ Words(p) }, { false, false, true }, "a secret one: Interrupted")
	NoViolation(w, "secret interruptedBy")

	-- A channel that ends by itself: no word.
	w.time = w.time + 2
	Tick(set)
	w.channel = { name = "Arcane Missiles", left = 3 }
	w:fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 5143)
	w.channel = nil
	w:fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 5143, nil)
	H.eq(set.holder:IsShown(), false, "a full channel: the bar goes")
	H.eq(set.flash, nil, "no flash")
end)

H.test("an old channel's cut-short stop does not cover a new cast", function()
	local w, ns, set, p = World()
	w.channel = { name = "Arcane Missiles", left = 3 }
	w:fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 5143)
	w.channel = nil
	-- The new cast starts before the old channel's stop comes.
	Cast(w, "Fireball", "Cast-2")
	w:fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 5143, "Creature-0-1")
	H.eq(set.flash, nil, "no flash")
	Same({ Words(p) }, { true, true, false }, "the new cast's words")
	H.eq(p.castName:GetText(), "Fireball", "its name")
end)

H.test("a channel's cut-short stop on a hidden cast bar shows nothing", function()
	local w, ns, set, p = World()
	w.channel = { name = "Arcane Missiles", left = 3 }
	w:fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 5143)
	-- TestMode.lua hides a sample's holder itself, cast or not.
	set.holder:Hide()
	w.channel = nil
	w:fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 5143, "Creature-0-1")
	H.eq(set.flash, nil, "no flash")
	H.eq(set.holder:IsShown(), false, "still hidden")
end)

H.test("a cast bar hidden by test mode's end gets no flash", function()
	local w, ns, set, p = World()
	local c = Cast(w)
	-- TestMode.lua hides a sample's holder itself, cast or not.
	set.holder:Hide()
	w.cast = nil
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", c.id, 133)
	H.eq(set.flash, nil, "no flash")
	H.eq(set.holder:IsShown(), false, "still hidden")
end)

H.test("your cast bar off ends the flash and its words", function()
	local w, ns, set, p = World()
	local c = Cast(w)
	w.cast = nil
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "player", c.id, 133)
	w.env.HUDiniDB.showPlayerCast = false
	ns.UpdateCastBars()
	H.eq(set.holder:IsShown(), false, "the bar goes")
	Same({ Words(p) }, { false, false, false }, "the words go")
	H.eq(set.flash, nil, "the flash is over")
	Same(set.base.__h.color, ns.BarColor("playercast"), "its colour back")
end)

--------------------------------------------------------------------------------
-- The target's cast (TICK-0126): its words on the target's power bar
--------------------------------------------------------------------------------

-- A target in a world, and the target's power bar with its time left
-- recorded the way World records yours.
local function TargetWorld()
	local w, ns, set, p = World()
	w.hasTarget = true
	w:fire("PLAYER_TARGET_CHANGED")
	local tp = ns.GetBar("targetpower")
	tp.castTime.SetFormattedText = p.castTime.SetFormattedText
	return w, ns, ns.casts.targetcast, tp, p
end

local function TargetCast(w, name, left)
	w.targetCast = { name = name or "Shadow Bolt", id = "Cast-7", left = left or 2.43 }
	w:fire("UNIT_SPELLCAST_START", "target", "Cast-7", 686)
	return w.targetCast
end

H.test("the target's words sit on the target's power bar, above its see-through cast bar", function()
	local w, ns, t, tp = TargetWorld()
	for _, key in ipairs({ "castName", "castTime", "castWord" }) do
		H.eq(tp[key]:GetParent(), tp.textLayer, key .. "'s layer")
	end
	H.ok(tp.textLayer:GetFrameLevel() > t.holder:GetFrameLevel() + 1, "above the holder and the fill's level in the game")
	H.ok(tp.textLayer:GetFrameLevel() > t.base:GetFrameLevel(), "above the gray fill")
	H.ok(tp.textLayer:GetFrameLevel() > t.hot:GetFrameLevel(), "above the yellow fill")
	H.eq(t.text, nil, "no centered name of its own")
end)

H.test("the target's cast shows its name and time on its power bar, and gets no flash", function()
	local w, ns, t, tp, p = TargetWorld()
	local c = TargetCast(w)
	H.eq(t.holder:IsShown(), true, "the target's cast bar")
	Same({ Words(tp) }, { true, true, false }, "the target's name and timer")
	H.eq(tp.castName:GetText(), "Shadow Bolt", "the name")
	H.eq(tp.castTime:GetText(), "2.4", "the time left")
	c.left = 1.05
	Tick(t)
	H.eq(tp.castTime:GetText(), "1.1", "each frame asks again")
	Same({ Words(p) }, { false, false, false }, "your words stay off")
	w.targetCast = nil
	w:fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-7", 686)
	H.eq(t.holder:IsShown(), false, "it hides at once, as before")
	H.eq(t.flash, nil, "no flash")
	Same({ Words(tp) }, { false, false, false }, "its words go")
	Same({ Words(p) }, { false, false, false }, "still none of yours")
end)

H.test("a secret target cast name and time left go to the game as they are", function()
	local w, ns, t, tp = TargetWorld()
	w.secretCasting = true
	local name, left = w.Secret(), w.Secret()
	local seen
	tp.castName.SetText = function(self, v) seen = v; self.__h.text = v end
	TargetCast(w, name, left)
	Tick(t)
	H.ok(rawequal(seen, name), "SetText got the secret name itself")
	H.ok(rawequal(tp.castTime.__h.arg, left), "SetFormattedText got the secret time itself")
	H.eq(tp.castTime.__h.format, "%.1f", "one decimal")
	NoViolation(w, "secret target cast")
end)

H.test("Target cast bar off: a target cast event shows nothing", function()
	local w, ns, t, tp = TargetWorld()
	w.env.HUDiniDB.showTargetCast = false
	ns.HUDini:Layout()
	TargetCast(w)
	H.eq(t.holder:IsShown(), false, "no cast bar")
	Same({ Words(tp) }, { false, false, false }, "no words")
end)
