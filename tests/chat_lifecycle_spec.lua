-- Coalescing and native lifecycle events use the production core handler.
local env = assert(loadfile("tests/support/runtime.lua"))().New()
local core, emitted = env.core, {}
for _, name in ipairs({ "FCFDock_SelectWindow", "FCF_SelectDockFrame", "FCF_DockUpdate",
  "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow", "FCF_SetTemporaryWindowType", "FCF_Close",
  "FCF_ResetChatWindows", "FCF_RestoreChatsToFrame" }) do _G[name] = function() end end
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
