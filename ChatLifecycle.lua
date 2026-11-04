-- RothChat - Blizzard chat-frame lifecycle router.
-- One coalesced lifecycle owner for native events and stable FCF post-hooks.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local frameHooks = setmetatable({}, { __mode = "k" })
RothChat._chatLayoutRevision = 0
function RothChat:GetChatLayoutRevision(frame)
  if not NS.CanAccessValue(frame) or (frame ~= nil and frameHooks[frame] ~= true) then return nil end
  return self._chatLayoutRevision
end

RothChat._chatLifecycleHooked = false
RothChat._chatLifecycleScheduleKey = {}
RothChat._chatLifecycleQueue = {
  queued = false, refreshAll = false, layoutReason = nil,
  frameReasons = {}, closedFrames = {},
}

local subscriptionMethods = {
  "AddMessageGroup", "RemoveMessageGroup", "AddSingleMessageType",
  "UnregisterAllMessageGroups", "RemoveAllMessageGroups",
  "AddChannel", "RemoveChannel", "RemoveAllChannels",
}

local function ReadField(object, name)
  return object[name]
end

local function GetCallableField(object, name)
  local ok, value = pcall(ReadField, object, name)
  if not ok or not NS.CanAccessValue(value) or type(value) ~= "function" then return nil end
  return value
end

local function InstallGlobalPostHook(name, callback)
  local ok, target = pcall(ReadField, _G, name)
  if not ok or not NS.CanAccessValue(target) or type(target) ~= "function" then return false end
  return NS.SafeCall(
    "RothChat:ChatLifecycleHook:" .. name,
    hooksecurefunc,
    name,
    callback
  )
end

local function OnSubscriptionsChanged(frame)
  if NS.CanAccessObject(frame) then
    RothChat:QueueChatLifecycleRefresh(frame, "subscriptions_changed")
  end
end

function RothChat:EnsureChatFrameLifecycleHooks(frame)
  if not NS.CanAccessObject(frame) or frameHooks[frame] ~= nil then return end
  local complete = true
  for _, method in ipairs(subscriptionMethods) do
    if GetCallableField(frame, method) then
      -- One attempt per frame/method; denied hooks are not retried on updates.
      if not NS.SafeCall(
        "RothChat:ChatSubscriptionHook:" .. method,
        hooksecurefunc,
        frame,
        method,
        OnSubscriptionsChanged
      ) then
        complete = false
      end
    else
      complete = false
    end
  end
  -- An incomplete invalidation path can still observe messages, but cannot
  -- authorize reuse of a cached window fingerprint.
  frameHooks[frame] = complete
end

local function ResetQueue(queue)
  queue.queued = false
  queue.refreshAll = false
  queue.layoutReason = nil
  queue.frameReasons = {}
  queue.closedFrames = {}
end

local function DropQueue(self)
  NS.CancelScheduled(self._chatLifecycleScheduleKey)
  ResetQueue(self._chatLifecycleQueue)
end

local function CanQueueLifecycle(self)
  if NS.IsChatMessagingRestricted()
    or (self._addonLoaded and not self._addonEnabled)
  then
    DropQueue(self)
    return false
  end
  return true
end

local function ScheduleLifecycleFlush(self, reason)
  local queue = self._chatLifecycleQueue
  queue.layoutReason = queue.layoutReason or reason
  if queue.queued then return true end
  queue.queued = true

  local scheduled = NS.RunNextFrame(self._chatLifecycleScheduleKey, function()
    local current = self._chatLifecycleQueue
    if not current.queued then return end
    if NS.IsChatMessagingRestricted()
      or (self._addonLoaded and not self._addonEnabled)
    then
      ResetQueue(current)
      return
    end

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
      for _, chatFrame in ipairs(NS.GetActiveChatFrames()) do
        -- CLOSE is terminal for this flush. Native frame pools can still report
        -- a just-closed slot as active until a later update; do not recreate
        -- addon state on that same lifecycle generation.
        if not closedFrames[chatFrame] then
          self:EnsureAddMsgHookForFrame(chatFrame)
          self:Emit("CHAT_FRAME_READY", chatFrame, frameReasons[chatFrame] or layoutReason)
        end
      end
    else
      for chatFrame, frameReason in pairs(frameReasons) do
        if not closedFrames[chatFrame] and NS.IsActiveChatFrame(chatFrame) then
          self:EnsureAddMsgHookForFrame(chatFrame)
          self:Emit("CHAT_FRAME_READY", chatFrame, frameReason)
        end
      end
    end
  end, "RothChat:ChatLifecycleRefresh")

  if scheduled == false then
    ResetQueue(queue)
    return false
  end
  return true
end

function RothChat:QueueChatLifecycleRefresh(chatFrame, reason)
  if not NS.CanAccessAllValues(chatFrame, reason)
    or (chatFrame ~= nil and not NS.CanAccessObject(chatFrame))
    or (reason ~= nil and type(reason) ~= "string")
  then
    return false
  end

  self._chatLayoutRevision = self._chatLayoutRevision + 1
  if not CanQueueLifecycle(self) then return false end

  local queue = self._chatLifecycleQueue
  reason = reason or "layout"
  if chatFrame then
    queue.frameReasons[chatFrame] = reason
  else
    queue.refreshAll = true
  end
  return ScheduleLifecycleFlush(self, reason)
end

function RothChat:QueueChatLifecycleClose(chatFrame, reason)
  if not NS.CanAccessAllValues(chatFrame, reason)
    or (chatFrame ~= nil and not NS.CanAccessObject(chatFrame))
    or (reason ~= nil and type(reason) ~= "string")
  then
    return false
  end

  self._chatLayoutRevision = self._chatLayoutRevision + 1
  if not CanQueueLifecycle(self) then return false end

  local queue = self._chatLifecycleQueue
  reason = reason or "close"
  if chatFrame then
    queue.closedFrames[chatFrame] = reason
    queue.frameReasons[chatFrame] = nil
  end
  queue.refreshAll = true
  return ScheduleLifecycleFlush(self, reason)
end

function RothChat:EnsureChatLifecycleHooks()
  if self._chatLifecycleHooked then return end
  -- Every supported hook gets one isolated attempt. A denied or drifting entry
  -- point must not abort installation of the remaining lifecycle evidence.
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

  InstallGlobalPostHook("FCFDock_SelectWindow", function()
    QueueAll("dock_select_window")
  end)

  InstallGlobalPostHook("FCF_SelectDockFrame", function()
    QueueAll("select_dock_frame")
  end)

  InstallGlobalPostHook("FCF_DockUpdate", function()
    QueueAll("dock_update")
  end)

  InstallGlobalPostHook("FCF_OpenTemporaryWindow", function()
    QueueAll("open_temporary_window")
  end)

  InstallGlobalPostHook("FCF_OpenNewWindow", function()
    QueueAll("open_new_window")
  end)

  InstallGlobalPostHook("FCF_SetTemporaryWindowType", function()
    QueueAll("set_temporary_window_type")
  end)

  InstallGlobalPostHook("FCF_Close", function(frame, fallback)
    local chatFrame = NS.ResolveClosedChatFrame(frame, fallback)
    RothChat:QueueChatLifecycleClose(chatFrame, "close_window")
  end)

  InstallGlobalPostHook("FCF_ResetChatWindows", function()
    QueueAll("reset_chat_windows")
  end)

  InstallGlobalPostHook("FCF_RestoreChatsToFrame", function(targetFrame)
    QueueFrame(targetFrame, "restore_chat_subscriptions")
  end)

  InstallGlobalPostHook("FCF_SetWindowName", function(chatFrame)
    if NS.CanAccessObject(chatFrame) then QueueFrame(chatFrame, "window_name_changed") end
  end)
end
