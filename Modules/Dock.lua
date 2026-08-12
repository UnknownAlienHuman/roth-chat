-- RothChat - Dock module
--
-- Fixes UI issues where custom chat tabs appear with oversized header bars.
-- Root cause: GeneralDockManager.scrollFrame child height/anchor can reset,
-- resulting in a taller dock strip.
--
-- This module enforces a stable 20px dock height and keeps the scroll frame
-- aligned to the bottom baseline (yOff = -1).

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local M = {
  name = "Dock",
  defaultEnabled = true,
  description = "Normalize GeneralDockManager height to prevent oversized chat tab headers.",
}

RothChat:RegisterModule(M)
M.__dockApplyKey = M.__dockApplyKey or {}

local function ApplyDockSizing(dock)
  if not dock then return end
  dock:SetHeight(20)
  if dock.scrollFrame then
    dock.scrollFrame:SetHeight(20)
    if dock.scrollFrame.child then
      dock.scrollFrame.child:SetHeight(20)
    end
    -- Keep the dock baseline aligned with Blizzard's layout.
    dock.scrollFrame:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, -1)
  end
end

local function QueueDockApply(dock)
  NS.RunNextFrame(M.__dockApplyKey, function()
    if InCombatLockdown() then return end
    ApplyDockSizing(dock)
  end, "RothChat:DockApply")
end

local function HandleDock(dock)
  if not dock or dock.__rothDockHandled then return end
  dock.__rothDockHandled = true

  ApplyDockSizing(dock)
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  local function ApplyAll()
    core:OffOwner(self)
    core:EnsureChatLifecycleHooks()
    local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
    if dock then
      HandleDock(dock)
      ApplyDockSizing(dock)
    end

    core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
      local currentDock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
      if currentDock then
        QueueDockApply(currentDock)
      end
    end, self)
  end

  if InCombatLockdown() then
    core:Defer(ApplyAll)
  else
    ApplyAll()
  end
end

function M:OnLogin(core)
  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if dock then
    QueueDockApply(dock)
  end
end
