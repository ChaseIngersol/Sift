-- The current character as the engine sees it, plus snapshots of alts.
local ADDON, ns = ...

local Character = {}
ns.Character = Character

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local selfCache = nil
local altsCache = nil

function Character.Key()
  local name = UnitName("player") or "Unknown"
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName() or ""
  return name .. "-" .. realm
end

function Character.ActiveSpecID()
  local S = C_SpecializationInfo
  local idx
  if S and S.GetSpecialization then idx = S.GetSpecialization() elseif GetSpecialization then idx = GetSpecialization() end
  if not idx then return nil end
  if S and S.GetSpecializationInfo then
    local info = S.GetSpecializationInfo(idx)
    if type(info) == "table" then return info.id end
    if type(info) == "number" then return info end
  end
  if GetSpecializationInfo then return (GetSpecializationInfo(idx)) end
  return nil
end

local function specList(activeID, extraIDs)
  local out, seen = {}, {}
  local active = activeID and ns.Specs.Get(activeID)
  if active then out[1] = active; seen[activeID] = true end
  for _, id in ipairs(extraIDs or {}) do
    local s = ns.Specs.Get(id)
    if s and not seen[id] then out[#out + 1] = s; seen[id] = true end
  end
  return out
end

-- The largest set count across the tier slots, and which set it is.
local function tierCountFromSlots(slots)
  local bySet = {}
  local best, bestSet = 0, nil
  for slot in pairs(ns.Season.tierSlots) do
    local eq = slots[slot]
    if eq and eq.setID and eq.setID ~= 0 then
      bySet[eq.setID] = (bySet[eq.setID] or 0) + 1
      if bySet[eq.setID] > best then best, bestSet = bySet[eq.setID], eq.setID end
    end
  end
  return best, bestSet
end

function Character.Invalidate()
  selfCache = nil
end

function Character.InvalidateAlts()
  altsCache = nil
end

-- Highest item level seen per slot family on this character, from every
-- item Sift reads (equipped or in bags). The game waives crests up to it.
function Character.ObserveWatermark(facts)
  if not facts or not facts.ilvl or facts.ilvl <= 0 then return false end
  local group = ns.Tracks.WatermarkGroup(facts.equipLoc)
  if not group or not ns.db then return false end
  local key = Character.Key()
  ns.db.watermarks[key] = ns.db.watermarks[key] or {}
  local marks = ns.db.watermarks[key]
  if (marks[group] or 0) >= facts.ilvl then return false end
  marks[group] = facts.ilvl
  if selfCache then selfCache.watermarks = marks end
  return true
end

-- Full context for the engine. Cached until Invalidate().
function Character.Self()
  if selfCache then return selfCache end
  local _, _, classID = UnitClass("player")
  local slots = {}
  for _, slot in ipairs(EQUIP_SLOTS) do
    local f = ns.ItemFacts.FromEquipped(slot)
    if f then slots[slot] = f end
  end
  local cdb = ns.cdb or {}
  local key = Character.Key()
  ns.db.watermarks[key] = ns.db.watermarks[key] or {}
  local tierCount, tierSetID = tierCountFromSlots(slots)
  selfCache = {
    key = key, name = UnitName("player"), realm = GetRealmName(),
    classID = classID, level = UnitLevel("player") or 0,
    specs = specList(Character.ActiveSpecID(), cdb.extraSpecs),
    slots = slots, tierCount = tierCount, tierSetID = tierSetID,
    importedWeights = cdb.imported, parked = cdb.parked or false,
    watermarks = ns.db.watermarks[key],
  }
  for _, f in pairs(slots) do Character.ObserveWatermark(f) end
  return selfCache
end

-- Persist this character for other characters to route against.
function Character.Snapshot()
  local me = Character.Self()
  local compact = {}
  for slot, f in pairs(me.slots) do compact[slot] = ns.ItemFacts.Compact(f) end
  local specIDs = {}
  for _, s in ipairs(me.specs) do specIDs[#specIDs + 1] = s.id end
  local _, classFile = UnitClass("player")
  ns.db.chars[me.key] = {
    name = me.name, realm = me.realm, classID = me.classID, classFile = classFile,
    level = me.level, specIDs = specIDs, slots = compact, tierCount = me.tierCount, tierSetID = me.tierSetID,
    importedWeights = me.importedWeights, parked = me.parked, updated = time(),
  }
  altsCache = nil
end

function Character.Alts()
  if altsCache then return altsCache end
  local out = {}
  local myKey = Character.Key()
  for key, snap in pairs(ns.db.chars or {}) do
    if key ~= myKey then
      out[#out + 1] = {
        key = key, name = snap.name, realm = snap.realm, classID = snap.classID,
        classFile = snap.classFile, level = snap.level or 0,
        specs = specList(snap.specIDs and snap.specIDs[1], snap.specIDs and { unpack(snap.specIDs, 2) }),
        slots = snap.slots or {}, tierCount = snap.tierCount or 0, tierSetID = snap.tierSetID,
        importedWeights = snap.importedWeights, parked = snap.parked or false,
        updated = snap.updated,
      }
    end
  end
  table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
  altsCache = out
  return out
end

function Character.SetParked(flag)
  ns.cdb.parked = flag and true or false
  Character.Invalidate()
  Character.Snapshot()
end

-- Average equipped item level, for status lines.
function Character.AverageIlvl(char)
  local total, n = 0, 0
  for _, f in pairs((char and char.slots) or {}) do
    if f.ilvl and f.ilvl > 0 then total = total + f.ilvl; n = n + 1 end
  end
  if n == 0 then return 0 end
  return math.floor(total / n + 0.5)
end

-- What is worn right now, per slot, so a later look can count changes.
local function gearFingerprint(char)
  local out = {}
  for slot, f in pairs(char.slots or {}) do
    out[slot] = string.format("%s:%s", tostring(f.id), tostring(f.ilvl))
  end
  return out
end

Character.STALE_DAYS = 14
Character.STALE_SLOTS = 4

-- Import a Pawn string for this character. Returns ok, message.
function Character.ImportWeights(str)
  local parsed, err = ns.PawnString.Parse(str)
  if not parsed then return false, err end
  local _, _, classID = UnitClass("player")
  if parsed.classID and parsed.classID ~= classID then
    return false, string.format("that string is for a %s", ns.Data.classes[parsed.classID].name)
  end
  local specID = parsed.specID or Character.ActiveSpecID()
  if not specID then return false, "could not tell which spec the string is for" end
  ns.cdb.imported[specID] = { name = parsed.name, weights = parsed.weights, ts = time(), gear = gearFingerprint(Character.Self()) }
  Character.Invalidate()
  Character.Snapshot()
  local spec = ns.Specs.Get(specID)
  return true, string.format("imported %q for %s", parsed.name, spec and spec.name or tostring(specID))
end

-- Where this character's weights for a spec come from and how fresh they
-- are. Returns { source, spec, name, ts, ageDays, changed, stale, profile,
-- generated }.
function Character.WeightsStatus(specID)
  local me = Character.Self()
  specID = specID or (me.specs[1] and me.specs[1].id)
  local spec = ns.Specs.Get(specID)
  local out = { specID = specID, spec = spec, source = "shipped" }
  if not spec then return out end
  local _, source = ns.Weights.Resolve(spec, me.importedWeights)
  out.source = source
  if source == "imported" then
    local entry = me.importedWeights[specID]
    out.name = entry.name
    out.ts = entry.ts
    out.ageDays = entry.ts and math.floor((time() - entry.ts) / 86400) or nil
    local changed = 0
    local now = gearFingerprint(me)
    for slot, v in pairs(now) do
      if not entry.gear or entry.gear[slot] ~= v then changed = changed + 1 end
    end
    out.changed = entry.gear and changed or nil
    out.stale = (out.ageDays or 0) >= Character.STALE_DAYS or (out.changed or 0) >= Character.STALE_SLOTS
  elseif source == "simc" then
    local _, entry = ns.Weights.FromSimC(spec)
    out.profile = entry and entry.profile
    out.generated = ns.WeightsData and ns.WeightsData.generated
  end
  return out
end

-- One sentence about the weights in use, for the panel footer and status.
function Character.DescribeWeights(specID)
  local st = Character.WeightsStatus(specID)
  local name = st.spec and st.spec.name or "this spec"
  if st.source == "imported" then
    local age = st.ageDays and (st.ageDays == 0 and "today" or st.ageDays == 1 and "yesterday" or string.format("%d days ago", st.ageDays)) or ""
    local changed = st.changed and st.changed > 0 and string.format(", %d slot%s changed since", st.changed, st.changed == 1 and "" or "s") or ""
    local line = string.format("Your weights for %s: %q, %s%s.", name, st.name or "imported", age, changed)
    if st.stale then line = line .. " Time for a fresh sim." end
    return line, st
  elseif st.source == "simc" then
    return string.format("SimulationCraft defaults for %s (%s). Your own sim will beat them.", name, st.generated or "generated"), st
  end
  if st.spec and st.spec.role == "heal" then
    return string.format("Rough stat priorities for %s. Raidbots does not sim healing; any Pawn string replaces them.", name), st
  end
  return string.format("Rough stat priorities for %s, no sim data. Paste your Raidbots weights.", name), st
end

-- At most one chat reminder a day when imported weights have gone stale.
function Character.StaleNudge()
  local line, st = Character.DescribeWeights()
  if not st.stale then return false end
  local last = ns.cdb.lastStaleNudge or 0
  if time() - last < 86400 then return false end
  ns.cdb.lastStaleNudge = time()
  ns.Chat(line .. " /sift weights")
  return true
end

function Character.ClearWeights(specID)
  if specID then ns.cdb.imported[specID] = nil else ns.cdb.imported = {} end
  Character.Invalidate()
  Character.Snapshot()
end
