-- ChatBar combat deferral and safe target selection contract.

local registeredModule
local deferred = {}
local canceled = {}
local inCombat = true
local framesCreated = {}
local hoverOwners = {}
local inaccessible = {}

_G.InCombatLockdown = function() return inCombat end
_G.GetTime = function() return 10 end
_G.ChatFrameUtil = { OpenChat = function() end }
_G.LibStub = nil
_G.GameTooltip = nil
_G.RothChat = {
  RegisterModule = function(_, module) registeredModule = module end,
}

local function NewRegion()
  return {
    SetPoint = function() end,
    SetText = function() end,
    SetTextColor = function() end,
    SetShadowColor = function() end,
    SetShadowOffset = function() end,
    SetFont = function() end,
  }
end

local function NewFrame(kind)
  local frame = { kind = kind, scripts = {}, shown = false, buttons = nil, level = 5 }
  function frame:SetFrameStrata() end
  function frame:SetFrameLevel(value) self.level = value end
  function frame:GetFrameLevel() return self.level end
  function frame:SetScript(name, callback) self.scripts[name] = callback end
  function frame:RegisterForClicks() end
  function frame:CreateFontString() return NewRegion() end
  function frame:SetSize(width, height) self.width, self.height = width, height end
  function frame:ClearAllPoints() self.points = {} end
  function frame:SetPoint(...) self.points = { ... } end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:IsShown() return self.shown end
  return frame
end

_G.CreateFrame = function(kind)
  local frame = NewFrame(kind)
  framesCreated[#framesCreated + 1] = frame
  return frame
end

local chatFrame = { index = 1, level = 10 }
function chatFrame:GetFrameLevel() return self.level end
function chatFrame:IsShown() return true end
_G.ChatFrame1 = chatFrame
_G.ChatFrame2 = { index = 2, level = 10 }
inaccessible[_G.ChatFrame2] = true

local NS = {
  CanAccessObject = function(object) return not inaccessible[object] end,
  CanAccessAllValues = function() return true end,
  SafeNumber = function(value, fallback) return type(value) == "number" and value or fallback end,
  IsActiveChatFrame = function(frame) return frame == chatFrame end,
  GetActiveChatFrames = function() return { chatFrame } end,
  GetSelectedDockChatFrame = function() return nil end,
  GetChatFrameIndex = function(frame) return frame.index end,
  ApplyGlassBackdrop = function() end,
  CreateHighlight = function() end,
}

assert(loadfile("Modules/ChatBar.lua"))("RothChat", NS)
local module = assert(registeredModule)
local values = {
  chatBarEnabled = true,
  chatBarAttachTo = 2, -- inaccessible configured slot; fall back to ChatFrame1
  chatBarButtonSize = 18,
  chatBarSpacing = 4,
  chatBarAnchor = "LEFT",
  styleFontSize = 12,
  styleShadow = true,
}
local core = {
  Get = function(_, key) return values[key] end,
  IsModuleActive = function() return active end,
  EnsureChatLifecycleHooks = function() end,
  RegisterHoverFrame = function(_, owner, accessory) hoverOwners[owner] = accessory end,
  UnregisterHoverFrame = function(_, owner) hoverOwners[owner] = nil end,
  On = function() end,
  DeferKeyed = function(_, key, callback, ...)
    deferred[key] = { callback = callback, args = { ... } }
  end,
  CancelDeferred = function(_, key)
    canceled[key] = true
    deferred[key] = nil
  end,
}
active = true

module:Init(core)
module:OnEnable(core)
assert(#framesCreated == 0, "protected chat layout must wait until combat ends")
local applyKey = module.__chatBarApplyKey
assert(applyKey and deferred[applyKey], "combat apply should be keyed")

-- Disable cancels the queued apply. A later enable schedules one current apply.
active = false
module:OnDisable(core)
assert(deferred[applyKey] == nil)
active = true
module:OnEnable(core)
assert(deferred[applyKey])
inCombat = false
local pending = deferred[applyKey]
deferred[applyKey] = nil
pending.callback(table.unpack(pending.args))

assert(#framesCreated == 11, "one bar and ten channel buttons should be created")
assert(framesCreated[1].shown)
assert(framesCreated[1].__rothAttachedChatFrame == chatFrame, "fallback must skip an inaccessible configured slot")
assert(hoverOwners[chatFrame] == framesCreated[1])

active = false
module:OnDisable(core)
assert(not framesCreated[1].shown)
assert(hoverOwners[chatFrame] == nil)

print("chatbar_spec: ok")
