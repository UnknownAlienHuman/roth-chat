-- UrlCopy transformation and event-coverage contract.

local function pack(...)
  return { n = select("#", ...), ... }
end

local registeredModule
local capturedFilter
local capturedHandler
local capturedEvents
local accessible = true

_G.RothChat = {
  RegisterModule = function(_, module)
    registeredModule = module
  end,
  IsModuleActive = function(_, name)
    return name == "UrlCopy"
  end,
}

_G.GetTime = function() return 100 end
_G.LinkProcessorResponse = { Handled = 1 }
_G.LinkUtil = {
  FormatLink = function(linkType, text, options)
    return "|H" .. linkType .. ":" .. options .. "|h" .. text .. "|h"
  end,
  IsLinkHandlerRegistered = function() return false end,
  RegisterLinkHandler = function(linkType, handler)
    assert(linkType == "rothchaturl")
    capturedHandler = handler
  end,
}

local NS = {
  CanAccessValue = function() return accessible end,
  ApplyGlassLook = function() end,
}

assert(loadfile("Modules/UrlCopy.lua"))("RothChat", NS)
local module = assert(registeredModule)

local core = {
  RegisterMessageFilters = function(_, owner, events, callback, priority)
    assert(owner == module)
    assert(type(events) == "table" and #events > 0)
    assert(priority == 60)
    capturedEvents = events
    capturedFilter = callback
    return #events
  end,
}

module:Init(core)
module:OnEnable(core)
assert(type(capturedFilter) == "function")
assert(type(capturedHandler) == "function")

local eventSet = {}
for _, event in ipairs(capturedEvents) do eventSet[event] = true end
for _, required in ipairs({
  "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER_INFORM",
  "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_COMMUNITIES_CHANNEL",
  "CHAT_MSG_EMOTE",
  "CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_SYSTEM",
  "CHAT_MSG_ACHIEVEMENT",
  "CHAT_MSG_GUILD_ACHIEVEMENT",
}) do
  assert(eventSet[required], required .. " must be linkified")
end

local transformed = pack(capturedFilter(nil, "CHAT_MSG_SAY", "See https://example.com/a_(b)."))
assert(transformed.n == 2)
assert(transformed[1] == false)
assert(transformed[2]:find("|Hrothchaturl:https://example.com/a_(b)|h", 1, true))
assert(transformed[2]:sub(-1) == ".")

local unmatched = pack(capturedFilter(nil, "CHAT_MSG_SAY", "See https://example.com/a)."))
assert(unmatched.n == 2)
assert(unmatched[2]:find("|Hrothchaturl:https://example.com/a|h", 1, true))
assert(unmatched[2]:sub(-2) == ").")

local existing = "|Hitem:19019|h[Thunderfury]|h and https://example.com/path"
local mixed = pack(capturedFilter(nil, "CHAT_MSG_SAY", existing))
assert(mixed.n == 2)
assert(mixed[2]:find("|Hitem:19019|h[Thunderfury]|h", 1, true))
assert(mixed[2]:find("|Hrothchaturl:https://example.com/path|h", 1, true))

local bnet = pack(capturedFilter(nil, "CHAT_MSG_BN_WHISPER_INFORM", "discord.gg/example"))
assert(bnet.n == 2)
assert(bnet[2]:find("|Hrothchaturl:discord.gg/example|h", 1, true))

accessible = false
local inaccessible = pack(capturedFilter(nil, "CHAT_MSG_SAY", "https://example.com"))
assert(inaccessible.n == 1)
assert(inaccessible[1] == false)

print("url_copy_spec: ok")
