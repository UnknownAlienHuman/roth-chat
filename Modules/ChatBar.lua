-- RothChat - ChatBar module
-- Diablo-ish minimal channel bar that appears on hover through Controls.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "ChatBar",
  defaultEnabled = true,
  description = "Mouseover channel bar (Say/Party/Raid/Instance/Guild/Whisper...).",
}

local bar
local lastRestrictedNotice = 0
local listenersRegistered = false
local ApplyBar

local BUTTONS = {
  { id = "SAY",      label = "S",  tip = "Say",                 text = "/s " },
  { id = "PARTY",    label = "P",  tip = "Party",               text = "/p " },
  { id = "RAID",     label = "R",  tip = "Raid",                text = "/raid " },
  { id = "INSTANCE", label = "I",  tip = "Instance",            text = "/i " },
  { id = "GUILD",    label = "G",  tip = "Guild",               text = "/g " },
  { id = "OFFICER",  label = "O",  tip = "Officer",             text = "/o " },
  { id = "CH1",      label = "1",  tip = "Channel 1",           text = "/1 " },
  { id = "CH2",      label = "2",  tip = "Channel 2",           text = "/2 " },
  { id = "WHISPER",  label = "W",  tip = "Whisper",             text = "/w " },
  { id = "REPLY",    label = "R>", tip = "Reply (last whisper)", text = "/r " },
}

local function IsPermanentActive(frame)
  return frame
    and not frame.isTemporary
    and (not NS.IsActiveChatFrame or NS.IsActiveChatFrame(frame))
end

local function GetTargetChatFrame(core)
  local configuredIndex = tonumber(core:Get("chatBarAttachTo")) or 1
  local configured = _G["ChatFrame" .. configuredIndex]
  if configured and NS.ResolveActiveDockChatFrame then
    configured = NS.ResolveActiveDockChatFrame(configured)
  end
  if IsPermanentActive(configured) then return configured end

  local candidates = {
    NS.GetSelectedDockChatFrame and NS.GetSelectedDockChatFrame() or nil,
    _G.ChatFrame1,
  }
  for _, frame in ipairs(NS.GetActiveChatFrames and NS.GetActiveChatFrames() or {}) do
    candidates[#candidates + 1] = frame
  end

  for _, frame in ipairs(candidates) do
    if IsPermanentActive(frame) then
      local index = NS.GetChatFrameIndex and NS.GetChatFrameIndex(frame)
      if index and index ~= configuredIndex and type(core.Set) == "function" then
        core:Set("chatBarAttachTo", index)
      end
      return frame
    end
  end
  return nil
end

local function NotifyChatRestriction(core)
  local now = GetTime()
  if (now - lastRestrictedNotice) < 2 then return end

  lastRestrictedNotice = now
  if core and type(core.Print) == "function" then
    core:Print("Chat input is unavailable while chat restrictions are active.")
  end
end

local function OpenChat(text, chatFrame)
  local util = _G.ChatFrameUtil
  local open = util and util.OpenChat or _G.ChatFrame_OpenChat
  if type(open) ~= "function" then return false end
  local ok = pcall(open, text, chatFrame)
  return ok
end

local function DetachBar(core)
  if not bar then return end
  local attached = bar.__rothAttachedChatFrame
  if attached and type(core.UnregisterHoverFrame) == "function" then
    core:UnregisterHoverFrame(attached, bar)
  end
  bar.__rothAttachedChatFrame = nil
end

local function SkinButton(button, core)
  local fontString = button.__fs
  if not fontString then return end
  fontString:SetTextColor(0.95, 0.90, 0.80)
  fontString:SetShadowColor(0, 0, 0, 0.7)
  fontString:SetShadowOffset(1, -1)

  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local font = core:Get("styleFont") or (LSM and LSM:Fetch("font", "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
  local size = math.max(10, (core:Get("styleFontSize") or 12) - 1)
  local outline = core:Get("styleFontOutline") or ""
  fontString:SetFont(font, size, outline)

  if not button.__skinned then
    NS.ApplyGlassBackdrop(button, 0.4, 0, 0)
    NS.CreateHighlight(button, "HIGHLIGHT", nil, nil, nil, 0)
    button.__skinned = true
  end
end

local function CreateBar(core, chatFrame)
  if bar then return bar end

  bar = CreateFrame("Frame", nil, UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:SetFrameLevel((chatFrame and chatFrame:GetFrameLevel() or 1) + 10)
  bar.buttons = {}

  for index, info in ipairs(BUTTONS) do
    local button = CreateFrame("Button", nil, bar)
    button.__info = info
    button.__fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.__fs:SetPoint("CENTER")
    button.__fs:SetText(info.label)

    button:SetScript("OnClick", function()
      if NS.IsChatMessagingRestricted and NS.IsChatMessagingRestricted() then
        NotifyChatRestriction(core)
        return
      end

      local target = GetTargetChatFrame(core)
      if target then OpenChat(info.text, target) end
    end)

    button:SetScript("OnEnter", function(self)
      if GameTooltip and not InCombatLockdown() then
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(info.tip)
        GameTooltip:Show()
      end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.7)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.7)
      end
    end)
    button:SetScript("OnLeave", function(self)
      if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.4)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.4)
      end
    end)

    SkinButton(button, core)
    bar.buttons[index] = button
  end

  return bar
end

local function LayoutBar(core)
  if not bar then return end
  local size = core:Get("chatBarButtonSize") or 18
  local spacing = core:Get("chatBarSpacing") or 4
  local anchor = core:Get("chatBarAnchor") or "LEFT"
  local chatFrame = GetTargetChatFrame(core)
  if not chatFrame then
    DetachBar(core)
    bar:Hide()
    return
  end

  local previous = bar.__rothAttachedChatFrame
  if previous and previous ~= chatFrame and type(core.UnregisterHoverFrame) == "function" then
    core:UnregisterHoverFrame(previous, bar)
  end

  bar:SetFrameLevel(chatFrame:GetFrameLevel() + 10)
  local padding = 6
  bar:ClearAllPoints()

  if anchor == "RIGHT" then
    bar:SetPoint("TOPRIGHT", chatFrame, "TOPLEFT", -(4 + padding), 0)
  elseif anchor == "TOP" then
    bar:SetPoint("BOTTOMLEFT", chatFrame, "TOPLEFT", 0, 4)
  elseif anchor == "BOTTOM" then
    bar:SetPoint("TOPLEFT", chatFrame, "BOTTOMLEFT", 0, -4)
  else
    bar:SetPoint("TOPLEFT", chatFrame, "TOPRIGHT", (4 + padding), 0)
  end

  local vertical = anchor == "LEFT" or anchor == "RIGHT"
  local totalWidth, totalHeight = 0, 0

  for index, button in ipairs(bar.buttons or {}) do
    button:SetSize(size, size)
    button:ClearAllPoints()

    if index == 1 then
      button:SetPoint("TOPLEFT", bar, "TOPLEFT", padding, -padding)
    else
      local previousButton = bar.buttons[index - 1]
      if vertical then
        button:SetPoint("TOPLEFT", previousButton, "BOTTOMLEFT", 0, -spacing)
      else
        button:SetPoint("TOPLEFT", previousButton, "TOPRIGHT", spacing, 0)
      end
    end

    if vertical then
      totalWidth = math.max(totalWidth, size)
      totalHeight = totalHeight + size + (index > 1 and spacing or 0)
    else
      totalHeight = math.max(totalHeight, size)
      totalWidth = totalWidth + size + (index > 1 and spacing or 0)
    end
  end

  bar:SetSize(totalWidth + padding * 2, totalHeight + padding * 2)
  if type(core.RegisterHoverFrame) == "function" then
    core:RegisterHoverFrame(chatFrame, bar)
    bar.__rothAttachedChatFrame = chatFrame
  else
    bar.__rothAttachedChatFrame = nil
  end
end

function M:Init(core)
  self.core = core
  return true
end

ApplyBar = function(core)
  if not core:Get("chatBarEnabled") then
    DetachBar(core)
    if bar then bar:Hide() end
    return
  end

  local chatFrame = GetTargetChatFrame(core)
  if not chatFrame then
    DetachBar(core)
    if bar then bar:Hide() end
    return
  end

  CreateBar(core, chatFrame)
  LayoutBar(core)
  bar:Show()
end

local function RegisterLifecycleListeners(core)
  if listenersRegistered then return end
  listenersRegistered = true

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if core2:IsModuleActive("ChatBar") then ApplyBar(core2) end
  end, M)

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if not core2:IsModuleActive("ChatBar") then return end
    if chatFrame == GetTargetChatFrame(core2) then ApplyBar(core2) end
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if bar and chatFrame == bar.__rothAttachedChatFrame then ApplyBar(core2) end
  end, M)
end

function M:OnEnable(core)
  listenersRegistered = false
  core:EnsureChatLifecycleHooks()
  RegisterLifecycleListeners(core)

  if InCombatLockdown() then
    core:Defer(function()
      if core:IsModuleActive("ChatBar") then ApplyBar(core) end
    end)
  else
    ApplyBar(core)
  end
end

function M:OnLogin(core)
  ApplyBar(core)
end

function M:OnDisable(core)
  DetachBar(core)
  listenersRegistered = false
  if bar then bar:Hide() end
end

function M:Refresh(core)
  ApplyBar(core)
end

RothChat:RegisterModule(M)
