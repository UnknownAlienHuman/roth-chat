-- RothChat - Style module
-- Responsibilities:
--   * Chat font + text shadow tuning
--   * Optional "glass" background behind chat windows
--   * EditBox skinning & positioning (ls_Glass style)
--   * ScrollToBottom button skinning (scroll-buttons.TGA atlas)
--   * Chat tab skinning (backdrop + border-highlight)
--   * ButtonFrame chrome removal (per-texture, like ls_Glass)

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Style",
  defaultEnabled = true,
  description = "Fonts, shadows, and ls_Glass visual style.",
}

local backgrounds = {} -- [chatFrame] = bgFrame
local QueueApplyAll -- forward
local DEFAULT_BG_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_BORDER_TEXTURE = NS.BORDER_TEXTURE or "Interface\\AddOns\\RothChat\\Assets\\border"
local DEFAULT_EDIT_CURSOR_BLINK = 0.85

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

-- ============================================================================
-- BUTTON FRAME CHROME: all 9 textures like ls_Glass
-- ============================================================================
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

local function StripButtonFrame(cf)
  local chatName = cf:GetName()
  if not chatName then return end
  local btnFrame = _G[chatName .. "ButtonFrame"]
  if not btnFrame then return end

  -- Zero out textures instead of hiding the frame entirely
  for _, texName in ipairs(BUTTON_FRAME_TEXTURES) do
    local obj = _G[btnFrame:GetName() .. texName]
    if obj and obj.SetTexture then
      obj:SetTexture(0)
    end
  end
  -- Increased width slightly to ensure scroll buttons aren't clipped
  -- and provide a bit more breathing room on the right edge.
  btnFrame:SetWidth(28)
end

-- ============================================================================
-- EDIT BOX: hide Blizz textures, backdrop with border.TGA
-- ============================================================================
local EDIT_BOX_TEXTURES = {
  "Left", "Mid", "Right",
  "FocusLeft", "FocusMid", "FocusRight",
}


-- EditBox backdrop behavior (ls_Glass-inspired):
--   * no placeholder/underlay when idle
--   * slight darkening when focused
--   * slightly stronger darkening while typing
local EDIT_ALPHA_IDLE  = 0.0
local EDIT_ALPHA_FOCUS = 0.22
local EDIT_ALPHA_TEXT  = 0.32

local function SetEditBoxGlassAlpha(eb, alpha)
  if not eb then return end
  alpha = alpha or 0
  if eb.__rothEditAlpha == alpha then return end
  eb.__rothEditAlpha = alpha
  NS.ApplyGlassLook(eb, alpha)
  if NS.UpdateGlassSize then NS.UpdateGlassSize(eb) end
end

local function KillEditBoxUnderlayTextures(eb)
  if not eb or not eb.GetNumRegions then return end
  for i = 1, eb:GetNumRegions() do
    local region = select(i, eb:GetRegions())
    if region and region.GetObjectType and region:GetObjectType() == 'Texture' then
      if region ~= eb.glassLeft and region ~= eb.glassCenter and region ~= eb.glassRight and region ~= eb.glassSolid and region ~= eb.glassBorder then
        if region.SetTexture then region:SetTexture(0) end
        if region.SetAlpha then region:SetAlpha(0) end
        if region.Hide then region:Hide() end
      end
    end
  end

  -- Some builds expose extra named textures on the editbox itself.
  local name = eb.GetName and eb:GetName()
  if name then
    local suffixes = {"Background", "Bg", "Backdrop", "Border"}
    for i = 1, #suffixes do
      local t = _G[name .. suffixes[i]]
      if t and t.SetTexture then
        t:SetTexture(0)
        if t.SetAlpha then t:SetAlpha(0) end
        if t.Hide then t:Hide() end
      end
    end
  end

  -- Clear any backdrop Blizzard may have set on the editbox
  if eb.SetBackdrop then eb:SetBackdrop(nil) end
end

local function RefreshEditBoxInsets(eb)
  if not eb or type(eb.GetTextInsets) ~= "function" or type(eb.SetTextInsets) ~= "function" then
    return
  end

  local left, right, top, bottom = eb:GetTextInsets()
  left = math.max(8, tonumber(left) or 0)
  right = math.max(8, tonumber(right) or 0)
  top = math.max(4, tonumber(top) or 0)
  bottom = math.max(4, tonumber(bottom) or 0)
  eb:SetTextInsets(left, right, top, bottom)
end

local function SkinEditBox(core, cf)
  local name = cf:GetName()
  if not name then return end
  local eb = _G[name.."EditBox"]
  if not eb then return end

  -- Hide ALL Blizz editbox textures by name (like ls_Glass)
  for _, texName in ipairs(EDIT_BOX_TEXTURES) do
    local tex = _G[name .. "EditBox" .. texName] or _G[eb:GetName() .. texName]
    if tex then
      tex:SetTexture(0)
      tex:SetAlpha(0)
      tex:Hide()
    end
  end

  -- Also catch any remaining ChatFrameEditBox / UI-ChatInputBorder textures
  for i = 1, eb:GetNumRegions() do
    local region = select(i, eb:GetRegions())
    if region and region:GetObjectType() == "Texture" then
      local tex = region:GetTexture()
      if tex and (type(tex) == "string") and (tex:find("ChatFrameEditBox") or tex:find("UI%-ChatInputBorder")) then
        region:SetTexture(0)
        region:SetAlpha(0)
        region:Hide()
      end
    end
  end

  -- Clear any backdrop set by Blizzard on the editbox itself
  if eb.SetBackdrop then eb:SetBackdrop(nil) end


  -- Apply glass background only when focused/typing (no fake placeholder when idle)
  if not eb.__glassStyled then
    eb.__glassStyled = true
    SetEditBoxGlassAlpha(eb, EDIT_ALPHA_IDLE)

    if not eb.__rothEditHooks then
      eb.__rothEditHooks = true
      eb:HookScript('OnEditFocusGained', function(self)
        -- Re-suppress Blizzard textures that may reappear on focus
        KillEditBoxUnderlayTextures(self)
        local a = (self:GetText() and self:GetText() ~= '') and EDIT_ALPHA_TEXT or EDIT_ALPHA_FOCUS
        SetEditBoxGlassAlpha(self, a)
      end)
      eb:HookScript('OnEditFocusLost', function(self)
        SetEditBoxGlassAlpha(self, EDIT_ALPHA_IDLE)
      end)
      eb:HookScript('OnTextChanged', function(self, userInput)
        if not userInput then return end
        if not self:HasFocus() then return end
        local a = (self:GetText() and self:GetText() ~= '') and EDIT_ALPHA_TEXT or EDIT_ALPHA_FOCUS
        SetEditBoxGlassAlpha(self, a)
      end)

      if type(eb.UpdateHeader) == "function" then
        hooksecurefunc(eb, "UpdateHeader", RefreshEditBoxInsets)
      end
    end
  end

  -- Ensure any remaining Blizzard underlay textures are removed.
  KillEditBoxUnderlayTextures(eb)

  -- Font
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local font = core:Get("styleFont") or (LSM and LSM:Fetch("font", "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
  local size = core:Get("styleFontSize") or 12
  eb:SetFont(font, size, "")
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

  -- Positioning
  local pos = core:Get("editBoxPosition") or "BOTTOM"
  eb:ClearAllPoints()
  eb:SetHeight(24)

  if pos == "TOP" then
    eb:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 24)
    eb:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 0, 24)
  else
    eb:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, -24)
    eb:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, -24)
  end

  if type(eb.UpdateHeader) == "function" then
    eb:UpdateHeader()
  end
  RefreshEditBoxInsets(eb)
end

-- ============================================================================
-- SCROLL TO BOTTOM BUTTON: atlas from scroll-buttons.TGA
-- ============================================================================
local function SkinScrollButton(core, cf)
  local btn = cf.ScrollToBottomButton
  if not btn then return end

  if not btn.__rothSkinned then
    btn.__rothSkinned = true

    -- Kill all Blizz textures
    btn:SetNormalTexture(0)
    btn:SetPushedTexture(0)
    if btn.SetDisabledTexture then btn:SetDisabledTexture(0) end
    btn:SetHighlightTexture(0)
    if btn.Flash then btn.Flash:SetAlpha(0) end

    -- Size: 24x24 like ls_Glass
    btn:SetSize(24, 24)

    -- Anchor slightly inside the frame to prevent clipping by SetClipsChildren(true)
    -- and align with the restyled ButtonFrame chrome.
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -2, 2)

    -- Backdrop with border.TGA
    NS.ApplyGlassBackdrop(btn, 0.8, 0, 0)

    -- Icon from scroll-buttons atlas
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    icon:SetTexture(NS.SCROLL_BTN_TEXTURE)
    local tc = NS.SCROLL_ICONS.TO_BOTTOM
    icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    btn.__scrollIcon = icon

    -- 3-part highlight
    NS.CreateHighlight(btn, "HIGHLIGHT", nil, nil, nil, 0)

    -- Hover alpha
    btn:HookScript("OnEnter", function()
      if btn.__glassBackdrop then
        btn.__glassBackdrop:SetBackdropColor(0, 0, 0, 1)
        btn.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 1)
      end
    end)
    btn:HookScript("OnLeave", function()
      if btn.__glassBackdrop then
        btn.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.8)
        btn.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.8)
      end
    end)
  end
end

-- ============================================================================
-- CHAT TABS: backdrop + 3-part border-highlight
-- ============================================================================
-- CHAT TABS: strip Blizz chrome, restyle highlight/active, enforce 20px
-- ============================================================================
local function SkinChatTab(core, cf)
  local chatName = cf:GetName()
  if not chatName then return end
  local tab = _G[chatName .. "Tab"]
  if not tab or tab.__rothTabSkinned then return end
  tab.__rothTabSkinned = true

  -- Nuke ALL background textures on the tab by iterating all regions.
  -- This catches Left/Middle/Right, atlas textures, and any version-specific textures.
  local regions = { tab:GetRegions() }
  local text = tab.Text or tab:GetFontString()
  for _, region in ipairs(regions) do
    if region:IsObjectType("Texture") then
      local drawLayer = region:GetDrawLayer()
      -- Hide background/border textures but preserve OVERLAY (glow, highlight)
      if drawLayer == "BACKGROUND" or drawLayer == "BORDER" or drawLayer == "ARTWORK" then
        -- Don't hide the active/highlight textures we want to restyle
        if region ~= tab.ActiveLeft and region ~= tab.ActiveMiddle and region ~= tab.ActiveRight
          and region ~= tab.HighlightLeft and region ~= tab.HighlightMiddle and region ~= tab.HighlightRight
          and region ~= tab.glow then
          region:SetTexture(0)
          region:SetAtlas("")
          region:SetSize(0.001, 0.001)
          region:Hide()
        end
      end
    end
  end

  -- Compact height: 20px
  tab:SetHeight(20)

  -- Hooks to prevent Blizzard from resizing
  hooksecurefunc(tab, "SetHeight", function(self, h)
    if self.__rothFixingHeight then return end
    if h ~= 20 then
      self.__rothFixingHeight = true
      self:SetHeight(20)
      self.__rothFixingHeight = nil
    end
  end)
  hooksecurefunc(tab, "SetSize", function(self, w, h)
    if self.__rothFixingHeight then return end
    if h ~= 20 then
      self.__rothFixingHeight = true
      self:SetSize(w, 20)
      self.__rothFixingHeight = nil
    end
  end)

  -- Reposition text: centered vertically in 20px
  if text then
    hooksecurefunc(text, "SetPoint", function(self, p, anchor, rP, x, y, shouldIgnore)
      if not shouldIgnore then
        self:SetPoint(p, anchor, rP, p == "LEFT" and 8 or x, p == "CENTER" and 0 or y, true)
      end
    end)
    text:SetShadowColor(0, 0, 0, 0.8)
    text:SetShadowOffset(1, -1)
  end

  -- Hide duplicate decorative FontStrings (e.g. Blizzard adds extra labels on some
  -- tab templates). Keep ANY FontString that carries actual text — only hide truly
  -- empty/whitespace ones that are not the primary label.
  do
    local keep = text or (tab.GetFontString and tab:GetFontString())
    local regs = { tab:GetRegions() }
    for _, r in ipairs(regs) do
      if r and r.IsObjectType and r:IsObjectType("FontString") and r ~= keep then
        local t = r.GetText and r:GetText()
        if not t or strtrim(t) == "" then
          r:Hide()
        end
      end
    end
  end

  -- Reposition glow (unread indicator)
  if tab.glow then
    tab.glow:ClearAllPoints()
    tab.glow:SetPoint("BOTTOMLEFT", 8, 2)
    tab.glow:SetPoint("BOTTOMRIGHT", -8, 2)
  end

  -- Restyle Highlight textures (mouseover effect)
  if tab.HighlightLeft then
    tab.HighlightLeft:ClearAllPoints()
    tab.HighlightLeft:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -2)
    tab.HighlightLeft:SetTexture(NS.BORDER_HL_TEXTURE)
    tab.HighlightLeft:SetTexCoord(0, 1, 0.5, 1)
    tab.HighlightLeft:SetSize(8, 8)
    tab.HighlightLeft:Show()
  end
  if tab.HighlightRight then
    tab.HighlightRight:ClearAllPoints()
    tab.HighlightRight:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, -2)
    tab.HighlightRight:SetTexture(NS.BORDER_HL_TEXTURE)
    tab.HighlightRight:SetTexCoord(1, 0, 0.5, 1)
    tab.HighlightRight:SetSize(8, 8)
    tab.HighlightRight:Show()
  end
  if tab.HighlightMiddle then
    tab.HighlightMiddle:ClearAllPoints()
    tab.HighlightMiddle:SetPoint("TOPLEFT", tab.HighlightLeft, "TOPRIGHT", 0, 0)
    tab.HighlightMiddle:SetPoint("TOPRIGHT", tab.HighlightRight, "TOPLEFT", 0, 0)
    tab.HighlightMiddle:SetTexture(NS.BORDER_HL_TEXTURE)
    tab.HighlightMiddle:SetTexCoord(0, 1, 0, 0.5)
    tab.HighlightMiddle:SetSize(8, 8)
    tab.HighlightMiddle:Show()
  end

  -- Restyle Active textures (selected tab indicator)
  if tab.ActiveLeft then
    tab.ActiveLeft:ClearAllPoints()
    tab.ActiveLeft:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -2)
    tab.ActiveLeft:SetTexture(NS.BORDER_HL_TEXTURE)
    tab.ActiveLeft:SetTexCoord(0, 1, 0.5, 1)
    tab.ActiveLeft:SetSize(8, 8)
    tab.ActiveLeft:Show()
  end
  if tab.ActiveRight then
    tab.ActiveRight:ClearAllPoints()
    tab.ActiveRight:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, -2)
    tab.ActiveRight:SetTexture(NS.BORDER_HL_TEXTURE)
    tab.ActiveRight:SetTexCoord(1, 0, 0.5, 1)
    tab.ActiveRight:SetSize(8, 8)
    tab.ActiveRight:Show()
  end
  if tab.ActiveMiddle then
    tab.ActiveMiddle:ClearAllPoints()
    tab.ActiveMiddle:SetPoint("TOPLEFT", tab.ActiveLeft, "TOPRIGHT", 0, 0)
    tab.ActiveMiddle:SetPoint("TOPRIGHT", tab.ActiveRight, "TOPLEFT", 0, 0)
    tab.ActiveMiddle:SetTexture(NS.BORDER_HL_TEXTURE)
    tab.ActiveMiddle:SetTexCoord(0, 1, 0, 0.5)
    tab.ActiveMiddle:SetSize(8, 8)
    tab.ActiveMiddle:Show()
  end

  -- Reset text position to trigger hooks
  if text and text.GetPoint and pcall(text.GetPoint, text, 1) then
    text:SetPoint(text:GetPoint(1))
  end
end

-- ============================================================================
-- SOCIAL/SYSTEM BUTTONS: QuickJoinToast, ChannelButton, MenuButton
-- ============================================================================
local function SkinOneSocialButton(btn, skipNormal)
  if not btn or btn.__rothSocialSkinned then return end
  btn.__rothSocialSkinned = true

  -- Only strip the chrome textures, NOT the icon
  -- skipNormal=true for buttons whose icon IS the normal texture (e.g. MenuButton)
  if not skipNormal and btn.SetNormalTexture then btn:SetNormalTexture(0) end
  if btn.SetPushedTexture then btn:SetPushedTexture(0) end
  if btn.SetHighlightTexture then btn:SetHighlightTexture(0) end
  if btn.SetDisabledTexture then pcall(btn.SetDisabledTexture, btn, 0) end

  -- Compact size
  btn:SetSize(24, 24)

  -- Glass backdrop + highlight
  NS.ApplyGlassBackdrop(btn, 0.4, 0, 0)
  NS.CreateHighlight(btn, "HIGHLIGHT", nil, nil, nil, 0)

  -- Hover effects
  btn:HookScript("OnEnter", function(self)
    if self.__glassBackdrop then
      self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.7)
      self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.7)
    end
  end)
  btn:HookScript("OnLeave", function(self)
    if self.__glassBackdrop then
      self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.4)
      self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.4)
    end
  end)
end

local function SkinSocialButtons(core)
  SkinOneSocialButton(_G.QuickJoinToastButton, false)
  SkinOneSocialButton(_G.ChatFrameChannelButton, false)
  SkinOneSocialButton(_G.ChatFrameMenuButton, true) -- MenuButton icon IS the normal texture
end

-- ============================================================================
-- BLIZZARD CHROME: hide background, glow, tab extras
-- ============================================================================
local function StripBlizzardChrome(cf)
  local chatName = cf:GetName()
  if not chatName then return end

  -- Background frame
  local blizzBg = cf.Background or _G[chatName .. "Background"]
  if blizzBg then blizzBg:SetAlpha(0) blizzBg:Hide() end

  -- Keep TabGlow active. Blizzard uses this texture for unread whisper flashes.
  local tabGlow = _G[chatName .. "TabGlow"]
  if tabGlow then
    tabGlow:SetAlpha(1)
  end

  -- ButtonFrame chrome
  StripButtonFrame(cf)

  -- Hide Blizz ScrollBar (the big arrow overlay) — we have our own ScrollToBottom
  if cf.ScrollBar then
    cf.ScrollBar:SetAlpha(0)
    cf.ScrollBar:EnableMouse(false)
    if cf.ScrollBar.Hide then cf.ScrollBar:Hide() end
  end

  -- Also hide the Blizz ScrollToBottomButton's Flash overlay
  local stb = cf.ScrollToBottomButton
  if stb and stb.Flash then stb.Flash:SetAlpha(0) end
end

local function EnsureChatBackgroundFrame(cf)
  local bg = backgrounds[cf]
  if bg then
    return bg
  end

  -- Use cf:GetParent() so the background isn't clipped by cf:SetClipsChildren(true).
  -- This is critical for smooth scrolling to work without cutting off the borders.
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
  if type(texture) ~= "string" or texture == "" then
    texture = DEFAULT_BG_TEXTURE
  end
  local fillR, fillG, fillB = ParseHexColor(core:Get("styleBackgroundColor"), 0, 0, 0)

  if bg.__fill then
    bg.__fill:SetTexture(texture)
    bg.__fill:SetVertexColor(fillR, fillG, fillB, alpha)
    bg.__fill:Show()
  end

  -- If older builds created gradient textures on this frame, keep them hidden.
  if bg.glassLeft then bg.glassLeft:Hide() end
  if bg.glassCenter then bg.glassCenter:Hide() end
  if bg.glassRight then bg.glassRight:Hide() end
  if bg.glassSolid then bg.glassSolid:Hide() end

  if core:Get("styleBorder") then
    if not bg.__border then
      bg.__border = CreateFrame("Frame", nil, bg, "BackdropTemplate")
      bg.__border:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
      bg.__border:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
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

-- ============================================================================
-- MAIN: apply all styling to a chat frame
-- ============================================================================
local function ApplyToChatFrame(core, cf)
  if not cf then return end

  -- Font
  local font = core:Get("styleFont")
  local size = core:Get("styleFontSize") or 12
  local outline = core:Get("styleFontOutline") or ""

  if not font then
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    font = LSM and LSM:Fetch("font", "Friz Quadrata TT") or "Fonts\\FRIZQT__.TTF"
  end

  if type(cf.SetFont) == "function" then
    cf:SetFont(font, size, outline)
  end
  local useShadow = core:Get("styleShadow")
  if type(cf.SetShadowColor) == "function" then
    if useShadow then
      cf:SetShadowColor(0, 0, 0, 0.55)
    else
      cf:SetShadowColor(0, 0, 0, 0)
    end
  end
  if type(cf.SetShadowOffset) == "function" then
    if useShadow then
      cf:SetShadowOffset(1, -1)
    else
      cf:SetShadowOffset(0, 0)
    end
  end

  -- Skin components
  SkinEditBox(core, cf)
  SkinScrollButton(core, cf)
  SkinChatTab(core, cf)
  StripBlizzardChrome(cf)

  -- Social buttons (only once, for first chat frame)
  if cf == _G.ChatFrame1 and not M.__socialSkinned then
    M.__socialSkinned = true
    SkinSocialButtons(core)
  end

  -- Configurable background texture under the entire chat field.
  local wantBG = core:Get("styleBackground")

  if wantBG then
    ApplyChatBackgroundStyle(core, cf)
  elseif backgrounds[cf] then
    backgrounds[cf]:Hide()
  end
end

local function ApplyAllToFrames(core)
  for _, cf in ipairs(NS.GetChatFrames()) do
    ApplyToChatFrame(core, cf)
  end
end

QueueApplyAll = function(core)
  if M.__applyQueued then return end
  M.__applyQueued = true
  NS.RunNextFrame(M, function()
    M.__applyQueued = false
    if not core or not core:IsModuleEnabled("Style") then return end
    if not core:Get("styleEnabled") then return end
    ApplyAllToFrames(core)
  end, "RothChat:StyleApplyAll")
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  if not core:Get("styleEnabled") then
    self:OnDisable(core)
    return
  end
  local function ApplyAll()
    core:OffOwner(self)
    core:EnsureChatLifecycleHooks()
    ApplyAllToFrames(core)

    core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
      if not core2:IsModuleEnabled("Style") then return end
      if not core2:Get("styleEnabled") then return end
      QueueApplyAll(core2)
    end, self)

    core:On("COPY_OVERLAY_VISIBILITY", function(_, core2, chatFrame, visible)
      local bg = chatFrame and backgrounds[chatFrame]
      if not bg then return end

      bg.__rothCopyHidden = visible and true or false
      if visible then
        bg:Hide()
        if bg.__border then bg.__border:Hide() end
      elseif core2:IsModuleEnabled("Style") and core2:Get("styleEnabled") and core2:Get("styleBackground") then
        ApplyChatBackgroundStyle(core2, chatFrame)
      end
    end, self)

    -- Global hooks for consistent tab sizing
    if not M.__tabUpdateHooked then
      M.__tabUpdateHooked = true

      -- FCFTab_UpdateColors fires for ALL tabs on every state change.
      -- We use it to: (a) re-apply 20px height, (b) auto-skin unskinned tabs.
      hooksecurefunc("FCFTab_UpdateColors", function(tabFrame, selected)
        if not tabFrame then return end
        -- Auto-skin any tab we haven't seen yet
        if not tabFrame.__rothTabSkinned then
          -- Find the associated chat frame
          local tabName = tabFrame:GetName()
          if tabName then
            local cfName = tabName:gsub("Tab$", "")
            local cf = _G[cfName]
            if cf then
              SkinChatTab(core, cf)
            end
          end
        end
        -- Always enforce 20px
        if tabFrame.__rothTabSkinned then
          if tabFrame.__rothFixingHeight then return end
          tabFrame.__rothFixingHeight = true
          tabFrame:SetHeight(20)
          tabFrame.__rothFixingHeight = nil
        end
      end)

      -- FCFTab_UpdateAlpha fires for alpha changes
      if FCFTab_UpdateAlpha then
        hooksecurefunc("FCFTab_UpdateAlpha", function(tabFrame)
          if tabFrame and tabFrame.__rothTabSkinned then
            if tabFrame.__rothFixingHeight then return end
            tabFrame.__rothFixingHeight = true
            tabFrame:SetHeight(20)
            tabFrame.__rothFixingHeight = nil
          end
        end)
      end

      -- Tooltip anchoring: chat tooltips follow cursor (use default anchor)
      hooksecurefunc("SetItemRef", function()
        if GameTooltip and GameTooltip:IsShown() then
          GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        end
      end)
    end
  end

  if InCombatLockdown() then
    core:Defer(ApplyAll)
  else
    ApplyAll()
  end
end

function M:OnLogin(core)
  QueueApplyAll(core)
end

function M:OnDisable(core)
  for _, bg in pairs(backgrounds) do
    if bg then bg:Hide() end
  end
end

function M:Refresh(core)
  if not core:IsModuleEnabled("Style") or not core:Get("styleEnabled") then
    self:OnDisable(core)
    return
  end
  QueueApplyAll(core)
end

RothChat:RegisterModule(M)
