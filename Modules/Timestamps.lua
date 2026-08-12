-- RothChat - Timestamps module
-- Goal: Add stylish, unobtrusive timestamps to chat messages.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Timestamps",
  defaultEnabled = true,
  description = "Adds time to chat messages.",
}

local TIMESTAMP_FORMAT = "[%H:%M]"
local DEFAULT_COLOR = "999999" -- Grey
local EVENTS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_SYSTEM", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
}

local cachedSecond = -1
local cachedStamp = ""
local cachedColor = ""
local cachedPrefix = ""

local function NormalizeHexColor(hex)
  if type(hex) ~= "string" then
    return DEFAULT_COLOR
  end
  hex = hex:gsub("^#", ""):gsub("^|c%x%x", ""):sub(1, 6):upper()
  if hex:match("^[0-9A-F]+$") and #hex == 6 then
    return hex
  end
  return DEFAULT_COLOR
end

local function GetTimestampPrefix()
  local now = time()
  if now ~= cachedSecond then
    cachedSecond = now
    local ok, stamp = pcall(date, TIMESTAMP_FORMAT, now)
    if ok and type(stamp) == "string" then
      cachedStamp = stamp
    else
      cachedStamp = "[--:--]"
    end
    -- Force prefix refresh after second boundary.
    cachedColor = ""
  end

  local color = NormalizeHexColor(RothChat and RothChat:Get("timestampColor"))
  if color ~= cachedColor then
    cachedColor = color
    cachedPrefix = "|cff" .. color .. cachedStamp .. "|r "
  end
  return cachedPrefix
end

local function AddTimestamp(self, event, msg, ...)
  if NS.IsSecretValue(msg) then return false end
  if type(msg) ~= "string" then return false end

  -- Skip if a timestamp prefix was already injected.
  if msg:find("^|cff%x%x%x%x%x%x%[%d%d:%d%d%]|r%s") then
    return false
  end

  local prefix = GetTimestampPrefix()
  if prefix == "" then return false end
  return false, prefix .. msg
end

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  core:RegisterMessageFilters(self, EVENTS, AddTimestamp, 80)
end

function M:OnDisable(core)
  cachedSecond = -1
  cachedStamp = ""
  cachedColor = ""
  cachedPrefix = ""
end

RothChat:RegisterModule(M)
