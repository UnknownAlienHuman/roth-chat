-- RothChat - Controls module
-- Responsibilities:
--   * Fade Blizzard chat chrome + Roth extras in/out on hover
--   * Provide a pin button
--   * Own accessory hover registration
--   * Provide fast and smooth scrolling without double-processing Blizzard scroll

local _, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Controls",
  defaultEnabled = true,
  description = "Mouseover controls, Immersion logic, and Fast Scroll.",
}

local state = { perChat = {} }
local wheelSnapshots = setmetatable({}, { __mode = "k" })
local presentationSnapshots = setmetatable({}, { __mode = "k" })
local ALPHA_EPSILON = 0.01
local controlsActive = false
local lifecycleListenersRegistered = false
M.__applyDeferredKey = {}
M.__refreshDeferredKey = {}
M.__restoreDeferredKey = {}

local UpdateForChat
local RegisterHoverFrame
local UnregisterHoverFrame

local function ControlsEnabled()
  return controlsActive
end

local function CanUseObject(object)
  return object ~= nil and NS.CanAccessObject(object)
end

local function GetAlpha(frame)
  if not CanUseObject(frame) then return nil end
  local ok, method = pcall(function() return frame.GetAlpha end)
  if not ok or not NS.CanAccessValue(method) or type(method) ~= "function" then return nil end
  local read, alpha = pcall(method, frame)
  return read and NS.SafeNumber(alpha) or nil
end

local function GetMouseEnabled(frame)
  if not CanUseObject(frame) then return nil end
  local ok, method = pcall(function() return frame.IsMouseEnabled end)
  if not ok or not NS.CanAccessValue(method) or type(method) ~= "function" then return nil end
  local read, enabled = pcall(method, frame)
  if not read or not NS.CanAccessValue(enabled) then return nil end
  return enabled and true or false
end

local function CapturePresentationOwnership(frame)
  if not CanUseObject(frame) or presentationSnapshots[frame] then return end
  presentationSnapshots[frame] = {
    alpha = GetAlpha(frame),
    mouseEnabled = GetMouseEnabled(frame),
  }
end

local function SetOwnedAlpha(frame, target, duration)
  if not CanUseObject(frame) then return false end
  CapturePresentationOwnership(frame)
  local snapshot = presentationSnapshots[frame]
  if not snapshot then return false end
  if not NS.FadeTo(frame, target, duration, nil, M) then return false end
  snapshot.lastAlphaWrite = target
  return true
end

local function SetOwnedMouse(frame, enabled)
  if not CanUseObject(frame) then return false end
  CapturePresentationOwnership(frame)
  local snapshot = presentationSnapshots[frame]
  if not snapshot then return false end
  local ok = pcall(function() frame:EnableMouse(enabled) end)
  if not ok then return false end
  snapshot.lastMouseWrite = enabled and true or false
  return true
end

local function RestorePresentationOwnership(frame)
  local snapshot = frame and presentationSnapshots[frame]
  if not snapshot then return false end
  presentationSnapshots[frame] = nil
  if not CanUseObject(frame) then return false end

  local hadActiveFade = type(NS.IsFading) == "function" and NS.IsFading(frame) or false
  local ownsActiveFade = type(NS.StopOwnedFade) == "function" and NS.StopOwnedFade(frame, M) or false
  local currentAlpha = GetAlpha(frame)
  local alphaStillOwned = ownsActiveFade
    or (not hadActiveFade and type(snapshot.lastAlphaWrite) == "number" and type(currentAlpha) == "number"
      and math.abs(currentAlpha - snapshot.lastAlphaWrite) < ALPHA_EPSILON)
  if alphaStillOwned and type(snapshot.alpha) == "number" then
    pcall(function() frame:SetAlpha(snapshot.alpha) end)
  end

  local currentMouse = GetMouseEnabled(frame)
  if snapshot.mouseEnabled ~= nil and snapshot.lastMouseWrite ~= nil
    and currentMouse == snapshot.lastMouseWrite
  then
    pcall(function() frame:EnableMouse(snapshot.mouseEnabled) end)
  end
  return true
end

local function CaptureWheelOwnership(chatFrame)
  if not CanUseObject(chatFrame) or wheelSnapshots[chatFrame] then return end
  local snapshot = {}
  if type(chatFrame.GetScript) == "function" then
    local ok, script = pcall(chatFrame.GetScript, chatFrame, "OnMouseWheel")
    if ok then snapshot.script = script end
  end
  if type(chatFrame.IsMouseWheelEnabled) == "function" then
    local ok, enabled = pcall(chatFrame.IsMouseWheelEnabled, chatFrame)
    if ok and NS.CanAccessValue(enabled) then
      snapshot.mouseWheelEnabled = enabled and true or false
    end
  end
  if type(chatFrame.GetClipsChildren) == "function" then
    local ok, clips = pcall(chatFrame.GetClipsChildren, chatFrame)
    if ok and NS.CanAccessValue(clips) then
      snapshot.clipsChildren = clips and true or false
    end
  end
  wheelSnapshots[chatFrame] = snapshot
end

local function RestoreWheelOwnership(chatFrame)
  local snapshot = wheelSnapshots[chatFrame]
  if not snapshot or not CanUseObject(chatFrame) then return false end

  if type(chatFrame.GetScript) == "function" and type(chatFrame.SetScript) == "function" then
    local ok, current = pcall(chatFrame.GetScript, chatFrame, "OnMouseWheel")
    if ok and current == chatFrame.__rothMouseWheelHandler then
      pcall(chatFrame.SetScript, chatFrame, "OnMouseWheel", snapshot.script)
    end
  end
  if snapshot.mouseWheelEnabled ~= nil and type(chatFrame.IsMouseWheelEnabled) == "function"
    and type(chatFrame.EnableMouseWheel) == "function"
  then
    local ok, current = pcall(chatFrame.IsMouseWheelEnabled, chatFrame)
    if ok and NS.CanAccessValue(current) and current == true then
      pcall(chatFrame.EnableMouseWheel, chatFrame, snapshot.mouseWheelEnabled)
    end
  end
  if snapshot.clipsChildren ~= nil and type(chatFrame.GetClipsChildren) == "function"
    and type(chatFrame.SetClipsChildren) == "function"
  then
    local ok, current = pcall(chatFrame.GetClipsChildren, chatFrame)
    if ok and NS.CanAccessValue(current) and current == true then
      pcall(chatFrame.SetClipsChildren, chatFrame, snapshot.clipsChildren)
    end
  end

  wheelSnapshots[chatFrame] = nil
  return true
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
  for _, existing in ipairs(list) do
    if existing == frame then return end
  end
  list[#list + 1] = frame
end

local function RemoveFrame(list, frame)
  for i = #list, 1, -1 do
    if list[i] == frame then table.remove(list, i) end
  end
end

local function GetFrameRect(frame)
  if not CanUseObject(frame) or type(frame.GetRect) ~= "function" then return nil end
  local left, bottom, width, height = frame:GetRect()
  if not left or not bottom or not width or not height or width <= 0 or height <= 0 then return nil end
  return left, bottom, left + width, bottom + height
end

local function IsInteractableChatFrame(cf)
  if not CanUseObject(cf) or not cf:IsShown() then return false end

  if NS.IsDockedChatFrame(cf) then
    local selected = NS.GetSelectedDockChatFrame()
    if selected and selected ~= cf then return false end
  end

  return true
end

local function IsAnyMouseOver(cf, st)
  if not IsInteractableChatFrame(cf) then return false end
  if cf.__rothResizing then return true end

  local name = cf.GetName and cf:GetName()
  local editBox = name and _G[name .. "EditBox"]
  if CanUseObject(editBox) then
    local ok, activeEditBox = pcall(function()
      return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    end)
    if ((ok and CanUseObject(activeEditBox) and activeEditBox == editBox)
      or (editBox.HasFocus and editBox:HasFocus())) then
      return true
    end
  end

  if CanUseObject(st.hotspot) and st.hotspot:IsMouseOver() then return true end
  if cf:IsMouseOver() then return true end
  if CanUseObject(st.button) and st.button:IsMouseOver() then return true end
  for _, frame in ipairs(st.frames) do
    if CanUseObject(frame) and frame:IsMouseOver() then return true end
  end
  return false
end

local function ScheduleHoverRecalc(core, cf)
  local st = GetOrCreateChatState(cf)
  local delay = tonumber(core:Get("hoverFadeDelay")) or 30

  NS.Schedule(st._hoverScheduleKey, delay, function()
    if not ControlsEnabled() then return end
    if not IsInteractableChatFrame(cf) then
      st.hovering = false
    else
      st.hovering = IsAnyMouseOver(cf, st)
    end
    UpdateForChat(core, cf)
  end, "RothChat:ControlsHover")
end

local function RequestHotspotBoundsUpdate(core, cf)
  local st = GetOrCreateChatState(cf)
  if not CanUseObject(st.hotspot) or not CanUseObject(cf) then return end

  NS.RunNextFrame(st._boundsScheduleKey, function()
    if not ControlsEnabled() or not IsInteractableChatFrame(cf) then return end
    local hotspot = st.hotspot
    if not hotspot then return end

    local minLeft, minBottom, maxRight, maxTop
    local function Accumulate(frame)
      local left, bottom, right, top = GetFrameRect(frame)
      if not left then return end
      if not minLeft or left < minLeft then minLeft = left end
      if not minBottom or bottom < minBottom then minBottom = bottom end
      if not maxRight or right > maxRight then maxRight = right end
      if not maxTop or top > maxTop then maxTop = top end
    end

    Accumulate(cf)
    Accumulate(st.button)
    for _, frame in ipairs(st.frames) do Accumulate(frame) end

    if not minLeft then
      hotspot:ClearAllPoints()
      hotspot:SetAllPoints(cf)
      return
    end

    local padding = NS.Clamp(tonumber(core:Get("hotspotPadding")) or 10, 0, 24)
    hotspot:ClearAllPoints()
    hotspot:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", minLeft - padding, minBottom - padding)
    hotspot:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", maxRight + padding, maxTop + padding)
  end, "RothChat:ControlsBounds")
end

local function CreateHotspot(core, cf)
  if not CanUseObject(cf) then return nil end
  local st = GetOrCreateChatState(cf)
  if st.hotspot then return CanUseObject(st.hotspot) and st.hotspot or nil end

  local hotspot = CreateFrame("Frame", nil, UIParent)
  hotspot:SetFrameStrata("HIGH")
  hotspot:SetFrameLevel(1000)
  hotspot:SetAllPoints(cf)
  hotspot:SetAlpha(0)
  hotspot:EnableMouse(true)
  hotspot:Hide()
  if hotspot.SetBackdrop then hotspot:SetBackdrop(nil) end

  hotspot:SetScript("OnEnter", function()
    if not ControlsEnabled() then return end
    st.hovering = true
    UpdateForChat(core, cf)
  end)
  hotspot:SetScript("OnLeave", function()
    if ControlsEnabled() then ScheduleHoverRecalc(core, cf) end
  end)

  st.hotspot = hotspot
  RequestHotspotBoundsUpdate(core, cf)
  return hotspot
end

local function SetControlsVisible(core, cf, visible)
  if not ControlsEnabled() then return end
  local st = GetOrCreateChatState(cf)
  local shownAlpha = core:Get("hoverAlphaShown") or 1
  local hiddenAlpha = core:Get("hoverAlphaHidden") or 0
  local duration = visible
    and (tonumber(core:Get("hoverFadeInDuration")) or tonumber(core:Get("hoverFadeDuration")) or 0.14)
    or (tonumber(core:Get("hoverFadeOutDuration")) or tonumber(core:Get("hoverFadeDuration")) or 0.35)
  local target = visible and shownAlpha or hiddenAlpha

  for _, frame in ipairs(st.frames) do
    if CanUseObject(frame) then
      if frame.__rothKeepMouseEnabled then
        SetOwnedAlpha(frame, 1, 0)
        SetOwnedMouse(frame, true)
      else
        SetOwnedAlpha(frame, target, duration)
        SetOwnedMouse(frame, visible)
      end
    end
  end

  if CanUseObject(st.button) then
    local showPin = visible and ControlsEnabled()
    local buttonTarget = showPin and 1 or 0
    NS.FadeTo(st.button, buttonTarget, duration, nil, M)
    pcall(function() st.button:EnableMouse(buttonTarget > 0) end)
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
  if not ControlsEnabled() then return end
  local st = GetOrCreateChatState(cf)

  if not IsInteractableChatFrame(cf) then
    st.hovering = false
    SetControlsVisible(core, cf, false)
    if CanUseObject(st.hotspot) then
      st.hotspot:Hide()
      st.hotspot:EnableMouse(false)
    end
    if CanUseObject(st.button) then st.button:EnableMouse(false) end
    return
  end

  if st.copyOverlayVisible then
    st.hovering = false
    SetControlsVisible(core, cf, false)
    if CanUseObject(st.hotspot) then
      st.hotspot:Hide()
      st.hotspot:EnableMouse(false)
    end
    if CanUseObject(st.button) then st.button:EnableMouse(false) end

    if st.lastVisible ~= false or st.lastPinned ~= st.pinned or st.lastHovering ~= st.hovering then
      st.lastVisible = false
      st.lastPinned = st.pinned
      st.lastHovering = st.hovering
      core:Emit("CONTROLS_VISIBILITY", cf, false, st.pinned, st.hovering)
    end
    return
  end

  if CanUseObject(st.hotspot) then st.hotspot:Show() end

  local visible = ShouldShow(core, cf)
  SetControlsVisible(core, cf, visible)

  local active = st.pinned or st.hovering
  if CanUseObject(st.hotspot) then st.hotspot:EnableMouse(not active) end

  if st.lastVisible ~= visible or st.lastPinned ~= st.pinned or st.lastHovering ~= st.hovering then
    st.lastVisible = visible
    st.lastPinned = st.pinned
    st.lastHovering = st.hovering
    core:Emit("CONTROLS_VISIBILITY", cf, visible, st.pinned, st.hovering)
  end
end

local function CreatePinButton(core, cf)
  if not CanUseObject(cf) then return nil end
  local st = GetOrCreateChatState(cf)
  if st.button then return CanUseObject(st.button) and st.button or nil end

  local parent = st.hotspot or CreateHotspot(core, cf)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(20, 20)
  button:SetPoint("TOPLEFT", cf, "TOPLEFT", -12, 12)
  button:EnableMouse(true)
  button:SetAlpha(0)

  NS.ApplyGlassBackdrop(button, 0.8, 0, 0)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 2, -2)
  icon:SetPoint("BOTTOMRIGHT", -2, 2)
  icon:SetTexture(NS.ICONS_TEXTURE)
  local tc = NS.BUTTON_ICONS.MINIMIZE
  icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
  button.__tex = icon

  NS.CreateHighlight(button, "HIGHLIGHT", nil, nil, nil, 0)

  button:SetScript("OnEnter", function()
    if not ControlsEnabled() then return end
    st.hovering = true
    UpdateForChat(core, cf)
  end)
  button:SetScript("OnLeave", function()
    if ControlsEnabled() then ScheduleHoverRecalc(core, cf) end
  end)
  button:SetScript("OnClick", function()
    if not ControlsEnabled() then return end
    st.pinned = not st.pinned
    local coords = st.pinned and NS.BUTTON_ICONS.MAXIMIZE or NS.BUTTON_ICONS.MINIMIZE
    icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    UpdateForChat(core, cf)
  end)

  st.button = button
  RequestHotspotBoundsUpdate(core, cf)
  return button
end

local function HookHover(core, cf)
  if not CanUseObject(cf) then return end
  if cf.__rothControlsHooked then return end
  cf.__rothControlsHooked = true

  cf:HookScript("OnEnter", function()
    if not ControlsEnabled() then return end
    GetOrCreateChatState(cf).hovering = true
    UpdateForChat(core, cf)
  end)
  cf:HookScript("OnLeave", function()
    if ControlsEnabled() then ScheduleHoverRecalc(core, cf) end
  end)
end

local function outCubic(t, b, c, d)
  t = t / d - 1
  return c * (t ^ 3 + 1) + b
end

local function ResetSmoothScroll(cf, restoreContainer)
  if not CanUseObject(cf) then return end
  local scrollFrame = cf.__rothSmoothScroll
  if scrollFrame then
    scrollFrame.offset = 0
    scrollFrame.startOffset = 0
    scrollFrame.startTime = 0
    scrollFrame:Hide()
  end

  local container = restoreContainer == false and nil or cf.FontStringContainer
  if container and CanUseObject(container) then
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
    container:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
  end
end

local function HandleMouseWheel(core, self, delta)
  if not ControlsEnabled() then
    local snapshot = wheelSnapshots[self]
    local original = snapshot and snapshot.script
    if original then original(self, delta) end
    return
  end

  if IsShiftKeyDown() then
    ResetSmoothScroll(self)
    if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
    return
  end

  local lines = 3
  if not core:Get("smoothScrollEnabled") then
    ResetSmoothScroll(self)
    if delta > 0 then
      for _ = 1, lines do self:ScrollUp() end
    else
      for _ = 1, lines do self:ScrollDown() end
    end
    return
  end

  local _, fontSize = self:GetFont()
  fontSize = tonumber(fontSize) or 12
  local distance = fontSize + (tonumber(self:GetSpacing()) or 0)
  if distance <= 0 then return end

  local scrollFrame = self.__rothSmoothScroll
  if not scrollFrame then return end
  scrollFrame.duration = math.max(0.01, tonumber(core:Get("smoothScrollDuration")) or 0.25)

  local moved = false
  if delta > 0 then
    local before = self:GetScrollOffset()
    for _ = 1, lines do self:ScrollUp() end
    local difference = self:GetScrollOffset() - before
    if difference > 0 then
      scrollFrame.offset = scrollFrame.offset + distance * difference
      moved = true
    end
  else
    local before = self:GetScrollOffset()
    for _ = 1, lines do self:ScrollDown() end
    local difference = before - self:GetScrollOffset()
    if difference > 0 then
      scrollFrame.offset = scrollFrame.offset - distance * difference
      moved = true
    end
  end

  if moved then
    scrollFrame.offset = NS.Clamp(scrollFrame.offset, -distance * 6, distance * 6)
    scrollFrame.startOffset = scrollFrame.offset
    scrollFrame.startTime = GetTime()
    scrollFrame:Show()
  end
end

local function HookScroll(core, cf)
  if not CanUseObject(cf) then return end
  CaptureWheelOwnership(cf)
  if not wheelSnapshots[cf] then return end

  if not cf.__rothScrollHooked then
    cf.__rothScrollHooked = true

    local container = cf.FontStringContainer
    local scrollFrame = CreateFrame("Frame", nil, cf)
    cf.__rothSmoothScroll = scrollFrame
    scrollFrame.offset = 0
    scrollFrame.startOffset = 0
    scrollFrame.startTime = 0
    scrollFrame.duration = tonumber(core:Get("smoothScrollDuration")) or 0.25
    scrollFrame:Hide()

    scrollFrame:SetScript("OnUpdate", function(frame)
      if not controlsActive then
        frame:Hide()
        return
      end
      if not container then
        frame:Hide()
        return
      end

      local now = GetTime()
      local duration = math.max(0.01, tonumber(frame.duration) or 0.25)
      local elapsed = now - (frame.startTime or now)

      if elapsed >= duration then
        ResetSmoothScroll(cf)
      else
        frame.offset = outCubic(elapsed, frame.startOffset, -frame.startOffset, duration)
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, frame.offset)
        container:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, frame.offset)
      end
    end)

    cf.__rothMouseWheelHandler = function(self, delta)
      HandleMouseWheel(core, self, delta)
    end
  end

  if type(cf.EnableMouseWheel) == "function" then cf:EnableMouseWheel(true) end
  if type(cf.SetClipsChildren) == "function" then cf:SetClipsChildren(true) end

  local current = cf:GetScript("OnMouseWheel")
  if current ~= cf.__rothMouseWheelHandler then
    -- If another owner replaced the handler while Controls was active, keep
    -- that current script as the delegate and restore target on disable.
    local snapshot = wheelSnapshots[cf]
    if snapshot and cf.__rothScrollHandlerInstalled then snapshot.script = current end
    cf:SetScript("OnMouseWheel", cf.__rothMouseWheelHandler)
    cf.__rothScrollHandlerInstalled = true
  end
end

local function OnSmoothScrollAddMessage(chatFrame)
  if not controlsActive then return end
  if NS.IsChatMessagingRestricted() then return end
  if not CanUseObject(chatFrame) then return end
  local core = M.core
  if not core or not core:Get("smoothScrollEnabled") or not chatFrame:IsVisible() then return end
  if type(chatFrame.GetScrollOffset) == "function" and chatFrame:GetScrollOffset() ~= 0 then return end

  local scrollFrame = chatFrame.__rothSmoothScroll
  if not scrollFrame then return end

  local _, fontSize = chatFrame:GetFont()
  fontSize = tonumber(fontSize) or 12
  local distance = fontSize + (tonumber(chatFrame:GetSpacing()) or 0)
  if distance <= 0 then return end

  scrollFrame.offset = NS.Clamp(scrollFrame.offset - distance, -distance * 6, 0)
  scrollFrame.startOffset = scrollFrame.offset
  scrollFrame.startTime = GetTime()
  scrollFrame:Show()
end

local function HookAccessoryHover(core, frame)
  if not CanUseObject(frame) then return end
  frame.__rothHoverChats = frame.__rothHoverChats or {}
  if frame.__rothHoverHooked then return end
  frame.__rothHoverHooked = true

  frame:HookScript("OnEnter", function(self)
    if not ControlsEnabled() then return end
    for cf in pairs(self.__rothHoverChats or {}) do
      local st = state.perChat[cf]
      if st then
        st.hovering = true
        UpdateForChat(core, cf)
      end
    end
  end)

  frame:HookScript("OnLeave", function(self)
    if not ControlsEnabled() then return end
    for cf in pairs(self.__rothHoverChats or {}) do
      ScheduleHoverRecalc(core, cf)
    end
  end)
end

RegisterHoverFrame = function(core, cf, frame)
  if not CanUseObject(cf) or not CanUseObject(frame) then return end
  local st = GetOrCreateChatState(cf)
  AddUnique(st.frames, frame)
  frame.__rothHoverChats = frame.__rothHoverChats or {}
  frame.__rothHoverChats[cf] = true
  HookAccessoryHover(core, frame)
  RequestHotspotBoundsUpdate(core, cf)
  UpdateForChat(core, cf)
end

UnregisterHoverFrame = function(core, cf, frame)
  if not CanUseObject(cf) or not CanUseObject(frame) then return end
  local st = state.perChat[cf]
  if st then
    RemoveFrame(st.frames, frame)
    st.hovering = IsAnyMouseOver(cf, st)
    RequestHotspotBoundsUpdate(core, cf)
    UpdateForChat(core, cf)
  end
  if frame.__rothHoverChats then
    frame.__rothHoverChats[cf] = nil
    if not next(frame.__rothHoverChats) then RestorePresentationOwnership(frame) end
  end
end

local function RegisterDefaultBlizzardFrames(core, cf)
  if not CanUseObject(cf) then return end
  local st = GetOrCreateChatState(cf)
  local name = cf:GetName()
  if not name then return end

  local tab = _G[name .. "Tab"]
  if tab then tab.__rothKeepMouseEnabled = true end

  local editBox = _G[name .. "EditBox"]
  local framesToHook = {
    _G[name .. "ButtonFrame"],
    tab,
    editBox,
    cf.ScrollToBottomButton,
    cf.DownButton,
  }

  for _, frame in ipairs(framesToHook) do
    if frame then RegisterHoverFrame(core, cf, frame) end
  end

  if editBox and not editBox.__rothFocusHooked then
    editBox.__rothFocusHooked = true
    editBox:HookScript("OnEditFocusGained", function()
      if not ControlsEnabled() then return end
      st.hovering = true
      UpdateForChat(core, cf)
    end)
    editBox:HookScript("OnEditFocusLost", function()
      if ControlsEnabled() then ScheduleHoverRecalc(core, cf) end
    end)
  end

  RequestHotspotBoundsUpdate(core, cf)
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

  if type(_G.FCF_FadeInChatFrame) == "function" then
    hooksecurefunc("FCF_FadeInChatFrame", function(cf)
      if ControlsEnabled() and core:Get("immersionEnabled") then UpdateHoverState(core, cf) end
    end)
  end

  if type(_G.FCF_FadeOutChatFrame) == "function" then
    hooksecurefunc("FCF_FadeOutChatFrame", function(cf)
      if ControlsEnabled() and core:Get("immersionEnabled") then UpdateHoverState(core, cf) end
    end)
  end
end

local function EnsureChatFrameHandled(core, cf)
  if not CanUseObject(cf) then return end
  CreateHotspot(core, cf)
  HookHover(core, cf)
  HookScroll(core, cf)
  RegisterDefaultBlizzardFrames(core, cf)
  CreatePinButton(core, cf)
end

local function RefreshAllChats(core)
  if InCombatLockdown() then
    core:DeferKeyed(M.__refreshDeferredKey, function()
      if controlsActive then RefreshAllChats(core) end
    end)
    return
  end
  for _, cf in ipairs(NS.GetChatFrames()) do
    EnsureChatFrameHandled(core, cf)
    local st = GetOrCreateChatState(cf)
    if not IsInteractableChatFrame(cf) then st.hovering = false end
    if not core:Get("smoothScrollEnabled") then ResetSmoothScroll(cf) end
    UpdateForChat(core, cf)
  end
end

local function QueueRefreshAllChats(core)
  NS.RunNextFrame(M, function()
    if ControlsEnabled() then RefreshAllChats(core) end
  end, "RothChat:ControlsRefreshAll")
end

local function IsNamedChatFrame(frame)
  if not frame or type(frame.GetName) ~= "function" then return false end
  local name = frame:GetName()
  return type(name) == "string" and name:match("^ChatFrame%d+$") ~= nil
end

local function RegisterLifecycleListeners(core)
  if lifecycleListenersRegistered then return end
  lifecycleListenersRegistered = true

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame, reason)
    if not ControlsEnabled() or not IsNamedChatFrame(chatFrame) then return end
    if InCombatLockdown() then
      RefreshAllChats(core2)
      return
    end

    if reason == "set_temporary_window_type" and chatFrame.isTemporary then
      ResetTransientState(GetOrCreateChatState(chatFrame))
    end

    EnsureChatFrameHandled(core2, chatFrame)
    UpdateForChat(core2, chatFrame)
  end, M)

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if ControlsEnabled() then QueueRefreshAllChats(core2) end
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if not ControlsEnabled() or not chatFrame then return end
    if InCombatLockdown() then
      RefreshAllChats(core2)
      return
    end
    local st = state.perChat[chatFrame]
    if st then
      ResetTransientState(st)
      ResetSmoothScroll(chatFrame)
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
  core.UnregisterHoverFrame = UnregisterHoverFrame
  core.UpdateHoverState = UpdateHoverState
  core.GetHotspot = GetHotspot
  return true
end

function M:OnEnable(core)
  core:CancelDeferred(M.__applyDeferredKey)
  core:CancelDeferred(M.__refreshDeferredKey)
  core:CancelDeferred(M.__restoreDeferredKey)
  controlsActive = true
  lifecycleListenersRegistered = false
  core:RegisterAddMessageHook(OnSmoothScrollAddMessage, self, 50)

  local function ApplyAll()
    if not ControlsEnabled() then return end
    core:EnsureChatLifecycleHooks()
    HookBlizzardFade(core)
    RegisterLifecycleListeners(core)
    for _, cf in ipairs(NS.GetChatFrames()) do
      EnsureChatFrameHandled(core, cf)
      GetOrCreateChatState(cf).hovering = false
      UpdateForChat(core, cf)
    end
    QueueRefreshAllChats(core)
    -- Controls may be enabled after accessory modules completed their own
    -- lifecycle. Re-emit frame readiness so ChatBar, Resize and CopyOverlay can
    -- attach to the newly created hover surfaces.
    core:QueueChatLifecycleRefresh(nil, "controls_enabled")
  end

  if InCombatLockdown() then
    core:DeferKeyed(M.__applyDeferredKey, function()
      if core:IsModuleActive("Controls") then ApplyAll() end
    end)
  else
    ApplyAll()
  end
end

function M:OnDisable(core)
  controlsActive = false
  lifecycleListenersRegistered = false
  core:UnregisterAddMessageHooks(self)
  NS.CancelScheduled(M)
  core:CancelDeferred(M.__applyDeferredKey)
  core:CancelDeferred(M.__refreshDeferredKey)
  core:CancelDeferred(M.__restoreDeferredKey)

  local function RestoreControlsState()
    if controlsActive then return end
    local restored = setmetatable({}, { __mode = "k" })
    for cf, st in pairs(state.perChat) do
      ResetTransientState(st)
      st.hovering = false
      st.pinned = false

      ResetSmoothScroll(cf)
      RestoreWheelOwnership(cf)

      for _, frame in ipairs(st.frames) do
        if not restored[frame] then
          restored[frame] = true
          RestorePresentationOwnership(frame)
        end
      end

      if CanUseObject(st.button) then
        NS.StopFading(st.button)
        st.button:EnableMouse(false)
        st.button:SetAlpha(0)
      end
      if CanUseObject(st.hotspot) then
        st.hotspot:EnableMouse(false)
        st.hotspot:Hide()
      end

      core:Emit("CONTROLS_VISIBILITY", cf, true, false, false)
    end
  end

  if InCombatLockdown() then
    core:DeferKeyed(M.__restoreDeferredKey, RestoreControlsState)
  else
    RestoreControlsState()
  end
end

function M:Refresh(core)
  if ControlsEnabled() then RefreshAllChats(core) end
end

RothChat:RegisterModule(M)
