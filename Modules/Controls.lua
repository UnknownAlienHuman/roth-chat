-- RothChat - Controls module
-- Responsibilities:
--   * Fade Blizzard chat chrome + Roth extras in/out on hover
--   * Provide a "pin" button: keep controls visible until unpinned
--   * Provide a central hover registry (other modules register their frames)
--   * OVERRIDE Blizzard's FCF_Fade logic to prevent conflicts.
--   * Fast Scroll logic.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Controls",
  defaultEnabled = true,
  description = "Mouseover controls, Immersion logic, and Fast Scroll.",
}

local state = {
  perChat = {},
}
local controlsActive = false

local UpdateForChat -- forward

local function ControlsEnabled(core)
  return controlsActive
end

local function GetOrCreateChatState(cf)
  local st = state.perChat[cf]
  if not st then
    st = {
      frames = {},
      pinned = false,
      hovering = false,
      copyOverlayVisible = false,
      button = nil,
      hotspot = nil,
      lastVisible = nil,
      lastPinned = nil,
      lastHovering = nil,
      _hoverScheduleKey = {},
      _boundsScheduleKey = {},
    }
    state.perChat[cf] = st
  end
  return st
end

local function ResetTransientState(st)
  if not st then return end
  NS.CancelScheduled(st._hoverScheduleKey)
  NS.CancelScheduled(st._boundsScheduleKey)
  st.hovering = false
  st.pinned = false
  st.lastVisible = nil
  st.lastPinned = nil
  st.lastHovering = nil
end

local function AddUnique(list, frame)
  for _, f in ipairs(list) do
    if f == frame then return end
  end
  list[#list + 1] = frame
end

local function SetFrameMouseForVisibility(frame, visible)
  if not frame or not frame.EnableMouse then return end
  -- Dock tabs must stay clickable even when their chat window is not currently active.
  if frame.__rothKeepMouseEnabled then
    frame:EnableMouse(true)
    return
  end
  frame:EnableMouse(visible)
end

local function GetFrameRect(frame)
  if not frame or type(frame.GetRect) ~= "function" then return nil end
  local left, bottom, width, height = frame:GetRect()
  if not left or not bottom or not width or not height then return nil end
  if width <= 0 or height <= 0 then return nil end
  return left, bottom, left + width, bottom + height
end

local function IsInteractableChatFrame(cf)
  if not cf then return false end
  if not cf:IsShown() then return false end

  if NS.IsDockedChatFrame and NS.IsDockedChatFrame(cf) then
    local selected = NS.GetSelectedDockChatFrame and NS.GetSelectedDockChatFrame()
    if selected and selected ~= cf then
      return false
    end
  end

  return true
end

local function IsAnyMouseOver(cf, st)
  if not IsInteractableChatFrame(cf) then return false end
  if cf.__rothResizing then return true end
  -- Treat active chat input as "interaction" (prevents chat hiding while typing).
  -- This also covers cases where the cursor is not over the chat area.
  do
    local name = cf and cf.GetName and cf:GetName()
    local eb = name and _G[name .. "EditBox"]
    if eb then
      local ok, active = pcall(function()
        return (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
      end)
      if (ok and active and active == eb) or (eb.HasFocus and eb:HasFocus()) then
        return true
      end
    end
  end
  if st.hotspot and st.hotspot:IsMouseOver() then return true end
  if cf and cf:IsMouseOver() then return true end
  if st.button and st.button:IsMouseOver() then return true end
  for _, f in ipairs(st.frames) do
    if f and f:IsMouseOver() then return true end
  end
  return false
end

local function ScheduleHoverRecalc(core, cf)
  local st = GetOrCreateChatState(cf)
  local delay = tonumber(core:Get("hoverFadeDelay")) or 30

  NS.Schedule(st._hoverScheduleKey, delay, function()
    if not ControlsEnabled(core) then return end
    if not IsInteractableChatFrame(cf) then
      st.hovering = false
      UpdateForChat(core, cf)
      return
    end
    st.hovering = IsAnyMouseOver(cf, st)
    UpdateForChat(core, cf)
  end, "RothChat:ControlsHover")
end

local function RequestHotspotBoundsUpdate(core, cf)
  local st = GetOrCreateChatState(cf)
  if not st.hotspot then return end

  NS.RunNextFrame(st._boundsScheduleKey, function()
    if not ControlsEnabled(core) then return end
    if not IsInteractableChatFrame(cf) then return end
    local hs = st.hotspot
    if not hs then return end

    local minL, minB, maxR, maxT
    local function Accum(frame)
      local l, b, r, t = GetFrameRect(frame)
      if not l then return end
      if not minL or l < minL then minL = l end
      if not minB or b < minB then minB = b end
      if not maxR or r > maxR then maxR = r end
      if not maxT or t > maxT then maxT = t end
    end

    Accum(cf)
    Accum(st.button)
    for _, f in ipairs(st.frames) do Accum(f) end

    if not minL then
      hs:ClearAllPoints()
      hs:SetAllPoints(cf)
      return
    end

    local pad = tonumber(core:Get("hotspotPadding")) or 10
    pad = NS.Clamp(pad, 0, 24)

    hs:ClearAllPoints()
    hs:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", minL - pad, minB - pad)
    hs:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", maxR + pad, maxT + pad)
  end, "RothChat:ControlsBounds")
end

local function CreateHotspot(core, cf)
  local st = GetOrCreateChatState(cf)
  if st.hotspot then return st.hotspot end

  local hs = CreateFrame("Frame", nil, UIParent)
  hs:SetFrameStrata("HIGH")
  hs:SetFrameLevel(1000)
  hs:SetAllPoints(cf)
  hs:SetAlpha(0)
  hs:EnableMouse(true)
  hs:Hide()

  -- Ensure hotspot is completely invisible (no backdrop, no textures)
  if hs.SetBackdrop then hs:SetBackdrop(nil) end

  hs:SetScript("OnEnter", function()
    if not ControlsEnabled(core) then return end
    st.hovering = true
    UpdateForChat(core, cf)
  end)
  hs:SetScript("OnLeave", function()
    if not ControlsEnabled(core) then return end
    ScheduleHoverRecalc(core, cf)
  end)

  st.hotspot = hs
  RequestHotspotBoundsUpdate(core, cf)
  return hs
end

local function SetControlsVisible(core, cf, visible)
  local st = GetOrCreateChatState(cf)

  local shownAlpha = core:Get("hoverAlphaShown") or 1
  local hiddenAlpha = core:Get("hoverAlphaHidden") or 0
  local durIn = tonumber(core:Get("hoverFadeInDuration")) or tonumber(core:Get("hoverFadeDuration")) or 0.14
  local durOut = tonumber(core:Get("hoverFadeOutDuration")) or tonumber(core:Get("hoverFadeDuration")) or 0.35
  local dur = visible and durIn or durOut

  local target = visible and shownAlpha or hiddenAlpha

  for _, f in ipairs(st.frames) do
    if f and f.SetAlpha then
      if f.__rothKeepMouseEnabled then
        f:SetAlpha(1)
        SetFrameMouseForVisibility(f, true)
      else
        NS.FadeTo(f, target, dur)
        SetFrameMouseForVisibility(f, visible)
      end
    end
  end

  if st.button and st.button.SetAlpha then
    local showPin = visible and ControlsEnabled(core)
    local btnTarget = showPin and 1 or 0
    NS.FadeTo(st.button, btnTarget, dur)
    if st.button.EnableMouse then st.button:EnableMouse(btnTarget > 0) end
  end
end

local function ShouldShow(core, cf)
  local st = GetOrCreateChatState(cf)
  if st.copyOverlayVisible then return false end
  if st.pinned then return true end
  if not core:Get("hoverControls") then return true end
  return st.hovering
end

UpdateForChat = function(core, cf)
  local st = GetOrCreateChatState(cf)

  if not IsInteractableChatFrame(cf) then
    st.hovering = false
    SetControlsVisible(core, cf, false)
    if st.hotspot then
      st.hotspot:Hide()
      if st.hotspot.EnableMouse then st.hotspot:EnableMouse(false) end
    end
    if st.button and st.button.EnableMouse then
      st.button:EnableMouse(false)
    end
    return
  end

  if st.copyOverlayVisible then
    st.hovering = false
    SetControlsVisible(core, cf, false)
    if st.hotspot then
      st.hotspot:Hide()
      if st.hotspot.EnableMouse then st.hotspot:EnableMouse(false) end
    end
    if st.button and st.button.EnableMouse then
      st.button:EnableMouse(false)
    end

    if st.lastVisible ~= false or st.lastPinned ~= st.pinned or st.lastHovering ~= st.hovering then
      st.lastVisible = false
      st.lastPinned = st.pinned
      st.lastHovering = st.hovering
      core:Emit("CONTROLS_VISIBILITY", cf, false, st.pinned, st.hovering)
    end
    return
  end

  if st.hotspot then
    st.hotspot:Show()
  end

  if not ControlsEnabled(core) then
    SetControlsVisible(core, cf, true)
    if st.hotspot and st.hotspot.EnableMouse then
      st.hotspot:EnableMouse(false)
    end
    return
  end

  local visible = ShouldShow(core, cf)
  SetControlsVisible(core, cf, visible)

  local active = st.pinned or st.hovering
  if st.hotspot and st.hotspot.EnableMouse then
    st.hotspot:EnableMouse(not active)
  end

  if st.lastVisible ~= visible or st.lastPinned ~= st.pinned or st.lastHovering ~= st.hovering then
    st.lastVisible = visible
    st.lastPinned = st.pinned
    st.lastHovering = st.hovering
    core:Emit("CONTROLS_VISIBILITY", cf, visible, st.pinned, st.hovering)
  end
end

local function CreatePinButton(core, cf)
  local st = GetOrCreateChatState(cf)
  if st.button then return st.button end

  local parent = st.hotspot or CreateHotspot(core, cf)

  local b = CreateFrame("Button", nil, parent)
  b:SetSize(20, 20)
  b:SetPoint("TOPLEFT", cf, "TOPLEFT", -12, 12)
  b:EnableMouse(true)
  b:SetAlpha(0.0)

  -- Backdrop with border.TGA
  NS.ApplyGlassBackdrop(b, 0.8, 0, 0)

  -- Icon from icons.TGA atlas — MINIMIZE for unpinned, MAXIMIZE for pinned
  local tc = NS.BUTTON_ICONS.MINIMIZE
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 2, -2)
  tex:SetPoint("BOTTOMRIGHT", -2, 2)
  tex:SetTexture(NS.ICONS_TEXTURE)
  tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
  b.__tex = tex

  -- 3-part highlight
  NS.CreateHighlight(b, "HIGHLIGHT", nil, nil, nil, 0)

  b:SetScript("OnEnter", function()
    if not ControlsEnabled(core) then return end
    st.hovering = true
    UpdateForChat(core, cf)
  end)
  b:SetScript("OnLeave", function()
    if not ControlsEnabled(core) then return end
    ScheduleHoverRecalc(core, cf)
  end)

  b:SetScript("OnClick", function()
    if not ControlsEnabled(core) then return end
    st.pinned = not st.pinned
    if st.pinned then
      local tcMax = NS.BUTTON_ICONS.MAXIMIZE
      tex:SetTexCoord(tcMax[1], tcMax[2], tcMax[3], tcMax[4])
    else
      local tcMin = NS.BUTTON_ICONS.MINIMIZE
      tex:SetTexCoord(tcMin[1], tcMin[2], tcMin[3], tcMin[4])
    end
    UpdateForChat(core, cf)
  end)

  st.button = b
  RequestHotspotBoundsUpdate(core, cf)
  return b
end

local function HookHover(core, cf)
  if cf.__rothControlsHooked then return end
  cf.__rothControlsHooked = true

  cf:HookScript("OnEnter", function()
    if not ControlsEnabled(core) then return end
    GetOrCreateChatState(cf).hovering = true
    UpdateForChat(core, cf)
  end)

  cf:HookScript("OnLeave", function()
    if not ControlsEnabled(core) then return end
    ScheduleHoverRecalc(core, cf)
  end)
end

local function outCubic(t, b, c, d)
  t = t / d - 1
  return c * (t ^ 3 + 1) + b
end

local function HookScroll(core, cf)
  if cf.__rothScrollHooked then return end
  cf.__rothScrollHooked = true

  cf:EnableMouseWheel(true)
  cf:SetClipsChildren(true) -- ensure the offset text doesn't spill over

  local fsc = cf.FontStringContainer
  local scrollFrame = CreateFrame("Frame", nil, cf)
  cf.__rothSmoothScroll = scrollFrame
  scrollFrame.offset = 0
  scrollFrame.startOffset = 0
  scrollFrame.startTime = 0
  scrollFrame.duration = tonumber(core:Get("smoothScrollDuration")) or 0.25
  scrollFrame:Hide()
  scrollFrame:SetScript("OnUpdate", function(f, elapsed)
    if not fsc then
      f:Hide()
      return
    end

    local now = GetTime()
    local duration = f.duration or 0.25
    local t = now - (f.startTime or now)

    if t >= duration then
      f.offset = 0
      fsc:ClearAllPoints()
      fsc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
      fsc:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
      f:Hide()
    else
      f.offset = outCubic(t, f.startOffset, 0 - f.startOffset, duration)
      fsc:ClearAllPoints()
      fsc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, f.offset)
      fsc:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, f.offset)
    end
  end)

  cf:HookScript("OnMouseWheel", function(self, delta)
    if not ControlsEnabled(core) then return end
    if IsShiftKeyDown() then
      if delta > 0 then
        self:ScrollToTop()
        scrollFrame.offset = 0
        scrollFrame:Hide()
      else
        self:ScrollToBottom()
        scrollFrame.offset = 0
        scrollFrame:Hide()
      end
    else
      local num = 3
      if not core:Get("smoothScrollEnabled") then
        if delta > 0 then
          for i = 1, num do self:ScrollUp() end
        else
          for i = 1, num do self:ScrollDown() end
        end
        return
      end

      local _, fontSize = self:GetFont()
      local distance = (fontSize + (self:GetSpacing() or 0))
      scrollFrame.duration = tonumber(core:Get("smoothScrollDuration")) or 0.25

      if delta > 0 then
        local offsetBefore = self:GetScrollOffset()
        for i = 1, num do self:ScrollUp() end
        local offsetAfter = self:GetScrollOffset()
        local diff = offsetAfter - offsetBefore
        if diff > 0 then
          scrollFrame.offset = scrollFrame.offset + (distance * diff)
          scrollFrame.startOffset = scrollFrame.offset
          scrollFrame.startTime = GetTime()
        end
      else
        local offsetBefore = self:GetScrollOffset()
        for i = 1, num do self:ScrollDown() end
        local offsetAfter = self:GetScrollOffset()
        local diff = offsetBefore - offsetAfter
        if diff > 0 then
          scrollFrame.offset = scrollFrame.offset - (distance * diff)
          scrollFrame.startOffset = scrollFrame.offset
          scrollFrame.startTime = GetTime()
        end
      end

      scrollFrame.offset = NS.Clamp(scrollFrame.offset, -distance * 6, distance * 6)
      scrollFrame.startOffset = scrollFrame.offset
      scrollFrame.startTime = GetTime()
      scrollFrame:Show()
    end
  end)

  -- AddMessage smooth-scroll animation is handled by the unified dispatcher.
  -- See OnSmoothScrollAddMessage below.
end

-- Unified AddMessage hook callback for smooth scroll (registered via core:RegisterAddMessageHook).
local function OnSmoothScrollAddMessage(chatFrame)
  if not controlsActive then return end
  local core = M and M.core
  if not core or not core:Get("smoothScrollEnabled") then return end
  if not chatFrame:IsVisible() then return end

  if type(chatFrame.GetScrollOffset) == "function" and chatFrame:GetScrollOffset() ~= 0 then return end

  local sf = chatFrame.__rothSmoothScroll
  if not sf then return end

  local _, fontSize = chatFrame:GetFont()
  local distance = (fontSize + (chatFrame:GetSpacing() or 0))

  sf.offset = sf.offset - distance
  sf.offset = NS.Clamp(sf.offset, -distance * 6, 0)
  sf.startOffset = sf.offset
  sf.startTime = GetTime()
  sf:Show()
end

local function HookAccessoryHover(core, cf, frame)
  if not frame or frame.__rothHoverHooked then return end
  frame.__rothHoverHooked = true

  frame:HookScript("OnEnter", function()
    if not ControlsEnabled(core) then return end
    GetOrCreateChatState(cf).hovering = true
    UpdateForChat(core, cf)
  end)

  frame:HookScript("OnLeave", function()
    if not ControlsEnabled(core) then return end
    ScheduleHoverRecalc(core, cf)
  end)
end

local function RegisterDefaultBlizzardFrames(core, cf)
  local st = GetOrCreateChatState(cf)
  local name = cf:GetName()
  if not name then return end

  local tab = _G[name .. "Tab"]
  if tab then
    tab.__rothKeepMouseEnabled = true
  end

  local eb = _G[name .. "EditBox"]

  local framesToHook = {
    _G[name .. "ButtonFrame"],
    tab,
    eb,
    cf.ScrollToBottomButton,
    cf.DownButton,
  }

  for _, frame in ipairs(framesToHook) do
    if frame then
      AddUnique(st.frames, frame)
      HookAccessoryHover(core, cf, frame)
    end
  end

  -- Хуки фокуса на EditBox: когда игрок нажимает Enter для ввода (даже в бою),
  -- Controls должен показать UI и не прятать его, пока фокус активен.
  if eb and not eb.__rothFocusHooked then
    eb.__rothFocusHooked = true
    eb:HookScript("OnEditFocusGained", function()
      if not ControlsEnabled(core) then return end
      st.hovering = true
      UpdateForChat(core, cf)
    end)
    eb:HookScript("OnEditFocusLost", function()
      if not ControlsEnabled(core) then return end
      ScheduleHoverRecalc(core, cf)
    end)
  end

  RequestHotspotBoundsUpdate(core, cf)
end

local function RegisterHoverFrame(core, cf, frame)
  if not cf or not frame then return end
  local st = GetOrCreateChatState(cf)
  AddUnique(st.frames, frame)
  HookAccessoryHover(core, cf, frame)
  RequestHotspotBoundsUpdate(core, cf)
  UpdateForChat(core, cf)
end

local function UpdateHoverState(core, cf)
  local st = GetOrCreateChatState(cf)
  st.hovering = IsAnyMouseOver(cf, st)
  UpdateForChat(core, cf)
end

local function GetHotspot(core, cf)
  local st = state.perChat[cf]
  return st and st.hotspot
end

local function HookBlizzardFade(core)
  if core.__blizzFadeHooked then return end
  core.__blizzFadeHooked = true

  hooksecurefunc("FCF_FadeInChatFrame", function(cf)
    if not ControlsEnabled(core) then return end
    if not core:Get("immersionEnabled") then return end
    UpdateHoverState(core, cf)
  end)

  hooksecurefunc("FCF_FadeOutChatFrame", function(cf)
    if not ControlsEnabled(core) then return end
    if not core:Get("immersionEnabled") then return end
    UpdateHoverState(core, cf)
  end)
end

local function EnsureChatFrameHandled(core, cf)
  if not cf then return end
  CreateHotspot(core, cf)
  HookHover(core, cf)
  HookScroll(core, cf)
  RegisterDefaultBlizzardFrames(core, cf)
  CreatePinButton(core, cf)
end

local function RefreshAllChats(core)
  for _, cf in ipairs(NS.GetChatFrames()) do
    EnsureChatFrameHandled(core, cf)
    local st = GetOrCreateChatState(cf)
    if not IsInteractableChatFrame(cf) then
      st.hovering = false
    end
    UpdateForChat(core, cf)
  end
end

local function QueueRefreshAllChats(core)
  NS.RunNextFrame(M, function()
    if not ControlsEnabled(core) then return end
    RefreshAllChats(core)
  end, "RothChat:ControlsRefreshAll")
end

local function IsNamedChatFrame(frame)
  if not frame or type(frame.GetName) ~= "function" then return false end
  local name = frame:GetName()
  return type(name) == "string" and name:match("^ChatFrame%d+$") ~= nil
end

local function RegisterLifecycleListeners(core)
  if core.__rothControlsLifecycleRegistered then return end
  core.__rothControlsLifecycleRegistered = true

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame, reason)
    if not ControlsEnabled(core2) then return end
    if not IsNamedChatFrame(chatFrame) then return end

    if reason == "set_temporary_window_type" and chatFrame.isTemporary then
      ResetTransientState(GetOrCreateChatState(chatFrame))
    end

    EnsureChatFrameHandled(core2, chatFrame)
    UpdateForChat(core2, chatFrame)
  end, M)

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if not ControlsEnabled(core2) then return end
    QueueRefreshAllChats(core2)
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if not ControlsEnabled(core2) then return end
    if not chatFrame then return end

    local st = state.perChat[chatFrame]
    if st then
      ResetTransientState(st)
    end
  end, M)

  core:On("COPY_OVERLAY_VISIBILITY", function(_, core2, chatFrame, visible)
    if not chatFrame then return end
    local st = GetOrCreateChatState(chatFrame)
    st.copyOverlayVisible = visible and true or false
    UpdateForChat(core2, chatFrame)
  end, M)
end

function M:Init(core)
  self.core = core
  core.RegisterHoverFrame = RegisterHoverFrame
  core.UpdateHoverState = UpdateHoverState
  core.GetHotspot = GetHotspot -- Export for CopyOverlay
  return true
end

function M:OnEnable(core)
  controlsActive = true

  -- Register smooth scroll with unified dispatcher (priority 50 = after Restore/Ticker)
  core:RegisterAddMessageHook(OnSmoothScrollAddMessage, self, 50)

  local function ApplyAll()
    core:EnsureChatLifecycleHooks()
    HookBlizzardFade(core)
    RegisterLifecycleListeners(core)
    for _, cf in ipairs(NS.GetChatFrames()) do
      EnsureChatFrameHandled(core, cf)
      GetOrCreateChatState(cf).hovering = false
      UpdateForChat(core, cf)
    end
    QueueRefreshAllChats(core)
  end

  if InCombatLockdown() then
    core:Defer(ApplyAll)
  else
    ApplyAll()
  end
end

function M:OnLogin(core)
end

function M:OnDisable(core)
  controlsActive = false
  core:UnregisterAddMessageHooks(self)

  for cf, st in pairs(state.perChat) do
    ResetTransientState(st)
    st.hovering = false
    st.pinned = false

    SetControlsVisible(core, cf, true)
    if st.button and st.button.EnableMouse then
      st.button:EnableMouse(false)
      st.button:SetAlpha(0)
    end
    if st.hotspot and st.hotspot.EnableMouse then
      st.hotspot:EnableMouse(false)
    end

    core:Emit("CONTROLS_VISIBILITY", cf, true, false, false)
  end
end

RothChat:RegisterModule(M)
