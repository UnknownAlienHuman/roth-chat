-- RothChat - History module
-- Responsibilities:
--   * Log all chat events into SavedVariables (persistent across reload/relog)
--   * Emit a lightweight internal event for other modules (ticker, analytics, etc.)
--
-- Design notes:
--   * We DO NOT try to replicate Blizzard's full chat formatting.
--   * We store both raw fields and a display string that is safe to reuse.
--   * We cap history size to avoid unbounded SavedVariables growth.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat

local M = {
  name = "History",
  defaultEnabled = false,
  description = "Persistent chat history + internal feed for other modules.",
}

local eventFrame

-- Conservative list; safe to register even if some events never fire.
local CHAT_EVENTS = {
  "CHAT_MSG_SAY",
  "CHAT_MSG_YELL",
  "CHAT_MSG_EMOTE",
  "CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_GUILD",
  "CHAT_MSG_OFFICER",
  "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_WHISPER",
  "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER",
  "CHAT_MSG_BN_WHISPER_INFORM",
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_COMMUNITIES_CHANNEL",
  "CHAT_MSG_SYSTEM",
  "CHAT_MSG_AFK",
  "CHAT_MSG_DND",
  "CHAT_MSG_LOOT",
  "CHAT_MSG_MONEY",
  "CHAT_MSG_CURRENCY",
  "CHAT_MSG_COMBAT_XP_GAIN",
  "CHAT_MSG_COMBAT_HONOR_GAIN",
  "CHAT_MSG_SKILL",
  "CHAT_MSG_TRADESKILLS",
  "CHAT_MSG_ACHIEVEMENT",
  "CHAT_MSG_GUILD_ACHIEVEMENT",
  "CHAT_MSG_BATTLEGROUND",
  "CHAT_MSG_BATTLEGROUND_LEADER",
}

local function EnsureHistory(core)
  local db = core.db
  if not db then return nil end
  if type(db.history) ~= "table" then
    db.history = { version = 1, entries = {} }
  end
  if type(db.history.entries) ~= "table" then
    db.history.entries = {}
  end
  return db.history
end

-- Expose a lightweight API so other modules (CopyOverlay) can use the persisted history.
-- Returns a newline-joined string of the last N stored lines.
local function GetHistoryText(core, maxLines, includeTimestamps)
  local history = EnsureHistory(core)
  if not history or not history.entries then return "" end

  maxLines = tonumber(maxLines) or 500
  if maxLines < 1 then maxLines = 1 end
  if maxLines > 5000 then maxLines = 5000 end

  local entries = history.entries
  local n = #entries
  if n == 0 then return "" end
  local start = math.max(1, n - maxLines + 1)

  local out = {}
  for i = start, n do
    local e = entries[i]
    if e and e.line then
      if includeTimestamps and e.t then
        local ts = date("%H:%M:%S", e.t)
        out[#out + 1] = string.format("[%s] %s", ts, e.line)
      else
        out[#out + 1] = e.line
      end
    end
  end
  return table.concat(out, "\n")
end

local function TrimHistory(core, history)
  local maxEntries = tonumber(core:Get("historyMaxEntries")) or 20000
  if maxEntries < 2000 then maxEntries = 2000 end
  if maxEntries > 200000 then maxEntries = 200000 end

  local entries = history.entries
  local n = #entries
  if n <= maxEntries then return end

  local remove = n - maxEntries

  -- Remove in one shift when large (avoid O(n^2) table.remove(1)).
  if table.move and remove > 64 then
    table.move(entries, remove + 1, n, 1)
    for i = maxEntries + 1, n do
      entries[i] = nil
    end
  else
    for _ = 1, remove do
      table.remove(entries, 1)
    end
  end
end

local function FormatDisplayLine(event, msg, author, channelName, channelNumber, channelBaseName)
  if NS.IsSecretValue(msg) or NS.IsSecretValue(author) then
    return nil
  end

  msg = NS.SafeToString(msg)
  author = NS.SafeToString(author)
  channelName = NS.SafeToString(channelName)
  channelBaseName = NS.SafeToString(channelBaseName)

  -- Prefix heuristics.
  local prefix = ""
  if event == "CHAT_MSG_GUILD" then
    prefix = "[G] "
  elseif event == "CHAT_MSG_OFFICER" then
    prefix = "[O] "
  elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
    prefix = "[P] "
  elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
    prefix = "[R] "
  elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
    prefix = "[I] "
  elseif event == "CHAT_MSG_WHISPER" then
    prefix = "[W] "
  elseif event == "CHAT_MSG_WHISPER_INFORM" then
    prefix = "[W->] "
  elseif event == "CHAT_MSG_CHANNEL" or event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
    local ch = (channelBaseName ~= "" and channelBaseName) or (channelName ~= "" and channelName) or "Channel"
    local num = NS.IsSecretValue(channelNumber) and nil or tonumber(channelNumber)
    if num and num > 0 then
      prefix = string.format("[%d.%s] ", num, ch)
    else
      prefix = string.format("[%s] ", ch)
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    prefix = "[System] "
  end

  if author ~= "" and (event:match("^CHAT_MSG_") and not event:match("SYSTEM")) then
    return prefix .. author .. ": " .. msg
  end
  return prefix .. msg
end

local function OnChatEvent(core, event, ...)
  if not core:Get("historyEnabled") then return end

  -- Signature varies, but first args are stable.
  local msg, author, languageName, channelName, target, flags, unknown, channelNumber, channelBaseName, unused,
        lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, suppressRaidIcons = ...

  if NS.IsSecretValue(msg) or NS.IsSecretValue(author) then
    return
  end

  local history = EnsureHistory(core)
  if not history then return end

  local now = (GetServerTime and GetServerTime()) or time()
  local line = FormatDisplayLine(event, msg, author, channelName, channelNumber, channelBaseName)
  if type(line) ~= "string" or line == "" then
    return
  end

  history.entries[#history.entries + 1] = { t = now, event = event, line = line }

  TrimHistory(core, history)

  -- History feed has a distinct event name to avoid signature conflicts with
  -- Restore's live feed (`CHAT_FEED`, where arg1 is chatFrame).
  core:Emit("CHAT_FEED_HISTORY", event, line, msg, author, now)
end

local function RegisterEvents(core)
  if not eventFrame then
    eventFrame = CreateFrame("Frame")
  end

  eventFrame:SetScript("OnEvent", function(_, event, ...)
    OnChatEvent(core, event, ...)
  end)

  for _, ev in ipairs(CHAT_EVENTS) do
    eventFrame:RegisterEvent(ev)
  end
end

local function UnregisterEvents()
  if not eventFrame then return end
  eventFrame:UnregisterAllEvents()
end

function M:Init(core)
  self.core = core
  EnsureHistory(core)

  -- Public API (kept tiny on purpose).
  core.GetHistoryText = function(_, maxLines, includeTimestamps)
    return GetHistoryText(core, maxLines, includeTimestamps)
  end

  return true
end

function M:OnEnable(core)
  local function Apply()
    RegisterEvents(core)
  end

  if InCombatLockdown() then
    core:Defer(Apply)
  else
    Apply()
  end
end

function M:OnLogin(core)
  -- Ensure events after PLAYER_LOGIN.
  self:OnEnable(core)
end

function M:OnDisable(core)
  UnregisterEvents()
end

RothChat:RegisterModule(M)
