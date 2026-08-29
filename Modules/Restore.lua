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

local function EnsureDB(core)
  local db = core.db
  if type(db.restore) ~= "table" then
    db.restore = { version = DB_VERSION, frames = {} }
  end
  if type(db.restore.frames) ~= "table" then db.restore.frames = {} end

  local previousVersion = tonumber(db.restore.version) or 1
  if previousVersion < DB_VERSION then
    -- Pre-v3 buckets were keyed only by ChatFrameN. Blizzard reuses a closed
    -- permanent slot for a newly configured window, so the old owner cannot be
    -- proven. Drop bucket references without walking every retained row.
    for index, bucket in pairs(db.restore.frames) do
      if type(index) ~= "number"
        or type(bucket) ~= "table"
        or type(bucket.fingerprint) ~= "string"
      then
        db.restore.frames[index] = nil
      end
    end
  end

  db.restore.version = DB_VERSION
  return db.restore
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
  if not chatFrame or chatFrame.isTemporary then return false end
  local index = NS.GetChatFrameIndex and NS.GetChatFrameIndex(chatFrame)
  if type(index) ~= "number" or index < 1 then return false end
  return index <= (NS.GetMaxPermanentChatWindows and NS.GetMaxPermanentChatWindows() or index)
end

local function ReadAccessible(value)
  if NS.CanAccessValue and not NS.CanAccessValue(value) then return "" end
  if type(value) == "string" then return value end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  return ""
end

local function EncodePart(value)
  value = ReadAccessible(value)
  return tostring(#value) .. ":" .. value
end

local function GetWindowName(chatFrame, index)
  if type(_G.FCF_GetChatWindowInfo) == "function" then
    local ok, name = pcall(_G.FCF_GetChatWindowInfo, index)
    if ok and ReadAccessible(name) ~= "" then return ReadAccessible(name) end
  end

  local name = chatFrame and chatFrame.name
  if ReadAccessible(name) ~= "" then return ReadAccessible(name) end
  if chatFrame and type(chatFrame.GetName) == "function" then
    local ok, frameName = pcall(chatFrame.GetName, chatFrame)
    if ok then return ReadAccessible(frameName) end
  end
  return ""
end

local function CollectSortedList(list)
  local values = {}
  if type(list) == "table" then
    for _, value in pairs(list) do
      local ordinary = ReadAccessible(value)
      if ordinary ~= "" then values[#values + 1] = ordinary end
    end
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
  if not IsPersistentChatFrame(chatFrame) then return nil end
  local index = NS.GetChatFrameIndex(chatFrame)
  local groups = CollectSortedList(chatFrame.messageTypeList)
  local channels = CollectSortedList(chatFrame.channelList)

  return table.concat({
    "window-v1",
    EncodePart(index),
    EncodePart(GetWindowName(chatFrame, index)),
    EncodePart(EncodeList(groups)),
    EncodePart(EncodeList(channels)),
  }, "|")
end

local function GetMatchingBucket(restoreDB, chatFrame, create)
  if not IsPersistentChatFrame(chatFrame) then return nil end
  local index = NS.GetChatFrameIndex(chatFrame)
  local fingerprint = GetFrameFingerprint(chatFrame)
  if not index or not fingerprint then return nil end

  local bucket = restoreDB.frames[index]
  if type(bucket) == "table" and bucket.fingerprint ~= fingerprint then
    restoreDB.frames[index] = nil
    bucket = nil
  end

  if type(bucket) ~= "table" and create then
    bucket = { fingerprint = fingerprint, entries = {} }
    restoreDB.frames[index] = bucket
  end

  if type(bucket) == "table" then
    bucket.fingerprint = fingerprint
    if type(bucket.entries) ~= "table" then bucket.entries = {} end
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

local function GetEntryBaseText(entry)
  if type(entry) ~= "table" then return "" end
  local text = NS.SanitizeDurableChatText(entry[2])
  if text == "" then return "" end

  if entry[6] ~= ENTRY_VERSION then
    local timestamp = type(entry[1]) == "number" and entry[1] or nil
    text = NS.StripDisplayTimestampPrefix(text, timestamp, true)
  end
  return text
end

local function BuildExport(entries, maxLines, includeTimestamps)
  local count = #entries
  if count <= 0 then return "" end

  maxLines = ClampInt(maxLines, 1, 10000, 500)
  local first = math.max(1, count - maxLines + 1)
  local out = {}

  for index = first, count do
    local entry = entries[index]
    local text = GetEntryBaseText(entry)
    if text ~= "" then
      local timestamp = type(entry[1]) == "number" and entry[1] or nil
      if includeTimestamps and timestamp then
        text = NS.FormatChatTimestamp(timestamp, false, nil, "%H:%M:%S") .. text
      end
      out[#out + 1] = text
    end
  end

  return table.concat(out, "\n")
end

local function BuildReplayText(core, entry)
  local text = GetEntryBaseText(entry)
  if text == "" then return "" end

  local timestamp = type(entry[1]) == "number" and entry[1] or nil
  if not timestamp then return text end

  if NS.HasNativeChatTimestamps and NS.HasNativeChatTimestamps() then
    local prefix = NS.FormatNativeChatTimestamp(timestamp)
    if prefix ~= "" then return prefix .. text end
  end

  if core:IsModuleActive("Timestamps") then
    return NS.FormatChatTimestamp(timestamp, true, core:Get("timestampColor")) .. text
  end
  return text
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
  if NS.CanAccessValue and not NS.CanAccessValue(value) then return nil end
  if type(value) ~= "number" then return nil end
  return NS.Clamp(value, 0, 1)
end

local function OnAddMessage(frame, text, r, g, b)
  if not M.active or M._restoring or frame.__rothRestoring then return end
  if not M.core or not M.core:IsModuleActive("Restore") then return end
  if not IsPersistentChatFrame(frame) then return end

  local maxLines = GetMaxPerChat(M.core)
  if maxLines <= 0 then return end
  if NS.CanAccessValue and not NS.CanAccessValue(text) then return end
  if type(text) ~= "string" then text = NS.SafeToString(text) end
  if text == "" then return end

  local now = GetTimeNow()
  local durableText = NS.SanitizeDurableChatText(NS.SafeTrunc(text, 4000))
  local baseText = NS.StripDisplayTimestampPrefix(durableText, now, false)
  if baseText == "" then return end

  local bucket = GetMatchingBucket(M.db, frame, true)
  if not bucket then return end

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

  M.core:Emit("CHAT_FEED", frame, durableText, r, g, b, now)
end

local function GetFrameMessageCount(chatFrame)
  if not chatFrame or type(chatFrame.GetNumMessages) ~= "function" then return 0 end
  local ok, count = pcall(chatFrame.GetNumMessages, chatFrame)
  if not ok then return 0 end
  return tonumber(count) or 0
end

local function RestoreChatFrame(self, chatFrame, maxLines)
  if replayedFrames[chatFrame] then return end
  if not IsPersistentChatFrame(chatFrame) or not NS.IsActiveChatFrame(chatFrame) then return end

  local bucket, index = GetMatchingBucket(self.db, chatFrame, false)
  if not bucket or #bucket.entries <= 0 then
    replayedFrames[chatFrame] = true
    return
  end

  -- Blizzard or another addon may already have populated the ScrollingMessageFrame.
  -- AddMessage appends; replaying here would duplicate or place old rows after
  -- current rows, so an already non-empty frame is the authoritative owner.
  if GetFrameMessageCount(chatFrame) > 0 then
    replayedFrames[chatFrame] = true
    return
  end

  local entries = bucket.entries
  local first = math.max(1, #entries - maxLines + 1)
  self._restoring = true
  chatFrame.__rothRestoring = true

  NS.SafeCall("RothChat:Restore:" .. tostring(index), function()
    for entryIndex = first, #entries do
      local entry = entries[entryIndex]
      local message = BuildReplayText(self.core, entry)
      if message ~= "" then
        local r = type(entry[3]) == "number" and entry[3] or 1
        local g = type(entry[4]) == "number" and entry[4] or 1
        local b = type(entry[5]) == "number" and entry[5] or 1
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
  local maxLines = GetMaxPerChat(core)
  if maxLines <= 0 then return end
  for _, chatFrame in ipairs(NS.GetActiveChatFrames()) do
    RestoreChatFrame(M, chatFrame, maxLines)
  end
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
    RestoreFrameSettings(chatFrame)
    replayedFrames[chatFrame] = nil

    if IsPersistentChatFrame(chatFrame) then
      local index = NS.GetChatFrameIndex(chatFrame)
      if index then M.db.frames[index] = nil end
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
    if not self.active or not core:IsModuleActive("Restore") then return "" end
    if core:Get("restoreEnabled") == false then return "" end

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
    core:Defer(function()
      if core:IsModuleActive("Restore") then ApplyAllActive(core) end
    end)
  else
    ApplyAllActive(core)
  end
end

function M:OnLogin(core)
  NS.RunNextFrame(self._replayScheduleKey, function()
    if self.active and core:IsModuleActive("Restore") then ReplayAllActive(core) end
  end, "RothChat:RestoreLoginReplay")
end

function M:OnDisable(core)
  self.active = false
  self._restoring = false
  lifecycleListenersRegistered = false
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
