-- RothChat - Dock module
--
-- Normalizes GeneralDockManager sizing so custom chat tabs do not inherit an
-- oversized header strip after Blizzard layout updates.

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

local dockActive = false
local dockDeferred = false

local function ApplyDockSizing(dock)
  if not dock then return end
  dock:SetHeight(20)
  if dock.scrollFrame then
    dock.scrollFrame:SetHeight(20)
    if dock.scrollFrame.child then
      dock.scrollFrame.child:SetHeight(20)
    end
    dock.scrollFrame:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, -1)
  end
end

local function IsEnabled(core)
  return dockActive and core and core:IsModuleActive("Dock")
end

local function DeferDockApply(core, dock)
  if dockDeferred then return end
  dockDeferred = true
  core:Defer(function()
    dockDeferred = false
    if IsEnabled(core) then
      ApplyDockSizing(dock)
    end
  end)
end

local function QueueDockApply(core, dock)
  NS.RunNextFrame(M.__dockApplyKey, function()
    if not IsEnabled(core) then return end
    if InCombatLockdown() then
      DeferDockApply(core, dock)
      return
    end
    ApplyDockSizing(dock)
  end, "RothChat:DockApply")
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  dockActive = true
  dockDeferred = false
  core:EnsureChatLifecycleHooks()

  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if dock then
    if InCombatLockdown() then
      DeferDockApply(core, dock)
    else
      ApplyDockSizing(dock)
    end
  end

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    local currentDock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
    if currentDock then
      QueueDockApply(core2, currentDock)
    end
  end, self)
end

function M:OnLogin(core)
  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if dock then
    QueueDockApply(core, dock)
  end
end

function M:OnDisable(core)
  dockActive = false
  dockDeferred = false
  NS.CancelScheduled(M.__dockApplyKey)
end

function M:Refresh(core)
  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if dock then
    QueueDockApply(core, dock)
  end
end
