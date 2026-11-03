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
core:OnAddonLoaded()
core:EnsureChatLifecycleHooks()
local closeHook = assert(env.hooks.FCF_Close)
core:EnsureChatLifecycleHooks()
assert(env.hooks.FCF_Close == closeHook, "hooks must be installed only once")

core:QueueChatLifecycleRefresh(nil, "initial")
core:QueueChatLifecycleRefresh(env.frame, "again")
assert(#emitted == 0)
env:Advance()
assert(#emitted == 2 and emitted[1][1] == "CHAT_LAYOUT_CHANGED")
assert(emitted[2][1] == "CHAT_FRAME_READY" and emitted[2][2] == env.frame)
assert(core:GetChatLayoutRevision(env.frame) == core:GetChatLayoutRevision())
core:EnsureChatFrameLifecycleHooks(inactive)
assert(core:GetChatLayoutRevision(inactive) == nil, "missing invalidation methods must disable caching")

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

emitted = {}
closeHook(env.frame, inactive)
env:Advance()
assert(emitted[1][1] == "CHAT_FRAME_CLOSED" and emitted[1][2] == inactive)
for _, entry in ipairs(emitted) do
  assert(not (entry[1] == "CHAT_FRAME_READY" and entry[2] == inactive))
end

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
