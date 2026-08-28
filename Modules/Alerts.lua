-- RothChat - Alerts module
-- Plays whisper sounds and highlights inactive docked chat tabs.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Alerts",
  defaultEnabled = true,
  description = "Plays whisper sounds and highlights inactive chat tabs on new messages.",
}

local SOUND_ID = (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081
local PRUNE_INTERVAL = 1.5
local LINE_TTL = 2.0

local seenLineIDs = {}
local nextPrune = 0
local lastSoundAt = 0
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
  for _, cf in ipairs(NS.GetChatFrames()) do
    StopTabFlash(cf, true)
  end
end

local function StopAllFlashes()
  if not CanFlashChatTab() then return end
  for _, cf in ipairs(NS.GetChatFrames()) do
    StopTabFlash(cf, false)
  end
end

local function GetSoundCooldown()
  if ChatFrameConstants and type(ChatFrameConstants.WhisperSoundAlertCooldown) == "number" then
    return ChatFrameConstants.WhisperSoundAlertCooldown
  end
  if type(CHAT_TELL_ALERT_TIME) == "number" and CHAT_TELL_ALERT_TIME > 0 then
    return CHAT_TELL_ALERT_TIME
  end
  return 1.0
end

local function PruneSeen(now)
  if now < nextPrune then return end
  nextPrune = now + PRUNE_INTERVAL
  for lineID, timestamp in pairs(seenLineIDs) do
    if (now - timestamp) > LINE_TTL then seenLineIDs[lineID] = nil end
  end
end

local function ShouldHandleLine(lineID, now)
  if NS.CanAccessValue and not NS.CanAccessValue(lineID) then
    return true
  end
  if type(lineID) ~= "number" or lineID <= 0 then
    return true
  end

  local timestamp = seenLineIDs[lineID]
  if timestamp and (now - timestamp) <= LINE_TTL then return false end
  seenLineIDs[lineID] = now
  return true
end

local function OnWhisperEvent(_, _, ...)
  if not IsEnabled(M.core) then return end

  local now = GetTime()
  PruneSeen(now)

  -- CHAT_MSG_* payload: lineID is argument #11.
  local lineID = select(11, ...)
  if not ShouldHandleLine(lineID, now) then return end

  local cooldown = GetSoundCooldown()
  if (now - lastSoundAt) < cooldown then return end
  lastSoundAt = now

  pcall(PlaySound, SOUND_ID)
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
  self.eventFrame = self.eventFrame or CreateFrame("Frame")
  self.eventFrame:SetScript("OnEvent", OnWhisperEvent)
  return true
end

function M:OnEnable(core)
  local frame = self.eventFrame
  if not frame then return end

  self.active = true
  listenersRegistered = false
  core:EnsureChatLifecycleHooks()
  RegisterLifecycleListeners(core)
  core:RegisterAddMessageHook(OnAddMessage, self, 80)
  RefreshDockFlashes()
  frame:RegisterEvent("CHAT_MSG_WHISPER")
  frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
end

function M:OnDisable(core)
  self.active = false
  listenersRegistered = false

  if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
  if core and core.UnregisterAddMessageHooks then core:UnregisterAddMessageHooks(self) end
  StopAllFlashes()

  if table and table.wipe then table.wipe(seenLineIDs) else seenLineIDs = {} end
  nextPrune = 0
  lastSoundAt = 0
end

RothChat:RegisterModule(M)
