-- RothChat - mutation-safe internal event bus.
-- Kept separate from the message-filter/AddMessage registries because listener
-- entries are named records rather than the compact callback arrays they use.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

RothChat._listenerStates = {}
RothChat._listeners = {}

local function GetState(self, event)
  local state = self._listenerStates[event]
  if state then return state end
  state = { entries = {}, pending = {}, depth = 0 }
  self._listenerStates[event] = state
  self._listeners[event] = state.entries
  return state
end

local function CompactEntries(entries)
  local writeIndex = 1
  for readIndex = 1, #entries do
    local entry = entries[readIndex]
    if entry and type(entry.fn) == "function" then
      if writeIndex ~= readIndex then entries[writeIndex] = entry end
      writeIndex = writeIndex + 1
    end
  end
  for index = writeIndex, #entries do entries[index] = nil end
end

local function Flush(self, event, state)
  if state.depth > 0 then return end
  CompactEntries(state.entries)

  for index = 1, #state.pending do
    local entry = state.pending[index]
    if entry and type(entry.fn) == "function" then
      state.entries[#state.entries + 1] = entry
    end
    state.pending[index] = nil
  end

  if #state.entries == 0 then
    self._listenerStates[event] = nil
    self._listeners[event] = nil
  end
end

function RothChat:On(event, fn, owner)
  if type(event) ~= "string" or type(fn) ~= "function" then return end
  local state = GetState(self, event)
  local entry = { fn = fn, owner = owner }
  if state.depth > 0 then
    state.pending[#state.pending + 1] = entry
  else
    state.entries[#state.entries + 1] = entry
  end
end

function RothChat:Off(event, fn)
  local state = self._listenerStates[event]
  if not state or type(fn) ~= "function" then return end

  for index = 1, #state.entries do
    local entry = state.entries[index]
    if entry and entry.fn == fn then entry.fn = nil end
  end
  for index = 1, #state.pending do
    local entry = state.pending[index]
    if entry and entry.fn == fn then entry.fn = nil end
  end
  Flush(self, event, state)
end

function RothChat:OffOwner(owner)
  if not owner then return end
  local states = {}
  for event, state in pairs(self._listenerStates) do
    states[#states + 1] = { event, state }
  end

  for index = 1, #states do
    local event, state = states[index][1], states[index][2]
    for entryIndex = 1, #state.entries do
      local entry = state.entries[entryIndex]
      if entry and entry.owner == owner then entry.fn = nil end
    end
    for entryIndex = 1, #state.pending do
      local entry = state.pending[entryIndex]
      if entry and entry.owner == owner then entry.fn = nil end
    end
    Flush(self, event, state)
  end
end

function RothChat:Emit(event, ...)
  local state = self._listenerStates[event]
  if not state then return end

  state.depth = state.depth + 1
  local limit = #state.entries
  for index = 1, limit do
    local entry = state.entries[index]
    if entry and type(entry.fn) == "function" then
      NS.SafeCall("RothChat:Emit:" .. event, entry.fn, entry.owner, self, ...)
    end
  end
  state.depth = state.depth - 1
  Flush(self, event, state)
end
