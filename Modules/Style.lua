-- RothChat - Style module
-- Chat typography and Roth/Glass presentation for Blizzard chat frames.

local _, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Style",
  defaultEnabled = true,
  description = "Fonts, shadows, and ls_Glass visual style.",
}
M.__applyDeferredKey = {}
M.__restoreDeferredKey = {}

local backgrounds = {}
local styleActive = false
local listenersRegistered = false
local QueueApplyAll

local DEFAULT_BG_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_BORDER_TEXTURE = NS.BORDER_TEXTURE
local DEFAULT_EDIT_CURSOR_BLINK = 0.85
local EDIT_ALPHA_IDLE = 0.0
local EDIT_ALPHA_FOCUS = 0.22

local BUTTON_FRAME_TEXTURES = {
  "Background",
  "TopLeftTexture",
  "TopRightTexture",
  "BottomLeftTexture",
  "BottomRightTexture",
  "TopTexture",
  "BottomTexture",
  "LeftTexture",
  "RightTexture",
}

local EDIT_BOX_TEXTURES = {
  "Left", "Mid", "Right",
  "FocusLeft", "FocusMid", "FocusRight",
}
local EDIT_BOX_EXTRA_TEXTURES = { "Background", "Bg", "Backdrop", "Border" }
local frameSnapshots = setmetatable({}, { __mode = "k" })
local socialSnapshots = setmetatable({}, { __mode = "k" })

-- Snapshot only the Blizzard-owned properties Style changes. These snapshots
-- belong to this module lifecycle and are cleared after restoration.
local function Pack(...)
  return { n = select("#", ...), ... }
end

local function CanUseObject(object)
  return object ~= nil and NS.CanAccessObject(object)
end

local function Call(object, methodName, ...)
  if not CanUseObject(object) then return nil end
  local method = object and object[methodName]
  if type(method) ~= "function" then return nil end
  local result = Pack(pcall(method, object, ...))
  if not result[1] then return nil end
  for index = 2, result.n do
    if not NS.CanAccessValue(result[index]) then return nil end
  end
  return unpack(result, 2, result.n)
end

local function CapturePoints(object)
  local points = {}
  local count = tonumber(Call(object, "GetNumPoints")) or 0
  for index = 1, count do
    local result = Pack(Call(object, "GetPoint", index))
    if result.n > 0 and result[1] then points[#points + 1] = result end
  end
  return points
end

local function RestorePoints(object, points)
  if not CanUseObject(object) or type(object.ClearAllPoints) ~= "function" or type(object.SetPoint) ~= "function" then return end
  object:ClearAllPoints()
  for index = 1, #(points or {}) do
    local point = points[index]
    pcall(object.SetPoint, object, unpack(point, 1, point.n))
  end
end

local function CaptureVisibility(object)
  return {
    shown = Call(object, "IsShown"),
    alpha = Call(object, "GetAlpha"),
  }
end

local function RestoreVisibility(object, state)
  if not CanUseObject(object) or not state then return end
  if type(state.alpha) == "number" and type(object.SetAlpha) == "function" then object:SetAlpha(state.alpha) end
  if state.shown ~= nil then
    if state.shown and type(object.Show) == "function" then object:Show()
    elseif not state.shown and type(object.Hide) == "function" then object:Hide() end
  end
end

local function CaptureTexture(texture)
  if not CanUseObject(texture) then return nil end
  return {
    object = texture,
    atlas = Call(texture, "GetAtlas"),
    texture = Call(texture, "GetTexture"),
    texCoord = Pack(Call(texture, "GetTexCoord")),
    vertex = Pack(Call(texture, "GetVertexColor")),
    blendMode = Call(texture, "GetBlendMode"),
    width = Call(texture, "GetWidth"),
    height = Call(texture, "GetHeight"),
    points = CapturePoints(texture),
    visibility = CaptureVisibility(texture),
  }
end

local function RestoreTexture(state, objectOverride)
  if not state then return end
  local texture = objectOverride or state.object
  if not CanUseObject(texture) then return end

  if state.atlas and type(texture.SetAtlas) == "function" then
    pcall(texture.SetAtlas, texture, state.atlas, false)
  elseif type(texture.SetTexture) == "function" then
    pcall(texture.SetTexture, texture, state.texture)
  end
  if state.texCoord and state.texCoord.n > 0 and type(texture.SetTexCoord) == "function" then
    pcall(texture.SetTexCoord, texture, unpack(state.texCoord, 1, state.texCoord.n))
  end
  if state.vertex and state.vertex.n >= 3 and type(texture.SetVertexColor) == "function" then
    pcall(texture.SetVertexColor, texture, unpack(state.vertex, 1, state.vertex.n))
  end
  if state.blendMode and type(texture.SetBlendMode) == "function" then
    pcall(texture.SetBlendMode, texture, state.blendMode)
  end
  if type(state.width) == "number" and type(state.height) == "number" and type(texture.SetSize) == "function" then
    texture:SetSize(state.width, state.height)
  end
  RestorePoints(texture, state.points)
  RestoreVisibility(texture, state.visibility)
end

local function CaptureFont(fontString)
  if not CanUseObject(fontString) then return nil end
  return {
    object = fontString,
    font = Pack(Call(fontString, "GetFont")),
    textColor = Pack(Call(fontString, "GetTextColor")),
    shadowColor = Pack(Call(fontString, "GetShadowColor")),
    shadowOffset = Pack(Call(fontString, "GetShadowOffset")),
    width = Call(fontString, "GetWidth"),
    height = Call(fontString, "GetHeight"),
    points = CapturePoints(fontString),
    visibility = CaptureVisibility(fontString),
  }
end

local function RestoreFont(state)
  if not state or not CanUseObject(state.object) then return end
  local fontString = state.object
  if state.font and state.font[1] and type(fontString.SetFont) == "function" then
    pcall(fontString.SetFont, fontString, unpack(state.font, 1, state.font.n))
  end
  if state.textColor and state.textColor.n >= 3 and type(fontString.SetTextColor) == "function" then
    pcall(fontString.SetTextColor, fontString, unpack(state.textColor, 1, state.textColor.n))
  end
  if state.shadowColor and state.shadowColor.n >= 3 and type(fontString.SetShadowColor) == "function" then
    pcall(fontString.SetShadowColor, fontString, unpack(state.shadowColor, 1, state.shadowColor.n))
  end
  if state.shadowOffset and state.shadowOffset.n >= 2 and type(fontString.SetShadowOffset) == "function" then
    pcall(fontString.SetShadowOffset, fontString, unpack(state.shadowOffset, 1, state.shadowOffset.n))
  end
  if type(state.width) == "number" and type(state.height) == "number" and type(fontString.SetSize) == "function" then
    fontString:SetSize(state.width, state.height)
  end
  RestorePoints(fontString, state.points)
  RestoreVisibility(fontString, state.visibility)
end

local function CaptureFrameGeometry(frame)
  if not CanUseObject(frame) then return nil end
  return {
    object = frame,
    width = Call(frame, "GetWidth"),
    height = Call(frame, "GetHeight"),
    points = CapturePoints(frame),
    visibility = CaptureVisibility(frame),
    mouseEnabled = Call(frame, "IsMouseEnabled"),
  }
end

local function RestoreFrameGeometry(state, restorePoints, restoreSize)
  if not state or not CanUseObject(state.object) then return end
  local frame = state.object
  if restoreSize and type(state.width) == "number" and type(state.height) == "number" and type(frame.SetSize) == "function" then
    frame:SetSize(state.width, state.height)
  end
  if restorePoints then RestorePoints(frame, state.points) end
  if state.mouseEnabled ~= nil and type(frame.EnableMouse) == "function" then frame:EnableMouse(state.mouseEnabled) end
  RestoreVisibility(frame, state.visibility)
end

local function CaptureFontOwner(object)
  if not CanUseObject(object) then return nil end
  return {
    object = object,
    font = Pack(Call(object, "GetFont")),
    textColor = Pack(Call(object, "GetTextColor")),
    shadowColor = Pack(Call(object, "GetShadowColor")),
    shadowOffset = Pack(Call(object, "GetShadowOffset")),
  }
end

local function RestoreFontOwner(state)
  if not state or not CanUseObject(state.object) then return end
  local object = state.object
  if state.font and state.font[1] and type(object.SetFont) == "function" then
    pcall(object.SetFont, object, unpack(state.font, 1, state.font.n))
  end
  if state.textColor and state.textColor.n >= 3 and type(object.SetTextColor) == "function" then
    pcall(object.SetTextColor, object, unpack(state.textColor, 1, state.textColor.n))
  end
  if state.shadowColor and state.shadowColor.n >= 3 and type(object.SetShadowColor) == "function" then
    pcall(object.SetShadowColor, object, unpack(state.shadowColor, 1, state.shadowColor.n))
  end
  if state.shadowOffset and state.shadowOffset.n >= 2 and type(object.SetShadowOffset) == "function" then
    pcall(object.SetShadowOffset, object, unpack(state.shadowOffset, 1, state.shadowOffset.n))
  end
end

local function CaptureButtonSlot(button, getterName)
  local texture = Call(button, getterName)
  return texture and CaptureTexture(texture) or false
end

local BUTTON_SLOTS = {
  { "GetNormalTexture", "SetNormalTexture", "SetNormalAtlas" },
  { "GetPushedTexture", "SetPushedTexture", "SetPushedAtlas" },
  { "GetDisabledTexture", "SetDisabledTexture", "SetDisabledAtlas" },
  { "GetHighlightTexture", "SetHighlightTexture", "SetHighlightAtlas" },
}

local function CaptureButton(button)
  if not CanUseObject(button) then return nil end
  local slots = {}
  for index = 1, #BUTTON_SLOTS do
    slots[index] = CaptureButtonSlot(button, BUTTON_SLOTS[index][1])
  end
  return {
    object = button,
    geometry = CaptureFrameGeometry(button),
    slots = slots,
  }
end

local function RestoreButtonSlot(button, descriptor, state)
  if not CanUseObject(button) then return end
  local setter = button and button[descriptor[2]]
  if type(setter) ~= "function" then return end
  if state == false then
    pcall(setter, button, nil)
    return
  end

  local atlasSetter = descriptor[3] and button[descriptor[3]]
  if state.atlas and type(atlasSetter) == "function" then
    pcall(atlasSetter, button, state.atlas)
  else
    pcall(setter, button, state.texture)
  end
  local current = Call(button, descriptor[1])
  if current then RestoreTexture(state, current) end
end

local function RestoreButton(state)
  if not state or not state.object then return end
  local button = state.object
  for index = 1, #BUTTON_SLOTS do
    RestoreButtonSlot(button, BUTTON_SLOTS[index], state.slots[index])
  end
  RestoreFrameGeometry(state.geometry, true, true)
end

local function ShowRothHighlights(owner)
  for _, region in ipairs(owner and owner.__rothHighlight or {}) do
    if CanUseObject(region) then region:Show() end
  end
end

local function IsRothTexture(owner, region)
  if not owner or not region then return false end
  if region == owner.glassLeft or region == owner.glassCenter or region == owner.glassRight
    or region == owner.glassSolid or region == owner.glassBorder or region == owner.__scrollIcon
  then
    return true
  end
  if owner.__rothHighlight then
    for index = 1, #owner.__rothHighlight do
      if region == owner.__rothHighlight[index] then return true end
    end
  end
  return false
end

local function CaptureRegions(owner)
  if not CanUseObject(owner) then return {}, {} end
  local textures, fonts = {}, {}
  local regions = Pack(Call(owner, "GetRegions"))
  for index = 1, regions.n do
    local region = regions[index]
    if region and not IsRothTexture(owner, region) then
      local objectType = Call(region, "GetObjectType")
      if objectType == "Texture" or objectType == "MaskTexture" then
        textures[#textures + 1] = CaptureTexture(region)
      elseif objectType == "FontString" then
        fonts[#fonts + 1] = CaptureFont(region)
      end
    end
  end
  return textures, fonts
end

local function CaptureEditBox(editBox)
  if not CanUseObject(editBox) then return nil end
  local textures, fonts = CaptureRegions(editBox)
  local name = Call(editBox, "GetName")
  if name then
    for index = 1, #EDIT_BOX_EXTRA_TEXTURES do
      local texture = _G[name .. EDIT_BOX_EXTRA_TEXTURES[index]]
      if texture and not IsRothTexture(editBox, texture) then textures[#textures + 1] = CaptureTexture(texture) end
    end
  end

  local backdrop = Call(editBox, "GetBackdrop")
  return {
    object = editBox,
    geometry = CaptureFrameGeometry(editBox),
    font = CaptureFontOwner(editBox),
    textInsets = Pack(Call(editBox, "GetTextInsets")),
    blinkSpeed = Call(editBox, "GetBlinkSpeed"),
    backdrop = type(backdrop) == "table" and NS.CopyTable(backdrop, {}) or backdrop,
    backdropColor = Pack(Call(editBox, "GetBackdropColor")),
    backdropBorderColor = Pack(Call(editBox, "GetBackdropBorderColor")),
    textures = textures,
    fonts = fonts,
  }
end

local function RestoreEditBox(state)
  if not state or not CanUseObject(state.object) then return end
  local editBox = state.object
  RestoreFrameGeometry(state.geometry, true, true)
  RestoreFontOwner(state.font)
  if state.textInsets and state.textInsets.n >= 4 and type(editBox.SetTextInsets) == "function" then
    pcall(editBox.SetTextInsets, editBox, unpack(state.textInsets, 1, state.textInsets.n))
  end
  if type(state.blinkSpeed) == "number" and type(editBox.SetBlinkSpeed) == "function" then
    editBox:SetBlinkSpeed(state.blinkSpeed)
  end
  if type(editBox.SetBackdrop) == "function" then pcall(editBox.SetBackdrop, editBox, state.backdrop) end
  if state.backdropColor and state.backdropColor.n >= 3 and type(editBox.SetBackdropColor) == "function" then
    pcall(editBox.SetBackdropColor, editBox, unpack(state.backdropColor, 1, state.backdropColor.n))
  end
  if state.backdropBorderColor and state.backdropBorderColor.n >= 3 and type(editBox.SetBackdropBorderColor) == "function" then
    pcall(editBox.SetBackdropBorderColor, editBox, unpack(state.backdropBorderColor, 1, state.backdropBorderColor.n))
  end
  for index = 1, #state.textures do RestoreTexture(state.textures[index]) end
  for index = 1, #state.fonts do RestoreFont(state.fonts[index]) end
  NS.HideRothVisuals(editBox)
  editBox.__rothEditAlpha = nil
end

local function CaptureTab(tab)
  if not CanUseObject(tab) then return nil end
  local textures, fonts = CaptureRegions(tab)
  return {
    object = tab,
    height = Call(tab, "GetHeight"),
    textures = textures,
    fonts = fonts,
  }
end

local function RestoreTab(state)
  if not state or not CanUseObject(state.object) then return end
  local tab = state.object
  if type(state.height) == "number" and type(tab.SetHeight) == "function" then tab:SetHeight(state.height) end
  for index = 1, #state.textures do RestoreTexture(state.textures[index]) end
  for index = 1, #state.fonts do RestoreFont(state.fonts[index]) end
end

local function CaptureButtonFrame(buttonFrame)
  if not CanUseObject(buttonFrame) then return nil end
  local textures = {}
  local name = Call(buttonFrame, "GetName")
  if name then
    for index = 1, #BUTTON_FRAME_TEXTURES do
      local texture = _G[name .. BUTTON_FRAME_TEXTURES[index]]
      if texture then textures[#textures + 1] = CaptureTexture(texture) end
    end
  end
  return {
    object = buttonFrame,
    width = Call(buttonFrame, "GetWidth"),
    textures = textures,
  }
end

local function RestoreButtonFrame(state)
  if not state or not CanUseObject(state.object) then return end
  if type(state.width) == "number" and type(state.object.SetWidth) == "function" then state.object:SetWidth(state.width) end
  for index = 1, #state.textures do RestoreTexture(state.textures[index]) end
end

local function CaptureChatFrame(chatFrame)
  if not CanUseObject(chatFrame) or frameSnapshots[chatFrame] then return end
  local name = Call(chatFrame, "GetName")
  if not name then return end

  local editBox = _G[name .. "EditBox"]
  local tab = _G[name .. "Tab"]
  local buttonFrame = _G[name .. "ButtonFrame"]

  frameSnapshots[chatFrame] = {
    object = chatFrame,
    font = CaptureFontOwner(chatFrame),
    background = CaptureTexture(chatFrame.Background or _G[name .. "Background"]),
    scrollBar = CaptureFrameGeometry(chatFrame.ScrollBar),
    scrollButton = CaptureButton(chatFrame.ScrollToBottomButton),
    scrollFlash = CaptureTexture(chatFrame.ScrollToBottomButton and chatFrame.ScrollToBottomButton.Flash),
    buttonFrame = CaptureButtonFrame(buttonFrame),
    editBox = CaptureEditBox(editBox),
    tab = CaptureTab(tab),
  }
end

local function RestoreChatFrame(state)
  if not state or not CanUseObject(state.object) then return false end
  RestoreFontOwner(state.font)
  RestoreTexture(state.background)
  RestoreFrameGeometry(state.scrollBar, false, false)
  RestoreButton(state.scrollButton)
  RestoreTexture(state.scrollFlash)
  RestoreButtonFrame(state.buttonFrame)
  RestoreEditBox(state.editBox)
  RestoreTab(state.tab)

  local scrollButton = state.scrollButton and state.scrollButton.object
  if CanUseObject(scrollButton) and NS.HideRothVisuals then NS.HideRothVisuals(scrollButton) end
  return true
end

local function RestoreSocialButtons()
  for button, state in pairs(socialSnapshots) do
    if CanUseObject(button) then
      RestoreButton(state)
      NS.HideRothVisuals(button)
      socialSnapshots[button] = nil
    end
  end
end

local function RestoreAllStyleState()
  for chatFrame, snapshot in pairs(frameSnapshots) do
    if RestoreChatFrame(snapshot) then frameSnapshots[chatFrame] = nil end
  end
  RestoreSocialButtons()
end


local function IsEnabled(core)
  return styleActive
    and core
    and core:IsModuleActive("Style")
    and core:Get("styleEnabled") ~= false
end

local function ParseHexColor(hex, defaultR, defaultG, defaultB)
  if type(hex) ~= "string" then
    return defaultR, defaultG, defaultB
  end

  local clean = hex:gsub("^#", ""):gsub("^|c%x%x", ""):sub(1, 6)
  if #clean ~= 6 then
    return defaultR, defaultG, defaultB
  end

  local r = tonumber(clean:sub(1, 2), 16)
  local g = tonumber(clean:sub(3, 4), 16)
  local b = tonumber(clean:sub(5, 6), 16)
  if not r or not g or not b then
    return defaultR, defaultG, defaultB
  end

  return r / 255, g / 255, b / 255
end

local function GetConfiguredFont(core)
  local font = core:Get("styleFont")
  if type(font) == "string" and font ~= "" then
    return font
  end

  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  return (LSM and LSM:Fetch("font", "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
end

local function StripButtonFrame(cf)
  if not CanUseObject(cf) then return end
  local chatName = cf and cf:GetName()
  if not chatName then return end
  local btnFrame = _G[chatName .. "ButtonFrame"]
  if not CanUseObject(btnFrame) then return end

  for _, texName in ipairs(BUTTON_FRAME_TEXTURES) do
    local obj = _G[btnFrame:GetName() .. texName]
    if CanUseObject(obj) and obj.SetTexture then
      obj:SetTexture(nil)
    end
  end

  btnFrame:SetWidth(28)
end

local function SetEditBoxGlassAlpha(eb, alpha)
  if not CanUseObject(eb) then return end
  alpha = tonumber(alpha) or 0
  if eb.__rothEditAlpha == alpha then return end
  eb.__rothEditAlpha = alpha
  NS.ApplyGlassLook(eb, alpha)
  NS.UpdateGlassSize(eb)
end

local function KillEditBoxUnderlayTextures(eb)
  if not CanUseObject(eb) or not eb.GetNumRegions then return end

  for i = 1, eb:GetNumRegions() do
    local region = select(i, eb:GetRegions())
    if CanUseObject(region) and region.GetObjectType and region:GetObjectType() == "Texture" then
      local isRothTexture = region == eb.glassLeft
        or region == eb.glassCenter
        or region == eb.glassRight
        or region == eb.glassSolid
        or region == eb.glassBorder

      if not isRothTexture then
        if region.SetTexture then region:SetTexture(nil) end
        if region.SetAlpha then region:SetAlpha(0) end
        if region.Hide then region:Hide() end
      end
    end
  end

  local name = eb.GetName and eb:GetName()
  if name then
    local suffixes = { "Background", "Bg", "Backdrop", "Border" }
    for i = 1, #suffixes do
      local texture = _G[name .. suffixes[i]]
      if CanUseObject(texture) and texture.SetTexture then
        texture:SetTexture(nil)
        if texture.SetAlpha then texture:SetAlpha(0) end
        if texture.Hide then texture:Hide() end
      end
    end
  end

  if eb.SetBackdrop then eb:SetBackdrop(nil) end
end

local function RefreshEditBoxInsets(eb)
  if not CanUseObject(eb) or type(eb.GetTextInsets) ~= "function" or type(eb.SetTextInsets) ~= "function" then
    return
  end

  local left, right, top, bottom = eb:GetTextInsets()
  if not NS.CanAccessAllValues(left, right, top, bottom) then return end
  left, right, top, bottom = NS.SafeNumber(left, 0), NS.SafeNumber(right, 0), NS.SafeNumber(top, 0), NS.SafeNumber(bottom, 0)
  eb:SetTextInsets(
    math.max(8, left),
    math.max(8, right),
    math.max(4, top),
    math.max(4, bottom)
  )
end

local function PositionEditBox(core, cf, eb)
  if not CanUseObject(cf) or not CanUseObject(eb) or eb.__rothPositioning then return end
  eb.__rothPositioning = true

  eb:ClearAllPoints()
  eb:SetHeight(24)

  if (core:Get("editBoxPosition") or "BOTTOM") == "TOP" then
    eb:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 24)
    eb:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 0, 24)
  else
    eb:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, -24)
    eb:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, -24)
  end

  eb.__rothPositioning = nil
end

local function SkinEditBox(core, cf)
  if not CanUseObject(cf) then return end
  local name = cf and cf:GetName()
  if not name then return end
  local eb = _G[name .. "EditBox"]
  if not CanUseObject(eb) then return end

  for _, texName in ipairs(EDIT_BOX_TEXTURES) do
    local texture = _G[name .. "EditBox" .. texName] or _G[eb:GetName() .. texName]
    if CanUseObject(texture) then
      texture:SetTexture(nil)
      texture:SetAlpha(0)
      texture:Hide()
    end
  end

  for i = 1, eb:GetNumRegions() do
    local region = select(i, eb:GetRegions())
    if CanUseObject(region) and region.GetObjectType and region:GetObjectType() == "Texture" then
      local texture = region:GetTexture()
      if type(texture) == "string" and (texture:find("ChatFrameEditBox") or texture:find("UI%-ChatInputBorder")) then
        region:SetTexture(nil)
        region:SetAlpha(0)
        region:Hide()
      end
    end
  end

  KillEditBoxUnderlayTextures(eb)

  if not eb.__rothEditHooks then
    eb.__rothEditHooks = true

    eb:HookScript("OnEditFocusGained", function(self)
      if not IsEnabled(core) then return end
      KillEditBoxUnderlayTextures(self)
      SetEditBoxGlassAlpha(self, EDIT_ALPHA_FOCUS)
    end)

    eb:HookScript("OnEditFocusLost", function(self)
      if not IsEnabled(core) then return end
      SetEditBoxGlassAlpha(self, EDIT_ALPHA_IDLE)
    end)

    eb:HookScript("OnTextChanged", function(self, userInput)
      if not userInput or not IsEnabled(core) or not self:HasFocus() then return end
      -- The edit-box contents can be restricted chat text. Styling depends on
      -- focus only, so never read or retain the contents here.
      SetEditBoxGlassAlpha(self, EDIT_ALPHA_FOCUS)
    end)

    if type(eb.UpdateHeader) == "function" then
      hooksecurefunc(eb, "UpdateHeader", function(self)
        if not IsEnabled(core) then return end
        RefreshEditBoxInsets(self)
      end)
    end
  end

  SetEditBoxGlassAlpha(eb, eb.HasFocus and eb:HasFocus() and EDIT_ALPHA_FOCUS or EDIT_ALPHA_IDLE)

  local size = tonumber(core:Get("styleFontSize")) or 12
  eb:SetFont(GetConfiguredFont(core), size, "")
  eb:SetTextColor(0.95, 0.95, 0.95, 1)

  if core:Get("styleShadow") then
    eb:SetShadowColor(0, 0, 0, 0.75)
    eb:SetShadowOffset(1, -1)
  else
    eb:SetShadowColor(0, 0, 0, 0)
    eb:SetShadowOffset(0, 0)
  end

  if type(eb.SetBlinkSpeed) == "function" then
    eb:SetBlinkSpeed(DEFAULT_EDIT_CURSOR_BLINK)
  end

  PositionEditBox(core, cf, eb)
  if type(eb.UpdateHeader) == "function" then eb:UpdateHeader() end
  RefreshEditBoxInsets(eb)
end

local function SkinScrollButton(core, cf)
  local btn = cf and cf.ScrollToBottomButton
  if not CanUseObject(btn) then return end

  btn:SetNormalTexture(nil)
  btn:SetPushedTexture(nil)
  if btn.SetDisabledTexture then btn:SetDisabledTexture(nil) end
  btn:SetHighlightTexture(nil)
  if CanUseObject(btn.Flash) then btn.Flash:SetAlpha(0) end
  btn:SetSize(24, 24)
  btn:ClearAllPoints()
  btn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -2, 2)
  NS.ApplyGlassBackdrop(btn, 0.8, 0, 0)

  if not btn.__scrollIcon then
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    icon:SetTexture(NS.SCROLL_BTN_TEXTURE)
    local tc = NS.SCROLL_ICONS.TO_BOTTOM
    icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    btn.__scrollIcon = icon
  else
    btn.__scrollIcon:Show()
  end
  if not btn.__rothHighlight then NS.CreateHighlight(btn, "HIGHLIGHT", nil, nil, nil, 0) end
  ShowRothHighlights(btn)

  if not btn.__rothSkinned then
    btn.__rothSkinned = true
    btn:HookScript("OnEnter", function(self)
      if not IsEnabled(core) then return end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 1)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 1)
      end
    end)

    btn:HookScript("OnLeave", function(self)
      if not IsEnabled(core) then return end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.8)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.8)
      end
    end)
  end
end

local function SetTabHeight(tab)
  if not CanUseObject(tab) or tab.__rothFixingHeight then return end
  tab.__rothFixingHeight = true
  tab:SetHeight(20)
  tab.__rothFixingHeight = nil
end

local function CenterTabText(core, tab, text)
  if not CanUseObject(text) or not CanUseObject(tab) or text.__rothFixingPoint then return end
  text.__rothFixingPoint = true
  text:ClearAllPoints()
  text:SetPoint("CENTER", tab, "CENTER", 0, 0)
  text.__rothFixingPoint = nil
end

local function SkinTabTriplet(left, middle, right, tab)
  if CanUseObject(left) then
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -2)
    left:SetTexture(NS.BORDER_HL_TEXTURE)
    left:SetTexCoord(0, 1, 0.5, 1)
    left:SetSize(8, 8)
  end

  if CanUseObject(right) then
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, -2)
    right:SetTexture(NS.BORDER_HL_TEXTURE)
    right:SetTexCoord(1, 0, 0.5, 1)
    right:SetSize(8, 8)
  end

  if CanUseObject(middle) and CanUseObject(left) and CanUseObject(right) then
    middle:ClearAllPoints()
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    middle:SetPoint("TOPRIGHT", right, "TOPLEFT", 0, 0)
    middle:SetTexture(NS.BORDER_HL_TEXTURE)
    middle:SetTexCoord(0, 1, 0, 0.5)
    middle:SetSize(8, 8)
  end
end

local function SkinChatTab(core, cf)
  local chatName = cf and cf:GetName()
  if not chatName then return end
  local tab = _G[chatName .. "Tab"]
  if not CanUseObject(tab) then return end

  tab.__rothTabSkinned = true
  local text = tab.Text or tab:GetFontString()
  if not CanUseObject(text) then text = nil end
  for _, region in ipairs({ tab:GetRegions() }) do
    if CanUseObject(region) and region.IsObjectType and region:IsObjectType("Texture") then
      local drawLayer = region:GetDrawLayer()
      local keep = region == tab.ActiveLeft
        or region == tab.ActiveMiddle
        or region == tab.ActiveRight
        or region == tab.HighlightLeft
        or region == tab.HighlightMiddle
        or region == tab.HighlightRight
        or region == tab.glow
        or region == tab.conversationIcon
      if not keep and (drawLayer == "BACKGROUND" or drawLayer == "BORDER" or drawLayer == "ARTWORK") then
        region:SetTexture(nil)
        region:SetSize(0.001, 0.001)
        region:Hide()
      end
    end
  end

  if not tab.__rothStyleHooksInstalled then
    tab.__rothStyleHooksInstalled = true
    hooksecurefunc(tab, "SetHeight", function(self, height)
      if not IsEnabled(core) or self.__rothFixingHeight then return end
      if InCombatLockdown() then QueueApplyAll(core); return end
      if tonumber(height) ~= 20 then SetTabHeight(self) end
    end)

    hooksecurefunc(tab, "SetSize", function(self, width, height)
      if not IsEnabled(core) or self.__rothFixingHeight then return end
      if InCombatLockdown() then QueueApplyAll(core); return end
      if tonumber(height) ~= 20 then
        self.__rothFixingHeight = true
        self:SetSize(width, 20)
        self.__rothFixingHeight = nil
      end
    end)

    if text then
      hooksecurefunc(text, "SetPoint", function(self)
        if not IsEnabled(core) or self.__rothFixingPoint then return end
        if InCombatLockdown() then QueueApplyAll(core); return end
        CenterTabText(core, tab, self)
      end)
    end
  end

  if text then
    text:SetShadowColor(0, 0, 0, 0.8)
    text:SetShadowOffset(1, -1)
    CenterTabText(core, tab, text)
  end

  local keepText = text or (tab.GetFontString and tab:GetFontString())
  for _, region in ipairs({ tab:GetRegions() }) do
    if CanUseObject(region) and region.IsObjectType and region:IsObjectType("FontString") and region ~= keepText then
      local value = region.GetText and region:GetText()
      if NS.CanAccessValue(value) then
        if value == nil or (type(value) == "string" and strtrim(value) == "") then region:Hide() end
      end
    end
  end

  if CanUseObject(tab.glow) then
    tab.glow:ClearAllPoints()
    tab.glow:SetPoint("BOTTOMLEFT", 8, 2)
    tab.glow:SetPoint("BOTTOMRIGHT", -8, 2)
  end

  SkinTabTriplet(tab.HighlightLeft, tab.HighlightMiddle, tab.HighlightRight, tab)
  SkinTabTriplet(tab.ActiveLeft, tab.ActiveMiddle, tab.ActiveRight, tab)
  SetTabHeight(tab)
end

local function SkinOneSocialButton(core, btn, skipNormal)
  if not CanUseObject(btn) then return end
  if not socialSnapshots[btn] then socialSnapshots[btn] = CaptureButton(btn) end
  btn.__rothSocialSkinned = true

  if not skipNormal and btn.SetNormalTexture then btn:SetNormalTexture(nil) end
  if btn.SetPushedTexture then btn:SetPushedTexture(nil) end
  if btn.SetHighlightTexture then btn:SetHighlightTexture(nil) end
  if btn.SetDisabledTexture then pcall(btn.SetDisabledTexture, btn, nil) end

  btn:SetSize(24, 24)
  NS.ApplyGlassBackdrop(btn, 0.4, 0, 0)
  if not btn.__rothHighlight then NS.CreateHighlight(btn, "HIGHLIGHT", nil, nil, nil, 0) end
  ShowRothHighlights(btn)

  if not btn.__rothStyleHooksInstalled then
    btn.__rothStyleHooksInstalled = true
    btn:HookScript("OnEnter", function(self)
      if not IsEnabled(core) then return end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.7)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.7)
      end
    end)

    btn:HookScript("OnLeave", function(self)
      if not IsEnabled(core) then return end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.4)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.4)
      end
    end)
  end
end

local function SkinSocialButtons(core)
  -- Call on every pass. Individual buttons are idempotent and some Blizzard
  -- buttons are created after RothChat's initial ADDON_LOADED phase.
  SkinOneSocialButton(core, _G.QuickJoinToastButton, false)
  SkinOneSocialButton(core, _G.ChatFrameChannelButton, false)
  SkinOneSocialButton(core, _G.ChatFrameMenuButton, true)
end

local function StripBlizzardChrome(cf)
  if not CanUseObject(cf) then return end
  local chatName = cf and cf:GetName()
  if not chatName then return end

  local blizzBg = cf.Background or _G[chatName .. "Background"]
  if CanUseObject(blizzBg) then
    blizzBg:SetAlpha(0)
    blizzBg:Hide()
  end

  StripButtonFrame(cf)

  if CanUseObject(cf.ScrollBar) then
    cf.ScrollBar:SetAlpha(0)
    cf.ScrollBar:EnableMouse(false)
    cf.ScrollBar:Hide()
  end

  if CanUseObject(cf.ScrollToBottomButton) and CanUseObject(cf.ScrollToBottomButton.Flash) then
    cf.ScrollToBottomButton.Flash:SetAlpha(0)
  end
end

local function EnsureChatBackgroundFrame(cf)
  local bg = backgrounds[cf]
  if bg then return CanUseObject(bg) and bg or nil end

  bg = CreateFrame("Frame", nil, cf:GetParent() or UIParent, "BackdropTemplate")
  bg:SetFrameStrata("BACKGROUND")
  bg:SetFrameLevel(0)
  bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -3, 3)
  bg:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 3, -3)
  bg:EnableMouse(false)

  bg.__fill = bg:CreateTexture(nil, "BACKGROUND")
  bg.__fill:SetAllPoints()

  backgrounds[cf] = bg
  return bg
end

local function ApplyChatBackgroundStyle(core, cf)
  local bg = EnsureChatBackgroundFrame(cf)
  if not CanUseObject(bg) then return end

  if bg.__rothCopyHidden then
    bg:Hide()
    if bg.__border then bg.__border:Hide() end
    return
  end

  local alpha = NS.Clamp(tonumber(core:Get("styleBackgroundAlpha")) or 0.4, 0, 1)
  local texture = core:Get("styleBgTexture")
  if type(texture) ~= "string" or texture == "" then texture = DEFAULT_BG_TEXTURE end
  local fillR, fillG, fillB = ParseHexColor(core:Get("styleBackgroundColor"), 0, 0, 0)

  bg.__fill:SetTexture(texture)
  bg.__fill:SetVertexColor(fillR, fillG, fillB, alpha)
  bg.__fill:Show()

  if bg.glassLeft then bg.glassLeft:Hide() end
  if bg.glassCenter then bg.glassCenter:Hide() end
  if bg.glassRight then bg.glassRight:Hide() end
  if bg.glassSolid then bg.glassSolid:Hide() end

  if core:Get("styleBorder") then
    if not bg.__border then
      bg.__border = CreateFrame("Frame", nil, bg, "BackdropTemplate")
      bg.__border:SetAllPoints(bg)
    end

    local borderTexture = core:Get("styleBorderTexture")
    if type(borderTexture) ~= "string" or borderTexture == "" then
      borderTexture = DEFAULT_BORDER_TEXTURE
    end

    if bg.__borderTexture ~= borderTexture then
      bg.__border:SetBackdrop({
        edgeFile = borderTexture,
        tile = true,
        tileEdge = true,
        edgeSize = 8,
      })
      bg.__borderTexture = borderTexture
    end

    local borderR, borderG, borderB = ParseHexColor(core:Get("styleBorderColor"), 0, 0, 0)
    bg.__border:SetBackdropBorderColor(borderR, borderG, borderB, math.min(1, alpha + 0.35))
    bg.__border:Show()
  elseif bg.__border then
    bg.__border:Hide()
  end

  bg:SetAlpha(1)
  bg:Show()
end

local function ApplyToChatFrame(core, cf)
  if not CanUseObject(cf) then return end
  CaptureChatFrame(cf)

  local font = GetConfiguredFont(core)
  local size = tonumber(core:Get("styleFontSize")) or 12
  local outline = core:Get("styleFontOutline") or ""

  if type(cf.SetFont) == "function" then cf:SetFont(font, size, outline) end

  if core:Get("styleShadow") then
    if type(cf.SetShadowColor) == "function" then cf:SetShadowColor(0, 0, 0, 0.55) end
    if type(cf.SetShadowOffset) == "function" then cf:SetShadowOffset(1, -1) end
  else
    if type(cf.SetShadowColor) == "function" then cf:SetShadowColor(0, 0, 0, 0) end
    if type(cf.SetShadowOffset) == "function" then cf:SetShadowOffset(0, 0) end
  end

  SkinEditBox(core, cf)
  SkinScrollButton(core, cf)
  SkinChatTab(core, cf)
  StripBlizzardChrome(cf)

  if cf == _G.ChatFrame1 then SkinSocialButtons(core) end

  if core:Get("styleBackground") then
    ApplyChatBackgroundStyle(core, cf)
  elseif backgrounds[cf] then
    backgrounds[cf]:Hide()
    if backgrounds[cf].__border then backgrounds[cf].__border:Hide() end
  end
end

local function ApplyAllToFrames(core)
  for _, cf in ipairs(NS.GetChatFrames()) do
    ApplyToChatFrame(core, cf)
  end
  SkinSocialButtons(core)
end

local function HideOwnedBackgrounds()
  for _, bg in pairs(backgrounds) do
    if CanUseObject(bg) then
      bg:Hide()
      if CanUseObject(bg.__border) then bg.__border:Hide() end
    end
  end
end

local function RestoreStyleState(core)
  NS.CancelScheduled(M)
  M.__applyQueued = false
  core:CancelDeferred(M.__applyDeferredKey)
  HideOwnedBackgrounds()
  local function RestoreIfDisabled()
    if IsEnabled(core) then return end
    RestoreAllStyleState()
  end
  if InCombatLockdown() then
    core:DeferKeyed(M.__restoreDeferredKey, RestoreIfDisabled)
  else
    core:CancelDeferred(M.__restoreDeferredKey)
    RestoreIfDisabled()
  end
end

local function DeferApplyAll(core)
  local function ApplyIfEnabled()
    if IsEnabled(core) then ApplyAllToFrames(core) end
  end
  core:DeferKeyed(M.__applyDeferredKey, ApplyIfEnabled)
end

QueueApplyAll = function(core)
  core:CancelDeferred(M.__restoreDeferredKey)
  if M.__applyQueued then return end
  M.__applyQueued = true

  NS.RunNextFrame(M, function()
    M.__applyQueued = false
    if not IsEnabled(core) then return end
    if InCombatLockdown() then
      DeferApplyAll(core)
      return
    end
    ApplyAllToFrames(core)
  end, "RothChat:StyleApplyAll")
end

local function EnsureGlobalHooks(core)
  if M.__tabUpdateHooked then return end
  M.__tabUpdateHooked = true

  if type(_G.FCFTab_UpdateColors) == "function" then
    hooksecurefunc("FCFTab_UpdateColors", function(tabFrame)
      if not IsEnabled(core) or not CanUseObject(tabFrame) then return end
      if InCombatLockdown() then
        QueueApplyAll(core)
        return
      end

      if not tabFrame.__rothTabSkinned then
        local tabName = tabFrame:GetName()
        local cf = tabName and _G[tabName:gsub("Tab$", "")]
        if cf then SkinChatTab(core, cf) end
      else
        SetTabHeight(tabFrame)
      end
    end)
  end

  -- Blizzard's function receives a chat frame, not a tab frame.
  if type(_G.FCFTab_UpdateAlpha) == "function" then
    hooksecurefunc("FCFTab_UpdateAlpha", function(chatFrame)
      if not IsEnabled(core) or not CanUseObject(chatFrame) then return end
      if InCombatLockdown() then QueueApplyAll(core); return end
      local name = chatFrame.GetName and chatFrame:GetName()
      local tab = name and _G[name .. "Tab"]
      if tab and tab.__rothTabSkinned then SetTabHeight(tab) end
    end)
  end
end

local function RegisterListeners(core)
  if listenersRegistered then return end
  listenersRegistered = true

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if not IsEnabled(core2) or not chatFrame then return end
    if InCombatLockdown() then
      QueueApplyAll(core2)
    else
      ApplyToChatFrame(core2, chatFrame)
    end
  end, M)

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if IsEnabled(core2) then QueueApplyAll(core2) end
  end, M)

  core:On("COPY_OVERLAY_VISIBILITY", function(_, core2, chatFrame, visible)
    local bg = chatFrame and backgrounds[chatFrame]
    if not bg then return end

    bg.__rothCopyHidden = visible and true or false
    if visible then
      bg:Hide()
      if bg.__border then bg.__border:Hide() end
    elseif IsEnabled(core2) and core2:Get("styleBackground") then
      ApplyChatBackgroundStyle(core2, chatFrame)
    end
  end, M)
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  styleActive = true
  listenersRegistered = false
  core:CancelDeferred(M.__restoreDeferredKey)
  core:CancelDeferred(M.__applyDeferredKey)
  core:EnsureChatLifecycleHooks()
  RegisterListeners(core)
  EnsureGlobalHooks(core)

  if core:Get("styleEnabled") == false then
    RestoreStyleState(core)
    return
  end

  if InCombatLockdown() then
    DeferApplyAll(core)
  else
    ApplyAllToFrames(core)
  end
end

function M:OnLogin(core)
  if core:Get("styleEnabled") ~= false then QueueApplyAll(core) end
end

function M:OnDisable(core)
  styleActive = false
  listenersRegistered = false
  M.__applyQueued = false
  NS.CancelScheduled(M)
  core:CancelDeferred(M.__applyDeferredKey)
  core:CancelDeferred(M.__restoreDeferredKey)

  RestoreStyleState(core)
end

function M:Refresh(core)
  if not IsEnabled(core) then
    RestoreStyleState(core)
    return
  end
  QueueApplyAll(core)
end

RothChat:RegisterModule(M)
