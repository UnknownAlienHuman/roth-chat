-- Restore owns bounded durable data only; Blizzard owns live frame capacity and fading.
local registeredModule
local addMessageHook
local listeners = {}
local runtimeActive = true
local timestampsActive = true
local nativeTimestamps = false
local restricted = false
local messageCount = 0
local frameCapacity = 3
local replayed = {}
local pendingNextFrame
local deferNextFrame = false
local layoutRevision = 1
local inaccessibleValue
local inaccessibleObject

_G.RothChat = { RegisterModule = function(_, module) registeredModule = module end }
_G.time = function() return 12345 end
_G.GetServerTime = function() return 12345 end

local frame = {
  name = "General",
  isTemporary = false,
  inUse = true,
  messageTypeList = { "SAY", "GUILD" },
  channelList = { "General" },
}
function frame:GetID() return 1 end
function frame:GetName() return "ChatFrame1" end
function frame:GetNumMessages()
  if messageCount == inaccessibleValue then return inaccessibleValue end
  return messageCount
end
function frame:GetMaxLines() return frameCapacity end
function frame:SetMaxLines() error("Restore must not own Blizzard frame capacity") end
function frame:SetFading() error("Restore must not own Blizzard fade policy") end
function frame:SetTimeVisible() error("Restore must not own Blizzard fade policy") end
function frame:SetFadeDuration() error("Restore must not own Blizzard fade policy") end
function frame:AddMessage(text, r, g, b)
  replayed[#replayed + 1] = { text, r, g, b }
  messageCount = messageCount + 1
end
function frame:ScrollToBottom() end
_G.ChatFrame1 = frame

local NS = {
  GetChatFrames = function() return { frame } end,
  GetActiveChatFrames = function() return { frame } end,
  IsActiveChatFrame = function(candidate) return candidate == frame and frame.inUse end,
  GetChatFrameIndex = function(candidate) return candidate == frame and 1 or nil end,
  GetMaxPermanentChatWindows = function() return 10 end,
  SafeNumber = function(value, fallback)
    if value ~= inaccessibleValue and type(value) == "number" and value == value
      and value ~= math.huge and value ~= -math.huge
    then
      return value
    end
    return fallback
  end,
  IsChatMessagingRestricted = function() return restricted end,
  CanAccessValue = function(value) return value == nil or value ~= inaccessibleValue end,
  CanAccessObject = function(value) return type(value) == "table" and value ~= inaccessibleObject end,
  SafeToString = function(value) return type(value) == "string" and value or "" end,
  SafeTrunc = function(text, maxChars) return text:sub(1, maxChars) end,
  Clamp = function(value, minValue, maxValue) return math.max(minValue, math.min(maxValue, value)) end,
  SafeCall = function(_, callback, ...) return pcall(callback, ...) end,
  SanitizeDurableChatText = function(text)
    if restricted or text == inaccessibleValue or type(text) ~= "string" then return "" end
    return text:gsub("|K.-|k", "???")
  end,
  StripDisplayTimestampPrefix = function(text, _, generic)
    if generic then return (text:gsub("^%[%d%d:%d%d%]%s*", "")) end
    return (text:gsub("^|cff%x%x%x%x%x%x%[%d%d:%d%d%]|r%s*", ""))
  end,
  FormatChatTimestamp = function(_, _, _, format)
    return format == "%H:%M:%S" and "[12:34:56] " or "|cff8E8E8E[12:34]|r "
  end,
  HasNativeChatTimestamps = function() return nativeTimestamps end,
  FormatNativeChatTimestamp = function() return nativeTimestamps and "[12:34] " or "" end,
  RunNextFrame = function(_, callback)
    if deferNextFrame then pendingNextFrame = callback else callback() end
  end,
  CancelScheduled = function() pendingNextFrame = nil end,
}

assert(loadfile("Modules/Restore.lua"))("RothChat", NS)
local module = assert(registeredModule)
local core = {
  db = {
    profile = {},
    restore = {
      version = 2,
      frames = {
        [1] = { entries = { { 12345, "old slot", 1, 1, 1, 2 } } },
        [2] = { entries = { { 12345, "second slot", 1, 1, 1, 2 } } },
        [11] = { entries = { { 12345, "invalid slot", 1, 1, 1, 2 } } },
      },
    },
  },
  Get = function(_, key)
    if key == "restoreEnabled" then return true end
    if key == "restoreMaxLinesPerChat" then return 1200 end
    if key == "timestampColor" then return "8E8E8E" end
  end,
  GetChatLayoutRevision = function() return layoutRevision end,
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
  On = function(_, event, callback) listeners[event] = callback end,
}

module:Init(core)
assert(core.db.restore.version == 3)
assert(core.db.restore.legacyFrames.frames[1].entries[1][2] == "old slot")
assert(core.db.restore.legacyFrames.frames[2].entries[1][2] == "second slot")
assert(core.db.restore.legacyFrames.frames[11] == nil)
assert(next(core.db.restore.frames) == nil)

module:OnEnable(core)
assert(type(addMessageHook) == "function")
frame.isTemporary = true
addMessageHook(frame, "temporary", 1, 1, 1)
assert(core.db.restore.frames[1] == nil)
frame.isTemporary = false

for index = 1, 5 do addMessageHook(frame, "m" .. index, 0.1, 0.2, 0.3) end
local bucket = assert(core.db.restore.frames[1])
assert(#bucket.entries == 5 and bucket.entries[1][6] == 2)
assert(core:GetRestoreText(frame, 20, false) == "m1\nm2\nm3\nm4\nm5")
assert(core:GetRestoreText(frame, 20, true):find("[12:34:56] m1", 1, true))

-- Exact audit scenario: 1000 durable rows, native capacity 128. A newer
-- unknown row at the end is skipped and does not consume replay capacity.
bucket.entries = {}
for index = 1, 1000 do
  bucket.entries[index] = { 12345, "m" .. index, 0.1, 0.2, 0.3, 2 }
end
bucket.entries[#bucket.entries + 1] = { 12345, "future-row", 1, 1, 1, 3 }
assert(not core:GetRestoreText(frame, 1001, false):find("future-row", 1, true))
assert(core:GetRestoreText(frame, 5, false) == "m996\nm997\nm998\nm999\nm1000",
  "unknown rows must not consume the valid export-line budget")

runtimeActive = false
module:OnDisable(core)
runtimeActive = true
module:OnEnable(core)
frameCapacity = 128
messageCount, replayed, timestampsActive = 0, {}, false
module:OnLogin(core)
assert(#replayed == 128)
assert(replayed[1][1] == "m873" and replayed[128][1] == "m1000")
assert(frameCapacity == 128)

-- Existing native history or unknown native capacity suppresses replay.
runtimeActive = false
module:OnDisable(core)
runtimeActive = true
module:OnEnable(core)
messageCount, replayed = 1, {}
module:OnLogin(core)
assert(#replayed == 0)
runtimeActive = false
module:OnDisable(core)
runtimeActive = true
module:OnEnable(core)
messageCount, replayed, frameCapacity = 0, {}, inaccessibleValue
module:OnLogin(core)
assert(#replayed == 0)
frameCapacity = 128

runtimeActive = false
module:OnDisable(core)
runtimeActive = true
module:OnEnable(core)
messageCount, replayed = -1, {}
module:OnLogin(core)
assert(#replayed == 0, "negative native message counts must not authorize replay")
runtimeActive = false
module:OnDisable(core)
runtimeActive = true
module:OnEnable(core)
messageCount, replayed, frameCapacity = 0, {}, 3.5
module:OnLogin(core)
assert(#replayed == 0, "fractional native capacity must not authorize replay")
frameCapacity = 128

-- Native timestamp presentation is reconstructed only during replay.
runtimeActive = false
module:OnDisable(core)
runtimeActive = true
module:OnEnable(core)
messageCount, replayed, nativeTimestamps, timestampsActive = 0, {}, true, true
module:OnLogin(core)
assert(#replayed == 128 and replayed[1][1] == "[12:34] m873" and replayed[128][1] == "[12:34] m1000")
nativeTimestamps = false

-- Identity permission and revision changes cannot leak a previous slot.
local before = #bucket.entries
inaccessibleValue = "SAY"
addMessageHook(frame, "denied identity", 1, 1, 1)
assert(#bucket.entries == before)
inaccessibleValue = nil
frame.name = "Loot"
frame.messageTypeList = { "LOOT" }
layoutRevision = layoutRevision + 1
assert(core:GetRestoreText(frame, 20, false) == "")
assert(core.db.restore.frames[1] == nil)

addMessageHook(frame, "new owner", "inaccessible-color", 0.4, 0.5)
local newBucket = assert(core.db.restore.frames[1])
assert(newBucket.entries[1][3] == nil)
listeners.CHAT_FRAME_CLOSED(nil, core, frame)
assert(core.db.restore.frames[1] == nil)

-- Restriction entry discards pending replay and blocks read/write.
addMessageHook(frame, "ordinary", 1, 1, 1)
local restrictedCount = #core.db.restore.frames[1].entries
restricted = true
addMessageHook(frame, "blocked", 1, 1, 1)
assert(#core.db.restore.frames[1].entries == restrictedCount)
assert(core:GetRestoreText(frame, 20, true) == "")
deferNextFrame = true
module:OnLogin(core)
assert(type(pendingNextFrame) == "function")
listeners.CHAT_RESTRICTION_CHANGED(nil, core, true)
assert(pendingNextFrame == nil)
deferNextFrame, restricted = false, false

for _ = 1, 1300 do addMessageHook(frame, "bounded", 1, 1, 1) end
assert(#core.db.restore.frames[1].entries <= 1250)

runtimeActive = false
module:OnDisable(core)
assert(addMessageHook == nil)

-- Unknown newer database versions and inaccessible roots remain untouched.
local futureBucket = { entries = { { 12345, "future" } } }
local future = { version = 4, frames = { [1] = futureBucket }, marker = "keep" }
local futureCore = { db = { profile = {}, restore = future }, Get = core.Get, IsModuleActive = core.IsModuleActive }
module:Init(futureCore)
assert(module.db == nil and future.version == 4 and future.marker == "keep" and future.frames[1] == futureBucket)

local denied = { version = 3, frames = {} }
local deniedCore = { db = { profile = {}, restore = denied }, Get = core.Get, IsModuleActive = core.IsModuleActive }
inaccessibleObject = denied
module:Init(deniedCore)
assert(module.db == nil and deniedCore.db.restore == denied)
inaccessibleObject = nil
print("restore_spec: ok")
