# Store page draft

The text for the HUDini project page on CurseForge, and on Wago once it exists. Each block says which field it goes in.

## Fields

| Field | Value |
|---|---|
| Name | HUDini |
| Slug | `hudini` |
| Summary | Your action bars, health, power and target in one small HUD at the center of your screen, hidden whenever nothing needs you. |
| Game flavor | WoW Forever only (`## Interface: 16001`; not for Retail) |
| License | MIT |
| Icon | The HUDini top hat icon |

The summary is the store's own one-line sentence. It must be the same on CurseForge and on Wago: change it here and on both stores at once. It is not the tagline. The tagline ("The Forever HUD: ...") stays at the top of `README.md` and at the top of the Description below. The About window has its own tagline, `about.tagline` in `Locales/enUS.lua`.

## Description

The text between the lines goes in the Description field (CurseForge takes Markdown). It is the README's player part, cut to what a store visitor reads before they install.

---

**The Forever HUD: Spells, health and target in the middle of your sight. Hidden when calm, back the moment it isn't.**

HUDini packs your action bars, in keybind order, into one block at screen center, with health and power bars for you and your target.

It shows when you fight, target an enemy or get hurt, while your power settles, or while a tracked buff, a weapon buff or fishing bait is missing. Otherwise it hides. `/hud why` says why.

Made for **WoW Forever** only, not Retail. All nine classes, from the first level, no other addon needed. If you level one class after another, it was made for you.

- **The icon grid:** every spell, item and macro on Action Bars 1-3, one row per bar, or packed and wrapped from all eight, in keybind order. Each icon shows what the real button shows: its cooldown, its proc glow, its range, and the time left on its buff.
- **Bars:** your health, power and cast, and your target's. A resource bar: combo points for the classes that have them, or a buff's stacks for any class that picks one on the Your class page. An XP bar that shows XP per hour. Click either health bar to target that unit.
- **Alerts, fitted to each class:** every class gets three. When a tracked buff (a buff of 5 minutes or more that HUDini learns as you cast it) runs out, its own icon, edged in red, sits by your health bar. When the friend you target lacks one of your tracked buffs, out of a fight, the same kind of icon sits by their health bar, dimmed while they are out of range. And "No bait." Classes with the right spell also get an outline on a cast you can interrupt, a tint for a debuff you can dispel, your target's buffs you can purge, and a mark when a combat buff (one your class keeps on in a fight) is off. Some come only at a certain level. You can pick your own spell for each of those four on the Your class page.
- **The feed:** one line for each thing you get. It waits out a fight, then fades.
- **A quieter screen:** the game's own action bars stay put. You can hide the game's own player frame, target frame, cast bar and experience bar, show the bag bar, menu and minimap only on hover, or move the bags and other windows. Each one is off until you turn it on.

**First time:** setup opens on its own, once for all your characters, in six short steps. Every page marks a safe choice, so Next is always safe. Finish for now stops there, keeps the choices made so far, and locks the HUD where it is. `/hud unlock` frees the HUD. Type `/hud setup` to run setup again, or `/hud` for the options. The minimap button does both: left-click for the options, right-click for setup.

**Four promises:**

- It hides, and it is back the moment something needs your attention.
- In a fight, the game locks some of its own pieces, so changes wait until the fight ends.
- It never pries at what the game keeps secret. When it cannot know, it says less, and when in doubt, it stays.
- `/hud why` always tells you why it shows or hides.

**Who made it, and how:** Edag made HUDini (The Forever HUD) with the help of several AI models. Edag decided what to build, tested it in the game, and said when it was right. HUDini reads your action bars and key bindings; your health, power, casts, buffs and XP; your weapon's tooltip, to spot a weapon buff or fishing bait; and your target's health, power, casts and buffs. It saves one file, HUDini.lua in your SavedVariables folder: your settings, and the spot, spells and buffs for each class. It never talks to anyone: no messages, no network, no reading other addons. It can hide or fade the game's own frames, and move the game's windows if you turn that on. It never replaces them. HUDini is free under the MIT License: use it, change it, share it. Every line is there to read.

The fonts are Fira Sans and Fira Code, under the SIL Open Font License.

---

## Still open

- **Links:** the source code, bug reports (the issue forms) and Unguided. They wait for the public repo.
- **Screenshots and the GIF:** taken in the game before the first upload.
- **Who made it, and how:** this paragraph is the store's own short form of the README's "How open we are trying to be". It has no line breaks. After the paste, check the CurseForge preview.
