-- Ownership regressions for RothChat's ChatTypeInfo mutations.
-- These cases exercise the two failure modes that value-only snapshots cannot represent:
-- an original nil value and a later external owner writing a replacement value.

local modules = {}
_G.RothChat = {
  RegisterModule = function(_, module) modules[module.name] = module end,
}

ChatTypeInfo = {
  SAY = { colorNameByClass = nil, sticky = nil },
}

local colorCalls = {}
SetChatColorNameByClass = function(chatType, enabled)
  colorCalls[#colorCalls + 1] = { chatType, enabled }
  ChatTypeInfo[chatType].colorNameByClass = enabled
end

local NS = {}
assert(loadfile("Modules/Colors.lua"))("RothChat", NS)
assert(loadfile("Modules/Sticky.lua"))("RothChat", NS)

local colors = assert(modules.Colors)
colors:Init({})
colors:OnEnable({})
assert(ChatTypeInfo.SAY.colorNameByClass == true)
colors:OnDisable({})
assert(ChatTypeInfo.SAY.colorNameByClass == nil, "Colors must restore an originally nil value")
assert(colorCalls[#colorCalls][2] == false)

-- A later addon or the user changes the property during the active period.
-- Roth Chat must leave that value intact when it relinquishes ownership.
colors:OnEnable({})
ChatTypeInfo.SAY.colorNameByClass = false
local callsBeforeDisable = #colorCalls
colors:OnDisable({})
assert(ChatTypeInfo.SAY.colorNameByClass == false, "Colors must preserve a later external value")
assert(#colorCalls == callsBeforeDisable, "Colors must not call the setter after ownership changed")

local sticky = assert(modules.Sticky)
sticky:Init({})
sticky:OnEnable({})
assert(ChatTypeInfo.SAY.sticky == 1)
sticky:OnDisable({})
assert(ChatTypeInfo.SAY.sticky == nil, "Sticky must restore an originally nil value")

sticky:OnEnable({})
ChatTypeInfo.SAY.sticky = 2
sticky:OnDisable({})
assert(ChatTypeInfo.SAY.sticky == 2, "Sticky must preserve a later external value")

print("color_sticky_ownership_spec: ok")
