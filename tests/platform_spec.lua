-- Current access predicates and native adapters, without private frame scans.
local env = assert(loadfile("tests/support/runtime.lua"))().New()
local NS = env.ns
local inactive = CreateFrame("Frame", "ChatFrame2")
inactive.id, inactive.shown = 2, false
local temporary = CreateFrame("Frame", "ChatFrame11")
temporary.id, temporary.isTemporary, temporary.inUse, temporary.shown = 11, true, true, false
local closed = CreateFrame("Frame", "ChatFrame12")
closed.id, closed.isTemporary, closed.inUse, closed.shown = 12, true, false, false
CHAT_FRAMES = { "ChatFrame1", "ChatFrame2", "ChatFrame11", "ChatFrame12" }
FCF_IsChatWindowIndexActive = function(index) return index == 1 end
FCF_IterateActiveChatWindows = function(callback) callback(ChatFrame1, 1) end
assert(NS.IsActiveChatFrame(env.frame) and not NS.IsActiveChatFrame(inactive))
assert(NS.IsActiveChatFrame(temporary) and not NS.IsActiveChatFrame(closed))
local active = NS.GetActiveChatFrames()
assert(#active == 2 and active[1] == env.frame and active[2] == temporary)
assert(NS.GetMaxPermanentChatWindows() == 10)

closed.inaccessible = true
assert(not NS.CanAccessObject(closed))
closed.inaccessible, closed.forbidden = false, true
assert(not NS.CanAccessObject(closed))
closed.forbidden = false
closed.CanBeAccessedInContext = function() return env.inaccessible end
assert(not NS.CanAccessObject(closed))

local result = NS.Pack(NS.SafeCall("multi", function(a, b)
  assert(a == "a" and b == "b")
  return 1, nil, 3, nil
end, "a", "b"))
assert(result.n == 5 and result[1] and result[2] == 1 and result[4] == 3)
local ok = NS.SafeCall("failure", function() error(env.inaccessible) end)
assert(not ok and #env.reports == 1)
NS.ReportError("failure", "private message must not be inspected")
assert(#env.reports == 1)
env.now = env.now + 11
NS.ReportError("failure", env.inaccessible)
assert(#env.reports == 2 and not env.reports[2]:find("private", 1, true))

-- Do not retry a failing current API through its legacy alias.
local legacyCalls = 0
ChatFrameUtil.AddMessageEventFilter = function() error("denied") end
ChatFrame_AddMessageEventFilter = function() legacyCalls = legacyCalls + 1 end
assert(not NS.AddMessageEventFilter("CHAT_MSG_SAY", function() end))
assert(legacyCalls == 0)

-- A secret buffer count is not converted/iterated, even with readable text.
env.frame.GetNumMessages = function() return env.inaccessible end
env.frame.GetMessageInfo = function() error("must not read a denied buffer") end
assert(NS.CollectChatText(env.frame, 100) == "")
env.restricted = true
env.frame.GetNumMessages = function() error("locked buffer must not be read") end
assert(NS.CollectChatText(env.frame, 100) == "")
local printed = #env.reports
assert(env.core:Print("blocked") == false and #env.reports == printed)
env.restricted = false
env.frame.forbidden = true
assert(env.core:Print("blocked") == false and #env.reports == printed)
env.frame.forbidden = false
assert(env.core:Print("available") == true and #env.reports == printed + 1)
print("platform_spec: ok")
