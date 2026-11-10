-- The whole addon loads in .toc order and logs in with no Lua error.

H.test("a new install loads and logs in", function()
	local w = H.world()
	w:loadAddon()
	H.ok(type(w.env.HUDiniDB) == "table", "HUDiniDB made")
	H.eq(w.ns.VERSION, "9.9.9", "version from the toc")
	H.eq(#w.printed, 0, "lines printed at login")
end)
