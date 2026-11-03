-- Options panel contract for RothChat's Blizzard Settings proxies.
-- Executes outside WoW with a small Settings API mock.

local saved = {}
local registered = {}
local controls = {}
local categories = {}
local deferred = {}
local inCombat = false
local refreshes = {}
local moduleCalls = {}
local presetCalls = {}
local notified = {}

local function recordControl(kind, category, setting, options)
  controls[#controls + 1] = {
    kind = kind,
    category = category,
    setting = setting,
    options = options,
  }
end

Settings = {
  VarType = { Boolean = 1, Number = 2, String = 3 },
}

function Settings.CreateControlTextContainer()
  local container = { data = {} }
  function container:Add(value, label, tooltip)
    self.data[#self.data + 1] = { value = value, label = label, tooltip = tooltip }
  end
  function container:GetData() return self.data end
  return container
end

function Settings.CreateSliderOptions(minimum, maximum, step)
  local options = { minimum = minimum, maximum = maximum, step = step }
  function options:SetLabelFormatter(_, formatter) self.formatter = formatter end
  return options
end

function Settings.RegisterVerticalLayoutCategory(name)
  local category = { name = name, id = #categories + 1 }
  function category:GetID() return self.id end
  categories[#categories + 1] = category
  return category
end

function Settings.RegisterVerticalLayoutSubcategory(parent, name)
  local category = { name = name, parent = parent }
  categories[#categories + 1] = category
  return category
end

function Settings.RegisterProxySetting(category, variable, variableType, name, defaultValue, getter, setter)
  assert(not registered[variable], "duplicate Settings proxy variable: " .. variable)
  local setting = {
    category = category,
    variable = variable,
    variableType = variableType,
    name = name,
    defaultValue = defaultValue,
    getter = getter,
    setter = setter,
  }
  registered[variable] = setting
  return setting
end

function Settings.CreateCheckbox(category, setting, tooltip)
  recordControl("checkbox", category, setting, tooltip)
end
function Settings.CreateSlider(category, setting, options, tooltip)
  recordControl("slider", category, setting, { slider = options, tooltip = tooltip })
end
function Settings.CreateDropdown(category, setting, options, tooltip)
  recordControl("dropdown", category, setting, { choices = options, tooltip = tooltip })
end
function Settings.CreateColorSwatch(category, setting, tooltip)
  recordControl("color", category, setting, tooltip)
end
function Settings.NotifyUpdate(variable) notified[variable] = (notified[variable] or 0) + 1 end
function Settings.RegisterAddOnCategory(category)
  category.registered = true
end

InCombatLockdown = function() return inCombat end

local moduleNames = {
  "Style", "Ticker", "ChatBar", "Cleaner", "Controls", "Restore", "CopyOverlay",
  "Timestamps", "Resize", "UrlCopy", "Colors", "Alerts", "Sticky",
}
local modules = {}
local active = {}
for _, name in ipairs(moduleNames) do
  modules[name] = {
    defaultEnabled = true,
    Refresh = function() refreshes[name] = (refreshes[name] or 0) + 1 end,
  }
  active[name] = true
end

local core = {
  DEFAULT_PROFILE = {
    immersionEnabled = true,
    immersionPreset = "normal",
    tickerEnabled = true,
    tickerSpeed = 30,
    tickerAnimation = "fade",
    chatBarEnabled = true,
    chatBarAttachTo = 1,
    chatBarButtonSize = 18,
    chatBarSpacing = 4,
    chatBarAnchor = "LEFT",
    smoothScrollEnabled = true,
    smoothScrollDuration = 0.25,
    primaryChatIndex = 1,
    hoverControls = true,
    styleEnabled = true,
    stylePreset = "minimal",
    fontPreset = "friz",
    textSizePreset = "normal",
    styleFont = "Fonts\\FRIZQT__.TTF",
    styleFontSize = 12,
    styleShadow = true,
    styleBackground = false,
    styleBackgroundAlpha = 0.18,
    styleBackgroundColor = "000000",
    styleBgTexture = "Interface\\Buttons\\WHITE8X8",
    styleBorder = false,
    styleBorderColor = "000000",
    styleBorderTexture = "Interface\\AddOns\\RothChat\\Assets\\border",
    timestampColor = "8E8E8E",
    editBoxPosition = "BOTTOM",
    restoreEnabled = true,
    restoreMaxLinesPerChat = 1200,
    copyFromHistory = true,
    copyIncludeTimestamps = true,
    copyMaxLines = 500,
    cleanerShorten = false,
  },
  modules = modules,
  IMMERSION_PRESETS = { fast = {}, normal = {}, slow = {} },
  STYLE_PRESETS = { minimal = { label = "Minimal" }, obsidian = { label = "Obsidian" } },
  FONT_PRESETS = { friz = { label = "Friz Quadrata" }, readable = { label = "Readable" } },
  TEXT_SIZE_PRESETS = { compact = { label = "Compact" }, normal = { label = "Normal" }, large = { label = "Large" } },
  db = { profile = saved },
}

function core:Get(key) return saved[key] end
function core:Set(key, value) saved[key] = value end
function core:IsModuleActive(name) return active[name] == true end
function core:IsModuleEnabled(name) return saved["module_" .. name .. "_enabled"] ~= false end
function core:EnableModule(name)
  moduleCalls[#moduleCalls + 1] = { "enable", name }
  active[name] = true
end
function core:DisableModule(name)
  moduleCalls[#moduleCalls + 1] = { "disable", name }
  active[name] = false
end
function core:DeferKeyed(key, callback) deferred[key] = callback end
function core:ApplyImmersionPreset(value)
  presetCalls[#presetCalls + 1] = { "immersion", value }
  saved.immersionPreset = value
end
function core:ApplyStylePreset(value)
  presetCalls[#presetCalls + 1] = { "style", value }
  saved.stylePreset = value
end
function core:ApplyFontPreset(value)
  presetCalls[#presetCalls + 1] = { "font", value }
  saved.fontPreset = value
end
function core:ApplyTextSizePreset(value)
  presetCalls[#presetCalls + 1] = { "size", value }
  saved.textSizePreset = value
end

_G.RothChat = core
local ns = {
  CanAccessValue = function() return true end,
  SafeCall = function(_, fn, ...) return pcall(fn, ...) end,
}
assert(loadfile("Options.lua"))("RothChat", ns)

local function setting(variable)
  assert(registered[variable], "missing proxy " .. variable)
  return registered[variable]
end

core:InitOptions()
local initialControlCount = #controls
local initialCategoryCount = #categories
core:InitOptions()
assert(#controls == initialControlCount, "InitOptions must not register controls twice")
assert(#categories == initialCategoryCount, "InitOptions must not register categories twice")
assert(core.optionsCategoryID == 1)
assert(setting("ROTHCHAT_RESTORE_ENABLED"), "Restore toggle should be available")
assert(setting("ROTHCHAT_COPY_TIMESTAMPS"), "copy timestamp toggle should be available")
assert(setting("ROTHCHAT_CHATBAR_ANCHOR"), "channel bar placement should be available")

-- Boolean controls accept actual boolean values only and refresh their owner.
setting("ROTHCHAT_HOVER_CONTROLS").setter("false")
assert(saved.hoverControls == false)
assert(refreshes.Controls == 1)
setting("ROTHCHAT_HOVER_CONTROLS").setter(true)
assert(saved.hoverControls == true)

-- Sliders clamp to their range and snap to the declared step before storing.
setting("ROTHCHAT_TICKER_SPEED").setter(500)
assert(saved.tickerSpeed == 100)
setting("ROTHCHAT_SCROLL_DURATION").setter(0.271)
assert(math.abs(saved.smoothScrollDuration - 0.25) < 0.000001)

-- A dropdown rejects values outside its displayed choices and applies valid choices.
setting("ROTHCHAT_TICKER_ANIMATION").setter("unsafe")
assert(saved.tickerAnimation == nil)
setting("ROTHCHAT_TICKER_ANIMATION").setter("marquee")
assert(saved.tickerAnimation == "marquee")

-- Preset controls use Core as the single place that writes preset-derived fields.
setting("ROTHCHAT_STYLE_PRESET").setter("missing")
assert(#presetCalls == 0)
setting("ROTHCHAT_STYLE_PRESET").setter("obsidian")
assert(presetCalls[1][1] == "style" and saved.stylePreset == "obsidian")
assert(refreshes.Style == 1)
assert(notified.ROTHCHAT_STYLE_BACKGROUND == 1)
assert(notified.ROTHCHAT_STYLE_BACKGROUND_ALPHA == 1)
assert(notified.ROTHCHAT_STYLE_BACKGROUND_COLOR == 1)
assert(notified.ROTHCHAT_STYLE_BORDER == 1)
assert(notified.ROTHCHAT_STYLE_BORDER_COLOR == 1)
assert(notified.ROTHCHAT_TIMESTAMP_COLOR == 1)
setting("ROTHCHAT_FONT_PRESET").setter("readable")
assert(notified.ROTHCHAT_STYLE_FONT == 1 and notified.ROTHCHAT_STYLE_SHADOW == 1)
setting("ROTHCHAT_TEXT_SIZE_PRESET").setter("large")
assert(notified.ROTHCHAT_STYLE_FONT_SIZE == 1)

-- Module toggles save immediately but defer runtime lifecycle changes in combat.
inCombat = true
setting("ROTHCHAT_URLCOPY_ENABLED").setter(false)
assert(saved.module_UrlCopy_enabled == false)
assert(#moduleCalls == 0)
setting("ROTHCHAT_URLCOPY_ENABLED").setter(true)
assert(saved.module_UrlCopy_enabled == true)
assert(#moduleCalls == 0)
inCombat = false
local queued = deferred["options:module:UrlCopy"]
assert(type(queued) == "function", "module lifecycle change should be combat-deferred")
queued()
assert(#moduleCalls == 1 and moduleCalls[1][1] == "enable", "deferred change should use latest saved value")

print("options_spec: ok")
