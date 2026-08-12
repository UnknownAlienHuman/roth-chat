-- RothChat - Resize module (Rubber Band)
-- Goal: Easy resize via a grip handle OR dragging the main chat tab.
-- Feature: "Rubber band" effect - chat snaps back to original size after inactivity.

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

local function GetState(cf)
  if not state[cf] then
    state[cf] = { baseW = nil, baseH = nil, timer = nil, anim = nil }
  end
  return state[cf]
end

local function IsMainChatFrame(cf)
  if not cf or not cf.GetID then return false end
  return cf:GetID() == MAIN_CHAT_INDEX
end

local function StopSnapTimer(cf)
  local st = GetState(cf)
  if st.timer then st.timer:Cancel(); st.timer = nil end
  if st.anim then st.anim:Cancel(); st.anim = nil end
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

local function AnimateSize(cf, targetW, targetH)
  if not cf then return end

  local st = GetState(cf)
  if st.anim then st.anim:Cancel() end

  local startW, startH = cf:GetSize()
  targetW, targetH = ClampTargetSize(cf, targetW, targetH)

  if math.abs(startW - targetW) < 0.5 and math.abs(startH - targetH) < 0.5 then
    cf:SetSize(targetW, targetH)
    return
  end

  local duration = ComputeSnapDuration(startW, startH, targetW, targetH)
  local startTime = GetTime()

  local ticker
  ticker = C_Timer.NewTicker(SNAP_ANIM_STEP, function()
    local now = GetTime()
    local progress = (now - startTime) / duration

    if progress >= 1 then
      cf:SetSize(targetW, targetH)
      ticker:Cancel()
      st.anim = nil
      -- Preserve scroll position after snap-back
      if cf.ScrollToBottom then pcall(cf.ScrollToBottom, cf) end
      return
    end

    -- Quartic ease-out for softer settle near the final size.
    progress = 1 - (1 - progress)^4

    local w = startW + (targetW - startW) * progress
    local h = startH + (targetH - startH) * progress
    cf:SetSize(w, h)
  end)

  st.anim = ticker
end

local function StartSnapTimer(cf)
  local st = GetState(cf)
  StopSnapTimer(cf)

  st.timer = C_Timer.NewTimer(SNAP_DELAY, function()
    if InCombatLockdown() then
      StartSnapTimer(cf)
      return
    end
    if st.baseW and st.baseH then
      AnimateSize(cf, st.baseW, st.baseH)
    end
  end)
end

local function OnResizeStart(cf, direction)
  if not cf or not cf.StartSizing then return end
  if InCombatLockdown() then return end

  local st = GetState(cf)
  StopSnapTimer(cf)

  if not st.baseW then
    st.baseW, st.baseH = cf:GetSize()
  end

  cf.__rothResizing = true
  if RothChat.UpdateHoverState then RothChat:UpdateHoverState(cf) end

  cf:StartSizing(direction or "BOTTOMLEFT")
end

local function OnResizeStop(cf)
  if not cf then return end

  cf:StopMovingOrSizing()
  cf.__rothResizing = nil
  if RothChat.UpdateHoverState then RothChat:UpdateHoverState(cf) end
  StartSnapTimer(cf)
end

-- Grip Handler
local function CreateGrip(core, cf)
  if grips[cf] then return grips[cf] end

  local g = CreateFrame("Button", nil, cf)
  g:SetSize(GRIP_SIZE, GRIP_SIZE)
  g:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, 0)
  g:SetFrameLevel(cf:GetFrameLevel() + 10)
  g:EnableMouse(true)
  g:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

  local tex = g:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\AddOns\\RothChat\\Assets\\resize_grip.tga")
  tex:SetTexCoord(1, 0, 0, 1) -- mirror for left corner grip
  tex:SetVertexColor(1, 1, 1, 0.5)
  g.tex = tex

  if not tex:GetTexture() then
    local fs = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOMLEFT", 2, 2)
    fs:SetText("<")
    fs:SetTextColor(1, 1, 1, 0.5)
  end

  g:SetScript("OnMouseDown", function()
    if not core:IsModuleEnabled("Resize") then return end
    OnResizeStart(cf, "BOTTOMLEFT")
  end)

  g:SetScript("OnMouseUp", function()
    if not core:IsModuleEnabled("Resize") then return end
    if cf.__rothResizing then
      OnResizeStop(cf)
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

  if core.RegisterHoverFrame then core:RegisterHoverFrame(cf, g) end
  grips[cf] = g
  return g
end

-- Main-tab handler (only ChatFrame1 tab)
local function HookMainTab(core, cf)
  if not IsMainChatFrame(cf) then return end

  local name = cf:GetName()
  local tab = name and _G[name .. "Tab"]
  if not tab or tab.__rothResizeHooked then return end
  tab.__rothResizeHooked = true

  tab:HookScript("OnMouseDown", function(self, button)
    if not core:IsModuleEnabled("Resize") then return end
    if not IsMainChatFrame(cf) then return end
    if InCombatLockdown() then return end

    -- Only resize via the main tab when the window is locked.
    -- Otherwise, leave Blizzard default behavior untouched.
    local isLocked = false
    if FCF_GetChatWindowInfo then
      local _, _, _, _, _, _, _, locked = FCF_GetChatWindowInfo(cf:GetID())
      isLocked = locked
    end

    if button == "LeftButton" and not IsModifierKeyDown() and isLocked then
      OnResizeStart(cf, "TOP")
    end
  end)

  tab:HookScript("OnMouseUp", function(self, button)
    if not core:IsModuleEnabled("Resize") then return end
    if not IsMainChatFrame(cf) then return end

    if button == "LeftButton" and cf.__rothResizing then
      OnResizeStop(cf)
    end
  end)
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  local function ApplyAll()
    for _, cf in ipairs(NS.GetChatFrames()) do
      if cf:IsResizable() then
        CreateGrip(core, cf):Show()
        if IsMainChatFrame(cf) then
          HookMainTab(core, cf)
        end
      end
    end
  end

  if InCombatLockdown() then
    core:Defer(ApplyAll)
  else
    ApplyAll()
  end
end

function M:OnDisable(core)
  for _, g in pairs(grips) do
    g:Hide()
  end

  for cf in pairs(state) do
    StopSnapTimer(cf)
    if cf.__rothResizing then
      cf:StopMovingOrSizing()
      cf.__rothResizing = nil
    end
  end
end

RothChat:RegisterModule(M)
