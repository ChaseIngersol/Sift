-- Crest and catalyst currencies, with name-based discovery when the season
-- data does not carry IDs yet.
local ADDON, ns = ...

local Resources = {}
ns.Resources = Resources

local discovered = false
local pinOK = {}

-- A pinned id counts only while the client still knows a currency of the
-- expected name under it; after a patch moves the ids, discovery takes over.
local function pinned(id, pattern)
  if not id then return nil end
  local ok = pinOK[id]
  if ok == nil then
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    ok = (info and info.name and info.name:find(pattern, 1, true)) and true or false
    pinOK[id] = ok
  end
  return ok and id or nil
end

-- Manual pick, then the season's pin, then whatever discovery saved.
local function ids()
  local season = ns.Season
  local s = (ns.db and ns.db.season) or {}
  local saved, manual = s.currency or {}, s.manual or {}
  local out = {}
  for _, track in ipairs(season.trackOrder) do
    out[track] = manual[track] or pinned(season.crestCurrency[track], season.crestNamePattern) or saved[track]
  end
  out.catalyst = manual.catalyst or pinned(season.catalystCurrency, season.catalystNamePattern) or saved.catalyst
  return out
end

-- Scan a range of currency IDs once per session and remember matches. The
-- scan runs every login even when picks are saved, because the choice
-- between same-named currencies depends on live fields (section below).
function Resources.Discover(force)
  if discovered and not force then return end
  discovered = true
  local season = ns.Season
  local lo, hi = season.currencyScanRange[1], season.currencyScanRange[2]
  local saved = ns.db.season.currency
  local candidates = ns.db.season.candidates
  local byKey = {}
  for id = lo, hi do
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    local name = info and info.name
    if name and name ~= "" then
      local key
      if name:find(season.crestNamePattern, 1, true) then
        for _, track in ipairs(season.trackOrder) do
          if name:find(track, 1, true) then key = track end
        end
      elseif name:find(season.catalystNamePattern, 1, true) then
        key = "catalyst"
      end
      if key then
        byKey[key] = byKey[key] or {}
        table.insert(byKey[key], { id = id, info = info })
      end
    end
  end
  -- Two currencies can share a name across seasons: the old season's copy
  -- lingers with a leftover quantity but no seasonal tracking (earned 0, cap
  -- 0), while the live one reports what was earned against its cap. Prefer
  -- the tracked one, then the newer id, then one the character has
  -- discovered. Manual picks always win.
  local function tracked(c)
    return ((c.info.totalEarned or 0) > 0 or (c.info.maxQuantity or 0) > 0) and 1 or 0
  end
  local function better(a, b)
    local ta, tb = tracked(a), tracked(b)
    if ta ~= tb then return ta > tb end
    if a.id ~= b.id then return a.id > b.id end
    return (a.info.discovered and 1 or 0) > (b.info.discovered and 1 or 0)
  end
  local found = {}
  for key, list in pairs(byKey) do
    table.sort(list, better)
    local ids = {}
    for i, c in ipairs(list) do ids[i] = c.id end
    candidates[key] = ids
    if saved[key] ~= list[1].id then
      saved[key] = list[1].id
      found[#found + 1] = key .. "=" .. list[1].id .. (#list > 1 and ("(of " .. #list .. ")") or "")
    end
  end
  if #found > 0 then ns.Log("info", "discovered currencies: " .. table.concat(found, ", ")) end
end

-- Every currency sharing the name, with the fields that tell a wallet from
-- a tally, and which one is in use.
function Resources.Candidates(key)
  local list = (ns.db.season.candidates or {})[key] or {}
  local inUse = ids()[key]
  local out = {}
  for _, id in ipairs(list) do
    local info = C_CurrencyInfo.GetCurrencyInfo(id) or {}
    out[#out + 1] = { id = id, quantity = info.quantity or 0, inUse = (id == inUse),
      totalEarned = info.totalEarned, thisWeek = info.quantityEarnedThisWeek, max = info.maxQuantity,
      accountWide = info.isAccountWide, discovered = info.discovered }
  end
  return out
end

function Resources.SetManual(key, id)
  ns.db.season.manual[key] = tonumber(id)
end

-- The icon file id of a crest track or the catalyst, nil when unknown.
function Resources.Icon(key)
  local id = ids()[key]
  if not id then return nil end
  local info = C_CurrencyInfo.GetCurrencyInfo(id)
  return info and info.iconFileID or nil
end

-- { crests = { Champion = n, ... }, catalystCharges = n, missing = {...} }
function Resources.Current()
  local map = ids()
  local out = { crests = {}, catalystCharges = 0, missing = {} }
  for _, track in ipairs(ns.Season.trackOrder) do
    local id = map[track]
    if id then
      local info = C_CurrencyInfo.GetCurrencyInfo(id)
      out.crests[track] = info and info.quantity or 0
    else
      out.crests[track] = 0
      out.missing[#out.missing + 1] = track
    end
  end
  if map.catalyst then
    local info = C_CurrencyInfo.GetCurrencyInfo(map.catalyst)
    out.catalystCharges = info and info.quantity or 0
  else
    out.missing[#out.missing + 1] = "catalyst"
  end
  return out
end

function Resources.Describe()
  local map = ids()
  local parts = {}
  for _, track in ipairs(ns.Season.trackOrder) do
    parts[#parts + 1] = string.format("%s=%s", track, tostring(map[track] or "?"))
  end
  parts[#parts + 1] = "catalyst=" .. tostring(map.catalyst or "?")
  return table.concat(parts, " ")
end
