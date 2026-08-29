-- Ticker primary-frame ownership and idle-work contract.

local registeredModule
local addMessageHook
local listeners = {}
local createdFrames = {}
local scheduled = {}

local function NewRegion()
  local region = { text = "", alpha = 1 }
  function region:SetPoint() end
  function region:ClearAllPoints() end
  function region:SetJustifyH() end
  function region:SetJustifyV() end
  function region:SetWordWrap() end
  function region:SetFont() end
  function region:SetShadowColor() end
  function region:SetShadowOffset() end
  function region:SetText(value) self.text = value end
  function region:GetText() return self.text end
  function region:SetTextColor() end
  function region:GetStringWidth() return #self.text * 6 end
  return region
end

local function NewTickerFrame()
  local frame = { alpha = 1, shown = false, scripts = {}, width = 300 }
  function frame:SetFrameStrata() end
  function frame:SetFrameLevel() end
  function frame:EnableMouse(value) self.mouseEnabled = value end
  function frame:CreateFontString() return NewRegion() end
  function frame:SetScript(name, callback) self.scripts[name] = callback end
  function frame:GetScript(name) return self.scripts[name] end
  function frame:SetPoint() end
  function frame:ClearAllPoints() end
  function frame:SetHeight(value) self.height = value end
  function frame:GetWidth() return self.width end
  function frame:SetAlpha(value) self.alpha = value end
  function frame:GetAlpha() return self.alpha end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:IsShown() return self.shown end
  return frame
end

_G.UIParent = {}
_G.LibStub = nil
_G.InCombatLockdown = function() return false end
_G.CreateFrame = function()
  local frame = NewTickerFrame()
  createdFrames[#createdFrames + 1] = frame
  return frame
end

local function NewChatFrame(index, active, alpha, mouseEnabled)
  local frame = {
    index = index,
    active = active,
    alpha = alpha,
    mouseEnabled = mouseEnabled,
    shown = active,
    isTemporary = false,
  }
  function frame:GetID() return self.index end
  function frame:GetName() return "ChatFrame" .. self.index end
  function frame:IsShown() return self.shown end
  function frame:GetAlpha() return self.alpha end
  function frame:SetAlpha(value) self.alpha = value end
  function frame:IsMouseEnabled() return self.mouseEnabled end
  function frame:EnableMouse(value) self.mouseEnabled = value end
  function frame:ScrollToBottom() self.scrolled = true end
  return frame
end

local primary = NewChatFrame(1, true, 0.65, true)
local inactiveConfigured = NewChatFrame(2, false, 0.4, false)
local secondary = NewChatFrame(3, true, 0.35, false)
_G.ChatFrame1 = primary
_G.ChatFrame2 = inactiveConfigured
_G.ChatFrame3 = secondary
_G.SELECTED_CHAT_FRAME = primary

_G.RothChat = {
  RegisterModule = function(_, module) registeredModule = module end,
}

local NS = {
  GetChatFrameIndex = function(frame) return frame and frame.index end,
  IsActiveChatFrame = function(frame) return frame and frame.active end,
  GetActiveChatFrames = function() return { primary, secondary } end,
  GetSelectedDockChatFrame = function() return primary end,
  IsDockedChatFrame = function() return false end,
  CanAccessValue = function() return true end,
  SafeToString = tostring,
  Utf8Len = function(text) return #text end,
  Utf8Sub = function(text, count) return text:sub(1, count) end,
  Clamp = function(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
  end,
  FadeTo = function(frame, target, _, callback)
    frame:SetAlpha(target)
    if callback then callback(frame) end
  end,
  StopFading = function() end,
  RunNextFrame = function(key, callback) scheduled[key] = callback end,
  Schedule = function(key, _, callback) scheduled[key] = callback end,
  CancelScheduled = function(key) scheduled[key] = nil end,
}

assert(loadfile("Modules/Ticker.lua"))("RothChat", NS)
local module = assert(registeredModule)

local values = {
  primaryChatIndex = 2,
  tickerEnabled = true,
  immersionEnabled = true,
  immersionChatAlphaShown = 0.8,
  immersionChatAlphaHidden = 0,
  immersionFadeInDuration = 0,
  immersionFadeOutDuration = 0,
  tickerAnimation = "none",
  tickerSpeed = 30,
  styleFontSize = 12,
  styleShadow = false,
}
local activeModules = { Controls = true, Ticker = true }

local core = {
  Get = function(_, key) return values[key] end,
  Set = function(_, key, value) values[key] = value end,
  IsModuleActive = function(_, name) return activeModules[name] and true or false end,
  EnsureChatLifecycleHooks = function() end,
  RegisterAddMessageHook = function(_, callback, owner)
    assert(owner == module)
    addMessageHook = callback
  end,
  UnregisterAddMessageHooks = function(_, owner)
    assert(owner == module)
    addMessageHook = nil
  end,
  OffOwner = function(_, owner)
    for event, entry in pairs(listeners) do
      if entry.owner == owner then listeners[event] = nil end
    end
  end,
  On = function(_, event, callback, owner)
    listeners[event] = { callback = callback, owner = owner }
  end,
  Defer = function(_, callback) callback() end,
}

module:Init(core)
module:OnEnable(core)

assert(values.primaryChatIndex == 1, "inactive configured slot must fall back to an active permanent frame")
assert(type(addMessageHook) == "function")
assert(primary.alpha == 0 and primary.mouseEnabled == false)
assert(secondary.alpha == 0.35 and secondary.mouseEnabled == false, "Ticker must not own non-primary frames")
assert(#createdFrames == 1)
assert(createdFrames[1]:GetScript("OnUpdate") == nil, "idle ticker must not keep an OnUpdate")

local visibility = assert(listeners.CONTROLS_VISIBILITY).callback
visibility(nil, core, primary, true, false, false)
assert(primary.alpha == 0.8 and primary.mouseEnabled == true)
visibility(nil, core, primary, false, false, false)
assert(primary.alpha == 0 and primary.mouseEnabled == false)

module:OnLogin(core)
addMessageHook(primary, "hidden message", 1, 1, 1)
assert(createdFrames[1].text:GetText() == "hidden message")
assert(createdFrames[1]:GetScript("OnUpdate") == nil, "non-animated ticker mode must remain idle between messages")

-- A non-primary visibility event cannot overwrite the secondary frame.
visibility(nil, core, secondary, true, false, false)
assert(secondary.alpha == 0.35 and secondary.mouseEnabled == false)

activeModules.Ticker = false
module:OnDisable(core)
assert(primary.alpha == 0.65 and primary.mouseEnabled == true, "disable must restore exact pre-Ticker state")
assert(secondary.alpha == 0.35 and secondary.mouseEnabled == false)
assert(addMessageHook == nil)

print("ticker_spec: ok")
