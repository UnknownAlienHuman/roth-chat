-- Blizzard Settings registration is lazy, one-shot, and resilient to load order.
local originalSettings, originalEventUtil, originalCreateFrame = Settings, EventUtil, CreateFrame
local continuations = {}
local frames = {}
local buildCalls = 0

Settings = nil
EventUtil = {
  ContinueOnAddOnLoaded = function(name, callback)
    assert(name == "Blizzard_Settings")
    continuations[#continuations + 1] = callback
  end,
}
CreateFrame = function()
  local frame = { events = {}, scripts = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:SetScript(name, callback) self.scripts[name] = callback end
  frames[#frames + 1] = frame
  return frame
end

local core = {
  InitOptions = function(self)
    assert(Settings, "category construction must wait for Blizzard_Settings")
    buildCalls = buildCalls + 1
    self.optionsCategoryID = 42
  end,
}
_G.RothChat = core
local NS = {
  CanAccessValue = function() return true end,
  SafeCall = function(_, callback, ...)
    local ok = pcall(callback, ...)
    return ok
  end,
}

assert(loadfile("OptionsBootstrap.lua"))("RothChat", NS)
assert(#continuations == 1 and buildCalls == 0, "one late-load continuation must be registered")
Settings = {}
continuations[1]()
continuations[1]()
assert(buildCalls == 1 and core.optionsCategoryID == 42, "category registration must be idempotent")
assert(core.InitOptions ~= nil, "bootstrap must not replace the Options owner")

-- Fallback ADDON_LOADED listener is bounded and ignores unrelated addons.
Settings = nil
EventUtil = nil
frames = {}
buildCalls = 0
local fallbackCore = {
  InitOptions = function(self)
    assert(Settings)
    buildCalls = buildCalls + 1
    self.optionsCategoryID = 7
  end,
}
_G.RothChat = fallbackCore
assert(loadfile("OptionsBootstrap.lua"))("RothChat", NS)
assert(#frames == 1 and frames[1].events.ADDON_LOADED)
local onEvent = assert(frames[1].scripts.OnEvent)
onEvent(frames[1], "ADDON_LOADED", "Other_AddOn")
assert(buildCalls == 0 and frames[1].events.ADDON_LOADED)
Settings = {}
onEvent(frames[1], "ADDON_LOADED", "Blizzard_Settings")
assert(buildCalls == 1 and fallbackCore.optionsCategoryID == 7)
assert(not frames[1].events.ADDON_LOADED and frames[1].scripts.OnEvent == nil,
  "fallback listener must retire after registration")

Settings, EventUtil, CreateFrame = originalSettings, originalEventUtil, originalCreateFrame
print("options_bootstrap_spec: ok")
