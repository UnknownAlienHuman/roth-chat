-- RothChat - Blizzard chat-frame lifecycle router.
-- Loaded after Core.lua so it can replace the generic FCF hook adapter with
-- Retail 12.1 active-window semantics from Blizzard_ChatFrameBase.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local function ResetQueue(queue)
  queue.queued = false
  queue.refreshAll = false
  queue.layoutReason = nil
  queue.frameReasons = {}
  queue.closedFrames = {}
end

function RothChat:QueueChatLifecycleRefresh(chatFrame, reason)
  local queue = self._chatLifecycleQueue
  reason = reason or "layout"

  if chatFrame then
    queue.frameReasons[chatFrame] = reason
  else
    queue.refreshAll = true
  end

  queue.layoutReason = queue.layoutReason or reason
  if queue.queued then return end
  queue.queued = true

  NS.RunNextFrame(self._chatLifecycleScheduleKey, function()
    local current = self._chatLifecycleQueue
    if not current.queued then return end

    local refreshAll = current.refreshAll
    local layoutReason = current.layoutReason or "layout"
    local frameReasons = current.frameReasons
    local closedFrames = current.closedFrames
    ResetQueue(current)

    for closedFrame, closedReason in pairs(closedFrames) do
      self:Emit("CHAT_FRAME_CLOSED", closedFrame, closedReason)
    end

    self:Emit("CHAT_LAYOUT_CHANGED", layoutReason)

    if refreshAll then
      for _, chatFrame2 in ipairs(NS.GetActiveChatFrames()) do
        self:EnsureAddMsgHookForFrame(chatFrame2)
        self:Emit("CHAT_FRAME_READY", chatFrame2, frameReasons[chatFrame2] or layoutReason)
      end
    else
      for chatFrame2, frameReason in pairs(frameReasons) do
        if NS.IsActiveChatFrame(chatFrame2) then
          self:EnsureAddMsgHookForFrame(chatFrame2)
          self:Emit("CHAT_FRAME_READY", chatFrame2, frameReason)
        end
      end
    end
  end, "RothChat:ChatLifecycleRefresh")
end

function RothChat:QueueChatLifecycleClose(chatFrame, reason)
  if chatFrame then
    self._chatLifecycleQueue.closedFrames[chatFrame] = reason or "close"
    self._chatLifecycleQueue.frameReasons[chatFrame] = nil
  end
  self:QueueChatLifecycleRefresh(nil, reason or "close")
end

function RothChat:EnsureChatLifecycleHooks()
  if self._chatLifecycleHooked then return end
  self._chatLifecycleHooked = true

  local function QueueAll(reason)
    RothChat:QueueChatLifecycleRefresh(nil, reason)
  end

  local function QueueFrame(chatFrame, reason)
    if chatFrame then
      RothChat:QueueChatLifecycleRefresh(chatFrame, reason)
    else
      QueueAll(reason)
    end
  end

  if type(_G.FCFDock_SelectWindow) == "function" then
    hooksecurefunc("FCFDock_SelectWindow", function(_, chatFrame)
      QueueFrame(chatFrame, "dock_select_window")
      QueueAll("dock_select_window")
    end)
  end

  if type(_G.FCF_SelectDockFrame) == "function" then
    hooksecurefunc("FCF_SelectDockFrame", function(chatFrame)
      QueueFrame(chatFrame, "select_dock_frame")
      QueueAll("select_dock_frame")
    end)
  end

  if type(_G.FCF_DockUpdate) == "function" then
    hooksecurefunc("FCF_DockUpdate", function()
      QueueAll("dock_update")
    end)
  end

  if type(_G.FCF_OpenTemporaryWindow) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
      QueueAll("open_temporary_window")
    end)
  end

  if type(_G.FCF_OpenNewWindow) == "function" then
    hooksecurefunc("FCF_OpenNewWindow", function()
      QueueAll("open_new_window")
    end)
  end

  if type(_G.FCF_SetTemporaryWindowType) == "function" then
    hooksecurefunc("FCF_SetTemporaryWindowType", function(chatFrame)
      QueueFrame(chatFrame, "set_temporary_window_type")
      QueueAll("set_temporary_window_type")
    end)
  end

  if type(_G.FCF_Close) == "function" then
    hooksecurefunc("FCF_Close", function(frame, fallback)
      local chatFrame = NS.ResolveClosedChatFrame(frame, fallback)
      RothChat:QueueChatLifecycleClose(chatFrame, "close_window")
    end)
  end

  if type(_G.FCF_ResetChatWindows) == "function" then
    hooksecurefunc("FCF_ResetChatWindows", function()
      QueueAll("reset_chat_windows")
    end)
  end

  if type(_G.FCF_RestoreChatsToFrame) == "function" then
    hooksecurefunc("FCF_RestoreChatsToFrame", function(targetFrame)
      QueueFrame(targetFrame, "restore_chat_subscriptions")
    end)
  end
end

-- UPDATE_CHAT_WINDOWS is the native signal that permanent window names,
-- subscriptions, shown state, docking or saved configuration may have changed.
-- Core's primary OnEvent script intentionally stays small; this secondary hook
-- translates the native event into the same coalesced lifecycle boundary.
if type(RothChat.RegisterEvent) == "function" then
  pcall(RothChat.RegisterEvent, RothChat, "UPDATE_CHAT_WINDOWS")
  pcall(RothChat.RegisterEvent, RothChat, "UPDATE_FLOATING_CHAT_WINDOWS")
end
if type(RothChat.HookScript) == "function" then
  RothChat:HookScript("OnEvent", function(_, event)
    if event == "UPDATE_CHAT_WINDOWS" or event == "UPDATE_FLOATING_CHAT_WINDOWS" then
      RothChat:QueueChatLifecycleRefresh(nil, string.lower(event))
    end
  end)
end
