-- RothChat - Alerts module
-- Goal: Play subtle sounds for important messages (Whispers).

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
    if selected then
      return selected
    end
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
  if not CanFlashChatTab() then return end
  if not IsInactiveDockTab(frame) then return end
  local tab = GetChatTab(frame)
  if not tab or tab.alerting then return end
  pcall(_G.FCF_StartAlertFlash, frame)
end

local function StopSelectedTabFlash(frame)
  if not CanFlashChatTab() or not frame then return end
  local tab = GetChatTab(frame)
  if not tab or not tab.alerting then return end
  if GetSelectedDockFrame() ~= frame then return end
  pcall(_G.FCF_StopAlertFlash, frame)
end

local function RefreshDockFlashes()
  if not CanFlashChatTab() then return end
  for _, cf in ipairs(NS.GetChatFrames()) do
    StopSelectedTabFlash(cf)
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
  for lineID, ts in pairs(seenLineIDs) do
    if (now - ts) > LINE_TTL then
      seenLineIDs[lineID] = nil
    end
  end
end

local function ShouldHandleLine(lineID, now)
  if type(lineID) ~= "number" or lineID <= 0 then
    return true
  end
  local ts = seenLineIDs[lineID]
  if ts and (now - ts) <= LINE_TTL then
    return false
  end
  seenLineIDs[lineID] = now
  return true
end

local function GetAccessibleLineID(...)
  -- CHAT_MSG_* payload: lineID is argument #11. Select does not inspect the
  -- value; access must still be checked before type/comparison/table use.
  local lineID = select(11, ...)
  if not NS.CanAccessValue(lineID) then
    return nil
  end
  if type(lineID) ~= "number" then
    return nil
  end
  return lineID
end

local function OnWhisperEvent(_, _, ...)
  local now = GetTime()
  PruneSeen(now)

  local lineID = GetAccessibleLineID(...)
  if not ShouldHandleLine(lineID, now) then
    return
  end

  local cooldown = GetSoundCooldown()
  if (now - lastSoundAt) < cooldown then
    return
  end
  lastSoundAt = now

  pcall(PlaySound, SOUND_ID)
end

local function OnAddMessage(frame, text)
  if not M.active then return end
  if not M.core or not M.core:IsModuleEnabled("Alerts") then return end
  if type(text) ~= "string" then
    text = NS.SafeToString(text)
  end
  if text == "" then return end
  StartInactiveTabFlash(frame)
end

local function RegisterLifecycleListeners(core)
  if listenersRegistered then return end
  listenersRegistered = true

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if not core2:IsModuleEnabled("Alerts") then return end
    RefreshDockFlashes()
  end, M)

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if not core2:IsModuleEnabled("Alerts") then return end
    StopSelectedTabFlash(chatFrame)
  end, M)
end

function M:Init(core)
  self.core = core
  self.eventFrame = self.eventFrame or CreateFrame("Frame")
  self.eventFrame:SetScript("OnEvent", OnWhisperEvent)
  return true
end

function M:OnEnable(core)
  local f = self.eventFrame
  if not f then return end
  self.active = true
  core:EnsureChatLifecycleHooks()
  RegisterLifecycleListeners(core)
  core:RegisterAddMessageHook(OnAddMessage, self, 80)
  RefreshDockFlashes()
  f:RegisterEvent("CHAT_MSG_WHISPER")
  f:RegisterEvent("CHAT_MSG_BN_WHISPER")
end

function M:OnDisable(core)
  self.active = false
  local f = self.eventFrame
  if f then
    f:UnregisterAllEvents()
  end
  if core and core.UnregisterAddMessageHooks then
    core:UnregisterAddMessageHooks(self)
  end
  if core and core.OffOwner then
    core:OffOwner(self)
  end
  listenersRegistered = false
  if table and table.wipe then
    table.wipe(seenLineIDs)
  else
    seenLineIDs = {}
  end
  nextPrune = 0
  lastSoundAt = 0
end

RothChat:RegisterModule(M)
