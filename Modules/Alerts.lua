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
local ownedFlashes = setmetatable({}, { __mode = "k" })

local function IsEnabled(core)
  return M.active and core and core:IsModuleActive("Alerts")
end

local function CanFlashChatTab()
  return type(_G.FCF_StartAlertFlash) == "function" and type(_G.FCF_StopAlertFlash) == "function"
end

local function GetChatTab(frame)
  if not NS.CanAccessObject(frame) then return nil end
  local getName = frame.GetName
  if not NS.CanAccessValue(getName) or type(getName) ~= "function" then return nil end
  local ok, name = pcall(getName, frame)
  if not ok or not NS.CanAccessValue(name) or type(name) ~= "string" then return nil end

  local tab = _G[name .. "Tab"]
  return NS.CanAccessObject(tab) and tab or nil
end

local function IsInactiveDockTab(frame)
  if not NS.CanAccessObject(frame) then return false end
  local restoring = frame.__rothRestoring
  if not NS.CanAccessValue(restoring) or restoring then return false end
  if not NS.IsActiveChatFrame(frame) or not NS.IsDockedChatFrame(frame) then return false end

  local selected = NS.GetSelectedDockChatFrame()
  return selected ~= nil and selected ~= frame
end

local function StartInactiveTabFlash(frame)
  if not CanFlashChatTab() or not IsInactiveDockTab(frame) then return end
  local tab = GetChatTab(frame)
  if not tab then return end

  local alerting = tab.alerting
  if not NS.CanAccessValue(alerting) or alerting then return end
  local ok = pcall(_G.FCF_StartAlertFlash, frame)
  if not ok then return end

  if not NS.CanAccessObject(tab) then return end
  alerting = tab.alerting
  if NS.CanAccessValue(alerting) and alerting == true then
    ownedFlashes[frame] = true
  end
end

local function StopTabFlash(frame, selectedOnly)
  if not NS.CanAccessObject(frame) then return end
  if not ownedFlashes[frame] then return end
  if not CanFlashChatTab() then
    ownedFlashes[frame] = nil
    return
  end

  if selectedOnly and NS.GetSelectedDockChatFrame() ~= frame then return end
  local tab = GetChatTab(frame)
  if tab then
    local alerting = tab.alerting
    if NS.CanAccessValue(alerting) and alerting == true then
      pcall(_G.FCF_StopAlertFlash, frame)
    end
  end
  ownedFlashes[frame] = nil
end

local function RefreshDockFlashes()
  if not CanFlashChatTab() then return end
  for _, chatFrame in ipairs(NS.GetChatFrames()) do
    StopTabFlash(chatFrame, true)
  end
end

local function StopAllFlashes()
  for chatFrame in pairs(ownedFlashes) do
    if NS.CanAccessObject(chatFrame) then StopTabFlash(chatFrame, false) end
  end
  ownedFlashes = setmetatable({}, { __mode = "k" })
end

local function OnAddMessage(frame, text)
  if not IsEnabled(M.core) then return end
  if NS.IsChatMessagingRestricted() then return end
  if not NS.CanAccessValue(text) then return end
  if type(text) ~= "string" then return end
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
  core:UnregisterAddMessageHooks(self)
  StopAllFlashes()
end

RothChat:RegisterModule(M)
