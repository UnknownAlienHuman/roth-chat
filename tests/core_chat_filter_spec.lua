-- Contract test for RothChat's centralized message-filter dispatcher.
-- Runs outside WoW with a deliberately small API stub.

local function pack(...)
  return { n = select("#", ...), ... }
end

unpack = table.unpack
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

function debugstack()
  return ""
end

function InCombatLockdown()
  return false
end

function CreateFrame()
  local frame = {}

  function frame:SetScript(scriptName, callback)
    self[scriptName] = callback
  end

  function frame:RegisterEvent()
  end

  return frame
end

local registeredFilters = {}
local NS = {}

function NS.SafeCall(_, fn, ...)
  local results = pack(pcall(fn, ...))
  if not results[1] then
    return false, results[2]
  end
  return true, table.unpack(results, 2, results.n)
end

function NS.SafeConcat(...)
  local out = {}
  for i = 1, select("#", ...) do
    out[#out + 1] = tostring(select(i, ...))
  end
  return table.concat(out, " ")
end

function NS.AddMessageEventFilter(event, callback)
  registeredFilters[event] = callback
  return true
end

function NS.RemoveMessageEventFilter(event, callback)
  if registeredFilters[event] == callback then
    registeredFilters[event] = nil
  end
  return true
end

function NS.IsSecretValue()
  return false
end

function NS.GetChatFrames()
  return {}
end

function NS.RunNextFrame(_, callback)
  callback()
end

assert(loadfile("Core.lua"))("RothChat", NS)

local core = assert(_G.RothChat)
local event = "CHAT_MSG_SAY"
local payload = {
  n = 19,
  [1] = "hello",
  [2] = "Sender-Realm",
  [3] = "Common",
  [4] = "General",
  [5] = "Sender",
  [6] = 0,
  [7] = nil,
  [8] = 1,
  [9] = "General - Zone",
  [10] = 0,
  [11] = 123,
  [12] = "Player-1-00000001",
  [13] = false,
  [14] = 77,
  [15] = "arg15",
  [16] = false,
  [17] = 9001,
  [18] = { userID = 42 },
  [19] = "tail",
}

local noOpOwner = {}
assert(core:RegisterMessageFilter(noOpOwner, event, function(_, _, ...)
  assert(select("#", ...) == payload.n)
  return false
end, 50))

local dispatcher = assert(registeredFilters[event])
local noOpResults = pack(dispatcher({}, event, table.unpack(payload, 1, payload.n)))
assert(noOpResults.n == 1, "no-op path must not replace Blizzard's secure tuple")
assert(noOpResults[1] == false, "no-op path must not discard")
core:UnregisterMessageFilters(noOpOwner)

local transformOwner = {}
local observerOwner = {}
assert(core:RegisterMessageFilter(transformOwner, event, function(_, _, ...)
  assert(select("#", ...) == payload.n)
  assert(select(1, ...) == "hello")
  assert(select(7, ...) == nil)
  assert(select(19, ...) == "tail")
  return false, "changed"
end, 50))

assert(core:RegisterMessageFilter(observerOwner, event, function(_, _, ...)
  assert(select("#", ...) == payload.n)
  assert(select(1, ...) == "changed", "later filters must receive transformed arg1")
  return false
end, 60))

dispatcher = assert(registeredFilters[event])
local transformedResults = pack(dispatcher({}, event, table.unpack(payload, 1, payload.n)))
assert(transformedResults.n == payload.n + 1, "discard flag plus all 19 fields must be returned")
assert(transformedResults[1] == false)
assert(transformedResults[2] == "changed")
for i = 2, payload.n do
  assert(transformedResults[i + 1] == payload[i], "payload mismatch at field " .. i)
end
core:UnregisterMessageFilters(transformOwner)
core:UnregisterMessageFilters(observerOwner)

local discardOwner = {}
assert(core:RegisterMessageFilter(discardOwner, event, function()
  return true
end, 10))

dispatcher = assert(registeredFilters[event])
local discardResults = pack(dispatcher({}, event, table.unpack(payload, 1, payload.n)))
assert(discardResults.n == 1)
assert(discardResults[1] == true)
core:UnregisterMessageFilters(discardOwner)
assert(registeredFilters[event] == nil, "last owner removal must unregister the dispatcher")

print("core_chat_filter_spec: ok")
