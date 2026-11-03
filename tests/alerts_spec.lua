-- Alerts ignores inaccessible or restricted chat output without coercing it.

local registeredModule
local addMessageHook
local restricted = false
local inaccessible = nil
local flashCount = 0

local frame = {
  inUse = true,
  GetName = function() return "ChatFrame2" end,
}
local selectedFrame = {}
local tab = { alerting = false }
_G.ChatFrame2Tab = tab
_G.SELECTED_CHAT_FRAME = selectedFrame
_G.FCF_StartAlertFlash = function(target)
  assert(target == frame)
  flashCount = flashCount + 1
  tab.alerting = true
end
_G.FCF_StopAlertFlash = function(target)
  assert(target == frame)
  tab.alerting = false
end

_G.RothChat = {
  RegisterModule = function(_, module) registeredModule = module end,
}

local NS = {
  IsChatMessagingRestricted = function() return restricted end,
  CanAccessValue = function(value) return value ~= inaccessible end,
  IsActiveChatFrame = function(candidate) return candidate == frame and frame.inUse end,
  IsDockedChatFrame = function(candidate) return candidate == frame end,
  GetSelectedDockChatFrame = function() return selectedFrame end,
  GetChatFrames = function() return { frame } end,
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

restricted = true
addMessageHook(frame, "restricted message")
assert(flashCount == 0)
restricted = false

local secretText = {}
inaccessible = secretText
addMessageHook(frame, secretText)
assert(flashCount == 0, "an inaccessible AddMessage payload must not drive tab alerting")

inaccessible = nil
addMessageHook(frame, "ordinary displayed text")
assert(flashCount == 1)

module:OnDisable(core)
assert(addMessageHook == nil)
assert(tab.alerting == false)

print("alerts_spec: ok")
