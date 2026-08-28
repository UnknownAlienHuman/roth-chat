-- Cleaner locale-preservation contract.

local registeredModule
_G.RothChat = {
  RegisterModule = function(_, module)
    registeredModule = module
  end,
}

local keys = {
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

local originals = {
  CHAT_SAY_GET = "[%s]: ",
  CHAT_YELL_GET = "[%s] кричит: ",
  CHAT_WHISPER_GET = "[%s] шепчет: ",
  CHAT_WHISPER_INFORM_GET = "Кому [%s]: ",
  CHAT_GUILD_GET = "|Hchannel:Guild|h[Гильдия]|h [%s]: ",
  CHAT_OFFICER_GET = "|Hchannel:Officer|h[Офицеры]|h [%s]: ",
  CHAT_PARTY_GET = "|Hchannel:Party|h[Группа]|h [%s]: ",
  CHAT_PARTY_LEADER_GET = "|Hchannel:Party|h[Лидер группы]|h [%s]: ",
  CHAT_PARTY_GUIDE_GET = "|Hchannel:Party|h[Проводник]|h [%s]: ",
  CHAT_RAID_GET = "|Hchannel:Raid|h[Рейд]|h [%s]: ",
  CHAT_RAID_LEADER_GET = "|Hchannel:Raid|h[Лидер рейда]|h [%s]: ",
  CHAT_RAID_WARNING_GET = "[Объявление рейду] [%s]: ",
  CHAT_INSTANCE_CHAT_GET = "|Hchannel:Instance|h[Подземелье]|h [%s]: ",
  CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:Instance|h[Лидер подземелья]|h [%s]: ",
}

for _, key in ipairs(keys) do _G[key] = originals[key] end

assert(loadfile("Modules/Cleaner.lua"))("RothChat", {})
local module = assert(registeredModule)
local shorten = false
local core = {
  Get = function(_, key)
    if key == "cleanerShorten" then return shorten end
  end,
  IsModuleActive = function(_, name)
    return name == "Cleaner"
  end,
}

module:Init(core)
module:OnEnable(core)
assert(CHAT_GUILD_GET:find("Гильдия", 1, true), "localized channel label must be preserved")
assert(CHAT_WHISPER_INFORM_GET:find("Кому", 1, true), "localized whisper prefix must be preserved")
assert(not CHAT_GUILD_GET:find("[%s]", 1, true), "sender placeholder brackets must be removed")
assert(not CHAT_WHISPER_INFORM_GET:find("[%s]", 1, true))

shorten = true
module:Refresh(core)
assert(CHAT_GUILD_GET:find("[G]", 1, true), "compact mode must use the explicit compact tag")
assert(CHAT_WHISPER_INFORM_GET:find("Кому", 1, true), "compact mode must not replace localized whisper text")

module:OnDisable(core)
for _, key in ipairs(keys) do
  assert(_G[key] == originals[key], "disable must restore the original format for " .. key)
end

print("cleaner_spec: ok")
