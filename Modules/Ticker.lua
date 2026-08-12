-- RothChat - Ticker (Typewriter)
-- Responsibilities:
--   * Hide chat content when idle.
--   * Show new messages with a typewriter effect.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Ticker",
  defaultEnabled = true,
  description = "Immersion: hide chat when idle, show messages via typewriter effect.",
}

local tickers = {}
local messageQueue = {} -- [chatFrame] = { first = n, last = n, [n] = {line, r, g, b} }

local function GetPrimaryChatFrame(core)
  local idx = tonumber(core:Get("primaryChatIndex")) or 1
  return _G["ChatFrame" .. idx] or _G.ChatFrame1
end



local function ShouldApplyImmersionToFrame(core, cf)
  if not cf then return false end

  -- Keep immersion/ticker scoped to the configured primary chat frame.
  -- Applying alpha hiding to every docked frame hides whisper temp tabs while
  -- only the primary frame has a ticker feed hook.
  local primary = GetPrimaryChatFrame(core)
  return (primary and cf == primary) and true or false
end
-- Check if a chat frame is the currently selected/visible frame in its dock
local function IsChatFrameActiveTab(cf)
  if not cf then return false end
  -- The most reliable signal for "active tab" is SELECTED_CHAT_FRAME.
  -- This avoids cross-dock bleed (Issue: ticker lines from ChatFrame1 appearing in other tabs).
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

local function QueuePush(cf, line, r, g, b)
  local q = EnsureQueue(cf)
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
  return (not q) or q.first > q.last
end

local function ClearQueue(cf)
  messageQueue[cf] = { first = 1, last = 0 }
end

local function CancelHold(tickerFrame)
  if not tickerFrame or not tickerFrame.__holdScheduleKey then
    return
  end

  tickerFrame.holding = false
  NS.CancelScheduled(tickerFrame.__holdScheduleKey)
end

local function ScheduleNextProcess(core, cf, delay)
  local tickerFrame = tickers[cf]
  if not tickerFrame then
    return
  end

  tickerFrame.__holdScheduleKey = tickerFrame.__holdScheduleKey or {}
  tickerFrame.holding = true
  NS.Schedule(tickerFrame.__holdScheduleKey, delay, function()
    tickerFrame.holding = false
    M:ProcessQueue(core, cf)
  end, "RothChat:TickerHold")
end

local function QueueLine(core, cf, line, r, g, b)
  if not core:Get("tickerEnabled") then return end
  if not core:IsModuleEnabled("Controls") then return end
  if NS.IsSecretValue(line) then return end
  -- Don't capture messages if the chat frame is not the active tab
  if not IsChatFrameActiveTab(cf) then return end

  local safeLine = NS.SafeToString(line)
  if safeLine == "" then return end

  QueuePush(cf, safeLine, r, g, b)

  local tt = tickers[cf]
  if tt and not tt.controlsVisible and not tt.isAnimating and not tt.holding then
    M:ProcessQueue(core, cf)
  end
end

-- Unified AddMessage hook callback (registered via core:RegisterAddMessageHook).
local function OnAddMessage(frame, text, r, g, b)
  if not M._loggedIn then return end
  if not M.core or not M.core:IsModuleEnabled("Ticker") then return end
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
  t.isAnimating = false
  t.holding = false
  t.animMode = "fade"
  t.fullText = ""
  t.charIndex = 0
  t.timer = 0
  t.slideOffset = 0

  t:SetScript("OnUpdate", function(self, elapsed)
    if not self.isAnimating then return end

    local mode = self.animMode

    if mode == "typewriter" then
      -- Character-by-character reveal with truncation for long messages
      self.timer = self.timer + elapsed
      local speed = tonumber(core:Get("tickerSpeed")) or 30
      local interval = 1 / speed
      local charsToAdd = math.floor(self.timer / interval)
      if charsToAdd >= 1 then
        self.timer = self.timer - charsToAdd * interval
        self.charIndex = self.charIndex + charsToAdd
        local sub = NS.Utf8Sub(self.fullText, self.charIndex)
        if #sub >= #self.fullText then
          self.text:SetText(self.fullText)
          self.isAnimating = false
          ScheduleNextProcess(core, cf, 2.0)
          return
        end
        self.text:SetText(sub .. "_")
      end

    elseif mode == "slide" then
      -- Slide up from below
      self.timer = self.timer + elapsed
      local dur = 0.2
      local progress = math.min(self.timer / dur, 1)
      -- outCubic: t = t/d - 1; result = c*(t^3+1)+b
      local t_norm = progress - 1
      local eased = 1 * (t_norm ^ 3 + 1) + 0
      local startOff = -20
      local yOff = startOff * (1 - eased)
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
      -- Scroll text from right to left (adaptive speed: longer text = faster)
      self.timer = self.timer + elapsed
      local speed = tonumber(core:Get("tickerSpeed")) or 30
      local textW = self.text:GetStringWidth() or 100
      local frameW = self:GetWidth() or 300
      local totalTravel = frameW + textW
      -- Adaptive: base speed + scale with text length so long messages don't take forever
      local pixelSpeed = speed * 4 + math.max(0, (textW - frameW) * 0.5)
      local offset = self.timer * pixelSpeed
      if offset >= totalTravel then
        self.text:ClearAllPoints()
        self.text:SetPoint("LEFT", self, "LEFT", 10, 0)
        self.text:SetPoint("RIGHT", self, "RIGHT", -10, 0)
        self.isAnimating = false
        ScheduleNextProcess(core, cf, 1.0)
        return
      end
      self.text:ClearAllPoints()
      self.text:SetPoint("LEFT", self, "RIGHT", -offset, 0)

    elseif mode == "fade" then
      -- Y-shift: animate text offset from -2 to 0 over 0.2s
      if self._fadeYShift then
        self._fadeTimer = (self._fadeTimer or 0) + elapsed
        local dur = 0.2
        local progress = math.min(self._fadeTimer / dur, 1)
        local yOff = -2 * (1 - progress)
        self.text:ClearAllPoints()
        self.text:SetPoint("LEFT", self, "LEFT", 10, yOff)
        self.text:SetPoint("RIGHT", self, "RIGHT", -10, yOff)
        if progress >= 1 then
          self._fadeYShift = false
        end
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
  if not t or t.controlsVisible or t.isAnimating or t.holding then return end

  local q = messageQueue[cf]
  if QueueIsEmpty(q) then
    t.text:SetText(t.fullText)
    -- Reset text anchor for marquee cleanup
    t.text:ClearAllPoints()
    t.text:SetPoint("LEFT", t, "LEFT", 10, 0)
    t.text:SetPoint("RIGHT", t, "RIGHT", -10, 0)
    NS.FadeTo(t, 0, 0.5, function() t:Hide() end)
    return
  end

  local msgData = QueuePop(cf)
  local line = msgData[1]
  local r, g, b = msgData[2], msgData[3], msgData[4]

  t.charIndex = 0
  t.timer = 0
  t._fadeYShift = false
  t._fadeTimer = 0
  if r then t.text:SetTextColor(r, g, b) else t.text:SetTextColor(1, 1, 1) end

  local mode = core:Get("tickerAnimation") or "fade"
  t.animMode = mode

  -- Typewriter: truncate very long messages to keep animation reasonable
  if mode == "typewriter" and NS.Utf8Len(line) > 200 then
    line = NS.Utf8Sub(line, 200) .. "..."
  end
  t.fullText = line

  if mode == "fade" then
    -- Fade transition with subtle Y-shift: message "floats up" 2px as it appears
    local function ShowNewFadeMessage()
      t.text:SetText(line)
      t.text:ClearAllPoints()
      t.text:SetPoint("LEFT", t, "LEFT", 10, -2)   -- start 2px below
      t.text:SetPoint("RIGHT", t, "RIGHT", -10, -2)
      t:SetAlpha(0)
      t:Show()
      t.isAnimating = true
      t._fadeYShift = true
      t._fadeTimer = 0
      NS.FadeTo(t, 1, 0.2, function()
        -- Ensure final position is correct
        t.text:ClearAllPoints()
        t.text:SetPoint("LEFT", t, "LEFT", 10, 0)
        t.text:SetPoint("RIGHT", t, "RIGHT", -10, 0)
        t.isAnimating = false
        t._fadeYShift = false
        ScheduleNextProcess(core, cf, 2.0)
      end)
    end

    if t:IsShown() and t:GetAlpha() > 0.01 then
      t.isAnimating = true -- prevent re-entry during fade-out
      NS.FadeTo(t, 0, 0.12, function()
        t.isAnimating = false
        ShowNewFadeMessage()
      end)
    else
      ShowNewFadeMessage()
    end

  elseif mode == "typewriter" then
    t.text:SetText("")
    t.text:ClearAllPoints()
    t.text:SetPoint("LEFT", t, "LEFT", 10, 0)
    t.text:SetPoint("RIGHT", t, "RIGHT", -10, 0)
    t.isAnimating = true
    t:Show()
    t:SetAlpha(1)

  elseif mode == "slide" then
    t.text:SetText(line)
    t.text:ClearAllPoints()
    t.text:SetPoint("LEFT", t, "LEFT", 10, 0)
    t.text:SetPoint("RIGHT", t, "RIGHT", -10, 0)
    t.isAnimating = true
    t:Show()
    t:SetAlpha(1)

  elseif mode == "marquee" then
    t.text:SetText(line)
    -- Let text flow naturally from the right
    t.text:ClearAllPoints()
    t.text:SetPoint("LEFT", t, "RIGHT", 0, 0)
    t.isAnimating = true
    t:Show()
    t:SetAlpha(1)

  else
    -- Unknown mode, fallback to fade
    t.text:SetText(line)
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

  -- When fully hidden, disable mouse so the world is clickable.
  -- The Controls module hotspot covers the chat area and restores visibility on hover.
  if target <= 0.01 then
    cf:EnableMouse(false)
    cf.__rothMouseForcedOff = true
  else
    if cf.__rothMouseForcedOff then
      cf:EnableMouse(true)
      cf.__rothMouseForcedOff = nil
    end
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
    if not core or not core.IsModuleEnabled or not core:IsModuleEnabled("Ticker") then return end
    ForceNonPrimaryVisible(core)
  end, "RothChat:TickerNonPrimary")
end

local function UpdateVisibility(core, cf, active)
  if not core:Get("immersionEnabled") or not core:Get("tickerEnabled") then
    SetChatAlpha(core, cf, true)
    return
  end

  local t = BuildTicker(core, cf)
  if not t then return end

  if active then
    CancelHold(t)
    NS.StopFading(t)
    SetChatAlpha(core, cf, true)
    -- When returning from immersion-hidden state, ensure we are viewing the latest messages.
    if cf and cf.ScrollToBottom then
      pcall(function() cf:ScrollToBottom() end)
    end
    t.controlsVisible = true
    t:Hide()
    ClearQueue(cf)
  else
    SetChatAlpha(core, cf, false)
    LayoutTicker(core, cf)
    t.controlsVisible = false
    M:ProcessQueue(core, cf)
  end
end

function M:Init(core)
  self.core = core
  self._loggedIn = false
  return true
end

local function RegisterTickerListeners(core)
  core:OffOwner(M)

  -- Controls visibility updates arrive for all chat frames; we only apply
  -- immersion/ticker logic to the configured primary frame.
  core:On("CONTROLS_VISIBILITY", function(_, core2, chatFrame, _controlsVisible, pinned, hovering)
    local active
    if core2:IsModuleEnabled("Controls") then
      active = (pinned or hovering)
    else
      active = true
    end

    -- Apply immersion only to the primary frame.
    if core2:Get("immersionEnabled") and ShouldApplyImmersionToFrame(core2, chatFrame) then
      UpdateVisibility(core2, chatFrame, active)
    else
      SetChatAlpha(core2, chatFrame, true)
    end
  end, M)

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if not core2:IsModuleEnabled("Ticker") then return end
    QueueForceNonPrimaryVisible(core2)
  end, M)

  core:On("COPY_OVERLAY_VISIBILITY", function(_, core2, chatFrame, visible)
    local t = chatFrame and tickers[chatFrame]
    if not t then return end

    if visible then
      CancelHold(t)
      t.isAnimating = false
      t.controlsVisible = true
      NS.StopFading(t, 0)
      t:Hide()
    else
      QueueForceNonPrimaryVisible(core2)
    end
  end, M)
end

local function ApplyTickerState(core, refreshListeners)
  core:EnsureChatLifecycleHooks()

  local primaryCf = GetPrimaryChatFrame(core)
  if refreshListeners then
    RegisterTickerListeners(core)
  end

  if M._feedTarget ~= primaryCf then
    core:UnregisterAddMessageHooks(M)
  end

  -- Build ticker and hook feed for primary chat frame
  if primaryCf then
    BuildTicker(core, primaryCf)
    LayoutTicker(core, primaryCf)
    EnsureQueue(primaryCf)
    M._feedTarget = primaryCf
    core:RegisterAddMessageHook(OnAddMessage, M, 30)
  else
    M._feedTarget = nil
  end

  for cf, tickerFrame in pairs(tickers) do
    ApplyTickerTextStyle(core, tickerFrame)
    if cf then
      LayoutTicker(core, cf)
    end
  end

  -- Initial state: hide only the primary frame when immersion is enabled.
  if core:IsModuleEnabled("Controls") and core:Get("immersionEnabled") then
    for _, cf in ipairs(NS.GetChatFrames()) do
      if ShouldApplyImmersionToFrame(core, cf) then
        UpdateVisibility(core, cf, false)
      else
        SetChatAlpha(core, cf, true)
      end
    end
  else
    -- Controls off or immersion off: keep all chat visible
    for _, cf in ipairs(NS.GetChatFrames()) do
      SetChatAlpha(core, cf, true)
    end
  end

  -- Enforce non-primary visibility after initial pass to avoid stale alpha
  -- inherited by temporary whisper windows from the primary frame.
  QueueForceNonPrimaryVisible(core)
end

function M:OnEnable(core)
  local function Apply()
    ApplyTickerState(core, true)
  end

  if InCombatLockdown() then
    core:Defer(Apply)
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
  -- Restore visibility for all chat frames (matches OnEnable which now handles all)
  for _, cf in ipairs(NS.GetChatFrames()) do
    SetChatAlpha(core, cf, true)
  end
  for chatFrame, t in pairs(tickers) do
    CancelHold(t)
    if t then
      t.isAnimating = false
      t.controlsVisible = true
      NS.StopFading(t)
      t:Hide()
    end
    ClearQueue(chatFrame)
  end
end

function M:Refresh(core)
  if not core:IsModuleEnabled("Ticker") then
    self:OnDisable(core)
    return
  end
  ApplyTickerState(core, false)
end

RothChat:RegisterModule(M)
