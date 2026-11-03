-- Small native boundary fixture; production files are loaded in TOC order.
local Runtime = {}

function Runtime.New(profile)
  local env = { now = 100, combat = false, restricted = false, frames = {}, filters = {}, hooks = {}, reports = {} }
  env.inaccessible = setmetatable({}, { __tostring = function() error("opaque value inspected") end })
  _G.unpack = unpack or table.unpack
  _G.SlashCmdList = {}
  _G.GetTime = function() return env.now end
  _G.InCombatLockdown = function() return env.combat end
  _G.C_ChatInfo = { InChatMessagingLockdown = function() return env.restricted end }
  _G.canaccessvalue = function(value) return not rawequal(value, env.inaccessible) end
  _G.canaccessallvalues = function(...)
    for index = 1, select("#", ...) do
      if not _G.canaccessvalue(select(index, ...)) then return false end
    end
    return true
  end
  _G.canaccesstable = _G.canaccessvalue
  _G.CreateFrame = function(_, name)
    local frame = { scripts = {}, events = {}, alpha = 1, shown = true }
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:GetScript(event) return self.scripts[event] end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:GetID() return self.id end
    function frame:GetName() return name end
    function frame:CanBeAccessedInContext() return not self.inaccessible end
    function frame:IsForbidden() return self.forbidden == true end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:IsShown() return self.shown end
    function frame:AddMessage(text) env.reports[#env.reports + 1] = text end
    env.frames[#env.frames + 1] = frame
    if name then _G[name] = frame end
    return frame
  end
  _G.hooksecurefunc = function(target, name, callback)
    if type(target) == "string" then
      env.hooks[target] = name
      return
    end
    local original = target[name]
    target[name] = function(...)
      original(...)
      callback(...)
    end
  end
  _G.ChatFrameUtil = {
    AddMessageEventFilter = function(event, fn) env.filters[event] = fn end,
    RemoveMessageEventFilter = function(event, fn)
      if env.filters[event] == fn then env.filters[event] = nil end
    end,
  }
  _G.CHAT_FRAMES = { "ChatFrame1" }
  _G.NUM_CHAT_WINDOWS = 10
  _G.Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
  _G.FCF_IterateActiveChatWindows = nil
  _G.FCF_IsChatWindowIndexActive = nil
  _G.SELECTED_CHAT_FRAME = nil
  _G.GENERAL_CHAT_DOCK = nil
  _G.GeneralDockManager = nil
  _G.ChatFrame1 = CreateFrame("Frame", "ChatFrame1")
  _G.ChatFrame1.id = 1
  _G.DEFAULT_CHAT_FRAME = _G.ChatFrame1
  _G.RothChatDB = { profile = profile or {} }
  env.frame = _G.ChatFrame1
  env.ns = {}
  for _, path in ipairs({ "Util.lua", "Platform.lua", "Core.lua", "CoreListeners.lua", "CoreDispatch.lua", "ChatLifecycle.lua" }) do
    assert(loadfile(path))("RothChat", env.ns)
  end
  env.core = _G.RothChat
  function env:Advance(seconds)
    self.now = self.now + (seconds or 0)
    local snapshot = {}
    for _, frame in ipairs(self.frames) do snapshot[#snapshot + 1] = frame end
    for _, frame in ipairs(snapshot) do
      local fn = frame:GetScript("OnUpdate")
      if fn then fn(frame, seconds or 0) end
    end
  end
  function env:Event(event, ...)
    local fn = self.core:GetScript("OnEvent")
    if self.core.events[event] and fn then fn(self.core, event, ...) end
  end
  return env
end

return Runtime
