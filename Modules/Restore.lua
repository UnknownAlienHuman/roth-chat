-- RothChat - bounded durable scrollback for permanent chat windows.
--
-- Restore owns only addon persistence and replay. Blizzard keeps ownership of
-- ScrollingMessageFrame capacity, fading, visibility and live message routing.
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

local replayedFrames = setmetatable({}, { __mode = "k" })
local frameFingerprintCache = setmetatable({}, { __mode = "k" })
local lifecycleListenersRegistered = false

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

  -- Pre-v3 buckets are not bound to a window configuration. Keep bounded
  -- references for manual recovery, but never replay or append to them.
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
    BuildLegacySnapshot(restore, previousVersion, frames)
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
  if not NS.CanAccessValue(isTemporary) or isTemporary then return false end

  local index = NS.GetChatFrameIndex(chatFrame)
  if not NS.CanAccessValue(index) or type(index) ~= "number" or index < 1 then return false end

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
  for _, value in pairs(list) do values[#values + 1] = value end
  table.sort(values)
  return values
end

local function EncodeList(values)
  local out = {}
  for index = 1, #values do out[index] = EncodePart(values[index]) end
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

  local revision = NS.SafeNumber(M.core:GetChatLayoutRevision(chatFrame))
  if revision ~= nil then
    local cached = frameFingerprintCache[chatFrame]
    if IsAccessibleTable(cached)
      and NS.CanAccessValue(cached.revision) and cached.revision == revision
      and NS.CanAccessValue(cached.fingerprint) and type(cached.fingerprint) == "string"
    then
      return cached.fingerprint
    end
  else
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
    frameFingerprintCache[chatFrame] = { revision = revision, fingerprint = fingerprint }
  end
  return fingerprint
end

local function GetMatchingBucket(restoreDB, chatFrame, create)
  if IsChatRestricted() or not IsAccessibleTable(restoreDB) then return nil end
  local frames = restoreDB.frames
  if not IsAccessibleTable(frames) or not IsPersistentChatFrame(chatFrame) then return nil end

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
  if count <= maxLines + slack then return end

  local extra = count - maxLines
  for index = 1, count - extra do entries[index] = entries[index + extra] end
  for index = count - extra + 1, count do entries[index] = nil end
end

local function ReadEntryValue(entry, index)
  local value = entry[index]
  if not NS.CanAccessValue(value) then return nil, false end
  return value, true
end

local function GetEntryBaseText(entry)
  if not IsAccessibleTable(entry) then return "", nil end

  local storedText, textAccessible = ReadEntryValue(entry, 2)
  if not textAccessible then return "", nil end
  local text = NS.SanitizeDurableChatText(storedText)
  if text == "" then return "" end

  local version, versionAccessible = ReadEntryValue(entry, 6)
  if not versionAccessible then return "", nil end
  local timestamp, timestampAccessible = ReadEntryValue(entry, 1)
  if not timestampAccessible then return "", nil end
  if type(timestamp) ~= "number" then timestamp = nil end

  if version == nil or version == 1 then
    text = NS.StripDisplayTimestampPrefix(text, timestamp, true)
  elseif version ~= ENTRY_VERSION then
    -- A newer writer owns unknown row semantics. Do not guess or partially
    -- expose the row merely because the database container version is known.
    return "", nil
  end
  return text, timestamp
end

local function BuildExport(entries, maxLines, includeTimestamps)
  if not IsAccessibleTable(entries) or not NS.CanAccessValue(includeTimestamps) then return "" end
  local count = #entries
  if count <= 0 then return "" end

  maxLines = ClampInt(maxLines, 1, 10000, 500)
  local first = math.max(1, count - maxLines + 1)
  local out = {}
  for index = first, count do
    local text, timestamp = GetEntryBaseText(entries[index])
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
  if text == "" or not timestamp then return text end

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
  if not IsAccessibleTable(entry) then return nil end
  local value, accessible = ReadEntryValue(entry, index)
  if not accessible or type(value) ~= "number" then return nil end
  return value
end

local function ReadFrameNumber(chatFrame, methodName)
  local method = chatFrame and chatFrame[methodName]
  if type(method) ~= "function" then return nil end
  local ok, value = pcall(method, chatFrame)
  if not ok or not NS.CanAccessValue(value) then return nil end
  return NS.SafeNumber(value)
end

local function GetReplayLimit(chatFrame, retentionLimit)
  local frameCapacity = ReadFrameNumber(chatFrame, "GetMaxLines")
  if not frameCapacity or frameCapacity < 1 then return nil end
  return math.min(retentionLimit, math.floor(frameCapacity))
end

local function SanitizeColor(value)
  if not NS.CanAccessValue(value) or type(value) ~= "number" then return nil end
  return NS.Clamp(value, 0, 1)
end

local function OnAddMessage(frame, text, r, g, b)
  if not M.db or IsChatRestricted() or not M.active or M._restoring or frame.__rothRestoring then return end
  if not M.core or not M.core:IsModuleActive("Restore") or not IsPersistentChatFrame(frame) then return end

  local maxLines = GetMaxPerChat(M.core)
  if maxLines <= 0 or not NS.CanAccessValue(text) then return end
  if type(text) ~= "string" then text = NS.SafeToString(text) end
  if text == "" then return end

  local now = GetTimeNow()
  local durableText = NS.SanitizeDurableChatText(NS.SafeTrunc(text, 4000))
  local baseText = NS.StripDisplayTimestampPrefix(durableText, now, false)
  if baseText == "" then return end

  local bucket = GetMatchingBucket(M.db, frame, true)
  if not bucket or not IsAccessibleTable(bucket.entries) then return end
  local entries = bucket.entries
  entries[#entries + 1] = {
    now,
    baseText,
    SanitizeColor(r),
    SanitizeColor(g),
    SanitizeColor(b),
    ENTRY_VERSION,
  }
  PruneWithSlack(entries, maxLines)
end

local function GetFrameMessageCount(chatFrame)
  return ReadFrameNumber(chatFrame, "GetNumMessages")
end

local function RestoreChatFrame(self, chatFrame, retentionLimit)
  if not self.db or IsChatRestricted() or replayedFrames[chatFrame] then return end
  if not IsPersistentChatFrame(chatFrame) or not NS.IsActiveChatFrame(chatFrame) then return end

  local bucket, index = GetMatchingBucket(self.db, chatFrame, false)
  if not bucket or not IsAccessibleTable(bucket.entries) or #bucket.entries <= 0 then
    replayedFrames[chatFrame] = true
    return
  end

  -- AddMessage appends. Existing native content owns ordering and must not be
  -- mixed with an older persisted snapshot.
  local existingMessageCount = GetFrameMessageCount(chatFrame)
  if not existingMessageCount or existingMessageCount > 0 then
    replayedFrames[chatFrame] = true
    return
  end

  local replayLimit = GetReplayLimit(chatFrame, retentionLimit)
  if not replayLimit or replayLimit <= 0 then
    replayedFrames[chatFrame] = true
    return
  end

  local entries = bucket.entries
  local selected = {}
  for entryIndex = #entries, 1, -1 do
    local entry = entries[entryIndex]
    local message = BuildReplayText(self.core, entry)
    if message ~= "" then
      selected[#selected + 1] = {
        message,
        GetEntryColor(entry, 3) or 1,
        GetEntryColor(entry, 4) or 1,
        GetEntryColor(entry, 5) or 1,
      }
      if #selected >= replayLimit then break end
    end
  end

  self._restoring = true
  chatFrame.__rothRestoring = true

  NS.SafeCall("RothChat:Restore:" .. tostring(index), function()
    for selectedIndex = #selected, 1, -1 do
      local row = selected[selectedIndex]
      chatFrame:AddMessage(row[1], row[2], row[3], row[4])
    end
    if chatFrame.ScrollToBottom then chatFrame:ScrollToBottom() end
  end)

  chatFrame.__rothRestoring = nil
  self._restoring = false
  replayedFrames[chatFrame] = true
end

local function ReplayAllActive(core)
  if not M.db then return end
  local maxLines = GetMaxPerChat(core)
  if maxLines <= 0 then return end
  for _, chatFrame in ipairs(NS.GetActiveChatFrames()) do
    RestoreChatFrame(M, chatFrame, maxLines)
  end
end

local function RegisterLifecycleListeners(core)
  if lifecycleListenersRegistered then return end
  lifecycleListenersRegistered = true

  core:On("CHAT_FRAME_CLOSED", function(_, _, chatFrame)
    if not chatFrame then return end
    frameFingerprintCache[chatFrame] = nil
    replayedFrames[chatFrame] = nil

    if M.db and IsPersistentChatFrame(chatFrame) and IsAccessibleTable(M.db.frames) then
      local index = NS.GetChatFrameIndex(chatFrame)
      if index then M.db.frames[index] = nil end
    end
  end, M)

  core:On("CHAT_RESTRICTION_CHANGED", function(_, _, restricted)
    if restricted then NS.CancelScheduled(M._replayScheduleKey) end
  end, M)
end

function M:Init(core)
  self.core = core
  self.db = EnsureDB(core)
  self._restoring = false
  self._replayScheduleKey = self._replayScheduleKey or {}
  self.active = false

  core.GetRestoreText = function(_, chatFrame, maxLines, includeTimestamps)
    if not self.db or not self.active or not core:IsModuleActive("Restore")
      or core:Get("restoreEnabled") == false or IsChatRestricted()
    then
      return ""
    end

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
end

function M:OnLogin(core)
  NS.RunNextFrame(self._replayScheduleKey, function()
    if not IsChatRestricted() and self.active and core:IsModuleActive("Restore") then
      ReplayAllActive(core)
    end
  end, "RothChat:RestoreLoginReplay")
end

function M:OnDisable(core)
  self.active = false
  self._restoring = false
  lifecycleListenersRegistered = false
  frameFingerprintCache = setmetatable({}, { __mode = "k" })
  core:UnregisterAddMessageHooks(self)
  NS.CancelScheduled(self._replayScheduleKey)

  for _, chatFrame in ipairs(NS.GetChatFrames()) do
    chatFrame.__rothRestoring = nil
    replayedFrames[chatFrame] = nil
  end
end

RothChat:RegisterModule(M)
