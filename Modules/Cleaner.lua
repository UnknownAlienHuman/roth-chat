-- RothChat - Cleaner module
-- Removes brackets around sender placeholders while preserving client locale.
-- Optional compact channel tags are language-neutral.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Cleaner",
  defaultEnabled = true,
  description = "Removes sender brackets and optionally shortens channel tags.",
}

local FORMAT_KEYS = {
  "CHAT_SAY_GET",
  "CHAT_YELL_GET",
  "CHAT_WHISPER_GET",
  "CHAT_WHISPER_INFORM_GET",
  "CHAT_GUILD_GET",
  "CHAT_OFFICER_GET",
  "CHAT_PARTY_GET",
  "CHAT_PARTY_LEADER_GET",
  "CHAT_PARTY_GUIDE_GET",
  "CHAT_RAID_GET",
  "CHAT_RAID_LEADER_GET",
  "CHAT_RAID_WARNING_GET",
  "CHAT_INSTANCE_CHAT_GET",
  "CHAT_INSTANCE_CHAT_LEADER_GET",
}

local COMPACT_FORMATS = {
  CHAT_GUILD_GET = "|Hchannel:Guild|h[G]|h %s:\32",
  CHAT_OFFICER_GET = "|Hchannel:Officer|h[O]|h %s:\32",
  CHAT_PARTY_GET = "|Hchannel:Party|h[P]|h %s:\32",
  CHAT_PARTY_LEADER_GET = "|Hchannel:Party|h[PL]|h %s:\32",
  CHAT_PARTY_GUIDE_GET = "|Hchannel:Party|h[PG]|h %s:\32",
  CHAT_RAID_GET = "|Hchannel:Raid|h[R]|h %s:\32",
  CHAT_RAID_LEADER_GET = "|Hchannel:Raid|h[RL]|h %s:\32",
  CHAT_RAID_WARNING_GET = "[RW] %s:\32",
  CHAT_INSTANCE_CHAT_GET = "|Hchannel:Instance|h[I]|h %s:\32",
  CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:Instance|h[IL]|h %s:\32",
}

local function SnapshotFormats()
  local out = {}
  for _, key in ipairs(FORMAT_KEYS) do out[key] = _G[key] end
  return out
end

local function RemoveSenderBrackets(formatString)
  if type(formatString) ~= "string" then return formatString end

  -- Preserve Blizzard's localized channel labels, colors and hyperlinks. Only
  -- remove literal square brackets that directly wrap the sender placeholder.
  local cleaned = formatString:gsub("%[%%s%]", "%%s")
  cleaned = cleaned:gsub("%[%s*%%s%s*%]", "%%s")
  return cleaned
end

local function BuildFormatMap(baseFormats, shorten)
  local out = {}
  for _, key in ipairs(FORMAT_KEYS) do
    out[key] = RemoveSenderBrackets(baseFormats[key])
  end

  if shorten then
    for key, formatString in pairs(COMPACT_FORMATS) do
      out[key] = formatString
    end
  end

  return out
end

function M:Init(core)
  self.core = core
  return true
end

function M:ApplyFormats()
  if not self.appliedFormats then return end
  for _, key in ipairs(FORMAT_KEYS) do
    local value = self.appliedFormats[key]
    if value ~= nil then _G[key] = value end
  end
end

function M:OnEnable(core)
  self.prevFormats = SnapshotFormats()
  self.appliedFormats = BuildFormatMap(self.prevFormats, core:Get("cleanerShorten"))
  self:ApplyFormats()
end

function M:OnDisable(core)
  if self.prevFormats and self.appliedFormats then
    for _, key in ipairs(FORMAT_KEYS) do
      local previous = self.prevFormats[key]
      local applied = self.appliedFormats[key]
      -- Do not overwrite a later change made by Blizzard or another addon.
      if applied ~= nil and _G[key] == applied then _G[key] = previous end
    end
  end

  self.prevFormats = nil
  self.appliedFormats = nil
end

function M:Refresh(core)
  if not core:IsModuleActive("Cleaner") or not self.prevFormats then return end
  self.appliedFormats = BuildFormatMap(self.prevFormats, core:Get("cleanerShorten"))
  self:ApplyFormats()
end

RothChat:RegisterModule(M)
