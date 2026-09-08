-- Reads every class's specializations from the client and installs them in
-- the Core/Specs.lua registry. One pass at login; the data is static.
local ADDON, ns = ...

local SpecScan = {}
ns.SpecScan = SpecScan

local MAX_CLASS = 13

local function numSpecs(classID)
  local S = C_SpecializationInfo
  if S and S.GetNumSpecializationsForClassID then return S.GetNumSpecializationsForClassID(classID) end
  if GetNumSpecializationsForClassID then return GetNumSpecializationsForClassID(classID) end
  return nil
end

-- Normalize the two shapes the client uses: a result table (12.0) or a list
-- of returns (id, name, description, icon, role, primaryStat).
local function record(classID, ...)
  local r1 = ...
  if type(r1) == "table" then
    return { classID = classID, id = r1.id or r1.specID, name = r1.name, role = r1.role, primaryStat = r1.primaryStat }
  elseif type(r1) == "number" then
    local _, name, _, _, role, primaryStat = ...
    return { classID = classID, id = r1, name = name, role = role, primaryStat = primaryStat }
  end
  return nil
end

local function readSpec(classID, i, ownClass)
  local S = C_SpecializationInfo
  local rec
  if S and S.GetSpecializationInfo then
    if ownClass then
      rec = record(classID, S.GetSpecializationInfo(i))
    else
      rec = record(classID, S.GetSpecializationInfo(i, false, false, nil, nil, nil, classID))
    end
  end
  if (not rec or not rec.id) and S and S.GetSpecializationInfoForClassID then
    rec = record(classID, S.GetSpecializationInfoForClassID(classID, i))
  end
  if (not rec or not rec.id) and GetSpecializationInfoForClassID then
    rec = record(classID, GetSpecializationInfoForClassID(classID, i))
  end
  if (not rec or not rec.id) and ownClass and GetSpecializationInfo then
    rec = record(classID, GetSpecializationInfo(i))
  end
  return rec
end

-- Raw client records for every class. Records for another class that turn
-- out to be the player's own specs (the classID argument was ignored) are
-- dropped here so a duplicate never reaches the registry.
function SpecScan.Read()
  local _, _, myClass = UnitClass("player")
  local out, seen = {}, {}
  for classID = 1, MAX_CLASS do
    local n = numSpecs(classID) or 0
    for i = 1, n do
      local rec = readSpec(classID, i, classID == myClass)
      if rec and rec.id then
        if seen[rec.id] then
          if seen[rec.id] ~= classID then rec.duplicate = true end
        else
          seen[rec.id] = classID
        end
        if not rec.duplicate then out[#out + 1] = rec end
      end
    end
  end
  return out
end

-- Read, install, persist a compact copy for offline review, and log.
function SpecScan.Load()
  local ok, raw = pcall(SpecScan.Read)
  if not ok then
    ns.Log("spec scan failed: " .. tostring(raw))
    return ns.Specs.Load({})
  end
  local records = {}
  for _, r in ipairs(raw) do
    local rec = ns.Specs.FromClient(r)
    if rec then records[#records + 1] = rec end
  end
  local summary = ns.Specs.Load(records)
  if ns.db then
    local list = {}
    for _, rec in ipairs(records) do
      list[#list + 1] = { id = rec.id, classID = rec.classID, name = rec.name, primary = rec.primary, role = rec.role }
    end
    table.sort(list, function(a, b) if a.classID ~= b.classID then return a.classID < b.classID end return a.id < b.id end)
    local _, build = GetBuildInfo()
    ns.db.specs = { ts = time(), build = build, list = list, diffs = ns.Specs.Diffs(), rejected = ns.Specs.Rejected(), summary = summary }
  end
  for _, line in ipairs(ns.Specs.DescribeDiffs()) do
    ns.Log("spec data: shipped disagreed with the client on " .. line)
  end
  if summary.rejected > 0 then
    ns.Log(string.format("spec data: %d client records rejected (class id argument not honored)", summary.rejected))
  end
  if ns.Character then ns.Character.Invalidate() end
  return summary
end

-- One line for /sift status.
function SpecScan.Describe()
  local s = ns.db and ns.db.specs and ns.db.specs.summary
  if not s or s.source ~= "client" then
    return "spec data: shipped tables (the client gave nothing)"
  end
  local line = string.format("spec data: %d specs from the client, %d with a primary stat", s.specs, s.withPrimary)
  local d = ns.Specs.DescribeDiffs()
  if #d > 0 then
    line = line .. ". Shipped data disagreed on " .. table.concat(d, "; ") .. " (the client wins)"
  else
    line = line .. ", shipped data agrees"
  end
  return line
end
