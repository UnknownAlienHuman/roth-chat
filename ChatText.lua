-- RothChat - shared chat-text boundaries
--
-- Keeps persistence/copy formatting separate from Blizzard's live secure chat
-- tuple. All functions operate only on values that already passed the current
-- accessibility gate; none is a declassification or a replacement renderer.

local ADDON_NAME, NS = ...
NS = NS or {}

local DEFAULT_TIMESTAMP_COLOR = "999999"
local DEFAULT_TIMESTAMP_FORMAT = "%H:%M"
local CENSORED_PLACEHOLDER = "[Censored message unavailable after reload]"
local LITERAL_PIPE_SENTINEL = "\001"

local function CanUse(value)
  return not NS.CanAccessValue or NS.CanAccessValue(value)
end

local function Trim(text)
  if type(_G.strtrim) == "function" then
    return _G.strtrim(text)
  end
  return text:match("^%s*(.-)%s*$") or ""
end

local function SafeStripHyperlinks(text)
  if type(text) ~= "string" then return "" end

  if _G.C_StringUtil and type(_G.C_StringUtil.StripHyperlinks) == "function" then
    local ok, stripped = pcall(_G.C_StringUtil.StripHyperlinks, text, false, true, true, false, false)
    if ok and type(stripped) == "string" then return stripped end
  end

  if type(_G.StripHyperlinks) == "function" then
    local ok, stripped = pcall(_G.StripHyperlinks, text)
    if ok and type(stripped) == "string" then return stripped end
  end

  return text
end

function NS.NormalizeHexColor(value, fallback)
  fallback = type(fallback) == "string" and fallback:upper() or DEFAULT_TIMESTAMP_COLOR
  if type(value) ~= "string" then return fallback end

  local hex = value:gsub("^#", ""):gsub("^|[cC]%x%x", ""):upper()
  if #hex >= 8 then
    hex = hex:sub(#hex - 5)
  else
    hex = hex:sub(1, 6)
  end

  if #hex == 6 and hex:match("^[0-9A-F]+$") then
    return hex
  end
  return fallback
end

function NS.FormatChatTimestamp(timestamp, colored, colorHex, formatCode)
  if not CanUse(timestamp) or type(timestamp) ~= "number" then return "" end

  formatCode = type(formatCode) == "string" and formatCode or DEFAULT_TIMESTAMP_FORMAT
  local stamp = "[--:--]"
  local dateFn = _G.date
  if type(dateFn) == "function" then
    local ok, formatted = pcall(dateFn, "[" .. formatCode .. "]", timestamp)
    if ok and type(formatted) == "string" then stamp = formatted end
  end

  if colored then
    local color = NS.NormalizeHexColor(colorHex, DEFAULT_TIMESTAMP_COLOR)
    return "|cff" .. color .. stamp .. "|r "
  end
  return stamp .. " "
end

function NS.GetNativeChatTimestampFormat()
  local util = _G.ChatFrameUtil
  if util and type(util.GetTimestampFormat) == "function" then
    local ok, format = pcall(util.GetTimestampFormat)
    if ok and type(format) == "string" and format ~= "" and format ~= "none" then
      return format
    end
  end

  local settings = _G.Settings
  if settings and type(settings.GetValue) == "function" then
    local ok, format = pcall(settings.GetValue, "showTimestamps")
    if ok and type(format) == "string" and format ~= "" and format ~= "none" then
      return format
    end
  end

  return nil
end

function NS.HasNativeChatTimestamps()
  return NS.GetNativeChatTimestampFormat() ~= nil
end

function NS.FormatNativeChatTimestamp(timestamp, format)
  if not CanUse(timestamp) or type(timestamp) ~= "number" then return "" end
  format = type(format) == "string" and format or NS.GetNativeChatTimestampFormat()
  if type(format) ~= "string" or format == "" or format == "none" then return "" end

  local timeUtil = _G.TimeUtil
  if timeUtil and type(timeUtil.BetterDate) == "function" then
    local ok, value = pcall(timeUtil.BetterDate, format, timestamp)
    if ok and type(value) == "string" then return value end
  end

  if type(_G.date) == "function" then
    local ok, value = pcall(_G.date, format, timestamp)
    if ok and type(value) == "string" then return value end
  end

  return ""
end

function NS.StripRothTimestampPrefix(text)
  if not CanUse(text) then return "" end
  if type(text) ~= "string" then text = NS.SafeToString and NS.SafeToString(text) or "" end
  if text == "" then return "" end

  local stripped, count = text:gsub("^|[cC][fF][fF]%x%x%x%x%x%x%[%d%d:%d%d:%d%d%]|[rR]%s*", "", 1)
  if count == 0 then
    stripped = text:gsub("^|[cC][fF][fF]%x%x%x%x%x%x%[%d%d:%d%d%]|[rR]%s*", "", 1)
  end
  return stripped
end

function NS.HasRothTimestampPrefix(text)
  if not CanUse(text) or type(text) ~= "string" then return false end
  return NS.StripRothTimestampPrefix(text) ~= text
end

local function StripExactPrefix(text, prefix)
  if type(prefix) ~= "string" or prefix == "" then return text, false end
  if text:sub(1, #prefix) == prefix then
    return text:sub(#prefix + 1), true
  end
  return text, false
end

local function StripCommonPlainTimestampPrefix(text)
  local patterns = {
    "^%[%d%d?:%d%d:%d%d%s+[AaPp][Mm]%]%s*",
    "^%[%d%d?:%d%d%s+[AaPp][Mm]%]%s*",
    "^%[%d%d:%d%d:%d%d%]%s*",
    "^%[%d%d:%d%d%]%s*",
  }

  for i = 1, #patterns do
    local stripped, count = text:gsub(patterns[i], "", 1)
    if count > 0 then return stripped end
  end
  return text
end

-- Remove exactly one display-owned prefix. The exact native prefix is tried at
-- timestamp +/- one second because the AddMessage observer runs after Blizzard
-- captured msgTime; a second boundary between both calls must not retain it.
function NS.StripDisplayTimestampPrefix(text, timestamp, allowGeneric)
  if not CanUse(text) then return "" end
  if type(text) ~= "string" then text = NS.SafeToString and NS.SafeToString(text) or "" end
  if text == "" then return "" end

  local stripped = NS.StripRothTimestampPrefix(text)
  if stripped ~= text then return stripped end

  local format = NS.GetNativeChatTimestampFormat()
  if format and type(timestamp) == "number" then
    for delta = -1, 1 do
      local prefix = NS.FormatNativeChatTimestamp(timestamp + delta, format)
      local candidate, matched = StripExactPrefix(text, prefix)
      if matched then return candidate end
    end
  end

  if allowGeneric then
    return StripCommonPlainTimestampPrefix(text)
  end
  return text
end

local function FlattenSessionLinks(text)
  local flattenTypes = {
    "BNplayer",
    "BNplayerCommunity",
    "playerCommunity",
    "discorduser",
    "discorduserCommunity",
    "playerGM",
    "channel",
  }

  for i = 1, #flattenTypes do
    local linkType = flattenTypes[i]
    text = text:gsub("|H" .. linkType .. ":[^|]*|h(.-)|h", "%1")
  end

  -- Player links with lineID/chatType/chatTarget contain session routing data.
  -- Preserve the stable character target and visible label only.
  text = text:gsub("|Hplayer:([^:|]+):[^|]*|h(.-)|h", "|Hplayer:%1|h%2|h")
  return text
end

function NS.SanitizeDurableChatText(text)
  if not CanUse(text) then return "" end
  if type(text) ~= "string" then text = NS.SafeToString and NS.SafeToString(text) or "" end
  if text == "" then return "" end

  -- Account-name tokens and censored-message callbacks are session/context
  -- handles, not durable content. Ordinary item/spell/achievement links remain.
  text = text:gsub("|[Kk].-|[Kk]", "???")
  text = text:gsub("|[Ww].-|[Ww]", "???")
  text = text:gsub("|Hreportcensoredmessage:[^|]*|h.-|h", CENSORED_PLACEHOLDER)
  text = text:gsub("|Hcensoredmessage[^:|]*:[^|]*|h.-|h", CENSORED_PLACEHOLDER)
  text = FlattenSessionLinks(text)

  return text
end

local function StripPlainTimestampPrefixes(text)
  text = StripCommonPlainTimestampPrefix(text)
  text = text:gsub("\n%[%d%d?:%d%d:%d%d%s+[AaPp][Mm]%]%s*", "\n")
  text = text:gsub("\n%[%d%d?:%d%d%s+[AaPp][Mm]%]%s*", "\n")
  text = text:gsub("\n%[%d%d:%d%d:%d%d%]%s*", "\n")
  text = text:gsub("\n%[%d%d:%d%d%]%s*", "\n")
  return text
end

function NS.NormalizeCopyText(text, includeTimestamps)
  if not CanUse(text) then return "" end
  text = NS.SanitizeDurableChatText(text)
  if text == "" then return "" end

  -- Preserve literal escaped pipes while removing WoW display markup.
  text = text:gsub("||", LITERAL_PIPE_SENTINEL)
  text = text:gsub("|[cC]%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|[rR]", "")
  text = text:gsub("|[tT].-|[tT]", "")
  text = text:gsub("|[aA].-|[aA]", "")
  text = text:gsub("|[kK].-|[kK]", "???")
  text = text:gsub("|[wW].-|[wW]", "???")
  text = text:gsub("|[hH].-|[hH](.-)|[hH]", "%1")
  text = text:gsub("|[nN]", "\n")
  text = SafeStripHyperlinks(text)
  text = text:gsub(LITERAL_PIPE_SENTINEL, "|")

  if includeTimestamps == false then
    text = StripPlainTimestampPrefixes(text)
  end

  return Trim(text)
end
