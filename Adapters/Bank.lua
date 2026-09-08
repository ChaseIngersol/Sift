-- The warband bank as Sift sees it, and the send lifecycle that hangs
-- off it.
--
-- A send is advice ("suggested") until something happens: the player
-- marks it on the panel ("sending"), or the item turns up in a warband
-- bank tab ("banked"). Item GUIDs survive the trip through the bank, so
-- seeing one in a tab is proof; seeing it gone again while a bank is
-- open means someone took it out. If it is in this character's bags now,
-- this character's own verdict takes over; otherwise the record is
-- dropped. The tabs read like bags, but only while a bank is open, so
-- everything here runs between BANKFRAME_OPENED and BANKFRAME_CLOSED.
local ADDON, ns = ...

local Bank = {}
ns.Bank = Bank

local open = false
local lastInfo = nil -- what the last tab read could see: { tabs, slots, items }

function Bank.IsOpen() return open end

local function debugging()
  return ns.db and ns.db.prefs and ns.db.prefs.debug
end

local function accountType()
  return (Enum and Enum.BankType and Enum.BankType.Account) or 1
end

-- Bag ids of the purchased warband tabs; empty when the client will not say.
function Bank.TabIDs()
  if not (C_Bank and C_Bank.FetchPurchasedBankTabIDs) then return {} end
  local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, accountType())
  if ok and type(ids) == "table" then return ids end
  return {}
end

-- guid -> { tab, slot, link } for everything in the warband tabs, plus
-- how much could be read: { tabs, slots, items }. Zero slots means the
-- client showed nothing, not that the tabs are empty.
function Bank.Locate()
  local map = {}
  local info = { tabs = 0, slots = 0, items = 0 }
  for _, tab in ipairs(Bank.TabIDs()) do
    info.tabs = info.tabs + 1
    local n = C_Container.GetContainerNumSlots(tab) or 0
    info.slots = info.slots + n
    for slot = 1, n do
      local item = C_Container.GetContainerItemInfo(tab, slot)
      if item and item.hyperlink then
        local loc = ItemLocation:CreateFromBagAndSlot(tab, slot)
        if loc:IsValid() then
          local guid = C_Item.GetItemGUID(loc)
          if guid then
            map[guid] = { tab = tab, slot = slot, link = item.hyperlink }
            info.items = info.items + 1
          end
        end
      end
    end
  end
  return map, info
end

local function firstName(key)
  return key and (key:match("^(.-)%-") or key) or "another character"
end

-- An item link with the viewer-dependent fields blanked (unique id,
-- link level, spec), so the same piece seen by two characters, or after
-- the bank re-instanced it, compares equal.
function Bank.LinkKey(link)
  if type(link) ~= "string" then return nil end
  local payload = link:match("|Hitem:([^|]+)|h") or link:match("^item:(.+)$")
  if not payload then return nil end
  local parts = {}
  for field in (payload .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = field end
  if #parts < 10 then return payload end
  parts[8], parts[9], parts[10] = "", "", ""
  return table.concat(parts, ":")
end

-- Match the send records against the tabs. Returns what changed:
-- banked = records that just landed, gone = records that left the bank.
function Bank.Reconcile()
  if not open then return nil end
  local Verdicts = ns.Verdicts
  local found, info = Bank.Locate()
  lastInfo = info
  if debugging() then
    ns.Log("debug", string.format("bank: %d tabs, %d slots, %d items readable", info.tabs, info.slots, info.items))
  end
  local me = ns.Character.Key()
  local inBags
  local byLink -- LinkKey -> { guid, tab }, for items the bank re-instanced
  local changed = { banked = {}, gone = {} }
  local holds = {}
  for guid, hold in pairs(ns.db.holds) do
    if hold.kind == "SEND" then holds[#holds + 1] = { guid = guid, hold = hold } end
  end
  for _, h in ipairs(holds) do
    local guid, hold = h.guid, h.hold
    local state = Verdicts.SendState(hold)
    local hit = found[guid]
    -- My own send, out of my bags, not in the tabs by GUID: the warband
    -- bank may have given it a new GUID on the way in, so look for the
    -- same item by link and move the record to the GUID it has now.
    if not hit and state ~= "banked" and hold.owner == me then
      inBags = inBags or Verdicts.LocateInBags()
      if not inBags[guid] then
        if not byLink then
          byLink = {}
          for g, f in pairs(found) do
            local key = Bank.LinkKey(f.link)
            if key and not ns.db.holds[g] then byLink[key] = byLink[key] or { guid = g, tab = f.tab } end
          end
        end
        local same = byLink[Bank.LinkKey(hold.link) or ""]
        if same then
          ns.db.holds[same.guid] = hold
          ns.db.holds[guid] = nil
          byLink[Bank.LinkKey(hold.link)] = nil
          guid, hit = same.guid, same
        end
      end
    end
    if debugging() then
      ns.Log("debug", string.format("bank: %s (%s) %s, state %s", hold.name or "?", hold.owner or "?",
        hit and ("in tab " .. tostring(hit.tab)) or "not in the tabs", state))
    end
    if hit then
      if state ~= "banked" then
        Verdicts.MarkBanked(guid, hit.tab)
        changed.banked[#changed.banked + 1] = { guid = guid, name = hold.name, link = hold.link, target = hold.target }
      end
    elseif state == "banked" then
        changed.gone[#changed.gone + 1] = { guid = guid, name = hold.name, link = hold.link }
        inBags = inBags or Verdicts.LocateInBags()
        local where = inBags[guid]
        if where then
          -- Back in someone's bags: that character's verdict takes over,
          -- and for the sender that is a fresh suggestion, not a send in
          -- progress.
          Verdicts.ResetSend(guid)
          local entry = Verdicts.ForBag(where.bag, where.slot, true)
          if entry then Verdicts.SyncHold(entry.facts, entry.verdict) else ns.db.holds[guid] = nil end
        else
          ns.db.holds[guid] = nil
        end
      end
  end
  return changed
end

-- Sends of mine still to be put in: in my bags, not yet banked.
function Bank.Deposits()
  local out = {}
  for _, h in ipairs(ns.Verdicts.MyHolds()) do
    if h.loc and h.hold.kind == "SEND" and ns.Verdicts.SendState(h.hold) ~= "banked" then out[#out + 1] = h end
  end
  table.sort(out, function(a, b) return (a.hold.name or "") < (b.hold.name or "") end)
  return out
end

-- Sends to me that are in the bank now.
function Bank.Pickups()
  local out = {}
  for guid, hold in pairs(ns.Verdicts.SendsForMe()) do
    if ns.Verdicts.SendState(hold) == "banked" then out[#out + 1] = { guid = guid, hold = hold } end
  end
  table.sort(out, function(a, b) return (a.hold.name or "") < (b.hold.name or "") end)
  return out
end

-- Toast rows for the reminder. They stick until the bank closes or the
-- item moves; a deposit row compares against the alt's gear on hover.
local function depositRow(h)
  local hold = h.hold
  return {
    icon = hold.icon, headline = "Deposit", quality = hold.quality, link = hold.link, verdict = { kind = "SEND" },
    line = string.format("For %s: put it in the warband bank.", hold.target or "an alt"),
    sticky = true, bank = "deposit", guid = h.guid, altKey = hold.targetKey, equipLoc = hold.equipLoc,
  }
end

local function pickupRow(h)
  local hold = h.hold
  return {
    icon = hold.icon, headline = "Pick up", quality = hold.quality, link = hold.link, verdict = { kind = "SEND" },
    line = string.format("From %s, waiting in the warband bank.", firstName(hold.owner)),
    sticky = true, bank = "pickup", guid = h.guid,
  }
end

-- What to deposit for alts and what is waiting for me: a chat line each,
-- and rows on the toast when the reminder is on.
function Bank.Remind()
  local deposits, pickups = Bank.Deposits(), Bank.Pickups()
  if #deposits > 0 then
    local lines = {}
    for _, h in ipairs(deposits) do
      lines[#lines + 1] = string.format("%s to %s", h.hold.link or h.hold.name, h.hold.target or "an alt")
    end
    ns.Chat("Deposit for alts: " .. table.concat(lines, ", "))
  end
  if #pickups > 0 then
    local lines = {}
    for _, h in ipairs(pickups) do
      lines[#lines + 1] = string.format("%s from %s", h.hold.link or h.hold.name, firstName(h.hold.owner))
    end
    ns.Chat("Waiting for you in the warband bank: " .. table.concat(lines, ", "))
  end
  if ns.db.prefs.bankReminder ~= false and ns.Toast then
    for _, h in ipairs(deposits) do ns.Toast.Show(depositRow(h)) end
    for _, h in ipairs(pickups) do ns.Toast.Show(pickupRow(h)) end
  end
end

local function dropRows(kind, guid)
  if not ns.Toast then return end
  ns.Toast.Remove(function(t) return t.bank ~= nil and (kind == nil or t.bank == kind) and (guid == nil or t.guid == guid) end)
end

-- A bank opened: what is already in a tab counts as banked before the
-- reminder is built, so nothing is asked for twice.
function Bank.Open()
  if open then return end
  open = true
  if ns.Triggers and ns.Triggers.WatchBankClose then ns.Triggers.WatchBankClose() end
  local changed = Bank.Reconcile()
  for _, b in ipairs(changed and changed.banked or {}) do
    ns.Chat(string.format("Already in the warband bank: %s for %s.", b.link or b.name, b.target or "an alt"))
  end
  Bank.Remind()
end

-- Bags changed while a bank is open: sends that landed in a tab leave
-- the reminder, sends taken back out are re-judged or dropped.
function Bank.OnBagUpdate()
  if not open then return end
  local changed = Bank.Reconcile()
  if not changed then return end
  for _, b in ipairs(changed.banked) do
    ns.Chat(string.format("In the warband bank: %s for %s.", b.link or b.name, b.target or "an alt"))
    dropRows("deposit", b.guid)
  end
  for _, g in ipairs(changed.gone) do dropRows("pickup", g.guid) end
end

-- The bank closed: one last look at the tabs, then reminder rows go. A
-- send that left the bags without reaching a warband tab is called out
-- once before the usual re-evaluation drops it; if the client showed no
-- tabs at all this session, it is taken as deposited instead, so a
-- client that will not read the tabs still gets the flow.
function Bank.Close()
  if not open then return end
  local changed = Bank.Reconcile()
  for _, b in ipairs(changed and changed.banked or {}) do
    ns.Chat(string.format("In the warband bank: %s for %s.", b.link or b.name, b.target or "an alt"))
  end
  local readable = lastInfo ~= nil and lastInfo.slots > 0
  local where = ns.Verdicts.LocateInBags()
  for _, h in ipairs(ns.Verdicts.MyHolds()) do
    if h.hold.kind == "SEND" and not where[h.guid] and ns.Verdicts.SendState(h.hold) ~= "banked" then
      if readable then
        ns.Chat(string.format("%s left your bags but is not in the warband bank.", h.hold.link or h.hold.name))
      else
        ns.Verdicts.MarkBanked(h.guid, nil)
        ns.Chat(string.format("%s left your bags at the bank; taking it as deposited for %s (the warband tabs could not be read).",
          h.hold.link or h.hold.name, h.hold.target or "an alt"))
      end
    end
  end
  open = false
  lastInfo = nil
  dropRows()
end

-- /sift probe bank: what the client shows of the warband bank right now.
function Bank.Probe()
  local say = ns.Print
  say(string.format("bank open (Sift): %s; C_Bank: %s; FetchPurchasedBankTabIDs: %s; BankType.Account: %s",
    tostring(open), tostring(C_Bank ~= nil), tostring(C_Bank ~= nil and C_Bank.FetchPurchasedBankTabIDs ~= nil),
    tostring(Enum and Enum.BankType and Enum.BankType.Account)))
  if C_Bank and C_Bank.CanViewBank then
    local ok, can = pcall(C_Bank.CanViewBank, accountType())
    say("CanViewBank(account): " .. tostring(ok and can or can))
  end
  local ids = Bank.TabIDs()
  local idText = {}
  for _, id in ipairs(ids) do idText[#idText + 1] = tostring(id) end
  say("tab ids: " .. (#ids > 0 and table.concat(idText, ", ") or "none"))
  if C_Bank and C_Bank.FetchPurchasedBankTabData then
    local ok, data = pcall(C_Bank.FetchPurchasedBankTabData, accountType())
    if ok and type(data) == "table" then
      for _, t in ipairs(data) do say(string.format("tab data: ID %s, name %s", tostring(t.ID), tostring(t.name))) end
    else
      say("FetchPurchasedBankTabData: " .. tostring(data))
    end
  end
  for _, tab in ipairs(ids) do
    local n = C_Container.GetContainerNumSlots(tab) or 0
    local items, shown = 0, 0
    for slot = 1, n do
      local item = C_Container.GetContainerItemInfo(tab, slot)
      if item then
        items = items + 1
        if shown < 3 then
          shown = shown + 1
          local loc = ItemLocation:CreateFromBagAndSlot(tab, slot)
          local valid = loc and loc.IsValid and loc:IsValid() or false
          say(string.format("  tab %s slot %d: %s, location valid %s, guid %s", tostring(tab), slot, tostring(item.hyperlink),
            tostring(valid), tostring(valid and C_Item.GetItemGUID(loc))))
        end
      end
    end
    say(string.format("tab %s: %d slots, %d items", tostring(tab), n, items))
  end
  local found = Bank.Locate()
  for guid, hold in pairs(ns.db.holds) do
    if hold.kind == "SEND" then
      say(string.format("send %s (%s, state %s): %s", hold.link or hold.name, hold.owner or "?", ns.Verdicts.SendState(hold),
        found[guid] and ("in tab " .. tostring(found[guid].tab)) or "not in the tabs"))
    end
  end
end
