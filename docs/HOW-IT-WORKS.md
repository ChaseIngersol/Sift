# How Sift works

Sift looks at every rare-or-better piece of gear that lands in your bags
and answers one question: what should you do with it? The answer is one
word and a reason. Sift never acts on it for you.

## The five words

| Word | Meaning |
| --- | --- |
| Equip | Better than what you wear for your active spec, by the numbers. |
| Hold | Keep it. It wins after upgrades, completes a tier set through the catalyst, or needs a level. The panel says what it is waiting for. |
| Sim it | Too close to call, or a trinket. Only a sim can answer, and Sift would rather say so than guess. Healers see "Your call" instead, since Raidbots does not sim healing. |
| Send | An alt on file wants it more than you do. |
| Dispose | Nothing you or your alts can use. Vendor or disenchant. |

Every verdict comes with a reason ("+4.8% vs Worn Helm, after 2 upgrades,
40 Champion crests") and, where it matters, a note.

## How it scores

Sift scores gear by stat weights, not item level. Each stat on a piece
is multiplied by its weight for your spec and the results are added up;
the primary stat, gems and empty sockets count. A candidate is compared
with the piece it would replace, and the gain is given as a percentage
of the worn piece's score. Rings and trinkets are compared with the
weaker of the two you wear.

The weights come from the first of these that exists for your spec:

1. Weights you pasted in from a Raidbots stat weights sim. They account
   for your talents and gear, and Sift asks for a fresh sim once they
   have gone stale.
2. Defaults generated from SimulationCraft's own profiles for the
   season.
3. Stat priorities for the specs SimulationCraft does not model, which
   give tier words ("clearly better", "about the same") instead of
   percentages.

Gains under the threshold (one percent by default) count as "about the
same".

## When Sift is unsure

Weights are an estimate, so every comparison carries a margin of error.
The margin is a share of how much the two pieces differ in secondary
stats: ten percent with your own weights, twenty with the generated
defaults, thirty with plain priorities. When the gain sits inside that
margin the answer is "Sim it" with both scores shown. Your own weights
narrow the margin; the shipped ones are wide on purpose.

Trinkets always get "Sim it", with their item levels, because their
effects cannot be scored from stats. Any other piece with an on-use or
on-equip effect gets a note saying the same. A piece you already wear is
scored on its stats alone, so an effect piece in a slot can look weaker
than it is.

## Upgrades and the long run

Season gear sits on an upgrade track (Adventurer, Veteran, Champion,
Hero, Myth), with six ranks per track and a crest cost per rank. Sift
knows each track's item levels, so a piece that is worse today but
better after two ranks is a Hold with the exact cost: "after 2 upgrades,
40 Champion crests". Ranks at or under the highest item level you have
already reached in that slot are free, and the reason says so.

The deciding question is which piece owns the slot in a month, not which
is ahead today. Both pieces are scored at the top of their own tracks:

- If the worn piece wins there, the candidate never gets an Equip. Ahead
  today, it is "Upgrade the worn piece instead, wear this meanwhile";
  behind, it is Dispose with the projection ("still -4.3% at max").
- If the candidate wins there, the usual rules stand: Equip when ahead
  now, Hold at the first rank that passes the worn piece.
- The same contest runs against everything else you are holding for that
  slot. A piece that loses to another held piece with confidence is
  "Outclassed by Hero Chest in your bags" and is disposed of, or sent if
  an alt wants it. A new hold re-runs the others, and a hold leaving your
  bags gives the pieces it outclassed another look.

## Tier sets and the catalyst

Sift counts the tier pieces you wear. A piece that would complete a
two-piece or four-piece through the catalyst is a Hold for the catalyst,
and "Catalyze" once a charge is ready. A piece that would replace a tier
piece while your set count sits exactly on a threshold is never an Equip,
however good its stats: it is the off-piece once another tier piece frees
the slot. The reverse holds too: a tier piece you already own is an Equip
when wearing it completes a two-piece or four-piece, whatever its stats
say, and a third piece is held for the four-piece. A setting sets the
lowest upgrade track worth a charge (Champion by default).

## Alts and sending

Sift remembers the gear of every character you log into. A piece that is
warbound until equipped is scored for each of them, and when an alt gains
more from it than you do the verdict is Send, naming the alt, with the
runners-up in a note. Hovering a Send row in the panel compares the piece
against what that alt wears, not what you wear.

Press "Will send" on the row and the alt's panel knows the piece is
coming. Put it in the warband bank and both panels see it there until
the alt picks it up. Opening any bank reminds you what to deposit for
alts and what is waiting for you.

A parked character never receives send suggestions. A setting puts alts
ahead of your own offspec holds.

## Levels

A piece above your level is judged as if you were at that level. If it
would be worth wearing then, it is a Hold that wakes when you level.

## Where it shows up

- **Tooltip.** One line on every piece you could equip: the word and
  the reason. Hold Shift for the math.
- **Chat.** One line per new verdict, delivered at a safe moment: out
  of combat, no keystone running, no boss in progress. Reminders at a
  vendor, an upgrade NPC and a bank follow the same setting.
- **Panel.** `/sift`, the minimap button or the addon compartment.
  Everything waiting on you, grouped by what to do next. Opening it
  evaluates your bags quietly, so pieces from before Sift are on it too,
  and it keeps up while open as you equip, loot and bank.
- **Toast.** A small card per verdict, at the same safe moments as
  chat. Place it in Edit Mode like any other HUD element, or switch it
  off in settings.
- **Rolls.** A word beside every Need and Greed window: Need with the
  gain, Sim it when close, Greed when an alt wants it, Pass when it is a
  dead end. Nothing is rolled for you.
- **Great Vault.** A ranking of the offers under the vault window while
  it is open.
- **The guide.** Four pages at the first login, and `/sift guide` after.

## Settings

| Setting | Default |
| --- | --- |
| Chat lines | on |
| Toast for each verdict | on |
| Sound with the toast | off |
| Put alts ahead of offspec holds | off |
| Advise on Great Vault picks | on |
| Advise on loot rolls | on |
| Remind at the bank | on |
| Park this character | off |
| Show minimap button | on |
| Minimum gain to call something better | 1% |
| Lowest item quality to evaluate | Rare |
| Lowest track to catalyze | Champion |
| Debug mode | off |

The settings page also opens the weights sheet, the guide, Edit Mode for
the toast and the feedback report, and lists every `/sift` command with a
button that runs it. `docs/COMMANDS.md` describes each command.

## What it never does

Sift never equips, sells, moves, rolls on or catalyzes anything. It
touches no protected frame and reads no combat data. Everything it
knows comes from item tooltips, your bags, your characters' gear and the
currency window, and everything it says is advice.
