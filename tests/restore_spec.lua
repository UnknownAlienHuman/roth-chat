-- Restore ownership and persistence-schema contract.
-- Verifies fade ownership, temporary-frame exclusion, durable sanitization,
-- timestamp separation, legacy compatibility and replay behavior.

local registeredModule
local addMessageHook
local runtimeActive = true
local timestampsActive = true
local replayed = {}

_G.RothChat = {
  RegisterModule = function(_, module)
    registeredModule = module
  end,
}

_G.InCombatLockdown = function()
  return false
end
_G.GetServerTime = function()
  return 12345
end
_G.time = function()
  return 12345
end
_G.date = function(format, timestamp)
  assert(timestamp == 12345)
  if format == "[%H:%M]" then return "[12:34]" end
  if format == "[%H:%M:%S]" then return "[12:34:56]" end
  error("unexpected date format: " .. tostring(format))
end
_G.NUM_CHAT_WINDOWS = 1

local fading = false
local timeVisible = 42
local fadeDuration = 7

local frame = {
  isTemporary = false,
  GetFading = function() return fading end,
  SetFading = function(_, value) fading = value end,
  GetTimeVisible = function() return timeVisible end,
  SetTimeVisible = function(_, value) timeVisible = value end,
  GetFadeDuration = function() return fadeDuration end,
  SetFadeDuration = function(_, value) fadeDuration = value end,
  AddMessage = function(_, text, r, g, b)
    replayed[#replayed + 1] = { text, r, g, b }
  end,
  ScrollToBottom = function()
  end,
}
_G.ChatFrame1 = frame

local NS = {
  GetChatFrames = function()
    return { frame }
  end,
  GetChatFrameIndex = function(candidate)
    return candidate == frame and 1 or nil
  end,
  CanAccessValue = function()
    return true
  end,
  SafeToString = tostring,
  SafeTrunc = function(text, maxChars)
    return text:sub(1, maxChars)
  end,
  Clamp = function(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
  end,
  SafeCall = function(_, fn, ...)
    return pcall(fn, ...)
  end,
}

assert(loadfile("ChatText.lua"))("RothChat", NS)
assert(loadfile("Modules/Restore.lua"))("RothChat", NS)
local module = assert(registeredModule)

local core = {
  db = { profile = {} },
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
  EnsureChatLifecycleHooks = function()
  end,
  On = function()
  end,
  Emit = function()
  end,
  Defer = function(_, callback)
    callback()
  end,
}

module:Init(core)
module:OnEnable(core)

assert(core.db.restore.version == 2)
assert(fading == true)
assert(timeVisible == 12)
assert(fadeDuration == 3)
assert(type(addMessageHook) == "function")

frame.isTemporary = true
addMessageHook(frame, "temporary whisper", 1, 1, 1)
assert(core.db.restore.frames[1] == nil, "temporary frames must not become durable persistence buckets")

frame.isTemporary = false
addMessageHook(
  frame,
  "|cff8E8E8E[12:34]|r |HBNplayer:Foo:1|hVisible|h |Kaccount|k",
  0.1,
  0.2,
  0.3
)

local bucket = assert(core.db.restore.frames[1])
assert(#bucket.entries == 1)
local entry = bucket.entries[1]
assert(entry[1] == 12345)
assert(entry[2] == "Visible ???", "v2 must store timestamp-free durable text")
assert(entry[3] == 0.1 and entry[4] == 0.2 and entry[5] == 0.3)
assert(entry[6] == 2)
assert(not entry[2]:find("BNplayer", 1, true))
assert(not entry[2]:find("|K", 1, true))

assert(core:GetRestoreText(frame, 500, false) == "Visible ???")
assert(core:GetRestoreText(frame, 500, true) == "[12:34:56] Visible ???")

module:OnLogin(core)
assert(#replayed == 1)
assert(replayed[1][1] == "|cff8E8E8E[12:34]|r Visible ???")

replayed = {}
timestampsActive = false
module:OnLogin(core)
assert(#replayed == 1)
assert(replayed[1][1] == "Visible ???", "replay must obey current Timestamps activation")

-- Legacy v1 rows stored the rendered timestamp inside entry[2]. Export and
-- replay must strip it before applying the current timestamp policy.
bucket.entries = {
  { 12345, "|cff8E8E8E[12:34]|r legacy", 1, 1, 1 },
}
assert(core:GetRestoreText(frame, 500, false) == "legacy")
assert(core:GetRestoreText(frame, 500, true) == "[12:34:56] legacy")

runtimeActive = false
module:OnDisable(core)
assert(fading == false, "explicit false fading state must be restored")
assert(timeVisible == 42)
assert(fadeDuration == 7)
assert(addMessageHook == nil)

print("restore_spec: ok")
