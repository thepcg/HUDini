# HUDini check gate: every commit must pass this.
# Usage (from the repo root):  powershell -NoProfile -File tools\check.ps1
# Judge the result by the "all passed" line.
#
# check.py runs: Lua 5.1 syntax, the .toc against the files, the tests in
# tools\tests (see tools\tests\harness.lua for how to write one), luacheck
# (options in tools\luacheck_wow.lua), the glossary check (rules and
# allow-list in tools\glossary_check.py), and the locale check
# (tools\locale_check.py).
#
# Needs a .tools folder next to the repo folder (..\.tools):
#   venv       the shared Python venv with lupa. To make it again:
#                python -m venv ..\.tools\venv
#                ..\.tools\venv\Scripts\python -m pip install lupa
#   luacheck   luacheck v1.2.0 (MIT), pure Lua, run inside lupa. To get it again:
#                git clone --depth 1 --branch v1.2.0 https://github.com/lunarmodules/luacheck ..\.tools\luacheck
#
# -I: isolated mode, so Python loads no module from the current folder.

$py = Join-Path $PSScriptRoot '..\..\.tools\venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    Write-Error "Missing $py. See the comment at the top of tools\check.ps1."
    exit 1
}
& $py -I (Join-Path $PSScriptRoot 'check.py')
exit $LASTEXITCODE
