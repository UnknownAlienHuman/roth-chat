-- RothChat - Retail platform boundaries layered over generic Util helpers.
-- Owns rate-limited diagnostics and active Blizzard chat-frame discovery.

local ADDON_NAME, NS = ...
NS = NS or {}

local ERROR_REPEAT_WINDOW = 10
local ERROR_CACHE_LIMIT = 64
local errorReporting = false
local errorSeen = {}
local errorSeenCount = 0

local function PackValues(...)
  return { n = select("#", ...), ... }
end

local function GetNow()
  if type(_G.GetTime) == "function" then
    local ok, value = pcall(_G.GetTime)
    if ok and type(value) == "number" then return value end
  end
  if type(_G.time) == "function" then
    local ok, value = pcall(_G.time)
    if ok and type(value) == "number" then return value end
  end
  return 0
end

local function FormatError(err)
  local text = tostring(err)
  if type(_G.debugstack) == "function" then
    local ok, stack = pcall(_G.debugstack, 2, 25, 25)
    if ok and type(stack) == "string" and stack ~= "" then
      text = text .. "\n" .. stack
    end
  end
  return text
end

function NS.IsReportingError()
  return errorReporting
end

function NS.ReportError(label, err)
  if errorReporting then return false end

  label = type(label) == "string" and label or "RothChat"
  local text = type(err) == "string" and err or tostring(err)
  local key = label .. "\031" .. text:sub(1, 240)
  local now = GetNow()
  local previous = errorSeen[key]
  if previous and (now - previous) < ERROR_REPEAT_WINDOW then
    return false
  end

  if errorSeenCount >= ERROR_CACHE_LIMIT then
    errorSeen = {}
    errorSeenCount = 0
  end
  if previous == nil then errorSeenCount = errorSeenCount + 1 end
  errorSeen[key] = now

  errorReporting = true
  local frame = _G.DEFAULT_CHAT_FRAME
  if frame and type(frame.AddMessage) == "function" then
    pcall(frame.AddMessage, frame, string.format("|cffff4040%s error|r: %s", label, text))
  end
  errorReporting = false
  return true
end

-- Lua 5.1 xpcall does not portably forward extra arguments. Use pcall's
-- vararg contract and preserve nil/trailing return positions explicitly.
function NS.SafeCall(label, fn, ...)
  if type(fn) ~= "function" then return true end
  local results = PackValues(pcall(fn, ...))
  if not results[1] then
    local errorText = FormatError(results[2])
    NS.ReportError(label, errorText)
    return false, errorText
  end
  return true, unpack(results, 2, results.n)
end

local function AddUniqueFrame(out, seen, frame)
  if not frame or seen[frame] then return end
  seen[frame] = true
  out[#out + 1] = frame
end

local function IsShown(frame)
  if not frame or type(frame.IsShown) ~= "function" then return false end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown and true or false
end

function NS.IsActiveChatFrame(chatFrame)
  if not chatFrame then return false end

  if chatFrame.isTemporary then
    return chatFrame.inUse and true
      or chatFrame.isDocked and true
      or IsShown(chatFrame)
  end

  local index = NS.GetChatFrameIndex and NS.GetChatFrameIndex(chatFrame)
  if type(index) == "number" and type(_G.FCF_IsChatWindowIndexActive) == "function" then
    local ok, active = pcall(_G.FCF_IsChatWindowIndexActive, index)
    if ok then return active and true or false end
  end

  if chatFrame == _G.DEFAULT_CHAT_FRAME or chatFrame == _G.ChatFrame1 then
    return true
  end
  return chatFrame.isDocked and true or IsShown(chatFrame)
end

function NS.GetMaxPermanentChatWindows()
  local constants = _G.Constants
  local chatConstants = constants and constants.ChatFrameConstants
  local maxWindows = chatConstants and chatConstants.MaxChatWindows
  if type(maxWindows) == "number" and maxWindows >= 1 then return maxWindows end
  if type(_G.NUM_CHAT_WINDOWS) == "number" and _G.NUM_CHAT_WINDOWS >= 1 then
    return _G.NUM_CHAT_WINDOWS
  end
  return 10
end

local function AddActivePermanentFallback(out, seen)
  local maxWindows = NS.GetMaxPermanentChatWindows()
  for index = 1, maxWindows do
    local frame = _G["ChatFrame" .. index]
    if NS.IsActiveChatFrame(frame) then AddUniqueFrame(out, seen, frame) end
  end
end

function NS.GetActiveChatFrames()
  local out, seen = {}, {}
  local iterated = false

  if type(_G.FCF_IterateActiveChatWindows) == "function" then
    local ok = pcall(_G.FCF_IterateActiveChatWindows, function(frame)
      iterated = true
      AddUniqueFrame(out, seen, frame)
    end)
    if not ok then iterated = false end
  end

  if not iterated then
    AddActivePermanentFallback(out, seen)
  end

  -- Blizzard's active-window iterator covers only permanent slots. Temporary
  -- whisper frames live above MaxChatWindows and remain in CHAT_FRAMES after
  -- close, so apply the explicit inUse/isDocked/shown predicate here.
  for _, frame in ipairs(NS.GetChatFrames and NS.GetChatFrames() or {}) do
    if frame and frame.isTemporary and NS.IsActiveChatFrame(frame) then
      AddUniqueFrame(out, seen, frame)
    end
  end

  return out
end

function NS.ResolveClosedChatFrame(frame, fallback)
  return fallback or frame
end
