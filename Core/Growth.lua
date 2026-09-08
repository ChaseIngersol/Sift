-- Live calibration of per-level stat growth from items seen in the same
-- slot at different item levels. Pure Lua: takes a store table the adapter
-- persists, returns growth factors by stat class.
local _, ns = ...

local Growth = {}
ns.Growth = Growth

Growth.MAX_PER_GROUP = 8
Growth.MAX_GROUPS = 48
Growth.MIN_GAP = 3

local CLASS_KEYS = {
  primary = { STRENGTH = true, AGILITY = true, INTELLECT = true },
  secondary = { CRIT = true, HASTE = true, MASTERY = true, VERSATILITY = true },
  stamina = { STAMINA = true },
  armor = { ARMOR = true },
  dps = { DPS = true },
  tertiary = { LEECH = true, AVOIDANCE = true, SPEED = true, INDESTRUCTIBLE = true },
}
Growth.CLASSES = { "primary", "secondary", "stamina", "armor", "dps", "tertiary" }

local function groupKey(item)
  local loc = item.equipLoc
  if loc == "INVTYPE_ROBE" then loc = "INVTYPE_CHEST" end
  return string.format("%s:%s:%s", tostring(loc), tostring(item.classID), tostring(item.subclassID))
end

-- Stat totals by class for one item. Gems are excluded: they do not scale.
function Growth.Totals(item)
  local t = {}
  for key, amount in pairs(item.stats or {}) do
    for class, keys in pairs(CLASS_KEYS) do
      if keys[key] then t[class] = (t[class] or 0) + amount end
    end
  end
  if item.flex and item.flex.value then t.primary = (t.primary or 0) + item.flex.value end
  return t
end

-- Record an item. store.groups[key] holds up to MAX_PER_GROUP observations
-- with distinct item levels (a repeat level replaces the older one).
-- Returns true when the store changed.
function Growth.Observe(store, item)
  if type(store) ~= "table" or type(item) ~= "table" then return false end
  if not item.ilvl or item.ilvl <= 0 or not item.equipLoc or item.equipLoc == "" then return false end
  local totals = Growth.Totals(item)
  if next(totals) == nil then return false end
  store.groups = store.groups or {}
  local key = groupKey(item)
  local group = store.groups[key]
  if not group then
    local n = 0
    for _ in pairs(store.groups) do n = n + 1 end
    if n >= Growth.MAX_GROUPS then return false end
    group = {}
    store.groups[key] = group
  end
  local obs = { ilvl = item.ilvl, id = item.id }
  for class, v in pairs(totals) do obs[class] = v end
  for i, existing in ipairs(group) do
    if existing.ilvl == item.ilvl then
      local same = true
      for _, class in ipairs(Growth.CLASSES) do
        if (existing[class] or 0) ~= (obs[class] or 0) then same = false end
      end
      if same then return false end
      group[i] = obs
      store.dirty = true
      return true
    end
  end
  group[#group + 1] = obs
  while #group > Growth.MAX_PER_GROUP do table.remove(group, 1) end
  store.dirty = true
  return true
end

local function median(list)
  table.sort(list)
  local n = #list
  if n == 0 then return nil end
  if n % 2 == 1 then return list[(n + 1) / 2] end
  return (list[n / 2] + list[n / 2 + 1]) / 2
end

-- Per-level growth estimate by class from every same-group pair with an
-- item level gap of at least MIN_GAP. Returns { class = { value, samples } }.
function Growth.Estimate(store, sane)
  local lists = {}
  local lo, hi = (sane and sane[1]) or 1.0, (sane and sane[2]) or 1.03
  for _, group in pairs((store and store.groups) or {}) do
    for i = 1, #group do
      for j = i + 1, #group do
        local a, b = group[i], group[j]
        if a.ilvl > b.ilvl then a, b = b, a end
        local gap = b.ilvl - a.ilvl
        if gap >= Growth.MIN_GAP then
          for _, class in ipairs(Growth.CLASSES) do
            local x, y = a[class], b[class]
            if x and y and x > 0 and y > 0 then
              local g = (y / x) ^ (1 / gap)
              if g >= lo and g <= hi then
                lists[class] = lists[class] or {}
                lists[class][#lists[class] + 1] = g
              end
            end
          end
        end
      end
    end
  end
  local out = {}
  for class, list in pairs(lists) do
    out[class] = { value = median(list), samples = #list }
  end
  return out
end

-- Seeds overridden by live estimates with enough samples. Returns growth
-- table by class plus a source table ("seed" or "live") by class.
function Growth.Resolve(store, seeds, minSamples, sane)
  local est = Growth.Estimate(store, sane)
  local out, source = {}, {}
  for class, seed in pairs(seeds or {}) do
    local e = est[class]
    if e and e.samples >= (minSamples or 3) then
      out[class], source[class] = e.value, "live"
    else
      out[class], source[class] = seed, "seed"
    end
  end
  return out, source, est
end
