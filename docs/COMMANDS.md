# Commands

Every slash command Sift answers to, with its arguments. `tests/smoke.lua`
checks this file against the command table in `Sift.lua`, so a new command
fails the tests until it is written up here, and a removed one fails until
its entry goes.

Two things apply to every command:

- Add `copy` at the end (`/sift status copy`) to reopen the output in a box
  you can select and copy from. `/sift copy` on its own reopens the last
  command's output.
- The last command's output is also kept in `SiftLootAdvisorDB.output` with the build
  number and character, readable from the SavedVariables file after a
  reload or logout.
- `/siftloot` is the same command under a name no other addon uses, for
  when another addon has claimed `/sift`.

Anything Sift does not recognize prints the command list. The settings
page lists every command with a button that runs it.

### /sift

Open or close the panel: held items with their wake conditions, pieces
ready to upgrade or catalyze, the send list grouped by alt, the vendor
list, and the Great Vault ranking while the vault is open.

### /sift guide

Open or close the guide: four pages on what the five verdicts mean,
where Sift shows up, what to do first and what to know. It opens by
itself once, at the first login after install, unless that login lands
in combat, in which case a chat line points at it and it waits for the
next login. The panel's Guide button and the settings page open it too.

### /sift scan

Evaluate every rare-or-better equippable item in the bags as if it had
just been picked up, announce each verdict in chat, and refresh the
panel. Holds are settled in a second pass so pieces competing for one
slot see each other. Prints how many candidates were scored. Opening the
panel does the same evaluation quietly, so the command is the chat
report of it. A scan never fills the toast: it repeats what the panel
shows, and the toast is for what just landed.

### /sift toast

Fill the toast with the bag verdicts, to place it or see it with real
rows. Works even when the toast is switched off in settings, and says
so.

### /sift weights

No argument: open the stat weights sheet, where a Raidbots Pawn string can
be pasted for the current spec and the shipped defaults can be inspected.

`/sift weights <Pawn string>`: import the string from the command line.
Sift parses the text itself; the Pawn addon is not involved.

`/sift weights clear`: drop the imported weights for this character and go
back to the shipped defaults. Every cached verdict is re-run either way.

### /sift park

Toggle whether this character receives send suggestions. A parked
character is still scored when it picks something up; it just never
appears as a target for other characters' items. The same switch is in
the options as "Park this character".

### /sift options

Open Sift's page in the game's Settings window.

### /sift status

What Sift knows right now: character, active spec, how many equipped slots
were read and how many tier pieces are worn; alts on file with their spec
and average item level; holds on file; which stat weights are in use and
where they came from; crest and catalyst counts; any currency the season
data could not find, and any name that matches more than one currency
(with the id in use, so `/sift currency` can correct it); the spec scan
and growth calibration state; whether the character is parked.

### /sift journal

What happened around each drop in your last run, from the loot journal
Sift keeps in its saved variables: every pickup with the word and the
brief it got, every roll window with the word Sift put beside it, and
every line Sift posted to the group or, in a dry run, would have posted.
A run is everything since the instance last changed or a keystone
started; the command shows the most recent run that has anything in it,
headed by where and when it was, so a fast keystone ending can be read
back after the group is gone. Item links stay clickable in chat.

`/sift journal all`: every run on file, oldest first. The journal keeps
the last three hundred entries.

### /sift vault

Rank what the Great Vault is offering. The vault window must be open; the
same ranking marks the cards in the window, heads the panel and is
announced in chat once per opening.

`/sift vault preview`: run the picker on the example items the game shows
for the slots earned this week, so the flow can be tried before the
reset. The output says it is a preview.

### /sift currency

`/sift currency <Adventurer|Veteran|Champion|Hero|Myth|catalyst> <id>`

Pin a crest or catalyst currency id by hand. Only needed when the season
data fails to find one or picks the wrong one of two currencies sharing a
name; `/sift status` lists the candidates. Re-runs every cached verdict.

### /sift reset

`/sift reset confirm` wipes every snapshot, hold and preference and starts
over. Without `confirm` it only says what it would do.

### /sift help

Print the command list.

### /sift feedback

Build a report and open it in the copy box, with the address to paste it
at on the first line: Sift's version and the game build, the status
lines, every setting, and the last entries of the log. Add what happened
and what you expected. The settings page and the guide's last page have
a button for the same thing.

### /sift copy

Reopen the last command's output in the copy box. See the note at the top
about the `copy` suffix.

## Developer commands

Useful while verifying the game's API; not needed to play. They run
whenever typed, but `/sift help` lists them only with debug mode on.

### /sift probe

Run the API verification probe: item tooltip fields, upgrade lines,
sockets and gems, currencies, spec facts, growth pairs. Prints a summary and stores the raw findings in `SiftLootAdvisorDB.probe.last`
after a reload or logout.

`/sift probe watch`: log the type of every interaction frame that opens
(bank, vendor, upgrade NPC) until `/sift probe stop`.

`/sift probe bank`: with a bank open, print what the client shows of the
warband tabs (ids, slots, the first items with their GUIDs) and whether
each send on record is found in them.

`/sift probe lines <bag> <slot>`: print every tooltip line of a bag
item as the client hands it over, with what Sift read from it: the
binding, whether it is bound, and whether it can still be traded to
the group. For the lines that come and go, such as the trade window.

`/sift probe cold`: treat three worn pieces as not loaded yet, the way a
cold client start can, and let their load callbacks rebuild the picture.
`/sift status` then counts the re-read.

### /sift chat

Where group chat stands: whether posting is live or every click is a
dry run, the channel a post would go to, and who is in the group with
their classes.

`/sift chat test`: print what each toast row would post to the group,
in your own chat frame, without posting anything, and write each line
to the journal. Works outside a group. `/sift toast` fills the toast
first if it is empty.

### /sift refresh

Re-run every hold and cached verdict as if gear or spec had just changed.
The game's own events do this on their own; the command exists to force
it while testing.
