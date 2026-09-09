# Maintaining Sift

What to check when a patch or a season lands, and where the addon leans
on game behavior that can change. `docs/ENGINEERING.md` has the rules
every change meets; `docs/ARCHITECTURE.md` has the layout and the data
flow.

## Each patch

1. `## Interface:` in `SiftLootAdvisor.toc` is the one supported client version.
   Compare it with `select(4, GetBuildInfo())` in game and bump it.
2. Run the tests: `lua5.1 tests/run.lua` and `lua5.1 tests/smoke.lua`.
   The pre-commit hook (`git config core.hooksPath .githooks`) runs both
   and rejects non-ASCII bytes.
3. Log in with debug mode on (settings, or `prefs.debug`) so errors reach
   BugSack with traces instead of being swallowed by `Adapters/Guard.lua`.
4. `/sift status`: the character, spec, slots, alts, weights source, crest
   and catalyst currency ids in use, the spec scan result and anything the
   client reports differently from `Core/Data.lua`. The client is the
   authority for a spec's primary stat and role at runtime; when it
   disagrees with the shipped table, fix the table so the tests and the
   spec sweep match the game.
5. `/sift probe`: the API verification probe (tooltip upgrade fields,
   catalyst eligibility, set ids, gems and sockets, currencies, spec
   facts, growth pairs). Its findings land in `SiftLootAdvisorDB.probe.last` after a reload; compare with
   the last known-good run.
6. Look once at every surface that hooks Blizzard's UI: the tooltip line,
   the roll strip (an LFR wing is the quickest way to see a Need/Greed
   roll), the vault ranking, the bank reminder, the toast in Edit Mode and
   the settings page.

## Each season

Everything seasonal lives in `Core/Season.lua` and nowhere else. Review
every field there:

- `id`, `label`, `interface`.
- `tracks` (item level by rank per upgrade track) and `trackOrder`.
  `Core/Tracks.lua` anchors on an item's observed level, so the step
  pattern between ranks is what has to be right.
- `crestPerRank`.
- `crestCurrency` per track and `crestNamePattern`; `catalystCurrency`
  and `catalystNamePattern`; `currencyScanRange`. A pinned id is used
  while the client knows the currency by that name, otherwise
  `Adapters/Resources.lua` discovers it by name inside the scan range.
  `/sift currency <track|catalyst> <id>` overrides both at runtime.
- `trackStringIDs`: seeds for the tooltip upgrade line;
  `Adapters/ItemFacts.lua` learns the rest from the line text.
- The stat growth constants, measured from same-slot pairs. Anything
  marked VERIFY was inferred, not observed. `Adapters/Calibrate.lua`
  replaces a class with a live estimate once enough pairs are seen.

Then regenerate the weights:

```sh
SEASON=<tag> tools/gen-weights/gen-weights.sh <simc-checkout> [iterations]
```

It rewrites `Core/WeightsData.lua` with provenance in its header (date,
SimulationCraft version, commit, branch, season, iterations), and
`tests/weightsdata_spec.lua` checks the shape. Specs SimulationCraft does
not maintain a profile for fall back to the priorities in `Core/Data.lua`;
those need a manual pass against a current guide each season.

Also confirm tier set membership (item set id), catalyst eligibility
(`C_Item.IsItemConvertibleAndValidForPlayer`) and the catalyst charge
currency against the first tier pieces of the season.

## Where Sift leans on the game

Verify against Blizzard's UI source (github.com/Gethe/wow-ui-source,
branch `live`) when any of these break.

| Area | Where | What it assumes |
| --- | --- | --- |
| Upgrade line | `Adapters/ItemFacts.lua` | The tooltip's typed upgrade line, its track string ids, and the "Track N/M" text as a fallback. Without it, holds lose their crest costs. |
| Item effects | `Adapters/ItemFacts.lua` | "Use:" and "Equip:" lines mark an effect; an "Equip: +stat" line does not. |
| Stats | `Core/Stats.lua` | `C_Item.GetItemStats` on links that carry upgrade bonus ids. |
| Currencies | `Adapters/Resources.lua` | `C_CurrencyInfo.GetCurrencyInfo` and discovery by name. |
| Warband bank | `Adapters/Bank.lua` | `C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)`, the tabs readable as bag ids while the bank is open, and the Banker/AccountBanker interaction types. |
| Great Vault | `Adapters/Vault.lua` | `C_WeeklyRewards.GetActivities`, `GetExampleRewardItemHyperlinks`, hooks on `WeeklyRewardsFrame` once `Blizzard_WeeklyRewards` loads. |
| Loot rolls | `Adapters/LootRoll.lua`, `UI/LootRoll.lua` | `GroupLootFrame1` to `GroupLootFrame4` and their show scripts. |
| Alt comparison | `UI/AltCompare.lua` | `C_TooltipComparison.GetItemComparisonDelta`, `C_TooltipInfo.GetHyperlink`, a post-hook on `GameTooltip:SetOwner`, `ShoppingTooltipTemplate`. |
| Settings page | `UI/Options.lua` | `Settings.RegisterProxySetting`, `CreateDropdown`, `CreateSettingsButtonInitializer`, `SettingsPanel:GetLayout`. |
| Edit Mode | `UI/EditMode.lua`, `UI/EditModePanel.lua` | `EditModeManagerFrame` and the `NineSliceUtil` highlight kits. |
| Dialogs | `UI/Guide.lua` | Showing a full-area UI panel runs `CloseAllWindows`, which hides every frame in `UISpecialFrames`; the guide steps aside for settings on purpose. |
| Catalyst | `Adapters/ItemFacts.lua` | `C_Item.IsItemConvertibleAndValidForPlayer` for anything with a location. A bare link (vault offer, roll window) is inferred: non-tier piece, tier slot, current track. |
| Spec facts | `Adapters/SpecScan.lua`, `Core/Specs.lua` | The client's spec records (primary stat, role, name) for every class. |

## Invariants

- `Core/Season.lua`, `Core/Data.lua` and `Core/WeightsData.lua` are data
  only. No logic goes in them.
- Every verdict word and reason is decided in `Core/Engine.lua`. Surfaces
  render what the engine says; none of them decides anything.
- Every entry point (events, slash commands, buttons, hooks) runs under
  `Adapters/Guard.lua`. Nothing Sift does may raise an error in play.
- Nothing runs while idle: no OnUpdate, no tickers without a job, events
  registered only while their answer matters (`Triggers.SyncWakeEvents`).
- ASCII only, Lua 5.1, no libraries, one TOC.
- Saved variables: `SiftLootAdvisorDB` (account) and `SiftLootAdvisorCharDB` (character), shaped
  in `Adapters/DB.lua`. A change to their shape needs a migration there,
  keyed on a stored version, and a smoke scenario that loads the old
  shape.
- Tests: a spec in `tests/*_spec.lua` for every engine branch, a smoke
  scenario in `tests/smoke.lua` for every surface and command
  (`docs/COMMANDS.md` is checked against the command table). The spec
  sweep in `tests/engine_spec.lua` runs all forty specs through the
  engine; keep it at forty when a spec is added.

## Releasing

- `.pkgmeta` keeps tests, tools, docs and editor files out of the package;
  the TOC version comes from `@project-version@`.
- Pushing a `v*` tag runs `.github/workflows/release.yml` (the BigWigs
  packager), which uploads to CurseForge, Wago and WoWInterface with the
  `CF_API_KEY`, `WAGO_API_TOKEN` and `WOWI_API_TOKEN` repository secrets
  and the `X-Curse-Project-ID`, `X-Wago-ID` and `X-WoWI-ID` TOC fields.
- Before tagging: tests green, a login with debug mode on, `/sift probe`,
  one roll, one vault visit.

## Reports from players

`/sift feedback` builds a report (Sift and game versions, the status
lines, the settings in effect, the last log lines) in the copy box.
`Feedback.URL` in `UI/Feedback.lua` is the one place that says where to
paste it.
