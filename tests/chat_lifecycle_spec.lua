-- Coalescing and native lifecycle events use the production core handler.
local env = assert(loadfile("tests/support/runtime.lua"))().New()
local core, emitted = env.core, {}
for _, name in ipairs({ "FCFDock_SelectWindow", "FCF_SelectDockFrame", "FCF_DockUpdate",
  "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow", "FCF_SetTemporaryWindowType", "FCF_Close",
  "FCF_ResetChatWindows", "FCF_RestoreChatsToFrame", "FCF_SetWindowName" }) do _G[name] = function() end end
local subscriptionMethods = {
  "AddMessageGroup", "RemoveMessageGroup", "AddSingleMessageType",
  "UnregisterAllMessageGroups", "RemoveAllMessageGroups",
  "AddChannel", "RemoveChannel", "RemoveAllChannels",
}
local nativeCalls = 0
for _, method in ipairs(subscriptionMethods) do
  env.frame[method] = function() nativeCalls = nativeCalls + 1 end
end
local inactive = CreateFrame("Frame", "ChatFrame2")
inactive.id, inactive.shown = 2, false
CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
FCF_IsChatWindowIndexActive = function(index) return index == 1 end
for _, name in ipairs({ "CHAT_LAYOUT_CHANGED", "CHAT_FRAME_READY", "CHAT_FRAME_CLOSED" }) do
  local event = name
  core:On(event, function(_, _, frame) emitted[#emitted + 1] = {event, frame} end, {})
end

-- One denied global hook must not abort the remaining lifecycle installation,
-- and the denied entry point must not be retried on a later ensure pass.
local nativeHooksecurefunc = hooksecurefunc
local deniedAttempts = 0
hooksecurefunc = function(target, ...)
  if target == "FCFDock_SelectWindow" then
    deniedAttempts = deniedAttempts + 1
    error("denied global lifecycle hook")
  end
  return nativeHooksecurefunc(target, ...)
end
core:OnAddonLoaded()
local closeHook = assert(env.hooks.FCF_Close)
assert(deniedAttempts == 1 and env.hooks.FCFDock_SelectWindow == nil)
core:EnsureChatLifecycleHooks()
assert(env.hooks.FCF_Close == closeHook, "hooks must be installed only once")
assert(deniedAttempts == 1, "a denied permanent hook must not be retried")
hooksecurefunc = nativeHooksecurefunc

-- Lifecycle identity, reasons and frame keys must be ordinary before they can
-- enter retained queue tables.
local initialRevision = core:GetChatLayoutRevision()
assert(not core:QueueChatLifecycleRefresh(env.inaccessible, "opaque_frame"))
assert(not core:QueueChatLifecycleRefresh(nil, env.inaccessible))
assert(not core:QueueChatLifecycleRefresh(nil, 42))
assert(not core:QueueChatLifecycleClose(env.inaccessible, "opaque_close"))
assert(core:GetChatLayoutRevision() == initialRevision)

-- A scheduler refusal must not leave queue.queued wedged forever.
local runNextFrame = env.ns.RunNextFrame
env.ns.RunNextFrame = function() return false end
assert(not core:QueueChatLifecycleRefresh(nil, "scheduler_rejected"))
local queue = core._chatLifecycleQueue
assert(not queue.queued and not queue.refreshAll and queue.layoutReason == nil)
assert(next(queue.frameReasons) == nil and next(queue.closedFrames) == nil)
env.ns.RunNextFrame = runNextFrame

core:QueueChatLifecycleRefresh(nil, "initial")
core:QueueChatLifecycleRefresh(env.frame, "again")
assert(#emitted == 0)
env:Advance()
assert(#emitted == 2 and emitted[1][1] == "CHAT_LAYOUT_CHANGED")
assert(emitted[2][1] == "CHAT_FRAME_READY" and emitted[2][2] == env.frame)
assert(core:GetChatLayoutRevision(env.frame) == core:GetChatLayoutRevision())
core:EnsureChatFrameLifecycleHooks(inactive)
assert(core:GetChatLayoutRevision(inactive) == nil, "missing invalidation methods must disable caching")

-- A hostile method lookup is evidence of an incomplete frame contract, not a
-- reason to throw or to authorize cached identity reuse.
local hostile = {
  HasAccessConstraints = function() return false end,
  CanBeAccessedInContext = function() return true end,
  IsForbidden = function() return false end,
}
setmetatable(hostile, {
  __index = function(_, key)
    if key == "AddMessageGroup" then error("denied method lookup") end
    return nil
  end,
})
core:EnsureChatFrameLifecycleHooks(hostile)
assert(core:GetChatLayoutRevision(hostile) == nil)

-- Native subscription/name changes invalidate identity before another message
-- can reuse the cache, without waiting for a global update event.
emitted = {}
local addChannel = env.frame.AddChannel
core:EnsureChatFrameLifecycleHooks(env.frame)
assert(env.frame.AddChannel == addChannel, "native methods must not accumulate hooks")
for _, method in ipairs(subscriptionMethods) do
  local revision = core:GetChatLayoutRevision()
  env.frame[method](env.frame, env.inaccessible)
  assert(core:GetChatLayoutRevision() == revision + 1, method .. " must invalidate immediately")
end
assert(nativeCalls == #subscriptionMethods)
local revision = core:GetChatLayoutRevision()
env.hooks.FCF_SetWindowName(env.frame, env.inaccessible)
assert(core:GetChatLayoutRevision() == revision + 1)
assert(#emitted == 0, "native mutations must share the deferred layout pass")
env:Advance()
assert(#emitted == 2)

-- The native fixed pool can still report a just-closed slot as active. CLOSE is
-- terminal for this flush; READY is allowed only in a later lifecycle generation.
emitted = {}
closeHook(env.frame)
env:Advance()
assert(emitted[1][1] == "CHAT_FRAME_CLOSED" and emitted[1][2] == env.frame)
for _, entry in ipairs(emitted) do
  assert(not (entry[1] == "CHAT_FRAME_READY" and entry[2] == env.frame))
end
emitted = {}
core:QueueChatLifecycleRefresh(nil, "later_reopen")
env:Advance()
local reopened = false
for _, entry in ipairs(emitted) do
  if entry[1] == "CHAT_FRAME_READY" and entry[2] == env.frame then reopened = true end
end
assert(reopened, "a later native generation may announce the active slot again")

-- Permanent post-hooks still run while the addon is disabled or messaging is
-- restricted. Their evidence must be dropped immediately, not replayed after
-- the gate opens again.
emitted = {}
core._addonEnabled = false
closeHook(env.frame)
assert(not queue.queued and next(queue.closedFrames) == nil)
core._addonEnabled = true
core:QueueChatLifecycleRefresh(nil, "after_enable")
env:Advance()
assert(#emitted == 2)
for _, entry in ipairs(emitted) do assert(entry[1] ~= "CHAT_FRAME_CLOSED") end

emitted = {}
env.restricted = true
closeHook(env.frame)
assert(not queue.queued and next(queue.closedFrames) == nil)
env.restricted = false
core:QueueChatLifecycleRefresh(nil, "after_restriction")
env:Advance()
assert(#emitted == 2)
for _, entry in ipairs(emitted) do assert(entry[1] ~= "CHAT_FRAME_CLOSED") end

emitted = {}
env:Event("UPDATE_CHAT_WINDOWS")
env:Event("UPDATE_FLOATING_CHAT_WINDOWS")
env:Advance()
assert(#emitted == 2, "native signals must share one coalesced pass")

local seenRestriction
core:On("CHAT_RESTRICTION_CHANGED", function(_, _, value, ...)
  assert(select("#", ...) == 0, "raw restriction event arguments must not be forwarded")
  seenRestriction = value
end, {})
emitted = {}
env.restricted = true
env:Event("ADDON_RESTRICTION_STATE_CHANGED", env.inaccessible)
core:QueueChatLifecycleRefresh(nil, "restricted")
env:Advance()
assert(seenRestriction == true and #emitted == 0)
env.restricted = false
env:Event("ADDON_RESTRICTION_STATE_CHANGED")
env:Advance()
assert(seenRestriction == false and #emitted == 2)
print("chat_lifecycle_spec: ok")
