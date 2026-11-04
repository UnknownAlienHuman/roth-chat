-- Ticker primary-frame ownership and idle-work contract.

local registeredModule
local addMessageHook
local listeners = {}
local createdFrames = {}
local scheduled = {}
local deferred = {}
local fadeOwners = setmetatable({}, { __mode = "k" })
local inCombat = false
local unpackValues = unpack or table.unpack

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
_G.InCombatLockdown = function() return inCombat end
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
  CanAccessObject = function(frame) return frame ~= nil end,
  CanAccessValue = function() return true end,
  CanAccessAllValues = function() return true end,
  SafeNumber = function(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value or nil
  end,
  IsChatMessagingRestricted = function() return false end,
  GetChatFrameIndex = function(frame) return frame and frame.index end,
  IsActiveChatFrame = function(frame) return frame and frame.active end,
  IsDockedChatFrame = function() return false end,
  GetSelectedDockChatFrame = function() return primary end,
  GetActiveChatFrames = function() return { primary, secondary } end,
  SafeToString = tostring,
  SafeTrunc = function(text, count)
    if #text > count then return text:sub(1, count) .. "..." end
    return text
  end,
  Utf8Len = function(text) return #text end,
  Utf8Sub = function(text, count) return text:sub(1, count) end,
  Clamp = function(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
  end,
  FadeTo = function(frame, target, duration, callback, owner)
    if owner and duration and duration > 0 then
      fadeOwners[frame] = owner
      frame:SetAlpha((frame:GetAlpha() + target) / 2)
      return
    end
    fadeOwners[frame] = nil
    frame:SetAlpha(target)
    if callback then callback(frame) end
  end,
  StopFading = function(frame) fadeOwners[frame] = nil end,
  IsFading = function(frame) return fadeOwners[frame] ~= nil end,
  StopOwnedFade = function(frame, owner)
    if fadeOwners[frame] ~= owner then return false end
    fadeOwners[frame] = nil
    return true
  end,
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
  DeferKeyed = function(_, key, callback, ...)
    deferred[key] = { callback = callback, args = { ... } }
  end,
  CancelDeferred = function(_, key) deferred[key] = nil end,
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

-- Lockdown discards both active animation text and any queued message, releases
-- frame ownership, and never resumes old content after access returns.
local holdKey = createdFrames[1].__holdScheduleKey
assert(scheduled[holdKey], "the previous message should be in its bounded hold period")
scheduled[holdKey]()
values.tickerAnimation = "typewriter"
addMessageHook(primary, "pre-lockdown text", 1, 0.5, 0.25)
assert(createdFrames[1]:GetScript("OnUpdate") ~= nil)
addMessageHook(primary, "queued pre-lockdown text", 0.1, 0.2, 0.3)
local restriction = assert(listeners.CHAT_RESTRICTION_CHANGED).callback
restriction(nil, core, true)
assert(createdFrames[1].text:GetText() == "")
assert(createdFrames[1].fullText == "")
assert(not createdFrames[1]:IsShown())
assert(createdFrames[1]:GetScript("OnUpdate") == nil)
assert(primary.alpha == 0.65 and primary.mouseEnabled == true,
  "restriction entry must relinquish Ticker frame ownership")
addMessageHook(primary, "restricted text", 1, 1, 1)
restriction(nil, core, false)
assert(createdFrames[1].text:GetText() == "", "lockdown-cleared content must not resume")
visibility(nil, core, primary, false, false, false)
values.tickerAnimation = "none"
addMessageHook(primary, "post-lockdown text", 0.2, 0.4, 0.6)
assert(createdFrames[1].text:GetText() == "post-lockdown text")

-- Sustained bursts remain bounded and discard the oldest queued lines.
local tickerFrame = createdFrames[1]
if scheduled[holdKey] then scheduled[holdKey]() end
values.tickerAnimation = "typewriter"
addMessageHook(primary, "burst blocker", 1, 1, 1)
for index = 1, 250 do
  addMessageHook(primary, "bounded message " .. index, 1, 1, 1)
end
tickerFrame.isAnimating = false
tickerFrame.holding = false
module:ProcessQueue(core, primary)
assert(tickerFrame.fullText == "bounded message 151", "a full queue should retain only the latest 100 lines")

-- A line size cap bounds retained strings and work sent to FontStrings.
restriction(nil, core, true)
restriction(nil, core, false)
visibility(nil, core, primary, false, false, false)
addMessageHook(primary, string.rep("x", 5000), 1, 1, 1)
assert(#tickerFrame.fullText <= 1027, "ticker text must be truncated before display")

-- A non-primary visibility event cannot overwrite the secondary frame.
visibility(nil, core, secondary, true, false, false)
assert(secondary.alpha == 0.35 and secondary.mouseEnabled == false)

-- An older combat apply/cleanup must not run after a fast disable/re-enable.
inCombat = true
module:Refresh(core)
assert(deferred[module.__applyDeferredKey])
activeModules.Ticker = false
module:OnDisable(core)
assert(deferred[module.__applyDeferredKey] == nil)
assert(deferred[module.__cleanupDeferredKey])
activeModules.Ticker = true
module:OnEnable(core)
assert(deferred[module.__cleanupDeferredKey] == nil)
assert(deferred[module.__applyDeferredKey])
inCombat = false
local pendingApply = deferred[module.__applyDeferredKey]
deferred[module.__applyDeferredKey] = nil
pendingApply.callback(unpackValues(pendingApply.args))
assert(type(addMessageHook) == "function", "latest re-enable should own the AddMessage hook")

-- A later owner wins. Disable must not overwrite alpha/mouse values that no
-- longer match Ticker's last writes.
primary.alpha = 0.42
primary.mouseEnabled = true
activeModules.Ticker = false
module:OnDisable(core)
assert(primary.alpha == 0.42 and primary.mouseEnabled == true,
  "foreign frame state must survive Ticker teardown")
assert(secondary.alpha == 0.35 and secondary.mouseEnabled == false)
assert(addMessageHook == nil)

-- A replacement fade owned by another subsystem must survive Ticker teardown,
-- even when it begins at the last alpha written by Ticker.
activeModules.Ticker = true
values.immersionFadeInDuration = 1
values.immersionFadeOutDuration = 1
module:OnEnable(core)
local foreignOwner = {}
NS.FadeTo(primary, 0.9, 1, nil, foreignOwner)
assert(fadeOwners[primary] == foreignOwner)
local foreignAlpha = primary.alpha
activeModules.Ticker = false
module:OnDisable(core)
assert(fadeOwners[primary] == foreignOwner and primary.alpha == foreignAlpha,
  "Ticker teardown must not cancel or overwrite a replacement foreign fade")
fadeOwners[primary] = nil

-- An in-flight fade still owned by Ticker is cancelled and the exact snapshot
-- is restored, including a non-default alpha and mouse state.
primary.alpha = 0.42
primary.mouseEnabled = true
activeModules.Ticker = true
values.immersionFadeInDuration = 1
values.immersionFadeOutDuration = 1
module:OnEnable(core)
assert(fadeOwners[primary] == module and primary.alpha ~= 0.42)
activeModules.Ticker = false
module:OnDisable(core)
assert(fadeOwners[primary] == nil)
assert(primary.alpha == 0.42 and primary.mouseEnabled == true)

print("ticker_spec: ok")
