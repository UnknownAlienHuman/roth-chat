-- CopyOverlay drops an open copy surface when chat restrictions start and
-- cannot fetch chat history while the restriction is active.

local function newWidget(kind, name)
  local widget = { kind = kind, name = name, scripts = {}, hooks = {}, shown = false, text = "", width = 400 }
  function widget:SetSize() end
  function widget:SetPoint() end
  function widget:SetAllPoints() end
  function widget:EnableMouse() end
  function widget:SetFrameStrata() end
  function widget:SetFrameLevel(value) self.frameLevel = value end
  function widget:GetFrameLevel() return self.frameLevel or 1 end
  function widget:SetClampedToScreen() end
  function widget:SetBackdrop() end
  function widget:SetScript(event, callback) self.scripts[event] = callback end
  function widget:HookScript(event, callback) self.hooks[event] = callback end
  function widget:SetMultiLine() end
  function widget:SetAutoFocus() end
  function widget:SetWidth(value) self.width = value end
  function widget:GetWidth() return self.width end
  function widget:SetHeight() end
  function widget:SetScrollChild() end
  function widget:SetVerticalScroll(value) self.verticalScroll = value end
  function widget:GetVerticalScrollRange() return 0 end
  function widget:SetText(value) self.text = value or "" end
  function widget:GetText() return self.text end
  function widget:ClearFocus() self.focused = false end
  function widget:SetFocus() self.focused = true end
  function widget:HighlightText() end
  function widget:SetTextInsets() end
  function widget:SetFont() end
  function widget:SetCursorPosition() end
  function widget:SetTextColor() end
  function widget:SetShadowColor() end
  function widget:SetShadowOffset() end
  function widget:SetCountInvisibleLetters() end
  function widget:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  function widget:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
  end
  function widget:IsShown() return self.shown end
  function widget:CreateFontString(_, layer)
    return newWidget("FontString", nil)
  end
  return widget
end

local createdFrames = {}
_G.CreateFrame = function(kind, name)
  local widget = newWidget(kind, name)
  createdFrames[#createdFrames + 1] = widget
  if type(name) == "string" then _G[name] = widget end
  return widget
end
_G.UIParent = newWidget("Frame", "UIParent")
_G.UISpecialFrames = {}
_G.GetTime = function() return 1 end
_G.InCombatLockdown = function() return false end
_G.IsControlKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.IsShiftKeyDown = function() return false end

local restricted = false
local registeredModule
local restrictionListener
local historyReads = 0
local chatFrame = newWidget("ScrollingMessageFrame", "ChatFrame1")
chatFrame.GetName = function() return "ChatFrame1" end
chatFrame.GetID = function() return 1 end
chatFrame.GetAlpha = function() return 1 end

_G.RothChat = {
  RegisterModule = function(_, module) registeredModule = module end,
}

local NS = {
  IsChatMessagingRestricted = function() return restricted end,
  IsActiveChatFrame = function(candidate) return candidate == chatFrame end,
  SafeToString = tostring,
  GetActiveChatFrames = function() return { chatFrame } end,
  ApplyGlassBackdrop = function() end,
  RunNextFrame = function(_, callback) callback() end,
  CancelScheduled = function() end,
  FadeTo = function() end,
  Clamp = function(value, low, high) return math.max(low, math.min(high, value)) end,
  NormalizeCopyText = function(text, includeTimestamps)
    if restricted then return "" end
    return text
  end,
  CollectChatText = function() return "native history" end,
}

assert(loadfile("Modules/CopyOverlay.lua"))("RothChat", NS)
local module = assert(registeredModule)
local core = {
  Get = function(_, key)
    if key == "copyIncludeTimestamps" then return false end
    if key == "copyFromHistory" then return true end
    if key == "copyMaxLines" then return 100 end
  end,
  IsModuleActive = function(_, name) return name == "CopyOverlay" end,
  EnsureChatLifecycleHooks = function() end,
  GetHotspot = function() return nil end,
  GetRestoreText = function()
    historyReads = historyReads + 1
    return "previously displayed chat"
  end,
  Emit = function() end,
  On = function(_, event, callback)
    if event == "CHAT_RESTRICTION_CHANGED" then restrictionListener = callback end
  end,
}

module:Init(core)
module:OnEnable(core)
local overlay = assert(_G.RothChatCopyOverlay_ChatFrame1)
local doubleClick = assert(chatFrame.hooks.OnMouseUp)
doubleClick(chatFrame, "LeftButton")
doubleClick(chatFrame, "LeftButton")
assert(overlay:IsShown())
assert(overlay.editBox:GetText() == "previously displayed chat")
assert(historyReads == 1)

restricted = true
restrictionListener(nil, core, true)
assert(not overlay:IsShown(), "active copy UI must close when chat restrictions start")
assert(overlay.editBox:GetText() == "", "restricted transition must clear retained copy text")

doubleClick(chatFrame, "LeftButton")
doubleClick(chatFrame, "LeftButton")
assert(historyReads == 1, "copying while restricted must not read persisted or native history")
assert(not overlay:IsShown())

restricted = false
restrictionListener(nil, core, false)
assert(not overlay:IsShown(), "cleared restrictions must not replay or reopen old copy content")
assert(overlay.editBox:GetText() == "")

module:OnDisable(core)
print("copy_overlay_lockdown_spec: ok")
