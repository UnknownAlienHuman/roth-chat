-- RothChat - mutation-safe internal event bus.
-- Kept separate from the message-filter/AddMessage registries because listener
-- entries are named records rather than the compact callback arrays they use.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

RothChat._listenerStates = {}
local nextListenerID = 0

local function GetState(self, event)
  local state = self._listenerStates[event]
  if state then return state end
  state = { entries = {}, pending = {}, depth = 0 }
  self._listenerStates[event] = state
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
  if state.dirty then
    CompactEntries(state.entries)
    state.dirty = nil
  end

  for index = 1, #state.pending do
    local entry = state.pending[index]
    if entry and type(entry.fn) == "function" then
      state.entries[#state.entries + 1] = entry
    end
    state.pending[index] = nil
  end

  if #state.entries == 0 then
    self._listenerStates[event] = nil
  end
end

function RothChat:On(event, fn, owner)
  if type(event) ~= "string" or type(fn) ~= "function" then return end
  local state = GetState(self, event)
  for _, entries in ipairs({ state.entries, state.pending }) do
    for _, existing in ipairs(entries) do
      if existing.fn == fn and existing.owner == owner then return end
    end
  end
  nextListenerID = nextListenerID + 1
  local entry = { fn = fn, owner = owner, id = nextListenerID }
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
    if entry and entry.fn == fn then entry.fn = nil; state.dirty = true end
  end
  for index = 1, #state.pending do
    local entry = state.pending[index]
    if entry and entry.fn == fn then entry.fn = nil; state.dirty = true end
  end
  Flush(self, event, state)
end

function RothChat:OffOwner(owner)
  if not owner then return end
  -- Flush only removes the current key; it never adds keys during traversal.
  for event, state in pairs(self._listenerStates) do
    for entryIndex = 1, #state.entries do
      local entry = state.entries[entryIndex]
      if entry and entry.fn and entry.owner == owner then entry.fn = nil; state.dirty = true end
    end
    for entryIndex = 1, #state.pending do
      local entry = state.pending[entryIndex]
      if entry and entry.fn and entry.owner == owner then entry.fn = nil; state.dirty = true end
    end
    Flush(self, event, state)
  end
end

function RothChat:Emit(event, ...)
  if not NS.CanAccessAllValues(...) then return end
  local state = self._listenerStates[event]
  if not state then return end

  state.depth = state.depth + 1
  local limit = #state.entries
  for index = 1, limit do
    local entry = state.entries[index]
    if entry and type(entry.fn) == "function" then
      NS.SafeCall(
        "RothChat:Emit:" .. event .. "#" .. tostring(entry.id),
        entry.fn,
        entry.owner,
        self,
        ...
      )
    end
  end
  state.depth = state.depth - 1
  Flush(self, event, state)
end
