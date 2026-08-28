-- RothChat - core
-- Goal: Prat-like modularity with Glass-like immersion.
-- We do NOT copy Prat/Glass; this is a clean-room implementation.

local ADDON_NAME, NS = ...

local RothChat = CreateFrame("Frame")
_G.RothChat = RothChat

RothChat.name = "RothChat"
RothChat.version = "1.1.1"

RothChat.modules = {}        -- [moduleName] = moduleTable
RothChat.moduleOrder = {}    -- ordered list
RothChat.moduleState = {}    -- [moduleName] = runtime lifecycle state
RothChat._moduleFilters = {} -- [moduleTable] = { [event] = { {callback, owner, priority}, ... } }
RothChat._messageFilterState = {} -- [event] = { entries = { {callback, owner, priority}, ... }, dispatcher, registered }

-- Deferred operations that are unsafe in combat.
RothChat._deferred = {}
RothChat._addonLoaded = false
RothChat._addonEnabled = false
RothChat._loginComplete = false
RothChat._chatLifecycleHooked = false
RothChat._chatLifecycleQueue = {
  queued = false,
  refreshAll = false,
  layoutReason = nil,
  frameReasons = {},
  closedFrames = {},
}
RothChat._chatLifecycleScheduleKey = {}

-- -----------------------------------------------------------------------------
-- Saved variables
-- -----------------------------------------------------------------------------

local DEFAULTS = {
  profile = {
    enabled = true,
    debug = false,

    -- History / persistence
    historyEnabled = false,
    historyMaxEntries = 20000,

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

local function InferStylePreset(profile)
  return "minimal"
end

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

local function InitDB()
  if not RothChatDB or type(RothChatDB) ~= "table" then
    RothChatDB = {}
  end
  if type(RothChatDB.profile) ~= "table" then
    RothChatDB.profile = {}
  end

  local hadStylePreset = RothChatDB.profile.stylePreset ~= nil
  local hadFontPreset = RothChatDB.profile.fontPreset ~= nil
  local hadTextSizePreset = RothChatDB.profile.textSizePreset ~= nil

  -- Apply defaults (shallow; profile values are primitives)
  for k, v in pairs(DEFAULTS.profile) do
    if RothChatDB.profile[k] == nil then
      RothChatDB.profile[k] = v
    end
  end

  -- Profile versioning / minimal migration. Version bumps must never overwrite
  -- explicit feature or module choices that already exist in SavedVariables.
  local prevVersion = RothChatDB.profile.__version
  if prevVersion ~= RothChat.version then
    -- New in v0.9.3: separate fade-in/out durations.
    if RothChatDB.profile.immersionFadeInDuration == nil then RothChatDB.profile.immersionFadeInDuration = 0.12 end
    if RothChatDB.profile.immersionFadeOutDuration == nil then RothChatDB.profile.immersionFadeOutDuration = 0.65 end
    if RothChatDB.profile.hoverFadeInDuration == nil then RothChatDB.profile.hoverFadeInDuration = 0.12 end
    if RothChatDB.profile.hoverFadeOutDuration == nil then RothChatDB.profile.hoverFadeOutDuration = 0.45 end
    -- Keep legacy single-duration sliders in a sane range.
    if type(RothChatDB.profile.hoverFadeDuration) == "number" and RothChatDB.profile.hoverFadeDuration > 1.0 then
      RothChatDB.profile.hoverFadeDuration = RothChatDB.profile.hoverFadeInDuration
    end

    -- History is legacy (Restore handles persistence); only initialize an
    -- absent flag. Never flip a value the user explicitly stored.
    if RothChatDB.profile.module_History_enabled == nil then
      RothChatDB.profile.module_History_enabled = false
    end

    if RothChatDB.profile.timestampColor == nil then
      RothChatDB.profile.timestampColor = DEFAULTS.profile.timestampColor
    end

    if not hadStylePreset then
      RothChatDB.profile.stylePreset = InferStylePreset(RothChatDB.profile)
    end
    if not hadFontPreset then
      RothChatDB.profile.fontPreset = InferFontPreset(RothChatDB.profile)
    end
    if not hadTextSizePreset then
      RothChatDB.profile.textSizePreset = InferTextSizePreset(RothChatDB.profile)
    end

    RothChatDB.profile.__version = RothChat.version
  end

  if not hadStylePreset and RothChatDB.profile.stylePreset == nil then
    RothChatDB.profile.stylePreset = InferStylePreset(RothChatDB.profile)
  end

  RothChat.db = RothChatDB

  -- Non-profile data
  if type(RothChatDB.history) ~= "table" then
    RothChatDB.history = { version = 1, entries = {} }
  elseif type(RothChatDB.history.entries) ~= "table" then
    RothChatDB.history.entries = {}
  end
end

-- -----------------------------------------------------------------------------
-- Event bus (internal, module-to-module)
-- -----------------------------------------------------------------------------

RothChat._listeners = {} -- [event] = { {fn=..., owner=...}, ... }

function RothChat:On(event, fn, owner)
  if type(event) ~= "string" or type(fn) ~= "function" then return end
  local list = self._listeners[event]
  if not list then
    list = {}
    self._listeners[event] = list
  end
  list[#list + 1] = { fn = fn, owner = owner }
end

function RothChat:Off(event, fn)
  local list = self._listeners[event]
  if not list or type(fn) ~= "function" then return end
  for i = #list, 1, -1 do
    if list[i].fn == fn then
      table.remove(list, i)
    end
  end
end

-- Remove all registered listeners for a given owner (typically a module table).
function RothChat:OffOwner(owner)
  if not owner then return end
  for _, list in pairs(self._listeners) do
    for i = #list, 1, -1 do
      if list[i].owner == owner then
        table.remove(list, i)
      end
    end
  end
end

function RothChat:Emit(event, ...)
  local list = self._listeners[event]
  if not list then return end
  for i = 1, #list do
    local it = list[i]
    if it and it.fn then
      NS.SafeCall("RothChat:Emit:" .. event, it.fn, it.owner, self, ...)
    end
  end
end

function RothChat:Get(k)
  return self.db and self.db.profile and self.db.profile[k]
end

function RothChat:Set(k, v)
  if not self.db or not self.db.profile then return end
  self.db.profile[k] = v
end

function RothChat:Debug(...)
  if not self:Get("debug") then return end
  local msg = NS.SafeConcat(...)
  DEFAULT_CHAT_FRAME:AddMessage("|cff70d0ffRothChat|r " .. msg)
end

function RothChat:Print(...)
  local msg = NS.SafeConcat(...)
  DEFAULT_CHAT_FRAME:AddMessage("|cff70d0ffRothChat|r " .. msg)
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
    enabled = defaultEnabled, -- compatibility field; configured state lives in the profile
    loaded = false,
    initOK = false,
    active = false,
    loginCalled = false,
    ok = false,
    err = nil,
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

local function InsertSortedByPriority(list, entry)
  local pri = entry[3]
  for i = 1, #list do
    if pri < list[i][3] then
      table.insert(list, i, entry)
      return
    end
  end
  list[#list + 1] = entry
end

local function RemoveListEntry(list, target)
  if not list or not target then return end
  for i = #list, 1, -1 do
    if list[i] == target then
      table.remove(list, i)
    end
  end
end

local function MultiErrorHandler(err)
  return tostring(err) .. "\n" .. debugstack(2, 25, 25)
end

-- Preserve both arity and nil positions. Chat filters gained a complete
-- 19-field contract in Retail 12.1, and future events may grow again.
local function PackValues(...)
  return { n = select("#", ...), ... }
end

local function UnpackValues(values, first)
  return unpack(values, first or 1, values.n)
end

local function SafeCallMulti(label, fn, ...)
  if type(fn) ~= "function" then
    return false
  end

  local results = PackValues(xpcall(fn, MultiErrorHandler, ...))
  if not results[1] then
    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff4040%s error|r: %s", tostring(label or "RothChat"), tostring(results[2])))
    end
    return false
  end

  return true, UnpackValues(results, 2)
end

local function GetOrCreateMessageFilterState(self, event)
  local state = self._messageFilterState[event]
  if state then
    return state
  end

  state = {
    entries = {},
  }

  -- Module filters may replace visible arg1 only. The dispatcher itself keeps
  -- the complete incoming tuple and returns a replacement tuple only when text
  -- actually changed. A no-op `return false` leaves Blizzard's secure tuple
  -- untouched, reducing taint on routing, sender, line-ID and access metadata.
  state.dispatcher = function(chatFrame, evt, ...)
    local args = PackValues(...)
    if args.n < 1 or (NS.CanAccessValue and not NS.CanAccessValue(args[1])) then
      return false
    end

    local current = self._messageFilterState[evt]
    local entries = current and current.entries
    local shouldDiscardMessage = false
    local transformedMessage = false

    if entries then
      for i = 1, #entries do
        local entry = entries[i]
        if entry and entry[1] then
          local results = PackValues(
            SafeCallMulti(
              "RothChat:MsgFilter:" .. evt,
              entry[1],
              chatFrame,
              evt,
              UnpackValues(args)
            )
          )

          if results[1] then
            local discard = results[2]
            local newArg1 = results[3]

            if discard then
              shouldDiscardMessage = true
              break
            elseif newArg1 and (not NS.CanAccessValue or NS.CanAccessValue(newArg1)) then
              args[1] = newArg1
              if args.n < 1 then
                args.n = 1
              end
              transformedMessage = true
            end
          end
        end
      end
    end

    if shouldDiscardMessage then
      return true
    end

    if transformedMessage then
      return false, UnpackValues(args)
    end

    return false
  end

  self._messageFilterState[event] = state
  return state
end

function RothChat:RegisterMessageFilter(owner, event, callback, priority)
  if type(owner) ~= "table" or type(event) ~= "string" or type(callback) ~= "function" then
    return false
  end
  priority = tonumber(priority) or 50

  local byEvent = self._moduleFilters[owner]
  if not byEvent then
    byEvent = {}
    self._moduleFilters[owner] = byEvent
  end

  local list = byEvent[event]
  if not list then
    list = {}
    byEvent[event] = list
  end

  for i = 1, #list do
    if list[i][1] == callback then
      return true
    end
  end

  local state = GetOrCreateMessageFilterState(self, event)
  if not state.registered then
    local ok = NS.AddMessageEventFilter(event, state.dispatcher)
    if not ok then
      return false
    end
    state.registered = true
  end

  local entry = { callback, owner, priority }
  InsertSortedByPriority(state.entries, entry)
  list[#list + 1] = entry
  return true
end

function RothChat:RegisterMessageFilters(owner, events, callback, priority)
  if type(events) ~= "table" then return 0 end
  local n = 0
  for i = 1, #events do
    if self:RegisterMessageFilter(owner, events[i], callback, priority) then
      n = n + 1
    end
  end
  return n
end

function RothChat:UnregisterMessageFilters(owner)
  if type(owner) ~= "table" then return end
  local byEvent = self._moduleFilters[owner]
  if not byEvent then return end

  for event, list in pairs(byEvent) do
    local state = self._messageFilterState[event]
    if state then
      for i = #list, 1, -1 do
        RemoveListEntry(state.entries, list[i])
        list[i] = nil
      end

      if state.registered and #state.entries == 0 then
        NS.RemoveMessageEventFilter(event, state.dispatcher)
        self._messageFilterState[event] = nil
      end
    end

    byEvent[event] = nil
  end

  self._moduleFilters[owner] = nil
end

local function SafeModuleCall(self, name, method, ...)
  local m = self.modules[name]
  if not m then return false end
  if type(m[method]) ~= "function" then return true end

  local ok, res = NS.SafeCall("RothChat:" .. name .. ":" .. method, m[method], m, self, ...)
  if not ok then
    local st = self.moduleState[name]
    if st then
      st.err = res
    end
  end
  return ok, res
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

  st.ok = false
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
    st.ok = st.initOK
    if not st.initOK then
      return false
    end
  elseif not st.initOK then
    return false
  end

  -- Owner-aware registrations are rebuilt for every activation. This prevents
  -- stale callbacks from surviving an incomplete module-specific OnDisable.
  CleanupModuleRegistrations(self, module)
  st.err = nil
  st.ok = true

  local ok = SafeModuleCall(self, name, "OnEnable")
  if not ok then
    st.ok = false
    st.active = false
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

  if st.active then
    SafeModuleCall(self, name, "OnDisable")
  end

  st.active = false
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
-- Combat-safe deferred execution
-- -----------------------------------------------------------------------------

function RothChat:Defer(fn, ...)
  if type(fn) ~= "function" then return end
  self._deferred[#self._deferred + 1] = { fn = fn, args = PackValues(...) }
end

function RothChat:RunDeferred()
  if InCombatLockdown() then return end
  if #self._deferred == 0 then return end

  local q = self._deferred
  self._deferred = {}
  for _, job in ipairs(q) do
    NS.SafeCall("RothChat:Deferred", job.fn, UnpackValues(job.args))
  end
end

-- -----------------------------------------------------------------------------
-- Unified AddMessage dispatcher
-- One hooksecurefunc per chatFrame instead of N separate hooks per module.
-- Modules register via core:RegisterAddMessageHook(callback, owner, priority).
-- Lower priority = called first.
-- -----------------------------------------------------------------------------

RothChat._addMsgCallbacks = {} -- sorted list: { {fn, owner, priority}, ... }
RothChat._addMsgHooked = {}   -- [chatFrame] = true

local function DispatchAddMessage(chatFrame, text, r, g, b, ...)
  if NS.CanAccessValue then
    if not NS.CanAccessValue(text) then return end
  elseif NS.IsSecretValue(text) then
    return
  end

  local cbs = RothChat._addMsgCallbacks
  for i = 1, #cbs do
    local entry = cbs[i]
    if entry and entry[1] then
      NS.SafeCall("AddMsgHook", entry[1], chatFrame, text, r, g, b, ...)
    end
  end
end

local function EnsureAddMsgHook(chatFrame)
  if not chatFrame or RothChat._addMsgHooked[chatFrame] then return end
  if type(chatFrame.AddMessage) ~= "function" then return end
  RothChat._addMsgHooked[chatFrame] = true
  hooksecurefunc(chatFrame, "AddMessage", DispatchAddMessage)
end

function RothChat:RegisterAddMessageHook(callback, owner, priority)
  if type(callback) ~= "function" then return end
  priority = tonumber(priority) or 50

  -- Deduplicate: same callback + owner = skip
  for i = 1, #self._addMsgCallbacks do
    local e = self._addMsgCallbacks[i]
    if e[1] == callback and e[2] == owner then return end
  end

  InsertSortedByPriority(self._addMsgCallbacks, { callback, owner, priority })

  -- Ensure all known chat frames are hooked
  for _, cf in ipairs(NS.GetChatFrames()) do
    EnsureAddMsgHook(cf)
  end
end

function RothChat:UnregisterAddMessageHooks(owner)
  if not owner then return end
  local cbs = self._addMsgCallbacks
  for i = #cbs, 1, -1 do
    if cbs[i][2] == owner then
      table.remove(cbs, i)
    end
  end
end

-- Hook new chat frames created after initial registration.
function RothChat:EnsureAddMsgHookForFrame(chatFrame)
  EnsureAddMsgHook(chatFrame)
end

-- -----------------------------------------------------------------------------
-- Shared chat lifecycle router
-- Consolidates overlapping FCF_* hooks and re-emits them through the core bus.
-- -----------------------------------------------------------------------------

local function ResetChatLifecycleQueue(queue)
  queue.queued = false
  queue.refreshAll = false
  queue.layoutReason = nil
  queue.frameReasons = {}
  queue.closedFrames = {}
end

function RothChat:QueueChatLifecycleRefresh(chatFrame, reason)
  local queue = self._chatLifecycleQueue
  reason = reason or "layout"

  if chatFrame then
    queue.frameReasons[chatFrame] = reason
  else
    queue.refreshAll = true
  end

  queue.layoutReason = queue.layoutReason or reason
  if queue.queued then
    return
  end

  queue.queued = true
  NS.RunNextFrame(self._chatLifecycleScheduleKey, function()
    local current = self._chatLifecycleQueue
    if not current.queued then
      return
    end

    local refreshAll = current.refreshAll
    local layoutReason = current.layoutReason or "layout"
    local frameReasons = current.frameReasons
    local closedFrames = current.closedFrames

    ResetChatLifecycleQueue(current)

    for closedFrame, closedReason in pairs(closedFrames) do
      self:Emit("CHAT_FRAME_CLOSED", closedFrame, closedReason)
    end

    self:Emit("CHAT_LAYOUT_CHANGED", layoutReason)

    if refreshAll then
      for _, cf in ipairs(NS.GetChatFrames()) do
        EnsureAddMsgHook(cf)
        self:Emit("CHAT_FRAME_READY", cf, frameReasons[cf] or layoutReason)
      end
    else
      for cf, frameReason in pairs(frameReasons) do
        EnsureAddMsgHook(cf)
        self:Emit("CHAT_FRAME_READY", cf, frameReason)
      end
    end
  end, "RothChat:ChatLifecycleRefresh")
end

function RothChat:QueueChatLifecycleClose(chatFrame, reason)
  if chatFrame then
    self._chatLifecycleQueue.closedFrames[chatFrame] = reason or "close"
  end
  self:QueueChatLifecycleRefresh(nil, reason or "close")
end

function RothChat:EnsureChatLifecycleHooks()
  if self._chatLifecycleHooked then
    return
  end
  self._chatLifecycleHooked = true

  local function QueueAll(reason)
    RothChat:QueueChatLifecycleRefresh(nil, reason)
  end

  local function QueueFrame(chatFrame, reason)
    if chatFrame then
      RothChat:QueueChatLifecycleRefresh(chatFrame, reason)
    else
      RothChat:QueueChatLifecycleRefresh(nil, reason)
    end
  end

  if type(_G.FCFDock_SelectWindow) == "function" then
    hooksecurefunc("FCFDock_SelectWindow", function(_, chatFrame)
      QueueFrame(chatFrame, "dock_select_window")
      QueueAll("dock_select_window")
    end)
  end

  if type(_G.FCF_SelectDockFrame) == "function" then
    hooksecurefunc("FCF_SelectDockFrame", function(chatFrame)
      QueueFrame(chatFrame, "select_dock_frame")
      QueueAll("select_dock_frame")
    end)
  end

  if type(_G.FCF_DockUpdate) == "function" then
    hooksecurefunc("FCF_DockUpdate", function()
      QueueAll("dock_update")
    end)
  end

  if type(_G.FCF_OpenTemporaryWindow) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
      QueueAll("open_temporary_window")
    end)
  end

  if type(_G.FCF_OpenNewWindow) == "function" then
    hooksecurefunc("FCF_OpenNewWindow", function()
      QueueAll("open_new_window")
    end)
  end

  if type(_G.FCF_SetTemporaryWindowType) == "function" then
    hooksecurefunc("FCF_SetTemporaryWindowType", function(chatFrame)
      QueueFrame(chatFrame, "set_temporary_window_type")
      QueueAll("set_temporary_window_type")
    end)
  end

  if type(_G.FCF_Close) == "function" then
    hooksecurefunc("FCF_Close", function(chatFrame)
      RothChat:QueueChatLifecycleClose(chatFrame, "close_window")
    end)
  end
end

-- -----------------------------------------------------------------------------
-- Lifecycle
-- -----------------------------------------------------------------------------

local function EnsureModuleFlagsInDB()
  -- Persist default module enabled flags into SavedVariables (only if absent).
  RothChat:ForEachModule(function(name, mod)
    local key = "module_" .. name .. "_enabled"
    if RothChat:Get(key) == nil then
      RothChat:Set(key, mod.defaultEnabled ~= false)
    end
  end)
end

function RothChat:OnAddonLoaded()
  InitDB()
  self._addonLoaded = true
  self._addonEnabled = self:Get("enabled") ~= false

  if not self._addonEnabled then
    self:Print("disabled in settings")
    return
  end

  EnsureModuleFlagsInDB()
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
    end
  elseif event == "PLAYER_LOGIN" then
    self:OnPlayerLogin()
  elseif event == "PLAYER_REGEN_ENABLED" then
    self:RunDeferred()
  end
end)

RothChat:RegisterEvent("ADDON_LOADED")
RothChat:RegisterEvent("PLAYER_LOGIN")
RothChat:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Slash command
SLASH_ROTHCHAT1 = "/rothchat"
SlashCmdList["ROTHCHAT"] = function(msg)
  if NS.IsSettingsOpenRestricted and NS.IsSettingsOpenRestricted() then
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
      RothChat:Print("Open Interface Options -> AddOns -> Roth Chat")
    end
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory("Roth Chat")
    InterfaceOptionsFrame_OpenToCategory("Roth Chat")
  else
    RothChat:Print("Open Interface Options -> AddOns -> Roth Chat")
  end
end
