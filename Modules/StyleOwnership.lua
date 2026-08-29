-- RothChat - reversible Style ownership.
-- Style.lua installs permanent guarded hooks, but its visual mutations must be
-- reversible when the module or styleEnabled feature is disabled at runtime.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local Style = RothChat.modules and RothChat.modules.Style
if not Style then return end

local originalEnable = Style.OnEnable
local originalDisable = Style.OnDisable
local originalRefresh = Style.Refresh
local originalLogin = Style.OnLogin

local preOwner = {}
local postOwner = {}
local postScheduleKey = {}
local styleOwned = false
local frameSnapshots = setmetatable({}, { __mode = "k" })
local socialSnapshots = setmetatable({}, { __mode = "k" })

local BUTTON_FRAME_TEXTURES = {
  "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture",
  "BottomRightTexture", "TopTexture", "BottomTexture", "LeftTexture", "RightTexture",
}
local EDIT_BOX_TEXTURES = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
local EDIT_BOX_EXTRA_TEXTURES = { "Background", "Bg", "Backdrop", "Border" }

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function Call(object, methodName, ...)
  local method = object and object[methodName]
  if type(method) ~= "function" then return nil end
  local result = Pack(pcall(method, object, ...))
  if not result[1] then return nil end
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
  if not object or type(object.ClearAllPoints) ~= "function" or type(object.SetPoint) ~= "function" then return end
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
  if not object or not state then return end
  if type(state.alpha) == "number" and type(object.SetAlpha) == "function" then object:SetAlpha(state.alpha) end
  if state.shown ~= nil then
    if state.shown and type(object.Show) == "function" then object:Show()
    elseif not state.shown and type(object.Hide) == "function" then object:Hide() end
  end
end

local function CaptureTexture(texture)
  if not texture then return nil end
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
  if not texture then return end

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
  if not fontString then return nil end
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
  if not state or not state.object then return end
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
  if not frame then return nil end
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
  if not state or not state.object then return end
  local frame = state.object
  if restoreSize and type(state.width) == "number" and type(state.height) == "number" and type(frame.SetSize) == "function" then
    frame:SetSize(state.width, state.height)
  end
  if restorePoints then RestorePoints(frame, state.points) end
  if state.mouseEnabled ~= nil and type(frame.EnableMouse) == "function" then frame:EnableMouse(state.mouseEnabled) end
  RestoreVisibility(frame, state.visibility)
end

local function CaptureFontOwner(object)
  if not object then return nil end
  return {
    object = object,
    font = Pack(Call(object, "GetFont")),
    textColor = Pack(Call(object, "GetTextColor")),
    shadowColor = Pack(Call(object, "GetShadowColor")),
    shadowOffset = Pack(Call(object, "GetShadowOffset")),
  }
end

local function RestoreFontOwner(state)
  if not state or not state.object then return end
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
  if not button then return nil end
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
  if not editBox then return nil end
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
  if not state or not state.object then return end
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
  if NS.HideRothVisuals then NS.HideRothVisuals(editBox) end
  editBox.__rothEditAlpha = nil
end

local function CaptureTab(tab)
  if not tab then return nil end
  local textures, fonts = CaptureRegions(tab)
  return {
    object = tab,
    height = Call(tab, "GetHeight"),
    textures = textures,
    fonts = fonts,
  }
end

local function RestoreTab(state)
  if not state or not state.object then return end
  local tab = state.object
  if type(state.height) == "number" and type(tab.SetHeight) == "function" then tab:SetHeight(state.height) end
  for index = 1, #state.textures do RestoreTexture(state.textures[index]) end
  for index = 1, #state.fonts do RestoreFont(state.fonts[index]) end
end

local function CaptureButtonFrame(buttonFrame)
  if not buttonFrame then return nil end
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
  if not state or not state.object then return end
  if type(state.width) == "number" and type(state.object.SetWidth) == "function" then state.object:SetWidth(state.width) end
  for index = 1, #state.textures do RestoreTexture(state.textures[index]) end
end

local function CaptureChatFrame(chatFrame)
  if not chatFrame or frameSnapshots[chatFrame] then return end
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
  if not state then return end
  RestoreFontOwner(state.font)
  RestoreTexture(state.background)
  RestoreFrameGeometry(state.scrollBar, false, false)
  RestoreButton(state.scrollButton)
  RestoreTexture(state.scrollFlash)
  RestoreButtonFrame(state.buttonFrame)
  RestoreEditBox(state.editBox)
  RestoreTab(state.tab)

  local scrollButton = state.scrollButton and state.scrollButton.object
  if NS.HideRothVisuals then NS.HideRothVisuals(scrollButton) end
end

local function CaptureSocialButtons()
  for _, button in ipairs({ _G.QuickJoinToastButton, _G.ChatFrameChannelButton, _G.ChatFrameMenuButton }) do
    if button and not socialSnapshots[button] then socialSnapshots[button] = CaptureButton(button) end
  end
end

local function RestoreSocialButtons()
  for button, state in pairs(socialSnapshots) do
    RestoreButton(state)
    if NS.HideRothVisuals then NS.HideRothVisuals(button) end
    socialSnapshots[button] = nil
  end
end

local function SkinTriplet(left, middle, right, tab)
  if left then
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -2)
    left:SetTexture(NS.BORDER_HL_TEXTURE)
    left:SetTexCoord(0, 1, 0.5, 1)
    left:SetSize(8, 8)
    left:Show()
  end
  if right then
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, -2)
    right:SetTexture(NS.BORDER_HL_TEXTURE)
    right:SetTexCoord(1, 0, 0.5, 1)
    right:SetSize(8, 8)
    right:Show()
  end
  if middle and left and right then
    middle:ClearAllPoints()
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    middle:SetPoint("TOPRIGHT", right, "TOPLEFT", 0, 0)
    middle:SetTexture(NS.BORDER_HL_TEXTURE)
    middle:SetTexCoord(0, 1, 0, 0.5)
    middle:SetSize(8, 8)
    middle:Show()
  end
end

local function ReapplyTab(chatFrame)
  local name = Call(chatFrame, "GetName")
  local tab = name and _G[name .. "Tab"]
  if not tab or not tab.__rothTabSkinned then return end
  local text = tab.Text or (tab.GetFontString and tab:GetFontString())

  local regions = Pack(Call(tab, "GetRegions"))
  for index = 1, regions.n do
    local region = regions[index]
    if region and Call(region, "GetObjectType") == "Texture" then
      local keep = region == tab.ActiveLeft or region == tab.ActiveMiddle or region == tab.ActiveRight
        or region == tab.HighlightLeft or region == tab.HighlightMiddle or region == tab.HighlightRight
        or region == tab.glow or region == tab.conversationIcon
      local drawLayer = Call(region, "GetDrawLayer")
      if not keep and (drawLayer == "BACKGROUND" or drawLayer == "BORDER" or drawLayer == "ARTWORK") then
        region:SetTexture(nil)
        region:SetSize(0.001, 0.001)
        region:Hide()
      end
    elseif region and Call(region, "GetObjectType") == "FontString" and region ~= text then
      local value = Call(region, "GetText")
      if not value or (type(_G.strtrim) == "function" and _G.strtrim(value) == "") then region:Hide() end
    end
  end

  if text then
    text.__rothFixingPoint = true
    text:ClearAllPoints()
    text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    text.__rothFixingPoint = nil
    text:SetShadowColor(0, 0, 0, 0.8)
    text:SetShadowOffset(1, -1)
  end
  if tab.glow then
    tab.glow:ClearAllPoints()
    tab.glow:SetPoint("BOTTOMLEFT", 8, 2)
    tab.glow:SetPoint("BOTTOMRIGHT", -8, 2)
  end
  SkinTriplet(tab.HighlightLeft, tab.HighlightMiddle, tab.HighlightRight, tab)
  SkinTriplet(tab.ActiveLeft, tab.ActiveMiddle, tab.ActiveRight, tab)
  tab.__rothFixingHeight = true
  tab:SetHeight(20)
  tab.__rothFixingHeight = nil
end

local function ReapplyScrollButton(chatFrame)
  local button = chatFrame and chatFrame.ScrollToBottomButton
  if not button or not button.__rothSkinned then return end
  button:SetNormalTexture(nil)
  button:SetPushedTexture(nil)
  if button.SetDisabledTexture then button:SetDisabledTexture(nil) end
  button:SetHighlightTexture(nil)
  if button.Flash then button.Flash:SetAlpha(0) end
  button:SetSize(24, 24)
  button:ClearAllPoints()
  button:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -2, 2)
  NS.ApplyGlassBackdrop(button, 0.8, 0, 0)
  if button.__scrollIcon then button.__scrollIcon:Show() end
  if button.__rothHighlight then
    for index = 1, #button.__rothHighlight do
      local region = button.__rothHighlight[index]
      if region then region:Show() end
    end
  end
end

local function ReapplySocialButton(button, skipNormal)
  if not button or not button.__rothSocialSkinned then return end
  if not skipNormal and button.SetNormalTexture then button:SetNormalTexture(nil) end
  if button.SetPushedTexture then button:SetPushedTexture(nil) end
  if button.SetHighlightTexture then button:SetHighlightTexture(nil) end
  if button.SetDisabledTexture then pcall(button.SetDisabledTexture, button, nil) end
  button:SetSize(24, 24)
  NS.ApplyGlassBackdrop(button, 0.4, 0, 0)
  if button.__rothHighlight then
    for index = 1, #button.__rothHighlight do
      local region = button.__rothHighlight[index]
      if region then region:Show() end
    end
  end
end

local function ReapplyPersistentVisuals()
  for _, chatFrame in ipairs(NS.GetActiveChatFrames and NS.GetActiveChatFrames() or {}) do
    ReapplyTab(chatFrame)
    ReapplyScrollButton(chatFrame)
  end
  ReapplySocialButton(_G.QuickJoinToastButton, false)
  ReapplySocialButton(_G.ChatFrameChannelButton, false)
  ReapplySocialButton(_G.ChatFrameMenuButton, true)
end

local function CaptureAll()
  for _, chatFrame in ipairs(NS.GetActiveChatFrames and NS.GetActiveChatFrames() or {}) do
    CaptureChatFrame(chatFrame)
  end
  CaptureSocialButtons()
end

local function RestoreAll()
  for chatFrame, state in pairs(frameSnapshots) do
    RestoreChatFrame(state)
    frameSnapshots[chatFrame] = nil
  end
  RestoreSocialButtons()
end

local function InstallPreListeners(core)
  core:OffOwner(preOwner)
  core:On("CHAT_FRAME_READY", function(_, _, chatFrame)
    if styleOwned then CaptureChatFrame(chatFrame) end
  end, preOwner)
  core:On("CHAT_LAYOUT_CHANGED", function()
    if styleOwned then CaptureAll() end
  end, preOwner)
end

local function InstallPostListeners(core)
  core:OffOwner(postOwner)
  core:On("CHAT_FRAME_READY", function(_, _, chatFrame)
    if styleOwned then
      ReapplyTab(chatFrame)
      ReapplyScrollButton(chatFrame)
    end
  end, postOwner)
  core:On("CHAT_LAYOUT_CHANGED", function()
    if styleOwned then ReapplyPersistentVisuals() end
  end, postOwner)
end

local function QueuePostReapply(core)
  NS.Schedule(postScheduleKey, 0.05, function()
    if styleOwned and core:IsModuleActive("Style") and core:Get("styleEnabled") ~= false then
      ReapplyPersistentVisuals()
    end
  end, "RothChat:StyleOwnershipReapply")
end

function Style:OnEnable(core)
  InstallPreListeners(core)
  if core:Get("styleEnabled") ~= false then
    CaptureAll()
    styleOwned = true
  end

  local result = originalEnable(self, core)
  InstallPostListeners(core)
  if styleOwned then ReapplyPersistentVisuals() end
  return result
end

function Style:OnLogin(core)
  local result
  if originalLogin then result = originalLogin(self, core) end
  if styleOwned then QueuePostReapply(core) end
  return result
end

function Style:Refresh(core)
  local enabled = core:Get("styleEnabled") ~= false
  if not enabled and styleOwned then
    local result = originalRefresh and originalRefresh(self, core)
    RestoreAll()
    styleOwned = false
    return result
  end

  if enabled and not styleOwned then
    CaptureAll()
    styleOwned = true
  end
  local result = originalRefresh and originalRefresh(self, core)
  if styleOwned then QueuePostReapply(core) end
  return result
end

function Style:OnDisable(core)
  NS.CancelScheduled(postScheduleKey)
  core:OffOwner(preOwner)
  core:OffOwner(postOwner)

  local result = originalDisable(self, core)
  if styleOwned then RestoreAll() end
  styleOwned = false
  return result
end
