-- RothChat - Timestamps module
-- Adds a Roth timestamp only where Blizzard's current formatter will not add
-- the native showTimestamps prefix after message-event filters run.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Timestamps",
  defaultEnabled = true,
  description = "Adds time to chat messages without duplicating Blizzard timestamps.",
}

local EVENTS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
  "CHAT_MSG_SYSTEM", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
}

-- Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua adds its native
-- timestamp after filters and final sender/channel formatting for the normal
-- chat path. The three direct AddMessage branches below do not receive it.
local BLIZZARD_NATIVE_TIMESTAMP_EVENTS = {
  CHAT_MSG_SAY = true,
  CHAT_MSG_YELL = true,
  CHAT_MSG_EMOTE = true,
  CHAT_MSG_TEXT_EMOTE = true,
  CHAT_MSG_WHISPER = true,
  CHAT_MSG_WHISPER_INFORM = true,
  CHAT_MSG_BN_WHISPER = true,
  CHAT_MSG_BN_WHISPER_INFORM = true,
  CHAT_MSG_GUILD = true,
  CHAT_MSG_OFFICER = true,
  CHAT_MSG_PARTY = true,
  CHAT_MSG_PARTY_LEADER = true,
  CHAT_MSG_RAID = true,
  CHAT_MSG_RAID_LEADER = true,
  CHAT_MSG_RAID_WARNING = true,
  CHAT_MSG_INSTANCE_CHAT = true,
  CHAT_MSG_INSTANCE_CHAT_LEADER = true,
  CHAT_MSG_CHANNEL = true,
  CHAT_MSG_COMMUNITIES_CHANNEL = true,
}

local cachedSecond = -1
local cachedStamp = ""
local cachedColor = ""
local cachedPrefix = ""

local function GetTimestampPrefix()
  local now = time()
  if now ~= cachedSecond then
    cachedSecond = now
    cachedStamp = NS.FormatChatTimestamp(now, false)
    if cachedStamp == "" then cachedStamp = "[--:--] " end
    cachedColor = ""
  end

  local color = NS.NormalizeHexColor(RothChat and RothChat:Get("timestampColor"), "999999")
  if color ~= cachedColor then
    cachedColor = color
    cachedPrefix = "|cff" .. color .. cachedStamp:gsub("%s+$", "") .. "|r "
  end
  return cachedPrefix
end

local function AddTimestamp(self, event, msg, ...)
  if NS.CanAccessValue and not NS.CanAccessValue(msg) then return false end
  if type(msg) ~= "string" then return false end

  -- Native timestamps are appended by Blizzard after this filter. Returning a
  -- replacement here would produce two prefixes in the final displayed line.
  if BLIZZARD_NATIVE_TIMESTAMP_EVENTS[event]
    and NS.HasNativeChatTimestamps
    and NS.HasNativeChatTimestamps()
  then
    return false
  end

  if NS.HasRothTimestampPrefix and NS.HasRothTimestampPrefix(msg) then
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
