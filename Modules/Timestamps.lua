-- RothChat - Timestamps module
-- Adds an unobtrusive timestamp to accessible chat text.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Timestamps",
  defaultEnabled = true,
  description = "Adds time to chat messages.",
}

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
local cachedColor = ""
local cachedPrefix = ""

local function GetTimestampPrefix()
  local now = time()
  local color = NS.NormalizeHexColor(RothChat and RothChat:Get("timestampColor"), "999999")
  if now ~= cachedSecond or color ~= cachedColor then
    cachedSecond = now
    cachedColor = color
    cachedPrefix = NS.FormatChatTimestamp(now, true, color)
  end
  return cachedPrefix
end

local function AddTimestamp(self, event, msg, ...)
  if NS.CanAccessValue and not NS.CanAccessValue(msg) then return false end
  if type(msg) ~= "string" then return false end
  if NS.HasRothTimestampPrefix(msg) then return false end

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
  cachedColor = ""
  cachedPrefix = ""
end

RothChat:RegisterModule(M)
