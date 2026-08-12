-- RothChat - Restore (persistent scrollback per chat window)
-- Also handles fast fade-out of text.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local M = {
  name = "Restore",
  description = "Persistent per-chat scrollback restore (SavedVariables).",
  defaultEnabled = true,
}

RothChat:RegisterModule(M)

local function ClampInt(v, minv, maxv, def)
  v = tonumber(v)
  if not v then return def end
  if v < minv then return minv end
  if v > maxv then return maxv end
  return math.floor(v)
end

local function GetMaxPerChat(core)
  if core:Get("restoreEnabled") == false then return 0 end
  return ClampInt(core:Get("restoreMaxLinesPerChat"), 100, 5000, 1200)
end

local function EnsureDB(core)
  local db = core.db
  if type(db.restore) ~= "table" then db.restore = { version = 1, frames = {} } end
  if type(db.restore.frames) ~= "table" then db.restore.frames = {} end
  return db.restore
end

local function EnsureFrameBucket(restoreDB, idx)
  local frames = restoreDB.frames
  local bucket = frames[idx]
  if type(bucket) ~= "table" then
    bucket = { entries = {} }
    frames[idx] = bucket
  end
  if type(bucket.entries) ~= "table" then bucket.entries = {} end
  return bucket
end

local function PruneWithSlack(entries, maxLines)
  local n = #entries
  local slack = 50
  if n <= (maxLines + slack) then return end
  local extra = n - maxLines
  for i = 1, (n - extra) do entries[i] = entries[i + extra] end
  for i = (n - extra + 1), n do entries[i] = nil end
end

local function GetTimeNow() return (GetServerTime and GetServerTime()) or time() end

local function FormatTS(t)
  local ok, s = pcall(date, "%H:%M:%S", t)
  if ok and type(s) == "string" then return s end
  return "--:--:--"
end

local function BuildExport(entries, maxLines, includeTimestamps)
  local n = #entries
  if n <= 0 then return "" end
  maxLines = ClampInt(maxLines, 1, 10000, 500)
  local start = math.max(1, n - maxLines + 1)
  local out = {}
  for i = start, n do
    local e = entries[i]
    if type(e) == "table" then
      local t = e[1]
      local msg = e[2]
      if type(msg) == "string" and msg ~= "" then
        if includeTimestamps and type(t) == "number" then
          out[#out + 1] = string.format("[%s] %s", FormatTS(t), msg)
        else
          out[#out + 1] = msg
        end
      end
    end
  end
  return table.concat(out, "\n")
end

function M:Init(core)
  self.core = core
  self.db = EnsureDB(core)
  self._restoring = false
  self.active = false

  core.GetRestoreText = function(_, chatFrame, maxLines, includeTimestamps)
    if not chatFrame then return "" end
    local idx = (NS.GetChatFrameIndex and NS.GetChatFrameIndex(chatFrame)) or (chatFrame.GetID and chatFrame:GetID())
    if not idx then return "" end
    local bucket = self.db.frames[idx]
    if type(bucket) ~= "table" or type(bucket.entries) ~= "table" then return "" end
    return BuildExport(bucket.entries, maxLines, includeTimestamps)
  end

  return true
end

local function ApplyFadeSettings(cf)
  -- Text stays visible for 12s, then fades over 3s (total ~15s).
  if cf.SetFading then cf:SetFading(true) end
  cf:SetTimeVisible(12)
  cf:SetFadeDuration(3)
end

-- Unified AddMessage hook callback (registered via core:RegisterAddMessageHook).
local function OnAddMessage(frame, text, r, g, b)
  if not M.active then return end
  if M._restoring or frame.__rothRestoring then return end
  if not M.core or not M.core:IsModuleEnabled("Restore") then return end

  local maxLines = GetMaxPerChat(M.core)
  if maxLines <= 0 then return end

  -- Secret/type checks already done by dispatcher, but double-check text type
  if type(text) ~= "string" then text = NS.SafeToString(text) end
  if text == "" then return end
  text = NS.SafeTrunc(text, 4000)

  local idx = NS.GetChatFrameIndex(frame)
  if not idx then return end

  local bucket = EnsureFrameBucket(M.db, idx)
  local entries = bucket.entries
  local now = GetTimeNow()
  entries[#entries + 1] = { now, text, r, g, b }
  PruneWithSlack(entries, maxLines)

  M.core:Emit("CHAT_FEED", frame, text, r, g, b, now)
end

function M:OnEnable(core)
  self.active = true

  -- Register with unified dispatcher (priority 20 = early, save before other hooks)
  core:RegisterAddMessageHook(OnAddMessage, self, 20)

  if InCombatLockdown() then
    core:Defer(function()
      for _, cf in ipairs(NS.GetChatFrames()) do
        ApplyFadeSettings(cf)
      end
    end)
  else
    for _, cf in ipairs(NS.GetChatFrames()) do
      ApplyFadeSettings(cf)
    end
  end
end

local function RestoreChatFrame(self, cf, idx, maxLines)
  local bucket = self.db.frames[idx]
  if type(bucket) ~= "table" or type(bucket.entries) ~= "table" then return end
  local entries = bucket.entries
  local n = #entries
  if n <= 0 then return end
  local start = math.max(1, n - maxLines + 1)

  self._restoring = true
  cf.__rothRestoring = true
  for i = start, n do
    local e = entries[i]
    if type(e) == "table" then
      local msg = e[2]
      if type(msg) == "string" and msg ~= "" then
        cf:AddMessage(msg, e[3], e[4], e[5])
      end
    end
  end
  if cf.ScrollToBottom then cf:ScrollToBottom() end
  cf.__rothRestoring = nil
  self._restoring = false
end

function M:OnLogin(core)
  if InCombatLockdown() then core:Defer(function() M:OnLogin(core) end) return end
  local maxLines = GetMaxPerChat(core)
  if maxLines <= 0 then return end
  if not NUM_CHAT_WINDOWS then return end
  for i = 1, NUM_CHAT_WINDOWS do
    local cf = _G["ChatFrame" .. i]
    if cf then RestoreChatFrame(self, cf, i, maxLines) end
  end
end

function M:OnDisable(core)
  self.active = false
  core:UnregisterAddMessageHooks(self)
end
