-- RothChat - ChatBar module
-- Diablo-ish minimal channel bar that appears on hover (via Controls module).

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

local function GetTargetChatFrame(core)
  local idx = core:Get("chatBarAttachTo") or 1
  local cf = _G["ChatFrame" .. tostring(idx)] or _G.ChatFrame1
  if NS.ResolveActiveDockChatFrame then
    cf = NS.ResolveActiveDockChatFrame(cf)
  end
  return cf
end

local function NotifyChatRestriction(core)
  local now = GetTime()
  if (now - lastRestrictedNotice) < 2 then
    return
  end

  lastRestrictedNotice = now
  if core and type(core.Print) == "function" then
    core:Print("Chat input is unavailable while chat restrictions are active.")
  end
end

local function DetachBar(core)
  if not bar then return end
  local attached = bar.__rothAttachedChatFrame
  if attached and type(core.UnregisterHoverFrame) == "function" then
    core:UnregisterHoverFrame(attached, bar)
  end
  bar.__rothAttachedChatFrame = nil
end

local function SkinButton(b, core)
  local fs = b.__fs
  if not fs then return end
  fs:SetTextColor(0.95, 0.90, 0.80)
  fs:SetShadowColor(0, 0, 0, 0.7)
  fs:SetShadowOffset(1, -1)

  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local font = core:Get("styleFont") or (LSM and LSM:Fetch("font", "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
  local size = math.max(10, (core:Get("styleFontSize") or 12) - 1)
  local outline = core:Get("styleFontOutline") or ""

  fs:SetFont(font, size, outline)

  if not b.__skinned then
    NS.ApplyGlassBackdrop(b, 0.4, 0, 0)
    NS.CreateHighlight(b, "HIGHLIGHT", nil, nil, nil, 0)
    b.__skinned = true
  end
end

local function CreateBar(core, cf)
  if bar then return bar end

  bar = CreateFrame("Frame", nil, UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:SetFrameLevel((cf and cf:GetFrameLevel() or 1) + 10)
  bar.buttons = {}

  for i, info in ipairs(BUTTONS) do
    local b = CreateFrame("Button", nil, bar)
    b.__info = info
    b.__fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.__fs:SetPoint("CENTER")
    b.__fs:SetText(info.label)

    b:SetScript("OnClick", function()
      if NS.IsChatMessagingRestricted and NS.IsChatMessagingRestricted() then
        NotifyChatRestriction(core)
        return
      end

      local targetCF = GetTargetChatFrame(core)
      if not targetCF then return end
      ChatFrame_OpenChat(info.text, targetCF)
    end)

    b:SetScript("OnEnter", function(self)
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
    b:SetScript("OnLeave", function(self)
      if GameTooltip and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
      end
      if self.__glassBackdrop then
        self.__glassBackdrop:SetBackdropColor(0, 0, 0, 0.4)
        self.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, 0.4)
      end
    end)

    SkinButton(b, core)
    bar.buttons[i] = b
  end

  return bar
end

local function LayoutBar(core)
  if not bar then return end
  local size = core:Get("chatBarButtonSize") or 18
  local spacing = core:Get("chatBarSpacing") or 4
  local anchor = core:Get("chatBarAnchor") or "LEFT"
  local cf = GetTargetChatFrame(core)
  if not cf then return end

  local previous = bar.__rothAttachedChatFrame
  if previous and previous ~= cf and type(core.UnregisterHoverFrame) == "function" then
    core:UnregisterHoverFrame(previous, bar)
  end

  bar:SetFrameLevel(cf:GetFrameLevel() + 10)
  local padding = 6
  bar:ClearAllPoints()

  if anchor == "RIGHT" then
    bar:SetPoint("TOPRIGHT", cf, "TOPLEFT", -(4 + padding), 0)
  elseif anchor == "TOP" then
    bar:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", 0, 4)
  elseif anchor == "BOTTOM" then
    bar:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", 0, -4)
  else
    bar:SetPoint("TOPLEFT", cf, "TOPRIGHT", (4 + padding), 0)
  end

  local vertical = (anchor == "LEFT" or anchor == "RIGHT")
  local totalW, totalH = 0, 0

  for i, b in ipairs(bar.buttons or {}) do
    b:SetSize(size, size)
    b:ClearAllPoints()

    if i == 1 then
      b:SetPoint("TOPLEFT", bar, "TOPLEFT", padding, -padding)
    else
      local prev = bar.buttons[i - 1]
      if vertical then
        b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -spacing)
      else
        b:SetPoint("TOPLEFT", prev, "TOPRIGHT", spacing, 0)
      end
    end

    if vertical then
      totalW = math.max(totalW, size)
      totalH = totalH + size + (i > 1 and spacing or 0)
    else
      totalH = math.max(totalH, size)
      totalW = totalW + size + (i > 1 and spacing or 0)
    end
  end

  bar:SetSize(totalW + padding * 2, totalH + padding * 2)

  if type(core.RegisterHoverFrame) == "function" then
    core:RegisterHoverFrame(cf, bar)
    bar.__rothAttachedChatFrame = cf
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

  local cf = GetTargetChatFrame(core)
  if not cf then return end
  CreateBar(core, cf)
  LayoutBar(core)
  bar:Show()
end

local function RegisterLifecycleListeners(core)
  if listenersRegistered then return end
  listenersRegistered = true

  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    if not core2:IsModuleEnabled("ChatBar") then return end
    ApplyBar(core2)
  end, M)

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if not core2:IsModuleEnabled("ChatBar") then return end
    local target = GetTargetChatFrame(core2)
    if chatFrame ~= target then return end
    ApplyBar(core2)
  end, M)
end

function M:OnEnable(core)
  listenersRegistered = false
  core:EnsureChatLifecycleHooks()
  RegisterLifecycleListeners(core)

  if InCombatLockdown() then
    core:Defer(function()
      if core:IsModuleActive("ChatBar") then
        ApplyBar(core)
      end
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
