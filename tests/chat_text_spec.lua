-- Shared chat-text boundary contract.

local accessible = true
local nativeFormat = "[%H:%M] "
local NS = {
  CanAccessValue = function()
    return accessible
  end,
  SafeToString = function(value)
    return value == nil and "" or tostring(value)
  end,
}

_G.ChatFrameUtil = {
  GetTimestampFormat = function()
    return nativeFormat
  end,
}
_G.TimeUtil = {
  BetterDate = function(format, timestamp)
    assert(format == nativeFormat)
    assert(timestamp >= 12344 and timestamp <= 12346)
    return "[12:34] "
  end,
}
_G.date = function(format, timestamp)
  assert(timestamp == 12345)
  if format == "[%H:%M]" then return "[12:34]" end
  if format == "[%H:%M:%S]" then return "[12:34:56]" end
  error("unexpected date format: " .. tostring(format))
end

assert(loadfile("ChatText.lua"))("RothChat", NS)

assert(NS.NormalizeHexColor("#8e8e8e", "999999") == "8E8E8E")
assert(NS.NormalizeHexColor("|cffA1B2C3", "999999") == "A1B2C3")
assert(NS.NormalizeHexColor("invalid", "999999") == "999999")

assert(NS.FormatChatTimestamp(12345, false) == "[12:34] ")
assert(NS.FormatChatTimestamp(12345, false, nil, "%H:%M:%S") == "[12:34:56] ")
assert(NS.FormatChatTimestamp(12345, true, "8e8e8e") == "|cff8E8E8E[12:34]|r ")
assert(NS.HasNativeChatTimestamps())
assert(NS.FormatNativeChatTimestamp(12345) == "[12:34] ")

local timestamped = "|cff8E8E8E[12:34]|r hello"
assert(NS.HasRothTimestampPrefix(timestamped))
assert(NS.StripRothTimestampPrefix(timestamped) == "hello")
assert(not NS.HasRothTimestampPrefix("[12:34] user text"))
assert(NS.StripDisplayTimestampPrefix("[12:34] native", 12345, false) == "native")
assert(NS.StripDisplayTimestampPrefix(timestamped, 12345, false) == "hello")

local durable = NS.SanitizeDurableChatText(
  "A |Kaccount|k B |Wprivate|w C |HBNplayer:Foo:1|hVisible|h "
  .. "|Hplayer:Tester:77:WHISPER:Target|h[Tester]|h "
  .. "|Hchannel:channel:2|h[2. Trade]|h "
  .. "|Hitem:19019|h[Thunderfury]|h "
  .. "|Hcensoredmessage:42|hsecret|h"
)
assert(not durable:find("|K", 1, true))
assert(not durable:find("|W", 1, true))
assert(not durable:find("|HBNplayer", 1, true))
assert(not durable:find("censoredmessage:", 1, true))
assert(not durable:find("|Hchannel", 1, true))
assert(durable:find("Visible", 1, true))
assert(durable:find("|Hplayer:Tester|h[Tester]|h", 1, true))
assert(durable:find("|Hitem:19019|h[Thunderfury]|h", 1, true))
assert(durable:find("[Censored message unavailable after reload]", 1, true))

local formatted = "|cff8E8E8E[12:34]|r |Hitem:19019|h[Thunderfury]|h || pipe"
assert(NS.NormalizeCopyText(formatted, true) == "[12:34] [Thunderfury] | pipe")
assert(NS.NormalizeCopyText(formatted, false) == "[Thunderfury] | pipe")

local multiline = "[12:34] first\n[12:34:56] second\n[3:45 PM] third\n[3:45:12 PM] fourth"
assert(NS.NormalizeCopyText(multiline, false) == "first\nsecond\nthird\nfourth")

nativeFormat = nil
assert(not NS.HasNativeChatTimestamps())
assert(NS.StripDisplayTimestampPrefix("[12:34] legacy", 12345, true) == "legacy")

accessible = false
assert(NS.SanitizeDurableChatText("secret") == "")
assert(NS.NormalizeCopyText("secret", true) == "")
assert(NS.FormatChatTimestamp(12345, true, "FFFFFF") == "")
assert(not NS.HasRothTimestampPrefix(timestamped))

print("chat_text_spec: ok")
