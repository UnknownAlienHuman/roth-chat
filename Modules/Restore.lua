-- RothChat - Restore (persistent scrollback per permanent chat window)
-- Also owns RothChat's chat-text fade settings while the module is active.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local M = {
  name = "Restore",
  description = "Persistent per-chat scrollback restore (SavedVariables).",
  defaultEnabled = true,
}

RothChat:RegisterModule(M)

local fadeSnapshots = setmetatable({}, { __mode = "k" })
local lifecycleListenersRegistered = false

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

local function GetTimeNow()
  return (GetServerTime and GetServerTime()) or time()
end

local function FormatTS(t)
  local ok, s = pcall(date, "%H:%M:%S", t)
  if ok and type(s) == "string" then return s end
  return "--:--:--"
end

local function IsPersistentChatFrame(chatFrame)
  if not chatFrame or chatFrame.isTemporary then return false end
  local idx = NS.GetChatFrameIndex and NS.GetChatFrameIndex(chatFrame)
  return type(idx) == "number" and idx >= 1
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
    if not self.active or not core:IsModuleActive("Restore") then return "" end
    if core:Get("restoreEnabled") == false then return "" end
    if not IsPersistentChatFrame(chatFrame) then return "" end

    local idx = NS.GetChatFrameIndex(chatFrame)
    if not idx then return "" end
    local bucket = self.db.frames[idx]
    if type(bucket) ~= "table" or type(bucket.entries) ~= "table" then return "" end
    return BuildExport(bucket.entries, maxLines, includeTimestamps)
  end

  return true
end

local function SnapshotFadeSettings(cf)
  if not cf or fadeSnapshots[cf] then return end
  fadeSnapshots[cf] = {
    fading = cf.GetFading and cf:GetFading() or nil,
    timeVisible = cf.GetTimeVisible and cf:GetTimeVisible() or nil,
    fadeDuration = cf.GetFadeDuration and cf:GetFadeDuration() or nil,
  }
end

local function ApplyFadeSettings(cf)
  if not cf then return end
  SnapshotFadeSettings(cf)
  -- Text stays visible for 12s, then fades over 3s (total approximately 15s).
  if cf.SetFading then cf:SetFading(true) end
  if cf.SetTimeVisible then cf:SetTimeVisible(12) end
  if cf.SetFadeDuration then cf:SetFadeDuration(3) end
end

local function RestoreFadeSettings(cf)
  local snapshot = cf and fadeSnapshots[cf]
  if not snapshot then return end

  if snapshot.fading ~= nil and cf.SetFading then
    cf:SetFading(snapshot.fading)
  end
  if snapshot.timeVisible ~= nil and cf.SetTimeVisible then
    cf:SetTimeVisible(snapshot.timeVisible)
  end
  if snapshot.fadeDuration ~= nil and cf.SetFadeDuration then
    cf:SetFadeDuration(snapshot.fadeDuration)
  end

  fadeSnapshots[cf] = nil
end

local function SanitizeColor(value)
  if NS.CanAccessValue and not NS.CanAccessValue(value) then return nil end
  if type(value) ~= "number" then return nil end
  return NS.Clamp(value, 0, 1)
end

-- Unified AddMessage hook callback (registered via core:RegisterAddMessageHook).
local function OnAddMessage(frame, text, r, g, b)
  if not M.active then return end
  if M._restoring or frame.__rothRestoring then return end
  if not M.core or not M.core:IsModuleActive("Restore") then return end
  if not IsPersistentChatFrame(frame) then return end

  local maxLines = GetMaxPerChat(M.core)
  if maxLines <= 0 then return end

  if NS.CanAccessValue and not NS.CanAccessValue(text) then return end
  if type(text) ~= "string" then text = NS.SafeToString(text) end
  if text == "" then return end
  text = NS.SafeTrunc(text, 4000)

  local idx = NS.GetChatFrameIndex(frame)
  if not idx then return end

  local bucket = EnsureFrameBucket(M.db, idx)
  local entries = bucket.entries
  local now = GetTimeNow()
  entries[#entries + 1] = {
    now,
    text,
    SanitizeColor(r),
    SanitizeColor(g),
    SanitizeColor(b),
  }
  PruneWithSlack(entries, maxLines)

  M.core:Emit("CHAT_FEED", frame, text, r, g, b, now)
end

local function RegisterLifecycleListeners(core)
  if lifecycleListenersRegistered then return end
  lifecycleListenersRegistered = true

  core:On("CHAT_FRAME_READY", function(_, core2, chatFrame)
    if not core2:IsModuleActive("Restore") then return end
    ApplyFadeSettings(chatFrame)
  end, M)
end

function M:OnEnable(core)
  self.active = true
  lifecycleListenersRegistered = false

  core:RegisterAddMessageHook(OnAddMessage, self, 20)
  core:EnsureChatLifecycleHooks()
  RegisterLifecycleListeners(core)

  local function ApplyAll()
    if not core:IsModuleActive("Restore") and core._loginComplete then return end
    for _, cf in ipairs(NS.GetChatFrames()) do
      ApplyFadeSettings(cf)
    end
  end

  if InCombatLockdown() then
    core:Defer(function()
      if core:IsModuleActive("Restore") then ApplyAll() end
    end)
  else
    ApplyAll()
  end
end

local function RestoreChatFrame(self, cf, idx, maxLines)
  if not IsPersistentChatFrame(cf) then return end
  local bucket = self.db.frames[idx]
  if type(bucket) ~= "table" or type(bucket.entries) ~= "table" then return end
  local entries = bucket.entries
  local n = #entries
  if n <= 0 then return end
  local start = math.max(1, n - maxLines + 1)

  self._restoring = true
  cf.__rothRestoring = true

  NS.SafeCall("RothChat:Restore:" .. tostring(idx), function()
    for i = start, n do
      local e = entries[i]
      if type(e) == "table" then
        local msg = e[2]
        if type(msg) == "string" and msg ~= "" then
          local r = type(e[3]) == "number" and e[3] or 1
          local g = type(e[4]) == "number" and e[4] or 1
          local b = type(e[5]) == "number" and e[5] or 1
          cf:AddMessage(msg, r, g, b)
        end
      end
    end
    if cf.ScrollToBottom then cf:ScrollToBottom() end
  end)

  cf.__rothRestoring = nil
  self._restoring = false
end

function M:OnLogin(core)
  if InCombatLockdown() then
    core:Defer(function()
      if core:IsModuleActive("Restore") then M:OnLogin(core) end
    end)
    return
  end

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
  self._restoring = false
  lifecycleListenersRegistered = false
  core:UnregisterAddMessageHooks(self)

  for _, cf in ipairs(NS.GetChatFrames()) do
    cf.__rothRestoring = nil
    RestoreFadeSettings(cf)
  end
end
