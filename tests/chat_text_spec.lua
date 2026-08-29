-- Shared chat-text boundary contract.

local accessible = true
local NS = {
  CanAccessValue = function()
    return accessible
  end,
  SafeToString = function(value)
    return value == nil and "" or tostring(value)
  end,
}

_G.date = function(format, timestamp)
  assert(format == "[%H:%M]")
  assert(timestamp == 12345)
  return "[12:34]"
end

assert(loadfile("ChatText.lua"))("RothChat", NS)

assert(NS.NormalizeHexColor("#8e8e8e", "999999") == "8E8E8E")
assert(NS.NormalizeHexColor("|cffA1B2C3", "999999") == "A1B2C3")
assert(NS.NormalizeHexColor("invalid", "999999") == "999999")

assert(NS.FormatChatTimestamp(12345, false) == "[12:34] ")
assert(NS.FormatChatTimestamp(12345, true, "8e8e8e") == "|cff8E8E8E[12:34]|r ")

local timestamped = "|cff8E8E8E[12:34]|r hello"
assert(NS.HasRothTimestampPrefix(timestamped))
assert(NS.StripRothTimestampPrefix(timestamped) == "hello")
assert(not NS.HasRothTimestampPrefix("[12:34] user text"))

local durable = NS.SanitizeDurableChatText(
  "A |Kaccount|k B |Wprivate|w C |HBNplayer:Foo:1|hVisible|h "
  .. "|Hcensoredmessage:42|hsecret|h"
)
assert(not durable:find("|K", 1, true))
assert(not durable:find("|W", 1, true))
assert(not durable:find("|HBNplayer", 1, true))
assert(not durable:find("censoredmessage:", 1, true))
assert(durable:find("Visible", 1, true))
assert(durable:find("[Censored message unavailable after reload]", 1, true))

local formatted = "|cff8E8E8E[12:34]|r |Hitem:19019|h[Thunderfury]|h || pipe"
assert(NS.NormalizeCopyText(formatted, true) == "[12:34] [Thunderfury] | pipe")
assert(NS.NormalizeCopyText(formatted, false) == "[Thunderfury] | pipe")

local multiline = "[12:34] first\n[12:34:56] second\nthird"
assert(NS.NormalizeCopyText(multiline, false) == "first\nsecond\nthird")

accessible = false
assert(NS.SanitizeDurableChatText("secret") == "")
assert(NS.NormalizeCopyText("secret", true) == "")
assert(NS.FormatChatTimestamp(12345, true, "FFFFFF") == "")
assert(not NS.HasRothTimestampPrefix(timestamped))

print("chat_text_spec: ok")
