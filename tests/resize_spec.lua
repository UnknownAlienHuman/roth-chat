-- Temporary resize ownership contract.

local registeredModule
local runtimeActive = true
local createdGrip
local timers = {}

_G.InCombatLockdown = function() return false end
_G.GetTime = function() return 100 end
_G.GameTooltip = nil
_G.RothChat = {
  RegisterModule = function(_, module) registeredModule = module end,
}

_G.C_Timer = {
  NewTimer = function(_, callback)
    local timer = { callback = callback, cancelled = false }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
  end,
  NewTicker = function(_, callback)
    local ticker = { callback = callback, cancelled = false }
    function ticker:Cancel() self.cancelled = true end
    return ticker
  end,
}

local function NewTexture()
  local texture = { value = "texture" }
  function texture:SetAllPoints() end
  function texture:SetTexture(value) self.value = value end
  function texture:GetTexture() return self.value end
  function texture:SetTexCoord() end
  function texture:SetVertexColor() end
  return texture
end

local function NewGrip()
  local grip = { scripts = {}, shown = false }
  function grip:SetSize() end
  function grip:SetPoint() end
  function grip:SetFrameLevel() end
  function grip:EnableMouse() end
  function grip:RegisterForClicks() end
  function grip:CreateTexture() return NewTexture() end
  function grip:CreateFontString()
    return {
      SetPoint = function() end,
      SetText = function() end,
      SetTextColor = function() end,
    }
  end
  function grip:SetScript(name, callback) self.scripts[name] = callback end
  function grip:Show() self.shown = true end
  function grip:Hide() self.shown = false end
  return grip
end

_G.CreateFrame = function()
  createdGrip = NewGrip()
  return createdGrip
end

local frame = {
  width = 400,
  height = 200,
  active = true,
  resizing = false,
}
function frame:GetID() return 1 end
function frame:GetName() return "ChatFrame1" end
function frame:IsResizable() return true end
function frame:GetFrameLevel() return 5 end
function frame:GetSize() return self.width, self.height end
function frame:SetSize(width, height) self.width, self.height = width, height end
function frame:GetResizeBounds() return 176, 64, 800, 600 end
function frame:StartSizing() self.resizing = true end
function frame:StopMovingOrSizing() self.resizing = false end
function frame:ScrollToBottom() end

local NS = {
  GetChatFrameIndex = function(candidate) return candidate == frame and 1 or nil end,
  IsActiveChatFrame = function(candidate) return candidate == frame and frame.active end,
  GetActiveChatFrames = function() return frame.active and { frame } or {} end,
}

assert(loadfile("Modules/Resize.lua"))("RothChat", NS)
local module = assert(registeredModule)

local listeners = {}
local core = {
  IsModuleActive = function(_, name) return name == "Resize" and runtimeActive end,
  EnsureChatLifecycleHooks = function() end,
  RegisterHoverFrame = function() end,
  UnregisterHoverFrame = function() end,
  On = function(_, event, callback) listeners[event] = callback end,
  Defer = function(_, callback) callback() end,
}

module:Init(core)
module:OnEnable(core)
assert(createdGrip and createdGrip.shown)
assert(type(createdGrip.scripts.OnMouseDown) == "function")
assert(type(createdGrip.scripts.OnMouseUp) == "function")

createdGrip.scripts.OnMouseDown()
assert(frame.resizing)
frame:SetSize(520, 310)
createdGrip.scripts.OnMouseUp()
assert(not frame.resizing)
assert(#timers == 1 and not timers[1].cancelled)

runtimeActive = false
module:OnDisable(core)
assert(timers[1].cancelled)
assert(frame.width == 400 and frame.height == 200, "disable must restore the owned temporary size")
assert(not createdGrip.shown)

-- External/Edit Mode geometry becomes the next base after layout refresh.
frame:SetSize(460, 240)
runtimeActive = true
module:OnEnable(core)
assert(type(listeners.CHAT_LAYOUT_CHANGED) == "function")
listeners.CHAT_LAYOUT_CHANGED(nil, core)
createdGrip.scripts.OnMouseDown()
frame:SetSize(600, 360)
createdGrip.scripts.OnMouseUp()
runtimeActive = false
module:OnDisable(core)
assert(frame.width == 460 and frame.height == 240, "new external geometry must replace the stale session base")

-- Closed/reused frames lose their old ownership state.
frame.active = false
assert(type(listeners.CHAT_FRAME_CLOSED) == "function")
listeners.CHAT_FRAME_CLOSED(nil, core, frame)
frame:SetSize(500, 250)
frame.active = true
runtimeActive = true
module:OnEnable(core)
createdGrip.scripts.OnMouseDown()
frame:SetSize(650, 400)
createdGrip.scripts.OnMouseUp()
runtimeActive = false
module:OnDisable(core)
assert(frame.width == 500 and frame.height == 250)

print("resize_spec: ok")
