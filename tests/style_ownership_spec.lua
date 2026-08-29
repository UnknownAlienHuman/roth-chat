-- Reversible Style ownership contract.

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
  texture.shown = true
  texture.alpha = 1
  texture.width = 16
  texture.height = 16
  texture.texCoord = { 0, 1, 0, 1 }
  texture.vertex = { 1, 1, 1, 1 }
  function texture:GetObjectType() return "Texture" end
  function texture:IsObjectType(kind) return kind == "Texture" end
  function texture:GetDrawLayer() return self.layer end
  function texture:GetTexture() return self.value end
  function texture:SetTexture(newValue) self.value = newValue end
  function texture:GetAtlas() return nil end
  function texture:GetTexCoord() return unpack(self.texCoord) end
  function texture:SetTexCoord(...) self.texCoord = { ... } end
  function texture:GetVertexColor() return unpack(self.vertex) end
  function texture:SetVertexColor(...) self.vertex = { ... } end
  function texture:GetBlendMode() return "BLEND" end
  function texture:SetBlendMode() end
  function texture:GetWidth() return self.width end
  function texture:GetHeight() return self.height end
  function texture:SetSize(width, height) self.width, self.height = width, height end
  function texture:GetAlpha() return self.alpha end
  function texture:SetAlpha(alpha) self.alpha = alpha end
  function texture:IsShown() return self.shown end
  function texture:Show() self.shown = true end
  function texture:Hide() self.shown = false end
  return texture
end

local function NewFontString()
  local text = NewPointObject()
  text.shown = true
  text.alpha = 1
  text.width = 80
  text.height = 16
  text.font = { "NativeFont", 14, "" }
  text.textColor = { 1, 1, 1, 1 }
  text.shadowColor = { 0, 0, 0, 0 }
  text.shadowOffset = { 0, 0 }
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
  function text:SetSize(width, height) self.width, self.height = width, height end
  function text:GetAlpha() return self.alpha end
  function text:SetAlpha(alpha) self.alpha = alpha end
  function text:IsShown() return self.shown end
  function text:Show() self.shown = true end
  function text:Hide() self.shown = false end
  return text
end

local function NewFrame(width, height)
  local frame = NewPointObject()
  frame.width = width
  frame.height = height
  frame.shown = true
  frame.alpha = 1
  frame.mouseEnabled = true
  function frame:GetWidth() return self.width end
  function frame:GetHeight() return self.height end
  function frame:SetWidth(value) self.width = value end
  function frame:SetHeight(value) self.height = value end
  function frame:SetSize(width2, height2) self.width, self.height = width2, height2 end
  function frame:GetAlpha() return self.alpha end
  function frame:SetAlpha(value) self.alpha = value end
  function frame:IsShown() return self.shown end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:IsMouseEnabled() return self.mouseEnabled end
  function frame:EnableMouse(value) self.mouseEnabled = value end
  return frame
end

local function NewButton()
  local button = NewFrame(32, 32)
  button.normal = NewTexture("native-normal")
  button.pushed = NewTexture("native-pushed")
  button.disabled = NewTexture("native-disabled")
  button.highlight = NewTexture("native-highlight")
  button.Flash = NewTexture("native-flash")
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
local scrollBar = NewFrame(8, 100)
local scrollButton = NewButton()
local buttonFrame = NewFrame(44, 100)
function buttonFrame:GetName() return "ChatFrame1ButtonFrame" end
local buttonFrameTexture = NewTexture("native-button-frame")
_G.ChatFrame1ButtonFrameBackground = buttonFrameTexture

local editBox = NewFrame(300, 32)
editBox.font = { "NativeEditFont", 14, "" }
editBox.textColor = { 0.8, 0.8, 0.8, 1 }
editBox.shadowColor = { 0, 0, 0, 0 }
editBox.shadowOffset = { 0, 0 }
editBox.insets = { 4, 4, 2, 2 }
editBox.blinkSpeed = 0.5
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
function editBox:GetRegions() return unpack(self.regions) end

local tab = NewFrame(64, 32)
local tabBase = NewTexture("native-tab", "BACKGROUND")
local tabText = NewFontString()
tab.regions = { tabBase, tabText }
tab.Text = tabText
function tab:GetRegions() return unpack(self.regions) end
function tab:GetFontString() return self.Text end

local chatFrame = NewFrame(400, 200)
chatFrame.font = { "NativeChatFont", 14, "" }
chatFrame.shadowColor = { 0, 0, 0, 0 }
chatFrame.shadowOffset = { 0, 0 }
chatFrame.Background = background
chatFrame.ScrollBar = scrollBar
chatFrame.ScrollToBottomButton = scrollButton
function chatFrame:GetName() return "ChatFrame1" end
function chatFrame:GetFont() return unpack(self.font) end
function chatFrame:SetFont(...) self.font = { ... } end
function chatFrame:GetShadowColor() return unpack(self.shadowColor) end
function chatFrame:SetShadowColor(...) self.shadowColor = { ... } end
function chatFrame:GetShadowOffset() return unpack(self.shadowOffset) end
function chatFrame:SetShadowOffset(...) self.shadowOffset = { ... } end

_G.ChatFrame1 = chatFrame
_G.ChatFrame1EditBox = editBox
_G.ChatFrame1Tab = tab
_G.ChatFrame1ButtonFrame = buttonFrame
_G.QuickJoinToastButton = nil
_G.ChatFrameChannelButton = nil
_G.ChatFrameMenuButton = nil
_G.strtrim = function(value) return value:match("^%s*(.-)%s*$") end

local fakeStyle = {
  name = "Style",
  OnEnable = function(self)
    chatFrame:SetFont("RothFont", 12, "")
    background:SetTexture(nil)
    background:SetAlpha(0)
    background:Hide()
    scrollBar:SetAlpha(0)
    scrollBar:EnableMouse(false)
    scrollBar:Hide()
    buttonFrame:SetWidth(28)
    buttonFrameTexture:SetTexture(nil)

    editBox:SetHeight(24)
    editBox:ClearAllPoints()
    editBox:SetPoint("BOTTOMLEFT", chatFrame, "BOTTOMLEFT", 0, -24)
    editBox:SetFont("RothFont", 12, "")
    editBox.underlay:SetTexture(nil)
    editBox.underlay:SetAlpha(0)
    editBox.underlay:Hide()
    editBox:SetBackdrop(nil)

    if not tab.__rothTabSkinned then
      tab.__rothTabSkinned = true
      tabBase:SetTexture(nil)
      tabBase:SetSize(0.001, 0.001)
      tabBase:Hide()
    end
    tab:SetHeight(20)

    if not scrollButton.__rothSkinned then
      scrollButton.__rothSkinned = true
      scrollButton:SetNormalTexture(nil)
      scrollButton:SetPushedTexture(nil)
      scrollButton:SetDisabledTexture(nil)
      scrollButton:SetHighlightTexture(nil)
      scrollButton:SetSize(24, 24)
      scrollButton:ClearAllPoints()
      scrollButton:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -2, 2)
      scrollButton.__scrollIcon = NewTexture("roth-icon")
      scrollButton.__glassBackdrop = NewFrame(24, 24)
      scrollButton.__rothHighlight = { NewTexture("hl1"), NewTexture("hl2"), NewTexture("hl3") }
    end
  end,
  OnDisable = function() end,
  Refresh = function(self, core) return self:OnEnable(core) end,
  OnLogin = function() end,
}

_G.RothChat = { modules = { Style = fakeStyle } }
local NS = {
  BORDER_HL_TEXTURE = "roth-highlight",
  CopyTable = function(source, destination)
    destination = destination or {}
    for key, value in pairs(source or {}) do destination[key] = value end
    return destination
  end,
  GetActiveChatFrames = function() return { chatFrame } end,
  GetChatFrames = function() return { chatFrame } end,
  Schedule = function(_, _, callback) callback() end,
  CancelScheduled = function() end,
  ApplyGlassBackdrop = function(button)
    if button.__glassBackdrop then button.__glassBackdrop:Show() end
  end,
  HideRothVisuals = function(frame)
    if not frame then return end
    if frame.__glassBackdrop then frame.__glassBackdrop:Hide() end
    if frame.__scrollIcon then frame.__scrollIcon:Hide() end
    if frame.__rothHighlight then
      for _, region in ipairs(frame.__rothHighlight) do region:Hide() end
    end
  end,
}

local listeners = {}
local active = true
local core = {
  Get = function(_, key)
    if key == "styleEnabled" then return true end
  end,
  IsModuleActive = function(_, name) return name == "Style" and active end,
  On = function(_, event, callback, owner)
    listeners[#listeners + 1] = { event = event, callback = callback, owner = owner }
  end,
  OffOwner = function(_, owner)
    for index = #listeners, 1, -1 do
      if listeners[index].owner == owner then table.remove(listeners, index) end
    end
  end,
}

assert(loadfile("Modules/StyleOwnership.lua"))("RothChat", NS)

fakeStyle:OnEnable(core)
assert(chatFrame.font[1] == "RothFont")
assert(background.value == nil and not background.shown)
assert(scrollBar.alpha == 0 and not scrollBar.mouseEnabled and not scrollBar.shown)
assert(buttonFrame.width == 28 and buttonFrameTexture.value == nil)
assert(editBox.height == 24 and editBox.font[1] == "RothFont" and editBox.underlay.value == nil)
assert(tab.height == 20 and tabBase.value == nil and not tabBase.shown)
assert(scrollButton.width == 24 and scrollButton.normal == nil)

active = false
fakeStyle:OnDisable(core)
assert(chatFrame.font[1] == "NativeChatFont")
assert(background.value == "native-background" and background.shown and background.alpha == 1)
assert(scrollBar.alpha == 1 and scrollBar.mouseEnabled and scrollBar.shown)
assert(buttonFrame.width == 44 and buttonFrameTexture.value == "native-button-frame")
assert(editBox.height == 32 and editBox.font[1] == "NativeEditFont" and editBox.underlay.value == "native-editbox")
assert(tab.height == 32 and tabBase.value == "native-tab" and tabBase.shown and tabBase.width == 16)
assert(scrollButton.width == 32 and scrollButton.normal and scrollButton.normal.value == "native-normal")
assert(not scrollButton.__scrollIcon.shown and not scrollButton.__glassBackdrop.shown)

-- The second enable must restyle one-time objects without creating replacements.
local originalIcon = scrollButton.__scrollIcon
local originalHighlights = scrollButton.__rothHighlight
active = true
fakeStyle:OnEnable(core)
assert(tab.height == 20 and tabBase.value == nil and not tabBase.shown)
assert(scrollButton.width == 24 and scrollButton.normal == nil)
assert(scrollButton.__scrollIcon == originalIcon and scrollButton.__scrollIcon.shown)
assert(scrollButton.__rothHighlight == originalHighlights)
for _, region in ipairs(originalHighlights) do assert(region.shown) end

active = false
fakeStyle:OnDisable(core)
assert(chatFrame.font[1] == "NativeChatFont")
assert(tabBase.value == "native-tab" and tabBase.shown)
assert(scrollButton.normal and scrollButton.normal.value == "native-normal")

print("style_ownership_spec: ok")
