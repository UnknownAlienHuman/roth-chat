-- Internal listeners keep ordinary diagnostic identity per registration and
-- defer additions made during an active dispatch.
local reports = {}
local RothChat = {}
_G.RothChat = RothChat

local NS = {
  CanAccessAllValues = function() return true end,
  SafeCall = function(label, callback, ...)
    local ok = pcall(callback, ...)
    if not ok then reports[#reports + 1] = label end
    return ok
  end,
}

assert(loadfile("CoreListeners.lua"))("RothChat", NS)

local ownerA, ownerB, ownerC = {}, {}, {}
local runsC = 0
local function failA() error("a") end
local function failB() error("b") end
local function runC() runsC = runsC + 1 end

RothChat:On("TEST", failA, ownerA)
RothChat:On("TEST", failB, ownerB)
RothChat:Emit("TEST")
assert(#reports == 2, "each failing listener must report independently")
assert(reports[1] ~= reports[2])
assert(reports[1]:find("RothChat:Emit:TEST#1", 1, true))
assert(reports[2]:find("RothChat:Emit:TEST#2", 1, true))

RothChat:OffOwner(ownerA)
RothChat:Emit("TEST")
assert(#reports == 3 and reports[3]:find("#2", 1, true),
  "owner removal must leave the other listener identity intact")

local added = false
RothChat:On("MUTATE", function()
  if not added then
    added = true
    RothChat:On("MUTATE", runC, ownerC)
  end
end, {})
RothChat:Emit("MUTATE")
assert(runsC == 0, "a listener added during dispatch must wait for the next generation")
RothChat:Emit("MUTATE")
assert(runsC == 1)

print("listener_failure_spec: ok")
