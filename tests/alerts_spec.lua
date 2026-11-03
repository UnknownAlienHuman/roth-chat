-- Alerts owns only the flashes it successfully starts.

local registeredModule
local addMessageHook
local restricted = false
local inaccessibleValue
local inaccessibleObject
local startCount = 0
local stopCount = 0

local frame = { inUse = true, GetName = function() return "ChatFrame2" end }
local addonFrame = { inUse = true, GetName = function() return "ChatFrame3" end }
local selectedFrame = {}
local nativeTab = { alerting = true }
local addonTab = {} -- Native tabs may have no alert flag before their first flash.
_G.ChatFrame2Tab = nativeTab
_G.ChatFrame3Tab = addonTab
_G.SELECTED_CHAT_FRAME = selectedFrame
_G.FCF_StartAlertFlash = function(target)
  startCount = startCount + 1
  if target == addonFrame then addonTab.alerting = true else nativeTab.alerting = true end
end
_G.FCF_StopAlertFlash = function(target)
  stopCount = stopCount + 1
  if target == addonFrame then addonTab.alerting = false else nativeTab.alerting = false end
end

_G.RothChat = {
  RegisterModule = function(_, module) registeredModule = module end,
}

local NS = {
  IsChatMessagingRestricted = function() return restricted end,
  CanAccessValue = function(value) return value == nil or value ~= inaccessibleValue end,
  CanAccessObject = function(value)
    return type(value) == "table" and value ~= inaccessibleObject
  end,
  IsActiveChatFrame = function(candidate)
    return (candidate == frame or candidate == addonFrame) and candidate.inUse
  end,
  IsDockedChatFrame = function(candidate) return candidate == frame or candidate == addonFrame end,
  GetSelectedDockChatFrame = function() return selectedFrame end,
  GetChatFrames = function() return { frame, addonFrame } end,
}

assert(loadfile("Modules/Alerts.lua"))("RothChat", NS)
local module = assert(registeredModule)
local core = {
  IsModuleActive = function(_, name) return name == "Alerts" end,
  EnsureChatLifecycleHooks = function() end,
  RegisterAddMessageHook = function(_, callback, owner)
    assert(owner == module)
    addMessageHook = callback
  end,
  UnregisterAddMessageHooks = function(_, owner)
    assert(owner == module)
    addMessageHook = nil
  end,
  On = function() end,
}

module:Init(core)
module:OnEnable(core)
assert(type(addMessageHook) == "function")
assert(nativeTab.alerting and startCount == 0 and stopCount == 0,
  "enable must leave a pre-existing native flash alone")

restricted = true
addMessageHook(frame, "restricted message")
assert(startCount == 0)
restricted = false

local secretText = {}
inaccessibleValue = secretText
addMessageHook(frame, secretText)
assert(startCount == 0, "an inaccessible AddMessage payload must not drive tab alerting")
inaccessibleValue = nil

addMessageHook(frame, "ordinary text on an already-flashing native tab")
assert(nativeTab.alerting and startCount == 0,
  "Alerts must not claim or restart a flash it did not start")

addMessageHook(addonFrame, "ordinary displayed text")
assert(startCount == 1 and addonTab.alerting)

module:OnDisable(core)
assert(addMessageHook == nil)
assert(nativeTab.alerting and not addonTab.alerting,
  "disable must stop the addon-owned flash and preserve the native flash")
assert(stopCount == 1)

module:OnEnable(core)
addMessageHook(addonFrame, "another message after the flag was cleared")
assert(startCount == 2 and addonTab.alerting)
module:OnDisable(core)
assert(stopCount == 2 and nativeTab.alerting and not addonTab.alerting)

print("alerts_spec: ok")
