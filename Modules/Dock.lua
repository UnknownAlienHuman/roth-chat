-- RothChat - Dock module
-- Normalizes GeneralDockManager sizing while preserving the exact pre-module
-- dock geometry for runtime disable/re-enable.

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
local snapshots = setmetatable({}, { __mode = "k" })

local function CapturePoints(frame)
  local points = {}
  if not frame or type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then
    return points
  end

  local count = frame:GetNumPoints() or 0
  for index = 1, count do
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
    points[#points + 1] = { point, relativeTo, relativePoint, x, y }
  end
  return points
end

local function RestorePoints(frame, points)
  if not frame or type(frame.ClearAllPoints) ~= "function" or type(frame.SetPoint) ~= "function" then return end
  frame:ClearAllPoints()
  for index = 1, #points do
    local point = points[index]
    frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
  end
end

local function CaptureDock(dock)
  if not dock or snapshots[dock] then return end
  local scrollFrame = dock.scrollFrame
  local child = scrollFrame and scrollFrame.child
  snapshots[dock] = {
    dockHeight = type(dock.GetHeight) == "function" and dock:GetHeight() or nil,
    scrollHeight = scrollFrame and type(scrollFrame.GetHeight) == "function" and scrollFrame:GetHeight() or nil,
    scrollPoints = CapturePoints(scrollFrame),
    childHeight = child and type(child.GetHeight) == "function" and child:GetHeight() or nil,
  }
end

local function ApplyDockSizing(dock)
  if not dock then return end
  CaptureDock(dock)
  dock.__rothDockOwned = true

  dock:SetHeight(20)
  if dock.scrollFrame then
    dock.scrollFrame:SetHeight(20)
    if dock.scrollFrame.child then dock.scrollFrame.child:SetHeight(20) end
    dock.scrollFrame:ClearAllPoints()
    dock.scrollFrame:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, -1)
  end
end

local function RestoreDockSizing(dock)
  local snapshot = dock and snapshots[dock]
  if not snapshot then return end

  -- Restore only while the current geometry is still the value Roth Chat owns.
  -- A later writer takes ownership and must not be overwritten on disable.
  if dock.__rothDockOwned and (not dock.GetHeight or math.abs((dock:GetHeight() or 20) - 20) < 0.01) then
    if snapshot.dockHeight and dock.SetHeight then dock:SetHeight(snapshot.dockHeight) end

    local scrollFrame = dock.scrollFrame
    if scrollFrame then
      if snapshot.scrollHeight and scrollFrame.SetHeight then scrollFrame:SetHeight(snapshot.scrollHeight) end
      RestorePoints(scrollFrame, snapshot.scrollPoints)
      local child = scrollFrame.child
      if child and snapshot.childHeight and child.SetHeight then child:SetHeight(snapshot.childHeight) end
    end
  end

  dock.__rothDockOwned = nil
  snapshots[dock] = nil
end

local function IsEnabled(core)
  return dockActive and core and core:IsModuleActive("Dock")
end

local function DeferDockApply(core, dock)
  if dockDeferred then return end
  dockDeferred = true
  core:Defer(function()
    dockDeferred = false
    if IsEnabled(core) then ApplyDockSizing(dock) end
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

local function RestoreOutsideCombat(core, dock)
  if not dock then return end
  if InCombatLockdown() then
    core:Defer(function() RestoreDockSizing(dock) end)
  else
    RestoreDockSizing(dock)
  end
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
    if InCombatLockdown() then DeferDockApply(core, dock) else ApplyDockSizing(dock) end
  end

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    local currentDock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
    if currentDock then QueueDockApply(core2, currentDock) end
  end, self)
end

function M:OnLogin(core)
  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if dock then QueueDockApply(core, dock) end
end

function M:OnDisable(core)
  dockActive = false
  dockDeferred = false
  NS.CancelScheduled(M.__dockApplyKey)

  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  RestoreOutsideCombat(core, dock)
end

function M:Refresh(core)
  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if dock then QueueDockApply(core, dock) end
end
