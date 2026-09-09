# Sift

A World of Warcraft addon that tells you what to do with the gear you just
looted: equip it, hold it (and for what), send it to an alt, or get rid of it.
Advice only. It never equips, sells, or moves anything.

Target client: Midnight 12.1 and later. No addon dependencies.

<p align="center">
  <img width="729" height="369" align="center" alt="guide" src="https://github.com/user-attachments/assets/dffb3897-be0c-419d-83ba-d528fc3cb0bf" />
</p>
<p align="center">
  <img width="692" height="801" align="center" alt="main-panel" src="https://github.com/user-attachments/assets/f4447253-307e-4eff-80e8-aa6b873f2114" />
</p>

## What it does

- Reads every equippable rare-or-better item as it lands in your bags.
- Compares it against what you and every alt are wearing, using stat weights
  rather than item level alone: your own Raidbots weights if you paste them
  in, otherwise defaults generated from SimulationCraft's profiles.
- Says "Sim it" when the answer does not survive a reasonable error in the
  weights, instead of guessing. Trinkets always get that answer. Healers,
  who cannot sim on Raidbots, see "Your call" instead.
- Reads gems and empty sockets, and projects upgrades with per-stat growth
  measured from real Season 2 gear.
- Knows the upgrade track ceiling, so a fresh Hero piece that is worse today
  but better after twenty crests gets a hold with the exact cost.
- Thinks in terms of who owns the slot in a month, not who is ahead today:
  a piece your worn gear or something already in your bags will beat once
  upgraded is a dead end, and says so ("Outclassed by Hero Chest in your
  bags"), even when it is ahead right now.
- Knows the catalyst, so a piece that completes your 2-set or 4-set says so.
- Marks the Great Vault's cards while it is open: "Take +4.2%" on the
  pick, "Good", "Sim it" or "Pass" on the rest, and one sentence under
  the window.
- Puts its word beside every Need/Greed roll window: "Need" with the gain,
  "Sim it" when it is close, "Greed" when an alt wants it, "Pass" when it
  is a dead end.
- Puts one line on the item tooltip, one line in chat and a toast at a safe
  moment, and keeps a panel of everything waiting on you. The toast goes
  wherever you place it in Edit Mode, like any other HUD element.
- When it says "Send to Zulkazar", hovering the row compares the item
  against what Zulkazar is wearing, not what you are. Click "Will send"
  and Zulkazar's panel knows it is coming; put it in the warband bank
  and both panels see it there until Zulkazar picks it up. Opening a
  bank puts what to deposit, and what is waiting for you, on the toast.

## Install

From CurseForge or Wago through their apps, or unzip a release into
`World of Warcraft/_retail_/Interface/AddOns/SiftLootAdvisor`. The first login opens
a four-page guide; `/sift guide` brings it back.

To work on it, symlink the checkout to
`World of Warcraft/_retail_/Interface/AddOns/SiftLootAdvisor` instead and `/reload`
after each change.

## Commands

```
/sift                          open the panel
/sift guide                    how Sift works, in four pages
/sift scan                     evaluate everything in your bags
/sift toast                    show your bag verdicts in the toast, to place or test it
/sift weights                  open the stat weights sheet
/sift weights <Pawn string>    import sim weights from the command line
/sift weights clear            drop imported weights
/sift park                     stop send suggestions for this character
/sift options                  open settings
/sift vault                    rank what the Great Vault is offering
/sift vault preview            try the picker on example items before the reset
/sift status                   what Sift knows right now
/sift journal                  what happened around each drop in your last run
/sift feedback                 a report to paste along with what you saw
/sift copy                     the last command's output in a box you can copy from
                               (or add copy to any command: /sift probe copy)
/sift reset confirm            wipe every snapshot, hold and preference
/sift probe                    run the API verification probe (see docs)
/sift currency <track> <id>    set a crest or catalyst currency id by hand
/siftloot ...                  the same commands, for when another addon has claimed /sift
```

Every command with its arguments is written up in `docs/COMMANDS.md`; the
smoke test keeps that file and the command table in step. The last three
are developer commands and stay out of `/sift help` unless debug mode is
on. The settings page lists every command with a button that runs it, and
the panel header opens Settings, the Guide and the Weights sheet.

## Feedback

`/sift feedback` builds a report (versions, status, settings, your last
run from the journal, the recent log) in a box you can copy, with the address to paste it at on the first
line. No account is needed beyond what that address asks for. Add what
happened and what you expected instead; a screenshot of the tooltip or
the panel row helps most.

## Layout

```
Core/       pure Lua 5.1, no game globals: season data, scoring, verdict engine
Adapters/   game APIs in, plain tables out: items, characters, currencies, events
UI/         tooltip line, panel, weights sheet, toast, options
tools/      gen-weights: offline SimulationCraft pipeline for Core/WeightsData.lua
tests/      engine tests: lua5.1 tests/run.lua
docs/       HOW-IT-WORKS.md (what Sift says and why), ARCHITECTURE.md (the code),
            COMMANDS.md (every slash command), ENGINEERING.md (rules every
            change meets), MAINTENANCE.md (what to check each patch and season)
Media/      the icon, rendered from tools/brand/sift-logo.svg
```

## Develop

- `lua5.1 tests/run.lua` runs the engine tests. `lua5.1 tests/smoke.lua`
  loads the whole addon under a fake WoW API and drives login, a loot pickup,
  tooltips, the panel, every slash command and the wake events. A pre-commit
  hook runs both and rejects non-ASCII bytes; `git config core.hooksPath
  .githooks` enables it.
- Any editor running `lua_ls` reads `.luarc.json`. Completion for the game
  API comes from the LuaLS annotations in Ketho's vscode-wow-api; in Neovim,
  warcraft-api.nvim adds them with `:WarcraftApi enable`.
- In game: `/sift probe` checks the game APIs the adapters depend on and
  stores the raw findings in SavedVariables (`docs/MAINTENANCE.md`).
- Releases: push a `v*` tag and the packager uploads to CurseForge, Wago and
  WoWInterface (secrets required).

## Stat weights

Sift scores with the first of these it finds for your spec:

1. Weights you pasted in. Type `/simc` in game (Simulationcraft addon), run
   a Stat Weights sim at raidbots.com, and paste the Pawn string into the
   sheet at `/sift weights`. Sift remembers when you did and how much gear
   has changed since, and asks for a fresh sim when it gets stale.
2. Defaults generated from SimulationCraft's own Season 2 profiles
   (`Core/WeightsData.lua`, regenerated with `tools/gen-weights`).
3. Rough priorities for specs SimC does not model.

Weights are a linear estimate, and Raidbots is right that a direct sim
(Top Gear, Droptimizer) beats them. Sift's answer to that is the
confidence band: when two pieces sit inside the margin of error the
verdict is "Sim it", with both scores shown, rather than a guess. Your
own weights narrow the band; the shipped ones are wider on purpose.

## Status

Loaded in the client with no errors; tooltips, chat, panel and minimap
button work. Verdicts are checked against Raidbots sims as they come up.
Everything under `Core/` is covered by tests.

License: MIT.
