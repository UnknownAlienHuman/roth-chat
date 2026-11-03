-- Style owns its own reversible Blizzard-frame snapshots and can reapply them
-- after a setting toggle or module disable without stacking permanent hooks.
local hookCount = 0
local function HookSecure(target, methodName, callback)
  assert(type(target) == "table" and type(methodName) == "string" and type(callback) == "function")
  target.__hooks = target.__hooks or {}
  target.__hooks[methodName] = target.__hooks[methodName] or {}
  table.insert(target.__hooks[methodName], callback)
  hookCount = hookCount + 1
end
_G.hooksecurefunc = HookSecure
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.strtrim = function(value) return value:match("^%s*(.-)%s*$") end
_G.UIParent = {}

local function NewPointObject()
  local object = { points = {} }
  function object:GetNumPoints() return #self.points end
  function object:GetPoint(index)
    local point = self.points[index]
    return point[1], point[2], point[3], point[4], point[5]
  end
  function object:ClearAllPoints() self.points = {} end
  function object:SetPoint(point, relativeTo, relativePoint, x, y)
    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x, y }
  end
  return object
end

local function NewTexture(value, layer)
  local texture = NewPointObject()
  texture.value = value
  texture.layer = layer or "BACKGROUND"
  texture.shown, texture.alpha = true, 1
  texture.width, texture.height = 16, 16
  texture.texCoord, texture.vertex = { 0, 1, 0, 1 }, { 1, 1, 1, 1 }
  function texture:GetObjectType() return "Texture" end
  function texture:IsObjectType(kind) return kind == "Texture" end
  function texture:GetDrawLayer() return self.layer end
  function texture:GetTexture() return self.value end
  function texture:SetTexture(value) self.value = value end
  function texture:GetAtlas() return nil end
  function texture:GetTexCoord() return unpack(self.texCoord) end
  function texture:SetTexCoord(...) self.texCoord = { ... } end
  function texture:GetVertexColor() return unpack(self.vertex) end
  function texture:SetVertexColor(...) self.vertex = { ... } end
  function texture:GetBlendMode() return "BLEND" end
  function texture:SetBlendMode(value) self.blendMode = value end
  function texture:GetWidth() return self.width end
  function texture:GetHeight() return self.height end
  function texture:SetSize(width, height) self.width, self.height = width, height end
  function texture:GetAlpha() return self.alpha end
  function texture:SetAlpha(value) self.alpha = value end
  function texture:IsShown() return self.shown end
  function texture:Show() self.shown = true end
  function texture:Hide() self.shown = false end
  return texture
end

local function NewFrame(width, height)
  local frame = NewPointObject()
  frame.width, frame.height = width, height
  frame.shown, frame.alpha, frame.mouseEnabled = true, 1, true
  function frame:GetWidth() return self.width end
  function frame:GetHeight() return self.height end
  function frame:SetWidth(value) self.width = value end
  function frame:SetHeight(value) self.height = value end
  function frame:SetSize(w, h) self.width, self.height = w, h end
  function frame:GetAlpha() return self.alpha end
  function frame:SetAlpha(value) self.alpha = value end
  function frame:IsShown() return self.shown end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:IsMouseEnabled() return self.mouseEnabled end
  function frame:EnableMouse(value) self.mouseEnabled = value end
  function frame:GetObjectType() return "Frame" end
  function frame:HookScript(name, callback)
    self.__scripts = self.__scripts or {}
    self.__scripts[name] = self.__scripts[name] or {}
    table.insert(self.__scripts[name], callback)
  end
  return frame
end

local function NewFontString()
  local text = NewPointObject()
  text.shown, text.alpha = true, 1
  text.width, text.height = 80, 16
  text.font = { "NativeFont", 14, "" }
  text.textColor, text.shadowColor, text.shadowOffset = { 1, 1, 1, 1 }, { 0, 0, 0, 0 }, { 0, 0 }
  function text:GetObjectType() return "FontString" end
  function text:IsObjectType(kind) return kind == "FontString" end
  function text:GetText() return "General" end
  function text:GetFont() return unpack(self.font) end
  function text:SetFont(...) self.font = { ... } end
  function text:GetTextColor() return unpack(self.textColor) end
  function text:SetTextColor(...) self.textColor = { ... } end
  function text:GetShadowColor() return unpack(self.shadowColor) end
  function text:SetShadowColor(...) self.shadowColor = { ... } end
  function text:GetShadowOffset() return unpack(self.shadowOffset) end
  function text:SetShadowOffset(...) self.shadowOffset = { ... } end
  function text:GetWidth() return self.width end
  function text:GetHeight() return self.height end
  function text:SetSize(w, h) self.width, self.height = w, h end
  function text:GetAlpha() return self.alpha end
  function text:SetAlpha(value) self.alpha = value end
  function text:IsShown() return self.shown end
  function text:Show() self.shown = true end
  function text:Hide() self.shown = false end
  return text
end

local function NewButton()
  local button = NewFrame(32, 32)
  button.normal = NewTexture("native-normal")
  button.pushed = NewTexture("native-pushed")
  button.disabled = NewTexture("native-disabled")
  button.highlight = NewTexture("native-highlight")
  button.Flash = NewTexture("native-flash")
  function button:GetName() return "ChatFrame1ScrollToBottomButton" end
  function button:CreateTexture(_, layer) return NewTexture(nil, layer) end
  local function SetSlot(self, key, value)
    if value == nil then self[key] = nil
    elseif type(value) == "table" then self[key] = value
    else self[key] = NewTexture(value) end
  end
  function button:GetNormalTexture() return self.normal end
  function button:SetNormalTexture(value) SetSlot(self, "normal", value) end
  function button:GetPushedTexture() return self.pushed end
  function button:SetPushedTexture(value) SetSlot(self, "pushed", value) end
  function button:GetDisabledTexture() return self.disabled end
  function button:SetDisabledTexture(value) SetSlot(self, "disabled", value) end
  function button:GetHighlightTexture() return self.highlight end
  function button:SetHighlightTexture(value) SetSlot(self, "highlight", value) end
  return button
end

local background = NewTexture("native-background")
local buttonFrame = NewFrame(44, 100)
function buttonFrame:GetName() return "ChatFrame1ButtonFrame" end
local buttonFrameTexture = NewTexture("native-button-frame")
_G.ChatFrame1ButtonFrameBackground = buttonFrameTexture
local scrollBar = NewFrame(8, 100)
local scrollButton = NewButton()
local editBox = NewFrame(300, 32)
editBox.font = { "NativeEditFont", 14, "" }
editBox.textColor, editBox.shadowColor, editBox.shadowOffset = { .8, .8, .8, 1 }, { 0, 0, 0, 0 }, { 0, 0 }
editBox.insets = { 4, 4, 2, 2 }
editBox.blinkSpeed = .5
editBox.backdrop = { bgFile = "native-backdrop" }
editBox.underlay = NewTexture("native-editbox")
editBox.regions = { editBox.underlay }
editBox:SetPoint("BOTTOMLEFT", nil, "BOTTOMLEFT", 5, 5)
function editBox:GetName() return "ChatFrame1EditBox" end
function editBox:GetFont() return unpack(self.font) end
function editBox:SetFont(...) self.font = { ... } end
function editBox:GetTextColor() return unpack(self.textColor) end
function editBox:SetTextColor(...) self.textColor = { ... } end
function editBox:GetShadowColor() return unpack(self.shadowColor) end
function editBox:SetShadowColor(...) self.shadowColor = { ... } end
function editBox:GetShadowOffset() return unpack(self.shadowOffset) end
function editBox:SetShadowOffset(...) self.shadowOffset = { ... } end
function editBox:GetTextInsets() return unpack(self.insets) end
function editBox:SetTextInsets(...) self.insets = { ... } end
function editBox:GetBlinkSpeed() return self.blinkSpeed end
function editBox:SetBlinkSpeed(value) self.blinkSpeed = value end
function editBox:GetBackdrop() return self.backdrop end
function editBox:SetBackdrop(value) self.backdrop = value end
function editBox:GetBackdropColor() return 1, 1, 1, 1 end
function editBox:SetBackdropColor() end
function editBox:GetBackdropBorderColor() return 1, 1, 1, 1 end
function editBox:SetBackdropBorderColor() end
function editBox:GetNumRegions() return #self.regions end
function editBox:GetRegions() return unpack(self.regions) end
function editBox:HasFocus() return false end

local tab = NewFrame(64, 32)
local tabBase = NewTexture("native-tab", "BACKGROUND")
local tabText = NewFontString()
tab.regions, tab.Text = { tabBase, tabText }, tabText
function tab:GetRegions() return unpack(self.regions) end
function tab:GetFontString() return self.Text end

local chatFrame = NewFrame(400, 200)
chatFrame.font = { "NativeChatFont", 14, "" }
chatFrame.shadowColor, chatFrame.shadowOffset = { 0, 0, 0, 0 }, { 0, 0 }
chatFrame.Background, chatFrame.ScrollBar, chatFrame.ScrollToBottomButton = background, scrollBar, scrollButton
function chatFrame:GetName() return "ChatFrame1" end
function chatFrame:GetFont() return unpack(self.font) end
function chatFrame:SetFont(...) self.font = { ... } end
function chatFrame:GetShadowColor() return unpack(self.shadowColor) end
function chatFrame:SetShadowColor(...) self.shadowColor = { ... } end
function chatFrame:GetShadowOffset() return unpack(self.shadowOffset) end
function chatFrame:SetShadowOffset(...) self.shadowOffset = { ... } end
function chatFrame:GetParent() return _G.UIParent end
_G.ChatFrame1, _G.ChatFrame1EditBox, _G.ChatFrame1Tab, _G.ChatFrame1ButtonFrame = chatFrame, editBox, tab, buttonFrame
_G.QuickJoinToastButton, _G.ChatFrameChannelButton, _G.ChatFrameMenuButton = nil, nil, nil

local RothChat = {
  modules = {},
  RegisterModule = function(self, module) self.modules[module.name] = module end,
}
_G.RothChat = RothChat
local NS = {
  CanAccessObject = function(object) return object ~= nil end,
  CanAccessValue = function() return true end,
  CanAccessAllValues = function() return true end,
  SafeNumber = function(value, fallback) return type(value) == "number" and value or fallback end,
  CopyTable = function(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
  end,
  Clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end,
  GetChatFrames = function() return { chatFrame } end,
  RunNextFrame = function(_, callback) callback() end,
  CancelScheduled = function() end,
  ApplyGlassLook = function() end,
  UpdateGlassSize = function() end,
  ApplyGlassBackdrop = function(button)
    if not button.__glassBackdrop then
      local backdrop = NewFrame(24, 24)
      function backdrop:SetBackdropColor(...) self.color = { ... } end
      function backdrop:SetBackdropBorderColor(...) self.borderColor = { ... } end
      button.__glassBackdrop = backdrop
    end
    button.__glassBackdrop:Show()
  end,
  CreateHighlight = function(button)
    button.__rothHighlight = { NewTexture("roth-highlight") }
  end,
  HideRothVisuals = function(owner)
    if owner.__glassBackdrop then owner.__glassBackdrop:Hide() end
    if owner.__scrollIcon then owner.__scrollIcon:Hide() end
    for _, texture in ipairs(owner.__rothHighlight or {}) do texture:Hide() end
  end,
  BORDER_TEXTURE = "roth-border",
  BORDER_HL_TEXTURE = "roth-highlight",
  SCROLL_BTN_TEXTURE = "roth-scroll",
  SCROLL_ICONS = { TO_BOTTOM = { 0, 1, 0, 1 } },
}

local listeners = {}
local active = true
local deferred = {}
local profile = { styleEnabled = true, styleFont = "RothFont", styleFontSize = 12,
  styleFontOutline = "", styleShadow = true, styleBackground = false, editBoxPosition = "BOTTOM" }
local core = {
  Get = function(_, key) return profile[key] end,
  IsModuleActive = function(_, name) return name == "Style" and active end,
  EnsureChatLifecycleHooks = function() end,
  On = function(_, event, callback, owner) listeners[#listeners + 1] = { event, callback, owner } end,
  OffOwner = function() end,
  Defer = function(_, callback) callback() end,
  DeferKeyed = function(_, key, callback, ...)
    deferred[key] = { callback = callback, args = { ... } }
    return true
  end,
  CancelDeferred = function(_, key) deferred[key] = nil end,
}

assert(loadfile("Modules/Style.lua"))("RothChat", NS)
local style = RothChat.modules.Style
style:OnEnable(core)
assert(chatFrame.font[1] == "RothFont")
assert(background.alpha == 0 and not background.shown)
assert(scrollBar.alpha == 0 and not scrollBar.mouseEnabled and not scrollBar.shown)
assert(buttonFrame.width == 28 and buttonFrameTexture.value == nil)
assert(editBox.height == 24 and editBox.font[1] == "RothFont" and editBox.underlay.value == nil)
assert(tab.height == 20 and tabBase.value == nil and not tabBase.shown)
assert(scrollButton.width == 24 and scrollButton.normal == nil)

local firstScrollIcon = scrollButton.__scrollIcon
local firstTabHookCount = #(tab.__hooks.SetHeight or {})
local firstPointHookCount = #(tabText.__hooks.SetPoint or {})
profile.styleEnabled = false
style:Refresh(core)
assert(chatFrame.font[1] == "NativeChatFont")
assert(background.value == "native-background" and background.shown and background.alpha == 1)
assert(scrollBar.alpha == 1 and scrollBar.mouseEnabled and scrollBar.shown)
assert(buttonFrame.width == 44 and buttonFrameTexture.value == "native-button-frame")
assert(editBox.height == 32 and editBox.font[1] == "NativeEditFont" and editBox.underlay.value == "native-editbox")
assert(tab.height == 32 and tabBase.value == "native-tab" and tabBase.shown and tabBase.width == 16)
assert(scrollButton.width == 32 and scrollButton.normal and scrollButton.normal.value == "native-normal")
assert(not firstScrollIcon.shown)

profile.styleEnabled = true
style:Refresh(core)
assert(chatFrame.font[1] == "RothFont" and background.value == "native-background")
assert(tab.height == 20 and tabBase.value == nil and not tabBase.shown)
assert(scrollButton.width == 24 and scrollButton.normal == nil)
assert(scrollButton.__scrollIcon == firstScrollIcon and firstScrollIcon.shown)
assert(scrollButton.__rothHighlight[1].shown)
assert(#(tab.__hooks.SetHeight or {}) == firstTabHookCount)
assert(#(tabText.__hooks.SetPoint or {}) == firstPointHookCount)
assert(hookCount == firstTabHookCount + #(tab.__hooks.SetSize or {}) + firstPointHookCount)

-- Setting toggles can alternate during combat without retaining stale
-- apply/restore callbacks. Finish once disabled, then once enabled.
inCombat = true
for _ = 1, 4 do
  profile.styleEnabled = false
  style:Refresh(core)
  assert(deferred[style.__restoreDeferredKey])
  assert(not deferred[style.__applyDeferredKey])

  profile.styleEnabled = true
  style:Refresh(core)
  assert(not deferred[style.__restoreDeferredKey])
  assert(deferred[style.__applyDeferredKey])
  local queuedCount = 0
  for _ in pairs(deferred) do queuedCount = queuedCount + 1 end
  assert(queuedCount <= 1)
end

profile.styleEnabled = false
style:Refresh(core)
inCombat = false
local restoreJob = deferred[style.__restoreDeferredKey]
assert(restoreJob and not deferred[style.__applyDeferredKey])
deferred[style.__restoreDeferredKey] = nil
restoreJob.callback(unpack(restoreJob.args))
assert(chatFrame.font[1] == "NativeChatFont")
assert(tab.height == 32 and tabBase.value == "native-tab" and tabBase.shown)
assert(scrollButton.width == 32 and scrollButton.normal.value == "native-normal")

profile.styleEnabled = true
inCombat = true
style:Refresh(core)
assert(deferred[style.__applyDeferredKey] and not deferred[style.__restoreDeferredKey])
inCombat = false
local enabledJob = deferred[style.__applyDeferredKey]
assert(enabledJob)
deferred[style.__applyDeferredKey] = nil
enabledJob.callback(unpack(enabledJob.args))
assert(chatFrame.font[1] == "RothFont")
assert(tab.height == 20 and tabBase.value == nil and not tabBase.shown)
assert(scrollButton.width == 24 and scrollButton.normal == nil)

-- Core marks a module active only after OnEnable returns. Combat work must
-- remain queued across that boundary and apply once activation completes.
inCombat = true
active = false
style:OnDisable(core)
assert(deferred[style.__restoreDeferredKey])
style:OnEnable(core)
assert(not deferred[style.__restoreDeferredKey])
assert(deferred[style.__applyDeferredKey])

-- Repeated combat toggles replace/cancel the opposite continuation instead
-- of retaining one stale closure per lifecycle cycle.
for _ = 1, 5 do
  active = false
  style:OnDisable(core)
  assert(deferred[style.__restoreDeferredKey])
  style:OnEnable(core)
  assert(not deferred[style.__restoreDeferredKey])
  assert(deferred[style.__applyDeferredKey])
  local queuedCount = 0
  for _ in pairs(deferred) do queuedCount = queuedCount + 1 end
  assert(queuedCount <= 1)
end

active = true
inCombat = false
local applyJob = deferred[style.__applyDeferredKey]
assert(applyJob)
deferred[style.__applyDeferredKey] = nil
applyJob.callback(unpack(applyJob.args))
assert(chatFrame.font[1] == "RothFont")
assert(tab.height == 20 and tabBase.value == nil and not tabBase.shown)
assert(scrollButton.width == 24 and scrollButton.normal == nil)

active = false
style:OnDisable(core)
assert(chatFrame.font[1] == "NativeChatFont")
assert(background.value == "native-background" and background.shown)
assert(tabBase.value == "native-tab" and tabBase.shown)
assert(scrollButton.normal and scrollButton.normal.value == "native-normal")

print("style_ownership_spec: ok")
