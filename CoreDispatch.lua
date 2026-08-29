-- RothChat - mutation-safe callback registries.
-- Loaded after Core.lua and before modules activate. Replaces array mutation
-- during dispatch with tombstones/deferred additions and uses Lua 5.1-safe
-- pcall varargs while preserving return arity.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local function PackValues(...)
  return { n = select("#", ...), ... }
end

local function UnpackValues(values, first)
  return unpack(values, first or 1, values.n)
end

local function SafeCallMulti(label, fn, ...)
  if type(fn) ~= "function" then return false end
  local results = PackValues(pcall(fn, ...))
  if not results[1] then
    if NS.ReportError then NS.ReportError(label, results[2]) end
    return false
  end
  return true, UnpackValues(results, 2)
end

local function InsertSorted(list, entry)
  local priority = entry[3]
  for index = 1, #list do
    local current = list[index]
    if current and current[1] and priority < current[3] then
      table.insert(list, index, entry)
      return
    end
  end
  list[#list + 1] = entry
end

local function Compact(list)
  local writeIndex = 1
  for readIndex = 1, #list do
    local entry = list[readIndex]
    if entry and type(entry[1]) == "function" then
      if writeIndex ~= readIndex then list[writeIndex] = entry end
      writeIndex = writeIndex + 1
    end
  end
  for index = writeIndex, #list do list[index] = nil end
end

local function HasActive(list)
  for index = 1, #list do
    local entry = list[index]
    if entry and type(entry[1]) == "function" then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Internal event bus
-- ---------------------------------------------------------------------------

RothChat._listenerStates = RothChat._listenerStates or {}
RothChat._listeners = RothChat._listeners or {}

local function GetListenerState(self, event)
  local state = self._listenerStates[event]
  if state then return state end
  state = { entries = {}, pending = {}, depth = 0 }
  self._listenerStates[event] = state
  self._listeners[event] = state.entries
  return state
end

local function FlushListenerState(self, event, state)
  if state.depth > 0 then return end
  Compact(state.entries)
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
  local state = GetListenerState(self, event)
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
  FlushListenerState(self, event, state)
end

function RothChat:OffOwner(owner)
  if not owner then return end
  for event, state in pairs(self._listenerStates) do
    for index = 1, #state.entries do
      local entry = state.entries[index]
      if entry and entry.owner == owner then entry.fn = nil end
    end
    for index = 1, #state.pending do
      local entry = state.pending[index]
      if entry and entry.owner == owner then entry.fn = nil end
    end
    FlushListenerState(self, event, state)
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
  FlushListenerState(self, event, state)
end

-- ---------------------------------------------------------------------------
-- Blizzard message-event filter registry
-- ---------------------------------------------------------------------------

RothChat._messageFilterState = RothChat._messageFilterState or {}
RothChat._moduleFilters = RothChat._moduleFilters or setmetatable({}, { __mode = "k" })

local function FlushFilterState(self, event, state)
  if state.depth > 0 then return end
  Compact(state.entries)
  for index = 1, #state.pending do
    local entry = state.pending[index]
    if entry and type(entry[1]) == "function" then InsertSorted(state.entries, entry) end
    state.pending[index] = nil
  end

  if not HasActive(state.entries) and #state.pending == 0 then
    if state.registered then NS.RemoveMessageEventFilter(event, state.dispatcher) end
    self._messageFilterState[event] = nil
  end
end

local function GetFilterState(self, event)
  local state = self._messageFilterState[event]
  if state then return state end

  state = { entries = {}, pending = {}, depth = 0 }
  state.dispatcher = function(chatFrame, evt, ...)
    local args = PackValues(...)
    if args.n < 1 or (NS.CanAccessValue and not NS.CanAccessValue(args[1])) then
      return false
    end

    local current = self._messageFilterState[evt] or state
    current.depth = current.depth + 1
    local discardMessage = false
    local transformedMessage = false
    local limit = #current.entries

    for index = 1, limit do
      local entry = current.entries[index]
      if entry and type(entry[1]) == "function" then
        local results = PackValues(SafeCallMulti(
          "RothChat:MsgFilter:" .. evt,
          entry[1],
          chatFrame,
          evt,
          UnpackValues(args)
        ))

        if results[1] then
          local discard = results[2]
          local newArg1 = results[3]
          if discard then
            discardMessage = true
            break
          elseif newArg1 ~= nil and newArg1 ~= false
            and (not NS.CanAccessValue or NS.CanAccessValue(newArg1))
          then
            args[1] = newArg1
            transformedMessage = true
          end
        end
      end
    end

    current.depth = current.depth - 1
    FlushFilterState(self, evt, current)

    if discardMessage then return true end
    if transformedMessage then return false, UnpackValues(args) end
    return false
  end

  self._messageFilterState[event] = state
  return state
end

function RothChat:RegisterMessageFilter(owner, event, callback, priority)
  if type(owner) ~= "table" or type(event) ~= "string" or type(callback) ~= "function" then
    return false
  end
  priority = tonumber(priority) or 50

  local byEvent = self._moduleFilters[owner]
  if not byEvent then
    byEvent = {}
    self._moduleFilters[owner] = byEvent
  end
  local ownerEntries = byEvent[event]
  if not ownerEntries then
    ownerEntries = {}
    byEvent[event] = ownerEntries
  end

  for index = 1, #ownerEntries do
    local entry = ownerEntries[index]
    if entry and entry[4] == callback and type(entry[1]) == "function" then return true end
  end

  local state = GetFilterState(self, event)
  if not state.registered then
    if not NS.AddMessageEventFilter(event, state.dispatcher) then return false end
    state.registered = true
  end

  local entry = { callback, owner, priority, callback }
  ownerEntries[#ownerEntries + 1] = entry
  if state.depth > 0 then
    state.pending[#state.pending + 1] = entry
  else
    InsertSorted(state.entries, entry)
  end
  return true
end

function RothChat:RegisterMessageFilters(owner, events, callback, priority)
  if type(events) ~= "table" then return 0 end
  local count = 0
  for index = 1, #events do
    if self:RegisterMessageFilter(owner, events[index], callback, priority) then
      count = count + 1
    end
  end
  return count
end

function RothChat:UnregisterMessageFilters(owner)
  if type(owner) ~= "table" then return end
  local byEvent = self._moduleFilters[owner]
  if not byEvent then return end

  for event, ownerEntries in pairs(byEvent) do
    local state = self._messageFilterState[event]
    if state then
      for index = 1, #ownerEntries do
        local entry = ownerEntries[index]
        if entry then entry[1] = nil end
        ownerEntries[index] = nil
      end
      FlushFilterState(self, event, state)
    end
    byEvent[event] = nil
  end
  self._moduleFilters[owner] = nil
end

-- ---------------------------------------------------------------------------
-- Displayed-message AddMessage fan-out
-- ---------------------------------------------------------------------------

local originalRegisterAddMessageHook = RothChat.RegisterAddMessageHook
local addMessagePending = {}
local addMessageFlushKey = {}
RothChat._addMsgDispatchDepth = 0

local FlushAddMessageRegistry

local function FindAddMessageRegistration(callback, owner)
  for index = 1, #RothChat._addMsgCallbacks do
    local entry = RothChat._addMsgCallbacks[index]
    if entry and type(entry[1]) == "function" and entry[2] == owner
      and (entry[4] == callback or entry[1] == callback)
    then
      return entry
    end
  end
  for index = 1, #addMessagePending do
    local entry = addMessagePending[index]
    if entry and entry.callback == callback and entry.owner == owner then return entry end
  end
  return nil
end

local function ScheduleAddMessageFlush()
  NS.RunNextFrame(addMessageFlushKey, function()
    FlushAddMessageRegistry()
  end, "RothChat:AddMessageRegistryFlush")
end

local function InstallAddMessageRegistration(callback, owner, priority)
  if FindAddMessageRegistration(callback, owner) then return end

  local wrapped
  wrapped = function(...)
    RothChat._addMsgDispatchDepth = RothChat._addMsgDispatchDepth + 1
    local results = PackValues(pcall(callback, ...))
    RothChat._addMsgDispatchDepth = RothChat._addMsgDispatchDepth - 1

    if not results[1] then
      if NS.ReportError then NS.ReportError("RothChat:AddMessage", results[2]) end
    end
    if RothChat._addMsgDispatchDepth == 0 then ScheduleAddMessageFlush() end
    if results[1] then return UnpackValues(results, 2) end
  end

  originalRegisterAddMessageHook(RothChat, wrapped, owner, priority)
  for index = 1, #RothChat._addMsgCallbacks do
    local entry = RothChat._addMsgCallbacks[index]
    if entry and entry[1] == wrapped and entry[2] == owner then
      entry[4] = callback
      return
    end
  end
end

FlushAddMessageRegistry = function()
  if RothChat._addMsgDispatchDepth > 0 then
    ScheduleAddMessageFlush()
    return
  end

  Compact(RothChat._addMsgCallbacks)
  local pending = addMessagePending
  addMessagePending = {}
  for index = 1, #pending do
    local entry = pending[index]
    if entry and type(entry.callback) == "function" then
      InstallAddMessageRegistration(entry.callback, entry.owner, entry.priority)
    end
  end
end

function RothChat:RegisterAddMessageHook(callback, owner, priority)
  if type(callback) ~= "function" then return end
  priority = tonumber(priority) or 50
  if FindAddMessageRegistration(callback, owner) then return end

  if self._addMsgDispatchDepth > 0 then
    addMessagePending[#addMessagePending + 1] = {
      callback = callback,
      owner = owner,
      priority = priority,
    }
    ScheduleAddMessageFlush()
  else
    InstallAddMessageRegistration(callback, owner, priority)
  end
end

function RothChat:UnregisterAddMessageHooks(owner)
  if not owner then return end

  for index = 1, #addMessagePending do
    local entry = addMessagePending[index]
    if entry and entry.owner == owner then entry.callback = nil end
  end

  for index = 1, #self._addMsgCallbacks do
    local entry = self._addMsgCallbacks[index]
    if entry and entry[2] == owner then entry[1] = nil end
  end

  if self._addMsgDispatchDepth > 0 then
    ScheduleAddMessageFlush()
  else
    FlushAddMessageRegistry()
  end
end
