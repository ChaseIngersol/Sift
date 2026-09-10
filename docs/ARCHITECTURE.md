# Architecture

Sift is three layers. The engine decides, the adapters feed it and keep
what it decided, and the surfaces show the result. Only the adapters know
the game exists.

```
Sift/
  SiftLootAdvisor.toc, Sift.lua   load order; slash commands, compartment click, public API
  Core/                pure Lua 5.1, no game globals, tested on the desktop
    Season.lua         season data: tracks, currencies, growth seeds (data only)
    Data.lua           classes, weapon models, shipped stat priorities (data only)
    WeightsData.lua    generated per-spec SimulationCraft weights (data only)
    Specs.lua          spec registry: client facts laid over shipped data
    Stats.lua          stat keys, token maps, bonus text parsing
    PawnString.lua     Pawn weight string parser
    Weights.lua        imported > generated > shipped weights, error bands
    Scorer.lua         weighted value, per-stat growth, gems, margin of error
    Growth.lua         growth calibration from same-slot pairs
    Eligibility.lua    hard filters: armor, weapons, binding, level
    Slots.lua          slot mapping and the incumbent for a piece
    Tracks.lua         upgrade track math: ranks, costs, watermarks
    Engine.lua         the verdicts
    Roll.lua           the roll word for a verdict
    Vault.lua          ranking of vault offers
  Adapters/            game APIs in, plain tables out
    Guard.lua          error guard, log, chat print
    DB.lua             saved variables, defaults
    ItemFacts.lua      item APIs and tooltip data into fact tables
    SpecScan.lua       every class's specs from the client
    Calibrate.lua      feeds Growth, hands the engine a calibrated season
    Character.lua      self and alt snapshots, weight import, staleness
    Resources.lua      crest and catalyst currency discovery
    Verdicts.lua       verdict cache, hold records, send states, bag scans
    Journal.lua        the loot journal: pickups, rolls and group posts by run
    GroupChat.lua      one click tells the group; the live switch and the dry run
    GroupLoot.lua      their drops, judged for you, with the ask
    Triggers.lua       events, safe moments, wake registration, announcements
    Bank.lua           the warband bank: deposits, pickups, reminders
    Vault.lua          the Great Vault window
    LootRoll.lua       the Need/Greed windows
    Status.lua         the status lines
    Probe.lua          the API verification probe
  UI/
    Style.lua          colors, fonts, buttons, dialogs, icons
    Tooltip.lua        the tooltip line
    Panel.lua          the panel
    Toast.lua          the toast stack
    EditMode.lua, EditModePanel.lua   Edit Mode placement for the toast
    LootRoll.lua       the strip beside a roll window
    Vault.lua          the words on the vault window's cards
    AltCompare.lua     "Equipped on <alt>" panes beside a send row
    Weights.lua        the stat weights sheet
    Guide.lua          the four-page guide
    Options.lua        the settings page
    Feedback.lua       the feedback report
    Copy.lua           the copy box
    Minimap.lua        the minimap button
```

## Data flow

1. An item lands in the bags (`BAG_UPDATE_DELAYED`, coalesced). Triggers
   diffs bag GUIDs against what it has seen and hands the new slots to
   Verdicts.
2. ItemFacts turns the item into a fact table: link, level, slot, stats,
   gems, sockets, track and rank, binding, effects, catalyst eligibility.
3. Verdicts builds the engine context: the facts, the character's
   snapshot (gear per slot, specs, weights), every alt snapshot, the
   currencies, the preferences and the season, and calls
   `Engine.Evaluate`.
4. The engine returns a verdict: `kind` (EQUIP, HOLD, SEND, DISPOSE),
   `sub` for holds (upgrade, catalyst, instead, set, offspec, sim,
   level), the `reason`, `notes`, `flags`, a `brief` (gain, versus, when,
   note, who, sign) for the compact surfaces, a `wake` condition, and
   the scoring details per spec.
5. Verdicts caches the result by GUID and, for holds and sends, writes a
   hold record to the saved variables. Triggers registers the events the
   wake condition needs and announces the verdict at the next safe
   moment. The surfaces read the cache and the hold records; none of
   them re-scores anything.

Wake events (currency changes, gear changes, spec changes, the bank, the
upgrade NPC, a merchant, a level-up) are registered only while a hold
depends on them, and a hold is re-evaluated when its input changes. A
verdict that changes is announced again with an "Update:" prefix.

## The engine's contract

`Engine.Evaluate(ctx)` takes plain tables and touches no game API, which
is what makes it testable under the desktop `lua5.1`. Every verdict word
and every reason is decided there and nowhere else. The scoring rules are:

- Weighted stat value per spec, with gems, empty sockets and the primary
  stat folded in (`Scorer`).
- The margin of error from the weight source's band and the spread of
  secondary stats (`Scorer.Margin`); inside it, the answer is "Sim it".
- Track ceilings, rank costs and free ranks (`Tracks`), the long-term
  rule and held items competing for a slot (`Engine`).
- Set counts and the catalyst (`Engine.setImpact`, `CatalystAllowed`).
- Alt scoring against every snapshot, with parking and the alt-first
  preference.
- Level-locked pieces scored at the required level.

Healers get "Your call" wherever a sim would settle a question, since
Raidbots does not sim healing (`v.flags.noSim`).

## Persistence

`SiftLootAdvisorDB` (account): preferences, character snapshots keyed by
name-realm, hold records keyed by item GUID, slot watermarks, discovered
currency ids, the last command's output, the log, the loot journal.
`SiftLootAdvisorCharDB`
(character): imported weights per spec, the parked flag. Defaults and
shapes live in `Adapters/DB.lua`.

## Rules every change meets

`docs/ENGINEERING.md`: no idle cost, a switch on every visible surface,
event-driven, zero taint and zero errors, one client version. Season
numbers only in `Core/Season.lua`. ASCII only. Tests for every rule.

## Tests

- `lua5.1 tests/run.lua`: the engine and the pure modules, with fixtures
  (`tests/fixtures.lua`). The spec sweep runs every spec through the
  engine with a piece in each kind of slot.
- `lua5.1 tests/smoke.lua`: the whole addon under a fake WoW API, driving
  login, a loot pickup, tooltips, the panel, every command, the bank,
  the vault, the settings page and the wake events. `docs/COMMANDS.md`
  is checked against the command table.

## Adding things

- A verdict rule: the engine branch, its `brief`, a fixture that proves
  it fires and one that proves it does not, and a smoke scenario if a
  surface changes.
- A surface: render from the cache and the hold records, never score;
  build on first use; register events only while they matter.
- A setting: `Adapters/DB.lua` default, a row in `UI/Options.lua`, the
  table in `docs/HOW-IT-WORKS.md`.
- A command: the handler table in `Sift.lua`, `usage()`, a section in
  `docs/COMMANDS.md`, a row in the settings reference.
