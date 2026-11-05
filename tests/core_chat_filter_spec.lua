-- Exact received-tuple and accessibility contracts for the loaded dispatcher.
local Runtime = assert(loadfile("tests/support/runtime.lua"))()
local env = Runtime.New()
local registeredFilters, NS = env.filters, env.ns
local pack = NS.Pack

-- The dispatcher must preserve the received tuple directly on the Lua stack;
-- allocating a Pack table per chat message is not part of the hot-path contract.
NS.Pack = function() error("message filter dispatcher allocated a tuple table") end

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
local noOpResults = pack(dispatcher({}, event, unpack(payload, 1, payload.n)))
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
local transformedResults = pack(dispatcher({}, event, unpack(payload, 1, payload.n)))
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
local discardResults = pack(dispatcher({}, event, unpack(payload, 1, payload.n)))
assert(discardResults.n == 1)
assert(discardResults[1] == true)
core:UnregisterMessageFilters(discardOwner)
assert(registeredFilters[event] == nil, "last owner removal must unregister the dispatcher")

-- Future-width and 14-field callbacks preserve interior and trailing nils.
for _, arity in ipairs({ 1, 14, 19, 23 }) do
  local owner = {}
  core:RegisterMessageFilter(owner, event, function(_, _, text) return false, text .. "!" end)
  local args = { [1] = "payload", [3] = "third", n = arity }
  local result = pack(registeredFilters[event]({}, event, unpack(args, 1, arity)))
  assert(result.n == arity + 1 and result[2] == "payload!")
  for index = 2, arity do assert(result[index + 1] == args[index]) end
  core:UnregisterMessageFilters(owner)
end

-- A readable message does not make neighboring routing metadata ordinary.
do
  local owner, calls = {}, 0
  core:RegisterMessageFilter(owner, event, function() calls = calls + 1; return false, "changed" end)
  local result = pack(registeredFilters[event]({}, event, "readable", env.inaccessible))
  assert(calls == 0 and result.n == 1 and result[1] == false)
  env.restricted = true
  result = pack(registeredFilters[event]({}, event, "readable", "sender"))
  assert(calls == 0 and result.n == 1)
  env.restricted = false
  core:UnregisterMessageFilters(owner)
end

-- Unchanged text, inaccessible results and invalid replacement types are no-op.
for _, replacement in ipairs({ "hello", env.inaccessible, 42 }) do
  local owner = {}
  core:RegisterMessageFilter(owner, event, function() return false, replacement end)
  local result = pack(registeredFilters[event]({}, event, "hello", "sender", nil))
  assert(result.n == 1 and result[1] == false)
  core:UnregisterMessageFilters(owner)
end

print("core_chat_filter_spec: ok")
