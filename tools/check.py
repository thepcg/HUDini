"""HUDini check gate. Run it through tools/check.ps1.

Checks, in order:
1. Every .lua file parses as Lua 5.1 (the WoW client's Lua).
2. Every file the .toc lists exists, and every .lua file is listed in the .toc.
3. Every test in tools/tests/test_*.lua passes (see tools/tests/harness.lua).
4. luacheck finds no warning in any .lua file (options: tools/luacheck_wow.lua).
   Mostly it finds a misspelled or unknown global, and an unused local.
5. No "Do not use" word of framework/glossary.md in player text: the Lua
   strings and the player docs (rules and allow-list: tools/glossary_check.py).
6. No player text in a Lua string outside Locales/enUS.lua, and every key
   the code asks for has a text there (rules: tools/locale_check.py).

Prints "all passed" and exits 0 only when every check passes.
Judge a run by the "all passed" line, not only by the exit code.
"""
import importlib.util
import pathlib
import sys

import lupa.lua51 as lua51

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP = {"tools", "docs", "tickets", "decisions", "framework"}  # and every folder that starts with "."

lua = lua51.LuaRuntime()
parse = lua.eval("function(s, n) local f, e = loadstring(s, n) return e end")

failures = []

lua_files = sorted(
    p for p in ROOT.rglob("*.lua")
    if not SKIP.intersection(p.relative_to(ROOT).parts)
    and not any(x.startswith(".") for x in p.relative_to(ROOT).parts)
)
for p in lua_files:
    rel = p.relative_to(ROOT).as_posix()
    err = parse(p.read_text(encoding="utf-8"), "@" + rel)
    if err:
        failures.append("syntax: " + str(err))

tocs = sorted(ROOT.glob("*.toc"))
if not tocs:
    failures.append("toc: no .toc file in " + str(ROOT))
listed = set()
for toc in tocs:
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        rel = line.replace("\\", "/")
        listed.add(rel)
        if not (ROOT / rel).is_file():
            failures.append("toc: %s lists %s, which does not exist" % (toc.name, rel))
for p in lua_files:
    rel = p.relative_to(ROOT).as_posix()
    if rel not in listed:
        failures.append("toc: %s is not listed in any .toc" % rel)

# Check 3: the test harness. Each tools/tests/test_*.lua runs in a fresh
# Lua 5.1 state, with tools/tests/harness.lua loaded first as H.
TESTS = ROOT / "tools" / "tests"
test_files = sorted(TESTS.glob("test_*.lua"))
test_count = 0
if not test_files:
    failures.append("test: no tools/tests/test_*.lua file found")
for t in test_files:
    state = lua51.LuaRuntime()
    state.globals().H_ROOT = ROOT.as_posix()
    run = state.eval(
        "function(h, hn, s, sn)"
        " local f, e = loadstring(h, hn) if not f then return e end"
        " local ok, err = pcall(f) if not ok then return tostring(err) end"
        " f, e = loadstring(s, sn) if not f then return e end"
        " ok, err = pcall(f) if not ok then return tostring(err) end"
        " end"
    )
    err = run(
        (TESTS / "harness.lua").read_text(encoding="utf-8"), "@tools/tests/harness.lua",
        t.read_text(encoding="utf-8"), "@tools/tests/" + t.name,
    )
    if err:
        failures.append("test: %s did not run: %s" % (t.name, err))
        continue
    results = state.globals().H.results
    if len(results) == 0:
        failures.append("test: %s has no tests" % t.name)
    for i in range(1, len(results) + 1):
        r = results[i]
        test_count += 1
        if not r.ok:
            failures.append("test: %s: %s: %s" % (t.name, r.name, r.err))

# Check 4: luacheck v1.2.0, with the options in tools/luacheck_wow.lua, on
# every addon .lua file. Pure Lua from the clone in ..\.tools\luacheck, run
# in a fresh Lua 5.1 state with no C modules. Any warning fails.
LUACHECK = ROOT.parent / ".tools" / "luacheck" / "src"
LINT_SETUP = r"""function(cfg, cfgname, src)
	package.path = src .. "/?.lua;" .. src .. "/?/init.lua"
	package.cpath = ""
	local f, e = loadstring(cfg, cfgname)
	if not f then return nil, e end
	local ok, opts = pcall(f)
	if not ok or type(opts) ~= "table" then return nil, cfgname:sub(2) .. " did not return a table: " .. tostring(opts) end
	local okL, luacheck = pcall(require, "luacheck")
	if not okL then return nil, tostring(luacheck) end
	if luacheck._VERSION ~= "1.2.0" then
		return nil, "found luacheck " .. tostring(luacheck._VERSION) .. ", the gate needs 1.2.0"
	end
	-- files = { ["Core.lua"] = { ignore = {...} } }: more ignores for one file.
	local files = opts.files or {}
	opts.files = nil
	local names = {}
	for name in pairs(files) do names[#names + 1] = name end
	local function lint(rel, text)
		local o = {}
		for k, v in pairs(opts) do o[k] = v end
		if files[rel] then
			o.ignore = {}
			for _, x in ipairs(opts.ignore or {}) do o.ignore[#o.ignore + 1] = x end
			for _, x in ipairs(files[rel].ignore or {}) do o.ignore[#o.ignore + 1] = x end
		end
		local okC, report = pcall(luacheck.check_strings, { text }, o)
		if not okC then return rel .. ": luacheck stopped: " .. tostring(report) end
		local r = report[1]
		if r.fatal then return rel .. ": luacheck could not check it (" .. tostring(r.fatal) .. ")" end
		local out = {}
		for _, ev in ipairs(r) do
			out[#out + 1] = ("%s:%d:%d: (W%s) %s"):format(rel, ev.line, ev.column, ev.code, luacheck.get_message(ev))
		end
		return table.concat(out, "\n")
	end
	return lint, table.concat(names, "\n")
end"""
lint_warnings = 0
if not (LUACHECK / "luacheck" / "init.lua").is_file():
    failures.append("luacheck: %s is missing; see tools/check.ps1" % LUACHECK)
else:
    state = lua51.LuaRuntime()
    cfg = ROOT / "tools" / "luacheck_wow.lua"
    lint, info = state.eval(LINT_SETUP)(
        cfg.read_text(encoding="utf-8"), "@tools/luacheck_wow.lua", LUACHECK.as_posix())
    if lint is None:
        failures.append("luacheck: " + str(info))
    else:
        rels = {p.relative_to(ROOT).as_posix() for p in lua_files}
        for name in filter(None, str(info).split("\n")):
            if name not in rels:
                failures.append("luacheck: tools/luacheck_wow.lua has ignores for %s, "
                                "which is not an addon .lua file" % name)
        for p in lua_files:
            rel = p.relative_to(ROOT).as_posix()
            for line in filter(None, str(lint(rel, p.read_text(encoding="utf-8"))).split("\n")):
                lint_warnings += 1
                failures.append("luacheck: " + line)

# Check 5: the glossary. -I keeps tools/ off sys.path, so load it by path.
spec = importlib.util.spec_from_file_location("glossary_check", ROOT / "tools" / "glossary_check.py")
glossary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(glossary)
glossary_failures, glossary_words, glossary_review = glossary.run(ROOT)
failures += glossary_failures

# Check 6: the locale. It reads the Lua strings with the glossary's reader.
spec = importlib.util.spec_from_file_location("locale_check", ROOT / "tools" / "locale_check.py")
locale = importlib.util.module_from_spec(spec)
spec.loader.exec_module(locale)
locale_failures, locale_keys = locale.run(ROOT, glossary, lua51)
failures += locale_failures

print("checked %d Lua files and %d toc file(s)" % (len(lua_files), len(tocs)))
print("ran %d test(s) in %d file(s)" % (test_count, len(test_files)))
print("luacheck: %d warning(s)" % lint_warnings)
print("glossary: %d banned word(s) scanned, %d hit(s); left to review: %s"
      % (len(glossary_words), len(glossary_failures), ", ".join(glossary_review)))
print("locale: %d key(s) asked for, %d hit(s)" % (locale_keys, len(locale_failures)))
if failures:
    for f in failures:
        print("FAIL " + f)
    print("%d check(s) failed" % len(failures))
    sys.exit(1)
print("all passed")
