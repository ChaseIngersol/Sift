-- The loot journal: a record in the saved variables of everything that
-- happens around a drop, so a fast keystone ending can be read back
-- after the group is gone. Every pickup Sift judges, every roll it puts
-- a word beside, and (once group chat exists) every line it posts or
-- would have posted in a dry run. Entries are grouped into runs; a run
-- ends when the instance changes or a keystone starts.
--
-- An entry: { t, run, where, kind, player, link, name, word, brief,
-- wear, channel, text }. Kinds: drop (yours), theirs, roll, post,
-- dryrun, ask.
local ADDON, ns = ...

local Journal = {}
ns.Journal = Journal

local MAX = 300

local function store()
  local db = ns.db
  if not db then return nil end
  db.journal = db.journal or {}
  local j = db.journal
  j.entries = j.entries or {}
  j.run = j.run or 0
  return j
end

-- Where the character is, as one string: "Ara-Kara +12" in a keystone,
-- "Nerub-ar Palace (Heroic)" in a raid, the zone outside.
local function place()
  local name, kind, _, difficulty, _, _, _, id
  if GetInstanceInfo then name, kind, _, difficulty, _, _, _, id = GetInstanceInfo() end
  if (kind == nil or kind == "none") and GetZoneText then
    local zone = GetZoneText()
    if zone and zone ~= "" then name = zone end
  end
  name = name or "?"
  local level
  local cm = C_ChallengeMode
  if cm and cm.IsChallengeModeActive and cm.IsChallengeModeActive() and cm.GetActiveKeystoneInfo then
    level = cm.GetActiveKeystoneInfo()
  end
  if level and level > 0 then
    name = string.format("%s +%d", name, level)
  elseif (kind == "raid" or kind == "party") and difficulty and difficulty ~= "" then
    name = string.format("%s (%s)", name, difficulty)
  end
  return name, id or 0
end

-- A new run when the instance is not the one the last entry saw.
function Journal.Sync()
  local j = store()
  if not j then return end
  local _, id = place()
  if j.instance ~= id then
    j.instance = id
    j.run = j.run + 1
  end
end

-- A keystone starting is a new run even inside the same dungeon.
function Journal.NewRun()
  local j = store()
  if not j then return end
  j.run = j.run + 1
end

local function itemName(link)
  if not link then return nil end
  local name = link:match("%[(.-)%]")
  return name or link
end

-- e: { player, link, word, brief, wear, channel, text }
function Journal.Add(kind, e)
  local j = store()
  if not j then return nil end
  Journal.Sync()
  local where = place()
  local entry = {
    t = time(), run = j.run, where = where, kind = kind,
    player = e.player, link = e.link, name = e.name or itemName(e.link),
    word = e.word, brief = e.brief, wear = e.wear, channel = e.channel, text = e.text,
  }
  local list = j.entries
  list[#list + 1] = entry
  while #list > MAX do table.remove(list, 1) end
  return entry
end

-- A pickup of your own with its verdict.
function Journal.Drop(entry)
  local f, v = entry.facts, entry.verdict
  if not f or not v then return end
  local me = ns.Character and ns.Character.Key and ns.Character.Key() or nil
  Journal.Add("drop", {
    player = me, link = f.link, name = f.name,
    word = ns.Engine.Headline(v), brief = ns.Engine.BriefLine(v) or v.reason,
  })
end

-- A Need/Greed window Sift put a word beside.
function Journal.Roll(link, word, line)
  Journal.Add("roll", { link = link, word = word, brief = line })
end

function Journal.Entries()
  local j = store()
  return j and j.entries or {}
end

-- The entries of the most recent run that has any.
function Journal.LastRun()
  local list = Journal.Entries()
  local out = {}
  if #list == 0 then return out end
  local run = list[#list].run
  for i = 1, #list do
    if list[i].run == run then out[#out + 1] = list[i] end
  end
  return out
end

local function clock(t, fmt)
  if type(date) == "function" then return date(fmt, t) end
  return tostring(t)
end

-- One entry as a chat line. plain: the item's name instead of its link,
-- for text that leaves the game.
local function describe(e, plain)
  local item = (plain and e.name) or e.link or e.name or "?"
  local tail = e.word and (e.word .. (e.brief and e.brief ~= "" and (", " .. e.brief) or "")) or (e.brief or "")
  local who = e.player and (e.player .. " ") or ""
  local body
  if e.kind == "drop" then
    body = string.format("you looted %s: %s", item, tail)
  elseif e.kind == "theirs" then
    body = string.format("%slooted %s: %s", who, item, tail)
  elseif e.kind == "roll" then
    body = string.format("roll on %s: %s", item, tail)
  elseif e.kind == "post" then
    body = string.format("posted to %s: %s", tostring(e.channel), tostring(e.text))
  elseif e.kind == "dryrun" then
    body = string.format("would have posted to %s: %s", tostring(e.channel), tostring(e.text))
  elseif e.kind == "ask" then
    body = string.format("asked in %s: %s", tostring(e.channel), tostring(e.text))
  else
    body = string.format("%s %s: %s", tostring(e.kind), item, tail)
  end
  if e.wear and e.wear ~= "" and e.kind ~= "post" and e.kind ~= "dryrun" and e.kind ~= "ask" then
    body = body .. " (could wear it: " .. e.wear .. ")"
  end
  if plain then body = body:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "") end
  return string.format("  %s %s", clock(e.t, "%H:%M"), body)
end

local function header(entries)
  local first, last = entries[1], entries[#entries]
  local span = clock(first.t, "%a %H:%M")
  if last.t ~= first.t then span = span .. " to " .. clock(last.t, "%H:%M") end
  return string.format("%s, %s, %d entr%s", last.where or "?", span, #entries, #entries == 1 and "y" or "ies")
end

-- The last run as lines, headed by where and when it was. all: every
-- run on file, oldest first. plain: names instead of links.
function Journal.Lines(all, plain)
  local lines = {}
  local list = all and Journal.Entries() or Journal.LastRun()
  if #list == 0 then
    lines[1] = "Journal: nothing on record yet. Sift writes down every drop it judges, every roll it advises on and every line it posts to a group."
    return lines
  end
  local run, group = nil, {}
  local function flush()
    if #group == 0 then return end
    lines[#lines + 1] = "Journal: " .. header(group)
    for _, e in ipairs(group) do lines[#lines + 1] = describe(e, plain) end
    group = {}
  end
  for _, e in ipairs(list) do
    if e.run ~= run then flush(); run = e.run end
    group[#group + 1] = e
  end
  flush()
  return lines
end
