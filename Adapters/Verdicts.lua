-- Session cache of verdicts by item GUID, persistence of holds, and
-- re-evaluation when inputs change.
local ADDON, ns = ...

local Verdicts = {}
ns.Verdicts = Verdicts

local byGuid = {}
local byLink = {}
local linkOrder = {}
local MAX_LINK = 64
local sessionDispose = {}
local sessionEquip = {}

-- What this character is holding, as competitors for the item's slot
-- (Engine: competeHeld). Facts come from the bags; a re-evaluation pass
-- caches them so n holds cost n reads rather than n squared.
local passFacts = nil
local function heldFor(facts)
  local out = {}
  for _, h in ipairs(Verdicts.MyHolds()) do
    if h.loc and h.guid ~= facts.guid and h.hold.kind == ns.Engine.KIND.HOLD then
      local f = passFacts and passFacts[h.guid]
      if f == nil then
        local cached = byGuid[h.guid]
        f = (cached and cached.facts) or ns.ItemFacts.FromBag(h.loc.bag, h.loc.slot) or false
        if passFacts then passFacts[h.guid] = f end
      end
      if f then out[#out + 1] = { item = f, sub = h.hold.sub, guid = h.guid } end
    end
  end
  return out
end

local function context(facts)
  local me = ns.Character.Self()
  ns.Calibrate.Observe(facts)
  -- Only what the character owns raises a slot watermark: a chat link or
  -- a vault offer is not in hand.
  if facts.guid then ns.Character.ObserveWatermark(facts) end
  for _, f in pairs(me.slots or {}) do ns.Calibrate.Observe(f) end
  return {
    item = facts,
    self = me,
    alts = ns.Character.Alts(),
    held = heldFor(facts),
    res = ns.Resources.Current(),
    prefs = ns.DB.Prefs(),
    season = ns.Calibrate.Season(),
  }
end

function Verdicts.Evaluate(facts)
  return ns.Engine.Evaluate(context(facts))
end

local function remember(facts, v)
  local entry = { facts = facts, verdict = v, ts = GetTime() }
  if facts.guid then
    byGuid[facts.guid] = entry
  elseif facts.link then
    if not byLink[facts.link] then
      linkOrder[#linkOrder + 1] = facts.link
      while #linkOrder > MAX_LINK do
        local old = table.remove(linkOrder, 1)
        byLink[old] = nil
      end
    end
    byLink[facts.link] = entry
  end
  if facts.guid then
    sessionDispose[facts.guid] = (v.kind == ns.Engine.KIND.DISPOSE) and entry or nil
    sessionEquip[facts.guid] = (v.kind == ns.Engine.KIND.EQUIP) and entry or nil
  end
  return entry
end

function Verdicts.Get(guid)
  return guid and byGuid[guid] or nil
end

function Verdicts.GetByLink(link)
  return link and byLink[link] or nil
end

function Verdicts.InvalidateAll()
  byGuid = {}
  byLink = {}
  linkOrder = {}
end

-- Evaluate the item in a bag slot. force bypasses the cache.
function Verdicts.ForBag(bag, slot, force)
  local facts, why = ns.ItemFacts.FromBag(bag, slot)
  if not facts then return nil, why end
  if not force and facts.guid and byGuid[facts.guid] then return byGuid[facts.guid] end
  if not ns.ItemFacts.IsCandidate(facts, ns.DB.Prefs()) then return nil, "not a candidate" end
  local v = Verdicts.Evaluate(facts)
  return remember(facts, v)
end

-- Evaluate a bare link (chat, vendor, loot roll). Cached by link.
function Verdicts.ForLink(link, force)
  if not force and byLink[link] then return byLink[link] end
  local facts, why = ns.ItemFacts.FromLink(link)
  if not facts then return nil, why end
  if not ns.ItemFacts.IsCandidate(facts, ns.DB.Prefs()) then return nil, "not a candidate" end
  local v = Verdicts.Evaluate(facts)
  return remember(facts, v)
end

-- Holds are the persisted list the panel and wake conditions work from.
local function holdRecord(facts, v)
  return {
    owner = ns.Character.Key(), link = facts.link, name = facts.name, icon = facts.icon,
    quality = facts.quality, ilvl = facts.ilvl, kind = v.kind, sub = v.sub, reason = v.reason,
    ready = v.ready or false, wake = v.wake, notes = v.notes, ts = time(),
    target = v.target and v.target.char and v.target.char.name or nil,
    targetKey = v.target and v.target.char and v.target.char.key or nil,
    equipLoc = facts.equipLoc, track = facts.track,
    instead = v.instead,
    gain = ns.Engine.Gain(v),
    brief = v.brief,
    noSim = v.flags and v.flags.noSim or nil,
  }
end

-- The character key a SEND verdict points at, nil for anything else.
function Verdicts.SendKey(v)
  if not v or v.kind ~= ns.Engine.KIND.SEND then return nil end
  return v.target and v.target.char and v.target.char.key or nil
end

function Verdicts.SyncHold(facts, v)
  if not facts.guid then return end
  local holds = ns.db.holds
  local K = ns.Engine.KIND
  if v.kind == K.HOLD or v.kind == K.SEND then
    local prev = holds[facts.guid]
    local rec = holdRecord(facts, v)
    -- A send keeps its progress across re-evaluations while it still
    -- points at the same character.
    if v.kind == K.SEND and prev and prev.kind == K.SEND and prev.send and prev.targetKey == rec.targetKey then
      rec.send = prev.send
    end
    holds[facts.guid] = rec
  else
    holds[facts.guid] = nil
  end
end

-- Send lifecycle. A SEND hold is advice ("suggested") until the player
-- marks it ("sending") or the item is seen in a warband tab ("banked").
function Verdicts.SendState(hold)
  return (hold and hold.send and hold.send.state) or "suggested"
end

function Verdicts.AckSend(guid)
  local h = ns.db.holds[guid]
  if not h or h.kind ~= ns.Engine.KIND.SEND then return false end
  h.send = { state = "sending", ts = time() }
  return true
end

function Verdicts.MarkBanked(guid, tab)
  local h = ns.db.holds[guid]
  if not h or h.kind ~= ns.Engine.KIND.SEND then return false end
  h.send = { state = "banked", ts = time(), tab = tab }
  return true
end

function Verdicts.ResetSend(guid)
  local h = ns.db.holds[guid]
  if h then h.send = nil end
end

-- Sends pointed at this character that are under way, guid -> hold.
-- A suggestion nobody has acted on is not one of them.
function Verdicts.SendsForMe()
  local me, myName = ns.Character.Key(), UnitName("player")
  local out = {}
  for guid, h in pairs(ns.db.holds) do
    if h.kind == ns.Engine.KIND.SEND and h.owner ~= me and Verdicts.SendState(h) ~= "suggested"
      and (h.targetKey == me or (not h.targetKey and h.target == myName)) then
      out[guid] = h
    end
  end
  return out
end

function Verdicts.ClearHold(guid)
  if guid then ns.db.holds[guid] = nil end
end

-- guid -> { bag, slot } for everything currently in bags.
function Verdicts.LocateInBags()
  local map = {}
  for bag = 0, 4 do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if loc:IsValid() then
          local guid = C_Item.GetItemGUID(loc)
          if guid then map[guid] = { bag = bag, slot = slot } end
        end
      end
    end
  end
  return map
end

-- Holds owned by this character, with their bag location if still held.
function Verdicts.MyHolds()
  local me = ns.Character.Key()
  local where = Verdicts.LocateInBags()
  local out = {}
  for guid, h in pairs(ns.db.holds) do
    if h.owner == me then
      out[#out + 1] = { guid = guid, hold = h, loc = where[guid] }
    end
  end
  table.sort(out, function(a, b) return (a.hold.ts or 0) > (b.hold.ts or 0) end)
  return out
end

function Verdicts.SessionDispose()
  local where = Verdicts.LocateInBags()
  local out = {}
  for guid, entry in pairs(sessionDispose) do
    if where[guid] then out[#out + 1] = { guid = guid, entry = entry, loc = where[guid] } end
  end
  return out
end

function Verdicts.SessionEquip()
  local where = Verdicts.LocateInBags()
  local out = {}
  for guid, entry in pairs(sessionEquip) do
    if where[guid] then out[#out + 1] = { guid = guid, entry = entry, loc = where[guid] } end
  end
  return out
end

-- Re-run every hold this character owns. Returns a list of transitions
-- { old = oldRecord, facts = facts, verdict = v } where the verdict kind,
-- sub or readiness changed. Holds whose item left the bags are dropped
-- silently: the player dealt with it. Session disposes that lost to a held
-- piece get another look too, since the winner may have left.
function Verdicts.ReevaluateHolds()
  local transitions, seen = {}, {}
  passFacts = {}
  for _, h in ipairs(Verdicts.MyHolds()) do
    seen[h.guid] = true
    if not h.loc then
      -- A send already in the warband bank stays on record until it is
      -- picked up; while a bank is open, a send that just left the bags
      -- is judged by the bank scan instead.
      local send = h.hold.kind == ns.Engine.KIND.SEND
      if not (send and (Verdicts.SendState(h.hold) == "banked" or (ns.Bank and ns.Bank.IsOpen()))) then
        ns.db.holds[h.guid] = nil
      end
    else
      local entry = Verdicts.ForBag(h.loc.bag, h.loc.slot, true)
      if entry then
        passFacts[h.guid] = entry.facts
        local old, v = h.hold, entry.verdict
        Verdicts.SyncHold(entry.facts, v)
        local changed = old.kind ~= v.kind or old.sub ~= v.sub or (old.ready or false) ~= (v.ready or false)
        if changed then
          transitions[#transitions + 1] = { old = old, facts = entry.facts, verdict = v }
        end
      end
    end
  end
  for _, d in ipairs(Verdicts.SessionDispose()) do
    if not seen[d.guid] and d.entry.verdict.flags and d.entry.verdict.flags.outclassed then
      local entry = Verdicts.ForBag(d.loc.bag, d.loc.slot, true)
      if entry and entry.verdict.kind ~= ns.Engine.KIND.DISPOSE then
        Verdicts.SyncHold(entry.facts, entry.verdict)
        transitions[#transitions + 1] = { old = { kind = ns.Engine.KIND.DISPOSE }, facts = entry.facts, verdict = entry.verdict }
      end
    end
  end
  passFacts = nil
  return transitions
end

-- Evaluate every candidate in bags. Returns list of entries. Holds found
-- early in the scan could not see holds found later, so a second pass over
-- the holds settles who owns each slot before anything is announced.
function Verdicts.ScanAll()
  local out, index = {}, {}
  passFacts = {}
  for bag = 0, 4 do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local entry = Verdicts.ForBag(bag, slot, true)
      if entry then
        Verdicts.SyncHold(entry.facts, entry.verdict)
        if entry.facts.guid then passFacts[entry.facts.guid] = entry.facts end
        out[#out + 1] = entry
        if entry.facts.guid then index[entry.facts.guid] = #out end
      end
    end
  end
  for _, t in ipairs(Verdicts.ReevaluateHolds()) do
    local i = t.facts.guid and index[t.facts.guid]
    if i then out[i] = { facts = t.facts, verdict = t.verdict, ts = out[i].ts } end
  end
  return out
end
