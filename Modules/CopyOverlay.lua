-- RothChat - CopyOverlay module
-- Goal: copy chat text without extra buttons/windows.
-- Implementation: double-click chat frame (or hotspot) -> overlay a scrollable EditBox.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "CopyOverlay",
  defaultEnabled = true,
  description = "Double-click to toggle a copyable overlay over the chat.",
}

local overlays = {} -- [chatFrame] = overlayFrame

local SECRET_PLACEHOLDER = "<SECRET>"
local EMPTY_COPY_PLACEHOLDER = "(No copyable chat lines available.)"

local function SanitizeName(s)
  s = NS.SafeToString(s):gsub("[^%w_]", "_")
  return s == "" and "Chat" or s
end

local function EnsureUISpecialFrame(name)
  if not UISpecialFrames or type(name) ~= "string" then return end
  for _, n in ipairs(UISpecialFrames) do
    if n == name then return end
  end
  table.insert(UISpecialFrames, name)
end

local function SafeStripHyperlinks(text)
  if type(text) ~= "string" then return "" end

  if C_StringUtil and type(C_StringUtil.StripHyperlinks) == "function" then
    local ok, stripped = pcall(C_StringUtil.StripHyperlinks, text, false, true, true, false, false)
    if ok and type(stripped) == "string" then
      return stripped
    end
  end

  if type(_G.StripHyperlinks) == "function" then
    local ok, stripped = pcall(_G.StripHyperlinks, text)
    if ok and type(stripped) == "string" then
      return stripped
    end
  end

  return text
end

local function NormalizeCopyText(text)
  if not NS.CanAccessValue(text) then
    return SECRET_PLACEHOLDER
  end

  if type(text) ~= "string" then
    text = NS.SafeToString(text)
  end

  if text == "" then
    return ""
  end

  -- Temporarily hide literal pipe escapes
  text = text:gsub("||", "\1")

  -- Colors: handle case insensitive e.g., |cFF000000 or |Cff000000
  text = text:gsub("|[cC]%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|[rR]", "")

  -- Textures and Atlases
  text = text:gsub("|[tT].-|[tT]", "")
  text = text:gsub("|[aA].-|[aA]", "")

  -- K codes (often internal tracking/TTS markers)
  text = text:gsub("|[kK].-|[kK]", "")

  -- Hyperlinks: if SafeStripHyperlinks isn't available or fails, this cleans up |H...|hText|h
  text = text:gsub("|[hH].-|[hH](.-)|[hH]", "%1")

  -- Linebreaks
  text = text:gsub("|[nN]", "\n")

  text = SafeStripHyperlinks(text)

  -- Restore literal pipe
  text = text:gsub("\1", "|")

  return strtrim(text)
end

local function CollectFromFontStrings(cf)
  if not cf or type(cf.GetRegions) ~= "function" then return "" end

  local regions = { cf:GetRegions() }
  if #regions == 0 then return "" end

  local out = {}
  for _, r in ipairs(regions) do
    if r and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText then
      local ok, text = pcall(r.GetText, r)
      if ok then
        local normalized = NormalizeCopyText(text)
        if normalized ~= "" then
          out[#out + 1] = normalized
        end
      end
    end
  end

  return table.concat(out, "\n")
end

local function CreateCopyTextBox(parent)
  -- Всегда используем UIPanelScrollFrameTemplate + plain EditBox.
  -- ScrollingEditBoxTemplate рассинхронизирует scroll-позицию и координаты выделения текста.
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:EnableMouse(true)
  eb:SetWidth(1)
  sf:SetScrollChild(eb)

  sf.GetEditBox = function()
    return eb
  end
  sf.SetTextInsets = function(_, left, right, top, bottom)
    if eb.SetTextInsets then
      eb:SetTextInsets(left, right, top, bottom)
    end
  end
  sf.SetText = function(self, text)
    eb:SetText(text or "")
    local w = (self.GetWidth and self:GetWidth() or 64) - 24
    if w > 16 then
      eb:SetWidth(w)
    end
    self:SetVerticalScroll(0)
  end
  sf.GetText = function()
    return eb:GetText()
  end
  sf.SetFocus = function()
    eb:SetFocus()
  end
  sf.ClearFocus = function()
    eb:ClearFocus()
  end
  sf.GetScrollBox = nil
  sf:SetScript("OnSizeChanged", function(self, w)
    if type(w) ~= "number" then return end
    if w > 24 then
      eb:SetWidth(w - 24)
    end
  end)

  return sf, eb
end

local function ApplyOverlayTextStyle(core, overlay)
  if not overlay or not overlay.editBox then
    return
  end

  local eb = overlay.editBox
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local font = core:Get("styleFont") or (LSM and LSM:Fetch("font", "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
  local size = core:Get("styleFontSize") or 12
  local outline = core:Get("styleFontOutline") or ""

  eb:SetFont(font, size, outline)
  eb:SetTextColor(0.95, 0.95, 0.95)
  eb:SetShadowColor(0, 0, 0, 1)
  eb:SetShadowOffset(1, -1)
end

local function BuildOverlay(core, cf)
  if overlays[cf] then return overlays[cf] end

  local baseName = (cf and cf.GetName and cf:GetName()) or ("Chat" .. tostring(cf and cf.GetID and cf:GetID() or 0))
  local overlayName = "RothChatCopyOverlay_" .. SanitizeName(baseName)

  local closer = CreateFrame("Button", overlayName .. "Closer", UIParent)
  closer:SetFrameStrata("DIALOG")
  closer:SetFrameLevel(100)
  closer:SetAllPoints()
  closer:EnableMouse(true)
  closer:SetScript("OnClick", function()
    if overlays[cf] then overlays[cf]:Hide() end
  end)
  closer:Hide()

  local o = CreateFrame("Frame", overlayName, UIParent)
  o:SetFrameStrata("DIALOG")
  o:SetFrameLevel(101)
  o:SetClampedToScreen(true)
  o:EnableMouse(true)
  o:ClearAllPoints()
  o:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
  o:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)

  -- Fully transparent overlay: copy mode should visually replace the chat.
  NS.ApplyGlassBackdrop(o, 0.0, 0, 0)

  o.closer = closer
  o.chatFrame = cf

  local textBox, eb = CreateCopyTextBox(o)
  textBox:SetPoint("TOPLEFT", o, "TOPLEFT", 10, -10)
  textBox:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -10, 10)
  textBox:SetFrameStrata("DIALOG")
  textBox:SetFrameLevel(o:GetFrameLevel() + 1)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:EnableMouse(true)
  if type(eb.SetCountInvisibleLetters) == "function" then
    eb:SetCountInvisibleLetters(false)
  end
  eb.__rothText = ""
  textBox:SetTextInsets(0, 0, 0, 0)
  ApplyOverlayTextStyle(core, o)

  eb:SetScript("OnEscapePressed", function()
    o:Hide()
  end)

  eb:SetScript("OnEnterPressed", function() end)

  eb:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      o:Hide()
      return
    end

    if key == "A" and IsControlKeyDown() then
      self:HighlightText(0, #self:GetText())
    end
  end)

  -- Read-only lock for copy mode.
  eb:SetScript("OnTextChanged", function(self)
    if self.__rothLock then return end
    if self:GetText() ~= (self.__rothText or "") then
      self.__rothLock = true
      self:SetText(self.__rothText or "")
      self.__rothLock = false
      self:HighlightText()
    end
  end)

  o.textBox = textBox
  o.editBox = eb

  o:SetScript("OnShow", function(self)
    closer:Show()

    core:Emit("COPY_OVERLAY_VISIBILITY", cf, true)

    -- Hide chat completely — only copy text visible on transparent overlay
    if cf then
      self._prevChatAlpha = cf:GetAlpha()
      NS.FadeTo(cf, 0, 0.15)
    end

    -- Прокручиваем к концу и даём фокус, но НЕ выделяем текст автоматически —
    -- пользователь сам выделит нужный фрагмент мышью, и копирование будет с правильного места.
    self.__focusScheduleKey = self.__focusScheduleKey or {}
    NS.RunNextFrame(self.__focusScheduleKey, function()
      if not self:IsShown() or not self.textBox then return end

      -- Прокручиваем к концу (самые свежие сообщения внизу)
      if self.textBox.SetVerticalScroll then
        local maxScroll = self.textBox:GetVerticalScrollRange() or 0
        self.textBox:SetVerticalScroll(maxScroll)
      end

      if self.textBox.SetFocus then
        self.textBox:SetFocus()
      end

      if self.editBox then
        self.editBox:SetCursorPosition(#(self.editBox:GetText() or ""))
      end
    end, "RothChat:CopyOverlayFocus")
  end)

  o:SetScript("OnHide", function(self)
    closer:Hide()

    core:Emit("COPY_OVERLAY_VISIBILITY", cf, false)

    -- Restore chat visibility smoothly
    if cf then
      local a = self._prevChatAlpha
      if type(a) ~= "number" then a = 1.0 end
      NS.FadeTo(cf, a, 0.15)
      self._prevChatAlpha = nil
    end

    if self.editBox and self.textBox then
      self.editBox.__rothLock = true
      self.editBox.__rothText = ""
      self.textBox:SetText("")
      self.editBox.__rothLock = false
      self.textBox:ClearFocus()
    end
  end)

  EnsureUISpecialFrame(overlayName)

  o:Hide()
  overlays[cf] = o
  return o
end

local function GetCopyText(core, cf, maxLines)
  local includeTS = core:Get("copyIncludeTimestamps")
  local function NormalizeCandidate(text)
    text = NormalizeCopyText(text)
    if type(text) == "string" and text ~= "" then
      return text
    end
    return nil
  end

  -- Restore module is the primary persistent source
  if core:Get("copyFromHistory") and core.GetRestoreText then
    local ok, result = pcall(core.GetRestoreText, core, cf, maxLines, includeTS)
    if ok and type(result) == "string" then
      result = NormalizeCandidate(result)
      if result then
        return result
      end
    end
  end

  do
    local ok, result = pcall(NS.CollectChatText, cf, maxLines)
    if ok and type(result) == "string" then
      result = NormalizeCandidate(result)
      if result then
        return result
      end
    end
  end

  do
    local result = NormalizeCandidate(CollectFromFontStrings(cf))
    if result then
      return result
    end
  end

  return EMPTY_COPY_PLACEHOLDER
end

local function ToggleOverlay(core, cf)
  if not cf then return end

  cf = (NS.ResolveActiveDockChatFrame and NS.ResolveActiveDockChatFrame(cf)) or cf
  if not cf then return end

  local o = BuildOverlay(core, cf)
  if o:IsShown() then
    o:Hide()
    return
  end

  local maxLines = NS.Clamp(tonumber(core:Get("copyMaxLines")) or 500, 50, 5000)
  local text = GetCopyText(core, cf, maxLines)

  o.editBox.__rothText = text
  o.editBox.__rothLock = true
  o.textBox:SetText(text)
  o.editBox.__rothLock = false

  o:Show()
end

local function HookDoubleClick(core, cf, frame)
  if not frame or frame.__rothCopyHooked then return end
  frame.__rothCopyHooked = true

  local threshold = 0.35
  frame:HookScript("OnMouseUp", function(self, button)
    if not core:IsModuleEnabled("CopyOverlay") then return end
    if button ~= "LeftButton" or IsAltKeyDown() or IsControlKeyDown() or IsShiftKeyDown() then return end

    local t = GetTime()
    local last = self.__rothLastClickTime
    self.__rothLastClickTime = t
    if last and (t - last) <= threshold then
      ToggleOverlay(core, cf)
      self.__rothLastClickTime = 0
    end
  end)
end

local function ApplyToChatFrame(core, cf)
  if not cf then return end
  BuildOverlay(core, cf)
  HookDoubleClick(core, cf, cf)

  if core.GetHotspot then
    local hs = core:GetHotspot(cf)
    if hs then HookDoubleClick(core, cf, hs) end
  end
end

local function ApplyAll(core)
  for _, cf in ipairs(NS.GetChatFrames()) do
    ApplyToChatFrame(core, cf)
  end
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  core:EnsureChatLifecycleHooks()

  if InCombatLockdown() then
    core:Defer(ApplyAll, core)
  else
    ApplyAll(core)
  end

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if not core2:IsModuleEnabled("CopyOverlay") then return end
    if not chatFrame then return end
    ApplyToChatFrame(core2, chatFrame)
  end, self)

  core:On("CHAT_FRAME_CLOSED", function(_, _, chatFrame)
    local o = chatFrame and overlays[chatFrame]
    if o and o:IsShown() then
      o:Hide()
    end
  end, self)
end

function M:OnLogin(core)
end

function M:OnDisable(core)
  for _, o in pairs(overlays) do
    if o then o:Hide() end
  end
end

function M:Refresh(core)
  for _, overlay in pairs(overlays) do
    ApplyOverlayTextStyle(core, overlay)
  end
end

RothChat:RegisterModule(M)
