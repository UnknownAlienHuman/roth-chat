-- RothChat - Colors module
-- Goal: Ensure class colors are enabled and enhance item links.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Colors",
  defaultEnabled = true,
  description = "Enforces class colors and enhances links.",
}

local BASE_CHANNELS = {
  "SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "PARTY_LEADER",
  "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
  "GUILD", "OFFICER", "ACHIEVEMENT", "GUILD_ACHIEVEMENT",
}
local CHANNELS = {}
local originalColorByClass = {}

local function BuildChatTypes()
  if #CHANNELS > 0 then return CHANNELS end

  for i = 1, #BASE_CHANNELS do
    CHANNELS[#CHANNELS + 1] = BASE_CHANNELS[i]
  end
  for i = 1, 20 do
    CHANNELS[#CHANNELS + 1] = "CHANNEL" .. i
  end

  return CHANNELS
end

function M:Init(core)
  self.core = core
  BuildChatTypes()
  return true
end

function M:OnEnable(core)
  if type(SetChatColorNameByClass) ~= "function" then return end

  -- Force enable class colors for standard types
  for _, chatType in ipairs(CHANNELS) do
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    if info then
      if originalColorByClass[chatType] == nil then
        originalColorByClass[chatType] = info.colorNameByClass
      end
      SetChatColorNameByClass(chatType, true)
    end
  end
end

function M:OnDisable(core)
  if type(SetChatColorNameByClass) ~= "function" then return end

  for chatType, wasEnabled in pairs(originalColorByClass) do
    if ChatTypeInfo and ChatTypeInfo[chatType] then
      SetChatColorNameByClass(chatType, wasEnabled and true or false)
    end
    originalColorByClass[chatType] = nil
  end
end

RothChat:RegisterModule(M)
