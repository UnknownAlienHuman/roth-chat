-- RothChat - Alerts module
-- Adds a broad inactive-tab flash policy. Whisper audio remains owned by
-- Blizzard_ChatFrameBase, which already plays SOUNDKIT.TELL_MESSAGE with the
-- native cooldown after processing WHISPER and BN_WHISPER.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Alerts",
  defaultEnabled = true,
  description = "Highlights inactive docked chat tabs on new messages.",
}

local listenersRegistered = false

local function IsEnabled(core)
  return M.active and core and core:IsModuleActive("Alerts")
end

local function CanFlashChatTab()
  return type(_G.FCF_StartAlertFlash) == "function" and type(_G.FCF_StopAlertFlash) == "function"
end

local function GetChatTab(frame)
  local name = frame and frame.GetName and frame:GetName()
  if type(name) ~= "string" then return nil end
  return _G[name .. "Tab"]
end

local function GetSelectedDockFrame()
  if NS.GetSelectedDockChatFrame then
    local selected = NS.GetSelectedDockChatFrame()
    if selected then return selected end
  end
  return _G.SELECTED_CHAT_FRAME
end

local function IsInactiveDockTab(frame)
  if not frame or frame.__rothRestoring then return false end
  if NS.IsActiveChatFrame and not NS.IsActiveChatFrame(frame) then return false end
  if not (NS.IsDockedChatFrame and NS.IsDockedChatFrame(frame)) then return false end
  local selected = GetSelectedDockFrame()
  return selected ~= nil and selected ~= frame
end

local function StartInactiveTabFlash(frame)
  if not CanFlashChatTab() or not IsInactiveDockTab(frame) then return end
  local tab = GetChatTab(frame)
  if not tab or tab.alerting then return end
  pcall(_G.FCF_StartAlertFlash, frame)
end

local function StopTabFlash(frame, selectedOnly)
  if not CanFlashChatTab() or not frame then return end
  local tab = GetChatTab(frame)
  if not tab or not tab.alerting then return end
  if selectedOnly and GetSelectedDockFrame() ~= frame then return end
  pcall(_G.FCF_StopAlertFlash, frame)
end

local function RefreshDockFlashes()
  if not CanFlashChatTab() then return end
  for _, chatFrame in ipairs(NS.GetChatFrames()) do
    StopTabFlash(chatFrame, true)
  end
end

local function StopAllFlashes()
  if not CanFlashChatTab() then return end
  for _, chatFrame in ipairs(NS.GetChatFrames()) do
    StopTabFlash(chatFrame, false)
  end
end

local function OnAddMessage(frame, text)
  if not IsEnabled(M.core) then return end
  if type(text) ~= "string" then text = NS.SafeToString(text) end
  if text == "" then return end
  StartInactiveTabFlash(frame)
end

local function RegisterLifecycleListeners(core)
  if listenersRegistered then return end
  listenersRegistered = true

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if IsEnabled(core2) then RefreshDockFlashes() end
  end, M)

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if IsEnabled(core2) then StopTabFlash(chatFrame, true) end
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if IsEnabled(core2) then StopTabFlash(chatFrame, false) end
  end, M)
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  self.active = true
  listenersRegistered = false
  core:EnsureChatLifecycleHooks()
  RegisterLifecycleListeners(core)
  core:RegisterAddMessageHook(OnAddMessage, self, 80)
  RefreshDockFlashes()
end

function M:OnDisable(core)
  self.active = false
  listenersRegistered = false
  if core and core.UnregisterAddMessageHooks then core:UnregisterAddMessageHooks(self) end
  StopAllFlashes()
end

RothChat:RegisterModule(M)
