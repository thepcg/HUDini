# HUDini

**Keep your spells close. Keep Azeroth in view.**

> An adventurer should be able to admire the view without losing track of the creature trying to eat them. I believe we can arrange both.
>
> Archmage Khadgar

HUDini gathers your spells, health, power, and target information into a compact display near the center of your screen. The main HUD can fade when things are quiet and return immediately when your chosen conditions call for it.

Built specifically for **World of Warcraft: Forever**, with support for all nine classes from the beginning of their adventures. **No other addon required. Not intended for Retail.**

Whether you have one well-traveled main or a character of every class awaiting attention, the aim is the same: useful information where you can see it, with room left for the world around it.

## A few useful enchantments

### Your actions, together

Keep spells, items, and supported macros in a compact icon grid, ordered by key binding or action-bar position. Cooldowns, activation glows, range cues, and recognized buff timers help you read the situation at a glance when the game supplies that information.

Choose the arrangement that suits your hands:

- **Rows: Action Bars 1-3** gives each of those bars its own row, including when the original bars are hidden. Empty slots are skipped.
- **Packed: selected bars** gathers actions from your chosen bars, up to all eight, into wrapping rows.

**HUD icons display your actions; they do not cast them.** Keep using your usual key bindings or the game's action buttons.

### Your condition, and theirs

Health, power, and casts sit close to the action icons. Your target has its own health, power, and cast display. Casts share the power-bar space, keeping the arrangement compact.

There is room for the details that matter to your class: combo points, a chosen buff's stacks, druid mana while shapeshifted, or active shaman totems. An optional experience bar tracks progress, rested experience, XP per hour, and an estimated time to the next level.

Health bars can also serve as unit controls: **left-click to target that unit, right-click for its menu**.

### A timely reminder

HUDini can remind you when a learned long-duration buff is missing, when a friendly player you target could use one of your buffs outside combat, or when your equipped fishing pole has no bait.

Classes with the appropriate abilities can also receive:

- An outline on an interruptible target cast when a configured interrupt is ready.
- A power-bar tint for a harmful effect you have a configured spell to remove.
- Icons for enemy buffs that match your removal ability.
- A reminder when your chosen combat buff is missing.

These alerts depend on the spells you know and the information the client provides. Choose the abilities they use on the **Your class** page.

> A useful reminder should arrive before the mistake becomes an anecdote.

### News of your travels

The optional **feed** collects recent loot, money gains, experience, quest turn-ins, discoveries, and other selected events into short messages. It can also note dwindling bag space and worn equipment.

Choose which events deserve a mention, how much detail to include, and whether larger announcements should celebrate notable gains. Optional hints add quest-objective progress and item-level comparisons for eligible equipment.

Message timers can pause during combat, giving you time to read afterward. New messages still arrive, and the message limit still applies. The feed is a passing account, not a permanent ledger.

### Room to breathe

Keep the original game displays you like. Hide the ones HUDini replaces. You can also make bag buttons, menu buttons, and the minimap appear only on hover, or temporarily move and resize supported game windows.

These conveniences are **off until you choose them**. HUDini does not hide the game's action bars for you.

## Install

1. Place the `HUDini` folder inside WoW Forever's AddOns directory:

   ```text
   _forever_\Interface\AddOns\HUDini
   ```

2. Start the game. If it was running when you added the folder, close and restart it.
3. Log in and type `/hud version` to confirm HUDini loaded.

The setup guide opens on your first login with the addon enabled.

## Your first few minutes

> You were promised a setup wizard. The makers of this addon appear to have taken that rather literally.

**HUDini Setup** introduces the display and walks you through six configuration steps. Choose the information you want, settle the HUD and feed into comfortable positions, and decide how much of the original interface should remain in view.

Choices marked **(default)** provide a starting point. **Changes take effect as you make them.** Selecting **Finish for now**, or pressing Escape, keeps your choices and locks the displays in place.

Once setup closes, the main HUD follows your visibility settings. It can remain visible for combat, a living target you can attack, missing health, unsettled power, or a missing tracked buff or weapon enhancement. Enabled reminders such as missing fishing bait can also keep it around.

Prefer steady company? Choose **Always visible** to keep the main HUD shown whenever it has supported actions to display. Target information and the feed have their own visibility rules.

| To do this | Use this |
|---|---|
| Open all settings | `/hud` |
| Run setup again with your current choices | `/hud setup` |
| Find out why the main HUD is visible or hidden | `/hud why` |
| Move the HUD and feed | `/hud unlock`, drag their highlighted boxes, then `/hud lock` |
| See a demonstration with sample information | `/hud test`; run it again to finish |
| Find a command | `/hud help` |

The HUD stays visible while Options is open so you can see your adjustments. Each class remembers its own HUD position. Combat ends the sample demonstration.

You can also use the minimap button: **left-click for Options, right-click for setup**.

## A quieter screen, at your own pace

Start with **Options > AddOns > HUDini > Game frames**. Choose which original frames to hide, which controls should appear on hover, and whether supported game windows should be movable.

Hiding the original player, target, or cast frame requires the corresponding HUDini bars. Hiding the original experience bar is independent, so enable HUDini's experience bar separately if you want a replacement.

### Hiding the original action bars

If you cast with key bindings, you may want to hide some of the game's action bars yourself:

1. Open the game's **Edit Mode**.
2. Select **Action Bar 2** or **Action Bar 3**.
3. Set **Bar Visible** to **Hidden**.

Their key bindings still work, and the bars appear while you drag spells onto them. Action Bar 1 cannot be hidden this way.

With HUDini's default **Rows: Action Bars 1-3** layout, those bars continue supplying their actions to the HUD even when hidden.

In **Packed: selected bars**, automatic bar selection follows which bars are visible. If you want a hidden bar included, turn off automatic selection and select that bar manually on the **Icons** page.

### Dismissing the gryphons

In the game's **Edit Mode**, select each **End Cap** at the ends of Action Bar 1 and check **Hidden**. This also applies to the wyvern decorations.

> The decorative creatures answer to Edit Mode. I respect an established chain of command, particularly when it saves me negotiating with a gryphon.

## Make it yours

Open settings with `/hud` or through **Options > AddOns > HUDini**. Common choices come first; more detailed controls sit under **Advanced** where available.

| Page | What you can arrange |
|---|---|
| **HUDini** | Presets, setup, the minimap button, About, position, scale, visibility conditions, fade duration, and the guide's flair. |
| **Icons** | Rows or packed layout, sort order, size, spacing, growth direction, icon details, and which action bars to read. |
| **Bars** | Player and target information, health-bar clicks, class resources, fonts, textures, and dimensions. |
| **Colors** | The colors of your bars, target reactions, and target casts. |
| **Alerts** | Class ability alerts and other reminders. |
| **Your class** | Abilities used for interrupts, dispels, enemy-buff removal, and combat-buff reminders; the resource to track; and learned buffs. Choices are shared by characters of that class. |
| **Feed** | Event types, larger announcements, optional hints, appearance, message timing, and filters. |
| **Game frames** | Original displays, hover behavior, movable windows, and muting cooldown and range voice lines. |

A grayed-out setting needs another choice enabled, a different layout, or a suitable class ability. Its tooltip explains the requirement. The page's **Defaults** button restores that page's settings.

### Three starting arrangements

Presets change five choices together. They leave your other settings, including position, scale, colors, and visibility conditions, as you arranged them.

| Preset | Experience bar | Target power | Feed | Quest-progress hints | Item-level hints |
|---|---|---|---|---|---|
| **Minimal** | Off | Off | Off | Off | Off |
| **Standard** | On | On | On | Off | Off |
| **Leveling** | On | On | On | On | On |

**Custom** appears when your combination differs from these presets.

### How much wizard would you like?

Under **HUDini > Advanced > Guide's flair**, choose the voice that accompanies the explanations:

- **Light:** Essential instructions, briefly delivered.
- **Modest:** A friendly guide with an occasional dry remark.
- **Full:** An archmage who has found agreeable company and sees no reason to waste it.

The features behave the same at every level. Only the commentary becomes more sociable.

## When you want things back

**For one setting or page:** change the option directly, or use that page's **Defaults** button.

**For the choices covered by setup:** run `/hud setup` again and select the defaults you want. This changes those choices without resetting unrelated settings or moving the HUD back to its original position.

**For shared settings:** type `/hud reset settings`, read the confirmation, then use `/hud reset yes` within 30 seconds. Class positions, class spell choices, learned buffs, histories, custom spell-to-buff pairs, and the feed's item ignore list are preserved.

**For the current class:** type `/hud reset class`, then confirm with `/hud reset yes`. This clears that class's saved HUD position, spell choices, learned buffs, and learned stacking buffs. It affects characters sharing that class.

Use `/hud reset no` to cancel either pending reset. `/hud reset` alone explains the choices without changing anything.

**To disable HUDini:** open **AddOns** on the character-selection screen and uncheck it. The original game frames are available again. Any changes you made yourself in the game's Edit Mode remain yours to reverse there.

## Chat commands

`/hud` opens Options. `/hudini` works as an alternative prefix. Use `/hud help` for the command list or `/hud help <command>` for an explanation.

| Command | Purpose |
|---|---|
| `/hud options` | Open Options. |
| `/hud setup` | Run the setup guide again. |
| `/hud why` | Explain the main HUD's current visibility. |
| `/hud unlock` and `/hud lock` | Position the HUD and feed, then secure them. |
| `/hud test` | Start or stop the sample demonstration. |
| `/hud buffs` | List learned buffs. Add `forget Name` to remove one, or `clear` to clear the list. Eligible buffs can be learned again. |
| `/hud auramap` | List custom spell-to-buff pairs. Add `Spell = Buff` to create a pair, or `Spell =` to remove that spell's custom pairs. |
| `/hud feedignore` | List ignored items. Add an item link or ID to toggle it, or `clear` to empty the list. |
| `/hud feedsession` | Show recorded feed session totals. Add `reset` to begin a fresh session. |
| `/hud xp reset` | Start a fresh experience-rate session. |
| `/hud version` | Show the installed version and where to find credits. |
| `/hud debug` | List diagnostic tools: `list`, `api`, `aura`, `modules`, `ids`, and `weapon`. |
| `/hud reset` | Explain the settings and class reset choices. |

HUDini also provides `/rl` as a shortcut for `/reload` when another addon has not already claimed it. Older setting commands, such as `/hud size`, direct you to the appropriate Options page.

## Why HUDini exists

Playing a roster across all nine classes meant tending a growing collection of addons: unit frames, cast bars, an experience display, window movers, and minimap controls. Keeping that collection working on WoW Forever began to take time away from actually playing it.

HUDini began with a simpler wish: gather the spells in keybind order near the center of the screen, so the eyes could stay closer to the adventure. The bars, reminders, and feed grew around that idea.

Its guiding habits remain straightforward:

- Let the main HUD step aside when its chosen conditions allow, and bring it back immediately when they call for it.
- Respect the game's combat restrictions; changes to protected elements wait when necessary.
- Use information the game makes available. Omit unavailable details rather than inventing an answer.
- Make the current visibility decision explainable with `/hud why`.

For a more deliberately unguided journey, **Unguided** is a separate addon that removes the quest list and minimap hints so reading the quests matters. Its restrictions are always on. HUDini's conveniences remain choices you make.

## For curious minds

The grid, visibility rules, bars, Forever-specific discoveries, and a map of the code live in [How it works](docs/HOW-IT-WORKS.md).

**Planned:** place the main HUD through the game's own Edit Mode. For now, use setup or `/hud unlock` to position it.

## Credits and development

- **SenseiClassResourceBar:** inspiration for the resource bar's passthrough approach.
- **Fira Sans:** The Mozilla Foundation and Telefonica S.A.
- **Fira Code:** The Fira Code Project Authors.

Both font families are distributed under the **SIL Open Font License 1.1**.

HUDini is an ongoing learning project developed with substantial assistance from several AI models. Its guide dialogue uses an unofficial fictional portrayal of Archmage Khadgar. This is a fan addon, not affiliated with or endorsed by Blizzard Entertainment.

> Now, enjoy the view. We went to some trouble to clear it.
