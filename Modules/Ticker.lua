-- RothChat - Ticker
-- Responsibilities:
--   * Own immersion alpha for one active permanent primary chat frame only.
--   * Show only messages that arrived while that chat was hidden.
--   * Keep animation, queue, and frame ownership bounded across toggles.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Ticker",
  defaultEnabled = true,
  description = "Immersion: hide chat when idle and show hidden-state messages in a ticker.",
}

local QUEUE_MAX = 100
local tickers = setmetatable({}, { __mode = "k" })
local messageQueue = setmetatable({}, { __mode = "k" })
local frameSnapshots = setmetatable({}, { __mode = "k" })
local refreshKey = {}

local function GetFrameIndex(frame)
  return NS.GetChatFrameIndex and NS.GetChatFrameIndex(frame) or nil
end

local function IsPermanentActiveFrame(frame)
  if not frame or frame.isTemporary then return false end
  return not NS.IsActiveChatFrame or NS.IsActiveChatFrame(frame)
end

local function ResolvePrimaryChatFrame(core)
  local configuredIndex = tonumber(core:Get("primaryChatIndex")) or 1
  local configured = _G["ChatFrame" .. configuredIndex]
  if IsPermanentActiveFrame(configured) then return configured end

  local candidates = {
    NS.GetSelectedDockChatFrame and NS.GetSelectedDockChatFrame() or nil,
    _G.ChatFrame1,
  }
  for _, frame in ipairs(NS.GetActiveChatFrames and NS.GetActiveChatFrames() or {}) do
    candidates[#candidates + 1] = frame
  end

  for _, frame in ipairs(candidates) do
    if IsPermanentActiveFrame(frame) then
      local index = GetFrameIndex(frame)
      if index and index ~= configuredIndex and type(core.Set) == "function" then
        core:Set("primaryChatIndex", index)
      end
      return frame
    end
  end
  return nil
end

local function IsChatFrameActiveTab(frame)
  if not IsPermanentActiveFrame(frame) then return false end
  if NS.IsDockedChatFrame and NS.IsDockedChatFrame(frame) then
    local selected = NS.GetSelectedDockChatFrame and NS.GetSelectedDockChatFrame()
    if selected and selected ~= frame then return false end
  end
  return type(frame.IsShown) ~= "function" or frame:IsShown() == true
end

local function EnsureQueue(frame)
  local queue = messageQueue[frame]
  if not queue then
    queue = { first = 1, last = 0 }
    messageQueue[frame] = queue
  end
  return queue
end

local function QueueSize(queue)
  if not queue or queue.first > queue.last then return 0 end
  return queue.last - queue.first + 1
end

local function QueuePush(frame, line, r, g, b)
  local queue = EnsureQueue(frame)
  while QueueSize(queue) >= QUEUE_MAX do
    queue[queue.first] = nil
    queue.first = queue.first + 1
  end
  queue.last = queue.last + 1
  queue[queue.last] = { line, r, g, b }
end

local function QueuePop(frame)
  local queue = messageQueue[frame]
  if not queue or queue.first > queue.last then return nil end

  local item = queue[queue.first]
  queue[queue.first] = nil
  queue.first = queue.first + 1
  if queue.first > queue.last then
    queue.first = 1
    queue.last = 0
  end
  return item
end

local function QueueIsEmpty(queue)
  return not queue or queue.first > queue.last
end

local function ClearQueue(frame)
  messageQueue[frame] = { first = 1, last = 0 }
end

local function ResetTextAnchors(tickerFrame)
  if not tickerFrame or not tickerFrame.text then return end
  tickerFrame.text:ClearAllPoints()
  tickerFrame.text:SetPoint("LEFT", tickerFrame, "LEFT", 10, 0)
  tickerFrame.text:SetPoint("RIGHT", tickerFrame, "RIGHT", -10, 0)
end

local function StopTickerUpdate(tickerFrame)
  if tickerFrame and type(tickerFrame.SetScript) == "function" then
    tickerFrame:SetScript("OnUpdate", nil)
  end
end

local function StartTickerUpdate(tickerFrame)
  if tickerFrame and tickerFrame.__rothOnUpdate and type(tickerFrame.SetScript) == "function" then
    tickerFrame:SetScript("OnUpdate", tickerFrame.__rothOnUpdate)
  end
end

local function CancelHold(tickerFrame)
  if not tickerFrame then return end
  tickerFrame.holding = false
  if tickerFrame.__holdScheduleKey then NS.CancelScheduled(tickerFrame.__holdScheduleKey) end
end

local function ResetTickerRuntime(tickerFrame, hide)
  if not tickerFrame then return end
  CancelHold(tickerFrame)
  NS.StopFading(tickerFrame)
  StopTickerUpdate(tickerFrame)
  tickerFrame.idleFading = false
  tickerFrame.isAnimating = false
  tickerFrame._fadeYShift = false
  tickerFrame._fadeTimer = 0
  tickerFrame.timer = 0
  tickerFrame.charIndex = 0
  tickerFrame.fullCharLen = 0
  ResetTextAnchors(tickerFrame)
  if hide then tickerFrame:Hide() end
end

local function GetMouseEnabled(frame)
  if frame and type(frame.IsMouseEnabled) == "function" then
    local ok, enabled = pcall(frame.IsMouseEnabled, frame)
    if ok then return enabled and true or false end
  end
  return nil
end

local function CaptureFrameOwnership(frame)
  if not frame or frameSnapshots[frame] then return end
  frameSnapshots[frame] = {
    alpha = type(frame.GetAlpha) == "function" and frame:GetAlpha() or 1,
    mouseEnabled = GetMouseEnabled(frame),
  }
end

local function RestoreFrameOwnership(frame)
  local snapshot = frame and frameSnapshots[frame]
  if not snapshot then return end

  NS.StopFading(frame)
  if type(frame.SetAlpha) == "function" and type(snapshot.alpha) == "number" then
    frame:SetAlpha(snapshot.alpha)
  end
  if type(frame.EnableMouse) == "function" and snapshot.mouseEnabled ~= nil then
    frame:EnableMouse(snapshot.mouseEnabled)
  end
  frame.__rothMouseForcedOff = nil
  frameSnapshots[frame] = nil
end

local function ApplyTickerTextStyle(core, tickerFrame)
  if not tickerFrame or not tickerFrame.text then return end

  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local font = core:Get("styleFont") or (LSM and LSM:Fetch("font", "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
  local size = core:Get("styleFontSize") or 12
  local outline = core:Get("styleFontOutline") or ""

  tickerFrame.text:SetFont(font, size, outline)
  if core:Get("styleShadow") then
    tickerFrame.text:SetShadowColor(0, 0, 0, 0.7)
    tickerFrame.text:SetShadowOffset(1, -1)
  else
    tickerFrame.text:SetShadowColor(0, 0, 0, 0)
    tickerFrame.text:SetShadowOffset(0, 0)
  end
end

local function ScheduleNextProcess(core, frame, delay)
  local tickerFrame = tickers[frame]
  if not tickerFrame then return end

  tickerFrame.__holdScheduleKey = tickerFrame.__holdScheduleKey or {}
  tickerFrame.holding = true
  NS.Schedule(tickerFrame.__holdScheduleKey, delay, function()
    tickerFrame.holding = false
    if M.core == core and core:IsModuleActive("Ticker") and M._feedTarget == frame then
      M:ProcessQueue(core, frame)
    end
  end, "RothChat:TickerHold")
end

local function BuildTicker(core, frame)
  local existing = tickers[frame]
  if existing then return existing end

  local tickerFrame = CreateFrame("Frame", nil, UIParent)
  tickerFrame:SetFrameStrata("LOW")
  tickerFrame:SetFrameLevel(20)
  tickerFrame:EnableMouse(false)

  local text = tickerFrame:CreateFontString(nil, "ARTWORK")
  text:SetPoint("LEFT", tickerFrame, "LEFT", 10, 0)
  text:SetPoint("RIGHT", tickerFrame, "RIGHT", -10, 0)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("MIDDLE")
  text:SetWordWrap(true)
  tickerFrame.text = text

  tickerFrame.controlsActive = false
  tickerFrame.controlsVisible = false
  tickerFrame.copyOverlayVisible = false
  tickerFrame.isAnimating = false
  tickerFrame.holding = false
  tickerFrame.idleFading = false
  tickerFrame.animMode = "fade"
  tickerFrame.fullText = ""
  tickerFrame.fullCharLen = 0
  tickerFrame.charIndex = 0
  tickerFrame.timer = 0

  tickerFrame.__rothOnUpdate = function(self, elapsed)
    if not self.isAnimating then
      StopTickerUpdate(self)
      return
    end

    local mode = self.animMode
    if mode == "typewriter" then
      self.timer = self.timer + elapsed
      local speed = math.max(1, tonumber(core:Get("tickerSpeed")) or 30)
      local interval = 1 / speed
      local charsToAdd = math.floor(self.timer / interval)
      if charsToAdd >= 1 then
        self.timer = self.timer - charsToAdd * interval
        self.charIndex = math.min(self.fullCharLen, self.charIndex + charsToAdd)
        if self.charIndex >= self.fullCharLen then
          self.text:SetText(self.fullText)
          self.isAnimating = false
          StopTickerUpdate(self)
          ScheduleNextProcess(core, frame, 2.0)
          return
        end
        self.text:SetText(NS.Utf8Sub(self.fullText, self.charIndex) .. "_")
      end

    elseif mode == "slide" then
      self.timer = self.timer + elapsed
      local duration = 0.2
      local progress = math.min(self.timer / duration, 1)
      local normalized = progress - 1
      local eased = normalized ^ 3 + 1
      local yOffset = -20 * (1 - eased)
      self:ClearAllPoints()
      self:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, yOffset)
      self:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, yOffset)
      if progress >= 1 then
        self.isAnimating = false
        StopTickerUpdate(self)
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        self:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        ScheduleNextProcess(core, frame, 2.0)
      end

    elseif mode == "marquee" then
      self.timer = self.timer + elapsed
      local speed = math.max(1, tonumber(core:Get("tickerSpeed")) or 30)
      local textWidth = self.text:GetStringWidth() or 100
      local frameWidth = self:GetWidth() or 300
      local totalTravel = frameWidth + textWidth
      local pixelSpeed = speed * 4 + math.max(0, (textWidth - frameWidth) * 0.5)
      local offset = self.timer * pixelSpeed
      if offset >= totalTravel then
        ResetTextAnchors(self)
        self.isAnimating = false
        StopTickerUpdate(self)
        ScheduleNextProcess(core, frame, 1.0)
        return
      end
      self.text:ClearAllPoints()
      self.text:SetPoint("LEFT", self, "RIGHT", -offset, 0)

    elseif mode == "fade" and self._fadeYShift then
      self._fadeTimer = (self._fadeTimer or 0) + elapsed
      local progress = math.min(self._fadeTimer / 0.2, 1)
      local yOffset = -2 * (1 - progress)
      self.text:ClearAllPoints()
      self.text:SetPoint("LEFT", self, "LEFT", 10, yOffset)
      self.text:SetPoint("RIGHT", self, "RIGHT", -10, yOffset)
      if progress >= 1 then
        self._fadeYShift = false
        if not self.isAnimating then StopTickerUpdate(self) end
      end
    else
      StopTickerUpdate(self)
    end
  end

  tickerFrame:Hide()
  tickers[frame] = tickerFrame
  ApplyTickerTextStyle(core, tickerFrame)
  return tickerFrame
end

local function LayoutTicker(frame)
  local tickerFrame = tickers[frame]
  if not tickerFrame then return end
  tickerFrame:ClearAllPoints()
  tickerFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  tickerFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  tickerFrame:SetHeight(22)
end

local function SetOwnedChatAlpha(core, frame, active)
  if not frame then return end
  CaptureFrameOwnership(frame)

  local shown = tonumber(core:Get("immersionChatAlphaShown")) or 1.0
  local hidden = tonumber(core:Get("immersionChatAlphaHidden")) or 0.0
  local target = NS.Clamp(active and shown or hidden, 0, 1)
  local duration = active
    and (tonumber(core:Get("immersionFadeInDuration")) or tonumber(core:Get("immersionFadeDuration")) or 0.15)
    or (tonumber(core:Get("immersionFadeOutDuration")) or tonumber(core:Get("immersionFadeDuration")) or 0.35)

  NS.FadeTo(frame, target, duration)
  local snapshot = frameSnapshots[frame]
  if type(frame.EnableMouse) == "function" then
    if target <= 0.01 then
      frame.__rothMouseForcedOff = true
      frame:EnableMouse(false)
    elseif snapshot and snapshot.mouseEnabled ~= nil then
      frame:EnableMouse(snapshot.mouseEnabled)
      frame.__rothMouseForcedOff = nil
    end
  end
end

local function FeatureCanOwnFrame(core, frame)
  return frame
    and M._feedTarget == frame
    and core:IsModuleActive("Controls")
    and core:Get("immersionEnabled")
    and core:Get("tickerEnabled")
end

local function UpdateVisibility(core, frame, active)
  local tickerFrame = tickers[frame]
  if not tickerFrame then return end

  if not FeatureCanOwnFrame(core, frame) then
    tickerFrame.controlsVisible = true
    ResetTickerRuntime(tickerFrame, true)
    ClearQueue(frame)
    RestoreFrameOwnership(frame)
    return
  end

  tickerFrame.controlsVisible = active and true or false
  if active then
    ResetTickerRuntime(tickerFrame, true)
    ClearQueue(frame)
    SetOwnedChatAlpha(core, frame, true)
    if frame.ScrollToBottom then pcall(frame.ScrollToBottom, frame) end
  else
    -- Start each hidden interval from an empty queue. Only subsequent incoming
    -- messages are eligible for ticker playback.
    ClearQueue(frame)
    ResetTickerRuntime(tickerFrame, true)
    LayoutTicker(frame)
    SetOwnedChatAlpha(core, frame, false)
  end
end

function M:ProcessQueue(core, frame)
  local tickerFrame = tickers[frame]
  if not tickerFrame or M._feedTarget ~= frame
    or tickerFrame.controlsVisible or tickerFrame.copyOverlayVisible
    or tickerFrame.isAnimating or tickerFrame.holding
  then
    return
  end

  local queue = messageQueue[frame]
  if QueueIsEmpty(queue) then
    tickerFrame.text:SetText(tickerFrame.fullText)
    ResetTextAnchors(tickerFrame)
    tickerFrame.idleFading = true
    NS.FadeTo(tickerFrame, 0, 0.5, function()
      tickerFrame.idleFading = false
      if M._feedTarget == frame
        and not tickerFrame.controlsVisible
        and not tickerFrame.copyOverlayVisible
        and not tickerFrame.isAnimating
        and QueueIsEmpty(messageQueue[frame])
      then
        tickerFrame:Hide()
      end
    end)
    return
  end

  NS.StopFading(tickerFrame)
  tickerFrame.idleFading = false

  local messageData = QueuePop(frame)
  if not messageData then return end
  local line = messageData[1]
  local r, g, b = messageData[2], messageData[3], messageData[4]

  tickerFrame.charIndex = 0
  tickerFrame.timer = 0
  tickerFrame._fadeYShift = false
  tickerFrame._fadeTimer = 0

  local accessibleColor = (not NS.CanAccessValue)
    or (NS.CanAccessValue(r) and NS.CanAccessValue(g) and NS.CanAccessValue(b))
  if accessibleColor and type(r) == "number" and type(g) == "number" and type(b) == "number" then
    tickerFrame.text:SetTextColor(r, g, b)
  else
    tickerFrame.text:SetTextColor(1, 1, 1)
  end

  local mode = core:Get("tickerAnimation") or "fade"
  tickerFrame.animMode = mode
  if mode == "typewriter" and NS.Utf8Len(line) > 200 then
    line = NS.Utf8Sub(line, 200) .. "..."
  end
  tickerFrame.fullText = line
  tickerFrame.fullCharLen = NS.Utf8Len(line)

  if mode == "fade" then
    local function ShowNewFadeMessage()
      if M._feedTarget ~= frame or tickerFrame.controlsVisible or tickerFrame.copyOverlayVisible then
        tickerFrame.isAnimating = false
        StopTickerUpdate(tickerFrame)
        return
      end

      tickerFrame.text:SetText(line)
      ResetTextAnchors(tickerFrame)
      tickerFrame.text:SetPoint("LEFT", tickerFrame, "LEFT", 10, -2)
      tickerFrame.text:SetPoint("RIGHT", tickerFrame, "RIGHT", -10, -2)
      tickerFrame:SetAlpha(0)
      tickerFrame:Show()
      tickerFrame.isAnimating = true
      tickerFrame._fadeYShift = true
      tickerFrame._fadeTimer = 0
      StartTickerUpdate(tickerFrame)

      NS.FadeTo(tickerFrame, 1, 0.2, function()
        ResetTextAnchors(tickerFrame)
        tickerFrame.isAnimating = false
        tickerFrame._fadeYShift = false
        StopTickerUpdate(tickerFrame)
        if M._feedTarget == frame and not tickerFrame.controlsVisible and not tickerFrame.copyOverlayVisible then
          ScheduleNextProcess(core, frame, 2.0)
        end
      end)
    end

    if tickerFrame:IsShown() and tickerFrame:GetAlpha() > 0.01 then
      tickerFrame.isAnimating = true
      NS.FadeTo(tickerFrame, 0, 0.12, function()
        tickerFrame.isAnimating = false
        ShowNewFadeMessage()
      end)
    else
      ShowNewFadeMessage()
    end

  elseif mode == "typewriter" then
    tickerFrame.text:SetText("")
    ResetTextAnchors(tickerFrame)
    tickerFrame.isAnimating = true
    tickerFrame:Show()
    tickerFrame:SetAlpha(1)
    StartTickerUpdate(tickerFrame)

  elseif mode == "slide" then
    tickerFrame.text:SetText(line)
    ResetTextAnchors(tickerFrame)
    tickerFrame.isAnimating = true
    tickerFrame:Show()
    tickerFrame:SetAlpha(1)
    StartTickerUpdate(tickerFrame)

  elseif mode == "marquee" then
    tickerFrame.text:SetText(line)
    tickerFrame.text:ClearAllPoints()
    tickerFrame.text:SetPoint("LEFT", tickerFrame, "RIGHT", 0, 0)
    tickerFrame.isAnimating = true
    tickerFrame:Show()
    tickerFrame:SetAlpha(1)
    StartTickerUpdate(tickerFrame)

  else
    tickerFrame.text:SetText(line)
    ResetTextAnchors(tickerFrame)
    tickerFrame:Show()
    tickerFrame:SetAlpha(1)
    tickerFrame.isAnimating = false
    ScheduleNextProcess(core, frame, 2.0)
  end
end

local function QueueLine(core, frame, line, r, g, b)
  if not FeatureCanOwnFrame(core, frame) then return end
  if NS.CanAccessValue and not NS.CanAccessValue(line) then return end
  if not IsChatFrameActiveTab(frame) then return end

  local tickerFrame = tickers[frame]
  if not tickerFrame or tickerFrame.controlsVisible or tickerFrame.copyOverlayVisible then return end

  local safeLine = NS.SafeToString(line)
  if safeLine == "" then return end
  QueuePush(frame, safeLine, r, g, b)

  if not tickerFrame.isAnimating and not tickerFrame.holding then
    NS.StopFading(tickerFrame)
    tickerFrame.idleFading = false
    M:ProcessQueue(core, frame)
  end
end

local function OnAddMessage(frame, text, r, g, b)
  if not M._loggedIn or not M.core or not M.core:IsModuleActive("Ticker") then return end
  if M._feedTarget ~= frame then return end
  QueueLine(M.core, frame, text, r, g, b)
end

local function CleanupFeedTarget(frame)
  if not frame then return end
  local tickerFrame = tickers[frame]
  if tickerFrame then
    tickerFrame.controlsActive = true
    tickerFrame.controlsVisible = true
    tickerFrame.copyOverlayVisible = false
    ResetTickerRuntime(tickerFrame, true)
  end
  ClearQueue(frame)
  RestoreFrameOwnership(frame)
end

local function QueueRefresh(core)
  NS.RunNextFrame(refreshKey, function()
    if core:IsModuleActive("Ticker") then M:Refresh(core) end
  end, "RothChat:TickerRefresh")
end

local function RegisterTickerListeners(core)
  core:OffOwner(M)

  core:On("CONTROLS_VISIBILITY", function(_, core2, chatFrame, controlsVisible)
    if chatFrame ~= M._feedTarget then return end
    local tickerFrame = tickers[chatFrame]
    if not tickerFrame then return end

    tickerFrame.controlsActive = controlsVisible and true or false
    UpdateVisibility(core2, chatFrame, tickerFrame.controlsActive or tickerFrame.copyOverlayVisible)
  end, M)

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if core2:IsModuleActive("Ticker") then QueueRefresh(core2) end
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if chatFrame == M._feedTarget then QueueRefresh(core2) end
  end, M)

  core:On("COPY_OVERLAY_VISIBILITY", function(_, core2, chatFrame, visible)
    if chatFrame ~= M._feedTarget then return end
    local tickerFrame = tickers[chatFrame]
    if not tickerFrame then return end

    tickerFrame.copyOverlayVisible = visible and true or false
    UpdateVisibility(core2, chatFrame, tickerFrame.copyOverlayVisible or tickerFrame.controlsActive)
  end, M)
end

local function ApplyTickerState(core, refreshListeners)
  core:EnsureChatLifecycleHooks()
  local primaryFrame = ResolvePrimaryChatFrame(core)
  if refreshListeners then RegisterTickerListeners(core) end

  if M._feedTarget ~= primaryFrame then
    core:UnregisterAddMessageHooks(M)
    CleanupFeedTarget(M._feedTarget)
    M._feedTarget = nil
  end

  if not primaryFrame then return end

  local tickerFrame = BuildTicker(core, primaryFrame)
  LayoutTicker(primaryFrame)
  EnsureQueue(primaryFrame)
  ApplyTickerTextStyle(core, tickerFrame)

  M._feedTarget = primaryFrame
  core:RegisterAddMessageHook(OnAddMessage, M, 30)

  -- Controls has already completed its initial pass before Ticker loads. Start
  -- in the idle state; the next Controls visibility event becomes authoritative.
  if FeatureCanOwnFrame(core, primaryFrame) then
    UpdateVisibility(core, primaryFrame, tickerFrame.controlsActive or tickerFrame.copyOverlayVisible)
  else
    UpdateVisibility(core, primaryFrame, true)
  end
end

function M:Init(core)
  self.core = core
  self._loggedIn = false
  return true
end

function M:OnEnable(core)
  local function Apply() ApplyTickerState(core, true) end
  if InCombatLockdown() then
    core:Defer(function()
      if core:IsModuleActive("Ticker") then Apply() end
    end)
  else
    Apply()
  end
end

function M:OnLogin(core)
  self._loggedIn = true
end

function M:OnDisable(core)
  NS.CancelScheduled(refreshKey)
  core:UnregisterAddMessageHooks(self)
  CleanupFeedTarget(self._feedTarget)
  self._feedTarget = nil

  for frame, tickerFrame in pairs(tickers) do
    if tickerFrame then ResetTickerRuntime(tickerFrame, true) end
    ClearQueue(frame)
    RestoreFrameOwnership(frame)
  end
end

function M:Refresh(core)
  if not core:IsModuleActive("Ticker") then return end
  ApplyTickerState(core, false)
end

RothChat:RegisterModule(M)
