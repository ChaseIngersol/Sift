-- Their drops. In a group, every piece of gear a groupmate loots is
-- read from the game's own loot events and judged for this character
-- quietly. One that is an Equip or an upgrade Hold for you becomes a
-- toast row and a panel row, "Bob got [item]: +8.9% for you", with an
-- Ask button that posts one line to the group on a click. Loot stays
-- tradeable to eligible group members for two hours after the drop.
-- The same live switch and dry run as Adapters/GroupChat.lua.
--
-- Two sources, deduplicated: ENCOUNTER_LOOT_RECEIVED carries boss loot
-- for everyone (link, player, class); CHAT_MSG_LOOT carries the rest,
-- the keystone chest included, as "X receives loot: [item]".
local ADDON, ns = ...

local GroupLoot = {}
ns.GroupLoot = GroupLoot

local Guard = ns.Guard
local frame = CreateFrame("Frame")
local recent = {}    -- { player, entry, t }, their drops worth asking for, this group
local seen = {}      -- player .. link -> GetTime(), so both sources count once
local pending = {}   -- link -> player, waiting on item data
local watching = false
local DEDUPE = 30

local function shortName(name)
  if not name then return "?" end
  if Ambiguate then return Ambiguate(name, "short") end
  return name:match("^(.-)%-") or name
end

local function isMe(name)
  local me = UnitName("player")
  return name == me or shortName(name) == me
end

-- Only a clear gain is worth asking for: not offspec, not a sim, not
-- a piece whose better move is upgrading your own.
local function wanted(v)
  local K = ns.Engine.KIND
  if v.kind == K.EQUIP then return true end
  if v.kind == K.HOLD and (v.sub == "upgrade" or v.sub == "catalyst") then return true end
  return false
end

-- Patterns from the client's own loot strings, in its language:
-- "%s receives loot: %s." and "%s receives loot: %sx%d.".
local patterns
local function lootPatterns()
  if patterns then return patterns end
  patterns = {}
  for _, key in ipairs({ "LOOT_ITEM", "LOOT_ITEM_MULTIPLE" }) do
    local fmt = rawget(_G, key)
    if type(fmt) == "string" then
      local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
      p = p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "%%d+")
      patterns[#patterns + 1] = "^" .. p .. "$"
    end
  end
  return patterns
end

-- The toast row and chat line for one of their drops worth asking for.
local function announce(name, entry)
  local f, v = entry.facts, entry.verdict
  local brief = ns.Engine.BriefLine(v, ns.Style and ns.Style.GAIN_HEX) or v.reason
  local t = ns.Triggers.ToastFor(entry)
  t.headline = name .. " got"
  t.line = brief .. " for you"
  t.theirs = name
  ns.Triggers.Notify({
    text = string.format("%s got %s: %s for you. Ask on the toast or in the panel.", name, f.link or f.name, brief),
    toast = t,
  })
end

local function consider(player, link)
  if not (player and link) then return end
  if not ns.GroupChat.Showing() then return end
  if isMe(player) then return end
  -- The encounter event names the realm, the chat line does not.
  local key = shortName(player) .. link
  local now = GetTime()
  if seen[key] and now - seen[key] < DEDUPE then return end
  seen[key] = now
  local entry, why = ns.Verdicts.ForLink(link)
  if not entry then
    if why == "uncached" then
      pending[link] = player
      frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    return
  end
  local f, v = entry.facts, entry.verdict
  local name = shortName(player)
  if ns.Journal then
    ns.Journal.Add("theirs", { player = name, link = f.link, name = f.name, word = ns.Engine.Headline(v), brief = ns.Engine.BriefLine(v) or v.reason })
  end
  if not wanted(v) then return end
  recent[#recent + 1] = { player = name, entry = entry, t = time() }
  announce(name, entry)
end

local function retryPending()
  frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
  local list = pending
  pending = {}
  for link, player in pairs(list) do
    seen[shortName(player) .. link] = nil
    consider(player, link)
  end
end

local function onChatLoot(msg)
  if type(msg) ~= "string" then return end
  for _, p in ipairs(lootPatterns()) do
    local who, link = msg:match(p)
    if who and link and link:find("|Hitem:", 1, true) then
      consider(who, link)
      return
    end
  end
end

-- The loot events matter only in a group.
local function watch(on)
  if on == watching then return end
  watching = on
  if on then
    frame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
    frame:RegisterEvent("CHAT_MSG_LOOT")
  else
    frame:UnregisterEvent("ENCOUNTER_LOOT_RECEIVED")
    frame:UnregisterEvent("CHAT_MSG_LOOT")
    frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    pending = {}
    seen = {}
    recent = {}
    if ns.Toast then ns.Toast.Remove(function(t) return t.theirs ~= nil end) end
    if ns.Panel then ns.Panel.Refresh() end
  end
end

local function sync()
  watch((IsInGroup and IsInGroup()) and true or false)
end

local handlers = {
  GROUP_ROSTER_UPDATE = sync,
  PLAYER_ENTERING_WORLD = sync,
  ENCOUNTER_LOOT_RECEIVED = function(_, _, link, _, player) consider(player, link) end,
  CHAT_MSG_LOOT = onChatLoot,
  GET_ITEM_INFO_RECEIVED = function() retryPending() end,
}

frame:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then Guard.Call(h, ...) end
end)
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Their drops worth asking for, oldest first, while the group lasts.
function GroupLoot.Recent()
  return recent
end

function GroupLoot.Dismiss(rec)
  for i, r in ipairs(recent) do
    if r == rec then table.remove(recent, i) break end
  end
  if ns.Toast then ns.Toast.Remove(function(t) return t.theirs == rec.player and t.link == rec.entry.facts.link end) end
end

-- The ask, for a drop of theirs. Returns text, word, brief.
function GroupLoot.Text(player, f, v)
  local link = f.link or f.name or "?"
  local b = v.brief
  local word = ns.Engine.Headline(v)
  local brief = ns.Engine.BriefLine(v) or v.reason
  if b and b.gain then
    local when = ns.GroupChat.PlainWhen(b)
    return string.format("Sift: %s, %s would be %s for me%s, if you do not need it", player, link, b.gain, when and (" " .. when) or ""), word, brief
  end
  return string.format("Sift: %s, %s would be an upgrade for me, if you do not need it", player, link), word, brief
end

-- Post the ask, or dry-run it.
function GroupLoot.Ask(player, f, v)
  local text, word, brief = GroupLoot.Text(player, f, v)
  return ns.GroupChat.Post(text, { link = f.link, word = word, brief = brief, kind = "ask" })
end

-- For tests: feed one drop as the events would.
function GroupLoot.Consider(player, link)
  consider(player, link)
end

function GroupLoot.Watching()
  return watching
end
