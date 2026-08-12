-- RothChat - Cleaner module
-- Goal: Remove clutter like brackets around player names, shorten channel names, and hide realm names.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "Cleaner",
  defaultEnabled = true,
  description = "Removes brackets, shortens channels, and hides realm names.",
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


local function BuildFormatMap(shorten)
  local out = {
    CHAT_SAY_GET = "%s:\32",
    CHAT_YELL_GET = "%s:\32",
    CHAT_WHISPER_GET = "%s:\32",
    CHAT_WHISPER_INFORM_GET = "To %s:\32",
  }

  if shorten then
    out.CHAT_GUILD_GET = "|Hchannel:Guild|h[G]|h %s:\32"
    out.CHAT_OFFICER_GET = "|Hchannel:Officer|h[O]|h %s:\32"
    out.CHAT_PARTY_GET = "|Hchannel:Party|h[P]|h %s:\32"
    out.CHAT_PARTY_LEADER_GET = "|Hchannel:Party|h[PL]|h %s:\32"
    out.CHAT_PARTY_GUIDE_GET = "|Hchannel:Party|h[PG]|h %s:\32"
    out.CHAT_RAID_GET = "|Hchannel:Raid|h[R]|h %s:\32"
    out.CHAT_RAID_LEADER_GET = "|Hchannel:Raid|h[RL]|h %s:\32"
    out.CHAT_RAID_WARNING_GET = "[RW] %s:\32"
    out.CHAT_INSTANCE_CHAT_GET = "|Hchannel:Instance|h[I]|h %s:\32"
    out.CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:Instance|h[IL]|h %s:\32"
  else
    out.CHAT_GUILD_GET = "|Hchannel:Guild|h[Guild]|h %s:\32"
    out.CHAT_OFFICER_GET = "|Hchannel:Officer|h[Officer]|h %s:\32"
    out.CHAT_PARTY_GET = "|Hchannel:Party|h[Party]|h %s:\32"
    out.CHAT_PARTY_LEADER_GET = "|Hchannel:Party|h[Party Leader]|h %s:\32"
    out.CHAT_PARTY_GUIDE_GET = "|Hchannel:Party|h[Dungeon Guide]|h %s:\32"
    out.CHAT_RAID_GET = "|Hchannel:Raid|h[Raid]|h %s:\32"
    out.CHAT_RAID_LEADER_GET = "|Hchannel:Raid|h[Raid Leader]|h %s:\32"
    out.CHAT_RAID_WARNING_GET = "[Raid Warning] %s:\32"
    out.CHAT_INSTANCE_CHAT_GET = "|Hchannel:Instance|h[Instance]|h %s:\32"
    out.CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:Instance|h[Instance Leader]|h %s:\32"
  end

  return out
end

local function SnapshotFormats()
  local out = {}
  for _, key in ipairs(FORMAT_KEYS) do
    out[key] = _G[key]
  end
  return out
end

-- Keep Cleaner on the safe side of Blizzard's chat pipeline.
-- Overwriting ChatFrameUtil helpers taints MessageEventHandler and can trip
-- secret-value errors later in HistoryKeeper, even for unrelated chat events.

function M:Init(core)
  self.core = core
  return true
end

function M:OnEnable(core)
  self.prevFormats = SnapshotFormats()
  self.appliedFormats = BuildFormatMap(core:Get("cleanerShorten"))
  self:ApplyFormats()
end

function M:ApplyFormats()
  if not self.appliedFormats then return end
  for _, key in ipairs(FORMAT_KEYS) do
    local value = self.appliedFormats[key]
    if value ~= nil then
      _G[key] = value
    end
  end
end

function M:OnDisable(core)
  if core and core.UnregisterMessageFilters then
    core:UnregisterMessageFilters(self)
  end

  if self.prevFormats and self.appliedFormats then
    for _, key in ipairs(FORMAT_KEYS) do
      local prev = self.prevFormats[key]
      local applied = self.appliedFormats[key]
      if applied ~= nil and _G[key] == applied then
        _G[key] = prev
      end
    end
  end

  self.prevFormats = nil
  self.appliedFormats = nil
end

function M:Refresh(core)
  if not core:IsModuleEnabled("Cleaner") then
    self:OnDisable(core)
    return
  end

  if not self.prevFormats then
    self.prevFormats = SnapshotFormats()
  end

  self.appliedFormats = BuildFormatMap(core:Get("cleanerShorten"))
  self:ApplyFormats()
end

RothChat:RegisterModule(M)
