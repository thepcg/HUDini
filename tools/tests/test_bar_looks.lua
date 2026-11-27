-- A look for each bar (TICK-0224, D-049; design docs/design/bar-textures.md).
-- A bar id with nothing saved paints as today (Bar texture, its color, no
-- gradient); a saved look paints that look; the texture button reads and
-- writes only its own id; a bad custom path falls back with no Lua error.
-- The old Timer bar texture row keeps changing the timer bars until
-- TICK-0225 takes it away. What the player sees needs DK's play.

local function World(setup)
	local w = H.world()
	if setup then setup(w) end
	w:loadAddon()
	return w, w.ns, w.env.HUDiniDB
end

-- Colors as plain tables, so a test can read a gradient's two ends.
local function PlainColors(w)
	w.env.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
end

-- A bar that writes down what it is told. fail: SetStatusBarTexture
-- throws ("throw") or answers false ("false") for that path.
local function Bar(fail)
	local bar = { calls = {}, fill = { gradients = {} } }
	function bar:SetStatusBarTexture(path)
		if fail and fail[path] == "throw" then error("no such file") end
		self.texture = path
		self.calls[#self.calls + 1] = "texture"
		if fail and fail[path] == "false" then return false end
		return true
	end
	function bar:SetStatusBarColor(r, g, b)
		self.color = { r, g, b }
		self.calls[#self.calls + 1] = "color"
	end
	function bar:GetStatusBarTexture() return self.fill end
	function bar:GetReverseFill() return self.reverse == true end
	function bar.fill:SetGradient(dir, from, to)
		self.gradients[#self.gradients + 1] = { dir = dir, from = from, to = to }
	end
	return bar
end

local RED = { 0.8, 0.1, 0.1 }

local function Near(a, b, msg)
	H.ok(math.abs(a - b) < 1e-6, ("%s: got %s, want %s"):format(msg, tostring(a), tostring(b)))
end

H.test("nothing saved: every bar id is Bar texture, Off, as today", function()
	local _, ns, db = World()
	for _, id in ipairs(ns.BAR_LOOK_IDS) do
		H.eq(ns.BarLookField(id, "texture"), "same", id)
		H.eq(ns.BarLookField(id, "gradient"), "off", id)
		H.eq(ns.BarLookPath(id), ns.BarTexturePath(), id)
	end
	H.eq(ns.BarLookPath(ns.TimerLookId("Evocation")), ns.BarTexturePath())
	H.eq(db.barLooks, nil, "nothing is written by looking")
end)

H.test("nothing saved: a bar gets the texture, then its color, and no gradient", function()
	local _, ns = World()
	local bar = Bar()
	ns.LookBar(bar, "health")
	ns.PaintBar(bar, RED)
	H.eq(bar.texture, ns.BarTexturePath())
	H.eq(table.concat(bar.calls, ","), "texture,color", "the color comes after the texture")
	H.eq(bar.color[1], 0.8)
	H.eq(#bar.fill.gradients, 0)
	-- Painted again in another color: the texture is not set again.
	ns.PaintBar(bar, { 0, 1, 0 })
	H.eq(table.concat(bar.calls, ","), "texture,color,color")
end)

H.test("the HUD's own bars carry their ids", function()
	local _, ns = World()
	H.eq(ns.GetBar("health").lookId, "health")
	H.eq(ns.GetBar("power").lookId, "power")
end)

H.test("a saved look on the health bar changes the health bar only", function()
	local w, ns, db = World()
	PlainColors(w)
	H.eq(ns.SetBarLook("health", "texture", "flat"), true)
	H.eq(ns.SetBarLook("health", "gradient", "darker"), true)
	H.eq(ns.BarLookPath("health"), ns.TexturePathFor("flat"))
	for _, id in ipairs(ns.BAR_LOOK_IDS) do
		if id ~= "health" then
			H.eq(ns.BarLookPath(id), ns.BarTexturePath(), id .. " keeps Bar texture")
			H.eq(ns.BarLookField(id, "gradient"), "off", id .. " keeps Off")
		end
	end
	local saved = {}
	for id in pairs(db.barLooks) do saved[#saved + 1] = id end
	H.eq(table.concat(saved, ","), "health", "only the health bar's look is saved")

	local bar = Bar()
	ns.LookBar(bar, "health")
	ns.PaintBar(bar, RED)
	H.eq(bar.texture, ns.TexturePathFor("flat"))
	H.eq(#bar.fill.gradients, 1)
	local g = bar.fill.gradients[1]
	H.eq(g.dir, "HORIZONTAL")
	Near(g.from.r, 0.8, "starts at the bar's color")
	Near(g.to.r, 0.8 * 0.45, "fades to a darker shade")
end)

H.test("the gradients: lighter, to a color, and a bar that fills from the right", function()
	local w, ns = World()
	PlainColors(w)
	local bar = Bar()
	ns.LookBar(bar, "targethealth")
	ns.SetBarLook("targethealth", "gradient", "lighter")
	ns.PaintBar(bar, RED)
	local g = bar.fill.gradients[#bar.fill.gradients]
	Near(g.to.r, 0.8 + 0.2 * 0.5, "lighter red")
	Near(g.to.g, 0.1 + 0.9 * 0.5, "lighter green")

	ns.SetBarLook("targethealth", "gradient", "color")
	ns.SetBarLook("targethealth", "color", { 0, 0, 1 })
	ns.PaintBar(bar, RED)
	g = bar.fill.gradients[#bar.fill.gradients]
	Near(g.to.b, 1, "to the picked color")

	bar.reverse = true
	ns.PaintBar(bar, RED)
	g = bar.fill.gradients[#bar.fill.gradients]
	Near(g.from.b, 1, "the fade starts at the right")
	Near(g.to.r, 0.8, "and ends in the bar's color")
end)

H.test("a flat part never gets a gradient", function()
	local w, ns = World()
	PlainColors(w)
	ns.SetBarLook("health", "gradient", "darker")
	local bar = Bar()
	ns.LookBar(bar, "health", true)
	ns.PaintBar(bar, RED)
	H.eq(#bar.fill.gradients, 0)
end)

H.test("a bad custom path falls back to Bar texture with no Lua error", function()
	local _, ns = World()
	local file = "Interface\\AddOns\\Mine\\Gone.tga"
	ns.CustomTextures()[1] = file
	ns.SetBarLook("health", "texture", file)
	for _, how in ipairs({ "throw", "false" }) do
		local bar = Bar({ [file] = how })
		ns.LookBar(bar, "health")
		H.ok(pcall(ns.PaintBar, bar, RED), how .. ": no error")
		H.eq(bar.texture, ns.BarTexturePath(), how .. ": Bar texture")
		H.eq(bar.color[1], 0.8, how .. ": its color still")
	end
	H.eq(ns.BarLookField("health", "texture"), file, "the pick stays for a restart")
end)

H.test("SetBarLook refuses a bad value and an unknown id", function()
	local _, ns, db = World()
	H.eq(ns.SetBarLook("health", "texture", "no such texture"), false)
	H.eq(ns.SetBarLook("health", "gradient", "sideways"), false)
	H.eq(ns.SetBarLook("health", "color", { 1, 2 }), false)
	H.eq(ns.SetBarLook("feet", "texture", "flat"), false)
	H.eq(ns.SetBarLook("health", "size", 3), false)
	H.eq(db.barLooks and db.barLooks.health, nil)
end)

H.test("a picked color is copied, and a cleared look leaves no table", function()
	local _, ns, db = World()
	local c = { 0.1, 0.2, 0.3 }
	ns.SetBarLook("xp", "color", c)
	c[1] = 0.9
	H.eq(ns.BarLookField("xp", "color")[1], 0.1)
	ns.SetBarLook("xp", "color", nil)
	H.eq(db.barLooks.xp, nil)
end)

H.test("the old Timer bar texture key no longer changes a timer bar (TICK-0231)", function()
	local _, ns, db = World()
	local id = ns.TimerLookId("Evocation")
	db.timerBarTexture = "flat"
	H.eq(ns.BarLookField(id, "texture"), "same", "only ns.MoveTimerBarTexture reads it")
	H.eq(ns.BarLookPath(id), ns.BarLookPath("health"), "the HUD's bar texture")
end)

H.test("UnbindLookButton: a let-go button hides and no longer repaints", function()
	local w, ns = World()
	local b = ns.CreateLookButton(w.env.UIParent, 120)
	local painted = 0
	ns.BindLookButton(b, { id = "health", label = "Health" })
	local paint = ns.PaintBar
	ns.PaintBar = function(bar, ...)
		if bar == b.strip then painted = painted + 1 end
		return paint(bar, ...)
	end
	ns.RepaintLookButtons()
	H.ok(painted > 0, "a bound button repaints")
	local before = painted
	ns.UnbindLookButton(b)
	H.eq(b:IsShown(), false, "hidden")
	H.eq(b.look, nil, "no look")
	ns.RepaintLookButtons()
	H.eq(painted, before, "a look change does not repaint it")
	ns.UnbindLookButton(nil)
end)

H.test("MoveTimerBarTexture: the old pick goes to each timer bar that is on", function()
	local _, ns = World()
	local db = {
		timerBarTexture = "flat",
		classes = {
			MAGE = { timerBars = { Evocation = true, Blink = false },
				looks = { ["timer:Frost Nova"] = { texture = "smooth" } } },
			WARRIOR = { timerBars = { ["Frost Nova"] = true } },
		},
	}
	db.classes.MAGE.timerBars["Frost Nova"] = true
	ns.MoveTimerBarTexture(db)
	H.eq(db.timerBarTexture, nil)
	H.eq(db.classes.MAGE.looks["timer:Evocation"].texture, "flat")
	H.eq(db.classes.MAGE.looks["timer:Blink"], nil, "a bar that is off")
	H.eq(db.classes.MAGE.looks["timer:Frost Nova"].texture, "smooth", "its own pick stays")
	H.eq(db.classes.WARRIOR.looks["timer:Frost Nova"].texture, "flat")

	local hud = { timerBarTexture = "hud", classes = { MAGE = { timerBars = { Evocation = true } } } }
	ns.MoveTimerBarTexture(hud)
	H.eq(hud.timerBarTexture, nil)
	H.eq(hud.classes.MAGE.looks, nil, "hud writes nothing")
end)

H.test("a class bar's look is saved per class, and a class file gives defaults", function()
	local _, ns, db = World()
	H.eq(ns.SetBarLook("resource", "gradient", "darker"), true)
	H.eq(db.barLooks and db.barLooks.resource, nil, "not in the shared looks")
	H.eq(ns.ClassDB().looks.resource.gradient, "darker")

	local real = ns.ClassDefault
	ns.ClassDefault = function(key)
		if key == "barLooks" then
			return { resource = { texture = "flat" }, timer = { Blink = { gradient = "lighter" } } }
		end
		return real(key)
	end
	H.eq(ns.BarLookField("resource", "texture"), "flat", "the class file's default")
	H.eq(ns.BarLookField("resource", "gradient"), "darker", "the player's pick wins")
	H.eq(ns.BarLookField(ns.TimerLookId("Blink"), "gradient"), "lighter")
	H.eq(ns.BarLookDefault(ns.TimerLookId("Blink"), "gradient"), "lighter")
	H.eq(ns.BarLookField("health", "texture"), "same", "a shared bar has no class default")
	ns.ClassDefault = real
end)

H.test("Use on every timer bar copies one look to each cooldown spell", function()
	local _, ns = World()
	local real = ns.CooldownSpells
	ns.CooldownSpells = function() return { "Evocation", "Blink" } end
	local from = ns.TimerLookId("Evocation")
	ns.SetBarLook(from, "texture", "banded")
	ns.SetBarLook(from, "gradient", "color")
	ns.SetBarLook(from, "color", { 0, 1, 0 })
	local repaints = 0
	local repaint = ns.RepaintLooks
	ns.RepaintLooks = function() repaints = repaints + 1 end
	H.eq(ns.SetLookOnAllTimers(from), true)
	H.eq(repaints, 1, "one repaint")
	local id = ns.TimerLookId("Blink")
	H.eq(ns.BarLookField(id, "texture"), "banded")
	H.eq(ns.BarLookField(id, "gradient"), "color")
	H.eq(ns.BarLookField(id, "color")[2], 1)
	H.eq(ns.BarLookField("health", "texture"), "same", "no other bar")
	ns.RepaintLooks, ns.CooldownSpells = repaint, real
end)

H.test("custom files: the path is cleaned, checked and kept, at most 10", function()
	local w, ns, db = World()
	H.eq(ns.CleanTexturePath("  D:/World of Warcraft/_forever_/Interface/AddOns//Mine/Stripes.tga "),
		"Interface\\AddOns\\Mine\\Stripes.tga")
	H.eq(ns.TextureFileName("Interface\\AddOns\\Mine\\Stripes.tga"), "Stripes")

	local probe = w.env.CreateFrame("Frame"):CreateTexture()
	local refuse = {}
	probe.SetTexture = function(_, path) return refuse[path] == nil end
	H.eq(select(2, ns.AddCustomTexture("   ", probe)), "look.custom.empty")
	H.eq(select(2, ns.AddCustomTexture("C:\\Pictures\\Me.tga", probe)), "look.custom.notInterface")
	refuse["Interface\\AddOns\\Mine\\Gone.tga"] = true
	H.eq(select(2, ns.AddCustomTexture("Interface\\AddOns\\Mine\\Gone.tga", probe)), "look.custom.noFile")
	H.eq(db.customTextures == nil or #db.customTextures == 0, true, "nothing kept on a refusal")

	local ok, path = ns.AddCustomTexture("interface/addons/Mine/Stripes.tga", probe)
	H.eq(ok, true)
	H.eq(path, "interface\\addons\\Mine\\Stripes.tga")
	local again, same = ns.AddCustomTexture("Interface\\AddOns\\Mine\\Stripes.tga", probe)
	H.eq(again, true, "a file in the list already")
	H.eq(same, path)
	for i = 2, 10 do H.eq((ns.AddCustomTexture("Interface\\AddOns\\Mine\\T" .. i, probe)), true) end
	H.eq(#db.customTextures, 10)
	H.eq(select(2, ns.AddCustomTexture("Interface\\AddOns\\Mine\\T11", probe)), "look.custom.full")
end)

H.test("removing a custom file gives its bars Same as Bar texture", function()
	local _, ns, db = World()
	local file = "Interface\\AddOns\\Mine\\Stripes"
	ns.CustomTextures()[1] = file
	ns.SetBarLook("health", "texture", file)
	ns.SetBarLook("health", "gradient", "darker")
	ns.SetBarLook(ns.TimerLookId("Blink"), "texture", file)
	ns.SetBarLook("power", "texture", "flat")
	ns.RemoveCustomTexture(file)
	H.eq(#db.customTextures, 0)
	H.eq(ns.BarLookField("health", "texture"), "same")
	H.eq(ns.BarLookField("health", "gradient"), "darker", "the rest of the look stays")
	H.eq(ns.BarLookField(ns.TimerLookId("Blink"), "texture"), "same")
	H.eq(ns.BarLookField("power", "texture"), "flat", "another pick stays")
end)

--------------------------------------------------------------------------------
-- The texture button and its menu
--------------------------------------------------------------------------------

-- The game's menu description, faked: each entry keeps what it was given.
local function Root()
	local function Menu()
		local m = { entries = {} }
		local function Add(e)
			e.SetTooltip = function(self, fn) self.tip = fn end
			e.SetEnabled = function(self, on) self.enabled = on end
			m.entries[#m.entries + 1] = e
			return e
		end
		function m:CreateButton(text, click)
			local e = Menu()
			e.kind, e.text, e.click = "button", text, click
			e.SetTooltip = function(self, fn) self.tip = fn end
			e.SetEnabled = function(self, on) self.enabled = on end
			m.entries[#m.entries + 1] = e
			return e
		end
		function m:CreateRadio(text, isSet, set, value)
			return Add({ kind = "radio", text = text, isSet = isSet, set = set, value = value })
		end
		function m:CreateDivider() return Add({ kind = "divider" }) end
		return m
	end
	return Menu()
end

local function Find(menu, text)
	for _, e in ipairs(menu.entries) do
		if e.text == text or (e.text and e.text:find(text, 1, true)) then return e end
	end
end

local function Button(ns, w, look)
	local b = ns.CreateLookButton(w.env.UIParent, 180)
	return ns.BindLookButton(b, look)
end

H.test("the menu: Texture, Gradient, Gradient color, Custom file...", function()
	local w, ns = World()
	local Text = ns.Text
	local root = Root()
	ns.LookMenu(Button(ns, w, { id = "health", label = "Health bar" }), root)
	local texture = Find(root, Text("opt.look.texture"))
	local gradient = Find(root, Text("opt.look.gradient"))
	H.ok(texture and gradient, "two submenus")
	H.ok(Find(root, Text("opt.look.customFile")), "Custom file...")
	H.eq(Find(root, Text("opt.look.allTimers")), nil, "no Use on every timer bar")
	H.eq(texture.entries[1].value, "same")
	H.eq(#texture.entries, 1 + #ns.BarTextureList())
	H.eq(#gradient.entries, #ns.LOOK_GRADIENTS)
	local color = Find(root, Text("opt.look.color"))
	H.eq(color.enabled, false, "gray unless To a color")
	H.eq(texture.entries[1].isSet(), true, "the mark is on Same as Bar texture")
end)

-- The color rows of a bar's menu (TICK-0242): { key, at, entry } in order,
-- and where Gradient is.
local function ColorRows(ns, w, id)
	local root = Root()
	ns.LookMenu(Button(ns, w, { id = id, label = id }), root)
	local out, gradientAt = {}, nil
	for i, e in ipairs(root.entries) do
		if e.text == ns.Text("opt.look.gradient") then gradientAt = i end
		for _, key in ipairs(ns.BarColorKeys(id)) do
			-- A timer bar's one row is its own color (TICK-0259).
			local want = id:find("^timer:") and ns.Text("opt.look.timerBase")
				or ns.Text("opt.look.base", ns.Text("opt.color." .. key))
			if e.text and e.text:find(want, 1, true) then
				out[#out + 1] = { key = key, at = i, entry = e }
			end
		end
	end
	return out, gradientAt
end

H.test("a color row for each color the bar takes, above Gradient (TICK-0242)", function()
	local w, ns = World()
	local rows, gradientAt = ColorRows(ns, w, "targethealth")
	local keys = {}
	for _, r in ipairs(rows) do
		keys[#keys + 1] = r.key
		H.ok(r.at < gradientAt, r.key .. " is above Gradient")
		H.ok(r.at > 1, r.key .. " is under Texture")
	end
	H.eq(table.concat(keys, ","), "hostile,neutral,friendly,tapped", "the Colors page's target colors")
	-- Every Each bar row, the class resource and a timer bar have a color
	-- row; every Colors page color is in one look window.
	local seen = {}
	local ids = { "health", "power", "druidmana", "playercast", "xp", "targethealth", "targetpower",
		"targetcast", "resource", ns.TimerLookId("Evocation") }
	for _, id in ipairs(ids) do
		local list = ns.BarColorKeys(id)
		H.ok(#list > 0, id .. " has a color row")
		H.eq(#ColorRows(ns, w, id), #list, id .. ": one row per color")
		for _, key in ipairs(list) do
			seen[key] = true
			H.ok(ns.defaults.colors[key], key .. " is a saved color")
		end
	end
	for _, e in ipairs(ns.COLOR_KEYS) do H.ok(seen[e.key], e.key .. " is in a look window") end
	H.eq(table.concat(ns.BarColorKeys(ns.TimerLookId("Evocation")), ","), "timer", "a timer bar: the timer color")
	H.eq(table.concat(ns.BarColorKeys("druidmana"), ","), "mana", "mana in forms wears Mana")
	H.eq(#ns.BarColorKeys("tot"), 0, "no bar yet, no row")
	-- A new list each time: a caller cannot change the next one.
	ns.BarColorKeys("health")[1] = "x"
	H.eq(ns.BarColorKeys("health")[1], "health")
end)

H.test("a color row picks the saved color itself; Cancel puts it back", function()
	local w, ns, db = World()
	w.env.CreateColor = function(r, g, b)
		return { GenerateHexColor = function()
			return string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5),
				math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
		end }
	end
	w.env.CreateColorFromHexString = function(hex)
		local function N(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
		return { r = N(3), g = N(5), b = N(7) }
	end
	local info
	w.env.ColorPickerFrame = {
		SetupColorPickerAndShow = function(_, i) info = i end,
		GetColorRGB = function() return 1, 0, 0 end,
	}
	local rows = ColorRows(ns, w, "health")
	H.eq(rows[1].key, "health")
	local d = ns.defaults.colors.health
	H.ok(rows[1].entry.text:find(("%d:%d:%d|t"):format(d[1] * 255, d[2] * 255, d[3] * 255), 1, true),
		"the square is the color now: " .. rows[1].entry.text)
	rows[1].entry.click()
	H.eq(info.r, d[1], "the picker starts at the color now")
	info.swatchFunc()
	H.eq(table.concat(db.colors.health, ","), "1,0,0", "saved where the Colors page saves it")
	H.eq(ns.BarColor("health")[1], 1)
	H.eq(db.barLooks, nil, "no look saved")
	info.cancelFunc()
	-- The Colors page keeps hex, so the color comes back to 1/255.
	local c = ns.BarColor("health")
	for i = 1, 3 do H.ok(math.abs(c[i] - d[i]) <= 0.5 / 255, "Cancel: the color before, " .. i) end

	-- The button's face is the bar as it looks now: a color pick repaints
	-- it. A timer color also repaints the timer bars (TimerBars.lua keeps
	-- them), as the Colors page's setter does.
	local faces, timers = 0, 0
	ns.RepaintLookButtons = function() faces = faces + 1 end
	ns.RefreshTimerBars = function() timers = timers + 1 end
	info.swatchFunc()
	H.eq(faces, 1, "a pick repaints the texture buttons")
	H.eq(timers, 0, "a health pick leaves the timer bars")
	-- A timer bar's row is its own color (TICK-0258): the Colors page's
	-- Timer bar color stays.
	local timer = table.concat(ns.BarColor("timer"), ",")
	local evocation = ns.TimerLookId("Evocation")
	ColorRows(ns, w, evocation)[1].entry.click()
	H.eq(info.r, ns.BarColor("timer")[1], "the picker starts at the color the bar wears")
	info.swatchFunc()
	H.eq(table.concat(ns.BarColor("timer"), ","), timer, "the Timer bar color stays")
	H.eq(table.concat(ns.BarLookField(evocation, "base"), ","), "1,0,0", "the bar's own color is saved")
	H.eq(timers, 1, "a timer pick repaints the timer bars")
	H.eq(faces, 2)
	info.cancelFunc()
	H.eq(ns.BarLookField(evocation, "base"), nil, "Cancel: none of its own again")
end)

H.test("a pick in the menu writes that bar's look and no other", function()
	local w, ns, db = World()
	local root = Root()
	ns.LookMenu(Button(ns, w, { id = "targetcast", label = "Target cast bar" }), root)
	local texture = Find(root, ns.Text("opt.look.texture"))
	local flat
	for _, e in ipairs(texture.entries) do if e.value == "flat" then flat = e end end
	flat.set()
	H.eq(flat.isSet(), true)
	local gradient = Find(root, ns.Text("opt.look.gradient"))
	gradient.entries[2].set()
	H.eq(ns.BarLookField("targetcast", "texture"), "flat")
	H.eq(ns.BarLookField("targetcast", "gradient"), ns.LOOK_GRADIENTS[2])
	local saved = {}
	for id in pairs(db.barLooks) do saved[#saved + 1] = id end
	H.eq(table.concat(saved, ","), "targetcast")
end)

H.test("a timer bar's menu offers Use on every timer bar", function()
	local w, ns = World()
	local root = Root()
	ns.LookMenu(Button(ns, w, { id = ns.TimerLookId("Evocation"), label = "Evocation", allTimers = true }), root)
	H.eq(root.entries[#root.entries - 1].kind, "divider")
	H.ok(Find(root, ns.Text("opt.look.allTimers")), "the entry")
end)

H.test("the menu's strips show the power bar in your power's color", function()
	local w, ns = World()
	ns.PowerColor = function() return { 0.9, 0.05, 0.05 } end
	H.eq(ns.BarLookColor("power")[1], 0.9)
	local root = Root()
	ns.LookMenu(Button(ns, w, { id = "power", label = "Power bar" }), root)
	local texture = Find(root, ns.Text("opt.look.texture"))
	H.ok(texture.entries[2].text:find(":229:12:12|t", 1, true), "a red strip: " .. texture.entries[2].text)
end)

H.test("custom files are in the Texture menu as Custom: and their name", function()
	local w, ns = World()
	ns.CustomTextures()[1] = "Interface\\AddOns\\Mine\\Stripes.tga"
	local root = Root()
	ns.LookMenu(Button(ns, w, { id = "xp", label = "XP bar" }), root)
	local texture = Find(root, ns.Text("opt.look.texture"))
	local last = texture.entries[#texture.entries]
	H.eq(last.value, "Interface\\AddOns\\Mine\\Stripes.tga")
	H.ok(last.text:find(ns.Text("opt.look.custom", "Stripes"), 1, true), last.text)
end)

H.test("the button's tooltip: the label, the picks, the row tip", function()
	local w, ns = World()
	local b = Button(ns, w, { id = "health", label = "Health bar" })
	ns.SetBarLook("health", "gradient", "darker")
	b:GetScript("OnEnter")(b)
	local lines = w.env.GameTooltip.__h.lines
	local all = { w.env.GameTooltip:GetText() }
	for _, l in ipairs(lines) do all[#all + 1] = type(l) == "table" and l.text or tostring(l) end
	local text = table.concat(all, "\n")
	H.ok(text:find("Health bar", 1, true), text)
	H.ok(text:find(ns.LookPicksLine("health"), 1, true), text)
	H.ok(ns.LookPicksLine("health"):find(ns.Text("opt.look.gradient.darker"), 1, true))
	H.ok(text:find(ns.Text("opt.look.row.tip"), 1, true), text)
end)

H.test("a new look repaints the bound button's strip", function()
	local w, ns = World()
	local b = Button(ns, w, { id = "pet", label = "Pet bar" })
	H.eq(b.strip.lookId, "pet")
	H.eq(b.strip.lookAsked, ns.BarTexturePath())
	ns.SetBarLook("pet", "texture", "banded")
	H.eq(b.strip.lookAsked, ns.TexturePathFor("banded"))
end)

H.test("the row's settings: fixed defaults, so the page's Defaults resets them", function()
	local w, ns = World()
	local made = {}
	w.env.Settings.RegisterProxySetting = function(_, name, _, _, default, get, set)
		made[name] = { default = default, get = get, set = set }
		return made[name]
	end
	ns.BarLookSettings(H.Fake(), "health")
	local tex, grad, col = made.HUDini_look_health_texture, made.HUDini_look_health_gradient,
		made.HUDini_look_health_color
	H.eq(tex.default, "same")
	H.eq(grad.default, "off")
	H.eq(type(col.default), "table", "the fake's hex") -- the fake CreateColor gives a fake
	tex.set("flat")
	H.eq(ns.BarLookField("health", "texture"), "flat")
	H.eq(tex.get(), "flat")
	tex.set(tex.default)
	H.eq(ns.BarLookPath("health"), ns.BarTexturePath(), "Defaults gives today's look")
	H.eq(ns.BarLookField("power", "texture"), "same")
end)

H.test("a texture button row gives its label to the settings search", function()
	local w, ns = World()
	local tags = {}
	local init = { AddSearchTags = function(_, ...) for _, t in ipairs({ ... }) do tags[#tags + 1] = t end end }
	w.env.Settings.CreateElementInitializer = function(template, data)
		init.template, init.data = template, data
		return init
	end
	local added
	local layout = { AddInitializer = function(_, i) added = i end }
	local got = ns.AddLookRow(H.Fake(), layout, { id = "health", label = "Health bar" })
	H.eq(got, init)
	H.eq(added, init)
	H.eq(table.concat(tags, ","), "Health bar")
	H.eq(init.data.look.id, "health")
end)

-- A frame of the game's SettingsListElementTemplate as this client makes
-- it: the mixin's methods, and no callback list, as its OnLoad never runs
-- (the template has no OnLoad script of its own; only its Tooltip child
-- has one: Blizzard_SettingControls.xml:50-78, wow-ui-source forever
-- 9dc84f0). Init asserts the list is empty and signs up one handle per
-- setting a grayed row reads (.lua:331 and :349-354); Release empties it.
local function BaseRow(w)
	local frame = w:Frame(nil, w.env.UIParent)
	local log = {}
	frame.OnLoad = function(self)
		local n = 0
		self.cbrHandles = {
			IsEmpty = function() return n == 0 end,
			Add = function() n = n + 1 end,
			Unregister = function() n = 0; log[#log + 1] = "unregister" end,
		}
	end
	frame.Init = function(self, init)
		assert(self.cbrHandles:IsEmpty())
		for _ in ipairs(init:GetEvaluateStateCVars() or {}) do self.cbrHandles.Add() end
		self.data = init.data
		log[#log + 1] = "init"
	end
	frame.Release = function(self)
		self.cbrHandles:Unregister()
		self.data = nil
	end
	return frame, log
end

-- The game's element initializer, as far as the row uses it, with the
-- settings a grayed row reads (GreyUnless in Options.lua).
local function RowMaker(w)
	w.env.Settings.CreateElementInitializer = function(template, data)
		local cvars
		return { template = template, data = data, AddSearchTags = function() end,
			AddEvaluateStateCVar = function(_, v) cvars = cvars or {}; cvars[#cvars + 1] = v end,
			GetEvaluateStateCVars = function() return cvars end }
	end
	return { AddInitializer = function() end }
end

-- Draw, free, draw again on the same pooled frame, grayed by one setting.
-- part: the row's HUDini child; bound: its bound field.
local function PoolTwice(w, init, part, bound)
	init:AddEvaluateStateCVar("HUDini_showHealth")
	H.eq(init.GetExtent and init:GetExtent(), 26, "26 high, as the game's rows")
	local frame, log = BaseRow(w)
	local ok, err = pcall(init.InitFrame, init, frame)
	H.ok(ok, "no Lua error: " .. tostring(err))
	H.eq(log[1], "init", "the game's Init ran")
	local x = frame[part]
	H.ok(x and x:IsShown() and x[bound], "it shows, bound")
	init.Resetter(init, frame)
	H.eq(log[2], "unregister", "a freed row lets the game's list go")
	H.eq(x[bound], nil, "and its own part")
	ok, err = pcall(init.InitFrame, init, frame)
	H.ok(ok, "the pooled frame draws again, its list empty: " .. tostring(err))
	H.ok(x:IsShown() and x[bound], "bound again")
end

H.test("TICK-0240: a texture button row draws on the game's base row, whose OnLoad never ran", function()
	local w, ns = World()
	local init = ns.AddLookRow(H.Fake(), RowMaker(w), { id = "health", label = "Health bar" })
	H.ok(init, "a row")
	PoolTwice(w, init, "hudiniLook", "look")
end)

--------------------------------------------------------------------------------
-- The Custom texture window
--------------------------------------------------------------------------------

H.test("Use this file adds the file and gives it to that bar only", function()
	local w, ns, db = World()
	local win = ns.OpenCustomTexture("health", "Health bar")
	local p = win.parts
	p.probe.SetTexture = function() return true end
	p.box:SetText("Interface\\AddOns\\Mine\\Stripes.tga")
	p.use:GetScript("OnClick")(p.use)
	H.eq(db.customTextures[1], "Interface\\AddOns\\Mine\\Stripes.tga")
	H.eq(ns.BarLookField("health", "texture"), "Interface\\AddOns\\Mine\\Stripes.tga")
	H.eq(ns.BarLookField("power", "texture"), "same")
	H.eq(win:IsShown(), false, "it closes")
end)

H.test("the window says why a path is refused and changes nothing", function()
	local w, ns, db = World()
	local win = ns.OpenCustomTexture("health", "Health bar")
	local p = win.parts
	p.probe.SetTexture = function() return false end
	p.box:SetText("C:\\Me.tga")
	p.use:GetScript("OnClick")(p.use)
	H.eq(p.err:GetText(), ns.Text("look.custom.notInterface"))
	p.box:SetText("Interface\\AddOns\\Mine\\Gone.tga")
	p.use:GetScript("OnClick")(p.use)
	H.eq(p.err:GetText(), ns.Text("look.custom.noFile"))
	H.eq(win:IsShown(), true)
	H.eq(db.customTextures == nil or #db.customTextures == 0, true)
	H.eq(ns.BarLookField("health", "texture"), "same")
end)

H.test("with 10 files Use this file is gray, and a removed file frees it", function()
	local w, ns = World()
	for i = 1, 10 do ns.CustomTextures()[i] = "Interface\\AddOns\\Mine\\T" .. i end
	local win = ns.OpenCustomTexture("xp", "XP bar")
	local p = win.parts
	p.box:SetText("Interface\\AddOns\\Mine\\New.tga")
	H.eq(p.use:IsEnabled(), false)
	p.rows[1].x:GetScript("OnClick")(p.rows[1].x)
	H.eq(#ns.CustomTextures(), 9)
	H.eq(p.use:IsEnabled(), true)
end)

H.test("a broken saved list of custom files gives no Lua error", function()
	local w, ns, db = World()
	db.customTextures = { "Interface\AddOns\Mine\A.tga", 5, {}, false, "Interface\AddOns\Mine\B.tga" }
	local list = ns.CustomTextures()
	H.eq(#list, 2, "only the paths are kept")
	H.eq(list[1], "Interface\AddOns\Mine\A.tga")
	H.eq(list[2], "Interface\AddOns\Mine\B.tga")
	db.customTextures = { [1] = "Interface\AddOns\Mine\A.tga", [3] = "Interface\AddOns\Mine\C.tga", x = 1 }
	H.eq(#ns.CustomTextures(), 2, "no gap left in the list")
	H.eq(ns.CustomTextures()[2], "Interface\AddOns\Mine\C.tga")
	-- Every reader of the list: the menu, the window's rows, typing a path.
	db.customTextures = { 7, "Interface\AddOns\Mine\A.tga", {} }
	local root = Root()
	ns.LookMenu(Button(ns, w, { id = "xp", label = "XP bar" }), root)
	local texture = Find(root, ns.Text("opt.look.texture"))
	H.eq(texture.entries[#texture.entries].value, "Interface\AddOns\Mine\A.tga")
	db.customTextures = { "Interface\AddOns\Mine\A.tga", true }
	local win = ns.OpenCustomTexture("xp", "XP bar")
	local p = win.parts
	p.box:SetText("Interface\AddOns\Mine\a.tga")
	local changed = p.box:GetScript("OnTextChanged")
	if changed then changed(p.box, true) end
	H.eq(p.rows[1].path:GetText(), "Interface\AddOns\Mine\A.tga")
end)

H.test("Use on every timer bar copies a saved texture whose addon is not loaded now", function()
	local _, ns = World()
	local realSpells, realList = ns.CooldownSpells, ns.BarTextureList
	ns.CooldownSpells = function() return { "Evocation", "Blink" } end
	local from = ns.TimerLookId("Evocation")
	ns.BarTextureList = function() return { { key = "Gone Stripes" } } end
	H.eq(ns.SetBarLook(from, "texture", "Gone Stripes"), true)
	ns.BarTextureList = function() return {} end -- its addon is gone now
	H.eq(ns.SetBarLook(ns.TimerLookId("Blink"), "texture", "Gone Stripes"), false, "a menu pick is refused")
	ns.SetLookOnAllTimers(from)
	H.eq(ns.BarLookField(ns.TimerLookId("Blink"), "texture"), "Gone Stripes", "the copy keeps it")
	ns.CooldownSpells, ns.BarTextureList = realSpells, realList
end)

H.test("Cancel in the color picker puts back what was saved, and nothing when nothing was", function()
	local w, ns = World()
	local info
	w.env.ColorPickerFrame = {
		SetupColorPickerAndShow = function(_, i) info = i end,
		GetColorRGB = function() return 1, 0, 1 end,
	}
	local function Pick()
		local root = Root()
		ns.LookMenu(Button(ns, w, { id = "health", label = "Health bar" }), root)
		Find(root, ns.Text("opt.look.color")).click()
	end
	Pick()
	info.swatchFunc()
	H.eq(ns.SavedBarLookField("health", "color")[1], 1, "the picked color shows")
	info.cancelFunc()
	H.eq(ns.SavedBarLookField("health", "color"), nil, "nothing saved again")
	ns.SetBarLook("health", "color", { 0, 1, 0 })
	Pick()
	info.swatchFunc()
	info.cancelFunc()
	local c = ns.SavedBarLookField("health", "color")
	H.eq(c[1] .. "," .. c[2] .. "," .. c[3], "0,1,0", "the saved color again")
end)

H.test("the color setting: a hex default, and the default saved as it is", function()
	local w, ns = World()
	w.env.CreateColor = function(r, g, b)
		return { GenerateHexColor = function()
			return string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5),
				math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
		end }
	end
	w.env.CreateColorFromHexString = function(hex)
		local function N(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
		return { r = N(3), g = N(5), b = N(7) }
	end
	local made = {}
	w.env.Settings.RegisterProxySetting = function(_, name, _, _, default, get, set)
		made[name] = { default = default, get = get, set = set }
		return made[name]
	end
	ns.BarLookSettings(H.Fake(), "health")
	local col = made.HUDini_look_health_color
	local d = ns.BarLookDefault("health", "color")
	H.eq(col.default, w.env.CreateColor(d[1], d[2], d[3]).GenerateHexColor())
	H.eq(col.get(), col.default)
	col.set("ff00ff00")
	H.eq(ns.BarLookField("health", "color")[2], 1)
	H.eq(col.get(), "ff00ff00")
	col.set(col.default)
	local c = ns.BarLookField("health", "color")
	H.eq(c[1] .. "," .. c[2] .. "," .. c[3], d[1] .. "," .. d[2] .. "," .. d[3], "the default, not its hex")
end)

--------------------------------------------------------------------------------
-- TICK-0258: each timer bar's own color.
--------------------------------------------------------------------------------

H.test("a timer bar's color is its own; with none it follows the Timer bar color", function()
	local _, ns, db = World()
	local evo, blink = ns.TimerLookId("Evocation"), ns.TimerLookId("Blink")
	db.colors.timer = { 0, 0, 1 }
	H.eq(table.concat(ns.TimerBarColor(evo), ",", 1, 3), "0,0,1", "none: the Timer bar color")
	H.eq(ns.SetBarLook(evo, "base", { 0, 1, 0 }), true)
	H.eq(table.concat(ns.TimerBarColor(evo), ",", 1, 3), "0,1,0", "its own")
	H.eq(table.concat(ns.TimerBarColor(blink), ",", 1, 3), "0,0,1", "the other bar keeps the Timer bar color")
	H.eq(table.concat(ns.BarLookColor(evo), ",", 1, 3), "0,1,0", "its texture button shows it")
	db.colors.timer = { 1, 1, 0 }
	H.eq(table.concat(ns.TimerBarColor(evo), ",", 1, 3), "0,1,0", "a new Timer bar color leaves its own")
	H.eq(table.concat(ns.TimerBarColor(blink), ",", 1, 3), "1,1,0", "and changes the bar with none")
	H.ok(ns.BarLookKey(evo) ~= ns.BarLookKey(blink), "the look key holds it, so the bar repaints")
	db.colors.timer = { 1, 1, 0, 0.5 }
	H.eq(ns.TimerBarColor(evo)[4], 0.5, "its own color keeps the Timer bar color's alpha")
	H.eq(ns.SetBarLook("health", "base", { 0, 1, 0 }), false, "only a timer bar has one")
	H.eq(db.barLooks, nil)
end)

H.test("Use on every timer bar copies the bar's own color, or none", function()
	local _, ns = World()
	local real = ns.CooldownSpells
	ns.CooldownSpells = function() return { "Evocation", "Blink" } end
	local evo, blink = ns.TimerLookId("Evocation"), ns.TimerLookId("Blink")
	ns.SetBarLook(evo, "base", { 0, 1, 0 })
	ns.SetLookOnAllTimers(evo)
	H.eq(table.concat(ns.BarLookField(blink, "base"), ","), "0,1,0", "copied")
	ns.SetBarLook(evo, "base", nil)
	ns.SetLookOnAllTimers(evo)
	H.eq(ns.BarLookField(blink, "base"), nil, "none copied: Blink follows the Timer bar color again")
	ns.CooldownSpells = real
end)

H.test("the timer bar's own color setting: Defaults clears it", function()
	local w, ns = World()
	local made = {}
	w.env.Settings.RegisterProxySetting = function(_, name, _, label, default, get, set)
		made[name] = { label = label, default = default, get = get, set = set }
		return made[name]
	end
	w.env.CreateColorFromHexString = function(hex)
		local function N(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
		return { r = N(3), g = N(5), b = N(7) }
	end
	local id = ns.TimerLookId("Evocation")
	local four = select(4, ns.BarLookSettings(H.Fake(), id, "cd_Evocation_look"))
	local own = made.HUDini_cd_Evocation_look_base
	H.ok(own ~= nil and own == four, "a fourth setting for a timer bar")
	H.eq(own.default, "", "none by default")
	H.eq(own.get(), "")
	own.set("ff00ff00")
	H.eq(table.concat(ns.BarLookField(id, "base"), ","), "0,1,0")
	own.set(own.default)
	H.eq(ns.BarLookField(id, "base"), nil, "Defaults: the Timer bar color again")
	H.eq(own.label, ns.Text("opt.look.timerBase"), "named This bar's color, not the Colors page's Timer bar (TICK-0259)")
	H.eq(select(4, ns.BarLookSettings(H.Fake(), "health")), nil, "no fourth for an Each bar row")
end)
