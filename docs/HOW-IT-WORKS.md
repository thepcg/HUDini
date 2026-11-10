# How HUDini works

The engineering notes for HUDini: how each part works, which 12.x and Forever
quirks shaped it, and where to look in the code. The player guide is the
[README](../README.md).

## The grid

`Core.lua` reads each action slot with `GetActionInfo`, resolves macros with
`GetMacroSpell` (or `GetMacroItem`), and sorts. Spells and items both count,
so food and water show up too, with their stack count.

Keybind order ranks the modifier first (none, Shift, Ctrl, Alt), then the key
(1-9, 0, -, =, F keys, mouse buttons, letters).

The icon layout **Rows: Action Bars 1-3** mirrors Action Bars 1-3: Action Bar 1 on row 1, Action Bar 2
on row 2, Action Bar 3 on row 3. An action bar never wraps, and an empty one
keeps its row, so Action Bar 3 never slides up into Action Bar 2's place. A
spell on two action bars shows on both rows.

The icon layout **Packed: selected bars** packs one stream from any of the eight bars and breaks a
row every `wrap` icons, up to `count`. A spell on two bars shows once, from
the lower bar. `bars auto` reads only the bars on screen; `bars 1234` picks
them by hand. Action Bar 1 is always read.

| Bar | Slots | Binding |
|---|---|---|
| Action Bar 1 | 1-12, or the page the game shows: 13-72 (Shift pages), 73-120 (Druid forms, Stealth) | ACTIONBUTTON |
| Action Bar 2 | 61-72 | MULTIACTIONBAR1BUTTON |
| Action Bar 3 | 49-60 | MULTIACTIONBAR2BUTTON |
| Action Bar 4 | 25-36 | MULTIACTIONBAR3BUTTON |
| Action Bar 5 | 37-48 | MULTIACTIONBAR4BUTTON |
| Action Bar 6 | 145-156 | MULTIACTIONBAR5BUTTON |
| Action Bar 7 | 157-168 | MULTIACTIONBAR6BUTTON |
| Action Bar 8 | 169-180 | MULTIACTIONBAR7BUTTON |

The grid is rebuilt out of combat only. Action bars do not change mid-fight,
and button registration should not run under the combat lockdown.

## Acting like a real action button

Each icon is a `CheckButton`, handed to `C_ActionBar.RegisterActionUIButton`
where the client has it. That lets the game drive the checked state and count
the icon for Assisted Combat.

| Behavior | How |
|---|---|
| Cooldown and GCD | `C_ActionBar.GetActionCooldownDuration(slot)` into `Cooldown:SetCooldownFromDurationObject` |
| Proc glow | `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` / `_HIDE`, matched by spell ID |
| "Press this next" | `C_AssistedCombat.GetNextCastSpell()`, asked every 0.15 s |
| Dim when unusable | `C_ActionBar.IsUsableAction(slot)` |
| Red when out of range | `C_ActionBar.IsActionInRange(slot)` |

Cooldown numbers are secret in combat. A `DurationObject` is the sealed box
the game hands out instead, and the Cooldown widget is the only thing that
opens it. The code never reads a number out of it.

## Buff time on icons

`Auras.lua` counts a buff down on the icon that gives it. It matches by name,
so every rank of a self-buff lights its icon, and Forever's spell IDs never
matter. An item uses the spell it casts: food casts "Food", water casts
"Drink". Buffs with another name are paired in `Classes.lua` and the class
files (Food also shows Well Fed; Arcane Intellect pairs with Arcane
Brilliance). `/hud auramap` adds your own. The time goes through
`C_UnitAuras.GetAuraDuration` into a second Cooldown on the icon, so it keeps
ticking when auras turn secret in combat.

## When the HUD shows

With "Hide when idle" on, the icons and your own bars show while any of these
is true:

- you are in combat
- your target is alive and you can attack it
- your health is below full
- your power is not at rest: mana or energy below full, or any rage left
- a tracked buff is off (5 minutes or more, or with no end, like a paladin
  aura). HUDini learns these per class the first time it sees the
  buff on you, from a spell on the HUD or any timed buff you cast on
  yourself (on a bar it does not read, or on no bar). `/hud buffs` lists them
- a weapon you hold has no weapon buff, once you know one (like a Shaman's
  Rockbiter Weapon). A shield, or anything with "Fishing" in its name, needs
  none
- you hold a fishing pole with no bait on it

Showing is instant. Hiding fades over 3 seconds (the "Fade out" slider; 0
hides at once). A target's bars show whenever you have a target, friendly
ones included. An unlocked HUD always shows, or you could never drag it.

## The bar stack

Above the grid, from the top down:

1. **target health**: level, name and title. Red hostile, yellow neutral,
   green friendly, white when someone else tagged it
2. **target power**, as tall as your power bar, with the target's cast
   see-through on top: yellow if you can interrupt it, gray if not. With
   Target power off, the slot stays and shows only the cast
3. **your health**, with the damage trail
4. **your power**, whichever you use now, with your cast bar see-through on top
5. **class resource**, if your class file has one
6. **experience**, hidden at max level

Health and power work by **passthrough**. `UnitHealth` and `UnitPower` can
return secret values, and `StatusBar:SetValue` is built to take them, so the
number goes straight from the game into the bar. The addon never reads it.

## Cast bars without reading anything

Three secrets sit inside a cast bar, and each one has its own door:

| Secret | Door |
|---|---|
| cast progress | `UnitCastingDuration(unit)` returns a `DurationObject`, fed to `StatusBar:SetTimerDuration`. The bar animates itself. |
| spell name | `FontString:SetText` accepts secret strings. |
| `notInterruptible` | `Region:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)` |

You may not test a secret boolean, so the interruptible color cannot be an
`if`. Instead the target cast bar is two bars stacked, gray under yellow, on
the same timer. `SetAlphaFromBoolean` shows one and hides the other inside
the game.

HUDini never tests whether a cast is running either. `TryTimer` calls
`SetTimerDuration` inside a `pcall`. If the call takes, there is a cast; if it
throws, there is not. A `pcall` result is a plain boolean, safe to branch on.

## The resource bar

Read the aura, pass the stack count straight into the bar:

```lua
local data = C_UnitAuras.GetAuraDataBySpellName("player", resource.aura, "HELPFUL")
bar:SetMinMaxValues(0, resource.max)
bar:SetValue(data.applications)  -- passthrough: never read, compared or defaulted
```

`data` is a plain table, so testing it is safe. `applications` may be secret,
so it goes straight into the bar. Credit to `SenseiClassResourceBar` for the
approach. A class file can also name a power type, like combo points.

## Classes

What differs between classes is data, not logic. `Classes.lua` is the
registry, and each file under `Classes/` registers one set of spell names.
Names, not IDs: one name covers every rank.

| Field | Used for |
|---|---|
| `interrupt` | the interrupt outline on the target cast bar |
| `dispel` | one spell per debuff type; the power bar takes the color of one you can remove |
| `purge` | a spell that takes magic buffs, or `{ spell, stealable = true }` |
| `keepUp` | the combat buffs: in a fight with none on, the first one you know shows by the health bar |
| `resource` | `{ aura = name, max = pips }` or a power type; nil for no resource bar |
| `auraMap` | extra buff names for an icon |
| `weaponBuff` | weapon buffs like Rockbiter Weapon |

Your own choices (the Your class page of the options: interrupt, dispels,
purge, combat buff, class resource) and the grid position are saved per
class in `HUDiniDB.classes`, and win over the class file.

So far only Mage and Shaman have class files. Every other class gets the grid,
the bars and the bait call-out, and no class alerts. To add one, copy
`Classes/Mage.lua`, change the class token and the spell names, and list the
file in `HUDini.toc`.

## Learning from the code, or borrowing it

Every file opens with a block comment that says what it does and how. The
comments explain why, not just what. If you want one piece for your own
addon, here is where to look.

| File | What it does |
|---|---|
| `Core.lua` | defaults, the grid, when to show, Blizzard frames, mouseover, slash commands |
| `Classes.lua`, `Classes/*.lua` | per-class spell data and per-class saved choices |
| `Bars.lua` | health, power, cast and resource bars; textures, fonts, colors |
| `XP.lua` | the XP bar and XP per hour |
| `Alerts.lua` | interrupt outline, an icon when a combat buff is off, dispel tint, purgeable buffs, bait, a red icon when a tracked buff is off, a friendly target missing a tracked buff |
| `Auras.lua` | buff time on icons, tracked buffs, weapon buffs and bait by tooltip |
| `Clicks.lua` | click the health bars to target, right-click for the unit menu |
| `Feed.lua` | the feed box: fading lines, the highlight, the session totals |
| `FeedLoot.lua` | feed lines from chat: loot, currency, crafts, reputation, skills |
| `FeedGains.lua` | feed lines for XP, money, quest turn-ins, levels, discoveries |
| `FeedWatch.lua` | feed lines for bags, gear, merchants, spells, collections, quest progress |
| `Mover.lua` | drag and scale Blizzard's windows; off by default, adds its hooks only once turned on |
| `Options.lua` | the Options -> AddOns panel |

Patterns worth taking:

- **Secret-safe values**: `Plain()` in `Core.lua`. One small function that turns
  a secret into `nil`, so no comparison can throw.
- **Passthrough bars**: `Fill()` in `Bars.lua`. Hand a possibly secret number
  to `StatusBar:SetValue` inside a `pcall`, and never touch it.
- **Cast bars with no reads**: `CreateCastSet`, `TryTimer` and `RefreshCast` in
  `Bars.lua`. Two stacked bars and `SetAlphaFromBoolean`.
- **"Has it stopped changing?"**: the `SETTLE` block in `Core.lua`. When a value
  is secret, watch its events instead; no change for 6 seconds means at rest.
- **Reading a weapon buff from the tooltip**: `TooltipLines` and
  `HandBuffed` in `Auras.lua`, for clients that answer "no enchant" wrongly.
- **Hiding a protected Blizzard frame**: `ApplyBlizzardFrames` in `Core.lua`.
  An attribute driver hides it, and waits for combat to end. (A frame that
  shows itself again, like the objective tracker, needs parking instead:
  see Unguided.)
- **Mouseover without OnEnter**: `UpdateMouseover` in `Core.lua`. 12.x forbids
  script handlers on protected frames, so a 0.1 s ticker asks `IsMouseOver`
  and sets alpha, which is not protected.
- **Secure click buttons over a frame that moves in combat**: `Clicks.lua`.
  The button hangs off UIParent at its bar's spot, never anchored to the
  bar, so the combat lock never spreads into the HUD. A state driver shows
  and hides it mid fight.
- **Moving Blizzard windows with hooks only**: all of `Mover.lua`. Copy the file,
  change the one `HUDiniDB.moveWindows` check in `Enabled()`, and call
  `ns.ApplyMover()` each time your setting changes. Without that call, turning
  it on takes effect only after a /reload.
- **A table-driven slash command**: the `COMMANDS` table at the end of
  `Core.lua`. One row per command gives you the parser and `/hud help` for
  free. `Toggle`, `Number` and `MediaPick` build most rows.
- **A clean Settings panel**: the building blocks at the top of `Options.lua`
  (`Checkbox`, `Slider`, `Dropdown`, `Proxy`, `Under`, `GreyUnless`,
  `CheckboxWithColor`). They wrap the 12.x Settings API for any addon that
  keeps its settings in one saved table, and they keep Blizzard's settings
  search free of taint: no `AddShownPredicate`, no `SetParentInitializer`.
- **Defaults that grow**: `ns.defaults` and `FillDefaults` in `Core.lua`. A new
  setting gets its default without touching the ones you changed.

All files share one table, `ns` (the second value from `...`), so a borrowed
piece may call a helper from another file. Search for the name and copy that
too.

## Forever and 12.x notes

- Action slots and key bindings are plain values. Nothing there is secret.
- Forever returns your own health and power as secrets even out of combat,
  which is why "at rest" watches events (see the `SETTLE` block in `Core.lua`).
- Forever answers "no enchant" for a weapon buff or bait that is on, and the
  buff is not on you either. Only the weapon's tooltip shows it
  ("Rockbiter 3 (53 min)"). A line with the buff's first word counts as a
  weapon buff; a line ending in a time, like "(10 min)", counts as bait.
- `COMBAT_LOG_EVENT_UNFILTERED` errors on registration in 12.x, so HUDini uses
  no combat log.
- The version is typed only in `## Version:` of `HUDini.toc`; `Core.lua` reads
  it into `ns.VERSION`, and `/hud version` prints it, so a test shows which
  build is running. The game reads the .toc only at start, so a new version
  needs a full restart, not `/reload`.

### A dead end, kept as a warning

The first resource bar went through 12.1's `AuraContainer` and
`AuraButton:SetApplicationBar`. It fails, in two steps:

1. `SetApplicationBar` rejects any bar that is not a descendant of the
   AuraButton: `Blizzard_AuraContainerUtil.lua:279: bad object ... (must be a
   direct child or indirect descendent of owner)`.
2. You cannot move one in either:
   `SetParent(): Reparenting disallowed as child object would inherit forbidden
   aspects: UntrustedScriptExecution, UntrustedLayoutScriptExecution,
   AlwaysPropagateInput, ScriptedInput`.

An addon frame cannot become part of a Blizzard AuraButton. `AuraContainer`
is for auras the game draws, not for feeding your own widgets. Use the plain
aura read instead.
