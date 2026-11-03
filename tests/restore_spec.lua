-- Restore ownership, identity and persistence-schema contract.

local registeredModule
local addMessageHook
local runtimeActive = true
local timestampsActive = true
local nativeFormat = nil
local restricted = false
local listeners = {}
local replayed = {}
local messageCount = 0
local emittedFeed = {}
local queueNextFrame = false
local pendingNextFrame
local windowName = "General"
local layoutRevision = 1
local windowInfoCalls = 0
local sortCalls = 0
local originalSort = table.sort
table.sort = function(...)
  sortCalls = sortCalls + 1
  return originalSort(...)
end

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
  windowInfoCalls = windowInfoCalls + 1
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
  SafeNumber = function(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then return value end
    return fallback
  end,
  IsChatMessagingRestricted = function() return restricted end,
  CanAccessValue = function(value) return value ~= "inaccessible-color" end,
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
    if queueNextFrame then pendingNextFrame = callback else callback() end
  end,
  CancelScheduled = function() pendingNextFrame = nil end,
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
        [2] = { entries = { { 12345, "second old slot", 1, 1, 1, 2 } } },
        [11] = { entries = { { 12345, "invalid permanent slot", 1, 1, 1, 2 } } },
        invalid = { entries = { { 12345, "invalid key", 1, 1, 1, 2 } } },
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
  On = function(_, event, callback)
    listeners[event] = callback
  end,
  Emit = function(_, event, frameArg, text, r, g, b, timestamp)
    emittedFeed[#emittedFeed + 1] = { event, frameArg, text, r, g, b, timestamp }
  end,
  Defer = function(_, callback) callback() end,
}

module:Init(core)
assert(core.db.restore.version == 3)
local legacySnapshot = assert(core.db.restore.legacyFrames, "old unbound scrollback must remain recoverable")
assert(legacySnapshot.version == 2)
assert(legacySnapshot.frames[1].entries[1][2] == "unverified old slot")
assert(legacySnapshot.frames[2].entries[1][2] == "second old slot")
assert(legacySnapshot.frames[11] == nil and legacySnapshot.frames.invalid == nil,
  "legacy recovery must be bounded to valid permanent slots")
local legacySlotCount = 0
for index in pairs(legacySnapshot.frames) do
  assert(type(index) == "number" and index >= 1 and index <= 10)
  legacySlotCount = legacySlotCount + 1
end
assert(legacySlotCount == 2)
assert(next(core.db.restore.frames) == nil, "legacy rows must not enter live v3 buckets")

module:OnEnable(core)
local initialWindowInfoCalls, initialSortCalls = windowInfoCalls, sortCalls
assert(initialWindowInfoCalls == 1 and initialSortCalls == 2,
  "initial layout pass should compute one fingerprint and sort each configuration list once")
assert(fading == true)
assert(timeVisible == 12)
assert(fadeDuration == 3)
assert(maxLines == 1200, "Restore must expand Blizzard's 128-line buffer")
assert(type(addMessageHook) == "function")

assert(core:GetRestoreText(frame, 500, true) == "", "legacy recovery buckets must stay out of new exports")

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
assert(windowInfoCalls == initialWindowInfoCalls and sortCalls == initialSortCalls,
  "AddMessage and export must reuse fingerprints only while layout revision is unchanged")
assert(emittedFeed[#emittedFeed][1] == "CHAT_FEED")
assert(emittedFeed[#emittedFeed][4] == 0.1 and emittedFeed[#emittedFeed][5] == 0.2 and emittedFeed[#emittedFeed][6] == 0.3)

-- Restore export owns timestamp inclusion but preserves stable ordinary links;
-- CopyOverlay flattens those links later in its copy-only normalization step.
assert(core:GetRestoreText(frame, 500, false) == "|Hplayer:Tester|h[Tester]|h ???")
assert(core:GetRestoreText(frame, 500, true) == "[12:34:56] |Hplayer:Tester|h[Tester]|h ???")

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
local beforeLayoutChangeWindowInfoCalls, beforeLayoutChangeSortCalls = windowInfoCalls, sortCalls
layoutRevision = layoutRevision + 1
assert(core:GetRestoreText(frame, 500, false) == "")
assert(core.db.restore.frames[1] == nil)
assert(windowInfoCalls == beforeLayoutChangeWindowInfoCalls + 1 and sortCalls == beforeLayoutChangeSortCalls + 2,
  "a changed layout revision must recompute the frame fingerprint")

nativeFormat = nil
addMessageHook(frame, "new window message", 1, 1, 1)
assert(core.db.restore.frames[1] ~= nil)
assert(type(listeners.CHAT_FRAME_CLOSED) == "function")
listeners.CHAT_FRAME_CLOSED(nil, core, frame)
assert(core.db.restore.frames[1] == nil, "closing a permanent slot must retire its bucket")
assert(maxLines == 128, "closing must return frame settings to Blizzard")

-- Inaccessible display colors are discarded before they enter either storage
-- or the synchronous feed consumed by other modules.
local beforeCloseAddWindowInfoCalls = windowInfoCalls
addMessageHook(frame, "safe text, inaccessible color", "inaccessible-color", 0.4, 0.5)
assert(windowInfoCalls == beforeCloseAddWindowInfoCalls + 1,
  "closing a frame must invalidate its cached fingerprint")
local safeColorEntry = core.db.restore.frames[1].entries[#core.db.restore.frames[1].entries]
assert(safeColorEntry[3] == nil)
assert(emittedFeed[#emittedFeed][4] == nil)

local beforeRestrictedWrite = #core.db.restore.frames[1].entries
local beforeRestrictedFeed = #emittedFeed
restricted = true
addMessageHook(frame, "must not be retained", 1, 1, 1)
assert(#core.db.restore.frames[1].entries == beforeRestrictedWrite)
assert(#emittedFeed == beforeRestrictedFeed)
assert(core:GetRestoreText(frame, 500, true) == "", "copy/export is unavailable during chat lockdown")

-- A pending one-shot restore is canceled on the restriction transition and is
-- not replayed later when access returns.
messageCount = 0
replayed = {}
queueNextFrame = true
module:OnLogin(core)
assert(type(pendingNextFrame) == "function")
listeners.CHAT_RESTRICTION_CHANGED(nil, core, true)
assert(pendingNextFrame == nil, "restriction entry must cancel queued replay")
queueNextFrame = false
restricted = false
if pendingNextFrame then pendingNextFrame() end
assert(#replayed == 0, "restriction exit must not replay content captured or queued during lockdown")

for _ = 1, 1300 do
  addMessageHook(frame, "bounded history row", 1, 1, 1)
end
assert(#core.db.restore.frames[1].entries <= 1250, "Restore buckets must remain bounded around the configured 1200-line limit")

runtimeActive = false
module:OnDisable(core)
assert(fading == false)
assert(timeVisible == 42)
assert(fadeDuration == 7)
assert(maxLines == 128)
assert(addMessageHook == nil)

local beforeDisableReenableCalls = windowInfoCalls
runtimeActive = true
module:OnEnable(core)
assert(windowInfoCalls == beforeDisableReenableCalls + 1,
  "module disable must invalidate frame fingerprint caches")
runtimeActive = false
module:OnDisable(core)
table.sort = originalSort

local v1Bucket = { entries = { { 12345, "v1 recovery row", 1, 1, 1 } } }
local v1Core = {
  db = { profile = {}, restore = { version = 1, frames = { [3] = v1Bucket } } },
  Get = core.Get,
  IsModuleActive = core.IsModuleActive,
}
module:Init(v1Core)
assert(v1Core.db.restore.version == 3)
assert(v1Core.db.restore.frames[3] == nil)
assert(v1Core.db.restore.legacyFrames.version == 1)
assert(v1Core.db.restore.legacyFrames.frames[3] == v1Bucket,
  "v1 migration must preserve old bucket references in the recovery snapshot")

print("restore_spec: ok")
