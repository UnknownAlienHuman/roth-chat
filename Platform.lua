-- RothChat - current Retail access, diagnostics and native chat adapters.
local _, NS = ...

function NS.CanAccessObject(object)
  if not NS.CanAccessValue(object) or object == nil then return false end
  local kind = type(object)
  if kind ~= "table" and kind ~= "userdata" then return false end
  if kind == "table" and type(_G.canaccesstable) == "function" then
    local ok, allowed = pcall(_G.canaccesstable, object)
    if not ok or not NS.CanAccessValue(allowed) or not allowed then return false end
  end
  if type(object.CanBeAccessedInContext) == "function" then
    local ok, allowed = pcall(object.CanBeAccessedInContext, object)
    if not ok or not NS.CanAccessValue(allowed) or not allowed then return false end
  end
  if type(object.IsForbidden) == "function" then
    local ok, forbidden = pcall(object.IsForbidden, object)
    if not ok or not NS.CanAccessValue(forbidden) or forbidden then return false end
  end
  return true
end

function NS.IsChatMessagingRestricted()
  local query = _G.C_ChatInfo and _G.C_ChatInfo.InChatMessagingLockdown
  if type(query) ~= "function" then return false end
  local ok, restricted = pcall(query)
  return not ok or not NS.CanAccessValue(restricted) or restricted == true
end

function NS.IsSettingsOpenRestricted()
  return InCombatLockdown() or NS.IsChatMessagingRestricted()
end

-- Only ordinary code labels enter diagnostics. Raw callback exceptions can
-- contain message text or inaccessible values, so never inspect or retain them.
local errorReporting = false
local errorSeen, errorSeenCount = {}, 0
local repeatWindow, cacheLimit = 10, 64
local burstStart, burstCount = 0, 0

function NS.IsReportingError()
  return errorReporting
end

function NS.ReportError(label)
  if errorReporting then return false end
  if not NS.CanAccessValue(label) or type(label) ~= "string" then label = "RothChat" end
  label = label:sub(1, 96)
  local now = GetTime()
  local previous = errorSeen[label]
  if previous and now - previous < repeatWindow then return false end
  if now - burstStart >= repeatWindow then burstStart, burstCount = now, 0 end
  if burstCount >= 8 then return false end
  if errorSeenCount >= cacheLimit then errorSeen, errorSeenCount = {}, 0 end
  if not errorSeen[label] then errorSeenCount = errorSeenCount + 1 end
  errorSeen[label] = now
  burstCount = burstCount + 1

  local frame = _G.DEFAULT_CHAT_FRAME
  if NS.IsChatMessagingRestricted() or not NS.CanAccessObject(frame)
    or type(frame.AddMessage) ~= "function" then return false end
  errorReporting = true
  pcall(frame.AddMessage, frame, "|cffff6060" .. label .. "|r: callback failed; repeated reports are limited.")
  errorReporting = false
  return true
end

local function CallResult(label, ok, ...)
  if not ok then
    NS.ReportError(label)
    return false, "callback failed"
  end
  return true, ...
end

-- Forward exact result arity on the stack; message consumers do not need an
-- allocated result table, and raw exceptions never enter retained state.
function NS.SafeCall(label, callback, ...)
  if type(callback) ~= "function" then return true end
  return CallResult(label, pcall(callback, ...))
end

function NS.GetChatFrameIndex(frame)
  if not NS.CanAccessObject(frame) then return nil end
  if type(frame.GetID) == "function" then
    local ok, index = pcall(frame.GetID, frame)
    if not ok or not NS.CanAccessValue(index) then return nil end
    index = NS.SafeNumber(index)
    if index and index >= 1 and index == math.floor(index) then return index end
  end
  if type(frame.GetName) == "function" then
    local ok, name = pcall(frame.GetName, frame)
    if ok and NS.CanAccessValue(name) and type(name) == "string" then
      return tonumber(name:match("^ChatFrame(%d+)$"))
    end
  end
  return nil
end

function NS.GetMaxPermanentChatWindows()
  local constants = _G.Constants and _G.Constants.ChatFrameConstants
  local count = constants and NS.SafeNumber(constants.MaxChatWindows)
    or NS.SafeNumber(_G.NUM_CHAT_WINDOWS, 10)
  return math.max(1, math.floor(count))
end

local function AddUniqueFrame(frames, seen, frame)
  if NS.CanAccessObject(frame) and not seen[frame] then
    seen[frame] = true
    frames[#frames + 1] = frame
  end
end

function NS.GetChatFrames()
  local frames, seen = {}, {}
  if type(_G.CHAT_FRAMES) == "table" then
    for _, name in ipairs(_G.CHAT_FRAMES) do
      if NS.CanAccessValue(name) and type(name) == "string" then
        AddUniqueFrame(frames, seen, _G[name])
      end
    end
  else
    for index = 1, NS.GetMaxPermanentChatWindows() do
      AddUniqueFrame(frames, seen, _G["ChatFrame" .. index])
    end
  end
  return frames
end

function NS.IsDockedChatFrame(frame)
  if not NS.CanAccessObject(frame) or not NS.CanAccessValue(frame.isDocked) then return false end
  return frame.isDocked and true or false
end

function NS.GetSelectedDockChatFrame()
  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if NS.CanAccessObject(dock) and type(_G.FCFDock_GetSelectedWindow) == "function" then
    local ok, selected = pcall(_G.FCFDock_GetSelectedWindow, dock)
    if ok and NS.CanAccessObject(selected) then return selected end
  end
  if NS.CanAccessObject(_G.SELECTED_CHAT_FRAME) then return _G.SELECTED_CHAT_FRAME end
end

function NS.ResolveActiveDockChatFrame(frame)
  if NS.IsDockedChatFrame(frame) then return NS.GetSelectedDockChatFrame() or frame end
  return frame
end

local function IsShown(frame)
  if not NS.CanAccessObject(frame) or type(frame.IsShown) ~= "function" then return false end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and NS.CanAccessValue(shown) and shown == true
end

function NS.IsActiveChatFrame(frame)
  if not NS.CanAccessObject(frame) or not NS.CanAccessValue(frame.isTemporary) then return false end
  if frame.isTemporary then
    return (NS.CanAccessValue(frame.inUse) and frame.inUse and true)
      or NS.IsDockedChatFrame(frame) or IsShown(frame)
  end
  local index = NS.GetChatFrameIndex(frame)
  if index and type(_G.FCF_IsChatWindowIndexActive) == "function" then
    local ok, active = pcall(_G.FCF_IsChatWindowIndexActive, index)
    if ok and NS.CanAccessValue(active) then return active and true or false end
    return false
  end
  return frame == _G.ChatFrame1 or frame == _G.DEFAULT_CHAT_FRAME
    or NS.IsDockedChatFrame(frame) or IsShown(frame)
end

function NS.GetActiveChatFrames()
  local frames, seen = {}, {}
  local iterated = false
  if type(_G.FCF_IterateActiveChatWindows) == "function" then
    local ok = pcall(_G.FCF_IterateActiveChatWindows, function(frame)
      iterated = true
      AddUniqueFrame(frames, seen, frame)
    end)
    if not ok then iterated = false end
  end
  if not iterated then
    for index = 1, NS.GetMaxPermanentChatWindows() do
      local frame = _G["ChatFrame" .. index]
      if NS.IsActiveChatFrame(frame) then AddUniqueFrame(frames, seen, frame) end
    end
  end
  for _, frame in ipairs(NS.GetChatFrames()) do
    if NS.CanAccessValue(frame.isTemporary) and frame.isTemporary and NS.IsActiveChatFrame(frame) then
      AddUniqueFrame(frames, seen, frame)
    end
  end
  return frames
end

function NS.ResolveClosedChatFrame(frame, fallback)
  if NS.CanAccessObject(fallback) then return fallback end
  if NS.CanAccessObject(frame) then return frame end
end

function NS.AddMessageEventFilter(event, callback)
  if type(event) ~= "string" or type(callback) ~= "function" then return false end
  local fn = _G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter
  if type(fn) ~= "function" then fn = _G.ChatFrame_AddMessageEventFilter end
  if type(fn) ~= "function" then return false end
  return pcall(fn, event, callback)
end

function NS.RemoveMessageEventFilter(event, callback)
  if type(event) ~= "string" or type(callback) ~= "function" then return false end
  local fn = _G.ChatFrameUtil and _G.ChatFrameUtil.RemoveMessageEventFilter
  if type(fn) ~= "function" then fn = _G.ChatFrame_RemoveMessageEventFilter end
  if type(fn) ~= "function" then return false end
  return pcall(fn, event, callback)
end

function NS.CollectChatText(frame, maxLines)
  if NS.IsChatMessagingRestricted() or not NS.CanAccessObject(frame)
    or type(frame.GetNumMessages) ~= "function" or type(frame.GetMessageInfo) ~= "function"
  then return "" end
  local ok, count = pcall(frame.GetNumMessages, frame)
  count = ok and NS.SafeNumber(count, 0) or 0
  count = math.max(0, math.floor(count))
  maxLines = NS.Clamp(math.floor(NS.SafeNumber(maxLines, 500)), 1, 5000)
  local lines = {}
  for index = math.max(1, count - maxLines + 1), count do
    local readable, text = pcall(frame.GetMessageInfo, frame, index)
    if readable and NS.CanAccessValue(text) and type(text) == "string" and text ~= "" then
      lines[#lines + 1] = NS.SafeTrunc(text, 4000)
    end
  end
  return table.concat(lines, "\n")
end
