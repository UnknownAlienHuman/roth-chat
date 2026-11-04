-- Alerts extends native tab policy without owning native alert state or audio.

local registeredModule
local addMessageHook
local restricted = false
local inaccessibleValue
local inaccessibleObject
local startCount = 0
local stopCount = 0
local alertingTabs = setmetatable({}, { __mode = "k" })

local frame = { inUse = true, GetName = function() return "ChatFrame2" end }
local addonFrame = { inUse = true, GetName = function() return "ChatFrame3" end }
local selectedFrame = {}
local nativeTab = { alerting = false }
local addonTab = { alerting = true }
_G.ChatFrame2Tab = nativeTab
_G.ChatFrame3Tab = addonTab
_G.SELECTED_CHAT_FRAME = selectedFrame
_G.ChatFrameUtil = {
  IsTabAlerting = function(tab) return alertingTabs[tab] == true end,
}
_G.FCF_StartAlertFlash = function(target)
  startCount = startCount + 1
  local tab = target == addonFrame and addonTab or nativeTab
  alertingTabs[tab] = true
end
_G.FCF_StopAlertFlash = function(target)
  stopCount = stopCount + 1
  local tab = target == addonFrame and addonTab or nativeTab
  alertingTabs[tab] = nil
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
}

assert(loadfile("Modules/Alerts.lua"))("RothChat", NS)
local module = assert(registeredModule)
local core = {
  IsModuleActive = function(_, name) return name == "Alerts" end,
  RegisterAddMessageHook = function(_, callback, owner)
    assert(owner == module)
    addMessageHook = callback
  end,
  UnregisterAddMessageHooks = function(_, owner)
    assert(owner == module)
    addMessageHook = nil
  end,
}

module:Init(core)
module:OnEnable(core)
assert(type(addMessageHook) == "function")

restricted = true
addMessageHook(frame, "restricted message")
assert(startCount == 0)
restricted = false

local secretText = {}
inaccessibleValue = secretText
addMessageHook(frame, secretText)
assert(startCount == 0, "an inaccessible AddMessage payload must not drive tab alerting")
inaccessibleValue = nil

-- Current Retail stores native alert state outside the tab object. A misleading
-- direct field must never cause a duplicate native flash.
alertingTabs[nativeTab] = true
nativeTab.alerting = false
addMessageHook(frame, "ordinary text on an already-flashing native tab")
assert(startCount == 0, "Alerts must consult ChatFrameUtil.IsTabAlerting")

-- Roth's extension requests one native flash for an inactive docked tab, then
-- lets Blizzard own the state and animation. Repeated messages do not restart it.
alertingTabs[addonTab] = nil
addonTab.alerting = true
addMessageHook(addonFrame, "ordinary displayed text")
assert(startCount == 1 and alertingTabs[addonTab])
addMessageHook(addonFrame, "another message while native flash is active")
assert(startCount == 1)

-- Selected, undocked, inactive, restoring and inaccessible frames are excluded.
selectedFrame = addonFrame
addMessageHook(addonFrame, "selected tab")
assert(startCount == 1)
selectedFrame = {}
addonFrame.inUse = false
addMessageHook(addonFrame, "inactive frame")
assert(startCount == 1)
addonFrame.inUse = true
addonFrame.__rothRestoring = true
addMessageHook(addonFrame, "restore replay")
assert(startCount == 1)
addonFrame.__rothRestoring = nil
inaccessibleObject = addonFrame
addMessageHook(addonFrame, "inaccessible frame")
assert(startCount == 1)
inaccessibleObject = nil

module:OnDisable(core)
assert(addMessageHook == nil)
assert(alertingTabs[nativeTab] and alertingTabs[addonTab],
  "disable must not stop native-owned flashes")
assert(stopCount == 0)

module:OnEnable(core)
alertingTabs[addonTab] = nil
addMessageHook(addonFrame, "new inactive-tab message")
assert(startCount == 2 and alertingTabs[addonTab])
module:OnDisable(core)
assert(stopCount == 0)

print("alerts_spec: ok")
