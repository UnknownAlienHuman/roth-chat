-- Controls owns wheel, clipping, accessory alpha and accessory mouse state
-- while active, then restores only properties that still carry its writes.
local unpackValues = unpack or table.unpack
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.UIParent = {}
_G.GetTime = function() return 1 end
_G.IsShiftKeyDown = function() return false end
_G.CreateFrameCalls = 0

local function newFrame(name)
  local frame = { name = name, shown = true, mouseEnabled = true, mouseWheelEnabled = false,
    clipsChildren = false, alpha = 1, width = 400, height = 200, scripts = {}, points = {} }
  function frame:GetName() return self.name end
  function frame:IsShown() return self.shown end
  function frame:IsVisible() return self.shown end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:SetAlpha(value) self.alpha = value end
  function frame:GetAlpha() return self.alpha end
  function frame:EnableMouse(value) self.mouseEnabled = value end
  function frame:IsMouseEnabled() return self.mouseEnabled end
  function frame:EnableMouseWheel(value)
    self.mouseWheelChanges = (self.mouseWheelChanges or 0) + 1
    self.mouseWheelEnabled = value
  end
  function frame:IsMouseWheelEnabled() return self.mouseWheelEnabled end
  function frame:SetClipsChildren(value)
    self.clipChanges = (self.clipChanges or 0) + 1
    self.clipsChildren = value
  end
  function frame:GetClipsChildren() return self.clipsChildren end
  function frame:SetScript(name, callback) self.scripts[name] = callback end
  function frame:GetScript(name) return self.scripts[name] end
  function frame:HookScript(name, callback)
    self.hooks = self.hooks or {}
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], callback)
  end
  function frame:SetFrameStrata(value) self.strata = value end
  function frame:SetFrameLevel(value) self.level = value end
  function frame:SetAllPoints(value) self.allPoints = value end
  function frame:SetSize(width, height) self.width, self.height = width, height end
  function frame:SetPoint(...)
    self.points[#self.points + 1] = { ... }
  end
  function frame:ClearAllPoints() self.points = {} end
  function frame:SetBackdrop(value) self.backdrop = value end
  function frame:CreateTexture()
    local texture = newFrame("texture")
    function texture:SetTexture(value) self.texture = value end
    function texture:SetTexCoord(...) self.texCoord = { ... } end
    return texture
  end
  function frame:IsMouseOver() return false end
  function frame:GetRect() return 0, 0, self.width, self.height end
  function frame:GetFont() return "Font", 12 end
  function frame:GetSpacing() return 0 end
  function frame:GetScrollOffset() return 0 end
  function frame:ScrollToTop() end
  function frame:ScrollToBottom() end
  function frame:ScrollUp() end
  function frame:ScrollDown() end
  return frame
end

local originalWheelCalls = 0
local function originalWheel(_, delta) originalWheelCalls = originalWheelCalls + delta end
local chatFrame = newFrame("ChatFrame1")
chatFrame.scripts.OnMouseWheel = originalWheel
chatFrame.FontStringContainer = newFrame("FontStringContainer")
_G.ChatFrame1 = chatFrame
local buttonFrame = newFrame("ChatFrame1ButtonFrame")
buttonFrame.alpha = 0.35
buttonFrame.mouseEnabled = false
_G.ChatFrame1ButtonFrame = buttonFrame
function _G.ChatFrame1ButtonFrame:GetName() return "ChatFrame1ButtonFrame" end

_G.CreateFrame = function(kind, name, parent)
  _G.CreateFrameCalls = _G.CreateFrameCalls + 1
  local frame = newFrame(name)
  frame.kind, frame.parent = kind, parent
  return frame
end

local listeners = {}
local deferred = {}
local active = true
local core = {
  Get = function(_, key)
    if key == "hoverControls" then return true end
    if key == "smoothScrollEnabled" then return true end
    if key == "smoothScrollDuration" then return .25 end
    if key == "hoverAlphaShown" then return 1 end
    if key == "hoverAlphaHidden" then return 0 end
    if key == "hoverFadeDelay" then return 0 end
    if key == "hoverFadeInDuration" or key == "hoverFadeOutDuration" then return .1 end
    return nil
  end,
  IsModuleActive = function(_, name) return name == "Controls" and active end,
  EnsureChatLifecycleHooks = function() end,
  RegisterAddMessageHook = function() end,
  UnregisterAddMessageHooks = function() end,
  QueueChatLifecycleRefresh = function() end,
  DeferKeyed = function(_, key, callback, ...)
    deferred[key] = { callback = callback, args = { ... } }
    return true
  end,
  CancelDeferred = function(_, key) deferred[key] = nil end,
  On = function(_, event, callback, owner) listeners[#listeners + 1] = { event, callback, owner } end,
  OffOwner = function(_, owner)
    for index = #listeners, 1, -1 do
      if listeners[index][3] == owner then table.remove(listeners, index) end
    end
  end,
  Emit = function() end,
}
local RothChat = {
  modules = {},
  RegisterModule = function(self, module) self.modules[module.name] = module end,
}
_G.RothChat = RothChat
local fadeOwners = setmetatable({}, { __mode = "k" })
local NS = {
  CanAccessObject = function(object) return object ~= nil end,
  CanAccessValue = function() return true end,
  SafeNumber = function(value, fallback)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
      and value or fallback
  end,
  GetChatFrames = function() return { chatFrame } end,
  GetActiveChatFrames = function() return { chatFrame } end,
  IsDockedChatFrame = function() return false end,
  GetSelectedDockChatFrame = function() return chatFrame end,
  RunNextFrame = function(_, callback) callback(); return true end,
  Schedule = function() return true end,
  CancelScheduled = function() end,
  Clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end,
  FadeTo = function(frame, alpha, duration, callback, owner)
    frame:SetAlpha(alpha)
    fadeOwners[frame] = duration and duration > 0 and { owner = owner } or nil
    if callback and (not duration or duration == 0) then callback(frame) end
    return true
  end,
  IsFading = function(frame) return fadeOwners[frame] ~= nil end,
  StopOwnedFade = function(frame, owner)
    local fade = fadeOwners[frame]
    if not fade or fade.owner ~= owner then return false end
    fadeOwners[frame] = nil
    return true
  end,
  StopFading = function(frame, alpha)
    fadeOwners[frame] = nil
    if type(alpha) == "number" then frame:SetAlpha(alpha) end
  end,
  ApplyGlassBackdrop = function(frame) frame.glass = true end,
  CreateHighlight = function(frame) frame.highlight = true end,
  ICONS_TEXTURE = "icons",
  BUTTON_ICONS = { MINIMIZE = { 0, .5, 0, .5 }, MAXIMIZE = { .5, 1, .5, 1 } },
}

assert(loadfile("Modules/Controls.lua"))("RothChat", NS)
local controls = RothChat.modules.Controls
controls:OnEnable(core)
assert(type(chatFrame.scripts.OnMouseWheel) == "function" and chatFrame.scripts.OnMouseWheel ~= originalWheel)
assert(chatFrame.mouseWheelEnabled and chatFrame.clipsChildren)
assert(buttonFrame.alpha == 0 and buttonFrame.mouseEnabled == false)
assert(fadeOwners[buttonFrame] and fadeOwners[buttonFrame].owner == controls)
local ownedHandler = chatFrame.scripts.OnMouseWheel
local scrollDriver = chatFrame.__rothSmoothScroll
local frameCountAfterEnable = _G.CreateFrameCalls

active = false
inCombat = true
controls:OnDisable(core)
core:OffOwner(controls)
assert(chatFrame.scripts.OnMouseWheel == ownedHandler)
assert(chatFrame.mouseWheelEnabled and chatFrame.clipsChildren)
inCombat = false
for key, job in pairs(deferred) do
  deferred[key] = nil
  job.callback(unpackValues(job.args))
end
assert(chatFrame.scripts.OnMouseWheel == originalWheel)
assert(chatFrame.mouseWheelEnabled == false and chatFrame.clipsChildren == false)
assert(chatFrame.__rothSmoothScroll == scrollDriver)
assert(buttonFrame.alpha == 0.35 and buttonFrame.mouseEnabled == false,
  "disable must restore the exact pre-Controls presentation snapshot")
assert(fadeOwners[buttonFrame] == nil)

-- The retained guarded handler must not create new frames or replace a later
-- owner's script during disable cleanup.
active = true
controls:OnEnable(core)
assert(chatFrame.scripts.OnMouseWheel == ownedHandler)
assert(chatFrame.__rothSmoothScroll == scrollDriver)
assert(_G.CreateFrameCalls == frameCountAfterEnable)

-- Repeated combat toggles retain at most the latest activation continuation.
inCombat = true
for cycle = 1, 5 do
  active = false
  controls:OnDisable(core)
  assert(deferred[controls.__applyDeferredKey] == nil)
  assert(deferred[controls.__refreshDeferredKey] == nil)
  assert(deferred[controls.__restoreDeferredKey])
  active = true
  controls:OnEnable(core)
  assert(deferred[controls.__restoreDeferredKey] == nil)
  assert(deferred[controls.__applyDeferredKey])
  if cycle < 5 then
    for index = #listeners, 1, -1 do
      local listener = listeners[index]
      if listener[1] == "CHAT_LAYOUT_CHANGED" then
        listener[2](nil, core)
        break
      end
    end
    assert(deferred[controls.__refreshDeferredKey])
  end
  local queuedCount = 0
  for _ in pairs(deferred) do queuedCount = queuedCount + 1 end
  assert(queuedCount <= 2)
end
inCombat = false
local latestApply = deferred[controls.__applyDeferredKey]
assert(latestApply)
deferred[controls.__applyDeferredKey] = nil
latestApply.callback(unpackValues(latestApply.args))
assert(chatFrame.scripts.OnMouseWheel == ownedHandler)
assert(chatFrame.__rothSmoothScroll == scrollDriver)
assert(_G.CreateFrameCalls == frameCountAfterEnable)

-- Later direct presentation writes win over Controls teardown.
fadeOwners[buttonFrame] = nil -- model completion of Controls' last fade
buttonFrame.alpha = 0.42
buttonFrame.mouseEnabled = true
active = false
controls:OnDisable(core)
assert(buttonFrame.alpha == 0.42 and buttonFrame.mouseEnabled == true,
  "foreign direct alpha/mouse changes must survive Controls teardown")

-- A later replacement fade also wins and must remain active.
active = true
controls:OnEnable(core)
local foreignOwner = {}
NS.FadeTo(buttonFrame, 0.9, 1, nil, foreignOwner)
active = false
controls:OnDisable(core)
assert(buttonFrame.alpha == 0.9)
assert(fadeOwners[buttonFrame] and fadeOwners[buttonFrame].owner == foreignOwner,
  "Controls teardown must not cancel a replacement foreign fade")
fadeOwners[buttonFrame] = nil

-- Wheel/clipping restoration remains conflict-safe as well.
active = true
controls:OnEnable(core)
local foreignWheelCalls = 0
local function foreignWheel() foreignWheelCalls = foreignWheelCalls + 1 end
chatFrame:SetScript("OnMouseWheel", foreignWheel)
chatFrame.mouseWheelEnabled = false
chatFrame.clipsChildren = false
local wheelChanges, clipChanges = chatFrame.mouseWheelChanges, chatFrame.clipChanges
active = false
controls:OnDisable(core)
assert(chatFrame.scripts.OnMouseWheel == foreignWheel)
assert(chatFrame.mouseWheelEnabled == false and chatFrame.clipsChildren == false)
assert(chatFrame.mouseWheelChanges == wheelChanges and chatFrame.clipChanges == clipChanges,
  "disable must not overwrite another owner's wheel or clipping state")

print("controls_ownership_spec: ok")
