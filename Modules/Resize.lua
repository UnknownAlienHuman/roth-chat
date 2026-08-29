-- RothChat - Resize module (Rubber Band)
-- Provides temporary resizing and returns each frame to the base geometry that
-- existed before Roth Chat started the current resize session.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Resize",
  defaultEnabled = true,
  description = "Adds a resize grip and main-tab dragging. Chat snaps back to original size after 30s.",
}

local GRIP_SIZE = 16
local SNAP_DELAY = 30
local SNAP_MIN_DURATION = 0.28
local SNAP_MAX_DURATION = 0.70
local SNAP_PIXELS_PER_SEC = 900
local SNAP_ANIM_STEP = 0.016
local MAIN_CHAT_INDEX = 1

local grips = setmetatable({}, { __mode = "k" })
local state = setmetatable({}, { __mode = "k" })
local resizeActive = false
local lifecycleListenersRegistered = false

local AnimateSize

local function IsEnabled(core)
  return resizeActive and core and core:IsModuleActive("Resize")
end

local function GetState(frame)
  local current = state[frame]
  if not current then
    current = {
      baseW = nil,
      baseH = nil,
      timer = nil,
      anim = nil,
      snapDeferred = false,
      ownsTemporarySize = false,
    }
    state[frame] = current
  end
  return current
end

local function IsMainChatFrame(frame)
  return frame and NS.GetChatFrameIndex and NS.GetChatFrameIndex(frame) == MAIN_CHAT_INDEX
end

local function IsActiveFrame(frame)
  return frame and (not NS.IsActiveChatFrame or NS.IsActiveChatFrame(frame))
end

local function StopSnapTimer(frame)
  local current = GetState(frame)
  if current.timer then
    current.timer:Cancel()
    current.timer = nil
  end
  if current.anim then
    current.anim:Cancel()
    current.anim = nil
  end
end

local function CaptureBaseSize(frame, force)
  if not frame or type(frame.GetSize) ~= "function" then return end
  local current = GetState(frame)
  if current.ownsTemporarySize and not force then return end

  local width, height = frame:GetSize()
  if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
    current.baseW = width
    current.baseH = height
  end
end

local function ClampTargetSize(frame, width, height)
  if not frame then return width, height end

  if type(frame.GetResizeBounds) == "function" then
    local minWidth, minHeight, maxWidth, maxHeight = frame:GetResizeBounds()
    if minWidth and width < minWidth then width = minWidth end
    if minHeight and height < minHeight then height = minHeight end
    if maxWidth and maxWidth > 0 and width > maxWidth then width = maxWidth end
    if maxHeight and maxHeight > 0 and height > maxHeight then height = maxHeight end
    return width, height
  end

  if frame.GetMinResize then
    local minWidth, minHeight = frame:GetMinResize()
    if minWidth and minWidth > 0 and width < minWidth then width = minWidth end
    if minHeight and minHeight > 0 and height < minHeight then height = minHeight end
  end
  if frame.GetMaxResize then
    local maxWidth, maxHeight = frame:GetMaxResize()
    if maxWidth and maxWidth > 0 and width > maxWidth then width = maxWidth end
    if maxHeight and maxHeight > 0 and height > maxHeight then height = maxHeight end
  end
  return width, height
end

local function ComputeSnapDuration(startWidth, startHeight, targetWidth, targetHeight)
  local dx = targetWidth - startWidth
  local dy = targetHeight - startHeight
  local distance = math.sqrt(dx * dx + dy * dy)
  local duration = distance / SNAP_PIXELS_PER_SEC
  if duration < SNAP_MIN_DURATION then return SNAP_MIN_DURATION end
  if duration > SNAP_MAX_DURATION then return SNAP_MAX_DURATION end
  return duration
end

local function CompleteOwnedResize(frame, width, height)
  local current = GetState(frame)
  current.ownsTemporarySize = false
  current.baseW = width
  current.baseH = height
end

local function QueueSnapAfterCombat(core, frame)
  local current = GetState(frame)
  if current.snapDeferred then return end
  current.snapDeferred = true

  core:Defer(function()
    current.snapDeferred = false
    if not IsEnabled(core) or not IsActiveFrame(frame) then return end
    if current.ownsTemporarySize and current.baseW and current.baseH then
      AnimateSize(core, frame, current.baseW, current.baseH)
    end
  end)
end

AnimateSize = function(core, frame, targetWidth, targetHeight)
  if not IsEnabled(core) or not IsActiveFrame(frame) then return end

  local current = GetState(frame)
  if current.anim then
    current.anim:Cancel()
    current.anim = nil
  end

  if InCombatLockdown() then
    QueueSnapAfterCombat(core, frame)
    return
  end

  local startWidth, startHeight = frame:GetSize()
  if not startWidth or not startHeight then return end
  targetWidth, targetHeight = ClampTargetSize(frame, targetWidth, targetHeight)

  if math.abs(startWidth - targetWidth) < 0.5 and math.abs(startHeight - targetHeight) < 0.5 then
    frame:SetSize(targetWidth, targetHeight)
    CompleteOwnedResize(frame, targetWidth, targetHeight)
    return
  end

  local duration = ComputeSnapDuration(startWidth, startHeight, targetWidth, targetHeight)
  local startTime = GetTime()
  local ticker

  ticker = C_Timer.NewTicker(SNAP_ANIM_STEP, function()
    if not IsEnabled(core) or not IsActiveFrame(frame) then
      ticker:Cancel()
      current.anim = nil
      return
    end

    if InCombatLockdown() then
      ticker:Cancel()
      current.anim = nil
      QueueSnapAfterCombat(core, frame)
      return
    end

    local progress = (GetTime() - startTime) / duration
    if progress >= 1 then
      frame:SetSize(targetWidth, targetHeight)
      ticker:Cancel()
      current.anim = nil
      CompleteOwnedResize(frame, targetWidth, targetHeight)
      if frame.ScrollToBottom then pcall(frame.ScrollToBottom, frame) end
      return
    end

    progress = 1 - (1 - progress) ^ 4
    frame:SetSize(
      startWidth + (targetWidth - startWidth) * progress,
      startHeight + (targetHeight - startHeight) * progress
    )
  end)

  current.anim = ticker
end

local function StartSnapTimer(core, frame)
  local current = GetState(frame)
  StopSnapTimer(frame)

  current.timer = C_Timer.NewTimer(SNAP_DELAY, function()
    current.timer = nil
    if not IsEnabled(core) or not IsActiveFrame(frame) then return end

    if InCombatLockdown() then
      QueueSnapAfterCombat(core, frame)
    elseif current.ownsTemporarySize and current.baseW and current.baseH then
      AnimateSize(core, frame, current.baseW, current.baseH)
    end
  end)
end

local function OnResizeStart(core, frame, direction)
  if not IsEnabled(core) or not IsActiveFrame(frame) or not frame.StartSizing then return end
  if InCombatLockdown() then return end

  local current = GetState(frame)
  StopSnapTimer(frame)
  if not current.ownsTemporarySize then
    CaptureBaseSize(frame, true)
    current.ownsTemporarySize = true
  end

  frame.__rothResizing = true
  if RothChat.UpdateHoverState then RothChat:UpdateHoverState(frame) end
  frame:StartSizing(direction or "BOTTOMLEFT")
end

local function OnResizeStop(core, frame)
  if not frame then return end
  frame:StopMovingOrSizing()
  frame.__rothResizing = nil
  if RothChat.UpdateHoverState then RothChat:UpdateHoverState(frame) end
  if IsEnabled(core) then StartSnapTimer(core, frame) end
end

local function RegisterGripHover(core, frame, grip)
  if core.RegisterHoverFrame then core:RegisterHoverFrame(frame, grip) end
end

local function CreateGrip(core, frame)
  local existing = grips[frame]
  if existing then
    RegisterGripHover(core, frame, existing)
    existing:Show()
    return existing
  end

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(GRIP_SIZE, GRIP_SIZE)
  grip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:EnableMouse(true)
  grip:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

  local texture = grip:CreateTexture(nil, "OVERLAY")
  texture:SetAllPoints()
  texture:SetTexture("Interface\\AddOns\\RothChat\\Assets\\resize_grip.tga")
  texture:SetTexCoord(1, 0, 0, 1)
  texture:SetVertexColor(1, 1, 1, 0.5)
  grip.tex = texture

  if not texture:GetTexture() then
    local fallback = grip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fallback:SetPoint("BOTTOMLEFT", 2, 2)
    fallback:SetText("<")
    fallback:SetTextColor(1, 1, 1, 0.5)
  end

  grip:SetScript("OnMouseDown", function() OnResizeStart(core, frame, "BOTTOMLEFT") end)
  grip:SetScript("OnMouseUp", function()
    if frame.__rothResizing then OnResizeStop(core, frame) end
  end)
  grip:SetScript("OnEnter", function()
    if grip.tex then grip.tex:SetVertexColor(1, 1, 1, 1) end
    if GameTooltip and not InCombatLockdown() then
      GameTooltip:SetOwner(grip, "ANCHOR_TOPLEFT")
      GameTooltip:SetText("Drag corner to resize\nMain tab drag: up only\n(Snaps back in 30s)")
      GameTooltip:Show()
    end
  end)
  grip:SetScript("OnLeave", function()
    if grip.tex then grip.tex:SetVertexColor(1, 1, 1, 0.5) end
    if GameTooltip and not InCombatLockdown() then GameTooltip:Hide() end
  end)

  grips[frame] = grip
  RegisterGripHover(core, frame, grip)
  return grip
end

local function HookMainTab(core, frame)
  if not IsMainChatFrame(frame) then return end
  local name = frame:GetName()
  local tab = name and _G[name .. "Tab"]
  if not tab or tab.__rothResizeHooked then return end
  tab.__rothResizeHooked = true

  tab:HookScript("OnMouseDown", function(_, button)
    if not IsEnabled(core) or not IsMainChatFrame(frame) or InCombatLockdown() then return end

    local isLocked = false
    if FCF_GetChatWindowInfo then
      local _, _, _, _, _, _, _, locked = FCF_GetChatWindowInfo(frame:GetID())
      isLocked = locked and true or false
    end

    if button == "LeftButton" and not IsModifierKeyDown() and isLocked then
      OnResizeStart(core, frame, "TOP")
    end
  end)

  tab:HookScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and frame.__rothResizing then OnResizeStop(core, frame) end
  end)
end

local function EnsureFrame(core, frame)
  if not IsActiveFrame(frame) or not frame.IsResizable or not frame:IsResizable() then return end
  local current = GetState(frame)
  if not current.ownsTemporarySize and not frame.__rothResizing then CaptureBaseSize(frame, true) end
  CreateGrip(core, frame):Show()
  HookMainTab(core, frame)
end

local function RestoreOwnedSize(core, frame)
  local current = state[frame]
  if not current or not current.ownsTemporarySize or not current.baseW or not current.baseH then return end

  local function Restore()
    if frame and frame.SetSize then
      local width, height = ClampTargetSize(frame, current.baseW, current.baseH)
      frame:SetSize(width, height)
      CompleteOwnedResize(frame, width, height)
    end
  end

  if InCombatLockdown() then core:Defer(Restore) else Restore() end
end

local function RegisterLifecycleListeners(core)
  if lifecycleListenersRegistered then return end
  lifecycleListenersRegistered = true

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if IsEnabled(core2) then EnsureFrame(core2, chatFrame) end
  end, M)

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if not IsEnabled(core2) then return end
    for _, chatFrame in ipairs(NS.GetActiveChatFrames()) do EnsureFrame(core2, chatFrame) end
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if not chatFrame then return end
    StopSnapTimer(chatFrame)
    chatFrame.__rothResizing = nil

    local grip = grips[chatFrame]
    if grip then
      if core2.UnregisterHoverFrame then core2:UnregisterHoverFrame(chatFrame, grip) end
      grip:Hide()
    end
    state[chatFrame] = nil
  end, M)
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  resizeActive = true
  lifecycleListenersRegistered = false
  core:EnsureChatLifecycleHooks()
  RegisterLifecycleListeners(core)

  local function ApplyAll()
    if not resizeActive then return end
    for _, frame in ipairs(NS.GetActiveChatFrames()) do EnsureFrame(core, frame) end
  end

  if InCombatLockdown() then
    core:Defer(function()
      if IsEnabled(core) then ApplyAll() end
    end)
  else
    ApplyAll()
  end
end

function M:OnDisable(core)
  resizeActive = false
  lifecycleListenersRegistered = false

  for frame, grip in pairs(grips) do
    if core.UnregisterHoverFrame then core:UnregisterHoverFrame(frame, grip) end
    grip:Hide()
  end

  for frame, current in pairs(state) do
    StopSnapTimer(frame)
    current.snapDeferred = false
    if frame.__rothResizing then
      frame:StopMovingOrSizing()
      frame.__rothResizing = nil
    end
    RestoreOwnedSize(core, frame)
  end
end

function M:Refresh(core)
  if not IsEnabled(core) then return end
  for _, frame in ipairs(NS.GetActiveChatFrames()) do EnsureFrame(core, frame) end
end

RothChat:RegisterModule(M)
