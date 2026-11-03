-- Runtime lifecycle contract using the production core composition.
local Runtime = assert(loadfile("tests/support/runtime.lua"))()
local function loadCore(profile)
  local env = Runtime.New(profile)
  return env.core, env.filters
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

-- Partial activation must relinquish resources even when OnEnable errors.
do
  local core, filters = loadCore({})
  local disabled = 0
  local module = { name = "Partial" }
  function module:OnEnable(runtime)
    runtime:RegisterMessageFilter(self, "CHAT_MSG_SAY", function() return false end)
    runtime:On("LEAK", function() error("stale listener") end, self)
    error("activation failed")
  end
  function module:OnDisable() disabled = disabled + 1 end
  core:RegisterModule(module)
  core:OnAddonLoaded()
  assert(not core:IsModuleActive("Partial"))
  assert(disabled == 1 and filters.CHAT_MSG_SAY == nil)
  core:Emit("LEAK")
end

-- Migration preserves explicit choices and repairs corrupt primitives.
do
  local core = loadCore({ enabled = false, styleEnabled = false, restoreEnabled = false,
    styleFontSize = 9999, primaryChatIndex = -1, tickerSpeed = 0/0,
    tickerAnimation = "invalid", styleBackgroundColor = "#abcdef", styleFont = {} })
  core:OnAddonLoaded()
  assert(core:Get("enabled") == false and core:Get("styleEnabled") == false)
  assert(core:Get("restoreEnabled") == false)
  assert(core:Get("styleFontSize") == 32 and core:Get("primaryChatIndex") == 1)
  assert(core:Get("tickerSpeed") == 30 and core:Get("tickerAnimation") == "fade")
  assert(core:Get("styleBackgroundColor") == "ABCDEF")
  assert(type(core:Get("styleFont")) == "string")
  assert(core.db.history == nil, "new profiles must not allocate inactive history")
end

print("core_module_lifecycle_spec: ok")
