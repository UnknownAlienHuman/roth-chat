-- Message-filter failures are isolated per callback and reported at a bounded cadence.
local now = 100
local registered = {}
local reports = {}
local unpackValues = unpack or table.unpack

_G.GetTime = function() return now end
_G.RothChat = {}

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
  AddMessageEventFilter = function(event, callback) registered[event] = callback; return true end,
  RemoveMessageEventFilter = function(event, callback)
    if registered[event] == callback then registered[event] = nil end
    return true
  end,
  ReportError = function(label) reports[#reports + 1] = label; return true end,
  IsReportingError = function() return false end,
  CanAccessObject = function() return true end,
  Clamp = function(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
  end,
  SafeCall = function(_, callback, ...)
    local ok = pcall(callback, ...)
    return ok
  end,
  GetActiveChatFrames = function() return {} end,
}

assert(loadfile("CoreDispatch.lua"))("RothChat", NS)
local core = _G.RothChat
local ownerA, ownerB = {}, {}
local opaqueError = setmetatable({}, { __tostring = function() error("must not inspect raw callback failure") end })
local failA, failB = true, true

assert(core:RegisterMessageFilter(ownerA, "CHAT_MSG_SAY", function(_, _, text)
  if failA then error(opaqueError) end
  return false, text .. "!"
end, 10))
assert(core:RegisterMessageFilter(ownerB, "CHAT_MSG_SAY", function(_, _, text)
  if failB then error(opaqueError) end
  return false, text .. "?"
end, 20))

local dispatcher = assert(registered.CHAT_MSG_SAY)
for _ = 1, 3 do
  local discard, text, sender = dispatcher(nil, "CHAT_MSG_SAY", "hello", "sender")
  assert(discard == false and text == nil and sender == nil,
    "failing callbacks must degrade to the no-op return contract")
end
assert(#reports == 2 and reports[1] ~= reports[2],
  "each failing callback needs an independent ordinary diagnostic key")
assert(reports[1]:find("#1", 1, true) and reports[2]:find("#2", 1, true))

now = now + 11
dispatcher(nil, "CHAT_MSG_SAY", "hello", "sender")
assert(#reports == 4)
assert(reports[3]:find("2 repeats suppressed", 1, true)
  and reports[4]:find("2 repeats suppressed", 1, true))

-- One success clears only that callback's failure streak.
failA, failB = false, false
local discard, text, sender = dispatcher(nil, "CHAT_MSG_SAY", "hello", "sender")
assert(discard == false and text == "hello!?" and sender == "sender")
failA = true
now = now + 1
dispatcher(nil, "CHAT_MSG_SAY", "hello", "sender")
assert(#reports == 5 and reports[5]:find("#1", 1, true)
  and not reports[5]:find("suppressed", 1, true))

core:UnregisterMessageFilters(ownerA)
core:UnregisterMessageFilters(ownerB)
assert(registered.CHAT_MSG_SAY == nil)
print("filter_failure_spec: ok")
