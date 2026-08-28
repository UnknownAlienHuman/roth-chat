-- RothChat - Resize module (Rubber Band)
-- Goal: easy temporary resize through a grip or the primary chat tab.
-- The frame returns to its captured base size after inactivity.

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

local grips = {}
local state = {}
local resizeActive = false
local lifecycleListenersRegistered = false

local AnimateSize

local function IsEnabled(core)
  return resizeActive and core and core:IsModuleActive("Resize")
end

local function GetState(cf)
  if not state[cf] then
    state[cf] = {
      baseW = nil,
      baseH = nil,
      timer = nil,
      anim = nil,
      snapDeferred = false,
    }
  end
  return state[cf]
end

local function IsMainChatFrame(cf)
  if not cf then return false end
  local idx = NS.GetChatFrameIndex and NS.GetChatFrameIndex(cf)
  return idx == MAIN_CHAT_INDEX
end

local function StopSnapTimer(cf)
  local st = GetState(cf)
  if st.timer then
    st.timer:Cancel()
    st.timer = nil
  end
  if st.anim then
    st.anim:Cancel()
    st.anim = nil
  end
end

local function ClampTargetSize(cf, w, h)
  if not cf then return w, h end

  if cf.GetMinResize then
    local minW, minH = cf:GetMinResize()
    if minW and minW > 0 and w < minW then w = minW end
    if minH and minH > 0 and h < minH then h = minH end
  end

  if cf.GetMaxResize then
    local maxW, maxH = cf:GetMaxResize()
    if maxW and maxW > 0 and w > maxW then w = maxW end
    if maxH and maxH > 0 and h > maxH then h = maxH end
  end

  return w, h
end

local function ComputeSnapDuration(startW, startH, targetW, targetH)
  local dx = targetW - startW
  local dy = targetH - startH
  local dist = math.sqrt(dx * dx + dy * dy)
  local dur = dist / SNAP_PIXELS_PER_SEC
  if dur < SNAP_MIN_DURATION then return SNAP_MIN_DURATION end
  if dur > SNAP_MAX_DURATION then return SNAP_MAX_DURATION end
  return dur
end

local function QueueSnapAfterCombat(core, cf)
  local st = GetState(cf)
  if st.snapDeferred then return end
  st.snapDeferred = true

  core:Defer(function()
    st.snapDeferred = false
    if not IsEnabled(core) then return end
    if st.baseW and st.baseH then
      AnimateSize(core, cf, st.baseW, st.baseH)
    end
  end)
end

AnimateSize = function(core, cf, targetW, targetH)
  if not IsEnabled(core) or not cf then return end

  local st = GetState(cf)
  if st.anim then
    st.anim:Cancel()
    st.anim = nil
  end

  if InCombatLockdown() then
    QueueSnapAfterCombat(core, cf)
    return
  end

  local startW, startH = cf:GetSize()
  if not startW or not startH then return end
  targetW, targetH = ClampTargetSize(cf, targetW, targetH)

  if math.abs(startW - targetW) < 0.5 and math.abs(startH - targetH) < 0.5 then
    cf:SetSize(targetW, targetH)
    return
  end

  local duration = ComputeSnapDuration(startW, startH, targetW, targetH)
  local startTime = GetTime()

  local ticker
  ticker = C_Timer.NewTicker(SNAP_ANIM_STEP, function()
    if not IsEnabled(core) then
      ticker:Cancel()
      st.anim = nil
      return
    end

    if InCombatLockdown() then
      ticker:Cancel()
      st.anim = nil
      QueueSnapAfterCombat(core, cf)
      return
    end

    local progress = (GetTime() - startTime) / duration
    if progress >= 1 then
      cf:SetSize(targetW, targetH)
      ticker:Cancel()
      st.anim = nil
      if cf.ScrollToBottom then pcall(cf.ScrollToBottom, cf) end
      return
    end

    -- Quartic ease-out for a soft settle.
    progress = 1 - (1 - progress) ^ 4
    local w = startW + (targetW - startW) * progress
    local h = startH + (targetH - startH) * progress
    cf:SetSize(w, h)
  end)

  st.anim = ticker
end

local function StartSnapTimer(core, cf)
  local st = GetState(cf)
  StopSnapTimer(cf)

  st.timer = C_Timer.NewTimer(SNAP_DELAY, function()
    st.timer = nil
    if not IsEnabled(core) then return end

    if InCombatLockdown() then
      QueueSnapAfterCombat(core, cf)
    elseif st.baseW and st.baseH then
      AnimateSize(core, cf, st.baseW, st.baseH)
    end
  end)
end

local function OnResizeStart(core, cf, direction)
  if not IsEnabled(core) or not cf or not cf.StartSizing then return end
  if InCombatLockdown() then return end

  local st = GetState(cf)
  StopSnapTimer(cf)

  if not st.baseW or not st.baseH then
    st.baseW, st.baseH = cf:GetSize()
  end

  cf.__rothResizing = true
  if RothChat.UpdateHoverState then RothChat:UpdateHoverState(cf) end
  cf:StartSizing(direction or "BOTTOMLEFT")
end

local function OnResizeStop(core, cf)
  if not cf then return end

  cf:StopMovingOrSizing()
  cf.__rothResizing = nil
  if RothChat.UpdateHoverState then RothChat:UpdateHoverState(cf) end

  if IsEnabled(core) then
    StartSnapTimer(core, cf)
  end
end

local function RegisterGripHover(core, cf, grip)
  if core.RegisterHoverFrame then
    core:RegisterHoverFrame(cf, grip)
  end
end

local function CreateGrip(core, cf)
  local existing = grips[cf]
  if existing then
    RegisterGripHover(core, cf, existing)
    existing:Show()
    return existing
  end

  local g = CreateFrame("Button", nil, cf)
  g:SetSize(GRIP_SIZE, GRIP_SIZE)
  g:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, 0)
  g:SetFrameLevel(cf:GetFrameLevel() + 10)
  g:EnableMouse(true)
  g:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

  local tex = g:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\AddOns\\RothChat\\Assets\\resize_grip.tga")
  tex:SetTexCoord(1, 0, 0, 1)
  tex:SetVertexColor(1, 1, 1, 0.5)
  g.tex = tex

  if not tex:GetTexture() then
    local fs = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOMLEFT", 2, 2)
    fs:SetText("<")
    fs:SetTextColor(1, 1, 1, 0.5)
  end

  g:SetScript("OnMouseDown", function()
    OnResizeStart(core, cf, "BOTTOMLEFT")
  end)

  g:SetScript("OnMouseUp", function()
    if cf.__rothResizing then
      OnResizeStop(core, cf)
    end
  end)

  g:SetScript("OnEnter", function()
    if g.tex then g.tex:SetVertexColor(1, 1, 1, 1) end
    if GameTooltip and not InCombatLockdown() then
      GameTooltip:SetOwner(g, "ANCHOR_TOPLEFT")
      GameTooltip:SetText("Drag corner to resize\nMain tab drag: up only\n(Snaps back in 30s)")
      GameTooltip:Show()
    end
  end)

  g:SetScript("OnLeave", function()
    if g.tex then g.tex:SetVertexColor(1, 1, 1, 0.5) end
    if GameTooltip and not InCombatLockdown() then GameTooltip:Hide() end
  end)

  grips[cf] = g
  RegisterGripHover(core, cf, g)
  return g
end

local function HookMainTab(core, cf)
  if not IsMainChatFrame(cf) then return end

  local name = cf:GetName()
  local tab = name and _G[name .. "Tab"]
  if not tab or tab.__rothResizeHooked then return end
  tab.__rothResizeHooked = true

  tab:HookScript("OnMouseDown", function(_, button)
    if not IsEnabled(core) or not IsMainChatFrame(cf) then return end
    if InCombatLockdown() then return end

    local isLocked = false
    if FCF_GetChatWindowInfo then
      local _, _, _, _, _, _, _, locked = FCF_GetChatWindowInfo(cf:GetID())
      isLocked = locked and true or false
    end

    if button == "LeftButton" and not IsModifierKeyDown() and isLocked then
      OnResizeStart(core, cf, "TOP")
    end
  end)

  tab:HookScript("OnMouseUp", function(_, button)
    if not IsEnabled(core) or not IsMainChatFrame(cf) then return end
    if button == "LeftButton" and cf.__rothResizing then
      OnResizeStop(core, cf)
    end
  end)
end

local function EnsureFrame(core, cf)
  if not cf or not cf.IsResizable or not cf:IsResizable() then return end
  CreateGrip(core, cf):Show()
  HookMainTab(core, cf)
end

local function RegisterLifecycleListeners(core)
  if lifecycleListenersRegistered then return end
  lifecycleListenersRegistered = true

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if not IsEnabled(core2) then return end
    EnsureFrame(core2, chatFrame)
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if not chatFrame then return end
    StopSnapTimer(chatFrame)
    chatFrame.__rothResizing = nil
    local grip = grips[chatFrame]
    if grip then
      if core2.UnregisterHoverFrame then
        core2:UnregisterHoverFrame(chatFrame, grip)
      end
      grip:Hide()
    end
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
    for _, cf in ipairs(NS.GetChatFrames()) do
      EnsureFrame(core, cf)
    end
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

  for cf, grip in pairs(grips) do
    if core.UnregisterHoverFrame then
      core:UnregisterHoverFrame(cf, grip)
    end
    grip:Hide()
  end

  for cf in pairs(state) do
    StopSnapTimer(cf)
    GetState(cf).snapDeferred = false
    if cf.__rothResizing then
      cf:StopMovingOrSizing()
      cf.__rothResizing = nil
    end
  end
end

function M:Refresh(core)
  if not IsEnabled(core) then return end
  for _, cf in ipairs(NS.GetChatFrames()) do
    EnsureFrame(core, cf)
  end
end

RothChat:RegisterModule(M)
