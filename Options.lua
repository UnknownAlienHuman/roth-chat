-- RothChat - Settings panel
-- Uses Blizzard's modern Settings API with proxy settings backed by RothChatDB.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local OPTIONS_NAME = "Roth Chat"
local settingsCategory

local STYLE_MODULES = { "Style" }
local FONT_MODULES = { "Style", "Ticker", "ChatBar", "CopyOverlay" }
local TICKER_MODULES = { "Ticker" }
local CHATBAR_MODULES = { "ChatBar" }
local CLEANER_MODULES = { "Cleaner" }
local CONTROLS_MODULES = { "Controls" }

local BUILTIN_MEDIA = {
  font = {
    { label = "Friz Quadrata", value = "Fonts\\FRIZQT__.TTF" },
    { label = "Arial Narrow", value = "Fonts\\ARIALN.TTF" },
    { label = "Friz Cyrillic", value = "Fonts\\FRIZQT___CYR.TTF" },
    { label = "AR Hei", value = "Fonts\\ARHei.TTF" },
  },
  background = {
    { label = "Solid", value = "Interface\\Buttons\\WHITE8X8" },
    { label = "Tooltip", value = "Interface\\Tooltips\\UI-Tooltip-Background" },
  },
  border = {
    { label = "Roth Border", value = "Interface\\AddOns\\RothChat\\Assets\\border" },
  },
}

local function GetLSM()
  return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function GetDefaultValue(key, fallback)
  local defaults = RothChat and RothChat.DEFAULT_PROFILE
  local value = defaults and defaults[key]
  if value == nil then
    return fallback
  end
  return value
end

local function GetModuleDefault(key)
  local name = type(key) == "string" and key:match("^module_(.+)_enabled$")
  local module = name and RothChat.modules and RothChat.modules[name]
  if module then
    return module.defaultEnabled ~= false
  end
  return false
end

local function SafeCallRefresh(name, mod)
  if not mod or type(mod.Refresh) ~= "function" then
    return
  end
  NS.SafeCall("RothChat:" .. name .. ":Refresh", mod.Refresh, mod, RothChat)
end

local function RefreshModules(moduleNames)
  if type(moduleNames) ~= "table" then
    return
  end

  local seen = {}
  for _, name in ipairs(moduleNames) do
    if not seen[name] and RothChat:IsModuleActive(name) then
      seen[name] = true
      SafeCallRefresh(name, RothChat.modules and RothChat.modules[name])
    end
  end
end

local function SetProfileValue(key, value)
  if RothChat:Get(key) == value then
    return false
  end
  RothChat:Set(key, value)
  return true
end

local function ApplyProfileValue(key, value, moduleNames)
  if not SetProfileValue(key, value) then
    return
  end
  RefreshModules(moduleNames)
end

local function ApplyModuleToggle(key, value)
  value = value and true or false
  if not SetProfileValue(key, value) then
    return
  end

  local name = key:match("^module_(.+)_enabled$")
  if not name then
    RothChat:ApplyModuleEnablement()
  elseif value then
    RothChat:EnableModule(name)
  else
    RothChat:DisableModule(name)
  end
end

local function NormalizeRGBHex(value, fallback)
  local source = type(value) == "string" and value or fallback or "FFFFFF"
  source = source:gsub("^#", ""):gsub("^|c%x%x", ""):upper()
  if #source >= 8 then
    source = source:sub(#source - 5)
  end
  source = source:sub(1, 6)
  if #source == 6 and source:match("^[0-9A-F]+$") then
    return source
  end
  return fallback or "FFFFFF"
end

local function RGBToARGB(value, fallback)
  return "FF" .. NormalizeRGBHex(value, fallback)
end

local function ARGBToRGB(value, fallback)
  return NormalizeRGBHex(value, fallback)
end

local function MakeOptions(list)
  return function()
    local container = Settings.CreateControlTextContainer()
    for _, item in ipairs(list) do
      container:Add(item.value, item.label, item.tooltip)
    end
    return container:GetData()
  end
end

local function MakeMediaOptions(mediaType, profileKey)
  return function()
    local container = Settings.CreateControlTextContainer()
    local seen = {}

    local function Add(label, value)
      if type(label) ~= "string" or type(value) ~= "string" or value == "" then
        return
      end

      local dedupeKey = value:upper()
      if seen[dedupeKey] then
        return
      end

      seen[dedupeKey] = true
      container:Add(value, label)
    end

    for _, entry in ipairs(BUILTIN_MEDIA[mediaType] or {}) do
      Add(entry.label, entry.value)
    end

    local currentValue = profileKey and RothChat:Get(profileKey)
    if type(currentValue) == "string" and currentValue ~= "" then
      Add("Current Selection", currentValue)
    end

    local lsm = GetLSM()
    if lsm and type(lsm.List) == "function" and type(lsm.Fetch) == "function" then
      local names = lsm:List(mediaType)
      if type(names) == "table" then
        local sorted = {}
        for i = 1, #names do
          sorted[i] = names[i]
        end
        table.sort(sorted)

        for _, name in ipairs(sorted) do
          Add(name, lsm:Fetch(mediaType, name))
        end
      end
    end

    return container:GetData()
  end
end

local function MakeSliderOptions(minValue, maxValue, step, formatter)
  local options = Settings.CreateSliderOptions(minValue, maxValue, step)
  if formatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
  end
  return options
end

local function RegisterProxySetting(category, variable, variableType, name, defaultValue, getValue, setValue)
  return Settings.RegisterProxySetting(category, variable, variableType, name, defaultValue, getValue, setValue)
end

local function AddCheckbox(category, variable, label, tooltip, key, moduleNames)
  local setting = RegisterProxySetting(
    category,
    variable,
    Settings.VarType.Boolean,
    label,
    GetDefaultValue(key, false),
    function()
      return RothChat:Get(key) and true or false
    end,
    function(value)
      ApplyProfileValue(key, value and true or false, moduleNames)
    end
  )

  Settings.CreateCheckbox(category, setting, tooltip)
end

local function AddModuleCheckbox(category, variable, label, tooltip, key)
  local setting = RegisterProxySetting(
    category,
    variable,
    Settings.VarType.Boolean,
    label,
    GetModuleDefault(key),
    function()
      local value = RothChat:Get(key)
      if value == nil then
        return GetModuleDefault(key)
      end
      return value and true or false
    end,
    function(value)
      ApplyModuleToggle(key, value)
    end
  )

  Settings.CreateCheckbox(category, setting, tooltip)
end

local function AddSlider(category, variable, label, tooltip, key, minValue, maxValue, step, formatter, moduleNames)
  local setting = RegisterProxySetting(
    category,
    variable,
    Settings.VarType.Number,
    label,
    tonumber(GetDefaultValue(key, minValue)) or minValue,
    function()
      return tonumber(RothChat:Get(key)) or tonumber(GetDefaultValue(key, minValue)) or minValue
    end,
    function(value)
      ApplyProfileValue(key, tonumber(value) or minValue, moduleNames)
    end
  )

  Settings.CreateSlider(category, setting, MakeSliderOptions(minValue, maxValue, step, formatter), tooltip)
end

local function AddDropdown(category, variable, label, tooltip, key, optionsFunc, moduleNames)
  local setting = RegisterProxySetting(
    category,
    variable,
    Settings.VarType.String,
    label,
    tostring(GetDefaultValue(key, "")),
    function()
      return tostring(RothChat:Get(key) or GetDefaultValue(key, ""))
    end,
    function(value)
      if type(value) ~= "string" then
        return
      end
      ApplyProfileValue(key, value, moduleNames)
    end
  )

  Settings.CreateDropdown(category, setting, optionsFunc, tooltip)
end

local function AddColorSwatch(category, variable, label, tooltip, key, moduleNames, fallbackRGB)
  local defaultRGB = NormalizeRGBHex(GetDefaultValue(key, fallbackRGB), fallbackRGB)
  local setting = RegisterProxySetting(
    category,
    variable,
    Settings.VarType.String,
    label,
    RGBToARGB(defaultRGB, fallbackRGB),
    function()
      return RGBToARGB(RothChat:Get(key), fallbackRGB)
    end,
    function(value)
      ApplyProfileValue(key, ARGBToRGB(value, fallbackRGB), moduleNames)
    end
  )

  Settings.CreateColorSwatch(category, setting, tooltip)
end

local function AddImmersionPreset(category)
  local options = MakeOptions({
    { label = "Fast", value = "fast" },
    { label = "Normal", value = "normal" },
    { label = "Slow", value = "slow" },
  })

  local setting = RegisterProxySetting(
    category,
    "ROTHCHAT_IMMERSION_PRESET",
    Settings.VarType.String,
    "Immersion Speed",
    tostring(GetDefaultValue("immersionPreset", "normal")),
    function()
      return tostring(RothChat:Get("immersionPreset") or GetDefaultValue("immersionPreset", "normal"))
    end,
    function(value)
      if type(value) ~= "string" or value == "" then
        return
      end
      RothChat:ApplyImmersionPreset(value)
      RefreshModules(TICKER_MODULES)
      RefreshModules(CONTROLS_MODULES)
    end
  )

  Settings.CreateDropdown(category, setting, options, "Controls fade-in, fade-out, and hover delay.")
end

local function AddTickerAnimation(category)
  local options = MakeOptions({
    { label = "Fade", value = "fade" },
    { label = "Typewriter", value = "typewriter" },
    { label = "Slide Up", value = "slide" },
    { label = "Marquee", value = "marquee" },
  })

  AddDropdown(
    category,
    "ROTHCHAT_TICKER_ANIMATION",
    "Ticker Animation",
    "Animation used for hidden-chat message playback.",
    "tickerAnimation",
    options,
    TICKER_MODULES
  )
end

local function AddEditBoxPosition(category)
  local options = MakeOptions({
    { label = "Bottom", value = "BOTTOM" },
    { label = "Top", value = "TOP" },
  })

  AddDropdown(
    category,
    "ROTHCHAT_EDITBOX_POSITION",
    "Edit Box Position",
    "Controls whether the chat input box sits above or below the frame.",
    "editBoxPosition",
    options,
    STYLE_MODULES
  )
end

local function BuildSettingsCategory()
  if settingsCategory or not Settings or not Settings.RegisterVerticalLayoutCategory then
    return
  end

  local category = Settings.RegisterVerticalLayoutCategory(OPTIONS_NAME)
  settingsCategory = category

  AddCheckbox(
    category,
    "ROTHCHAT_IMMERSION_ENABLED",
    "Hide Chat When Idle",
    "Fades the primary chat frame when idle and lets the ticker take over.",
    "immersionEnabled",
    TICKER_MODULES
  )
  AddImmersionPreset(category)
  AddCheckbox(
    category,
    "ROTHCHAT_TICKER_ENABLED",
    "Enable Ticker",
    "Shows incoming messages as an overlay when chat is hidden.",
    "tickerEnabled",
    TICKER_MODULES
  )
  AddTickerAnimation(category)
  AddCheckbox(
    category,
    "ROTHCHAT_CHATBAR_ENABLED",
    "Channel Bar",
    "Shows the quick channel buttons beside the chat frame.",
    "chatBarEnabled",
    CHATBAR_MODULES
  )
  AddCheckbox(
    category,
    "ROTHCHAT_SMOOTH_SCROLL",
    "Smooth Scroll",
    "Uses animated movement when scrolling chat history.",
    "smoothScrollEnabled",
    CONTROLS_MODULES
  )

  local typography = Settings.RegisterVerticalLayoutSubcategory(category, "Typography")
  AddDropdown(
    typography,
    "ROTHCHAT_STYLE_FONT",
    "Chat Font",
    "Chooses the chat font. SharedMedia fonts are listed when available.",
    "styleFont",
    MakeMediaOptions("font", "styleFont"),
    FONT_MODULES
  )
  AddSlider(
    typography,
    "ROTHCHAT_STYLE_FONT_SIZE",
    "Font Size",
    "Base font size used by RothChat text surfaces.",
    "styleFontSize",
    8,
    24,
    1,
    function(value)
      return tostring(math.floor(value + 0.5))
    end,
    FONT_MODULES
  )
  AddCheckbox(
    typography,
    "ROTHCHAT_STYLE_SHADOW",
    "Text Shadow",
    "Adds a text shadow for readability.",
    "styleShadow",
    FONT_MODULES
  )
  AddModuleCheckbox(
    typography,
    "ROTHCHAT_TIMESTAMPS_ENABLED",
    "Show Timestamps",
    "Injects timestamps into chat lines.",
    "module_Timestamps_enabled"
  )
  AddColorSwatch(
    typography,
    "ROTHCHAT_TIMESTAMP_COLOR",
    "Timestamp Color",
    "Color used for timestamp prefixes.",
    "timestampColor",
    nil,
    "8E8E8E"
  )
  AddEditBoxPosition(typography)

  local background = Settings.RegisterVerticalLayoutSubcategory(category, "Background")
  AddCheckbox(
    background,
    "ROTHCHAT_STYLE_BACKGROUND",
    "Show Background Fill",
    "Enables the custom chat background fill.",
    "styleBackground",
    STYLE_MODULES
  )
  AddSlider(
    background,
    "ROTHCHAT_STYLE_BACKGROUND_ALPHA",
    "Background Alpha",
    "Opacity of the custom chat background fill.",
    "styleBackgroundAlpha",
    0,
    0.9,
    0.05,
    function(value)
      return string.format("%d%%", math.floor((value * 100) + 0.5))
    end,
    STYLE_MODULES
  )
  AddColorSwatch(
    background,
    "ROTHCHAT_STYLE_BACKGROUND_COLOR",
    "Background Color",
    "Color tint applied to the chat background fill.",
    "styleBackgroundColor",
    STYLE_MODULES,
    "000000"
  )
  AddDropdown(
    background,
    "ROTHCHAT_STYLE_BACKGROUND_TEXTURE",
    "Background Texture",
    "Background texture path. SharedMedia backgrounds are listed when available.",
    "styleBgTexture",
    MakeMediaOptions("background", "styleBgTexture"),
    STYLE_MODULES
  )

  local border = Settings.RegisterVerticalLayoutSubcategory(category, "Border")
  AddCheckbox(
    border,
    "ROTHCHAT_STYLE_BORDER",
    "Show Border",
    "Enables the custom border around the chat frame.",
    "styleBorder",
    STYLE_MODULES
  )
  AddColorSwatch(
    border,
    "ROTHCHAT_STYLE_BORDER_COLOR",
    "Border Color",
    "Color applied to the custom chat border.",
    "styleBorderColor",
    STYLE_MODULES,
    "000000"
  )
  AddDropdown(
    border,
    "ROTHCHAT_STYLE_BORDER_TEXTURE",
    "Border Texture",
    "Border texture path. SharedMedia borders are listed when available.",
    "styleBorderTexture",
    MakeMediaOptions("border", "styleBorderTexture"),
    STYLE_MODULES
  )

  local features = Settings.RegisterVerticalLayoutSubcategory(category, "Features")
  AddModuleCheckbox(
    features,
    "ROTHCHAT_RESIZE_ENABLED",
    "Resize Grip",
    "Keeps the RothChat resize grip active.",
    "module_Resize_enabled"
  )
  AddModuleCheckbox(
    features,
    "ROTHCHAT_URLCOPY_ENABLED",
    "Clickable URLs",
    "Converts URLs into clickable chat links.",
    "module_UrlCopy_enabled"
  )
  AddModuleCheckbox(
    features,
    "ROTHCHAT_COLORS_ENABLED",
    "Class Colors",
    "Applies class colors to player names where supported.",
    "module_Colors_enabled"
  )
  AddModuleCheckbox(
    features,
    "ROTHCHAT_CLEANER_ENABLED",
    "Cleaner",
    "Applies RothChat chat formatting cleanup rules.",
    "module_Cleaner_enabled"
  )
  AddCheckbox(
    features,
    "ROTHCHAT_CLEANER_SHORTEN",
    "Shorten Channels",
    "Uses compact channel tags such as [G] or [P].",
    "cleanerShorten",
    CLEANER_MODULES
  )
  AddModuleCheckbox(
    features,
    "ROTHCHAT_ALERTS_ENABLED",
    "Chat Alerts",
    "Plays whisper sounds and highlights inactive tabs on new messages.",
    "module_Alerts_enabled"
  )
  AddModuleCheckbox(
    features,
    "ROTHCHAT_STICKY_ENABLED",
    "Sticky Channels",
    "Remembers the last used channel between chat edits.",
    "module_Sticky_enabled"
  )

  Settings.RegisterAddOnCategory(category)
  RothChat.optionsCategoryID = category:GetID()
end

function RothChat:InitOptions()
  BuildSettingsCategory()
end
