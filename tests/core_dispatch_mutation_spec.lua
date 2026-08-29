-- Mutation-safe bus, filter and AddMessage dispatch contract.

local scheduled = {}
local registeredFilters = {}

local NS = {
  SafeCall = function(_, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return false, a end
    return true, a, b, c, d
  end,
  ReportError = function(_, err)
    error("unexpected callback error: " .. tostring(err))
  end,
  CanAccessValue = function() return true end,
  AddMessageEventFilter = function(event, callback)
    registeredFilters[event] = callback
    return true
  end,
  RemoveMessageEventFilter = function(event, callback)
    if registeredFilters[event] == callback then registeredFilters[event] = nil end
    return true
  end,
  RunNextFrame = function(key, callback)
    scheduled[key] = callback
  end,
}

local function RunScheduled()
  local jobs = scheduled
  scheduled = {}
  for _, callback in pairs(jobs) do callback() end
end

_G.RothChat = {
  _listeners = {},
  _messageFilterState = {},
  _moduleFilters = setmetatable({}, { __mode = "k" }),
  _addMsgCallbacks = {},
  RegisterAddMessageHook = function(self, callback, owner, priority)
    local entry = { callback, owner, priority }
    local inserted = false
    for index = 1, #self._addMsgCallbacks do
      if priority < self._addMsgCallbacks[index][3] then
        table.insert(self._addMsgCallbacks, index, entry)
        inserted = true
        break
      end
    end
    if not inserted then self._addMsgCallbacks[#self._addMsgCallbacks + 1] = entry end
  end,
}

assert(loadfile("CoreDispatch.lua"))("RothChat", NS)
assert(loadfile("CoreListeners.lua"))("RothChat", NS)
local core = _G.RothChat

-- Event bus: removing the next listener must not skip the independent tail;
-- additions begin with the next outer dispatch only.
do
  local calls = {}
  local ownerA, ownerB, ownerC, ownerD = {}, {}, {}, {}
  local added = false

  core:On("BUS", function()
    calls[#calls + 1] = "A"
    core:OffOwner(ownerB)
    if not added then
      added = true
      core:On("BUS", function() calls[#calls + 1] = "D" end, ownerD)
    end
  end, ownerA)
  core:On("BUS", function() calls[#calls + 1] = "B" end, ownerB)
  core:On("BUS", function() calls[#calls + 1] = "C" end, ownerC)

  core:Emit("BUS")
  assert(table.concat(calls) == "AC")
  calls = {}
  core:Emit("BUS")
  assert(table.concat(calls) == "ACD")
end

-- Message filters preserve the tuple while allowing removal/addition during the
-- same event without skipping later callbacks.
do
  local event = "CHAT_MSG_SAY"
  local ownerA, ownerB, ownerC, ownerD = {}, {}, {}, {}
  local calls = {}
  local added = false

  core:RegisterMessageFilter(ownerA, event, function(_, _, text)
    calls[#calls + 1] = "A"
    core:UnregisterMessageFilters(ownerB)
    if not added then
      added = true
      core:RegisterMessageFilter(ownerD, event, function(_, _, value)
        calls[#calls + 1] = "D"
        return false, value .. "D"
      end, 25)
    end
    return false, text .. "A"
  end, 10)
  core:RegisterMessageFilter(ownerB, event, function(_, _, text)
    calls[#calls + 1] = "B"
    return false, text .. "B"
  end, 20)
  core:RegisterMessageFilter(ownerC, event, function(_, _, text)
    calls[#calls + 1] = "C"
    return false, text .. "C"
  end, 30)

  local dispatcher = assert(registeredFilters[event])
  local discard, text, sender, trailing = dispatcher(nil, event, "x", "sender", nil)
  assert(discard == false)
  assert(text == "xAC" and sender == "sender" and trailing == nil)
  assert(table.concat(calls) == "AC")

  calls = {}
  discard, text, sender, trailing = dispatcher(nil, event, "x", "sender", nil)
  assert(discard == false)
  assert(text == "xADC" and sender == "sender" and trailing == nil)
  assert(table.concat(calls) == "ADC")
end

-- AddMessage uses a next-frame flush because its core dispatcher is a permanent
-- local hook. Tombstones act immediately; pending registrations wait.
do
  local calls = {}
  local ownerA, ownerB, ownerC, ownerD = {}, {}, {}, {}
  local added = false

  core:RegisterAddMessageHook(function()
    calls[#calls + 1] = "A"
    core:UnregisterAddMessageHooks(ownerB)
    if not added then
      added = true
      core:RegisterAddMessageHook(function() calls[#calls + 1] = "D" end, ownerD, 25)
    end
  end, ownerA, 10)
  core:RegisterAddMessageHook(function() calls[#calls + 1] = "B" end, ownerB, 20)
  core:RegisterAddMessageHook(function() calls[#calls + 1] = "C" end, ownerC, 30)

  local limit = #core._addMsgCallbacks
  for index = 1, limit do
    local entry = core._addMsgCallbacks[index]
    if entry and entry[1] then entry[1](nil, "message") end
  end
  assert(table.concat(calls) == "AC")

  RunScheduled()
  calls = {}
  limit = #core._addMsgCallbacks
  for index = 1, limit do
    local entry = core._addMsgCallbacks[index]
    if entry and entry[1] then entry[1](nil, "message") end
  end
  assert(table.concat(calls) == "ADC")
  RunScheduled()
end

print("core_dispatch_mutation_spec: ok")
