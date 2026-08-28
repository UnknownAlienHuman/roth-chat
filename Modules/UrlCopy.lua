-- RothChat - UrlCopy module
-- Goal: Make URLs in chat clickable. Clicking opens a popup to copy the link.
-- Inspired by Prat's URL copy functionality.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "UrlCopy",
  defaultEnabled = true,
  description = "Makes URLs clickable. Click to open a copy popup.",
}

local COLOR_URL = "0099FF" -- Light blue
local LINK_TYPE = "rothchaturl"

-- URL patterns: %w matches only ASCII (safe for UTF-8 — multibyte chars >127 won't match).
-- Raw UTF-8 in URL paths (e.g. /путь) won't be captured; percent-encoded paths work fine.
local HTTP_PATTERN = "https?://[%w%-%._~:/%?#%[%]@!$&'()%*+,;=%%]+"
local WWW_PATTERN = "www%.[%w%-%._~:/%?#%[%]@!$&'()%*+,;=%%]+"
local DISCORD_PATTERN = "%f[%w]discord%.gg/[%w%-]+"
local DISCORD_INVITE_PATTERN = "%f[%w]discord%.com/invite/[%w%-]+"
local BNET_PATTERN = "%f[%w]battle%.net[%w%-%._~:/%?#%[%]@!$&'()%*+,;=%%]*"
local IP_PATTERN = "%f[%d](%d+%.%d+%.%d+%.%d+)(:%d+)?%f[%D]"

local THROTTLE_WINDOW = 1.0
local THROTTLE_MAX = 40
local throttle = { t = 0, n = 0 }
local FILTER_EVENTS = {
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER",
  "CHAT_MSG_BN_WHISPER", "CHAT_MSG_CHANNEL",
}

local function UrlCopyEnabled()
  return RothChat and RothChat.IsModuleEnabled and RothChat:IsModuleEnabled("UrlCopy")
end

local function IsSafeChatString(v)
  return NS.CanAccessValue(v) and type(v) == "string"
end

local function AllowLinkify()
  local now = GetTime()
  if now - throttle.t > THROTTLE_WINDOW then
    throttle.t = now
    throttle.n = 0
  end
  throttle.n = throttle.n + 1
  return throttle.n <= THROTTLE_MAX
end

local function HasUrlHints(msg)
  if not IsSafeChatString(msg) or msg == "" then return false end
  if msg:find("://", 1, true) then return true end
  if msg:find("www.", 1, true) then return true end
  if msg:find("discord", 1, true) then return true end
  if msg:find("battle%.net") then return true end
  if msg:find("%d+%.%d+%.%d+%.%d+") then return true end
  return false
end

local function StripTrailingPunct(url)
  local trail = ""
  while url ~= "" do
    local ch = url:sub(-1)
    if ch:match("[%.%,%:%;%!%?%)%]%}]") then
      trail = ch .. trail
      url = url:sub(1, -2)
    else
      break
    end
  end
  return url, trail
end

local function MakeLink(url)
  if _G.LinkUtil and type(_G.LinkUtil.FormatLink) == "function" then
    return "|cff" .. COLOR_URL .. _G.LinkUtil.FormatLink(LINK_TYPE, "[" .. url .. "]", url) .. "|r"
  end
  return "|cff" .. COLOR_URL .. "|H" .. LINK_TYPE .. ":" .. url .. "|h[" .. url .. "]|h|r"
end

local function IsValidIPv4(ip)
  local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return false end
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not a or not b or not c or not d then return false end
  return a <= 255 and b <= 255 and c <= 255 and d <= 255
end

local function FindNextIP(text, startIndex)
  local s, e, ip, port = text:find(IP_PATTERN, startIndex)
  while s do
    if IsValidIPv4(ip) then
      return s, e, ip, port
    end
    s, e, ip, port = text:find(IP_PATTERN, e + 1)
  end
  return nil
end

local function FindNextUrl(text, startIndex)
  local bestS, bestE, bestUrl

  local function Consider(s, e, url)
    if not s then return end
    if (not bestS) or (s < bestS) or (s == bestS and e > bestE) then
      bestS, bestE, bestUrl = s, e, url
    end
  end

  local s, e = text:find(HTTP_PATTERN, startIndex)
  if s then Consider(s, e, text:sub(s, e)) end

  s, e = text:find(WWW_PATTERN, startIndex)
  if s then Consider(s, e, text:sub(s, e)) end

  s, e = text:find(DISCORD_PATTERN, startIndex)
  if s then Consider(s, e, text:sub(s, e)) end

  s, e = text:find(DISCORD_INVITE_PATTERN, startIndex)
  if s then Consider(s, e, text:sub(s, e)) end

  s, e = text:find(BNET_PATTERN, startIndex)
  if s then Consider(s, e, text:sub(s, e)) end

  local ipS, ipE, ip, port = FindNextIP(text, startIndex)
  if ipS then Consider(ipS, ipE, ip .. (port or "")) end

  return bestS, bestE, bestUrl
end

local function LinkifySegment(text)
  if not IsSafeChatString(text) or text == "" then return text end

  local out = {}
  local i = 1
  local len = #text

  while i <= len do
    local s, e, url = FindNextUrl(text, i)
    if not s then
      out[#out + 1] = text:sub(i)
      break
    end

    if s > i then
      out[#out + 1] = text:sub(i, s - 1)
    end

    local clean, trail = StripTrailingPunct(url)
    if clean == "" then
      out[#out + 1] = text:sub(s, e)
    else
      out[#out + 1] = MakeLink(clean)
      if trail ~= "" then
        out[#out + 1] = trail
      end
    end

    i = e + 1
  end

  return table.concat(out)
end

local function LinkifyMessage(msg)
  if not IsSafeChatString(msg) or msg == "" then return msg end
  if not msg:find("|H", 1, true) then
    return LinkifySegment(msg)
  end

  local out = {}
  local i = 1
  local len = #msg

  while i <= len do
    local s = msg:find("|H", i, true)
    if not s then
      out[#out + 1] = LinkifySegment(msg:sub(i))
      break
    end

    if s > i then
      out[#out + 1] = LinkifySegment(msg:sub(i, s - 1))
    end

    local h1s, h1e = msg:find("|h", s + 2, true)
    if not h1s then
      out[#out + 1] = LinkifySegment(msg:sub(s))
      break
    end
    local h2s, h2e = msg:find("|h", h1e + 1, true)
    if not h2s then
      out[#out + 1] = LinkifySegment(msg:sub(s))
      break
    end

    out[#out + 1] = msg:sub(s, h2e)
    i = h2e + 1
  end

  return table.concat(out)
end

local function ShowPopup(url)
  if not UrlCopyEnabled() then return end

  local popupName = "RothChat_UrlCopyPopup"
  local f = _G[popupName]
  if not f then
    f = CreateFrame("Frame", popupName, UIParent)
    f:SetSize(400, 60)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)

    NS.ApplyGlassLook(f, 0.95)

    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetPoint("LEFT", 10, 0)
    eb:SetPoint("RIGHT", -10, 0)
    eb:SetHeight(24)
    eb:SetAutoFocus(true)
    f.editBox = eb

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 2)
    lbl:SetText("Press Ctrl+C to copy:")

    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEnterPressed", function() f:Hide() end)

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
  end

  f.editBox:SetText(url)
  f.editBox:HighlightText()
  f:Show()
end

local function RegisterLinkHandler()
  if M._linkHandlerRegistered then return true end

  if _G.LinkUtil and type(_G.LinkUtil.IsLinkHandlerRegistered) == "function" and _G.LinkUtil.IsLinkHandlerRegistered(LINK_TYPE) then
    M._linkHandlerRegistered = true
    return true
  end

  if _G.LinkUtil and type(_G.LinkUtil.RegisterLinkHandler) == "function" then
    _G.LinkUtil.RegisterLinkHandler(LINK_TYPE, function(link, text, linkData, contextData)
      local url = linkData and linkData.options or ""
      if type(url) == "string" and url ~= "" then
        ShowPopup(url)
      end
      return _G.LinkProcessorResponse and _G.LinkProcessorResponse.Handled or nil
    end)
    M._linkHandlerRegistered = true
    return true
  end

  return false
end

local function ChatFilter(self, event, msg, ...)
  if not IsSafeChatString(msg) then return false end
  if msg:find("|H" .. LINK_TYPE .. ":", 1, true) then return false end
  if not HasUrlHints(msg) then return false end
  if not AllowLinkify() then return false end

  local newMsg = LinkifyMessage(msg)
  if newMsg ~= msg then
    return false, newMsg
  end
  return false
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  core:RegisterMessageFilters(self, FILTER_EVENTS, ChatFilter, 60)

  if not self.hooked then
    self.hooked = RegisterLinkHandler()
  end
end

function M:OnDisable(core)
end

RothChat:RegisterModule(M)
