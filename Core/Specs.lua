-- Specialization registry: what the client says about every spec (primary
-- stat, role, name) laid over the shipped data in Core/Data.lua (weapon
-- model, stat priorities). The client is the authority for primary stat and
-- role; shipped data fills in what the client cannot say. Pure Lua.
local _, ns = ...

local Specs = {}
ns.Specs = Specs

-- LE_UNIT_STAT_* values carried by the client's primaryStat field.
Specs.PRIMARY_BY_STAT = { [1] = "STRENGTH", [2] = "AGILITY", [4] = "INTELLECT" }
Specs.ROLE_BY_CLIENT = { DAMAGER = "dps", TANK = "tank", HEALER = "heal" }

local registry = nil
local diffs = {}
local rejected = {}
local source = "shipped"

-- Canonical record from one raw client record. Returns nil, reason when the
-- record cannot be used at all.
function Specs.FromClient(raw)
  if type(raw) ~= "table" then return nil, "not a table" end
  local id = tonumber(raw.id)
  if not id or id <= 0 then return nil, "no id" end
  local classID = tonumber(raw.classID)
  if not classID then return nil, "no class" end
  local rec = { id = id, classID = classID, name = raw.name }
  local ps = tonumber(raw.primaryStat)
  if ps then rec.primary = Specs.PRIMARY_BY_STAT[ps] end
  if type(raw.role) == "string" then rec.role = Specs.ROLE_BY_CLIENT[raw.role] or nil end
  return rec
end

local function clone(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- Build a registry from a list of canonical client records (Specs.FromClient
-- output). Returns registry, diffs, rejected where diffs lists every field on
-- which shipped data disagreed with the client (the client wins) and rejected
-- lists records that contradict the shipped class for that spec id, which
-- means the classID argument was not honored and the record is garbage.
function Specs.Build(records)
  local shipped = ns.Data.specs
  local out, d, rej = {}, {}, {}
  for id, s in pairs(shipped) do
    local c = clone(s)
    c.source = "shipped"
    out[id] = c
  end
  for _, rec in ipairs(records or {}) do
    local base = shipped[rec.id]
    if base and base.classID ~= rec.classID then
      rej[#rej + 1] = { id = rec.id, shippedClass = base.classID, clientClass = rec.classID }
    else
      local spec = out[rec.id]
      if not spec then
        spec = { id = rec.id, classID = rec.classID, name = rec.name or ("Spec " .. rec.id), model = nil, priority = {}, unknown = true }
        out[rec.id] = spec
      end
      spec.source = "client"
      for _, field in ipairs({ "primary", "role" }) do
        local value = rec[field]
        if value then
          if base and base[field] ~= value then
            d[#d + 1] = { id = rec.id, name = base.name, field = field, shipped = base[field], client = value }
          end
          spec[field] = value
        elseif base then
          spec[field .. "Source"] = "shipped"
        end
      end
      if rec.name and rec.name ~= "" then spec.name = rec.name end
    end
  end
  return out, d, rej
end

-- Install a registry built from client records. Returns a summary.
function Specs.Load(records)
  local reg, d, rej = Specs.Build(records)
  local fromClient, withPrimary = 0, 0
  for _, s in pairs(reg) do
    if s.source == "client" then
      fromClient = fromClient + 1
      if s.primary and s.primarySource ~= "shipped" then withPrimary = withPrimary + 1 end
    end
  end
  if fromClient > 0 then
    registry, diffs, rejected, source = reg, d, rej, "client"
  else
    registry, diffs, rejected, source = nil, {}, rej, "shipped"
  end
  return { specs = fromClient, withPrimary = withPrimary, diffs = #d, rejected = #rej, source = source }
end

function Specs.Reset()
  registry, diffs, rejected, source = nil, {}, {}, "shipped"
end

function Specs.Source() return source end
function Specs.Diffs() return diffs end
function Specs.Rejected() return rejected end

function Specs.Get(id)
  if not id then return nil end
  if registry then return registry[id] end
  return ns.Data.specs[id]
end

function Specs.All()
  return registry or ns.Data.specs
end

function Specs.ForClass(classID)
  local out = {}
  for id, s in pairs(Specs.All()) do
    if s.classID == classID then out[#out + 1] = s end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

local function squash(name)
  return (name:lower():gsub("%s+", ""))
end

function Specs.FindByName(classID, name)
  if not classID or not name then return nil end
  local lname = squash(name)
  for id, s in pairs(Specs.All()) do
    if s.classID == classID and s.name and squash(s.name) == lname then return id, s end
  end
  -- A renamed spec still matches its shipped name.
  local sid, s = ns.Data.FindSpecByName(classID, name)
  if sid then return sid, Specs.Get(sid) or s end
  return nil
end

-- One line per disagreement, for status output and the log.
function Specs.DescribeDiffs()
  local lines = {}
  local Stats = ns.Stats
  for _, x in ipairs(diffs) do
    local function label(v)
      if x.field == "primary" then return Stats.LABEL[v] or tostring(v) end
      return tostring(v)
    end
    lines[#lines + 1] = string.format("%s %s: shipped %s, client %s", x.name or tostring(x.id), x.field, label(x.shipped), label(x.client))
  end
  return lines
end
