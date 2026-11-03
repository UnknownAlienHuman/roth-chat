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
  return formatString:gsub("%[%s*%%s%s*%]", "%%s")
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
  if not self.prevFormats or not self.ownedFormats then return end
  local desiredFormats = BuildFormatMap(self.prevFormats, self.core:Get("cleanerShorten"))
  for _, key in ipairs(FORMAT_KEYS) do
    local desired = desiredFormats[key]
    local current = _G[key]
    local owned = self.ownedFormats[key]

    if owned then
      if current == owned.applied then
        if current ~= desired then
          _G[key] = desired
          owned.applied = desired
        end
      else
        -- Another owner changed this format. Leave it alone for this enable cycle.
        self.ownedFormats[key] = nil
      end
    elseif current == self.prevFormats[key] and current ~= desired then
      _G[key] = desired
      self.ownedFormats[key] = { applied = desired }
    end
  end
end

function M:OnEnable(core)
  self.prevFormats = SnapshotFormats()
  self.ownedFormats = {}
  self:ApplyFormats()
end

function M:OnDisable(core)
  if self.prevFormats and self.ownedFormats then
    for _, key in ipairs(FORMAT_KEYS) do
      local owned = self.ownedFormats[key]
      -- Do not overwrite a later change made by Blizzard or another addon.
      if owned and _G[key] == owned.applied then _G[key] = self.prevFormats[key] end
    end
  end

  self.prevFormats = nil
  self.ownedFormats = nil
end

function M:Refresh(core)
  if not core:IsModuleActive("Cleaner") or not self.prevFormats then return end
  self:ApplyFormats()
end

RothChat:RegisterModule(M)
