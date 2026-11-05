-- RothChat - sole owner of synchronous filters and displayed-message observers.
local _, NS = ...
local core = _G.RothChat

local CALLBACK_ERROR_WINDOW = 10
local nextRegistrationID = 0

local function InsertSorted(entries, entry)
  for index = 1, #entries do
    if entry[3] < entries[index][3] then table.insert(entries, index, entry); return end
  end
  entries[#entries + 1] = entry
end

local function Compact(entries)
  local write = 1
  for read = 1, #entries do
    local entry = entries[read]
    if entry[1] then entries[write] = entry; write = write + 1 end
  end
  for index = write, #entries do entries[index] = nil end
end

local function Flush(state)
  if state.depth > 0 then return end
  if state.dirty then
    Compact(state.entries)
    state.dirty = nil
  end
  for index = 1, #state.pending do
    local entry = state.pending[index]
    if entry[1] then InsertSorted(state.entries, entry) end
    state.pending[index] = nil
  end
end

local function FindIn(entries, callback, owner)
  for index = 1, #entries do
    local entry = entries[index]
    if entry[1] == callback and entry[2] == owner then return entry end
  end
end

local function Find(state, callback, owner)
  return FindIn(state.entries, callback, owner)
    or FindIn(state.pending, callback, owner)
end

local function RemoveOwnerFrom(entries, owner)
  local removed = false
  for index = 1, #entries do
    local entry = entries[index]
    if entry[1] and entry[2] == owner then
      entry[1] = nil
      removed = true
    end
  end
  return removed
end

local function RemoveOwner(state, owner)
  if RemoveOwnerFrom(state.entries, owner) then state.dirty = true end
  if RemoveOwnerFrom(state.pending, owner) then state.dirty = true end
end

local function AddEntry(state, callback, owner, priority)
  if Find(state, callback, owner) then return end
  nextRegistrationID = nextRegistrationID + 1
  local entry = { callback, owner, NS.SafeNumber(priority, 50), nil, nextRegistrationID }
  if state.depth > 0 then state.pending[#state.pending + 1] = entry
  else InsertSorted(state.entries, entry) end
end

local function ReportCallbackFailure(prefix, entry)
  local now = NS.SafeNumber(GetTime(), 0)
  local failure = entry[4]
  if not failure then
    failure = { suppressed = 0 }
    entry[4] = failure
  end

  local lastReport = failure.lastReport
  if lastReport and now - lastReport < CALLBACK_ERROR_WINDOW then
    failure.suppressed = failure.suppressed + 1
    return
  end

  local label = prefix .. "#" .. tostring(entry[5])
  if failure.suppressed > 0 then
    label = label .. " (" .. failure.suppressed .. " repeats suppressed)"
  end
  failure.lastReport = now
  if NS.ReportError(label) then
    failure.suppressed = 0
  else
    failure.suppressed = failure.suppressed + 1
  end
end

core._messageFilterState = {}

local function FlushFilter(event, state)
  Flush(state)
  if state.depth > 0 or #state.entries > 0 then return end
  if not state.registered or NS.RemoveMessageEventFilter(event, state.dispatcher) then
    state.registered = false
    core._messageFilterState[event] = nil
  end
end

local function NewFilterState(event)
  local state = {
    entries = {},
    pending = {},
    depth = 0,
    registered = false,
    failurePrefix = "RothChat:MsgFilter:" .. event,
  }
  state.dispatcher = function(chatFrame, _, ...)
    if not state.registered or #state.entries == 0 or NS.IsChatMessagingRestricted()
      or (chatFrame ~= nil and not NS.CanAccessObject(chatFrame))
      or not NS.CanAccessAllValues(...)
    then return false end

    -- Borrow the exact synchronous tuple directly from the client. The visible
    -- first field can change between filters; every remaining field stays on
    -- the Lua stack with its exact arity and nil positions.
    if select("#", ...) == 0 then return false end
    local originalText = ...
    if type(originalText) ~= "string" then return false end
    local currentText, discardMessage = originalText, false

    state.depth = state.depth + 1
    local limit = #state.entries
    for index = 1, limit do
      local entry = state.entries[index]
      if entry[1] then
        local ok, discard, replacement = pcall(
          entry[1],
          chatFrame,
          event,
          currentText,
          select(2, ...)
        )
        if not ok then
          ReportCallbackFailure(state.failurePrefix, entry)
        else
          entry[4] = nil
          if NS.CanAccessValue(discard) then
            if discard == true then
              discardMessage = true
              break
            elseif NS.CanAccessValue(replacement) and type(replacement) == "string" then
              currentText = replacement
            end
          end
        end
      end
    end
    state.depth = state.depth - 1
    FlushFilter(event, state)

    if discardMessage then return true end
    if currentText ~= originalText then return false, currentText, select(2, ...) end
    return false
  end
  return state
end

function core:RegisterMessageFilter(owner, event, callback, priority)
  if not NS.CanAccessAllValues(owner, event, callback, priority)
    or type(owner) ~= "table" or type(event) ~= "string" or type(callback) ~= "function"
  then
    return false
  end
  local state = self._messageFilterState[event]
  if not state then
    state = NewFilterState(event)
    self._messageFilterState[event] = state
  end
  if not state.registered then
    if not NS.AddMessageEventFilter(event, state.dispatcher) then
      self._messageFilterState[event] = nil
      return false
    end
    state.registered = true
  end
  AddEntry(state, callback, owner, priority)
  return true
end

function core:RegisterMessageFilters(owner, events, callback, priority)
  if not NS.CanAccessTable(events) then return 0 end
  local count = 0
  for _, event in ipairs(events) do
    if self:RegisterMessageFilter(owner, event, callback, priority) then count = count + 1 end
  end
  return count
end

function core:UnregisterMessageFilters(owner)
  if not NS.CanAccessValue(owner) or owner == nil then return end
  for event, state in pairs(self._messageFilterState) do
    RemoveOwner(state, owner)
    FlushFilter(event, state)
  end
end

-- AddMessage observers receive displayed ordinary text and RGB only. Line IDs,
-- access IDs and trailing opaque metadata never enter addon feature callbacks.
local messageState = { entries = {}, pending = {}, depth = 0 }
core._addMsgHooked = setmetatable({}, { __mode = "k" })

local function Color(value)
  value = NS.SafeNumber(value)
  return value and NS.Clamp(value, 0, 1) or nil
end

local function DispatchAddMessage(frame, text, r, g, b)
  if #messageState.entries == 0 or NS.IsReportingError() or NS.IsChatMessagingRestricted()
    or not NS.CanAccessObject(frame) or not NS.CanAccessValue(text) or type(text) ~= "string"
  then return end
  r, g, b = Color(r), Color(g), Color(b)
  messageState.depth = messageState.depth + 1
  local limit = #messageState.entries
  for index = 1, limit do
    local entry = messageState.entries[index]
    if entry[1] then
      local ok = pcall(entry[1], frame, text, r, g, b)
      if ok then
        entry[4] = nil
      else
        ReportCallbackFailure("RothChat:AddMessage", entry)
      end
    end
  end
  messageState.depth = messageState.depth - 1
  Flush(messageState)
end

function core:EnsureAddMsgHookForFrame(frame)
  if not NS.CanAccessObject(frame) or self._addMsgHooked[frame] ~= nil
    or type(frame.AddMessage) ~= "function"
  then
    return
  end
  self:EnsureChatFrameLifecycleHooks(frame)
  -- A denied hook is terminal for this frame lifetime. Repeating the same
  -- forbidden operation on every native update only creates an error storm.
  self._addMsgHooked[frame] = pcall(hooksecurefunc, frame, "AddMessage", DispatchAddMessage)
end

function core:RegisterAddMessageHook(callback, owner, priority)
  if not NS.CanAccessAllValues(callback, owner, priority)
    or type(callback) ~= "function" or type(owner) ~= "table"
  then
    return false
  end
  AddEntry(messageState, callback, owner, priority)
  for _, frame in ipairs(NS.GetActiveChatFrames()) do self:EnsureAddMsgHookForFrame(frame) end
  return true
end

function core:UnregisterAddMessageHooks(owner)
  if not NS.CanAccessValue(owner) or owner == nil then return end
  RemoveOwner(messageState, owner)
  Flush(messageState)
end
