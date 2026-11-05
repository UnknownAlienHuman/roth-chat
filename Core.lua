-- RothChat - configuration, module lifecycle and combat-deferred work.

local ADDON_NAME, NS = ...

local RothChat = CreateFrame("Frame")
_G.RothChat = RothChat

RothChat.name = "RothChat"
-- TOC metadata is the single release-version source.
RothChat.version = "development"
if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
  local ok, version = pcall(_G.C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
  if ok and NS.CanAccessValue(version) and type(version) == "string" and version ~= "" then
    RothChat.version = version
  end
end

RothChat.modules = {}        -- [moduleName] = moduleTable
RothChat.moduleOrder = {}    -- ordered list
RothChat.moduleState = {}    -- [moduleName] = runtime lifecycle state
RothChat._deferred = {}
RothChat._deferredByKey = {}
RothChat._deferredCount = 0
RothChat._nextDeferredID = 0
RothChat._addonLoaded = false
RothChat._addonEnabled = false
RothChat._loginComplete = false

-- -----------------------------------------------------------------------------
-- Saved variables
-- -----------------------------------------------------------------------------

local DEFAULTS = {
  profile = {
    enabled = true,
    debug = false,

    -- Restore (persistent scrollback per chat window)
    restoreEnabled = true,
    restoreMaxLinesPerChat = 1200,

    -- Immersion (hide chat, keep ticker)
    immersionEnabled = true,
    immersionPreset = "normal", -- "fast" | "normal" | "slow"
    immersionChatAlphaHidden = 0.0,
    immersionChatAlphaShown = 1.0,
    immersionFadeDuration = 0.12,
    immersionFadeInDuration = 0.12,
    immersionFadeOutDuration = 0.65,
    tickerEnabled = true,
    tickerSpeed = 30,         -- chars per second
    tickerAnimation = "fade", -- "fade" | "typewriter" | "slide" | "marquee"

    -- Interaction
    hoverControls = true, -- controls (blizz buttons + roth bar) fade in on hover
    hoverAlphaHidden = 0.0,
    hoverAlphaShown = 1.0,
    hoverFadeDuration = 0.12,
    hoverFadeInDuration = 0.12,
    hoverFadeOutDuration = 0.45,
    hoverFadeDelay = 15, -- seconds to wait after cursor leaves before fading

    -- Hover hotspot
    hotspotPadding = 10,

    -- Smooth Scrolling
    smoothScrollEnabled = true,
    smoothScrollSpeed = 15,
    smoothScrollDuration = 0.25,

    -- Copy
    copyMaxLines = 500,
    copyFromHistory = true,
    copyIncludeTimestamps = true,

    -- Primary chat window for immersion/ticker
    primaryChatIndex = 1,

    -- ChatBar
    chatBarEnabled = true,
    chatBarAttachTo = 1, -- ChatFrame index
    chatBarButtonSize = 18,
    chatBarSpacing = 4,
    chatBarAnchor = "LEFT", -- LEFT/RIGHT/TOP/BOTTOM

    -- Style
    stylePreset = "minimal",
    fontPreset = "friz",
    textSizePreset = "normal",
    styleEnabled = true,
    styleFont = "Fonts\\FRIZQT__.TTF",
    styleFontSize = 12,
    styleFontOutline = "",
    styleShadow = true,
    styleBackground = false,
    styleBackgroundAlpha = 0.18,
    styleBackgroundColor = "000000",
    styleBorder = false,
    styleBorderColor = "000000",
    styleBgTexture = "Interface\\Buttons\\WHITE8X8",
    styleBorderTexture = "Interface\\AddOns\\RothChat\\Assets\\border",
    editBoxPosition = "BOTTOM",

    -- Formatting
    cleanerShorten = false,
    timestampColor = "8E8E8E",
  }
}
RothChat.DEFAULT_PROFILE = DEFAULTS.profile

-- Immersion speed presets (applied via Options dropdown)
local IMMERSION_PRESETS = {
  fast   = { fadeIn = 0.08, fadeOut = 0.3,  delay = 8,  hoverIn = 0.08, hoverOut = 0.25 },
  normal = { fadeIn = 0.12, fadeOut = 0.65, delay = 15, hoverIn = 0.12, hoverOut = 0.45 },
  slow   = { fadeIn = 0.2,  fadeOut = 1.2,  delay = 25, hoverIn = 0.18, hoverOut = 0.8  },
}
RothChat.IMMERSION_PRESETS = IMMERSION_PRESETS

local STYLE_PRESETS = {
  minimal = {
    label = "Minimal",
    styleBackground = false,
    styleBackgroundAlpha = 0.18,
    styleBackgroundColor = "000000",
    styleBorder = false,
    styleBorderColor = "000000",
    timestampColor = "8E8E8E",
  },
}
STYLE_PRESETS.obsidian = {
  label = "Obsidian",
  styleBackground = true,
  styleBackgroundAlpha = 0.30,
  styleBackgroundColor = "080A12",
  styleBorder = false,
  styleBorderColor = "3D465A",
  timestampColor = "9EA9BE",
}
STYLE_PRESETS.ember = {
  label = "Ember",
  styleBackground = true,
  styleBackgroundAlpha = 0.42,
  styleBackgroundColor = "110B0A",
  styleBorder = true,
  styleBorderColor = "6B4930",
  timestampColor = "C59B63",
}
RothChat.STYLE_PRESETS = STYLE_PRESETS

local FONT_PRESETS = {
  friz = {
    label = "Friz Quadrata",
    styleFont = "Fonts\\FRIZQT__.TTF",
    styleFontOutline = "",
    styleShadow = true,
  },
  readable = {
    label = "Arial Narrow",
    styleFont = "Fonts\\ARIALN.TTF",
    styleFontOutline = "",
    styleShadow = true,
  },
  cyr = {
    label = "Friz Cyrillic",
    styleFont = "Fonts\\FRIZQT___CYR.TTF",
    styleFontOutline = "",
    styleShadow = true,
  },
  wide = {
    label = "AR Hei Wide",
    styleFont = "Fonts\\ARHei.TTF",
    styleFontOutline = "",
    styleShadow = true,
  },
}
RothChat.FONT_PRESETS = FONT_PRESETS

local TEXT_SIZE_PRESETS = {
  compact = { label = "Compact", styleFontSize = 11 },
  normal = { label = "Normal", styleFontSize = 12 },
  large = { label = "Large", styleFontSize = 14 },
}
RothChat.TEXT_SIZE_PRESETS = TEXT_SIZE_PRESETS

local function InferFontPreset(profile)
  local font = type(profile.styleFont) == "string" and profile.styleFont:upper() or ""
  if font:find("ARHEI", 1, true) then
    return "wide"
  elseif font:find("FRIZQT___CYR", 1, true) then
    return "cyr"
  elseif font:find("ARIALN", 1, true) then
    return "readable"
  end
  return "friz"
end

local function InferTextSizePreset(profile)
  local size = tonumber(profile.styleFontSize) or 12
  if size <= 11 then
    return "compact"
  elseif size >= 14 then
    return "large"
  end
  return "normal"
end

function RothChat:ApplyImmersionPreset(presetName)
  local p = IMMERSION_PRESETS[presetName]
  if not p then return end
  self:Set("immersionPreset", presetName)
  self:Set("immersionFadeInDuration", p.fadeIn)
  self:Set("immersionFadeOutDuration", p.fadeOut)
  self:Set("hoverFadeDelay", p.delay)
  self:Set("hoverFadeInDuration", p.hoverIn)
  self:Set("hoverFadeOutDuration", p.hoverOut)
end

function RothChat:ApplyStylePreset(presetName)
  local p = STYLE_PRESETS[presetName]
  if not p then return end
  self:Set("stylePreset", presetName)
  self:Set("styleBackground", p.styleBackground)
  self:Set("styleBackgroundAlpha", p.styleBackgroundAlpha)
  self:Set("styleBackgroundColor", p.styleBackgroundColor)
  self:Set("styleBorder", p.styleBorder)
  self:Set("styleBorderColor", p.styleBorderColor)
  self:Set("timestampColor", p.timestampColor)
end

function RothChat:ApplyFontPreset(presetName)
  local p = FONT_PRESETS[presetName]
  if not p then return end
  self:Set("fontPreset", presetName)
  self:Set("styleFont", p.styleFont)
  self:Set("styleFontOutline", p.styleFontOutline)
  self:Set("styleShadow", p.styleShadow)
end

function RothChat:ApplyTextSizePreset(presetName)
  local p = TEXT_SIZE_PRESETS[presetName]
  if not p then return end
  self:Set("textSizePreset", presetName)
  self:Set("styleFontSize", p.styleFontSize)
end

-- Settings and SavedVariables share one normalization owner. Repair invalid
-- values without replacing explicit false choices or valid custom media paths.
local NUMBER_LIMITS = {
  restoreMaxLinesPerChat = { 100, 5000, true },
  immersionChatAlphaHidden = { 0, 1 }, immersionChatAlphaShown = { 0, 1 },
  immersionFadeDuration = { 0, 5 }, immersionFadeInDuration = { 0, 5 }, immersionFadeOutDuration = { 0, 5 },
  tickerSpeed = { 5, 100 }, hoverAlphaHidden = { 0, 1 }, hoverAlphaShown = { 0, 1 },
  hoverFadeDuration = { 0, 5 }, hoverFadeInDuration = { 0, 5 }, hoverFadeOutDuration = { 0, 5 },
  hoverFadeDelay = { 0, 60 }, hotspotPadding = { 0, 40 },
  smoothScrollSpeed = { 1, 50 }, smoothScrollDuration = { 0.05, 1 },
  copyMaxLines = { 50, 5000, true }, primaryChatIndex = { 1, 10, true },
  chatBarAttachTo = { 1, 10, true }, chatBarButtonSize = { 12, 32, true }, chatBarSpacing = { 0, 16, true },
  styleFontSize = { 8, 32, true }, styleBackgroundAlpha = { 0, 1 },
}
local ENUM_VALUES = {
  immersionPreset = IMMERSION_PRESETS, stylePreset = STYLE_PRESETS,
  fontPreset = FONT_PRESETS, textSizePreset = TEXT_SIZE_PRESETS,
  tickerAnimation = { fade = true, typewriter = true, slide = true, marquee = true },
  chatBarAnchor = { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true },
  editBoxPosition = { TOP = true, BOTTOM = true },
  styleFontOutline = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
    ["OUTLINE,MONOCHROME"] = true, ["THICKOUTLINE,MONOCHROME"] = true },
}
local COLOR_KEYS = { styleBackgroundColor = true, styleBorderColor = true, timestampColor = true }

local function NormalizeValue(key, value)
  local fallback = DEFAULTS.profile[key]
  if fallback == nil then return nil end
  if not NS.CanAccessValue(value) or type(value) ~= type(fallback) then return fallback end
  local limits = NUMBER_LIMITS[key]
  if limits then
    value = NS.Clamp(NS.SafeNumber(value, fallback), limits[1], limits[2])
    return limits[3] and math.floor(value) or value
  end
  local choices = ENUM_VALUES[key]
  if choices then return choices[value] and value or fallback end
  if COLOR_KEYS[key] then
    value = value:gsub("^#", ""):upper()
    return #value == 6 and value:match("^%x+$") and value or fallback
  end
  if type(value) == "string" and (#value > 256 or value:find("%z") or value == "") then return fallback end
  return value
end

local function InitDB()
  if type(RothChatDB) ~= "table" then RothChatDB = {} end
  if type(RothChatDB.profile) ~= "table" then RothChatDB.profile = {} end
  local profile = RothChatDB.profile
  local hadFontPreset, hadTextSizePreset = profile.fontPreset ~= nil, profile.textSizePreset ~= nil
  for key in pairs(DEFAULTS.profile) do profile[key] = NormalizeValue(key, profile[key]) end
  if not hadFontPreset then profile.fontPreset = InferFontPreset(profile) end
  if not hadTextSizePreset then profile.textSizePreset = InferTextSizePreset(profile) end
  profile.__version = RothChat.version
  RothChat.db = RothChatDB
  -- Existing legacy history remains untouched, but no inactive history store
  -- or obsolete History module settings are created for new profiles.
end

function RothChat:Get(k)
  return self.db and self.db.profile and self.db.profile[k]
end

function RothChat:Set(key, value)
  if not self.db or not self.db.profile or type(key) ~= "string" then return false end
  if DEFAULTS.profile[key] ~= nil then
    value = NormalizeValue(key, value)
  else
    local moduleName = key:match("^module_(.+)_enabled$")
    if not moduleName or not self.modules[moduleName] or type(value) ~= "boolean" then return false end
  end
  if self.db.profile[key] == value then return false end
  self.db.profile[key] = value
  return true
end

function RothChat:Debug(...)
  if self:Get("debug") then return self:Print(...) end
end

function RothChat:Print(...)
  local frame = _G.DEFAULT_CHAT_FRAME
  if NS.IsChatMessagingRestricted() or not NS.CanAccessObject(frame)
    or type(frame.AddMessage) ~= "function" then return false end
  frame:AddMessage("|cff70d0ffRothChat|r " .. NS.SafeConcat(...))
  return true
end

-- -----------------------------------------------------------------------------
-- Module framework
-- -----------------------------------------------------------------------------

function RothChat:RegisterModule(module)
  if type(module) ~= "table" or type(module.name) ~= "string" then
    return
  end
  if self.modules[module.name] then
    return
  end

  local defaultEnabled = module.defaultEnabled ~= false
  self.modules[module.name] = module
  self.moduleOrder[#self.moduleOrder + 1] = module.name
  self.moduleState[module.name] = {
    defaultEnabled = defaultEnabled,
    loaded = false,
    initOK = false,
    active = false,
    loginCalled = false,
  }
end

function RothChat:IsModuleEnabled(name)
  local st = self.moduleState[name]
  if not st then return false end
  local key = "module_" .. name .. "_enabled"
  local v = self:Get(key)
  if v == nil then return st.defaultEnabled end
  return v and true or false
end

function RothChat:IsModuleActive(name)
  local st = self.moduleState[name]
  return st and st.active and true or false
end

function RothChat:SetModuleEnabled(name, enabled)
  local key = "module_" .. name .. "_enabled"
  self:Set(key, enabled and true or false)
end

function RothChat:ForEachModule(fn)
  for _, name in ipairs(self.moduleOrder) do
    local m = self.modules[name]
    if m then fn(name, m) end
  end
end

local function SafeModuleCall(self, name, method, ...)
  local m = self.modules[name]
  if not m then return false end
  if type(m[method]) ~= "function" then return true end

  return NS.SafeCall("RothChat:" .. name .. ":" .. method, m[method], m, self, ...)
end

local function CleanupModuleRegistrations(self, module)
  if not module then return end
  self:UnregisterMessageFilters(module)
  self:UnregisterAddMessageHooks(module)
  self:OffOwner(module)
end

local function NotifyModuleLogin(self, name)
  local st = self.moduleState[name]
  local module = self.modules[name]
  if not st or not module or not st.active or st.loginCalled or not self._loginComplete then
    return true
  end

  local ok = SafeModuleCall(self, name, "OnLogin")
  if ok then
    st.loginCalled = true
    return true
  end

  st.active = false
  SafeModuleCall(self, name, "OnDisable")
  CleanupModuleRegistrations(self, module)
  return false
end

function RothChat:EnableModule(name)
  local module = self.modules[name]
  local st = self.moduleState[name]
  if not module or not st then return false end
  if self._addonLoaded and not self._addonEnabled then return false end
  if st.active then return true end

  if not st.loaded then
    local ok = SafeModuleCall(self, name, "Init")
    st.loaded = true
    st.initOK = ok and true or false
    if not st.initOK then
      SafeModuleCall(self, name, "OnDisable")
      CleanupModuleRegistrations(self, module)
      return false
    end
  elseif not st.initOK then
    return false
  end

  -- Owner-aware registrations are rebuilt for every activation. This prevents
  -- stale callbacks from surviving an incomplete module-specific OnDisable.
  CleanupModuleRegistrations(self, module)
  local ok = SafeModuleCall(self, name, "OnEnable")
  if not ok then
    st.active = false
    SafeModuleCall(self, name, "OnDisable")
    CleanupModuleRegistrations(self, module)
    return false
  end

  st.active = true
  if not NotifyModuleLogin(self, name) then
    return false
  end

  return true
end

function RothChat:DisableModule(name)
  local module = self.modules[name]
  local st = self.moduleState[name]
  if not module or not st then return false end

  -- Teardown callbacks and their emitted events must observe the module as
  -- inactive. This prevents another module from reacting to stale activation
  -- state while OnDisable restores shared UI ownership.
  local wasActive = st.active
  st.active = false

  if wasActive then
    SafeModuleCall(self, name, "OnDisable")
  end

  CleanupModuleRegistrations(self, module)
  return true
end

function RothChat:ApplyModuleEnablement()
  if self._addonLoaded and not self._addonEnabled then return end

  self:ForEachModule(function(name)
    if self:IsModuleEnabled(name) then
      self:EnableModule(name)
    else
      self:DisableModule(name)
    end
  end)
end

-- -----------------------------------------------------------------------------
-- Bounded latest-state work; no message tuples or changing permissions retained.
-- -----------------------------------------------------------------------------

function RothChat:DeferKeyed(key, callback, ...)
  if not NS.CanAccessAllValues(key, callback) or key == nil
    or type(callback) ~= "function" or not NS.CanAccessAllValues(...)
  then
    return false
  end

  local job = self._deferredByKey[key]
  if job then
    job.fn, job.args = callback, NS.Pack(...)
    return true
  end
  if self._deferredCount >= 128 then return false end
  if #self._deferred >= 128 then
    local retained = {}
    for _, old in ipairs(self._deferred) do
      if old.fn then retained[#retained + 1] = old end
    end
    self._deferred = retained
  end
  self._nextDeferredID = self._nextDeferredID + 1
  job = {
    key = key,
    fn = callback,
    args = NS.Pack(...),
    diagnosticLabel = "RothChat:Deferred#" .. tostring(self._nextDeferredID),
  }
  self._deferredByKey[key] = job
  self._deferred[#self._deferred + 1] = job
  self._deferredCount = self._deferredCount + 1
  return true
end

function RothChat:CancelDeferred(key)
  if key == nil or not NS.CanAccessValue(key) then return false end
  local job = self._deferredByKey[key]
  if not job then return false end
  job.fn = nil
  self._deferredByKey[key] = nil
  self._deferredCount = self._deferredCount - 1
  if self._deferredCount == 0 then self._deferred = {} end
  return true
end

function RothChat:RunDeferred()
  if InCombatLockdown() or self._deferredCount == 0 then return end
  local jobs = self._deferred
  self._deferred = {}
  for _, job in ipairs(jobs) do
    if self._deferredByKey[job.key] == job and job.fn then
      if InCombatLockdown() then
        self._deferred[#self._deferred + 1] = job
      else
        self._deferredByKey[job.key] = nil
        self._deferredCount = self._deferredCount - 1
        NS.SafeCall(job.diagnosticLabel, job.fn, NS.Unpack(job.args))
      end
    end
  end
end

-- -----------------------------------------------------------------------------
-- Lifecycle
-- -----------------------------------------------------------------------------

local function EnsureModuleFlagsInDB()
  -- Persist default module enabled flags into SavedVariables (only if absent).
  RothChat:ForEachModule(function(name, mod)
    local key = "module_" .. name .. "_enabled"
    if type(RothChat:Get(key)) ~= "boolean" then
      RothChat:Set(key, mod.defaultEnabled ~= false)
    end
  end)
end

function RothChat:OnAddonLoaded()
  InitDB()
  self._addonLoaded = true
  self._addonEnabled = self:Get("enabled") ~= false

  EnsureModuleFlagsInDB()
  if not self._addonEnabled then return end
  self:EnsureChatLifecycleHooks()
  self:ApplyModuleEnablement()
end

function RothChat:OnPlayerLogin()
  self._loginComplete = true

  if self._addonEnabled then
    self:ForEachModule(function(name)
      local st = self.moduleState[name]
      if st and st.active then
        NotifyModuleLogin(self, name)
      end
    end)

    self:QueueChatLifecycleRefresh(nil, "player_login")
  end

  -- Options panel is created after all modules are registered.
  if type(self.InitOptions) == "function" then
    NS.SafeCall("RothChat:InitOptions", self.InitOptions, self)
  end
end

-- Event handler
RothChat:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON_NAME then
      self:OnAddonLoaded()
      self:UnregisterEvent("ADDON_LOADED")
    end
  elseif event == "PLAYER_LOGIN" then
    self:OnPlayerLogin()
  elseif event == "PLAYER_REGEN_ENABLED" then
    self:RunDeferred()
  elseif event == "UPDATE_CHAT_WINDOWS" or event == "UPDATE_FLOATING_CHAT_WINDOWS" then
    if self._addonEnabled then self:QueueChatLifecycleRefresh(nil, event) end
  elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
    local restricted = NS.IsChatMessagingRestricted()
    self:Emit("CHAT_RESTRICTION_CHANGED", restricted)
    if not restricted and self._addonEnabled then self:QueueChatLifecycleRefresh(nil, "restriction_changed") end
  end
end)

RothChat:RegisterEvent("ADDON_LOADED")
RothChat:RegisterEvent("PLAYER_LOGIN")
RothChat:RegisterEvent("PLAYER_REGEN_ENABLED")
RothChat:RegisterEvent("UPDATE_CHAT_WINDOWS")
RothChat:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
RothChat:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")

-- Slash command
SLASH_ROTHCHAT1 = "/rothchat"
SlashCmdList["ROTHCHAT"] = function(msg)
  if NS.IsSettingsOpenRestricted() then
    RothChat:Print("Settings are unavailable while combat or chat restrictions are active.")
    return
  end

  if Settings and Settings.OpenToCategory then
    -- Ensure options category is built before trying to open it.
    if not RothChat.optionsCategoryID and type(RothChat.InitOptions) == "function" then
      NS.SafeCall("RothChat:InitOptions", RothChat.InitOptions, RothChat)
    end

    if RothChat.optionsCategoryID then
      Settings.OpenToCategory(RothChat.optionsCategoryID)
    else
      RothChat:Print("Open Settings -> AddOns -> Roth Chat")
    end
  else
    RothChat:Print("Open Settings -> AddOns -> Roth Chat")
  end
end
