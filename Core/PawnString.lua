-- Parser for the Pawn-string stat weight format emitted by Raidbots and
-- SimulationCraft. This is a text format; the Pawn addon is not involved.
--   ( Pawn: v1: "Name": Class=Warrior, Spec=Fury, Strength=1.00, CritRating=0.55, ... )
local _, ns = ...

local PawnString = {}
ns.PawnString = PawnString

function PawnString.Parse(str)
  if type(str) ~= "string" then return nil, "not a string" end
  local body = str:match("Pawn%s*:%s*v1%s*:%s*(.*)$")
  if not body then return nil, "not a Pawn v1 string" end
  local name, rest = body:match('^%s*"([^"]*)"%s*:%s*(.*)$')
  if not name then return nil, "missing scale name" end
  rest = rest:gsub("%)%s*$", "")

  local out = { name = name, weights = {}, unknown = {} }
  for key, value in rest:gmatch("([%w_]+)%s*=%s*([^,%s%)]+)") do
    if key == "Class" then
      out.class = value
    elseif key == "Spec" then
      out.spec = value
    else
      local canonical = ns.Stats.PAWN_TO_KEY[key]
      local n = tonumber(value)
      if canonical and n then
        out.weights[canonical] = n
      elseif not canonical then
        out.unknown[#out.unknown + 1] = key
      end
    end
  end

  if next(out.weights) == nil then return nil, "no recognized stat weights" end

  local classID = ns.Data.FindClassByName(out.class)
  if classID then
    out.classID = classID
    local specID = ns.Specs.FindByName(classID, out.spec)
    out.specID = specID
  end
  return out
end
