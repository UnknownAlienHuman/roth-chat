-- Timestamps module integration contract.

local registeredModule
local capturedFilter
local accessible = true
local currentTime = 12345
local color = "8E8E8E"

_G.RothChat = {
  RegisterModule = function(_, module)
    registeredModule = module
  end,
  Get = function(_, key)
    if key == "timestampColor" then return color end
  end,
}

_G.time = function()
  return currentTime
end
_G.date = function(format, timestamp)
  assert(format == "[%H:%M]")
  assert(timestamp == currentTime)
  return currentTime == 12345 and "[12:34]" or "[12:35]"
end

local NS = {
  CanAccessValue = function()
    return accessible
  end,
  SafeToString = tostring,
}

assert(loadfile("ChatText.lua"))("RothChat", NS)
assert(loadfile("Modules/Timestamps.lua"))("RothChat", NS)
local module = assert(registeredModule)

local core = {
  RegisterMessageFilters = function(_, owner, events, callback, priority)
    assert(owner == module)
    assert(type(events) == "table" and #events > 0)
    assert(priority == 80)
    capturedFilter = callback
    return #events
  end,
}

module:Init(core)
module:OnEnable(core)
assert(type(capturedFilter) == "function")

local discard, transformed = capturedFilter(nil, "CHAT_MSG_SAY", "hello")
assert(discard == false)
assert(transformed == "|cff8E8E8E[12:34]|r hello")

local resultCount = select("#", capturedFilter(nil, "CHAT_MSG_SAY", transformed))
assert(resultCount == 1, "already timestamped text must take the no-op path")

accessible = false
resultCount = select("#", capturedFilter(nil, "CHAT_MSG_SAY", "secret"))
assert(resultCount == 1)

accessible = true
currentTime = 12346
color = "A1B2C3"
local _, updated = capturedFilter(nil, "CHAT_MSG_SAY", "next")
assert(updated == "|cffA1B2C3[12:35]|r next")

module:OnDisable(core)

print("timestamps_spec: ok")
