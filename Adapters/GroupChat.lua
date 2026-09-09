-- Telling the group. One click on a toast row, a panel row or the roll
-- strip posts one line to party, raid or instance chat: what a drop is
-- worth to you, or who in the group could wear what is not. The game
-- allows group chat from addon code only on a hardware event, which is
-- the rule here anyway: nothing is ever posted without a click.
--
-- LIVE is the master switch. While it is false every post is a dry run
-- that prints "would post to PARTY: ..." in your own chat frame and goes
-- into the journal, and the buttons show only in debug mode. It flips
-- once a real group run with debug on reads right. Live, debug mode
-- still dry-runs.
local ADDON, ns = ...

local GroupChat = {}
ns.GroupChat = GroupChat

GroupChat.LIVE = false

local NO_ARMOR_CHECK = { INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_HOLDABLE = true }
local ARMOR_NAME = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
local PRIMARY_NAME = { STRENGTH = "strength", AGILITY = "agility", INTELLECT = "intellect" }

function GroupChat.Enabled()
  return ns.DB.Prefs().groupChat ~= false
end

-- Whether the buttons show at all: the setting, and before the flip,
-- only in debug mode.
function GroupChat.Showing()
  if not GroupChat.Enabled() then return false end
  if not GroupChat.LIVE and not ns.DB.Prefs().debug then return false end
  return GroupChat.Channel() ~= nil
end

-- Where a post goes, or nil when not in a group.
function GroupChat.Channel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end

-- The button's word for the channel.
function GroupChat.Label(channel)
  channel = channel or GroupChat.Channel()
  if channel == "RAID" then return "Tell raid" end
  if channel == "INSTANCE_CHAT" then return "Tell group" end
  return "Tell party"
end

-- Everyone else in the group: { name, classID, classFile }.
function GroupChat.Members()
  local out = {}
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local raid = IsInRaid and IsInRaid()
  local last = raid and n or (n - 1)
  for i = 1, last do
    local unit = (raid and "raid" or "party") .. i
    if not (raid and UnitIsUnit and UnitIsUnit(unit, "player")) then
      local name = UnitName(unit)
      local _, classFile, classID = UnitClass(unit)
      if name and name ~= "" and name ~= UNKNOWNOBJECT and classID then
        out[#out + 1] = { name = name, classID = classID, classFile = classFile }
      end
    end
  end
  return out
end

-- Can a class wear this piece: armor weight, weapon kind, shield or
-- off-hand, and a primary stat one of its specs uses. A class whose
-- specs are unknown passes the stat check.
local function classCanWear(classID, f)
  local Data = ns.Data
  local class = Data.classes[classID]
  if not class then return false end
  if f.classID == Data.ITEM_CLASS.ARMOR then
    local sub = f.subclassID
    if sub == Data.ARMOR.SHIELD then
      if not class.shield then return false end
    elseif f.equipLoc == "INVTYPE_HOLDABLE" then
      if not class.offhand then return false end
    elseif ARMOR_NAME[sub] and not NO_ARMOR_CHECK[f.equipLoc] then
      if sub ~= class.armor then return false end
    end
  elseif f.classID == Data.ITEM_CLASS.WEAPON then
    if not class.weapons[f.subclassID] then return false end
  end
  local fixed = ns.Stats.FixedPrimary(f.stats or {})
  local wants = fixed and { [fixed] = true } or f.flex
  if wants then
    local specs = ns.Specs.ForClass(classID)
    if #specs > 0 then
      local any = false
      for _, s in ipairs(specs) do if wants[s.primary] then any = true end end
      if not any then return false end
    end
  end
  return true
end

-- What kind of piece it is, for the ask: "Plate, strength", "Cloth",
-- "daggers, agility", "a ring".
local function kindOf(f)
  local Data = ns.Data
  local parts = {}
  if f.classID == Data.ITEM_CLASS.ARMOR then
    local sub = f.subclassID
    if sub == Data.ARMOR.SHIELD then parts[1] = "A shield"
    elseif f.equipLoc == "INVTYPE_HOLDABLE" then parts[1] = "An off-hand"
    elseif ARMOR_NAME[sub] and not NO_ARMOR_CHECK[f.equipLoc] then parts[1] = ARMOR_NAME[sub]
    elseif f.equipLoc == "INVTYPE_CLOAK" then parts[1] = "A cloak"
    elseif f.equipLoc == "INVTYPE_NECK" then parts[1] = "A neck"
    elseif f.equipLoc == "INVTYPE_FINGER" then parts[1] = "A ring"
    elseif f.equipLoc == "INVTYPE_TRINKET" then parts[1] = "A trinket"
    end
  elseif f.classID == Data.ITEM_CLASS.WEAPON then
    local name = Data.WEAPON_NAME[f.subclassID]
    if name then parts[1] = name:sub(1, 1):upper() .. name:sub(2) end
  end
  local fixed = ns.Stats.FixedPrimary(f.stats or {})
  if fixed and PRIMARY_NAME[fixed] then parts[#parts + 1] = PRIMARY_NAME[fixed] end
  return table.concat(parts, ", ")
end

-- The names of everyone else in the group who could wear the piece,
-- and what kind of piece it is.
function GroupChat.Wearers(f)
  local names = {}
  for _, m in ipairs(GroupChat.Members()) do
    if classCanWear(m.classID, f) then names[#names + 1] = m.name end
  end
  return names, kindOf(f)
end

-- "Marcus", "Marcus or Elena", "Marcus, Elena or Bob", and past three
-- "Marcus, Elena, Bob or 4 more": a chat line holds 255 characters and
-- the item link takes a good part of that.
local MAX_NAMES = 3
local function listNames(names)
  if #names == 0 then return "anyone" end
  if #names == 1 then return names[1] end
  if #names > MAX_NAMES then
    return table.concat(names, ", ", 1, MAX_NAMES) .. string.format(" or %d more", #names - MAX_NAMES)
  end
  return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
end

-- The condition without the crest cost: "after 1 upgrade".
local function plainWhen(b)
  local w = b and b.when
  if not w then return nil end
  w = w:gsub(",%s*%d+%s+%a+%s+crests?", "")
  return w
end

-- The line for a drop of yours. Returns text, word, brief, wear.
function GroupChat.Text(f, v)
  local K = ns.Engine.KIND
  local link = f.link or f.name or "?"
  local word = ns.Engine.Headline(v)
  local brief = ns.Engine.BriefLine(v) or v.reason
  local b = v.brief
  if v.kind == K.EQUIP or v.kind == K.HOLD then
    local text
    if v.kind == K.HOLD and v.sub == "sim" then
      text = string.format("Sift: %s is close to what I have, I will sim it. Taking it.", link)
    elseif v.kind == K.HOLD and v.sub == "offspec" then
      text = string.format("Sift: %s for my offspec. Taking it.", link)
    elseif b and b.gain then
      local when = plainWhen(b)
      text = string.format("Sift: %s %s for me%s. Taking it.", link, b.gain, when and (" " .. when) or "")
    else
      text = string.format("Sift: %s is an upgrade for me. Taking it.", link)
    end
    return text, word, brief, nil
  end
  local names, kind = GroupChat.Wearers(f)
  local wear = table.concat(names, ", ")
  local ask = (kind ~= "" and (kind .. ": ") or "") .. listNames(names) .. "?"
  return string.format("Sift: %s not for me. %s", link, ask), word, brief, wear
end

-- The line behind "Say why" on a roll: what the Need is for.
function GroupChat.RollText(link, v)
  local K = ns.Engine.KIND
  local b = v.brief
  if v.kind == K.HOLD and v.sub == "sim" then
    return string.format("Sift: needing %s, close enough to sim", link)
  elseif v.kind == K.HOLD and v.sub == "offspec" then
    return string.format("Sift: needing %s for my offspec", link)
  elseif b and b.gain then
    local when = plainWhen(b)
    return string.format("Sift: needing %s for %s%s", link, b.gain, when and (" " .. when) or "")
  end
  return string.format("Sift: needing %s, an upgrade for me", link)
end

-- Whether a roll's advice earns a "Say why": only a Need of some kind.
function GroupChat.RollOffers(v)
  if not v then return false end
  local K = ns.Engine.KIND
  return v.kind == K.EQUIP or (v.kind == K.HOLD and v.sub ~= "instead")
end

-- Post one line, or dry-run it. e: { link, word, brief, wear } for the
-- journal. channel defaults to the group's; test = true forces a dry
-- run to PARTY outside a group. Returns "post", "dryrun" or nil.
function GroupChat.Post(text, e, channel, test)
  channel = channel or GroupChat.Channel() or (test and "PARTY") or nil
  if not channel then
    ns.Print("not in a group, nothing posted")
    return nil
  end
  e = e or {}
  local live = GroupChat.LIVE and not ns.DB.Prefs().debug and not test
  local kind = live and "post" or "dryrun"
  if live then
    SendChatMessage(text, channel)
  else
    ns.Print(string.format("would post to %s: %s", channel, text))
  end
  if ns.Journal then
    ns.Journal.Add(kind, { link = e.link, word = e.word, brief = e.brief, wear = e.wear, channel = channel, text = text })
  end
  return kind
end

-- A drop of yours, from a toast or panel row: facts and verdict.
function GroupChat.Tell(f, v)
  local text, word, brief, wear = GroupChat.Text(f, v)
  return GroupChat.Post(text, { link = f.link, word = word, brief = brief, wear = wear })
end

-- A roll's "Say why".
function GroupChat.SayWhy(link, v, word)
  return GroupChat.Post(GroupChat.RollText(link, v), { link = link, word = word, brief = ns.Roll.Line(v) })
end

-- Whether a drop of yours gets the button: tradeable to the group, and
-- the buttons showing.
function GroupChat.Offers(f)
  return f ~= nil and f.tradeable == true and GroupChat.Showing()
end

-- /sift chat test: every toast row, as it would be posted, printed here
-- and journaled. Works outside a group. Returns the count.
function GroupChat.Test()
  if not ns.Toast then return 0 end
  local n = 0
  for _, e in ipairs(ns.Toast.Entries()) do
    local t = e.t
    if not e.sample and t.facts and t.verdict then
      local text, word, brief, wear = GroupChat.Text(t.facts, t.verdict)
      GroupChat.Post(text, { link = t.facts.link, word = word, brief = brief, wear = wear }, nil, true)
      n = n + 1
    end
  end
  return n
end

-- /sift chat: where things stand.
function GroupChat.Status()
  local channel = GroupChat.Channel()
  local lines = {}
  lines[1] = GroupChat.LIVE and "group chat is live: a click posts to the group, unless debug mode is on"
    or "group chat is not live yet: every click is a dry run printed here and written to the journal"
  lines[2] = channel and ("in a group: posts would go to " .. channel) or "not in a group"
  if not GroupChat.Enabled() then lines[#lines + 1] = "the setting is off: no buttons show" end
  local members = GroupChat.Members()
  if #members > 0 then
    local names = {}
    for _, m in ipairs(members) do names[#names + 1] = m.name .. " (" .. tostring(m.classFile) .. ")" end
    lines[#lines + 1] = "with " .. table.concat(names, ", ")
  end
  lines[#lines + 1] = "/sift chat test prints what each toast row would post"
  return lines
end
