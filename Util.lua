-- RothChat - ordinary-value helpers, cancellable scheduling and shared fades.
local _, NS = ...
local unpackValues = unpack or table.unpack

function NS.Pack(...)
  return { n = select("#", ...), ... }
end

function NS.Unpack(values, first)
  return unpackValues(values, first or 1, values.n)
end

local function IsSecretValue(value)
  if type(_G.issecretvalue) ~= "function" then return false end
  local ok, secret = pcall(_G.issecretvalue, value)
  return not ok or secret == true
end

function NS.CanAccessValue(value)
  if type(_G.canaccessvalue) == "function" then
    local ok, accessible = pcall(_G.canaccessvalue, value)
    return ok and accessible == true
  end
  return not IsSecretValue(value)
end

function NS.CanAccessAllValues(...)
  if type(_G.canaccessallvalues) == "function" then
    local ok, accessible = pcall(_G.canaccessallvalues, ...)
    return ok and accessible == true
  end
  for index = 1, select("#", ...) do
    if not NS.CanAccessValue(select(index, ...)) then return false end
  end
  return true
end

-- Table access is a separate capability. The query result can itself be
-- inaccessible, and a failing query must not fall through to iteration.
function NS.CanAccessTable(value)
  if not NS.CanAccessValue(value) or type(value) ~= "table" then return false end
  local query = _G.canaccesstable
  if type(query) ~= "function" then return true end
  local ok, accessible = pcall(query, value)
  return ok and NS.CanAccessValue(accessible) and accessible == true
end

function NS.SafeNumber(value, fallback)
  if not NS.CanAccessValue(value) or type(value) ~= "number"
    or value ~= value or value == math.huge or value == -math.huge
  then
    return fallback
  end
  return value
end

function NS.SafeToString(value)
  if not NS.CanAccessValue(value) then return "" end
  local kind = type(value)
  if kind == "string" then return value end
  if kind == "number" then
    return NS.SafeNumber(value) and tostring(value) or ""
  end
  if kind == "boolean" then return value and "true" or "false" end
  return ""
end

function NS.SafeConcat(...)
  local parts = {}
  for index = 1, select("#", ...) do
    parts[#parts + 1] = NS.SafeToString(select(index, ...))
  end
  return table.concat(parts, " ")
end

local function Utf8Step(text, index)
  local byte = string.byte(text, index)
  local count = byte >= 0xC2 and byte <= 0xDF and 2
    or byte >= 0xE0 and byte <= 0xEF and 3
    or byte >= 0xF0 and byte <= 0xF4 and 4 or 1
  for offset = 1, count - 1 do
    local nextByte = string.byte(text, index + offset)
    if not nextByte or nextByte < 0x80 or nextByte > 0xBF then return 1 end
  end
  return count
end

function NS.Utf8Len(text)
  if not NS.CanAccessValue(text) or type(text) ~= "string" then return 0 end
  local index, count = 1, 0
  while index <= #text do
    index = index + Utf8Step(text, index)
    count = count + 1
  end
  return count
end

function NS.Utf8Sub(text, maxChars)
  if not NS.CanAccessValue(text) or type(text) ~= "string" then return "" end
  maxChars = math.max(0, math.floor(NS.SafeNumber(maxChars, 0)))
  local index, count = 1, 0
  while index <= #text and count < maxChars do
    index = index + Utf8Step(text, index)
    count = count + 1
  end
  return string.sub(text, 1, index - 1)
end

function NS.SafeTrunc(text, maxChars)
  text = NS.SafeToString(text)
  maxChars = math.max(1, math.floor(NS.SafeNumber(maxChars, 4000)))
  local index, count = 1, 0
  while index <= #text and count < maxChars do
    index = index + Utf8Step(text, index)
    count = count + 1
  end
  if index <= #text then return string.sub(text, 1, index - 1) .. "..." end
  return text
end

local function CopyAccessibleEntries(source, staged)
  for key, value in pairs(source) do
    if NS.CanAccessAllValues(key, value) then staged[key] = value end
  end
end

function NS.CopyTable(source, target)
  if not NS.CanAccessValue(target) then return {} end
  if target == nil then
    target = {}
  elseif not NS.CanAccessTable(target) then
    return target
  end
  if not NS.CanAccessTable(source) then return target end

  -- Stage the copy so an iteration failure cannot leave a partially mutated
  -- ownership snapshot behind.
  local staged = {}
  if not pcall(CopyAccessibleEntries, source, staged) then return target end
  for key, value in pairs(staged) do target[key] = value end
  return target
end

function NS.Clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

-- One keyed job per owner/action. A replaced or cancelled due job cannot run
-- from an earlier snapshot; callback arguments retain their exact nil arity.
local scheduledJobs, scheduledCount, nextScheduledJobID = {}, 0, 0
local MAX_SCHEDULED_JOBS = 128
local schedulerFrame = CreateFrame("Frame", "RothChatScheduler")

local function SchedulerOnUpdate(self)
  local now = NS.SafeNumber(GetTime())
  if not now then return end

  local due
  for key, job in pairs(scheduledJobs) do
    if now >= job.at then
      due = due or {}
      due[#due + 1] = key
      due[#due + 1] = job
    end
  end
  if not due then return end

  for index = 1, #due, 2 do
    local key, job = due[index], due[index + 1]
    if scheduledJobs[key] == job then
      scheduledJobs[key] = nil
      scheduledCount = scheduledCount - 1
      NS.SafeCall(job.diagnosticLabel, job.fn, NS.Unpack(job.args))
    end
  end
  if not next(scheduledJobs) then self:SetScript("OnUpdate", nil) end
end

function NS.Schedule(key, delay, callback, label, ...)
  if not NS.CanAccessAllValues(key, delay, callback, label) or key == nil
    or type(callback) ~= "function" or (label ~= nil and type(label) ~= "string")
    or not NS.CanAccessAllValues(...)
  then
    return false
  end

  delay = NS.SafeNumber(delay)
  local now = NS.SafeNumber(GetTime())
  if delay == nil or now == nil then return false end

  local previous = scheduledJobs[key]
  local id = previous and previous.id
  if not id then
    if scheduledCount >= MAX_SCHEDULED_JOBS then return false end
    scheduledCount = scheduledCount + 1
    nextScheduledJobID = nextScheduledJobID + 1
    id = nextScheduledJobID
  end

  local baseLabel = label or "RothChat:Schedule"
  scheduledJobs[key] = {
    at = now + math.max(0, delay),
    fn = callback,
    args = NS.Pack(...),
    id = id,
    diagnosticLabel = baseLabel .. "#" .. tostring(id),
  }
  if not schedulerFrame:GetScript("OnUpdate") then
    schedulerFrame:SetScript("OnUpdate", SchedulerOnUpdate)
  end
  return true
end

function NS.RunNextFrame(key, callback, label, ...)
  return NS.Schedule(key, 0, callback, label, ...)
end

function NS.CancelScheduled(key)
  if not NS.CanAccessValue(key) then return false end
  if key == nil or not scheduledJobs[key] then return false end
  scheduledJobs[key] = nil
  scheduledCount = scheduledCount - 1
  if not next(scheduledJobs) then schedulerFrame:SetScript("OnUpdate", nil) end
  return true
end

-- Shared easing adapted from ls_Glass (Apache-2.0; see ThirdParty/ATTRIBUTIONS.md).
local fadeObjects = {}
local fadeUpdater = CreateFrame("Frame", "RothChatFader")
local nextFadeID = 0

local function CanFade(frame)
  return NS.CanAccessObject(frame)
end

local function ReadField(object, field)
  return object[field]
end

local function GetFrameMethod(frame, methodName)
  local ok, method = pcall(ReadField, frame, methodName)
  if not ok or not NS.CanAccessValue(method) or type(method) ~= "function" then return nil end
  return method
end

local function ReadAlpha(frame)
  if not CanFade(frame) then return nil end
  local method = GetFrameMethod(frame, "GetAlpha")
  if not method then return nil end
  local ok, alpha = pcall(method, frame)
  return ok and NS.SafeNumber(alpha) or nil
end

local function WriteAlpha(frame, alpha)
  if not CanFade(frame) then return false end
  local method = GetFrameMethod(frame, "SetAlpha")
  if not method then return false end
  return pcall(method, frame, alpha)
end

local function NewFadeDiagnosticLabel()
  nextFadeID = nextFadeID + 1
  return "RothChat:FadeComplete#" .. tostring(nextFadeID)
end

local function StopIdleFader()
  if not next(fadeObjects) then fadeUpdater:SetScript("OnUpdate", nil) end
end

local function FadeOnUpdate(_, elapsed)
  elapsed = NS.SafeNumber(elapsed)
  if not elapsed or elapsed < 0 then return end

  local completed
  for frame, data in pairs(fadeObjects) do
    if not CanFade(frame) then
      fadeObjects[frame] = nil
    else
      data.timer = data.timer + elapsed
      local done = data.timer >= data.duration
      local alpha
      if done then
        alpha = data.target
      else
        local progress = data.timer / data.duration - 1
        alpha = NS.Clamp(data.initial + (data.target - data.initial) * (progress ^ 3 + 1), 0, 1)
      end

      if not WriteAlpha(frame, alpha) then
        if fadeObjects[frame] == data then fadeObjects[frame] = nil end
      elseif done then
        if data.callback then
          completed = completed or {}
          completed[#completed + 1] = frame
          completed[#completed + 1] = data
        elseif fadeObjects[frame] == data then
          fadeObjects[frame] = nil
        end
      end
    end
  end

  -- Keep completion identity until dispatch so an earlier callback can cancel
  -- or replace a later completion from this same update.
  if completed then
    for index = 1, #completed, 2 do
      local frame, data = completed[index], completed[index + 1]
      if fadeObjects[frame] == data then
        fadeObjects[frame] = nil
        if CanFade(frame) then NS.SafeCall(data.diagnosticLabel, data.callback, frame) end
      end
    end
  end
  StopIdleFader()
end

function NS.StopFading(frame, alpha)
  if not NS.CanAccessValue(frame) or frame == nil then return false end
  local stopped = fadeObjects[frame] ~= nil
  fadeObjects[frame] = nil
  alpha = NS.SafeNumber(alpha)
  if alpha ~= nil then WriteAlpha(frame, NS.Clamp(alpha, 0, 1)) end
  StopIdleFader()
  return stopped
end

-- Stop a fade only when the caller still owns the active fade record. This is
-- the teardown primitive for modules that share an alpha surface with another
-- owner and must not cancel a later replacement fade.
function NS.IsFading(frame)
  return CanFade(frame) and fadeObjects[frame] ~= nil
end

function NS.StopOwnedFade(frame, owner)
  if not CanFade(frame) or owner == nil or not NS.CanAccessValue(owner) then return false end
  local data = fadeObjects[frame]
  if not data or data.owner ~= owner then return false end
  fadeObjects[frame] = nil
  StopIdleFader()
  return true
end

function NS.FadeTo(frame, target, duration, callback, owner)
  if not CanFade(frame) or not NS.CanAccessAllValues(target, duration, callback, owner)
    or (callback ~= nil and type(callback) ~= "function")
  then
    return false
  end

  target = NS.SafeNumber(target)
  duration = NS.SafeNumber(duration)
  if target == nil or duration == nil then return false end
  target = NS.Clamp(target, 0, 1)
  duration = math.max(0, duration)

  local current = ReadAlpha(frame)
  if current == nil then NS.StopFading(frame); return false end

  if duration == 0 or math.abs(current - target) < 0.01 then
    NS.StopFading(frame)
    if not WriteAlpha(frame, target) then return false end
    if callback then NS.SafeCall(NewFadeDiagnosticLabel(), callback, frame) end
    return true
  end

  local previous = fadeObjects[frame]
  if previous and previous.target == target and previous.owner == owner
    and previous.duration == duration
  then
    previous.callback = callback
    if callback and not previous.diagnosticLabel then
      previous.diagnosticLabel = NewFadeDiagnosticLabel()
    end
    return true
  end

  fadeObjects[frame] = {
    timer = 0,
    initial = current,
    target = target,
    duration = duration,
    callback = callback,
    diagnosticLabel = callback and NewFadeDiagnosticLabel() or nil,
    owner = owner,
  }
  if not fadeUpdater:GetScript("OnUpdate") then fadeUpdater:SetScript("OnUpdate", FadeOnUpdate) end
  return true
end
