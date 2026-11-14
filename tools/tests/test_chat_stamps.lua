-- Chat date and time stamps (TICK-0154, D-038): with the setting on, each
-- new line in a chat window starts "yy-mm-dd@HH:MM:SS | " in realm time
-- (typed "||": in game text one "|" starts a code). Off at the start. A
-- secret line is left as it came, with no error.

-- A chat window as the game makes one, cut down: AddMessage puts the line
-- in a ring of CAP lines; TransformMessages asks the predicate about every
-- line in the ring, in order, and rewrites the ones it says yes to.
local CAP = 4

local function ChatFrame(w, name)
	local buf = { elements = {}, head = 0 }
	function buf:CalculateElementIndex(offset) return (self.head - offset) % CAP + 1 end
	local f = { name = name, historyBuffer = buf, transforms = 0 }
	function f:Clear() buf.elements, buf.head = {}, 0 end
	function f:AddMessage(msg, r, g, b, ...)
		buf.head = buf.head % CAP + 1
		buf.elements[buf.head] = { msg, r, g, b, ... }
	end
	function f:TransformMessages(pred, transform)
		self.transforms = self.transforms + 1
		for i, e in ipairs(buf.elements) do
			if pred(unpack(e)) then buf.elements[i] = { transform(unpack(e)) } end
		end
	end
	-- The newest line's text.
	function f:Last() return buf.elements[buf.head][1] end
	function f:Line(i) return buf.elements[i] and buf.elements[i][1] end
	w.env[name] = f
	return f
end

-- A world at serverTime (UTC), whose realm calendar says cal. saved: the
-- saved settings. Chat windows 1 to 3; 2 is the combat log.
local function World(saved, serverTime, cal)
	local w = H.world()
	w.secret = {}
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.env.HUDiniDB = saved
	w.serverTime = serverTime or 1794666304 -- 2026-11-14 14:25:04 UTC
	w.cal = cal or { year = 2026, month = 11, monthDay = 14, hour = 9, minute = 25 }
	w.env.GetServerTime = function() return w.serverTime end
	w.env.C_DateAndTime = { GetCurrentCalendarTime = function() return w.cal end }
	w.env.ChatFrameUtil = { GetTimestampFormat = function() return w.gameStamps end }
	w.env.NUM_CHAT_WINDOWS = 3
	w.env.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2", "ChatFrame3" }
	for i = 1, 3 do ChatFrame(w, "ChatFrame" .. i) end
	w.env.COMBATLOG = w.env.ChatFrame2
	-- A whisper in its own window, as FloatingChatFrame.lua:881-960 does it:
	-- reuse a closed whisper window or make one, clear it, copy the source
	-- window's lines for that target (the 5th argument here) into it.
	local function CopyLines(from, to, target)
		if not from then return end
		for _, e in ipairs(from.historyBuffer.elements) do
			if e[5] == target then to:AddMessage(unpack(e)) end
		end
	end
	w.env.FCF_OpenTemporaryWindow = function(_, target, source)
		local f
		for _, name in pairs(w.env.CHAT_FRAMES) do
			local c = w.env[name]
			if c.isTemporary and not c.inUse then f = c; break end
		end
		if not f then
			local name = "ChatFrame" .. (#w.env.CHAT_FRAMES + 1)
			f = ChatFrame(w, name)
			table.insert(w.env.CHAT_FRAMES, name)
		end
		f:Clear()
		f.inUse, f.isTemporary = true, true
		CopyLines(source, f, target)
		return f
	end
	-- Pop a chat tab out (ChatFrameUtil.lua:740-795): a new window (here
	-- window 3), cleared, then the lines copied.
	w.env.ChatFrameUtil.PopOutChat = function(source, _, target)
		local f = w.env.ChatFrame3
		f:Clear()
		CopyLines(source, f, target)
	end
	w:loadAddon()
	return w, w.env.ChatFrame1
end

local function On()
	return World({ chatStamps = true })
end

local function AddMessageHooks(w)
	local n = 0
	for _, h in ipairs(w.secureHooks) do
		if h.name == "AddMessage" then n = n + 1 end
	end
	return n
end

H.test("off at the start: no stamp, no chat window hooked", function()
	local w, chat = World()
	H.eq(w.env.HUDiniDB.chatStamps, false, "the default is off")
	H.eq(AddMessageHooks(w), 0, "no AddMessage hook")
	chat:AddMessage("hello", 1, 1, 0)
	H.eq(chat:Last(), "hello", "as it came")
end)

H.test("on: a line starts with the realm date and time", function()
	local _, chat = On()
	chat:AddMessage("hello", 1, 1, 0, 7)
	H.eq(chat:Last(), "26-11-14@09:25:04 || hello", "realm time: UTC 14:25:04, realm 09:25")
	local e = chat.historyBuffer.elements[chat.historyBuffer.head]
	H.eq(e[2] .. e[3] .. e[4] .. e[5], "1107", "color and the rest kept")
end)

H.test("every chat window but the combat log", function()
	local w = On()
	for i = 1, 3 do w.env["ChatFrame" .. i]:AddMessage("line " .. i) end
	H.eq(w.env.ChatFrame1:Last(), "26-11-14@09:25:04 || line 1", "window 1")
	H.eq(w.env.ChatFrame2:Last(), "line 2", "the combat log: as it came")
	H.eq(w.env.ChatFrame3:Last(), "26-11-14@09:25:04 || line 3", "window 3")
end)

H.test("a whisper window opened later is stamped too", function()
	local w = On()
	local f = w.env.FCF_OpenTemporaryWindow("WHISPER", "Someone", w.env.ChatFrame1, true)
	f:AddMessage("psst")
	H.eq(f:Last(), "26-11-14@09:25:04 || psst", "the new window")
end)

H.test("the realm date, not the UTC date, near midnight", function()
	-- 2026-11-15 03:00:10 UTC; the realm says 2026-11-14 22:00.
	local _, chat = World({ chatStamps = true }, 1794711610,
		{ year = 2026, month = 11, monthDay = 14, hour = 22, minute = 0 })
	chat:AddMessage("late")
	H.eq(chat:Last(), "26-11-14@22:00:10 || late", "the realm's day")
end)

H.test("a leap day, and a realm ahead of UTC", function()
	-- 2024-02-29 23:59:59 UTC; the realm says 2024-03-01 00:59.
	local _, chat = World({ chatStamps = true }, 1709251199,
		{ year = 2024, month = 3, monthDay = 1, hour = 0, minute = 59 })
	chat:AddMessage("tick")
	H.eq(chat:Last(), "24-03-01@00:59:59 || tick", "one hour ahead, past the leap day")
end)

H.test("the seconds move on with the server clock", function()
	local w, chat = On()
	w.serverTime = w.serverTime + 125 -- the calendar is read again only each minute
	chat:AddMessage("later")
	H.eq(chat:Last(), "26-11-14@09:27:09 || later", "2 minutes 5 seconds on")
end)

H.test("a secret line is left as it came, with no error", function()
	local w, chat = On()
	chat:AddMessage("hush")
	H.eq(chat:Last(), "26-11-14@09:25:04 || hush", "plain: stamped")
	w.secret["hush"] = true
	local before = chat.transforms
	chat:AddMessage("hush")
	H.eq(chat:Last(), "hush", "secret: as it came")
	H.eq(chat.transforms, before, "secret: the history is not even read")
end)

H.test("a secret server time gives no stamp", function()
	local w, chat = On()
	chat:AddMessage("a")
	H.eq(chat:Last(), "26-11-14@09:25:04 || a", "plain: stamped")
	w.serverTime = w.serverTime + 1
	w.secret[w.serverTime] = true
	chat:AddMessage("b")
	H.eq(chat:Last(), "b", "secret: no stamp")
end)

H.test("a secret calendar hour gives no stamp, never a wrong one", function()
	local w, chat = World({ chatStamps = true }, nil,
		{ year = 2026, month = 11, monthDay = 14, hour = 9.5, minute = 25 })
	chat:AddMessage("a")
	H.eq(chat:Last(), "26-11-14@09:55:04 || a", "plain: the hour is read")
	w = World({ chatStamps = true }, nil,
		{ year = 2026, month = 11, monthDay = 14, hour = 9.5, minute = 25 })
	w.secret[9.5] = true
	chat = w.env.ChatFrame1
	chat:AddMessage("b")
	H.eq(chat:Last(), "b", "secret: no stamp")
end)

H.test("no calendar from the game: no stamp, never the PC clock", function()
	local w, chat = On()
	w.cal = nil
	chat:AddMessage("x")
	H.eq(chat:Last(), "x", "as it came")
end)

H.test("the game's own stamp is taken off: one stamp on the line", function()
	local w, chat = On()
	w.gameStamps = "%H:%M:%S "
	chat:AddMessage("15:25:04 hello")
	H.eq(chat:Last(), "26-11-14@09:25:04 || hello", "24-hour stamp replaced")
	w.gameStamps = "[%I:%M %p] "
	chat:AddMessage("[3:25 PM] hi")
	H.eq(chat:Last(), "26-11-14@09:25:04 || hi", "12-hour stamp replaced")
	w.gameStamps = nil
	chat:AddMessage("12:00 noon")
	H.eq(chat:Last(), "26-11-14@09:25:04 || 12:00 noon", "game stamps off: the text stays whole")
end)

H.test("an older line with the same text keeps its own text", function()
	local w, chat = World()
	local db = w.env.HUDiniDB
	-- Off: six lines in a ring of four, so the ring has wrapped:
	-- e, f, c, d. The new line goes in place 3, after the old "e" in place 1.
	for _, s in ipairs({ "a", "b", "c", "d", "e", "f" }) do chat:AddMessage(s) end
	db.chatStamps = true
	w.ns.HUDini:Apply()
	chat:AddMessage("e")
	H.eq(chat:Line(1), "e", "the old line: as it was")
	H.eq(chat:Line(3), "26-11-14@09:25:04 || e", "the new line: stamped")
end)

H.test("turned off again: new lines come as they are", function()
	local w, chat = On()
	chat:AddMessage("one")
	w.env.HUDiniDB.chatStamps = false
	w.ns.HUDini:Apply()
	chat:AddMessage("two")
	H.eq(chat:Line(1), "26-11-14@09:25:04 || one", "a stamped line stays")
	H.eq(chat:Last(), "two", "no stamp")
	w.env.HUDiniDB.chatStamps = true
	w.ns.HUDini:Apply()
	H.eq(AddMessageHooks(w), 3, "on again: each window hooked once")
end)

H.test("a line with HUDini's stamp at the start gets no second one", function()
	local w, chat = On()
	chat:AddMessage("hi")
	w.serverTime = w.serverTime + 300
	w.env.ChatFrame3:AddMessage(chat:Last())
	H.eq(w.env.ChatFrame3:Last(), "26-11-14@09:25:04 || hi", "one stamp, the first time")
end)

H.test("a reused whisper window: the copied lines keep their own stamp", function()
	local w, chat = World()
	local db = w.env.HUDiniDB
	chat:AddMessage("old", 1, 1, 1, "Bob")    -- before the setting went on
	db.chatStamps = true
	w.ns.HUDini:Apply()
	chat:AddMessage("hi", 1, 1, 1, "Bob")
	local open = w.env.FCF_OpenTemporaryWindow
	local f = open("WHISPER", "Bob", chat, true)
	f.inUse = false                           -- closed
	w.serverTime = w.serverTime + 300
	f = open("WHISPER", "Bob", chat, true)    -- the same window again, hooked now
	H.eq(f:Line(1), "old", "a copy keeps its lack of a stamp")
	H.eq(f:Line(2), "26-11-14@09:25:04 || hi", "a copy keeps its stamp, one stamp")
	f:AddMessage("new", 1, 1, 1, "Bob")
	H.eq(f:Last(), "26-11-14@09:30:04 || new", "a new line after the copy: stamped")
end)

H.test("a popped-out tab: the copied lines keep their own stamp", function()
	local w, chat = World()
	local db = w.env.HUDiniDB
	chat:AddMessage("old", 1, 1, 1, "GUILD")
	db.chatStamps = true
	w.ns.HUDini:Apply()
	w.env.ChatFrameUtil.PopOutChat(chat, "GUILD", "GUILD")
	local f = w.env.ChatFrame3
	H.eq(f:Last(), "old", "the copy: as it was")
	f:AddMessage("new", 1, 1, 1, "GUILD")
	H.eq(f:Last(), "26-11-14@09:25:04 || new", "a new line after the copy: stamped")
end)

H.test("a window cleared on its own stamps again at the next screen frame", function()
	local w, chat = On()
	chat:Clear()
	chat:AddMessage("x")
	H.eq(chat:Last(), "x", "in the same frame as the clear: taken as a copy")
	w:runTimers()
	chat:AddMessage("y")
	H.eq(chat:Last(), "26-11-14@09:25:04 || y", "the next frame: stamped")
end)

H.test("a calendar that is not ready gives no stamp, not a wrong date", function()
	local _, chat = World({ chatStamps = true }, nil,
		{ year = 2026, month = 0, monthDay = 0, hour = 0, minute = 0 })
	chat:AddMessage("a")
	H.eq(chat:Last(), "a", "zeroed: no stamp")
	_, chat = World({ chatStamps = true }, nil,
		{ year = 2026, month = 11, monthDay = 15, hour = 9, minute = 25 })
	chat:AddMessage("b")
	H.eq(chat:Last(), "b", "a day off (19 hours from UTC): no stamp")
	_, chat = World({ chatStamps = true }, nil,
		{ year = 2026, month = 11, monthDay = 14, hour = 8, minute = 85 })
	chat:AddMessage("c")
	H.eq(chat:Last(), "c", "minute 85: no stamp")
end)

H.test("a history with no place for its newest line: no stamp", function()
	local _, chat = On()
	chat.historyBuffer.CalculateElementIndex = nil
	chat:AddMessage("a")
	H.eq(chat:Last(), "a", "no guess")
end)

--------------------------------------------------------------------------------
-- The three shapes (TICK-0155, D-039)
--------------------------------------------------------------------------------

H.test("the long shape is the default", function()
	local w, chat = On()
	H.eq(w.env.HUDiniDB.chatStampShape, "long", "the default")
	chat:AddMessage("hello")
	H.eq(chat:Last(), "26-11-14@09:25:04 || hello", "long")
end)

H.test("each shape for a fixed time", function()
	for shape, want in pairs({
		long = "26-11-14@09:25:04 || hello",
		short = "[09:25] hello",
		dated = "11/14/26 [09:25] hello",
		odd = "26-11-14@09:25:04 || hello", -- an unknown shape: the long one
	}) do
		local _, chat = World({ chatStamps = true, chatStampShape = shape })
		chat:AddMessage("hello")
		H.eq(chat:Last(), want, shape)
	end
end)

H.test("the dated shape on a leap day and the day after: month, day, year", function()
	local _, chat = World({ chatStamps = true, chatStampShape = "dated" }, 1709251199,
		{ year = 2024, month = 2, monthDay = 29, hour = 23, minute = 59 })
	chat:AddMessage("tick")
	H.eq(chat:Last(), "02/29/24 [23:59] tick", "the leap day")
	_, chat = World({ chatStamps = true, chatStampShape = "dated" }, 1709251199,
		{ year = 2024, month = 3, monthDay = 1, hour = 0, minute = 59 })
	chat:AddMessage("tick")
	H.eq(chat:Last(), "03/01/24 [00:59] tick", "the realm's day, after the leap day")
end)

H.test("no second stamp for each shape, whatever the shape is now", function()
	for _, first in ipairs({ "long", "short", "dated" }) do
		for _, now in ipairs({ "long", "short", "dated" }) do
			local w, chat = World({ chatStamps = true, chatStampShape = first })
			chat:AddMessage("hi")
			local stamped = chat:Last()
			H.ok(stamped ~= "hi", first .. ": stamped")
			w.env.HUDiniDB.chatStampShape = now
			w.serverTime = w.serverTime + 300
			w.env.ChatFrame3:AddMessage(stamped)
			H.eq(w.env.ChatFrame3:Last(), stamped, first .. " then " .. now .. ": one stamp")
		end
	end
end)

H.test("the game's own stamp with the short shape: one stamp, realm time", function()
	local w, chat = World({ chatStamps = true, chatStampShape = "short" })
	w.gameStamps = "%H:%M "
	chat:AddMessage("15:25 hi")
	H.eq(chat:Last(), "[09:25] hi", "the game's PC-time stamp replaced by the realm's")
end)

H.test("a hand-set bracketed game stamp with the short shape: one stamp, realm time", function()
	-- Not in the game's options: /console showTimestamps or another addon.
	local w, chat = World({ chatStamps = true, chatStampShape = "short" })
	w.gameStamps = "[%H:%M] "
	chat:AddMessage("[15:25] hi")
	H.eq(chat:Last(), "[09:25] hi", "the game's PC-time stamp replaced by the realm's")
end)

H.test("a reused whisper window keeps a short stamp as it was", function()
	local w, chat = World({ chatStamps = true, chatStampShape = "short" })
	chat:AddMessage("hi", 1, 1, 1, "Bob")
	local open = w.env.FCF_OpenTemporaryWindow
	local f = open("WHISPER", "Bob", chat, true)
	f.inUse = false
	w.serverTime = w.serverTime + 300
	f = open("WHISPER", "Bob", chat, true)
	H.eq(f:Line(1), "[09:25] hi", "one stamp, the first time")
	f:AddMessage("new", 1, 1, 1, "Bob")
	H.eq(f:Last(), "[09:30] new", "a new line: the new time")
end)
