-- RothChat - Ticker
-- Responsibilities:
--   * Hide the configured primary chat frame when idle.
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
local tickers = {}
local messageQueue = {} -- [chatFrame] = { first=n, last=n, [n]={line,r,g,b} }

local function GetPrimaryChatFrame(core)
  local idx = tonumber(core:Get("primaryChatIndex")) or 1
  return _G["ChatFrame" .. idx] or _G.ChatFrame1
end

local function ShouldApplyImmersionToFrame(core, cf)
  if not cf then return false end
  local primary = GetPrimaryChatFrame(core)
  return primary and cf == primary or false
end

local function IsChatFrameActiveTab(cf)
  if not cf then return false end
  local selected = _G.SELECTED_CHAT_FRAME
  if selected and selected ~= cf then
    return false
  end
  return cf:IsShown() == true
end

local function EnsureQueue(cf)
  local q = messageQueue[cf]
  if not q then
    q = { first = 1, last = 0 }
    messageQueue[cf] = q
  end
  return q
end

local function QueueSize(q)
  if not q or q.first > q.last then return 0 end
  return q.last - q.first + 1
end

local function QueuePush(cf, line, r, g, b)
  local q = EnsureQueue(cf)
  while QueueSize(q) >= QUEUE_MAX do
    q[q.first] = nil
    q.first = q.first + 1
  end

  q.last = q.last + 1
  q[q.last] = { line, r, g, b }
  return q
end

local function QueuePop(cf)
  local q = messageQueue[cf]
  if not q or q.first > q.last then
    return nil
  end

  local item = q[q.first]
  q[q.first] = nil
  q.first = q.first + 1

  if q.first > q.last then
    q.first = 1
    q.last = 0
  end

  return item
end

local function QueueIsEmpty(q)
  return not q or q.first > q.last
end

local function ClearQueue(cf)
  messageQueue[cf] = { first = 1, last = 0 }
end

local function ResetTextAnchors(tickerFrame)
  if not tickerFrame or not tickerFrame.text then return end
  tickerFrame.text:ClearAllPoints()
  tickerFrame.text:SetPoint("LEFT", tickerFrame, "LEFT", 10, 0)
  tickerFrame.text:SetPoint("RIGHT", tickerFrame, "RIGHT", -10, 0)
end

local function CancelHold(tickerFrame)
  if not tickerFrame then return end
  tickerFrame.holding = false
  if tickerFrame.__holdScheduleKey then
    NS.CancelScheduled(tickerFrame.__holdScheduleKey)
  end
end

local function ResetTickerRuntime(tickerFrame, hide)
  if not tickerFrame then return end
  CancelHold(tickerFrame)
  NS.StopFading(tickerFrame)
  tickerFrame.idleFading = false
  tickerFrame.isAnimating = false
  tickerFrame._fadeYShift = false
  tickerFrame._fadeTimer = 0
  tickerFrame.timer = 0
  tickerFrame.charIndex = 0
  tickerFrame.fullCharLen = 0
  ResetTextAnchors(tickerFrame)
  if hide then
    tickerFrame:Hide()
  end
end

local function ScheduleNextProcess(core, cf, delay)
  local tickerFrame = tickers[cf]
  if not tickerFrame then return end

  tickerFrame.__holdScheduleKey = tickerFrame.__holdScheduleKey or {}
  tickerFrame.holding = true
  NS.Schedule(tickerFrame.__holdScheduleKey, delay, function()
    tickerFrame.holding = false
    if M.core == core and core:IsModuleActive("Ticker") then
      M:ProcessQueue(core, cf)
    end
  end, "RothChat:TickerHold")
end

local function QueueLine(core, cf, line, r, g, b)
  if not core:Get("tickerEnabled") then return end
  if not core:IsModuleActive("Controls") then return end
  if NS.CanAccessValue and not NS.CanAccessValue(line) then return end
  if not IsChatFrameActiveTab(cf) then return end

  local tickerFrame = tickers[cf]
  -- Visible-chat messages have already been read in the normal chat surface and
  -- must never be replayed later when immersion hides the frame.
  if not tickerFrame or tickerFrame.controlsVisible or tickerFrame.copyOverlayVisible then
    return
  end

  local safeLine = NS.SafeToString(line)
  if safeLine == "" then return end

  QueuePush(cf, safeLine, r, g, b)

  if not tickerFrame.isAnimating and not tickerFrame.holding then
    NS.StopFading(tickerFrame)
    tickerFrame.idleFading = false
    M:ProcessQueue(core, cf)
  end
end

-- Unified AddMessage hook callback (registered via core:RegisterAddMessageHook).
local function OnAddMessage(frame, text, r, g, b)
  if not M._loggedIn then return end
  if not M.core or not M.core:IsModuleActive("Ticker") then return end
  if M._feedTarget ~= frame then return end
  QueueLine(M.core, frame, text, r, g, b)
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

local function BuildTicker(core, cf)
  if tickers[cf] then return tickers[cf] end

  local t = CreateFrame("Frame", nil, UIParent)
  t:SetFrameStrata("LOW")
  t:SetFrameLevel(20)
  t:EnableMouse(false)

  local fs = t:CreateFontString(nil, "ARTWORK")
  fs:SetPoint("LEFT", t, "LEFT", 10, 0)
  fs:SetPoint("RIGHT", t, "RIGHT", -10, 0)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("MIDDLE")
  fs:SetWordWrap(true)
  t.text = fs
  ApplyTickerTextStyle(core, t)

  t.controlsVisible = true
  t.copyOverlayVisible = false
  t.isAnimating = false
  t.holding = false
  t.idleFading = false
  t.animMode = "fade"
  t.fullText = ""
  t.fullCharLen = 0
  t.charIndex = 0
  t.timer = 0

  t:SetScript("OnUpdate", function(self, elapsed)
    if not self.isAnimating then return end

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
          ScheduleNextProcess(core, cf, 2.0)
          return
        end
        self.text:SetText(NS.Utf8Sub(self.fullText, self.charIndex) .. "_")
      end

    elseif mode == "slide" then
      self.timer = self.timer + elapsed
      local dur = 0.2
      local progress = math.min(self.timer / dur, 1)
      local tNorm = progress - 1
      local eased = tNorm ^ 3 + 1
      local yOff = -20 * (1 - eased)
      self:ClearAllPoints()
      self:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, yOff)
      self:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, yOff)
      if progress >= 1 then
        self.isAnimating = false
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, 0)
        self:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
        ScheduleNextProcess(core, cf, 2.0)
      end

    elseif mode == "marquee" then
      self.timer = self.timer + elapsed
      local speed = math.max(1, tonumber(core:Get("tickerSpeed")) or 30)
      local textW = self.text:GetStringWidth() or 100
      local frameW = self:GetWidth() or 300
      local totalTravel = frameW + textW
      local pixelSpeed = speed * 4 + math.max(0, (textW - frameW) * 0.5)
      local offset = self.timer * pixelSpeed
      if offset >= totalTravel then
        ResetTextAnchors(self)
        self.isAnimating = false
        ScheduleNextProcess(core, cf, 1.0)
        return
      end
      self.text:ClearAllPoints()
      self.text:SetPoint("LEFT", self, "RIGHT", -offset, 0)

    elseif mode == "fade" and self._fadeYShift then
      self._fadeTimer = (self._fadeTimer or 0) + elapsed
      local progress = math.min(self._fadeTimer / 0.2, 1)
      local yOff = -2 * (1 - progress)
      self.text:ClearAllPoints()
      self.text:SetPoint("LEFT", self, "LEFT", 10, yOff)
      self.text:SetPoint("RIGHT", self, "RIGHT", -10, yOff)
      if progress >= 1 then
        self._fadeYShift = false
      end
    end
  end)

  t:Hide()
  tickers[cf] = t
  return t
end

local function LayoutTicker(core, cf)
  local t = tickers[cf]
  if not t then return end
  t:ClearAllPoints()
  t:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, 0)
  t:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
  t:SetHeight(22)
end

function M:ProcessQueue(core, cf)
  local t = tickers[cf]
  if not t or t.controlsVisible or t.copyOverlayVisible or t.isAnimating or t.holding then return end

  local q = messageQueue[cf]
  if QueueIsEmpty(q) then
    t.text:SetText(t.fullText)
    ResetTextAnchors(t)
    t.idleFading = true
    NS.FadeTo(t, 0, 0.5, function()
      t.idleFading = false
      if not t.controlsVisible and not t.copyOverlayVisible and not t.isAnimating and QueueIsEmpty(messageQueue[cf]) then
        t:Hide()
      end
    end)
    return
  end

  NS.StopFading(t)
  t.idleFading = false

  local msgData = QueuePop(cf)
  if not msgData then return end
  local line = msgData[1]
  local r, g, b = msgData[2], msgData[3], msgData[4]

  t.charIndex = 0
  t.timer = 0
  t._fadeYShift = false
  t._fadeTimer = 0

  local accessibleColor = (not NS.CanAccessValue)
    or (NS.CanAccessValue(r) and NS.CanAccessValue(g) and NS.CanAccessValue(b))
  if accessibleColor and type(r) == "number" and type(g) == "number" and type(b) == "number" then
    t.text:SetTextColor(r, g, b)
  else
    t.text:SetTextColor(1, 1, 1)
  end

  local mode = core:Get("tickerAnimation") or "fade"
  t.animMode = mode

  if mode == "typewriter" and NS.Utf8Len(line) > 200 then
    line = NS.Utf8Sub(line, 200) .. "..."
  end
  t.fullText = line
  t.fullCharLen = NS.Utf8Len(line)

  if mode == "fade" then
    local function ShowNewFadeMessage()
      if t.controlsVisible or t.copyOverlayVisible then
        t.isAnimating = false
        return
      end
      t.text:SetText(line)
      ResetTextAnchors(t)
      t.text:SetPoint("LEFT", t, "LEFT", 10, -2)
      t.text:SetPoint("RIGHT", t, "RIGHT", -10, -2)
      t:SetAlpha(0)
      t:Show()
      t.isAnimating = true
      t._fadeYShift = true
      t._fadeTimer = 0
      NS.FadeTo(t, 1, 0.2, function()
        ResetTextAnchors(t)
        t.isAnimating = false
        t._fadeYShift = false
        if not t.controlsVisible and not t.copyOverlayVisible then
          ScheduleNextProcess(core, cf, 2.0)
        end
      end)
    end

    if t:IsShown() and t:GetAlpha() > 0.01 then
      t.isAnimating = true
      NS.FadeTo(t, 0, 0.12, function()
        t.isAnimating = false
        ShowNewFadeMessage()
      end)
    else
      ShowNewFadeMessage()
    end

  elseif mode == "typewriter" then
    t.text:SetText("")
    ResetTextAnchors(t)
    t.isAnimating = true
    t:Show()
    t:SetAlpha(1)

  elseif mode == "slide" then
    t.text:SetText(line)
    ResetTextAnchors(t)
    t.isAnimating = true
    t:Show()
    t:SetAlpha(1)

  elseif mode == "marquee" then
    t.text:SetText(line)
    t.text:ClearAllPoints()
    t.text:SetPoint("LEFT", t, "RIGHT", 0, 0)
    t.isAnimating = true
    t:Show()
    t:SetAlpha(1)

  else
    t.text:SetText(line)
    ResetTextAnchors(t)
    t:Show()
    t:SetAlpha(1)
    t.isAnimating = false
    ScheduleNextProcess(core, cf, 2.0)
  end
end

local function SetChatAlpha(core, cf, active)
  if not cf then return end
  local shown = tonumber(core:Get("immersionChatAlphaShown")) or 1.0
  local hidden = tonumber(core:Get("immersionChatAlphaHidden")) or 0.0
  local target = active and shown or hidden

  local durIn = tonumber(core:Get("immersionFadeInDuration")) or tonumber(core:Get("immersionFadeDuration")) or 0.15
  local durOut = tonumber(core:Get("immersionFadeOutDuration")) or tonumber(core:Get("immersionFadeDuration")) or 0.35
  local dur = active and durIn or durOut
  NS.FadeTo(cf, NS.Clamp(target, 0, 1), dur)

  if target <= 0.01 then
    cf:EnableMouse(false)
    cf.__rothMouseForcedOff = true
  elseif cf.__rothMouseForcedOff then
    cf:EnableMouse(true)
    cf.__rothMouseForcedOff = nil
  end
end

local function ForceNonPrimaryVisible(core)
  local primary = GetPrimaryChatFrame(core)
  for _, cf in ipairs(NS.GetChatFrames()) do
    if cf and cf ~= primary then
      SetChatAlpha(core, cf, true)
    end
  end
end

local function QueueForceNonPrimaryVisible(core)
  NS.RunNextFrame(M, function()
    if not core or not core:IsModuleActive("Ticker") then return end
    ForceNonPrimaryVisible(core)
  end, "RothChat:TickerNonPrimary")
end

local function UpdateVisibility(core, cf, active)
  local t = BuildTicker(core, cf)
  if not t then return end

  if not core:Get("immersionEnabled") or not core:Get("tickerEnabled") then
    t.controlsVisible = true
    ResetTickerRuntime(t, true)
    ClearQueue(cf)
    SetChatAlpha(core, cf, true)
    return
  end

  if active then
    t.controlsVisible = true
    ResetTickerRuntime(t, true)
    ClearQueue(cf)
    SetChatAlpha(core, cf, true)
    if cf.ScrollToBottom then
      pcall(cf.ScrollToBottom, cf)
    end
  else
    -- Start each hidden interval from an empty queue. Only subsequent incoming
    -- messages are eligible for ticker playback.
    ClearQueue(cf)
    ResetTickerRuntime(t, true)
    LayoutTicker(core, cf)
    t.controlsVisible = false
    SetChatAlpha(core, cf, false)
  end
end

function M:Init(core)
  self.core = core
  self._loggedIn = false
  return true
end

local function RegisterTickerListeners(core)
  core:OffOwner(M)

  core:On("CONTROLS_VISIBILITY", function(_, core2, chatFrame, _controlsVisible, pinned, hovering)
    local active
    if core2:IsModuleActive("Controls") then
      active = pinned or hovering
    else
      active = true
    end

    if core2:Get("immersionEnabled") and ShouldApplyImmersionToFrame(core2, chatFrame) then
      UpdateVisibility(core2, chatFrame, active)
    else
      local t = tickers[chatFrame]
      if t then
        t.controlsVisible = true
        ResetTickerRuntime(t, true)
        ClearQueue(chatFrame)
      end
      SetChatAlpha(core2, chatFrame, true)
    end
  end, M)

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if not core2:IsModuleActive("Ticker") then return end
    QueueForceNonPrimaryVisible(core2)
  end, M)

  core:On("COPY_OVERLAY_VISIBILITY", function(_, core2, chatFrame, visible)
    local t = chatFrame and tickers[chatFrame]
    if not t then return end

    t.copyOverlayVisible = visible and true or false
    if visible then
      t.controlsVisible = true
      ResetTickerRuntime(t, true)
      ClearQueue(chatFrame)
    else
      QueueForceNonPrimaryVisible(core2)
    end
  end, M)
end

local function CleanupFeedTarget(core, cf)
  if not cf then return end
  local t = tickers[cf]
  if t then
    t.controlsVisible = true
    t.copyOverlayVisible = false
    ResetTickerRuntime(t, true)
  end
  ClearQueue(cf)
  SetChatAlpha(core, cf, true)
end

local function ApplyTickerState(core, refreshListeners)
  core:EnsureChatLifecycleHooks()

  local primaryCf = GetPrimaryChatFrame(core)
  if refreshListeners then
    RegisterTickerListeners(core)
  end

  if M._feedTarget ~= primaryCf then
    core:UnregisterAddMessageHooks(M)
    CleanupFeedTarget(core, M._feedTarget)
    M._feedTarget = nil
  end

  if primaryCf then
    BuildTicker(core, primaryCf)
    LayoutTicker(core, primaryCf)
    EnsureQueue(primaryCf)
    M._feedTarget = primaryCf
    core:RegisterAddMessageHook(OnAddMessage, M, 30)
  end

  for cf, tickerFrame in pairs(tickers) do
    ApplyTickerTextStyle(core, tickerFrame)
    if cf then LayoutTicker(core, cf) end
  end

  if core:IsModuleActive("Controls") and core:Get("immersionEnabled") and core:Get("tickerEnabled") then
    for _, cf in ipairs(NS.GetChatFrames()) do
      if ShouldApplyImmersionToFrame(core, cf) then
        UpdateVisibility(core, cf, false)
      else
        CleanupFeedTarget(core, cf)
      end
    end
  else
    for _, cf in ipairs(NS.GetChatFrames()) do
      CleanupFeedTarget(core, cf)
    end
  end

  QueueForceNonPrimaryVisible(core)
end

function M:OnEnable(core)
  local function Apply()
    if core:IsModuleActive("Ticker") or not core._loginComplete then
      ApplyTickerState(core, true)
    end
  end

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
  self._feedTarget = nil
  core:UnregisterAddMessageHooks(self)
  for _, cf in ipairs(NS.GetChatFrames()) do
    CleanupFeedTarget(core, cf)
  end
  for chatFrame, t in pairs(tickers) do
    if t then
      t.controlsVisible = true
      t.copyOverlayVisible = false
      ResetTickerRuntime(t, true)
    end
    ClearQueue(chatFrame)
  end
end

function M:Refresh(core)
  if not core:IsModuleActive("Ticker") then return end
  ApplyTickerState(core, false)
end

RothChat:RegisterModule(M)
