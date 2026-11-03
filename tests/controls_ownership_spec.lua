-- Controls owns the chat-frame wheel script while enabled, then restores the
-- prior script, wheel enablement and clipping state without building a second
-- smooth-scroll driver on re-enable.
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
  function frame:EnableMouseWheel(value) self.mouseWheelEnabled = value end
  function frame:IsMouseWheelEnabled() return self.mouseWheelEnabled end
  function frame:SetClipsChildren(value) self.clipsChildren = value end
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
_G.ChatFrame1ButtonFrame = newFrame("ChatFrame1ButtonFrame")
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
  Defer = function(_, callback) deferred[#deferred + 1] = callback end,
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
local NS = {
  CanAccessObject = function(object) return object ~= nil end,
  CanAccessValue = function() return true end,
  GetChatFrames = function() return { chatFrame } end,
  GetActiveChatFrames = function() return { chatFrame } end,
  IsDockedChatFrame = function() return false end,
  GetSelectedDockChatFrame = function() return chatFrame end,
  RunNextFrame = function(_, callback) callback() end,
  Schedule = function() end,
  CancelScheduled = function() end,
  Clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end,
  FadeTo = function(frame, alpha) frame:SetAlpha(alpha) end,
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
for index = 1, #deferred do deferred[index]() end
deferred = {}
assert(chatFrame.scripts.OnMouseWheel == originalWheel)
assert(chatFrame.mouseWheelEnabled == false and chatFrame.clipsChildren == false)
assert(chatFrame.__rothSmoothScroll == scrollDriver)

-- The retained guarded handler must not create new frames or replace a later
-- owner's script during disable cleanup.
active = true
controls:OnEnable(core)
assert(chatFrame.scripts.OnMouseWheel == ownedHandler)
assert(chatFrame.__rothSmoothScroll == scrollDriver)
assert(_G.CreateFrameCalls == frameCountAfterEnable)
local foreignWheelCalls = 0
local function foreignWheel() foreignWheelCalls = foreignWheelCalls + 1 end
chatFrame:SetScript("OnMouseWheel", foreignWheel)
active = false
controls:OnDisable(core)
assert(chatFrame.scripts.OnMouseWheel == foreignWheel)
assert(chatFrame.mouseWheelEnabled == false and chatFrame.clipsChildren == false)

print("controls_ownership_spec: ok")
