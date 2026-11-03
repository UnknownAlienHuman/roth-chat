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
local RESTORE_MODULES = { "Restore" }
local COPY_MODULES = { "CopyOverlay" }
local pendingModuleChanges = {}

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
  if type(key) ~= "string" then return end
  local name = key:match("^module_(.+)_enabled$")
  if not name or not (RothChat.modules and RothChat.modules[name]) then return end

  value = value == true
  if not SetProfileValue(key, value) then
    return
  end

  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    if pendingModuleChanges[name] then return end
    pendingModuleChanges[name] = true
    if type(RothChat.DeferKeyed) == "function" then
      RothChat:DeferKeyed("options:module:" .. name, function()
        pendingModuleChanges[name] = nil
        if RothChat:Get("enabled") == false then return end
        if RothChat:IsModuleEnabled(name) then
          RothChat:EnableModule(name)
        else
          RothChat:DisableModule(name)
        end
      end)
    else
      RothChat:Defer(function()
        pendingModuleChanges[name] = nil
        if RothChat:Get("enabled") == false then return end
        if RothChat:IsModuleEnabled(name) then
          RothChat:EnableModule(name)
        else
          RothChat:DisableModule(name)
        end
      end)
    end
    return
  end

  if RothChat:Get("enabled") == false then return end
  if value then
    RothChat:EnableModule(name)
  else
    RothChat:DisableModule(name)
  end
end

local function ClampSliderValue(value, minimum, maximum, step)
  value = tonumber(value)
  if not value then return minimum end
  value = math.max(minimum, math.min(maximum, value))
  if type(step) == "number" and step > 0 then
    value = minimum + math.floor(((value - minimum) / step) + 0.5) * step
    value = math.max(minimum, math.min(maximum, value))
  end
  return value
end

local function IsDropdownValueAllowed(optionsFunc, value)
  if type(value) ~= "string" or type(optionsFunc) ~= "function" then return false end
  local options = optionsFunc()
  if type(options) ~= "table" then return false end
  for _, option in ipairs(options) do
    if type(option) == "table" and option.value == value then return true end
  end
  return false
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
      return RothChat:Get(key) == true
    end,
    function(value)
      ApplyProfileValue(key, value == true, moduleNames)
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
      return value == true
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
    ClampSliderValue(GetDefaultValue(key, minValue), minValue, maxValue, step),
    function()
      return ClampSliderValue(RothChat:Get(key) or GetDefaultValue(key, minValue), minValue, maxValue, step)
    end,
    function(value)
      ApplyProfileValue(key, ClampSliderValue(value, minValue, maxValue, step), moduleNames)
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
      if not IsDropdownValueAllowed(optionsFunc, value) then
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
      if not RothChat.IMMERSION_PRESETS or not RothChat.IMMERSION_PRESETS[value] then
        return
      end
      RothChat:ApplyImmersionPreset(value)
      RefreshModules(TICKER_MODULES)
      RefreshModules(CONTROLS_MODULES)
    end
  )

  Settings.CreateDropdown(category, setting, options, "Controls fade-in, fade-out, and hover delay.")
end

local function MakePresetOptions(presets)
  return function()
    local container = Settings.CreateControlTextContainer()
    local keys = {}
    for key in pairs(presets or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
      local aLabel = tostring(presets[a].label or a)
      local bLabel = tostring(presets[b].label or b)
      return aLabel < bLabel
    end)
    for _, key in ipairs(keys) do
      container:Add(key, presets[key].label or key)
    end
    return container:GetData()
  end
end

local function AddPresetDropdown(category, variable, label, tooltip, key, presets, applyMethod, moduleNames)
  if type(presets) ~= "table" or type(applyMethod) ~= "string" then return end
  local options = MakePresetOptions(presets)
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
      if type(value) ~= "string" or not presets[value] then return end
      local apply = RothChat[applyMethod]
      if type(apply) ~= "function" then return end
      apply(RothChat, value)
      RefreshModules(moduleNames)
    end
  )
  Settings.CreateDropdown(category, setting, options, tooltip)
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
  local chatBehavior = Settings.RegisterVerticalLayoutSubcategory(category, "Chat Behavior")

  AddCheckbox(
    chatBehavior,
    "ROTHCHAT_IMMERSION_ENABLED",
    "Hide Chat When Idle",
    "Fades the primary chat frame when idle and lets the ticker take over.",
    "immersionEnabled",
    TICKER_MODULES
  )
  AddImmersionPreset(chatBehavior)
  AddCheckbox(
    chatBehavior,
    "ROTHCHAT_TICKER_ENABLED",
    "Enable Ticker",
    "Shows incoming messages as an overlay when chat is hidden.",
    "tickerEnabled",
    TICKER_MODULES
  )
  AddTickerAnimation(chatBehavior)
  AddCheckbox(
    chatBehavior,
    "ROTHCHAT_SMOOTH_SCROLL",
    "Smooth Scroll",
    "Uses animated movement when scrolling chat history.",
    "smoothScrollEnabled",
    CONTROLS_MODULES
  )
  AddSlider(
    chatBehavior,
    "ROTHCHAT_PRIMARY_CHAT",
    "Primary Chat Window",
    "Chat window used for idle fading and the message ticker.",
    "primaryChatIndex",
    1,
    10,
    1,
    function(value) return tostring(math.floor(value + 0.5)) end,
    TICKER_MODULES
  )
  AddSlider(
    chatBehavior,
    "ROTHCHAT_TICKER_SPEED",
    "Ticker Speed",
    "Playback speed for the ticker animations that reveal text over time.",
    "tickerSpeed",
    5,
    100,
    5,
    function(value) return string.format("%d chars/sec", math.floor(value + 0.5)) end,
    TICKER_MODULES
  )
  AddCheckbox(
    chatBehavior,
    "ROTHCHAT_HOVER_CONTROLS",
    "Show Chat Controls on Hover",
    "Fades the chat buttons and channel bar in when the pointer enters the chat area.",
    "hoverControls",
    CONTROLS_MODULES
  )
  AddSlider(
    chatBehavior,
    "ROTHCHAT_SCROLL_DURATION",
    "Scroll Animation Duration",
    "Time used for smooth chat scrolling. Shorter values move the history faster.",
    "smoothScrollDuration",
    0.05,
    1,
    0.05,
    function(value) return string.format("%.2f sec", value) end,
    CONTROLS_MODULES
  )

  local channelBar = Settings.RegisterVerticalLayoutSubcategory(category, "Channel Bar")
  AddCheckbox(
    channelBar,
    "ROTHCHAT_CHATBAR_ENABLED",
    "Show Channel Bar",
    "Shows quick channel buttons beside the selected chat window.",
    "chatBarEnabled",
    CHATBAR_MODULES
  )
  AddSlider(
    channelBar,
    "ROTHCHAT_CHATBAR_ATTACH_TO",
    "Attach to Chat Window",
    "Chat window that receives the channel buttons.",
    "chatBarAttachTo",
    1,
    10,
    1,
    function(value) return tostring(math.floor(value + 0.5)) end,
    CHATBAR_MODULES
  )
  AddSlider(
    channelBar,
    "ROTHCHAT_CHATBAR_BUTTON_SIZE",
    "Button Size",
    "Size of the channel buttons in pixels.",
    "chatBarButtonSize",
    12,
    32,
    1,
    function(value) return tostring(math.floor(value + 0.5)) end,
    CHATBAR_MODULES
  )
  AddSlider(
    channelBar,
    "ROTHCHAT_CHATBAR_SPACING",
    "Button Spacing",
    "Gap between channel buttons in pixels.",
    "chatBarSpacing",
    0,
    16,
    1,
    function(value) return tostring(math.floor(value + 0.5)) end,
    CHATBAR_MODULES
  )
  AddDropdown(
    channelBar,
    "ROTHCHAT_CHATBAR_ANCHOR",
    "Button Position",
    "Places the channel buttons along the selected side of the chat window.",
    "chatBarAnchor",
    MakeOptions({
      { label = "Left", value = "LEFT" },
      { label = "Right", value = "RIGHT" },
      { label = "Top", value = "TOP" },
      { label = "Bottom", value = "BOTTOM" },
    }),
    CHATBAR_MODULES
  )

  local typography = Settings.RegisterVerticalLayoutSubcategory(category, "Typography")
  AddPresetDropdown(
    typography,
    "ROTHCHAT_FONT_PRESET",
    "Font Preset",
    "Applies one of Roth Chat's built-in font choices.",
    "fontPreset",
    RothChat.FONT_PRESETS,
    "ApplyFontPreset",
    FONT_MODULES
  )
  AddPresetDropdown(
    typography,
    "ROTHCHAT_TEXT_SIZE_PRESET",
    "Text Size Preset",
    "Applies a compact, normal, or large chat text size.",
    "textSizePreset",
    RothChat.TEXT_SIZE_PRESETS,
    "ApplyTextSizePreset",
    FONT_MODULES
  )
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
  AddPresetDropdown(
    background,
    "ROTHCHAT_STYLE_PRESET",
    "Appearance Preset",
    "Applies a built-in background, border, and timestamp color combination.",
    "stylePreset",
    RothChat.STYLE_PRESETS,
    "ApplyStylePreset",
    STYLE_MODULES
  )
  AddCheckbox(
    background,
    "ROTHCHAT_STYLE_ENABLED",
    "Enable Chat Styling",
    "Applies Roth Chat font, background, border, and edit box styling to chat windows.",
    "styleEnabled",
    STYLE_MODULES
  )
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

  local scrollback = Settings.RegisterVerticalLayoutSubcategory(category, "Scrollback & Copy")
  AddCheckbox(
    scrollback,
    "ROTHCHAT_RESTORE_ENABLED",
    "Keep Chat Scrollback",
    "Restores recent displayed messages after a reload for each permanent chat window.",
    "restoreEnabled",
    RESTORE_MODULES
  )
  AddSlider(
    scrollback,
    "ROTHCHAT_RESTORE_LINES",
    "Lines per Chat Window",
    "Maximum number of displayed messages retained for each chat window.",
    "restoreMaxLinesPerChat",
    100,
    5000,
    100,
    function(value) return tostring(math.floor(value + 0.5)) end,
    RESTORE_MODULES
  )
  AddCheckbox(
    scrollback,
    "ROTHCHAT_COPY_FROM_HISTORY",
    "Copy from Restored Scrollback",
    "Includes retained messages when copying chat text.",
    "copyFromHistory",
    COPY_MODULES
  )
  AddCheckbox(
    scrollback,
    "ROTHCHAT_COPY_TIMESTAMPS",
    "Include Timestamps when Copying",
    "Adds a plain timestamp to copied messages when one is available.",
    "copyIncludeTimestamps",
    COPY_MODULES
  )
  AddSlider(
    scrollback,
    "ROTHCHAT_COPY_MAX_LINES",
    "Maximum Lines to Copy",
    "Limits the number of recent chat lines shown in the copy window.",
    "copyMaxLines",
    50,
    5000,
    50,
    function(value) return tostring(math.floor(value + 0.5)) end,
    COPY_MODULES
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
