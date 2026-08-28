-- Restore ownership contract.
-- Verifies explicit false fade snapshots and temporary-frame exclusion.

local registeredModule
local addMessageHook
local runtimeActive = true

_G.RothChat = {
  RegisterModule = function(_, module)
    registeredModule = module
  end,
}

_G.InCombatLockdown = function()
  return false
end
_G.time = os.time
_G.date = os.date

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
}

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

assert(loadfile("Modules/Restore.lua"))("RothChat", NS)
local module = assert(registeredModule)

local core = {
  db = { profile = {} },
  Get = function(_, key)
    if key == "restoreEnabled" then return true end
    if key == "restoreMaxLinesPerChat" then return 1200 end
  end,
  IsModuleActive = function(_, name)
    return name == "Restore" and runtimeActive
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

assert(fading == true)
assert(timeVisible == 12)
assert(fadeDuration == 3)
assert(type(addMessageHook) == "function")

frame.isTemporary = true
addMessageHook(frame, "temporary whisper", 1, 1, 1)
assert(core.db.restore.frames[1] == nil, "temporary frames must not become durable persistence buckets")

frame.isTemporary = false
addMessageHook(frame, "permanent message", 1, 1, 1)
local bucket = assert(core.db.restore.frames[1])
assert(#bucket.entries == 1)
assert(bucket.entries[1][2] == "permanent message")

runtimeActive = false
module:OnDisable(core)
assert(fading == false, "explicit false fading state must be restored")
assert(timeVisible == 42)
assert(fadeDuration == 7)
assert(addMessageHook == nil)

print("restore_spec: ok")
