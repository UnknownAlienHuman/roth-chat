-- Blizzard chat-frame lifecycle routing contract.

local hooks = {}
local emitted = {}
local readyHooked = {}
local registeredEvents = {}
local eventHook

_G.FCFDock_SelectWindow = function() end
_G.FCF_SelectDockFrame = function() end
_G.FCF_DockUpdate = function() end
_G.FCF_OpenTemporaryWindow = function() end
_G.FCF_OpenNewWindow = function() end
_G.FCF_SetTemporaryWindowType = function() end
_G.FCF_Close = function() end
_G.FCF_ResetChatWindows = function() end
_G.FCF_RestoreChatsToFrame = function() end

_G.hooksecurefunc = function(name, callback)
  hooks[name] = callback
end

local activeFrame = { active = true }
local inactiveFrame = { active = false }
local fallbackFrame = { active = false }

local NS = {
  RunNextFrame = function(_, callback)
    callback()
  end,
  GetActiveChatFrames = function()
    return { activeFrame }
  end,
  IsActiveChatFrame = function(frame)
    return frame and frame.active or false
  end,
  ResolveClosedChatFrame = function(frame, fallback)
    return fallback or frame
  end,
}

_G.RothChat = {
  _chatLifecycleHooked = false,
  _chatLifecycleScheduleKey = {},
  _chatLifecycleQueue = {
    queued = false,
    refreshAll = false,
    layoutReason = nil,
    frameReasons = {},
    closedFrames = {},
  },
  Emit = function(_, event, frame, reason)
    emitted[#emitted + 1] = { event, frame, reason }
  end,
  EnsureAddMsgHookForFrame = function(_, frame)
    readyHooked[frame] = true
  end,
  RegisterEvent = function(_, event)
    registeredEvents[event] = true
  end,
  HookScript = function(_, script, callback)
    assert(script == "OnEvent")
    eventHook = callback
  end,
}

assert(loadfile("ChatLifecycle.lua"))("RothChat", NS)
local core = _G.RothChat

core:QueueChatLifecycleRefresh(nil, "initial")
assert(#emitted == 2)
assert(emitted[1][1] == "CHAT_LAYOUT_CHANGED")
assert(emitted[2][1] == "CHAT_FRAME_READY" and emitted[2][2] == activeFrame)
assert(readyHooked[activeFrame] == true)
assert(readyHooked[inactiveFrame] == nil)

emitted = {}
core:QueueChatLifecycleRefresh(inactiveFrame, "inactive")
assert(#emitted == 1 and emitted[1][1] == "CHAT_LAYOUT_CHANGED")

core:EnsureChatLifecycleHooks()
assert(type(hooks.FCF_Close) == "function")
assert(registeredEvents.UPDATE_CHAT_WINDOWS)
assert(registeredEvents.UPDATE_FLOATING_CHAT_WINDOWS)
assert(type(eventHook) == "function")

emitted = {}
hooks.FCF_Close(activeFrame, fallbackFrame)
assert(emitted[1][1] == "CHAT_FRAME_CLOSED")
assert(emitted[1][2] == fallbackFrame, "FCF_Close fallback must be the closed frame")
for i = 1, #emitted do
  assert(not (emitted[i][1] == "CHAT_FRAME_READY" and emitted[i][2] == fallbackFrame))
end

emitted = {}
eventHook(nil, "UPDATE_CHAT_WINDOWS")
assert(emitted[1][1] == "CHAT_LAYOUT_CHANGED")
assert(emitted[2][1] == "CHAT_FRAME_READY" and emitted[2][2] == activeFrame)

print("chat_lifecycle_spec: ok")
