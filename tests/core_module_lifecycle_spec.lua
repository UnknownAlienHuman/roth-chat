-- Runtime lifecycle contract for RothChat modules.
-- Executes outside WoW with a minimal API surface.

local function pack(...)
  return { n = select("#", ...), ... }
end

unpack = table.unpack
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

function debugstack()
  return ""
end

function InCombatLockdown()
  return false
end

function hooksecurefunc()
end

function CreateFrame()
  local frame = {}

  function frame:SetScript(scriptName, callback)
    self[scriptName] = callback
  end

  function frame:RegisterEvent()
  end

  return frame
end

local function newNamespace()
  local registeredFilters = {}
  local ns = {}

  function ns.SafeCall(_, fn, ...)
    local results = pack(pcall(fn, ...))
    if not results[1] then
      return false, results[2]
    end
    return true, table.unpack(results, 2, results.n)
  end

  function ns.SafeConcat(...)
    local out = {}
    for i = 1, select("#", ...) do
      out[#out + 1] = tostring(select(i, ...))
    end
    return table.concat(out, " ")
  end

  function ns.AddMessageEventFilter(event, callback)
    registeredFilters[event] = callback
    return true
  end

  function ns.RemoveMessageEventFilter(event, callback)
    if registeredFilters[event] == callback then
      registeredFilters[event] = nil
    end
    return true
  end

  function ns.CanAccessValue()
    return true
  end

  function ns.IsSecretValue()
    return false
  end

  function ns.GetChatFrames()
    return {}
  end

  function ns.RunNextFrame(_, callback)
    callback()
  end

  function ns.IsSettingsOpenRestricted()
    return false
  end

  return ns, registeredFilters
end

local function loadCore(profile)
  RothChatDB = { profile = profile or {} }
  local ns, filters = newNamespace()
  assert(loadfile("Core.lua"))("RothChat", ns)
  return assert(_G.RothChat), filters
end

-- Initial activation, login delivery, owner cleanup, and idempotent disable.
do
  local core, filters = loadCore({})
  local calls = { init = 0, enable = 0, login = 0, disable = 0, feed = 0, bus = 0 }
  local module = {
    name = "LifecycleProbe",
    defaultEnabled = true,
  }

  local function filter()
    return false
  end

  local function feed()
    calls.feed = calls.feed + 1
  end

  function module:Init()
    calls.init = calls.init + 1
    return true
  end

  function module:OnEnable(runtime)
    calls.enable = calls.enable + 1
    runtime:On("PROBE", function()
      calls.bus = calls.bus + 1
    end, self)
    runtime:RegisterMessageFilter(self, "CHAT_MSG_SAY", filter, 50)
    runtime:RegisterAddMessageHook(feed, self, 50)
  end

  function module:OnLogin()
    calls.login = calls.login + 1
  end

  function module:OnDisable()
    calls.disable = calls.disable + 1
  end

  core:RegisterModule(module)
  core:OnAddonLoaded()

  assert(calls.init == 1)
  assert(calls.enable == 1)
  assert(calls.login == 0)
  assert(core:IsModuleActive(module.name))
  assert(#core._addMsgCallbacks == 1)
  assert(filters.CHAT_MSG_SAY ~= nil)

  core:OnPlayerLogin()
  assert(calls.login == 1, "active module must receive OnLogin exactly once")

  core:Emit("PROBE")
  assert(calls.bus == 1)

  core:DisableModule(module.name)
  assert(calls.disable == 1)
  assert(not core:IsModuleActive(module.name))
  assert(#core._addMsgCallbacks == 0, "core must remove owner AddMessage hooks")
  assert(filters.CHAT_MSG_SAY == nil, "core must remove owner message filters")

  core:Emit("PROBE")
  assert(calls.bus == 1, "core must remove owner bus listeners")

  core:DisableModule(module.name)
  assert(calls.disable == 1, "repeated disable must be idempotent")

  core:EnableModule(module.name)
  assert(calls.init == 1, "Init must remain one-shot")
  assert(calls.enable == 2)
  assert(calls.login == 1, "OnLogin is a one-shot lifecycle notification")
  assert(core:IsModuleActive(module.name))
  assert(#core._addMsgCallbacks == 1)
end

-- A module disabled at login must receive OnLogin when first enabled later.
do
  local core = loadCore({ module_LateProbe_enabled = false })
  local calls = { init = 0, enable = 0, login = 0 }
  local module = {
    name = "LateProbe",
    defaultEnabled = true,
  }

  function module:Init()
    calls.init = calls.init + 1
  end

  function module:OnEnable()
    calls.enable = calls.enable + 1
  end

  function module:OnLogin()
    calls.login = calls.login + 1
  end

  core:RegisterModule(module)
  core:OnAddonLoaded()
  core:OnPlayerLogin()

  assert(calls.init == 0)
  assert(calls.enable == 0)
  assert(calls.login == 0)

  core:SetModuleEnabled(module.name, true)
  assert(core:EnableModule(module.name))
  assert(calls.init == 1)
  assert(calls.enable == 1)
  assert(calls.login == 1, "late activation must receive the completed login lifecycle")
end

-- A profile-disabled addon must not initialize or login-notify modules.
do
  local core = loadCore({ enabled = false })
  local calls = { init = 0, enable = 0, login = 0 }
  local module = {
    name = "DisabledAddonProbe",
    defaultEnabled = true,
  }

  function module:Init()
    calls.init = calls.init + 1
  end

  function module:OnEnable()
    calls.enable = calls.enable + 1
  end

  function module:OnLogin()
    calls.login = calls.login + 1
  end

  core:RegisterModule(module)
  core:OnAddonLoaded()
  core:OnPlayerLogin()

  assert(calls.init == 0)
  assert(calls.enable == 0)
  assert(calls.login == 0)
  assert(not core:IsModuleActive(module.name))
end

print("core_module_lifecycle_spec: ok")
