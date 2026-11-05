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

local function ReadField(object, name)
  return object[name]
end

local function GetField(object, name)
  if not CanUseObject(object) then return nil end
  local ok, value = pcall(ReadField, object, name)
  if not ok or not NS.CanAccessValue(value) then return nil end
  return value
end

local function GetMethod(object, name)
  local method = GetField(object, name)
  return type(method) == "function" and method or nil
end

local function CallOne(object, name, ...)
  local method = GetMethod(object, name)
  if not method then return nil end
  local ok, value = pcall(method, object, ...)
  if not ok or not NS.CanAccessValue(value) then return nil end
  return value
end

local function Invoke(object, name, ...)
  local method = GetMethod(object, name)
  if not method then return false end
  return pcall(method, object, ...)
end

local function GetAlpha(frame)
  return NS.SafeNumber(CallOne(frame, "GetAlpha"))
end

local function GetMouseEnabled(frame)
  local enabled = CallOne(frame, "IsMouseEnabled")
  if type(enabled) ~= "boolean" then return nil end
  return enabled
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
  if not snapshot or not Invoke(frame, "EnableMouse", enabled) then return false end
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
    Invoke(frame, "SetAlpha", snapshot.alpha)
  end

  local currentMouse = GetMouseEnabled(frame)
  if snapshot.mouseEnabled ~= nil and snapshot.lastMouseWrite ~= nil
    and currentMouse == snapshot.lastMouseWrite
  then
    Invoke(frame, "EnableMouse", snapshot.mouseEnabled)
  end
  return true
end

local function CaptureWheelOwnership(chatFrame)
  if not CanUseObject(chatFrame) or wheelSnapshots[chatFrame] then return end
  local snapshot = {}
  local getScript = GetMethod(chatFrame, "GetScript")
  if getScript then
    local ok, script = pcall(getScript, chatFrame, "OnMouseWheel")
    if ok and NS.CanAccessValue(script) then snapshot.script = script end
  end
  local enabled = CallOne(chatFrame, "IsMouseWheelEnabled")
  if type(enabled) == "boolean" then snapshot.mouseWheelEnabled = enabled end
  local clips = CallOne(chatFrame, "GetClipsChildren")
  if type(clips) == "boolean" then snapshot.clipsChildren = clips end
  wheelSnapshots[chatFrame] = snapshot
end

local function RestoreWheelOwnership(chatFrame)
  local snapshot = wheelSnapshots[chatFrame]
  if not snapshot or not CanUseObject(chatFrame) then return false end

  local current = CallOne(chatFrame, "GetScript", "OnMouseWheel")
  if current == chatFrame.__rothMouseWheelHandler then
    Invoke(chatFrame, "SetScript", "OnMouseWheel", snapshot.script)
  end

  if snapshot.mouseWheelEnabled ~= nil
    and CallOne(chatFrame, "IsMouseWheelEnabled") == true
  then
    Invoke(chatFrame, "EnableMouseWheel", snapshot.mouseWheelEnabled)
  end

  if snapshot.clipsChildren ~= nil
    and CallOne(chatFrame, "GetClipsChildren") == true
  then
    Invoke(chatFrame, "SetClipsChildren", snapshot.clipsChildren)
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
  for index = #list, 1, -1 do
    if list[index] == frame then table.remove(list, index) end
  end
end

local function GetFrameRect(frame)
  local method = GetMethod(frame, "GetRect")
  if not method then return nil end
  local ok, left, bottom, width, height = pcall(method, frame)
  if not ok or not NS.CanAccessValue(left) or not NS.CanAccessValue(bottom)
    or not NS.CanAccessValue(width) or not NS.CanAccessValue(height)
  then
    return nil
  end
  left, bottom = NS.SafeNumber(left), NS.SafeNumber(bottom)
  width, height = NS.SafeNumber(width), NS.SafeNumber(height)
  if left == nil or bottom == nil or width == nil or height == nil
    or width <= 0 or height <= 0
  then
    return nil
  end
  return left, bottom, left + width, bottom + height
end

local function IsInteractableChatFrame(cf)
  if not CanUseObject(cf) or CallOne(cf, "IsShown") ~= true then return false end

  if NS.IsDockedChatFrame(cf) then
    local selected = NS.GetSelectedDockChatFrame()
    if selected and selected ~= cf then return false end
  end

  return true
end

local function IsMouseOver(frame)
  return CanUseObject(frame) and CallOne(frame, "IsMouseOver") == true
end

local function IsAnyMouseOver(cf, st)
  if not IsInteractableChatFrame(cf) then return false end
  if NS.CanAccessValue(cf.__rothResizing) and cf.__rothResizing then return true end

  local name = CallOne(cf, "GetName")
  local editBox = type(name) == "string" and _G[name .. "EditBox"] or nil
  if CanUseObject(editBox) then
    local activeEditBox
    if type(_G.ChatEdit_GetActiveWindow) == "function" then
      local ok, active = pcall(_G.ChatEdit_GetActiveWindow)
      if ok and CanUseObject(active) then activeEditBox = active end
    end
    if activeEditBox == editBox or CallOne(editBox, "HasFocus") == true then
      return true
    end
  end

  if IsMouseOver(st.hotspot) or IsMouseOver(cf) or IsMouseOver(st.button) then return true end
  for _, frame in ipairs(st.frames) do
    if IsMouseOver(frame) then return true end
  end
  return false
end

local function ScheduleHoverRecalc(core, cf)
  local st = GetOrCreateChatState(cf)
  local delay = NS.SafeNumber(core:Get("hoverFadeDelay"), 30)

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
    if not CanUseObject(hotspot) then return end

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
      Invoke(hotspot, "ClearAllPoints")
      Invoke(hotspot, "SetAllPoints", cf)
      return
    end

    local padding = NS.Clamp(NS.SafeNumber(core:Get("hotspotPadding"), 10), 0, 24)
    Invoke(hotspot, "ClearAllPoints")
    Invoke(hotspot, "SetPoint", "BOTTOMLEFT", UIParent, "BOTTOMLEFT", minLeft - padding, minBottom - padding)
    Invoke(hotspot, "SetPoint", "TOPRIGHT", UIParent, "BOTTOMLEFT", maxRight + padding, maxTop + padding)
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
  local shownAlpha = NS.SafeNumber(core:Get("hoverAlphaShown"), 1)
  local hiddenAlpha = NS.SafeNumber(core:Get("hoverAlphaHidden"), 0)
  local duration = visible
    and (NS.SafeNumber(core:Get("hoverFadeInDuration"))
      or NS.SafeNumber(core:Get("hoverFadeDuration"), 0.14))
    or (NS.SafeNumber(core:Get("hoverFadeOutDuration"))
      or NS.SafeNumber(core:Get("hoverFadeDuration"), 0.35))
  local target = visible and shownAlpha or hiddenAlpha

  for _, frame in ipairs(st.frames) do
    if CanUseObject(frame) then
      if NS.CanAccessValue(frame.__rothKeepMouseEnabled) and frame.__rothKeepMouseEnabled then
        SetOwnedAlpha(frame, 1, 0)
        SetOwnedMouse(frame, true)
      else
        SetOwnedAlpha(frame, target, duration)
        SetOwnedMouse(frame, visible)
      end
    end
  end

  if CanUseObject(st.button) then
    local buttonTarget = visible and 1 or 0
    NS.FadeTo(st.button, buttonTarget, duration, nil, M)
    Invoke(st.button, "EnableMouse", buttonTarget > 0)
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
      Invoke(st.hotspot, "Hide")
      Invoke(st.hotspot, "EnableMouse", false)
    end
    if CanUseObject(st.button) then Invoke(st.button, "EnableMouse", false) end
    return
  end

  if st.copyOverlayVisible then
    st.hovering = false
    SetControlsVisible(core, cf, false)
    if CanUseObject(st.hotspot) then
      Invoke(st.hotspot, "Hide")
      Invoke(st.hotspot, "EnableMouse", false)
    end
    if CanUseObject(st.button) then Invoke(st.button, "EnableMouse", false) end

    if st.lastVisible ~= false or st.lastPinned ~= st.pinned or st.lastHovering ~= st.hovering then
      st.lastVisible = false
      st.lastPinned = st.pinned
      st.lastHovering = st.hovering
      core:Emit("CONTROLS_VISIBILITY", cf, false, st.pinned, st.hovering)
    end
    return
  end

  if CanUseObject(st.hotspot) then Invoke(st.hotspot, "Show") end

  local visible = ShouldShow(core, cf)
  SetControlsVisible(core, cf, visible)

  local active = st.pinned or st.hovering
  if CanUseObject(st.hotspot) then Invoke(st.hotspot, "EnableMouse", not active) end

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
  if not CanUseObject(cf) or cf.__rothControlsHooked ~= nil then return end

  local enterOK = Invoke(cf, "HookScript", "OnEnter", function()
    if not ControlsEnabled() then return end
    GetOrCreateChatState(cf).hovering = true
    UpdateForChat(core, cf)
  end)
  local leaveOK = Invoke(cf, "HookScript", "OnLeave", function()
    if ControlsEnabled() then ScheduleHoverRecalc(core, cf) end
  end)
  cf.__rothControlsHooked = enterOK and leaveOK
end

local function outCubic(t, b, c, d)
  t = t / d - 1
  return c * (t ^ 3 + 1) + b
end

local function GetFontSize(frame)
  local method = GetMethod(frame, "GetFont")
  if not method then return nil end
  local ok, _, size = pcall(method, frame)
  if not ok or not NS.CanAccessValue(size) then return nil end
  return NS.SafeNumber(size)
end

local function ResetSmoothScroll(cf, restoreContainer)
  if not CanUseObject(cf) then return end
  local scrollFrame = GetField(cf, "__rothSmoothScroll")
  if CanUseObject(scrollFrame) then
    scrollFrame.offset = 0
    scrollFrame.startOffset = 0
    scrollFrame.startTime = 0
    Invoke(scrollFrame, "Hide")
  end

  local container = restoreContainer == false and nil or GetField(cf, "FontStringContainer")
  if CanUseObject(container) then
    Invoke(container, "ClearAllPoints")
    Invoke(container, "SetPoint", "TOPLEFT", cf, "TOPLEFT", 0, 0)
    Invoke(container, "SetPoint", "BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
  end
end

local function HandleMouseWheel(core, self, delta)
  delta = NS.SafeNumber(delta)
  if not delta then return end

  if not ControlsEnabled() then
    local snapshot = wheelSnapshots[self]
    local original = snapshot and snapshot.script
    if type(original) == "function" then pcall(original, self, delta) end
    return
  end

  if IsShiftKeyDown() then
    ResetSmoothScroll(self)
    Invoke(self, delta > 0 and "ScrollToTop" or "ScrollToBottom")
    return
  end

  local lines = 3
  if not core:Get("smoothScrollEnabled") then
    ResetSmoothScroll(self)
    local method = delta > 0 and "ScrollUp" or "ScrollDown"
    for _ = 1, lines do Invoke(self, method) end
    return
  end

  local fontSize = GetFontSize(self) or 12
  local distance = fontSize + (NS.SafeNumber(CallOne(self, "GetSpacing"), 0))
  if distance <= 0 then return end

  local scrollFrame = GetField(self, "__rothSmoothScroll")
  if not CanUseObject(scrollFrame) then return end
  scrollFrame.duration = math.max(0.01, NS.SafeNumber(core:Get("smoothScrollDuration"), 0.25))

  local before = NS.SafeNumber(CallOne(self, "GetScrollOffset"))
  if before == nil then return end
  local method = delta > 0 and "ScrollUp" or "ScrollDown"
  for _ = 1, lines do Invoke(self, method) end
  local after = NS.SafeNumber(CallOne(self, "GetScrollOffset"))
  if after == nil then return end

  local difference = delta > 0 and (after - before) or (before - after)
  if difference <= 0 then return end
  scrollFrame.offset = scrollFrame.offset + (delta > 0 and 1 or -1) * distance * difference
  scrollFrame.offset = NS.Clamp(scrollFrame.offset, -distance * 6, distance * 6)
  scrollFrame.startOffset = scrollFrame.offset
  scrollFrame.startTime = NS.SafeNumber(GetTime(), 0)
  Invoke(scrollFrame, "Show")
end

local function HookScroll(core, cf)
  if not CanUseObject(cf) then return end
  CaptureWheelOwnership(cf)
  if not wheelSnapshots[cf] then return end

  if not cf.__rothScrollHooked then
    cf.__rothScrollHooked = true

    local scrollFrame = CreateFrame("Frame", nil, cf)
    cf.__rothSmoothScroll = scrollFrame
    scrollFrame.offset = 0
    scrollFrame.startOffset = 0
    scrollFrame.startTime = 0
    scrollFrame.duration = NS.SafeNumber(core:Get("smoothScrollDuration"), 0.25)
    scrollFrame:Hide()

    scrollFrame:SetScript("OnUpdate", function(frame)
      if not controlsActive then
        frame:Hide()
        return
      end

      local container = GetField(cf, "FontStringContainer")
      if not CanUseObject(container) then
        frame:Hide()
        return
      end

      local now = NS.SafeNumber(GetTime())
      local duration = math.max(0.01, NS.SafeNumber(frame.duration, 0.25))
      local startTime = NS.SafeNumber(frame.startTime, now)
      if not now or not startTime then
        frame:Hide()
        return
      end
      local elapsed = now - startTime

      if elapsed >= duration then
        ResetSmoothScroll(cf)
      else
        frame.offset = outCubic(elapsed, frame.startOffset, -frame.startOffset, duration)
        Invoke(container, "ClearAllPoints")
        Invoke(container, "SetPoint", "TOPLEFT", cf, "TOPLEFT", 0, frame.offset)
        Invoke(container, "SetPoint", "BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, frame.offset)
      end
    end)

    cf.__rothMouseWheelHandler = function(self, delta)
      HandleMouseWheel(core, self, delta)
    end
  end

  Invoke(cf, "EnableMouseWheel", true)
  Invoke(cf, "SetClipsChildren", true)

  local current = CallOne(cf, "GetScript", "OnMouseWheel")
  if current ~= cf.__rothMouseWheelHandler then
    -- If another owner replaced the handler while Controls was active, keep
    -- that current script as the delegate and restore target on disable.
    local snapshot = wheelSnapshots[cf]
    if snapshot and cf.__rothScrollHandlerInstalled then snapshot.script = current end
    if Invoke(cf, "SetScript", "OnMouseWheel", cf.__rothMouseWheelHandler) then
      cf.__rothScrollHandlerInstalled = true
    end
  end
end

local function OnSmoothScrollAddMessage(chatFrame)
  if not controlsActive or NS.IsChatMessagingRestricted() or not CanUseObject(chatFrame) then return end
  local core = M.core
  if not core or not core:Get("smoothScrollEnabled") or CallOne(chatFrame, "IsVisible") ~= true then return end
  local currentOffset = NS.SafeNumber(CallOne(chatFrame, "GetScrollOffset"))
  if currentOffset == nil or currentOffset ~= 0 then return end

  local scrollFrame = GetField(chatFrame, "__rothSmoothScroll")
  if not CanUseObject(scrollFrame) then return end

  local fontSize = GetFontSize(chatFrame) or 12
  local distance = fontSize + NS.SafeNumber(CallOne(chatFrame, "GetSpacing"), 0)
  if distance <= 0 then return end

  scrollFrame.offset = NS.Clamp(scrollFrame.offset - distance, -distance * 6, 0)
  scrollFrame.startOffset = scrollFrame.offset
  scrollFrame.startTime = NS.SafeNumber(GetTime(), 0)
  Invoke(scrollFrame, "Show")
end

local function HookAccessoryHover(core, frame)
  if not CanUseObject(frame) then return end
  frame.__rothHoverChats = frame.__rothHoverChats or {}
  if frame.__rothHoverHooked ~= nil then return end

  local enterOK = Invoke(frame, "HookScript", "OnEnter", function(self)
    if not ControlsEnabled() then return end
    for cf in pairs(self.__rothHoverChats or {}) do
      local st = state.perChat[cf]
      if st then
        st.hovering = true
        UpdateForChat(core, cf)
      end
    end
  end)

  local leaveOK = Invoke(frame, "HookScript", "OnLeave", function(self)
    if not ControlsEnabled() then return end
    for cf in pairs(self.__rothHoverChats or {}) do
      ScheduleHoverRecalc(core, cf)
    end
  end)

  frame.__rothHoverHooked = enterOK and leaveOK
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
  local name = CallOne(cf, "GetName")
  if type(name) ~= "string" or name == "" then return end

  local tab = _G[name .. "Tab"]
  if CanUseObject(tab) then tab.__rothKeepMouseEnabled = true end

  local editBox = _G[name .. "EditBox"]
  local framesToHook = {
    _G[name .. "ButtonFrame"],
    tab,
    editBox,
    GetField(cf, "ScrollToBottomButton"),
    GetField(cf, "DownButton"),
  }

  for _, frame in ipairs(framesToHook) do
    if CanUseObject(frame) then RegisterHoverFrame(core, cf, frame) end
  end

  if CanUseObject(editBox) and editBox.__rothFocusHooked == nil then
    local gained = Invoke(editBox, "HookScript", "OnEditFocusGained", function()
      if not ControlsEnabled() then return end
      st.hovering = true
      UpdateForChat(core, cf)
    end)
    local lost = Invoke(editBox, "HookScript", "OnEditFocusLost", function()
      if ControlsEnabled() then ScheduleHoverRecalc(core, cf) end
    end)
    editBox.__rothFocusHooked = gained and lost
  end

  RequestHotspotBoundsUpdate(core, cf)
end

local function UpdateHoverState(core, cf)
  if not CanUseObject(cf) then return end
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
    pcall(hooksecurefunc, "FCF_FadeInChatFrame", function(cf)
      if ControlsEnabled() and core:Get("immersionEnabled") then UpdateHoverState(core, cf) end
    end)
  end

  if type(_G.FCF_FadeOutChatFrame) == "function" then
    pcall(hooksecurefunc, "FCF_FadeOutChatFrame", function(cf)
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
  local name = CallOne(frame, "GetName")
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

    local isTemporary = GetField(chatFrame, "isTemporary")
    if reason == "set_temporary_window_type" and isTemporary == true then
      ResetTransientState(GetOrCreateChatState(chatFrame))
    end

    EnsureChatFrameHandled(core2, chatFrame)
    UpdateForChat(core2, chatFrame)
  end, M)

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if ControlsEnabled() then QueueRefreshAllChats(core2) end
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if not ControlsEnabled() or not CanUseObject(chatFrame) then return end
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
    if not CanUseObject(chatFrame) then return end
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
        Invoke(st.button, "EnableMouse", false)
        Invoke(st.button, "SetAlpha", 0)
      end
      if CanUseObject(st.hotspot) then
        Invoke(st.hotspot, "EnableMouse", false)
        Invoke(st.hotspot, "Hide")
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
