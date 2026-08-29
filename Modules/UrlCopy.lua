-- RothChat - UrlCopy module
-- Makes URLs in accessible chat text clickable. Clicking opens a copy popup.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "UrlCopy",
  defaultEnabled = true,
  description = "Makes URLs clickable. Click to open a copy popup.",
}

local COLOR_URL = "0099FF"
local LINK_TYPE = "rothchaturl"

-- %w is deliberately ASCII-only here. Raw non-ASCII URL paths are left as
-- ordinary text; percent-encoded paths remain supported.
local HTTP_PATTERN = "https?://[%w%-%._~:/%?#%[%]@!$&'()%*+,;=%%]+"
local WWW_PATTERN = "www%.[%w%-%._~:/%?#%[%]@!$&'()%*+,;=%%]+"
local DISCORD_PATTERN = "%f[%w]discord%.gg/[%w%-]+"
local DISCORD_INVITE_PATTERN = "%f[%w]discord%.com/invite/[%w%-]+"
local BNET_PATTERN = "%f[%w]battle%.net[%w%-%._~:/%?#%[%]@!$&'()%*+,;=%%]*"
local IP_PATTERN = "%f[%d](%d+%.%d+%.%d+%.%d+)(:%d+)?%f[%D]"

local THROTTLE_WINDOW = 1.0
local THROTTLE_MAX = 40
local throttle = { t = 0, n = 0 }

-- These are the user/system text families Roth Chat intentionally transforms.
-- Monster/combat/loot payloads are left to Blizzard because they are either
-- not user-authored or have specialized formatting/security paths.
local FILTER_EVENTS = {
  "CHAT_MSG_SAY",
  "CHAT_MSG_YELL",
  "CHAT_MSG_EMOTE",
  "CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_WHISPER",
  "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER",
  "CHAT_MSG_BN_WHISPER_INFORM",
  "CHAT_MSG_GUILD",
  "CHAT_MSG_OFFICER",
  "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_COMMUNITIES_CHANNEL",
  "CHAT_MSG_SYSTEM",
  "CHAT_MSG_ACHIEVEMENT",
  "CHAT_MSG_GUILD_ACHIEVEMENT",
}

local function UrlCopyEnabled()
  return RothChat and RothChat.IsModuleActive and RothChat:IsModuleActive("UrlCopy")
end

local function IsSafeChatString(value)
  return type(value) == "string" and (not NS.CanAccessValue or NS.CanAccessValue(value))
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

local function HasUrlHints(message)
  if not IsSafeChatString(message) or message == "" then return false end
  if message:find("://", 1, true) then return true end
  if message:find("www.", 1, true) then return true end
  if message:find("discord", 1, true) then return true end
  if message:find("battle.net", 1, true) then return true end
  if message:find("%d+%.%d+%.%d+%.%d+") then return true end
  return false
end

local function CountPlain(text, needle)
  local count = 0
  local start = 1
  while true do
    local position = text:find(needle, start, true)
    if not position then return count end
    count = count + 1
    start = position + 1
  end
end

local function IsUnmatchedCloser(url, character)
  if character == ")" then
    return CountPlain(url, ")") > CountPlain(url, "(")
  elseif character == "]" then
    return CountPlain(url, "]") > CountPlain(url, "[")
  elseif character == "}" then
    return CountPlain(url, "}") > CountPlain(url, "{")
  end
  return false
end

local function StripTrailingPunctuation(url)
  local trailing = ""
  while url ~= "" do
    local character = url:sub(-1)
    local strip = character:match("[%.%,%:%;%!%?]") ~= nil or IsUnmatchedCloser(url, character)
    if not strip then break end
    trailing = character .. trailing
    url = url:sub(1, -2)
  end
  return url, trailing
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
  local startPos, endPos, ip, port = text:find(IP_PATTERN, startIndex)
  while startPos do
    if IsValidIPv4(ip) then return startPos, endPos, ip, port end
    startPos, endPos, ip, port = text:find(IP_PATTERN, endPos + 1)
  end
  return nil
end

local function FindNextUrl(text, startIndex)
  local bestStart, bestEnd, bestUrl

  local function Consider(startPos, endPos, url)
    if not startPos then return end
    if not bestStart or startPos < bestStart or (startPos == bestStart and endPos > bestEnd) then
      bestStart, bestEnd, bestUrl = startPos, endPos, url
    end
  end

  local startPos, endPos = text:find(HTTP_PATTERN, startIndex)
  if startPos then Consider(startPos, endPos, text:sub(startPos, endPos)) end

  startPos, endPos = text:find(WWW_PATTERN, startIndex)
  if startPos then Consider(startPos, endPos, text:sub(startPos, endPos)) end

  startPos, endPos = text:find(DISCORD_PATTERN, startIndex)
  if startPos then Consider(startPos, endPos, text:sub(startPos, endPos)) end

  startPos, endPos = text:find(DISCORD_INVITE_PATTERN, startIndex)
  if startPos then Consider(startPos, endPos, text:sub(startPos, endPos)) end

  startPos, endPos = text:find(BNET_PATTERN, startIndex)
  if startPos then Consider(startPos, endPos, text:sub(startPos, endPos)) end

  local ipStart, ipEnd, ip, port = FindNextIP(text, startIndex)
  if ipStart then Consider(ipStart, ipEnd, ip .. (port or "")) end

  return bestStart, bestEnd, bestUrl
end

local function LinkifySegment(text)
  if not IsSafeChatString(text) or text == "" then return text end

  local out = {}
  local cursor = 1
  local length = #text

  while cursor <= length do
    local startPos, endPos, url = FindNextUrl(text, cursor)
    if not startPos then
      out[#out + 1] = text:sub(cursor)
      break
    end

    if startPos > cursor then out[#out + 1] = text:sub(cursor, startPos - 1) end

    local clean, trailing = StripTrailingPunctuation(url)
    if clean == "" then
      out[#out + 1] = text:sub(startPos, endPos)
    else
      out[#out + 1] = MakeLink(clean)
      if trailing ~= "" then out[#out + 1] = trailing end
    end

    cursor = endPos + 1
  end

  return table.concat(out)
end

local function LinkifyMessage(message)
  if not IsSafeChatString(message) or message == "" then return message end
  if not message:find("|H", 1, true) then return LinkifySegment(message) end

  local out = {}
  local cursor = 1
  local length = #message

  while cursor <= length do
    local linkStart = message:find("|H", cursor, true)
    if not linkStart then
      out[#out + 1] = LinkifySegment(message:sub(cursor))
      break
    end

    if linkStart > cursor then out[#out + 1] = LinkifySegment(message:sub(cursor, linkStart - 1)) end

    local firstLabelStart, firstLabelEnd = message:find("|h", linkStart + 2, true)
    if not firstLabelStart then
      out[#out + 1] = LinkifySegment(message:sub(linkStart))
      break
    end
    local secondLabelStart, secondLabelEnd = message:find("|h", firstLabelEnd + 1, true)
    if not secondLabelStart then
      out[#out + 1] = LinkifySegment(message:sub(linkStart))
      break
    end

    out[#out + 1] = message:sub(linkStart, secondLabelEnd)
    cursor = secondLabelEnd + 1
  end

  return table.concat(out)
end

local function ShowPopup(url)
  if not UrlCopyEnabled() or not IsSafeChatString(url) or url == "" then return end

  local popupName = "RothChat_UrlCopyPopup"
  local frame = _G[popupName]
  if not frame then
    frame = CreateFrame("Frame", popupName, UIParent)
    frame:SetSize(400, 60)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    NS.ApplyGlassLook(frame, 0.95)

    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetPoint("LEFT", 10, 0)
    editBox:SetPoint("RIGHT", -10, 0)
    editBox:SetHeight(24)
    editBox:SetAutoFocus(true)
    frame.editBox = editBox

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, 2)
    label:SetText("Press Ctrl+C to copy:")

    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnEnterPressed", function() frame:Hide() end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
  end

  frame.editBox:SetText(url)
  frame.editBox:HighlightText()
  frame:Show()
end

local function RegisterLinkHandler()
  if M._linkHandlerRegistered then return true end

  if _G.LinkUtil and type(_G.LinkUtil.IsLinkHandlerRegistered) == "function"
    and _G.LinkUtil.IsLinkHandlerRegistered(LINK_TYPE)
  then
    M._linkHandlerRegistered = true
    return true
  end

  if _G.LinkUtil and type(_G.LinkUtil.RegisterLinkHandler) == "function" then
    _G.LinkUtil.RegisterLinkHandler(LINK_TYPE, function(link, text, linkData, contextData)
      local url = linkData and linkData.options or ""
      if IsSafeChatString(url) and url ~= "" then ShowPopup(url) end
      return _G.LinkProcessorResponse and _G.LinkProcessorResponse.Handled or nil
    end)
    M._linkHandlerRegistered = true
    return true
  end

  return false
end

local function ChatFilter(self, event, message, ...)
  if not IsSafeChatString(message) then return false end
  if message:find("|H" .. LINK_TYPE .. ":", 1, true) then return false end
  if not HasUrlHints(message) or not AllowLinkify() then return false end

  local transformed = LinkifyMessage(message)
  if transformed ~= message then return false, transformed end
  return false
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  core:RegisterMessageFilters(self, FILTER_EVENTS, ChatFilter, 60)
  if not self.hooked then self.hooked = RegisterLinkHandler() end
end

function M:OnDisable(core)
end

RothChat:RegisterModule(M)
