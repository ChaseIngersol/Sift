-- Minimal test runner for Sift's pure-Lua core. No external dependencies.
-- Usage: lua5.1 tests/run.lua [filter]
local script = arg and arg[0] or "tests/run.lua"
local root = script:match("^(.*)/tests/run%.lua$") or "."
package.path = root .. "/?.lua;" .. root .. "/tests/?.lua;" .. package.path

local ns = {}
local function loadAddonFile(rel)
  local chunk, err = loadfile(root .. "/" .. rel)
  if not chunk then error(err, 2) end
  return chunk("Sift", ns)
end

-- Same order as SiftLootAdvisor.toc.
local CORE = {
  "Core/Season.lua", "Core/Stats.lua", "Core/Data.lua", "Core/Specs.lua", "Core/PawnString.lua",
  "Core/Weights.lua", "Core/Scorer.lua", "Core/Growth.lua", "Core/Eligibility.lua", "Core/Slots.lua",
  "Core/Tracks.lua", "Core/Engine.lua", "Core/Vault.lua", "Core/Roll.lua",
}
for _, f in ipairs(CORE) do loadAddonFile(f) end

-- Guard: the core must not touch WoW globals. Any global read that is not a
-- Lua standard is an error while specs run.
local allowed = {}
for k in pairs(_G) do allowed[k] = true end

local passed, failed, failures = 0, 0, {}
local suite = ""
local function serialize(v, depth)
  depth = depth or 0
  if type(v) ~= "table" then return tostring(v) end
  if depth > 3 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k], depth + 1) end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function describe(name, fn)
  suite = name
  fn()
  suite = ""
end

function it(name, fn)
  local filter = arg and arg[1]
  local full = suite .. " > " .. name
  if filter and not full:find(filter, 1, true) then return end
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    failures[#failures + 1] = full .. "\n      " .. tostring(err)
  end
end

function expect(actual)
  local e = {}
  function e.toBe(exp)
    if actual ~= exp then error(string.format("expected %s, got %s", serialize(exp), serialize(actual)), 2) end
  end
  function e.toEqual(exp)
    if not deepEqual(actual, exp) then error(string.format("expected %s, got %s", serialize(exp), serialize(actual)), 2) end
  end
  function e.toBeNil() if actual ~= nil then error("expected nil, got " .. serialize(actual), 2) end end
  function e.toBeTruthy() if not actual then error("expected truthy, got " .. serialize(actual), 2) end end
  function e.toBeFalsy() if actual then error("expected falsy, got " .. serialize(actual), 2) end end
  function e.toBeCloseTo(exp, eps)
    eps = eps or 1e-6
    if type(actual) ~= "number" or math.abs(actual - exp) > eps then
      error(string.format("expected %s within %s, got %s", tostring(exp), tostring(eps), serialize(actual)), 2)
    end
  end
  function e.toContain(needle)
    if type(actual) == "string" then
      if not actual:find(needle, 1, true) then error(string.format("expected %q to contain %q", actual, needle), 2) end
    elseif type(actual) == "table" then
      for _, v in pairs(actual) do if v == needle then return end end
      error("expected table to contain " .. serialize(needle) .. ", got " .. serialize(actual), 2)
    else
      error("toContain needs a string or table", 2)
    end
  end
  function e.toBeGreaterThan(n) if not (type(actual) == "number" and actual > n) then error(string.format("expected > %s, got %s", tostring(n), serialize(actual)), 2) end end
  function e.toBeLessThan(n) if not (type(actual) == "number" and actual < n) then error(string.format("expected < %s, got %s", tostring(n), serialize(actual)), 2) end end
  return e
end

SiftTest = { ns = ns, root = root }

setmetatable(_G, { __index = function(_, k)
  if allowed[k] then return nil end
  error("core touched an undefined global: " .. tostring(k), 2)
end })

local SPECS = {
  "stats_spec", "specs_spec", "pawnstring_spec", "weights_spec", "scorer_spec", "growth_spec",
  "vault_spec", "roll_spec",
  "eligibility_spec", "slots_spec", "tracks_spec", "engine_spec", "weightsdata_spec",
}
for _, s in ipairs(SPECS) do
  local ok, err = pcall(require, s)
  if not ok then
    failed = failed + 1
    failures[#failures + 1] = s .. " (load)\n      " .. tostring(err)
  end
end

print(string.format("%d passed, %d failed", passed, failed))
for _, f in ipairs(failures) do print("  FAIL " .. f) end
os.exit(failed == 0 and 0 or 1)
