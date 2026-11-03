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
M.__dockDeferredApplyKey = M.__dockDeferredApplyKey or {}
M.__dockDeferredRestoreKey = M.__dockDeferredRestoreKey or {}

local dockActive = false
local snapshots = setmetatable({}, { __mode = "k" })

local function CanAccessFrame(frame)
  return frame ~= nil and (not NS.CanAccessObject or NS.CanAccessObject(frame))
end

local function SafeNumber(value)
  if NS.SafeNumber then return NS.SafeNumber(value) end
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value or nil
end

local function DeferKeyed(core, key, callback, ...)
  if type(core.DeferKeyed) == "function" then
    core:DeferKeyed(key, callback, ...)
  elseif type(core.Defer) == "function" then
    core:Defer(callback, ...)
  end
end

local function CancelDeferred(core, key)
  if type(core.CancelDeferred) == "function" then core:CancelDeferred(key) end
end

local function CapturePoints(frame)
  local points = {}
  if not CanAccessFrame(frame) or type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then
    return points
  end

  local count = math.max(0, math.floor(SafeNumber(frame:GetNumPoints(), 0)))
  for index = 1, count do
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
    if (not NS.CanAccessAllValues or NS.CanAccessAllValues(point, relativeTo, relativePoint, x, y))
      and (relativeTo == nil or CanAccessFrame(relativeTo))
    then
      points[#points + 1] = { point, relativeTo, relativePoint, SafeNumber(x), SafeNumber(y) }
    end
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

local function IsOwnedHeight(frame)
  if not CanAccessFrame(frame) or type(frame.GetHeight) ~= "function" then return false end
  local height = SafeNumber(frame:GetHeight())
  return height ~= nil and math.abs(height - 20) < 0.01
end

local function HasOwnedScrollPoint(frame, dock)
  if not CanAccessFrame(frame) or type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then
    return false
  end
  if SafeNumber(frame:GetNumPoints()) ~= 1 then return false end
  local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
  return (not NS.CanAccessAllValues or NS.CanAccessAllValues(point, relativeTo, relativePoint, x, y))
    and point == "BOTTOMRIGHT"
    and relativeTo == dock
    and relativePoint == "BOTTOMRIGHT"
    and SafeNumber(x) == 0
    and SafeNumber(y) == -1
end

local function CaptureDock(dock)
  if not CanAccessFrame(dock) or snapshots[dock] then return end
  local scrollFrame = dock.scrollFrame
  if scrollFrame and not CanAccessFrame(scrollFrame) then scrollFrame = nil end
  local child = scrollFrame and scrollFrame.child
  if child and not CanAccessFrame(child) then child = nil end
  local dockHeight = type(dock.GetHeight) == "function" and dock:GetHeight() or nil
  local scrollHeight = scrollFrame and type(scrollFrame.GetHeight) == "function" and scrollFrame:GetHeight() or nil
  local childHeight = child and type(child.GetHeight) == "function" and child:GetHeight() or nil
  snapshots[dock] = {
    dockHeight = SafeNumber(dockHeight),
    scrollHeight = SafeNumber(scrollHeight),
    scrollPoints = CapturePoints(scrollFrame),
    childHeight = SafeNumber(childHeight),
  }
end

local function ApplyDockSizing(dock)
  if not CanAccessFrame(dock) then return end
  CaptureDock(dock)
  dock.__rothDockOwned = true

  dock:SetHeight(20)
  local scrollFrame = dock.scrollFrame
  if CanAccessFrame(scrollFrame) then
    scrollFrame:SetHeight(20)
    local child = scrollFrame.child
    if CanAccessFrame(child) then child:SetHeight(20) end
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, -1)
  end
end

local function RestoreDockSizing(dock)
  local snapshot = dock and snapshots[dock]
  if not snapshot or not CanAccessFrame(dock) then return end

  -- Restore only while the current geometry is still the value Roth Chat owns.
  -- A later writer takes ownership and must not be overwritten on disable.
  if dock.__rothDockOwned and IsOwnedHeight(dock) then
    if snapshot.dockHeight and dock.SetHeight then dock:SetHeight(snapshot.dockHeight) end
  end

  local scrollFrame = dock.scrollFrame
  if CanAccessFrame(scrollFrame) then
    if snapshot.scrollHeight and IsOwnedHeight(scrollFrame) and scrollFrame.SetHeight then
      scrollFrame:SetHeight(snapshot.scrollHeight)
    end
    if HasOwnedScrollPoint(scrollFrame, dock) then RestorePoints(scrollFrame, snapshot.scrollPoints) end
    local child = scrollFrame.child
    if snapshot.childHeight and IsOwnedHeight(child) and child.SetHeight then child:SetHeight(snapshot.childHeight) end
  end

  dock.__rothDockOwned = nil
  snapshots[dock] = nil
end

local function IsEnabled(core)
  return dockActive and core and core:IsModuleActive("Dock")
end

local function DeferDockApply(core, dock)
  DeferKeyed(core, M.__dockDeferredApplyKey, function(target)
    if IsEnabled(core) and CanAccessFrame(target) then ApplyDockSizing(target) end
  end, dock)
end

local function QueueDockApply(core, dock)
  NS.RunNextFrame(M.__dockApplyKey, function()
    if not IsEnabled(core) or not CanAccessFrame(dock) then return end
    if InCombatLockdown() then
      DeferDockApply(core, dock)
      return
    end
    ApplyDockSizing(dock)
  end, "RothChat:DockApply")
end

local function RestoreOutsideCombat(core, dock)
  if not CanAccessFrame(dock) then return end
  if InCombatLockdown() then
    DeferKeyed(core, M.__dockDeferredRestoreKey, function(target)
      if not dockActive then RestoreDockSizing(target) end
    end, dock)
  else
    RestoreDockSizing(dock)
  end
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  CancelDeferred(core, M.__dockDeferredRestoreKey)
  dockActive = true
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
  CancelDeferred(core, M.__dockDeferredApplyKey)
  NS.CancelScheduled(M.__dockApplyKey)

  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  RestoreOutsideCombat(core, dock)
end

function M:Refresh(core)
  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if dock then QueueDockApply(core, dock) end
end
