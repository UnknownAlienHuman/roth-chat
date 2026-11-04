-- RothChat - inactive dock-tab alert policy extension.
--
-- Blizzard owns whisper audio, alert state, animation and teardown. Roth Chat
-- only requests the same native flash for ordinary messages on inactive docked
-- tabs that Blizzard's current policy does not cover.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Alerts",
  defaultEnabled = true,
  description = "Extends native tab flashing to ordinary messages on inactive docked tabs.",
}

local function IsEnabled(core)
  return M.active and core and core:IsModuleActive("Alerts")
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

local function IsTabAlerting(tab)
  local util = _G.ChatFrameUtil
  local query = util and util.IsTabAlerting
  if type(query) == "function" then
    local ok, alerting = pcall(query, tab)
    if ok and NS.CanAccessValue(alerting) and type(alerting) == "boolean" then
      return alerting
    end
    -- Failing closed avoids starting a duplicate native animation when current
    -- alert state cannot be established.
    return true
  end

  -- Compatibility fallback for older clients that exposed the state directly.
  local alerting = tab and tab.alerting
  if not NS.CanAccessValue(alerting) then return true end
  return alerting == true
end

local function RequestInactiveTabFlash(frame)
  if type(_G.FCF_StartAlertFlash) ~= "function" or not IsInactiveDockTab(frame) then return end

  local tab = GetChatTab(frame)
  if not tab or IsTabAlerting(tab) then return end

  -- The native function owns state and animation from this point onward. Roth
  -- Chat deliberately does not stop or restore the flash during module teardown.
  pcall(_G.FCF_StartAlertFlash, frame)
end

local function OnAddMessage(frame, text)
  if not IsEnabled(M.core) or NS.IsChatMessagingRestricted() then return end
  if not NS.CanAccessValue(text) or type(text) ~= "string" or text == "" then return end
  RequestInactiveTabFlash(frame)
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  self.active = true
  core:RegisterAddMessageHook(OnAddMessage, self, 80)
end

function M:OnDisable(core)
  self.active = false
  core:UnregisterAddMessageHooks(self)
end

RothChat:RegisterModule(M)
