-- Restore ownership, identity and persistence-schema contract.

local registeredModule
local addMessageHook
local runtimeActive = true
local timestampsActive = true
local nativeFormat = nil
local listeners = {}
local replayed = {}
local messageCount = 0
local windowName = "General"

_G.RothChat = {
  RegisterModule = function(_, module)
    registeredModule = module
  end,
}
_G.InCombatLockdown = function() return false end
_G.time = function() return 12345 end
_G.GetServerTime = function() return 12345 end
_G.date = function(format, timestamp)
  assert(timestamp == 12345)
  if format == "[%H:%M]" then return "[12:34]" end
  if format == "[%H:%M:%S]" then return "[12:34:56]" end
  error("unexpected date format: " .. tostring(format))
end
_G.ChatFrameUtil = {
  GetTimestampFormat = function() return nativeFormat end,
}
_G.TimeUtil = {
  BetterDate = function(format, timestamp)
    assert(format == "[%H:%M] ")
    assert(timestamp == 12345)
    return "[12:34] "
  end,
}
_G.FCF_GetChatWindowInfo = function(index)
  assert(index == 1)
  return windowName
end

local fading = false
local timeVisible = 42
local fadeDuration = 7
local maxLines = 128

local frame = {
  isTemporary = false,
  inUse = true,
  messageTypeList = { "SAY", "GUILD" },
  channelList = { "General" },
  GetID = function() return 1 end,
  GetName = function() return "ChatFrame1" end,
  GetFading = function() return fading end,
  SetFading = function(_, value) fading = value end,
  GetTimeVisible = function() return timeVisible end,
  SetTimeVisible = function(_, value) timeVisible = value end,
  GetFadeDuration = function() return fadeDuration end,
  SetFadeDuration = function(_, value) fadeDuration = value end,
  GetMaxLines = function() return maxLines end,
  SetMaxLines = function(_, value) maxLines = value end,
  GetNumMessages = function() return messageCount end,
  AddMessage = function(_, text, r, g, b)
    replayed[#replayed + 1] = { text, r, g, b }
    messageCount = messageCount + 1
  end,
  ScrollToBottom = function() end,
}
_G.ChatFrame1 = frame

local NS = {
  GetChatFrames = function() return { frame } end,
  GetActiveChatFrames = function() return { frame } end,
  IsActiveChatFrame = function(candidate) return candidate == frame and frame.inUse end,
  GetChatFrameIndex = function(candidate) return candidate == frame and 1 or nil end,
  GetMaxPermanentChatWindows = function() return 10 end,
  CanAccessValue = function() return true end,
  SafeToString = tostring,
  SafeTrunc = function(text, maxChars) return text:sub(1, maxChars) end,
  Clamp = function(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
  end,
  SafeCall = function(_, fn, ...)
    return pcall(fn, ...)
  end,
  RunNextFrame = function(_, callback)
    callback()
  end,
  CancelScheduled = function() end,
}

assert(loadfile("ChatText.lua"))("RothChat", NS)
assert(loadfile("Modules/Restore.lua"))("RothChat", NS)
local module = assert(registeredModule)

local core = {
  db = {
    profile = {},
    restore = {
      version = 2,
      frames = {
        [1] = { entries = { { 12345, "unverified old slot", 1, 1, 1, 2 } } },
      },
    },
  },
  Get = function(_, key)
    if key == "restoreEnabled" then return true end
    if key == "restoreMaxLinesPerChat" then return 1200 end
    if key == "timestampColor" then return "8E8E8E" end
  end,
  IsModuleActive = function(_, name)
    if name == "Restore" then return runtimeActive end
    if name == "Timestamps" then return timestampsActive end
    return false
  end,
  RegisterAddMessageHook = function(_, callback, owner)
    assert(owner == module)
    addMessageHook = callback
  end,
  UnregisterAddMessageHooks = function(_, owner)
    assert(owner == module)
    addMessageHook = nil
  end,
  EnsureChatLifecycleHooks = function() end,
  On = function(_, event, callback)
    listeners[event] = callback
  end,
  Emit = function() end,
  Defer = function(_, callback) callback() end,
}

module:Init(core)
assert(core.db.restore.version == 3)
assert(core.db.restore.frames[1] == nil, "unfingerprinted slot history must be retired")

module:OnEnable(core)
assert(fading == true)
assert(timeVisible == 12)
assert(fadeDuration == 3)
assert(maxLines == 1200, "Restore must expand Blizzard's 128-line buffer")
assert(type(addMessageHook) == "function")

frame.isTemporary = true
addMessageHook(frame, "temporary whisper", 1, 1, 1)
assert(core.db.restore.frames[1] == nil)

frame.isTemporary = false
addMessageHook(
  frame,
  "|cff8E8E8E[12:34]|r |Hplayer:Tester:77:WHISPER:Target|h[Tester]|h |Kaccount|k",
  0.1,
  0.2,
  0.3
)

local bucket = assert(core.db.restore.frames[1])
assert(type(bucket.fingerprint) == "string" and bucket.fingerprint ~= "")
assert(#bucket.entries == 1)
local entry = bucket.entries[1]
assert(entry[1] == 12345)
assert(entry[2] == "|Hplayer:Tester|h[Tester]|h ???")
assert(entry[3] == 0.1 and entry[4] == 0.2 and entry[5] == 0.3)
assert(entry[6] == 2)

assert(core:GetRestoreText(frame, 500, false) == "[Tester] ???")
assert(core:GetRestoreText(frame, 500, true) == "[12:34:56] [Tester] ???")

messageCount = 0
module:OnLogin(core)
assert(#replayed == 1)
assert(replayed[1][1] == "|cff8E8E8E[12:34]|r |Hplayer:Tester|h[Tester]|h ???")

-- A second lifecycle delivery cannot append the same history again.
module:OnLogin(core)
assert(#replayed == 1)

-- Re-enable with an already populated frame: existing Blizzard contents own
-- ordering, so Restore must not append its old rows after current messages.
runtimeActive = false
module:OnDisable(core)
assert(maxLines == 128)
runtimeActive = true
module:OnEnable(core)
messageCount = 1
replayed = {}
module:OnLogin(core)
assert(#replayed == 0, "non-empty frame must suppress replay")

-- Native timestamp ownership is reconstructed for direct AddMessage replay.
runtimeActive = false
module:OnDisable(core)
runtimeActive = true
module:OnEnable(core)
messageCount = 0
nativeFormat = "[%H:%M] "
timestampsActive = true
replayed = {}
module:OnLogin(core)
assert(#replayed == 1)
assert(replayed[1][1] == "[12:34] |Hplayer:Tester|h[Tester]|h ???")

-- Reusing the same numeric slot with a different window configuration retires
-- the prior bucket instead of leaking its history into the new window.
windowName = "Loot"
frame.messageTypeList = { "LOOT" }
assert(core:GetRestoreText(frame, 500, false) == "")
assert(core.db.restore.frames[1] == nil)

nativeFormat = nil
addMessageHook(frame, "new window message", 1, 1, 1)
assert(core.db.restore.frames[1] ~= nil)
assert(type(listeners.CHAT_FRAME_CLOSED) == "function")
listeners.CHAT_FRAME_CLOSED(nil, core, frame)
assert(core.db.restore.frames[1] == nil, "closing a permanent slot must retire its bucket")
assert(maxLines == 128, "closing must return frame settings to Blizzard")

runtimeActive = false
module:OnDisable(core)
assert(fading == false)
assert(timeVisible == 42)
assert(fadeDuration == 7)
assert(maxLines == 128)
assert(addMessageHook == nil)

print("restore_spec: ok")
