-- Dock geometry ownership contract.

local registeredModule
local runtimeActive = true
local layoutListener

_G.InCombatLockdown = function() return false end
_G.RothChat = {
  RegisterModule = function(_, module) registeredModule = module end,
}

local function NewFrame(height)
  local frame = { height = height, points = {} }
  function frame:GetHeight() return self.height end
  function frame:SetHeight(value) self.height = value end
  function frame:GetNumPoints() return #self.points end
  function frame:GetPoint(index)
    local point = self.points[index]
    return point[1], point[2], point[3], point[4], point[5]
  end
  function frame:ClearAllPoints() self.points = {} end
  function frame:SetPoint(point, relativeTo, relativePoint, x, y)
    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x, y }
  end
  return frame
end

local dock = NewFrame(37)
local scrollFrame = NewFrame(31)
local child = NewFrame(29)
scrollFrame.child = child
scrollFrame:SetPoint("TOPLEFT", dock, "TOPLEFT", 4, -3)
dock.scrollFrame = scrollFrame
_G.GeneralDockManager = dock

local NS = {
  RunNextFrame = function(_, callback) callback() end,
  CancelScheduled = function() end,
}

assert(loadfile("Modules/Dock.lua"))("RothChat", NS)
local module = assert(registeredModule)

local core = {
  IsModuleActive = function(_, name) return name == "Dock" and runtimeActive end,
  EnsureChatLifecycleHooks = function() end,
  Defer = function(_, callback) callback() end,
  On = function(_, event, callback)
    if event == "CHAT_LAYOUT_CHANGED" then layoutListener = callback end
  end,
}

module:Init(core)
module:OnEnable(core)
assert(dock.height == 20)
assert(scrollFrame.height == 20)
assert(child.height == 20)
assert(#scrollFrame.points == 1)
assert(scrollFrame.points[1][1] == "BOTTOMRIGHT")

assert(type(layoutListener) == "function")
layoutListener(nil, core)
assert(dock.height == 20)

runtimeActive = false
module:OnDisable(core)
assert(dock.height == 37)
assert(scrollFrame.height == 31)
assert(child.height == 29)
assert(#scrollFrame.points == 1)
assert(scrollFrame.points[1][1] == "TOPLEFT")
assert(scrollFrame.points[1][4] == 4 and scrollFrame.points[1][5] == -3)

-- A later writer owns the geometry if it changes Roth's 20px marker.
runtimeActive = true
module:OnEnable(core)
assert(dock.height == 20)
dock:SetHeight(25)
runtimeActive = false
module:OnDisable(core)
assert(dock.height == 25, "disable must not overwrite a later geometry owner")

print("dock_spec: ok")
