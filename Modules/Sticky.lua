-- RothChat - Sticky module
-- Goal: Make chat channels "sticky" (remember last used channel).

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Sticky",
  defaultEnabled = true,
  description = "Makes chat channels sticky (remembers last used channel).",
}

local STICKY_TYPES = {
  "SAY", "YELL", "EMOTE", "PARTY", "RAID", "GUILD", "OFFICER",
  "WHISPER", "BN_WHISPER", "CHANNEL", "INSTANCE_CHAT"
}
local originalSticky = {}

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  for _, type in ipairs(STICKY_TYPES) do
    local info = ChatTypeInfo[type]
    if info then
      if originalSticky[type] == nil then
        originalSticky[type] = info.sticky
      end
      info.sticky = 1
    end
  end
end

function M:OnDisable(core)
  for _, type in ipairs(STICKY_TYPES) do
    local info = ChatTypeInfo[type]
    if info and originalSticky[type] ~= nil then
      info.sticky = originalSticky[type]
      originalSticky[type] = nil
    end
  end
end

RothChat:RegisterModule(M)
