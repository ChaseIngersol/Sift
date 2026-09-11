# Changelog

## 1.0.5 - 2026-09-10

- Hovering a send row no longer throws a Lua error. The "Equipped on"
  panes beside the tooltip, which show what the alt wears, measured
  their header to size it, and the game now hands that measurement
  back as a secret value inside a tooltip. The panes size themselves
  without measuring anything.
- Dismiss under the toast clears the whole stack once you are done
  looking. A click on a row still clears just that row.

## 1.0.4 - 2026-09-08

- The Great Vault ranking now sits on the vault's own cards: Take with
  the gain and a jade edge on the pick, Good, Sim it or Pass on the rest,
  and one sentence under the window instead of a line per item. The
  word is set in the card's own item-level type, so it reads as part of
  the window. The full reason is still in each card's tooltip and in
  `/sift vault`.
- A vault offer or a roll that would replace a worn tier piece now says
  to catalyze it and keep the set, instead of calling it an off-piece.
  The game cannot be asked whether a bare link converts, so a non-tier
  piece in a tier slot on a current track is taken as convertible.
- The panel keeps your place when it refreshes after you equip, vendor
  or bank something. It starts at the top only when you open it.
- The panel's default width is narrower, to fit the shorter row text.
  Double-click the corner grip to return to it.

## 1.0.3 - 2026-09-07

- The wait for worn gear the client has not loaded yet now rides each
  item's own load callback, so a cold start can no longer miss the moment
  the data arrives.
- `/sift status` says when worn pieces are still waiting on item data and
  how often the picture was re-read; `/sift probe cold` exercises it.

## 1.0.2 - 2026-09-07

- Worn gear the client had not loaded yet at login left holes in Sift's
  picture of you, and every verdict against a hole called the slot empty.
  Sift now waits for the item data and re-runs everything once it has it.
- Slots with plural names read right: your legs are empty.

## 1.0.1 - 2026-09-07

- Listed on CurseForge. The project id in the TOC lets the CurseForge app
  match installed copies to the project.

## 1.0.0 - 2026-09-07

First release, for Midnight 12.1 (Season 2).

- One word and a reason for every rare-or-better piece that lands in
  your bags: Equip, Hold, Sim it, Send or Dispose.
- Scoring by stat weights (your own Raidbots weights, defaults generated
  from SimulationCraft, or shipped priorities), with gems and sockets, a
  margin of error, upgrade tracks with crest costs and free ranks, the
  long-term rule, held items competing for a slot, tier sets and the
  catalyst.
- Alts: gear remembered per character, sends through the warband bank
  with reminders at the bank, comparison panes against the alt's gear.
- Surfaces: a tooltip line, chat at safe moments, the panel, a toast
  placed in Edit Mode, a word beside Need and Greed rolls, a Great Vault
  ranking.
- A four-page guide at the first login, a settings page with a command
  reference, and `/sift feedback` for reports.
