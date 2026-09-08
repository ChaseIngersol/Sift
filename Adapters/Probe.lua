-- /sift probe: checks the game APIs the adapters depend on (docs/MAINTENANCE.md)
-- and stores the raw findings in SiftLootAdvisorDB.probe for reading after logout.
local ADDON, ns = ...

local Probe = {}
ns.Probe = Probe

local INTERESTING = { [3] = true, [20] = true, [31] = true, [32] = true }

local function copyLine(line)
  local c = {}
  for k, v in pairs(line) do
    if type(v) ~= "table" and type(v) ~= "function" then c[k] = v end
  end
  return c
end

local function inspect(out, desc, link, loc, tooltipFn)
  local rec = { desc = desc, link = link, lines = {} }
  local ok, data = pcall(tooltipFn)
  if ok and type(data) == "table" and type(data.lines) == "table" then
    for _, line in ipairs(data.lines) do
      local text = line.leftText or ""
      if INTERESTING[line.type] or text:find("Cantrip") or text:find("%(%d+/%d+%)") then
        rec.lines[#rec.lines + 1] = copyLine(line)
      end
    end
  end
  if loc and loc:IsValid() then
    rec.bound = C_Item.IsBound(loc)
    if C_Item.IsItemConvertibleAndValidForPlayer then
      rec.catalyst = C_Item.IsItemConvertibleAndValidForPlayer(loc)
    end
  end
  local name, _, _, _, _, _, _, _, equipLoc, _, _, _, _, bindType, _, setID = C_Item.GetItemInfo(link)
  rec.name, rec.equipLoc, rec.bindType, rec.setID = name, equipLoc, bindType, setID
  local f = ns.ItemFacts.Build(link, loc, tooltipFn)
  if f then
    rec.parsed = { track = f.track, rank = f.rank, maxRank = f.maxRank, ilvl = f.ilvl, binding = f.binding, sendable = f.sendable, isTier = f.isTier, hasEffect = f.hasEffect, cantrip = f.cantrip, gems = f.gems, sockets = f.sockets }
    if f.track and f.rank then
      out.growth[#out.growth + 1] = { id = f.id, track = f.track, rank = f.rank, ilvl = f.ilvl, stats = f.stats, flex = f.flex and f.flex.value or nil }
    end
  end
  out.items[#out.items + 1] = rec
  return rec
end

function Probe.Run()
  local version, build = GetBuildInfo()
  local inInstance, instanceType = IsInInstance()
  local out = { ts = time(), version = version, build = build, instance = instanceType, inInstance = inInstance, items = {}, growth = {}, currencies = {} }

  for slot = 1, 17 do
    local link = GetInventoryItemLink("player", slot)
    if link then
      inspect(out, "equipped " .. slot, link, ItemLocation:CreateFromEquipmentSlot(slot), function() return C_TooltipInfo.GetInventoryItem("player", slot) end)
    end
  end
  for bag = 0, 4 do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local _, _, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(info.hyperlink)
        if ns.Slots.IsEquippable(equipLoc) then
          inspect(out, string.format("bag %d slot %d", bag, slot), info.hyperlink, loc, function() return C_TooltipInfo.GetBagItem(bag, slot) end)
        end
      end
    end
  end

  local season = ns.Season
  for id = season.currencyScanRange[1], season.currencyScanRange[2] do
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if info and info.name and (info.name:find(season.crestNamePattern, 1, true) or info.name:find(season.catalystNamePattern, 1, true)) then
      out.currencies[#out.currencies + 1] = { id = id, name = info.name, quantity = info.quantity,
        totalEarned = info.totalEarned, thisWeek = info.quantityEarnedThisWeek, max = info.maxQuantity,
        weekly = info.canEarnPerWeek, discovered = info.discovered, accountWide = info.isAccountWide,
        backpack = info.isShowInBackpack, icon = info.iconFileID, unused = info.isTypeUnused }
    end
  end

  out.specs = ns.db.specs
  out.growth_estimate = select(3, ns.Growth.Resolve(ns.db.season.growth, ns.Season.statGrowth, ns.Season.growthMinSamples, ns.Season.growthSane))
  ns.db.probe.last = out

  local parsed, catalyst, sets, sample = 0, 0, 0, nil
  for _, rec in ipairs(out.items) do
    if rec.parsed and rec.parsed.track then parsed = parsed + 1 end
    if rec.catalyst then catalyst = catalyst + 1 end
    if rec.setID and rec.setID ~= 0 then sets = sets + 1 end
    if not sample then
      for _, line in ipairs(rec.lines) do if line.type == 32 then sample = line end end
    end
  end
  ns.Print(string.format("probe: %d items, %d with an upgrade line parsed, %d catalyst-eligible, %d with a set id, %d currencies matched (%s)",
    #out.items, parsed, catalyst, sets, #out.currencies, inInstance and ("in " .. tostring(instanceType)) or "not in an instance"))
  if sample then
    local keys = {}
    for k, v in pairs(sample) do keys[#keys + 1] = k .. "=" .. tostring(v) end
    table.sort(keys)
    ns.Print("upgrade line fields: " .. table.concat(keys, "  "))
  else
    ns.Print("no ItemUpgradeLevel line (type 32) seen on any item")
  end
  for _, c in ipairs(out.currencies) do
    ns.Print(string.format("currency %d: %s have %d, earned %s total, %s this week, max %s, discovered %s, warband %s, icon %s",
      c.id, c.name, c.quantity or 0, tostring(c.totalEarned), tostring(c.thisWeek), tostring(c.max),
      tostring(c.discovered), tostring(c.accountWide), tostring(c.icon)))
  end
  local gems, sockets, shown = 0, 0, 0
  for _, rec in ipairs(out.items) do
    if rec.parsed and rec.parsed.gems then gems = gems + 1 end
    if rec.parsed and rec.parsed.sockets then sockets = sockets + rec.parsed.sockets end
    for _, line in ipairs(rec.lines) do
      if line.type == 3 and shown < 12 then
        shown = shown + 1
        local parsed = {}
        for k, v in pairs((rec.parsed and rec.parsed.gems) or {}) do parsed[#parsed + 1] = k .. " " .. v end
        table.sort(parsed)
        local what = #parsed > 0 and table.concat(parsed, ", ") or ((rec.parsed and rec.parsed.sockets) and "empty" or "nothing parsed")
        ns.Print(string.format("socket line on %s: %q -> %s", rec.name or "?", tostring(line.leftText), what))
        if what == "nothing parsed" or what:find("PRIMARY", 1, true) then
          local statName = tostring(line.leftText):match("^%+[%d,]+%s+(.-)%s*$")
          if statName then ns.Print("  global strings with that text: " .. Probe.GlobalsNamed(statName)) end
        end
      end
    end
  end
  ns.Print(string.format("%d items with a gem read, %d empty sockets", gems, sockets))
  ns.Print(ns.SpecScan.Describe())
  ns.Print(ns.Calibrate.Describe())
  ns.Print("full dump lands in SavedVariables as SiftLootAdvisorDB.probe.last after /reload or logout")
end

-- Names of global strings whose value is exactly text, for pinning a
-- locale-safe token. Walks _G, so probe use only.
function Probe.GlobalsNamed(text)
  local names = {}
  for k, v in pairs(_G) do
    if type(k) == "string" and v == text and (k:find("^ITEM_MOD_") or k:find("^STAT_") or k:find("PRIMARY")) then
      names[#names + 1] = k
    end
  end
  table.sort(names)
  return #names > 0 and table.concat(names, ", ") or "none"
end

function Probe.Watch(flag)
  ns.db.probe.watch = flag and true or nil
  ns.Triggers.SyncWakeEvents()
  ns.Print(flag and "logging interaction frame types; open the bank, a vendor and the upgrade NPC" or "stopped logging interactions")
end
