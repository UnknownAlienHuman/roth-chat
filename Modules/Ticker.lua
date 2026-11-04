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
local MAX_MESSAGE_CHARS = 1024
local ALPHA_EPSILON = 0.01
local tickers = setmetatable({}, { __mode = "k" })
local messageQueue = setmetatable({}, { __mode = "k" })
local frameSnapshots = setmetatable({}, { __mode = "k" })
local refreshKey = {}
local ApplyTickerState
M.__applyDeferredKey = M.__applyDeferredKey or {}
M.__cleanupDeferredKey = M.__cleanupDeferredKey or {}
local chatRestricted = false

local function CanAccessFrame(frame)
  return NS.CanAccessObject(frame)
end

local SafeNumber = NS.SafeNumber

local function IsChatRestricted()
  return chatRestricted or NS.IsChatMessagingRestricted()
end

local function GetFrameIndex(frame)
  return NS.GetChatFrameIndex(frame)
end

local function IsPermanentActiveFrame(frame)
  if not CanAccessFrame(frame) or frame.isTemporary then return false end
  return NS.IsActiveChatFrame(frame)
end

local function ResolvePrimaryChatFrame(core)
  local configuredIndex = SafeNumber(core:Get("primaryChatIndex")) or 1
  configuredIndex = math.floor(NS.Clamp(configuredIndex, 1, 10))
  local configured = _G["ChatFrame" .. configuredIndex]
  if IsPermanentActiveFrame(configured) then return configured end

  local candidates = {}
  local function AddCandidate(frame)
    if CanAccessFrame(frame) then candidates[#candidates + 1] = frame end
  end
  AddCandidate(NS.GetSelectedDockChatFrame())
  AddCandidate(_G.ChatFrame1)
  for _, frame in ipairs(NS.GetActiveChatFrames and NS.GetActiveChatFrames() or {}) do
    AddCandidate(frame)
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
  if NS.IsDockedChatFrame(frame) then
    local selected = NS.GetSelectedDockChatFrame()
    if selected and selected ~= frame then return false end
  end
  return type(frame.IsShown) ~= "function" or frame:IsShown() == true
end

local function EnsureQueue(frame)
  local queue = messageQueue[frame]
  if not queue then
    queue = { head = 1, count = 0 }
    messageQueue[frame] = queue
  end
  return queue
end

local function QueuePush(frame, line, r, g, b)
  local queue = EnsureQueue(frame)
  if queue.count >= QUEUE_MAX then
    queue[queue.head] = nil
    queue.head = queue.head % QUEUE_MAX + 1
    queue.count = queue.count - 1
  end
  local tail = (queue.head + queue.count - 1) % QUEUE_MAX + 1
  queue[tail] = { line, r, g, b }
  queue.count = queue.count + 1
end

local function QueuePop(frame)
  local queue = messageQueue[frame]
  if not queue or queue.count == 0 then return nil end

  local item = queue[queue.head]
  queue[queue.head] = nil
  queue.head = queue.head % QUEUE_MAX + 1
  queue.count = queue.count - 1
  if queue.count == 0 then queue.head = 1 end
  return item
end

local function QueueIsEmpty(queue)
  return not queue or queue.count == 0
end

local function ClearQueue(frame)
  messageQueue[frame] = { head = 1, count = 0 }
end

local function ResetTextAnchors(tickerFrame)
  if not CanAccessFrame(tickerFrame) or not tickerFrame.text then return end
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
  if not CanAccessFrame(tickerFrame) then return end
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

local function ClearTickerDisplay(frame)
  local tickerFrame = tickers[frame]
  if not CanAccessFrame(tickerFrame) then return end
  ClearQueue(frame)
  ResetTickerRuntime(tickerFrame, true)
  tickerFrame.text:SetText("")
  tickerFrame.fullText = ""
  tickerFrame.fullCharLen = 0
  tickerFrame.charIndex = 0
end

local function GetAlpha(frame)
  if CanAccessFrame(frame) and type(frame.GetAlpha) == "function" then
    local ok, alpha = pcall(frame.GetAlpha, frame)
    if ok then return SafeNumber(alpha) end
  end
  return nil
end

local function GetMouseEnabled(frame)
  if CanAccessFrame(frame) and type(frame.IsMouseEnabled) == "function" then
    local ok, enabled = pcall(frame.IsMouseEnabled, frame)
    if ok and NS.CanAccessValue(enabled) then return enabled and true or false end
  end
  return nil
end

local function CaptureFrameOwnership(frame)
  if not CanAccessFrame(frame) or frameSnapshots[frame] then return end
  frameSnapshots[frame] = {
    alpha = GetAlpha(frame),
    mouseEnabled = GetMouseEnabled(frame),
  }
end

local function RestoreFrameOwnership(frame)
  local snapshot = frame and frameSnapshots[frame]
  if not snapshot or not CanAccessFrame(frame) then return end

  local ownsActiveFade = type(NS.StopOwnedFade) == "function" and NS.StopOwnedFade(frame, M) or false
  local currentAlpha = GetAlpha(frame)
  local alphaStillOwned = ownsActiveFade
    or (type(snapshot.lastAlphaWrite) == "number" and type(currentAlpha) == "number"
      and math.abs(currentAlpha - snapshot.lastAlphaWrite) < ALPHA_EPSILON)
  if alphaStillOwned and type(frame.SetAlpha) == "function" and type(snapshot.alpha) == "number" then
    frame:SetAlpha(snapshot.alpha)
  end

  local currentMouse = GetMouseEnabled(frame)
  if snapshot.mouseEnabled ~= nil and snapshot.lastMouseWrite ~= nil
    and currentMouse == snapshot.lastMouseWrite and type(frame.EnableMouse) == "function"
  then
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
  if core:Ge