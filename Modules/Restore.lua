-- RothChat - Restore (persistent scrollback per permanent chat window)
-- Also owns RothChat's fade/max-line changes while the module is active.
--
-- Database schema v3 binds each bucket to a permanent-window configuration
-- fingerprint. Entry schema v2 keeps timestamp metadata separate from durable
-- text so replay/export can apply the current timestamp policy exactly once.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local DB_VERSION = 3
local ENTRY_VERSION = 2

local M = {
  name = "Restore",
  description = "Persistent per-chat scrollback restore (SavedVariables).",
  defaultEnabled = true,
}

RothChat:RegisterModule(M)

local frameSnapshots = setmetatable({}, { __mode = "k" })
local replayedFrames = setmetatable({}, { __mode = "k" })
local frameFingerprintCache = setmetatable({}, { __mode = "k" })
local lifecycleListenersRegistered = false
local DEFERRED_APPLY_KEY = {}

local function ClampInt(value, minValue, maxValue, defaultValue)
  value = tonumber(value)
  if not value then return defaultValue end
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return math.floor(value)
end

local function GetMaxPerChat(core)
  if core:Get("restoreEnabled") == false then return 0 end
  return ClampInt(core:Get("restoreMaxLinesPerChat"), 100, 5000, 1200)
end

local function IsChatRestricted()
  return NS.IsChatMessagingRestricted()
end

local function IsAccessibleTable(value)
  return NS.CanAccessValue(value) and type(value) == "table" and NS.CanAccessObject(value)
end

local function GetPermanentSlotCount()
  return ClampInt(NS.SafeNumber(NS.GetMaxPermanentChatWindows(), 10), 0, 50, 10)
end

local function BuildLegacySnapshot(restore, previousVersion, oldFrames)
  if not IsAccessibleTable(oldFrames) then return end

  local oldSnapshot = restore.legacyFrames
  local oldSnapshotFrames
  if IsAccessibleTable(oldSnapshot) and IsAccessibleTable(oldSnapshot.frames) then
    oldSnapshotFrames = oldSnapshot.frames
  end

  -- The old buckets are unbound to a permanent-window configuration. Preserve
  -- their references for manual recovery, but never replay or append to them.
  -- Iterating only valid permanent slots bounds the snapshot without scanning
  -- any row contents or duplicating their data.
  local snapshotFrames = {}
  local hasEntries = false
  for index = 1, GetPermanentSlotCount() do
    local bucket = oldSnapshotFrames and oldSnapshotFrames[index]
    if not IsAccessibleTable(bucket) then bucket = oldFrames[index] end
    if IsAccessibleTable(bucket) then
      snapshotFrames[index] = bucket
      hasEntries = true
    end
  end

  if hasEntries then
    restore.legacyFrames = {
      version = previousVersion,
      frames = snapshotFrames,
    }
  end
end

local function EnsureDB(core)
  local db = core.db
  if not NS.CanAccessObject(db) then return nil end

  local restore = db.restore
  if not NS.CanAccessValue(restore) then return nil end
  if type(restore) == "table" then
    if not IsAccessibleTable(restore) then return nil end
  else
    restore = { version = DB_VERSION, frames = {} }
    db.restore = restore
  end

  local storedVersion = restore.version
  if not NS.CanAccessValue(storedVersion) then return nil end
  local previousVersion = 1
  if storedVersion ~= nil then
    previousVersion = NS.SafeNumber(storedVersion)
    if not previousVersion or previousVersion < 1 or previousVersion ~= math.floor(previousVersion)
      or previousVersion > DB_VERSION
    then
      return nil
    end
  end

  local frames = restore.frames
  if not NS.CanAccessValue(frames) then return nil end
  if type(frames) == "table" then
    if not IsAccessibleTable(frames) then return nil end
  else
    frames = {}
    restore.frames = frames
  end

  if previousVersion < DB_VERSION then
    -- Pre-v3 buckets were keyed only by ChatFrameN. Their original window
    -- owners cannot be proven, so keep bounded references in a non-replayable
    -- recovery snapshot and start live v3 buckets empty.
    BuildLegacySnapshot(restore, previousVersion, restore.frames)
    restore.frames = {}
  end

  restore.version = DB_VERSION
  return restore
end

local function GetTimeNow()
  if type(_G.time) == "function" then
    local ok, value = pcall(_G.time)
    if ok and type(value) == "number" then return value end
  end
  if type(_G.GetServerTime) == "function" then
    local ok, value = pcall(_G.GetServerTime)
    if ok and type(value) == "number" then return value end
  end
  return 0
end

local function IsPersistentChatFrame(chatFrame)
  if not NS.CanAccessObject(chatFrame) then return false end
  local isTemporary = chatFrame.isTemporary
  if not NS.CanAccessValue(isTemporary) then return false end
  if isTemporary then return false end

  local index = NS.GetChatFrameIndex(chatFrame)
  if not NS.CanAccessValue(index) then return false end
  if type(index) ~= "number" or index < 1 then return false end

  local maxWindows = NS.GetMaxPermanentChatWindows()
  if not NS.CanAccessValue(maxWindows) then return false end
  return index <= maxWindows
end

local function ReadAccessible(value)
  if not NS.CanAccessValue(value) then return "" end
  if type(value) == "string" then return value end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  return ""
end

local function EncodePart(value)
  value = ReadAccessible(value)
  return tostring(#value) .. ":" .. value
end

local function IsOrdinaryStringList(list)
  if not IsAccessibleTable(list) then return false end
  for key, value in pairs(list) do
    local index = NS.SafeNumber(key)
    if not index or index < 1 or index ~= math.floor(index)
      or not NS.CanAccessValue(value) or type(value) ~= "string"
    then
      return false
    end
  end
  return true
end

local function CollectSortedList(list)
  local values = {}
  for _, value in pairs(list) do
    values[#values + 1] = value
  end
  table.sort(values)
  return values
end

local function EncodeList(values)
  local out = {}
  for i = 1, #values do out[i] = EncodePart(values[i]) end
  return table.concat(out, ",")
end

local function GetFrameFingerprint(chatFrame)
  if IsChatRestricted() or not IsPersistentChatFrame(chatFrame) then return nil end

  local frameName = chatFrame.name
  local groups = chatFrame.messageTypeList
  local channels = chatFrame.channelList
  if not NS.CanAccessValue(frameName) or type(frameName) ~= "string"
    or not IsOrdinaryStringList(groups) or not IsOrdinaryStringList(channels)
  then
    frameFingerprintCache[chatFrame] = nil
    return nil
  end

  local core = M.core
  local revision = NS.SafeNumber(core:GetChatLayoutRevision(chatFrame))
  if revision ~= nil then
    local cached = frameFingerprintCache[chatFrame]
    if IsAccessibleTable(cached) then
      local cachedRevision = cached.revision
      local cachedFingerprint = cached.fingerprint
      if NS.CanAccessValue(cachedRevision)
        and type(cachedRevision) == "number"
        and cachedRevision == revision
        and NS.CanAccessValue(cachedFingerprint)
        and type(cachedFingerprint) == "string"
      then
        return cachedFingerprint
      end
    end
  else
    -- An unavailable revision cannot authorize a cache hit.
    frameFingerprintCache[chatFrame] = nil
  end

  local index = NS.GetChatFrameIndex(chatFrame)
  if not NS.CanAccessValue(index) then return nil end
  local fingerprint = table.concat({
    "window-v1",
    EncodePart(index),
    EncodePart(frameName),
    EncodePart(EncodeList(CollectSortedList(groups))),
    EncodePart(EncodeList(CollectSortedList(channels))),
  }, "|")
  if revision ~= nil and not IsChatRestricted() then
    frameFingerprintCache[chatFrame] = {
      revision = revision,
      fingerprint = fingerprint,
    }
  end
  return fingerprint
end

local function GetMatchingBucket(restoreDB, chatFrame, create)
  if IsChatRestricted() then return nil end
  if not IsAccessibleTable(restoreDB) then return nil end
  local frames = restoreDB.frames
  if not IsAccessibleTable(frames) then return nil end
  if not IsPersistentChatFrame(chatFrame) then return nil end
  local index = NS.GetChatFrameIndex(chatFrame)
  local fingerprint = GetFrameFingerprint(chatFrame)
  if not index or not fingerprint then return nil end

  local bucket = frames[index]
  if bucket ~= nil then
    if not IsAccessibleTable(bucket) then return nil end
    local previousFingerprint = bucket.fingerprint
    if not NS.CanAccessValue(previousFingerprint) then return nil end
    if previousFingerprint ~= fingerprint then
      frames[index] = nil
      bucket = nil
    end
  end

  if type(bucket) ~= "table" and create then
    bucket = { fingerprint = fingerprint, entries = {} }
    frames[index] = bucket
  end

  if type(bucket) == "table" then
    bucket.fingerprint = fingerprint
    local entries = bucket.entries
    if entries ~= nil and not IsAccessibleTable(entries) then return nil end
    if not IsAccessibleTable(entries) then bucket.entries = {} end
  end
  return bucket, index
end

local function PruneWithSlack(entries, maxLines)
  local count = #entries
  local slack = 50
  if count <= (maxLines + slack) then return end

  local extra = count - maxLines
  for index = 1, count - extra do
    entries[index] = entries[index + extra]
  end
  for index = count - extra + 1, count do entries[index] = nil end
end

local function IsAccessibleEntry(entry)
  return IsAccessibleTable(entry)
end

local function ReadEntryValue(entry, index)
  local value = entry[index]
  if not NS.CanAccessValue(value) then return nil, false end
  return value, true
end

local function GetEntryBaseText(entry)
  if not IsAccessibleEntry(entry) then return "", nil end
  local storedText, textAccessible = ReadEntryValue(entry, 2)
  if not textAccessible then return "", nil end
  local text = NS.SanitizeDurableChatText(storedText)
  if text == "" then return "" end

  local version, versionAccessible = ReadEntryValue(entry, 6)
  if not versionAccessible then return "", nil end
  local timestamp, timestampAccessible = ReadEntryValue(entry, 1)
  if not timestampAccessible then return "", nil end
  if type(timestamp) ~= "number" then timestamp = nil end

  if version ~= ENTRY_VERSION then
    text = NS.StripDisplayTimestampPrefix(text, timestamp, true)
  end
  return text, timestamp
end

local function BuildExport(entries, maxLines, includeTimestamps)
  if not IsAccessibleTable(entries) then return "" end
  local count = #entries
  if count <= 0 then return "" end

  maxLines = ClampInt(maxLines, 1, 10000, 500)
  local first = math.max(1, count - maxLines + 1)
  local out = {}

  for index = first, count do
    local entry = entries[index]
    local text, timestamp = GetEntryBaseText(entry)
    if text ~= "" then
      if includeTimestamps and timestamp then
        text = NS.FormatChatTimestamp(timestamp, false, nil, "%H:%M:%S") .. text
      end
      out[#out + 1] = text
    end
  end

  return table.concat(out, "\n")
end

local function BuildReplayText(core, entry)
  local text, timestamp = GetEntryBaseText(entry)
  if text == "" then return "" end

  if not timestamp then return text end

  if NS.HasNativeChatTimestamps() then
    local prefix = NS.FormatNativeChatTimestamp(timestamp)
    if prefix ~= "" then return prefix .. text end
  end

  if core:IsModuleActive("Timestamps") then
    return NS.FormatChatTimestamp(timestamp, true, core:Get("timestampColor")) .. text
  end
  return text
end

local function GetEntryColor(entry, index)
  if not IsAccessibleEntry(entry) then return nil end
  local value, accessible = ReadEntryValue(entry, index)
  if not accessible or type(value) ~= "number" then return nil end
  return value
end

local function ReadOptionalFrameValue(chatFrame, methodName)
  local method = chatFrame and chatFrame[methodName]
  if type(method) ~= "function" then return nil end
  local ok, value = pcall(method, chatFrame)
  if ok then return value end
  return nil
end

local function SnapshotFrameSettings(chatFrame)
  if not chatFrame or frameSnapshots[chatFrame] then return end
  frameSnapshots[chatFrame] = {
    fading = ReadOptionalFrameValue(chatFrame, "GetFading"),
    timeVisible = ReadOptionalFrameValue(chatFrame, "GetTimeVisible"),
    fadeDuration = ReadOptionalFrameValue(chatFrame, "GetFadeDuration"),
    maxLines = ReadOptionalFrameValue(chatFrame, "GetMaxLines"),
  }
end

local function ApplyFrameSettings(chatFrame, maxLines)
  if not chatFrame then return end
  SnapshotFrameSettings(chatFrame)

  if chatFrame.SetFading then chatFrame:SetFading(true) end
  if chatFrame.SetTimeVisible then chatFrame:SetTimeVisible(12) end
  if chatFrame.SetFadeDuration then chatFrame:SetFadeDuration(3) end
  if IsPersistentChatFrame(chatFrame) and maxLines > 0 and chatFrame.SetMaxLines then
    chatFrame:SetMaxLines(maxLines)
  end
end

local function RestoreFrameSettings(chatFrame)
  local snapshot = chatFrame and frameSnapshots[chatFrame]
  if not snapshot then return end

  if snapshot.fading ~= nil and chatFrame.SetFading then chatFrame:SetFading(snapshot.fading) end
  if snapshot.timeVisible ~= nil and chatFrame.SetTimeVisible then chatFrame:SetTimeVisible(snapshot.timeVisible) end
  if snapshot.fadeDuration ~= nil and chatFrame.SetFadeDuration then chatFrame:SetFadeDuration(snapshot.fadeDuration) end
  if snapshot.maxLines ~= nil and chatFrame.SetMaxLines then chatFrame:SetMaxLines(snapshot.maxLines) end

  frameSnapshots[chatFrame] = nil
end

local function SanitizeColor(value)
  if not NS.CanAccessValue(value) then return nil end
  if type(value) ~= "number" then return nil end
  return NS.Clamp(value, 0, 1)
end

local function OnAddMessage(frame, text, r, g, b)
  if not M.db or IsChatRestricted() then return end
  if not M.active or M._restoring or frame.__rothRestoring then return end
  if not M.core or not M.core:IsModuleActive("Restore") then return end
  if not IsPersistentChatFrame(frame) then return end

  local maxLines = GetMaxPerChat(M.core)
  if maxLines <= 0 then return end
  if not NS.CanAccessValue(text) then return end
  if type(text) ~= "string" then text = NS.SafeToString(text) end
  if text == "" then return end

  local now = GetTimeNow()
  local durableText = NS.SanitizeDurableChatText(NS.SafeTrunc(text, 4000))
  local baseText = NS.StripDisplayTimestampPrefix(durableText, now, false)
  if baseText == "" then return end

  local bucket = GetMatchingBucket(M.db, frame, true)
  if not bucket then return end

  local entries = bucket.entries
  if not IsAccessibleTable(entries) then return end
  local safeR, safeG, safeB = SanitizeColor(r), SanitizeColor(g), SanitizeColor(b)
  entries[#entries + 1] = {
    now,
    baseText,
    safeR,
    safeG,
    safeB,
    ENTRY_VERSION,
  }
  PruneWithSlack(entries, maxLines)

  M.core:Emit("CHAT_FEED", frame, durableText, safeR, safeG, safeB, now)
end

local function GetFrameMessageCount(chatFrame)
  if not NS.CanAccessObject(chatFrame) or type(chatFrame.GetNumMessages) ~= "function" then return nil end
  local ok, count = pcall(chatFrame.GetNumMessages, chatFrame)
  if not ok or not NS.CanAccessValue(count) then return nil end
  return NS.SafeNumber(count)
end

local function RestoreChatFrame(self, chatFrame, maxLines)
  if not self.db or IsChatRestricted() or replayedFrames[chatFrame] then return end
  if not IsPersistentChatFrame(chatFrame) or not NS.IsActiveChatFrame(chatFrame) then return end

  local bucket, index = GetMatchingBucket(self.db, chatFrame, false)
  if not bucket or not IsAccessibleTable(bucket.entries) or #bucket.entries <= 0 then
    replayedFrames[chatFrame] = true
    return
  end

  -- Blizzard or another addon may already have populated the ScrollingMessageFrame.
  -- AddMessage appends; replaying here would duplicate or place old rows after
  -- current rows, so an already non-empty frame is the authoritative owner.
  local existingMessageCount = GetFrameMessageCount(chatFrame)
  if not existingMessageCount or existingMessageCount > 0 then
    replayedFrames[chatFrame] = true
    return
  end

  local entries = bucket.entries
  if not IsAccessibleTable(entries) then return end
  local first = math.max(1, #entries - maxLines + 1)
  self._restoring = true
  chatFrame.__rothRestoring = true

  NS.SafeCall("RothChat:Restore:" .. tostring(index), function()
    for entryIndex = first, #entries do
      local entry = entries[entryIndex]
      local message = BuildReplayText(self.core, entry)
      if message ~= "" then
        local r = GetEntryColor(entry, 3) or 1
        local g = GetEntryColor(entry, 4) or 1
        local b = GetEntryColor(entry, 5) or 1
        chatFrame:AddMessage(message, r, g, b)
      end
    end
    if chatFrame.ScrollToBottom then chatFrame:ScrollToBottom() end
  end)

  chatFrame.__rothRestoring = nil
  self._restoring = false
  replayedFrames[chatFrame] = true
end

local function ApplyAllActive(core)
  local maxLines = GetMaxPerChat(core)
  for _, chatFrame in ipairs(NS.GetActiveChatFrames()) do
    ApplyFrameSettings(chatFrame, maxLines)
    if IsPersistentChatFrame(chatFrame) then
      GetMatchingBucket(M.db, chatFrame, false)
    end
  end
end

local function ReplayAllActive(core)
  if not M.db then return end
  local maxLines = GetMaxPerChat(core)
  if maxLines <= 0 then return end
  for _, chatFrame in ipairs(NS.GetActiveChatFrames()) do
    RestoreChatFrame(M, chatFrame, maxLines)
  end
end

local function ApplyDeferred()
  local core = M.core
  if core and core:IsModuleActive("Restore") then ApplyAllActive(core) end
end

local function RegisterLifecycleListeners(core)
  if lifecycleListenersRegistered then return end
  lifecycleListenersRegistered = true

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if not core2:IsModuleActive("Restore") or not chatFrame then return end
    ApplyFrameSettings(chatFrame, GetMaxPerChat(core2))
    if IsPersistentChatFrame(chatFrame) then
      GetMatchingBucket(M.db, chatFrame, false)
    end
  end, M)

  core:On("CHAT_FRAME_CLOSED", function(_, core2, chatFrame)
    if not chatFrame then return end
    frameFingerprintCache[chatFrame] = nil
    RestoreFrameSettings(chatFrame)
    replayedFrames[chatFrame] = nil

    if M.db and IsPersistentChatFrame(chatFrame) then
      local index = NS.GetChatFrameIndex(chatFrame)
      if index then M.db.frames[index] = nil end
    end
  end, M)

  core:On("CHAT_RESTRICTION_CHANGED", function(_, _, restricted)
    if restricted then
      -- Cancel a login replay already queued for the next frame. It is dropped
      -- permanently instead of waiting for chat access to return.
      NS.CancelScheduled(M._replayScheduleKey)
    end
  end, M)
end

function M:Init(core)
  self.core = core
  self.db = EnsureDB(core)
  self._restoring = false
  self._replayScheduleKey = self._replayScheduleKey or {}
  self.active = false

  core.GetRestoreText = function(_, chatFrame, maxLines, includeTimestamps)
    if not self.db or not self.active or not core:IsModuleActive("Restore") then return "" end
    if core:Get("restoreEnabled") == false then return "" end
    if IsChatRestricted() then return "" end

    local bucket = GetMatchingBucket(self.db, chatFrame, false)
    if not bucket then return "" end
    return BuildExport(bucket.entries, maxLines, includeTimestamps)
  end

  return true
end

function M:OnEnable(core)
  self.active = true
  lifecycleListenersRegistered = false

  core:RegisterAddMessageHook(OnAddMessage, self, 20)
  core:EnsureChatLifecycleHooks()
  RegisterLifecycleListeners(core)

  if InCombatLockdown() then
    core:DeferKeyed(DEFERRED_APPLY_KEY, ApplyDeferred)
  else
    ApplyAllActive(core)
  end
end

function M:OnLogin(core)
  NS.RunNextFrame(self._replayScheduleKey, function()
    -- A restriction transition invalidates this one-shot replay. It is dropped
    -- here rather than held for later when chat access returns.
    if not IsChatRestricted() and self.active and core:IsModuleActive("Restore") then
      ReplayAllActive(core)
    end
  end, "RothChat:RestoreLoginReplay")
end

function M:OnDisable(core)
  self.active = false
  core:CancelDeferred(DEFERRED_APPLY_KEY)
  self._restoring = false
  lifecycleListenersRegistered = false
  frameFingerprintCache = setmetatable({}, { __mode = "k" })
  core:UnregisterAddMessageHooks(self)
  NS.CancelScheduled(self._replayScheduleKey)

  for _, chatFrame in ipairs(NS.GetChatFrames()) do
    chatFrame.__rothRestoring = nil
    replayedFrames[chatFrame] = nil
    RestoreFrameSettings(chatFrame)
  end
end

function M:Refresh(core)
  if not core:IsModuleActive("Restore") then return end
  ApplyAllActive(core)
end
