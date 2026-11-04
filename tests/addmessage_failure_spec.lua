-- Displayed-message observer failures are isolated per registration.
local now = 100
local reports = {}
local addMessageDispatcher
local unpackValues = unpack or table.unpack

_G.GetTime = function() return now end
_G.RothChat = {}
_G.hooksecurefunc = function(target, name, callback)
  assert(name == "AddMessage" and type(target[name]) == "function")
  addMessageDispatcher = callback
end

local frame = { AddMessage = function() end }
local NS = {
  SafeNumber = function(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
      return value
    end
    return fallback
  end,
  Pack = function(...) return { n = select("#", ...), ... } end,
  Unpack = function(values, first) return unpackValues(values, first or 1, values.n) end,
  IsChatMessagingRestricted = function() return false end,
  CanAccessAllValues = function() return true end,
  CanAccessValue = function() return true end,
  CanAccessTable = function(value) return type(value) == "table" end,
  AddMessageEventFilter = function() return true end,
  RemoveMessageEventFilter = function() return true end,
  ReportError = function(label) reports[#reports + 1] = label; return true end,
  IsReportingError = function() return false end,
  CanAccessObject = function(value) return value == frame end,
  Clamp = function(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
  end,
  GetActiveChatFrames = function() return { frame } end,
}

assert(loadfile("CoreDispatch.lua"))("RothChat", NS)
local core = _G.RothChat
function core:EnsureChatFrameLifecycleHooks() end

local ownerA, ownerB = {}, {}
local opaqueError = setmetatable({}, { __tostring = function() error("must not inspect observer failure") end })
local failA, failB = true, true

assert(core:RegisterAddMessageHook(function()
  if failA then error(opaqueError) end
end, ownerA, 10))
assert(core:RegisterAddMessageHook(function()
  if failB then error(opaqueError) end
end, ownerB, 20))
assert(type(addMessageDispatcher) == "function")

for _ = 1, 3 do addMessageDispatcher(frame, "hello", 1, 1, 1) end
assert(#reports == 2 and reports[1] ~= reports[2],
  "each observer needs an independent ordinary diagnostic key")
assert(reports[1]:find("RothChat:AddMessage#1", 1, true)
  and reports[2]:find("RothChat:AddMessage#2", 1, true))

now = now + 11
addMessageDispatcher(frame, "hello", 1, 1, 1)
assert(#reports == 4)
assert(reports[3]:find("2 repeats suppressed", 1, true)
  and reports[4]:find("2 repeats suppressed", 1, true))

-- Success clears only that registration's failure streak.
failA, failB = false, false
addMessageDispatcher(frame, "hello", 1, 1, 1)
failA = true
now = now + 1
addMessageDispatcher(frame, "hello", 1, 1, 1)
assert(#reports == 5 and reports[5]:find("#1", 1, true)
  and not reports[5]:find("suppressed", 1, true))

core:UnregisterAddMessageHooks(ownerA)
core:UnregisterAddMessageHooks(ownerB)
addMessageDispatcher(frame, "hello", 1, 1, 1)
assert(#reports == 5, "unregistered observers must not run")

print("addmessage_failure_spec: ok")
