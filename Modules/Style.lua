-- RothChat - Style module
-- Chat typography and Roth/Glass presentation for Blizzard chat frames.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Style",
  defaultEnabled = true,
  description = "Fonts, shadows, and ls_Glass visual style.",
}

local backgrounds = {}
local styleActive = false
local listenersRegistered = false
local QueueApplyAll

local DEFAULT_BG_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_BORDER_TEXTURE = NS.BORDER_TEXTURE or "Interface\\AddOns\\RothChat\\Assets\\border"
local DEFAULT_EDIT_CURSOR_BLINK = 0.85
local EDIT_ALPHA_IDLE = 0.0
local EDIT_ALPHA_FOCUS = 0.22
local EDIT_ALPHA_TEXT = 0.32

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
  local chatName = cf and cf:GetName()
  if not chatName then return end
  local btnFrame = _G[chatName .. "ButtonFrame"]
  if not btnFrame then return end

  for _, texName in ipairs(BUTTON_FRAME_TEXTURES) do
    local obj = _G[btnFrame:GetName() .. texName]
    if obj and obj.SetTexture then
      obj:SetTexture(nil)
    end
  end

  btnFrame:SetWidth(28)
end

local function SetEditBoxGlassAlpha(eb, alpha)
  if not eb then return end
  alpha = tonumber(alpha) or 0
  if eb.__rothEditAlpha == alpha then return end
  eb.__rothEditAlpha = alpha
  NS.ApplyGlassLook(eb, alpha)
  if NS.UpdateGlassSize then NS.UpdateGlassSize(eb) end
end

local function KillEditBoxUnderlayTextures(eb)
  if not eb or not eb.GetNumRegions then return end

  for i = 1, eb:GetNumRegions() do
    local region = select(i, eb:GetRegions())
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
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
      if texture and texture.SetTexture then
        texture:SetTexture(nil)
        if texture.SetAlpha then texture:SetAlpha(0) end
        if texture.Hide then texture:Hide() end
      end
    end
  end

  if eb.SetBackdrop then eb:SetBackdrop(nil) end
end

local function RefreshEditBoxInsets(eb)
  if not eb or type(eb.GetTextInsets) ~= "function" or type(eb.SetTextInsets) ~= "function" then
    return
  end

  local left, right, top, bottom = eb:GetTextInsets()
  eb:SetTextInsets(
    math.max(8, tonumber(left) or 0),
    math.max(8, tonumber(right) or 0),
    math.max(4, tonumber(top) or 0),
    math.max(4, tonumber(bottom) or 0)
  )
end

local function PositionEditBox(core, cf, eb)
  if not cf or not eb or eb.__rothPositioning then return end
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
  local name = cf and cf:GetName()
  if not name then return end
  local eb = _G[name .. "EditBox"]
  if not eb then return end

  for _, texName in ipairs(EDIT_BOX_TEXTURES) do
    local texture = _G[name .. "EditBox" .. texName] or _G[eb:GetName() .. texName]
    if texture then
      texture:SetTexture(nil)
      texture:SetAlpha(0)
      texture:Hide()
    end
  end

  for i = 1, eb:GetNumRegions() do
    local region = select(i, eb:GetRegions())
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
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
      local text = self:GetText()
      SetEditBoxGlassAlpha(self, text and text ~= "" and EDIT_ALPHA_TEXT or EDIT_ALPHA_FOCUS)
    end)

    eb:HookScript("OnEditFocusLost", function(self)
      if not styleActive then return end
      SetEditBoxGlassAlpha(self, EDIT_ALPHA_IDLE)
    end)

    eb:HookScript("OnTextChanged", function(self, userInput)
      if not userInput or not IsEnabled(core) or not self:HasFocus() then return end
      local text = self:GetText()
      SetEditBoxGlassAlpha(self, text and text ~= "" and EDIT_ALPHA_TEXT or EDIT_ALPHA_FOCUS)
    end)

    if type(eb.UpdateHeader) == "function" then
      hooksecurefunc(eb, "UpdateHeader", function(self)
        if not IsEnabled(core) then return end
        RefreshEditBoxInsets(self)
      end)
    end
  end

  if not eb.__glassStyled then
    eb.__glassStyled = true
    SetEditBoxGlassAlpha(eb, EDIT_ALPHA_IDLE)
  end

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
  if not btn then return end

  if not btn.__rothSkinned then
    btn.__rothSkinned = true
    btn:SetNormalTexture(nil)
    btn:SetPushedTexture(nil)
    if btn.SetDisabledTexture then btn:SetDisabledTexture(nil) end
    btn:SetHighlightTexture(nil)
    if btn.Flash then btn.Flash:SetAlpha(0) end

    btn:SetSize(24, 24)
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -2, 2)

    NS.ApplyGlassBackdrop(btn, 0.8, 0, 0)

    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    icon:SetTexture(NS.SCROLL_BTN_TEXTURE)
    local tc = NS.SCROLL_ICONS.TO_BOTTOM
    icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    btn.__scrollIcon = icon

    NS.CreateHighlight(btn, "HIGHLIGHT", nil, nil, nil, 0)

    btn:HookScript("OnEnter", function(self)
      if not IsEnabled(core) then return end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 1)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 1)
      end
    end)

    btn:HookScript("OnLeave", function(self)
      if not styleActive then return end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.8)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.8)
      end
    end)
  end
end

local function SetTabHeight(tab)
  if not tab or tab.__rothFixingHeight then return end
  tab.__rothFixingHeight = true
  tab:SetHeight(20)
  tab.__rothFixingHeight = nil
end

local function CenterTabText(core, tab, text)
  if not text or text.__rothFixingPoint then return end
  text.__rothFixingPoint = true
  text:ClearAllPoints()
  text:SetPoint("CENTER", tab, "CENTER", 0, 0)
  text.__rothFixingPoint = nil
end

local function SkinTabTriplet(left, middle, right, tab)
  if left then
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -2)
    left:SetTexture(NS.BORDER_HL_TEXTURE)
    left:SetTexCoord(0, 1, 0.5, 1)
    left:SetSize(8, 8)
  end

  if right then
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, -2)
    right:SetTexture(NS.BORDER_HL_TEXTURE)
    right:SetTexCoord(1, 0, 0.5, 1)
    right:SetSize(8, 8)
  end

  if middle and left and right then
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
  if not tab then return end

  if not tab.__rothTabSkinned then
    tab.__rothTabSkinned = true
    local text = tab.Text or tab:GetFontString()

    for _, region in ipairs({ tab:GetRegions() }) do
      if region and region.IsObjectType and region:IsObjectType("Texture") then
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

    hooksecurefunc(tab, "SetHeight", function(self, height)
      if not IsEnabled(core) or self.__rothFixingHeight then return end
      if tonumber(height) ~= 20 then SetTabHeight(self) end
    end)

    hooksecurefunc(tab, "SetSize", function(self, width, height)
      if not IsEnabled(core) or self.__rothFixingHeight then return end
      if tonumber(height) ~= 20 then
        self.__rothFixingHeight = true
        self:SetSize(width, 20)
        self.__rothFixingHeight = nil
      end
    end)

    if text then
      hooksecurefunc(text, "SetPoint", function(self)
        if not IsEnabled(core) or self.__rothFixingPoint then return end
        CenterTabText(core, tab, self)
      end)
      text:SetShadowColor(0, 0, 0, 0.8)
      text:SetShadowOffset(1, -1)
      CenterTabText(core, tab, text)
    end

    local keepText = text or (tab.GetFontString and tab:GetFontString())
    for _, region in ipairs({ tab:GetRegions() }) do
      if region and region.IsObjectType and region:IsObjectType("FontString") and region ~= keepText then
        local value = region.GetText and region:GetText()
        if not value or strtrim(value) == "" then region:Hide() end
      end
    end

    if tab.glow then
      tab.glow:ClearAllPoints()
      tab.glow:SetPoint("BOTTOMLEFT", 8, 2)
      tab.glow:SetPoint("BOTTOMRIGHT", -8, 2)
    end

    SkinTabTriplet(tab.HighlightLeft, tab.HighlightMiddle, tab.HighlightRight, tab)
    SkinTabTriplet(tab.ActiveLeft, tab.ActiveMiddle, tab.ActiveRight, tab)
  end

  SetTabHeight(tab)
end

local function SkinOneSocialButton(core, btn, skipNormal)
  if not btn or btn.__rothSocialSkinned then return end
  btn.__rothSocialSkinned = true

  if not skipNormal and btn.SetNormalTexture then btn:SetNormalTexture(nil) end
  if btn.SetPushedTexture then btn:SetPushedTexture(nil) end
  if btn.SetHighlightTexture then btn:SetHighlightTexture(nil) end
  if btn.SetDisabledTexture then pcall(btn.SetDisabledTexture, btn, nil) end

  btn:SetSize(24, 24)
  NS.ApplyGlassBackdrop(btn, 0.4, 0, 0)
  NS.CreateHighlight(btn, "HIGHLIGHT", nil, nil, nil, 0)

  btn:HookScript("OnEnter", function(self)
    if not IsEnabled(core) then return end
    if self.__glassBackdrop then
      self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.7)
      self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.7)
    end
  end)

  btn:HookScript("OnLeave", function(self)
    if not styleActive then return end
    if self.__glassBackdrop then
      self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.4)
      self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.4)
    end
  end)
end

local function SkinSocialButtons(core)
  -- Call on every pass. Individual buttons are idempotent and some Blizzard
  -- buttons are created after RothChat's initial ADDON_LOADED phase.
  SkinOneSocialButton(core, _G.QuickJoinToastButton, false)
  SkinOneSocialButton(core, _G.ChatFrameChannelButton, false)
  SkinOneSocialButton(core, _G.ChatFrameMenuButton, true)
end

local function StripBlizzardChrome(cf)
  local chatName = cf and cf:GetName()
  if not chatName then return end

  local blizzBg = cf.Background or _G[chatName .. "Background"]
  if blizzBg then
    blizzBg:SetAlpha(0)
    blizzBg:Hide()
  end

  StripButtonFrame(cf)

  if cf.ScrollBar then
    cf.ScrollBar:SetAlpha(0)
    cf.ScrollBar:EnableMouse(false)
    cf.ScrollBar:Hide()
  end

  if cf.ScrollToBottomButton and cf.ScrollToBottomButton.Flash then
    cf.ScrollToBottomButton.Flash:SetAlpha(0)
  end
end

local function EnsureChatBackgroundFrame(cf)
  local bg = backgrounds[cf]
  if bg then return bg end

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
  if not bg then return end

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
  if not cf then return end

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

local function DeferApplyAll(core)
  if M.__applyDeferred then return end
  M.__applyDeferred = true
  core:Defer(function()
    M.__applyDeferred = false
    if IsEnabled(core) then ApplyAllToFrames(core) end
  end)
end

QueueApplyAll = function(core)
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
      if not IsEnabled(core) or not tabFrame then return end
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
      if not IsEnabled(core) or not chatFrame then return end
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
  M.__applyDeferred = false
  core:EnsureChatLifecycleHooks()
  RegisterListeners(core)
  EnsureGlobalHooks(core)

  if core:Get("styleEnabled") == false then return end

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
  M.__applyDeferred = false
  NS.CancelScheduled(M)

  for _, bg in pairs(backgrounds) do
    if bg then
      bg:Hide()
      if bg.__border then bg.__border:Hide() end
    end
  end

  for _, cf in ipairs(NS.GetChatFrames()) do
    local name = cf:GetName()
    local eb = name and _G[name .. "EditBox"]
    if eb then SetEditBoxGlassAlpha(eb, EDIT_ALPHA_IDLE) end
  end
end

function M:Refresh(core)
  if not IsEnabled(core) then
    for _, bg in pairs(backgrounds) do
      if bg then bg:Hide() end
    end
    return
  end
  QueueApplyAll(core)
end

RothChat:RegisterModule(M)
