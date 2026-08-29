-- Retail platform boundary contract.

local now = 100
local reports = 0
local NS = {}

_G.GetTime = function() return now end
_G.debugstack = function() return "stack" end
_G.DEFAULT_CHAT_FRAME = {
  AddMessage = function()
    reports = reports + 1
    -- Simulate the unified AddMessage hook reporting another callback failure
    -- while the first diagnostic is being printed.
    NS.SafeCall("nested", function() error("nested failure") end)
  end,
}

local permanent = {
  GetID = function() return 1 end,
  IsShown = function() return true end,
}
local inactivePermanent = {
  GetID = function() return 2 end,
  IsShown = function() return false end,
}
local activeTemporary = {
  isTemporary = true,
  inUse = true,
  GetID = function() return 11 end,
  IsShown = function() return false end,
}
local closedTemporary = {
  isTemporary = true,
  inUse = false,
  isDocked = false,
  GetID = function() return 12 end,
  IsShown = function() return false end,
}

_G.ChatFrame1 = permanent
_G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME
_G.Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
_G.FCF_IsChatWindowIndexActive = function(index)
  return index == 1
end
_G.FCF_IterateActiveChatWindows = function(callback)
  callback(permanent, 1)
end

NS.GetChatFrameIndex = function(frame)
  return frame and frame:GetID() or nil
end
NS.GetChatFrames = function()
  return { permanent, inactivePermanent, activeTemporary, closedTemporary }
end

assert(loadfile("Platform.lua"))("RothChat", NS)

assert(NS.IsActiveChatFrame(permanent))
assert(not NS.IsActiveChatFrame(inactivePermanent))
assert(NS.IsActiveChatFrame(activeTemporary))
assert(not NS.IsActiveChatFrame(closedTemporary))
assert(NS.GetMaxPermanentChatWindows() == 10)

local active = NS.GetActiveChatFrames()
assert(#active == 2)
assert(active[1] == permanent)
assert(active[2] == activeTemporary)

local results = { n = select("#", NS.SafeCall("multi", function(a, b)
  assert(a == "a" and b == "b")
  return 1, nil, 3
end, "a", "b")), NS.SafeCall("multi", function(a, b)
  assert(a == "a" and b == "b")
  return 1, nil, 3
end, "a", "b") }
assert(results.n == 4)
assert(results[1] == true and results[2] == 1 and results[3] == nil and results[4] == 3)

local ok = NS.SafeCall("boom", function() error("failure") end)
assert(ok == false)
assert(reports == 1, "diagnostic AddMessage recursion must be suppressed")

NS.ReportError("duplicate", "same")
NS.ReportError("duplicate", "same")
assert(reports == 2, "duplicate diagnostic must be rate-limited")
now = now + 11
NS.ReportError("duplicate", "same")
assert(reports == 3)

print("platform_spec: ok")
