# Sift - Engineering Rules

These are acceptance criteria, not suggestions. They are adapted from the
EllesmereUI contribution rules, which are the strictest public standard for a
Midnight-era addon. A change that violates one is not done.

## The five criteria

1. **Zero cost when idle.** Nothing runs on a frame tick. No `OnUpdate`. Event
   handlers are registered only while something depends on them: merchant,
   bank, and upgrade-vendor events are registered when a hold or send exists
   and unregistered when none remain. The tooltip hook does a cache lookup and
   nothing else. Frames for the panel and options are built on first use.

2. **Every visible surface has a switch.** The verdict surfaces ship on
   (tooltip line, chat line, toast, roll word, vault ranking, bank reminder,
   minimap button) and each is one checkbox from off. Anything else, and
   every new setting, defaults off. A bug fix may change behavior; a
   feature may not.

3. **Low cost when enabled.** Event-driven only. `C_Timer.After` is allowed to
   coalesce bursts of `BAG_UPDATE_DELAYED`; it is never a logic gate. No table
   allocation in hot paths: reuse scratch tables, cache item facts by GUID,
   scan only slots flagged new. Loops are bounded by bag size or alt count.

4. **Zero taint, zero errors.** Sift never calls a protected function and
   never touches a secure frame. Every entry point from the game (event
   handler, tooltip hook, slash command, button) runs through one guarded call
   that catches errors, logs each distinct error once, and keeps the addon
   alive. Every return value from a Blizzard API is treated as possibly nil.
   Sift reads no unit, aura, cast, or combat data, so it should never see a
   secret value; `issecretvalue()` guards sit on any path that could plausibly
   receive one, and finding one is a bug to fix, not a case to handle.

5. **Midnight only.** Single TOC, `## Interface: 120100`, updated each patch.
   No version gates, no compatibility branches, no deprecated globals
   (`getglobal`, `setglobal`, the pre-`C_Item` item functions, the pre-`C_Container`
   bag functions). Use `C_Item`, `C_Container`, `C_TooltipInfo`,
   `C_CurrencyInfo`, `C_NewItems`, and the Settings API.

## Code style

- Lua 5.1 only. No `goto`, no labels, no integer division operator, no
  bitwise operators.
- ASCII only in code, comments, strings, and docs. No em dashes, no curly
  quotes. A pre-commit check rejects non-ASCII bytes.
- `local` everything. The only globals are `Sift` (public table),
  `SiftLootAdvisorDB`, and `SiftLootAdvisorCharDB`. Files share state through the addon namespace
  table received as the second vararg.
- The engine in `Core/` references no WoW global. If it needs a game fact, the
  adapter passes it in as data. This is what makes it testable on the desktop.
- Season-specific numbers (track caps, currency IDs, tier slots) live only in
  `Core/Season.lua`.
- Match the surrounding code. Before adding an options row or panel widget,
  copy the shape of the nearest existing one.

## Testing

- `lua5.1 tests/run.lua` runs the engine fixtures. `lua5.1 tests/smoke.lua`
  runs the whole addon under a fake WoW API. Both must pass before any commit
  that touches a Lua file; the pre-commit hook enforces it.
- Every verdict rule gets at least one fixture that proves it fires and one
  that proves it does not.
- In-game checks for adapters are noted in the commit that lands them, with
  the build number.

## Tooling

- `lua_ls` with the `.luarc.json` in the root. Game API completion comes
  from the LuaLS annotations in Ketho's vscode-wow-api; Neovim users get
  them through warcraft-api.nvim (`:WarcraftApi enable` in the checkout).
- No separate linter. lua_ls flags unknown names in the editor; the tests
  and the pre-commit hook are the gate.
- Symlink the checkout into the game's `Interface/AddOns/SiftLootAdvisor` folder and
  `/reload` to see a change.
- Release through the BigWigs packager GitHub Action from a git tag.
- `tools/gen-weights/gen-weights.sh` regenerates `Core/WeightsData.lua` from
  a SimulationCraft checkout (needs cmake, a C++ compiler and python3). It
  is build-time only and excluded from the package. Commit the generated
  file with its provenance header intact.

## Change etiquette

- One focused change per commit. The message says why, not what.
- Anything visual gets a before and after screenshot in the commit or PR.
- If a rule above cannot be met, the change is not made until it can.
