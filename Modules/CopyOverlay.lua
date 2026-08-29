-- RothChat - CopyOverlay module
-- Double-click a chat frame or its hotspot to open a read-only copy surface.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "CopyOverlay",
  defaultEnabled = true,
  description = "Double-click to toggle a copyable overlay over the chat.",
}

local overlays = {}
local EMPTY_COPY_PLACEHOLDER = "(No copyable chat lines available.)"
local copyActive = false

local function IsEnabled(core)
  return copyActive and core and core:IsModuleActive("CopyOverlay")
end

local function SanitizeName(value)
  value = NS.SafeToString(value):gsub("[^%w_]", "_")
  return value == "" and "Chat" or value
end

local function EnsureUISpecialFrame(name)
  if not UISpecialFrames or type(name) ~= "string" then return end
  for _, existing in ipairs(UISpecialFrames) do
    if existing == name then return end
  end
  table.insert(UISpecialFrames, name)
end

local function CollectFromFontStrings(chatFrame, includeTimestamps)
  if not chatFrame or type(chatFrame.GetRegions) ~= "function" then return "" end

  local out = {}
  for _, region in ipairs({ chatFrame:GetRegions() }) do
    if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
      local ok, text = pcall(region.GetText, region)
      if ok then
        local normalized = NS.NormalizeCopyText(text, includeTimestamps)
        if normalized ~= "" then out[#out + 1] = normalized end
      end
    end
  end

  return table.concat(out, "\n")
end

local function CreateCopyTextBox(parent)
  local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:EnableMouse(true)
  editBox:SetWidth(1)
  scrollFrame:SetScrollChild(editBox)

  scrollFrame.GetEditBox = function() return editBox end
  scrollFrame.SetTextInsets = function(_, left, right, top, bottom)
    if editBox.SetTextInsets then editBox:SetTextInsets(left, right, top, bottom) end
  end
  scrollFrame.SetText = function(self, text)
    editBox:SetText(text or "")
    local width = (self.GetWidth and self:GetWidth() or 64) - 24
    if width > 16 then editBox:SetWidth(width) end
    self:SetVerticalScroll(0)
  end
  scrollFrame.GetText = function() return editBox:GetText() end
  scrollFrame.SetFocus = function() editBox:SetFocus() end
  scrollFrame.ClearFocus = function() editBox:ClearFocus() end
  scrollFrame.GetScrollBox = nil
  scrollFrame:SetScript("OnSizeChanged", function(_, width)
    if type(width) == "number" and width > 24 then editBox:SetWidth(width - 24) end
  end)

  return scrollFrame, editBox
end

local function ApplyOverlayTextStyle(core, overlay)
  if not overlay or not overlay.editBox then return end

  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local font = core:Get("styleFont") or (LSM and LSM:Fetch("font", "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
  local size = core:Get("styleFontSize") or 12
  local outline = core:Get("styleFontOutline") or ""

  overlay.editBox:SetFont(font, size, outline)
  overlay.editBox:SetTextColor(0.95, 0.95, 0.95)
  overlay.editBox:SetShadowColor(0, 0, 0, 1)
  overlay.editBox:SetShadowOffset(1, -1)
end

local function BuildOverlay(core, chatFrame)
  if overlays[chatFrame] then return overlays[chatFrame] end

  local baseName = (chatFrame.GetName and chatFrame:GetName())
    or ("Chat" .. tostring(chatFrame.GetID and chatFrame:GetID() or 0))
  local overlayName = "RothChatCopyOverlay_" .. SanitizeName(baseName)

  local closer = CreateFrame("Button", overlayName .. "Closer", UIParent)
  closer:SetFrameStrata("DIALOG")
  closer:SetFrameLevel(100)
  closer:SetAllPoints()
  closer:EnableMouse(true)
  closer:Hide()

  local overlay = CreateFrame("Frame", overlayName, UIParent)
  overlay:SetFrameStrata("DIALOG")
  overlay:SetFrameLevel(101)
  overlay:SetClampedToScreen(true)
  overlay:EnableMouse(true)
  overlay:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", 0, 0)
  overlay:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 0, 0)
  NS.ApplyGlassBackdrop(overlay, 0, 0, 0)

  overlay.closer = closer
  overlay.chatFrame = chatFrame
  closer:SetScript("OnClick", function() overlay:Hide() end)

  local textBox, editBox = CreateCopyTextBox(overlay)
  textBox:SetPoint("TOPLEFT", overlay, "TOPLEFT", 10, -10)
  textBox:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -10, 10)
  textBox:SetFrameStrata("DIALOG")
  textBox:SetFrameLevel(overlay:GetFrameLevel() + 1)
  if type(editBox.SetCountInvisibleLetters) == "function" then editBox:SetCountInvisibleLetters(false) end
  editBox.__rothText = ""
  textBox:SetTextInsets(0, 0, 0, 0)

  overlay.textBox = textBox
  overlay.editBox = editBox
  ApplyOverlayTextStyle(core, overlay)

  editBox:SetScript("OnEscapePressed", function() overlay:Hide() end)
  editBox:SetScript("OnEnterPressed", function() end)
  editBox:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      overlay:Hide()
    elseif key == "A" and IsControlKeyDown() then
      self:HighlightText(0, #self:GetText())
    end
  end)

  editBox:SetScript("OnTextChanged", function(self)
    if self.__rothLock then return end
    if self:GetText() ~= (self.__rothText or "") then
      self.__rothLock = true
      self:SetText(self.__rothText or "")
      self.__rothLock = false
      self:HighlightText()
    end
  end)

  overlay:SetScript("OnShow", function(self)
    closer:Show()

    -- Snapshot before listeners or fades can change the frame.
    self._prevChatAlpha = chatFrame:GetAlpha()
    core:Emit("COPY_OVERLAY_VISIBILITY", chatFrame, true)
    NS.FadeTo(chatFrame, 0, 0.15)

    self.__focusScheduleKey = self.__focusScheduleKey or {}
    NS.RunNextFrame(self.__focusScheduleKey, function()
      if not self:IsShown() then return end
      local maxScroll = self.textBox:GetVerticalScrollRange() or 0
      self.textBox:SetVerticalScroll(maxScroll)
      self.textBox:SetFocus()
      self.editBox:SetCursorPosition(#(self.editBox:GetText() or ""))
    end, "RothChat:CopyOverlayFocus")
  end)

  overlay:SetScript("OnHide", function(self)
    closer:Hide()
    NS.CancelScheduled(self.__focusScheduleKey)

    -- Restore first, then let Controls/Ticker establish the authoritative final
    -- alpha for the current hover/immersion state.
    local previousAlpha = self._prevChatAlpha
    if type(previousAlpha) ~= "number" then previousAlpha = 1 end
    NS.FadeTo(chatFrame, previousAlpha, 0.15)
    self._prevChatAlpha = nil

    self.editBox.__rothLock = true
    self.editBox.__rothText = ""
    self.textBox:SetText("")
    self.editBox.__rothLock = false
    self.textBox:ClearFocus()

    core:Emit("COPY_OVERLAY_VISIBILITY", chatFrame, false)
  end)

  EnsureUISpecialFrame(overlayName)
  overlay:Hide()
  overlays[chatFrame] = overlay
  return overlay
end

local function GetCopyText(core, chatFrame, maxLines)
  local includeTimestamps = core:Get("copyIncludeTimestamps")
  local function NormalizeCandidate(text)
    text = NS.NormalizeCopyText(text, includeTimestamps)
    if text ~= "" then return text end
    return nil
  end

  if core:Get("copyFromHistory") and core.GetRestoreText then
    local ok, result = pcall(core.GetRestoreText, core, chatFrame, maxLines, includeTimestamps)
    if ok and type(result) == "string" then
      result = NormalizeCandidate(result)
      if result then return result end
    end
  end

  do
    local ok, result = pcall(NS.CollectChatText, chatFrame, maxLines)
    if ok and type(result) == "string" then
      result = NormalizeCandidate(result)
      if result then return result end
    end
  end

  local fallback = CollectFromFontStrings(chatFrame, includeTimestamps)
  return fallback ~= "" and fallback or EMPTY_COPY_PLACEHOLDER
end

local function ToggleOverlay(core, chatFrame)
  if not IsEnabled(core) or not chatFrame then return end
  chatFrame = (NS.ResolveActiveDockChatFrame and NS.ResolveActiveDockChatFrame(chatFrame)) or chatFrame
  if not chatFrame then return end

  local overlay = BuildOverlay(core, chatFrame)
  if overlay:IsShown() then
    overlay:Hide()
    return
  end

  local maxLines = NS.Clamp(tonumber(core:Get("copyMaxLines")) or 500, 50, 5000)
  local text = GetCopyText(core, chatFrame, maxLines)
  overlay.editBox.__rothText = text
  overlay.editBox.__rothLock = true
  overlay.textBox:SetText(text)
  overlay.editBox.__rothLock = false
  overlay:Show()
end

local function HookDoubleClick(core, chatFrame, frame)
  if not frame or frame.__rothCopyHooked then return end
  frame.__rothCopyHooked = true

  local threshold = 0.35
  frame:HookScript("OnMouseUp", function(self, button)
    if not IsEnabled(core) then return end
    if button ~= "LeftButton" or IsAltKeyDown() or IsControlKeyDown() or IsShiftKeyDown() then return end

    local now = GetTime()
    local previous = self.__rothLastClickTime
    self.__rothLastClickTime = now
    if previous and (now - previous) <= threshold then
      ToggleOverlay(core, chatFrame)
      self.__rothLastClickTime = 0
    end
  end)
end

local function ApplyToChatFrame(core, chatFrame)
  if not chatFrame then return end
  BuildOverlay(core, chatFrame)
  HookDoubleClick(core, chatFrame, chatFrame)

  if core.GetHotspot then
    local hotspot = core:GetHotspot(chatFrame)
    if hotspot then HookDoubleClick(core, chatFrame, hotspot) end
  end
end

local function ApplyAll(core)
  for _, chatFrame in ipairs(NS.GetChatFrames()) do ApplyToChatFrame(core, chatFrame) end
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  copyActive = true
  core:EnsureChatLifecycleHooks()

  if InCombatLockdown() then
    core:Defer(function()
      if IsEnabled(core) then ApplyAll(core) end
    end)
  else
    ApplyAll(core)
  end

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if IsEnabled(core2) and chatFrame then ApplyToChatFrame(core2, chatFrame) end
  end, self)

  core:On("CHAT_FRAME_CLOSED", function(_, _, chatFrame)
    local overlay = chatFrame and overlays[chatFrame]
    if overlay and overlay:IsShown() then overlay:Hide() end
  end, self)
end

function M:OnLogin(core)
end

function M:OnDisable(core)
  copyActive = false
  for _, overlay in pairs(overlays) do
    if overlay then overlay:Hide() end
  end
end

function M:Refresh(core)
  for _, overlay in pairs(overlays) do ApplyOverlayTextStyle(core, overlay) end
end

RothChat:RegisterModule(M)
