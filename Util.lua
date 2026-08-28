-- RothChat - shared utilities
-- Design goal: predictable behavior, low allocations.

local ADDON_NAME, NS = ...
NS = NS or {}

-- -----------------------------------------------------------------------------
-- Errors / safe call
-- -----------------------------------------------------------------------------

local function ErrorHandler(err)
  return tostring(err) .. "\n" .. debugstack(2, 25, 25)
end

function NS.SafeCall(label, fn, ...)
  if type(fn) ~= "function" then return true end
  local ok, res = xpcall(fn, ErrorHandler, ...)
  if not ok then
    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff4040%s error|r: %s", tostring(label or "RothChat"), tostring(res)))
    end
    return false, res
  end
  return true, res
end

-- -----------------------------------------------------------------------------
-- Shared scheduler
-- -----------------------------------------------------------------------------

local scheduledJobs = {}
local schedulerFrame = CreateFrame("Frame", "RothChatScheduler")

local function SchedulerOnUpdate(self)
  local now = GetTime()
  local due = nil

  for key, job in next, scheduledJobs do
    if job and now >= job.at then
      if not due then
        due = {}
      end
      due[#due + 1] = job
      scheduledJobs[key] = nil
    end
  end

  if not next(scheduledJobs) then
    self:SetScript("OnUpdate", nil)
  end

  if not due then
    return
  end

  for i = 1, #due do
    local job = due[i]
    if job and job.fn then
      NS.SafeCall(job.label or "RothChat:Schedule", job.fn, unpack(job.args))
    end
  end
end

local function EnsureScheduler()
  if not schedulerFrame:GetScript("OnUpdate") then
    schedulerFrame:SetScript("OnUpdate", SchedulerOnUpdate)
  end
end

function NS.Schedule(key, delay, fn, label, ...)
  if key == nil or type(fn) ~= "function" then
    return
  end

  scheduledJobs[key] = {
    at = GetTime() + math.max(0, tonumber(delay) or 0),
    fn = fn,
    args = { ... },
    label = label,
  }

  EnsureScheduler()
end

function NS.RunNextFrame(key, fn, label, ...)
  NS.Schedule(key, 0, fn, label, ...)
end

function NS.CancelScheduled(key)
  if key == nil then
    return
  end

  scheduledJobs[key] = nil
  if not next(scheduledJobs) then
    schedulerFrame:SetScript("OnUpdate", nil)
  end
end

-- -----------------------------------------------------------------------------
-- Restriction helpers
-- -----------------------------------------------------------------------------

function NS.IsChatMessagingRestricted()
  local chatInfo = _G.C_ChatInfo
  if not chatInfo or type(chatInfo.InChatMessagingLockdown) ~= "function" then
    return false
  end

  local ok, restricted = pcall(chatInfo.InChatMessagingLockdown)
  return ok and restricted and true or false
end

function NS.IsSettingsOpenRestricted()
  local inCombat = false
  local fn = _G.InCombatLockdown
  if type(fn) == "function" then
    local ok, locked = pcall(fn)
    inCombat = ok and locked and true or false
  end

  return inCombat or NS.IsChatMessagingRestricted()
end

-- -----------------------------------------------------------------------------
-- Secret/access-safe value handling
-- -----------------------------------------------------------------------------

function NS.IsSecretValue(v)
  local fn = _G.issecretvalue
  if type(fn) ~= "function" then return false end
  local ok, res = pcall(fn, v)
  return ok and (res and true or false) or false
end

-- `issecretvalue` and `canaccessvalue` answer different questions in Retail
-- 12.1. Addon code must gate on current accessibility before evaluating a value.
function NS.CanAccessValue(v)
  local fn = _G.canaccessvalue
  if type(fn) == "function" then
    local ok, res = pcall(fn, v)
    if ok then
      return res and true or false
    end
    return false
  end

  -- Compatibility fallback for clients without the access predicate.
  return not NS.IsSecretValue(v)
end

function NS.IsInaccessibleValue(v)
  return not NS.CanAccessValue(v)
end

function NS.SafeToString(v)
  if v == nil then return "" end
  if not NS.CanAccessValue(v) then return "" end

  local tv = type(v)
  if tv == "string" then return v end
  if tv == "number" then return tostring(v) end
  if tv == "boolean" then return v and "true" or "false" end

  local ok, s = pcall(tostring, v)
  if not ok or type(s) ~= "string" then
    return ""
  end
  if not NS.CanAccessValue(s) then
    return ""
  end
  return s
end

function NS.SafeConcat(...)
  local n = select("#", ...)
  if n == 0 then return "" end
  local out = {}
  for i = 1, n do
    out[#out + 1] = NS.SafeToString(select(i, ...))
  end
  return table.concat(out, " ")
end

function NS.Utf8Len(str)
  if not str or not NS.CanAccessValue(str) then return 0 end
  local len = 0
  local i = 1
  local n = #str
  while i <= n do
    local b = string.byte(str, i)
    if not b then break end
    if b < 128 then i = i + 1
    elseif b < 224 then i = i + 2
    elseif b < 240 then i = i + 3
    else i = i + 4 end
    len = len + 1
  end
  return len
end

function NS.Utf8Sub(str, numChars)
  if not str or not NS.CanAccessValue(str) then return "" end
  numChars = math.max(0, tonumber(numChars) or 0)
  local len = #str
  local count = 0
  local i = 1
  while i <= len and count < numChars do
    local b = string.byte(str, i)
    if not b then break end
    if b < 128 then i = i + 1
    elseif b < 224 then i = i + 2
    elseif b < 240 then i = i + 3
    else i = i + 4 end
    count = count + 1
  end
  return string.sub(str, 1, i - 1)
end

function NS.SafeTrunc(s, maxChars)
  if not NS.CanAccessValue(s) then return "" end
  s = NS.SafeToString(s)
  maxChars = tonumber(maxChars) or 4000
  if maxChars < 64 then maxChars = 64 end
  if NS.Utf8Len(s) > maxChars then
    return NS.Utf8Sub(s, maxChars) .. "..."
  end
  return s
end

-- -----------------------------------------------------------------------------
-- Tables / math
-- -----------------------------------------------------------------------------

function NS.CopyTable(src, dst)
  dst = dst or {}
  if not src then return dst end
  for k, v in pairs(src) do dst[k] = v end
  return dst
end

function NS.DeepCopy(src, dst)
  if type(src) ~= "table" then return src end
  dst = dst or {}
  for k, v in pairs(src) do
    if type(v) == "table" then dst[k] = NS.DeepCopy(v, {}) else dst[k] = v end
  end
  return dst
end

function NS.Clamp(v, minv, maxv)
  if v < minv then return minv end
  if v > maxv then return maxv end
  return v
end

-- -----------------------------------------------------------------------------
-- Animation helpers (Native AnimationGroup) outCubic easing (from ls_Glass by ls-, Apache-2.0)
local function clampAlpha(v)
  if v > 1 then return 1 elseif v < 0 then return 0 end
  return v
end

local function outCubic(t, b, c, d)
  t = t / d - 1
  return clampAlpha(c * (t ^ 3 + 1) + b)
end

-- Smooth OnUpdate-based fader with outCubic easing (inspired by ls_Glass)
local fadeObjects = {}
local fadeUpdater = CreateFrame("Frame", "RothChatFader")

local function fadeUpdater_OnUpdate(_, elapsed)
  local anyLeft = false
  for obj, data in next, fadeObjects do
    data.timer = data.timer + elapsed
    if data.timer >= data.duration then
      obj:SetAlpha(data.target)
      fadeObjects[obj] = nil
      obj.__rothFadeTarget = nil
      local cb = data.callback
      if cb then cb(obj) end
    else
      obj:SetAlpha(outCubic(data.timer, data.initAlpha, data.target - data.initAlpha, data.duration))
      anyLeft = true
    end
  end
  if not anyLeft and not next(fadeObjects) then
    fadeUpdater:SetScript("OnUpdate", nil)
  end
end

function NS.FadeTo(frame, targetAlpha, duration, callback)
  if not frame then return end
  targetAlpha = NS.Clamp(targetAlpha or 1, 0, 1)
  duration = duration or 0.35

  local cur = frame:GetAlpha()
  if math.abs(cur - targetAlpha) < 0.01 then
    frame:SetAlpha(targetAlpha)
    frame.__rothFadeTarget = nil
    if callback then callback(frame) end
    return
  end

  -- Deduplicate: skip if already fading to same target
  if frame.__rothFadeTarget ~= nil and math.abs(frame.__rothFadeTarget - targetAlpha) < 0.005 and fadeObjects[frame] then
    return
  end
  frame.__rothFadeTarget = targetAlpha

  fadeObjects[frame] = {
    timer = 0,
    initAlpha = cur,
    target = targetAlpha,
    duration = duration,
    callback = callback,
  }

  if not fadeUpdater:GetScript("OnUpdate") then
    fadeUpdater:SetScript("OnUpdate", fadeUpdater_OnUpdate)
  end
end

function NS.StopFading(frame, alpha)
  if not frame then return end
  fadeObjects[frame] = nil
  frame.__rothFadeTarget = nil
  if alpha then frame:SetAlpha(alpha) end
  if not next(fadeObjects) then
    fadeUpdater:SetScript("OnUpdate", nil)
  end
end

-- -----------------------------------------------------------------------------
-- UI helpers
-- -----------------------------------------------------------------------------

-- Asset paths (ls_Glass textures, Apache-2.0)
local BORDER_TEXTURE = "Interface\\AddOns\\RothChat\\Assets\\border"
local BORDER_HL_TEXTURE = "Interface\\AddOns\\RothChat\\Assets\\border-highlight"
local SCROLL_BTN_TEXTURE = "Interface\\AddOns\\RothChat\\Assets\\scroll-buttons"
local ICONS_TEXTURE = "Interface\\AddOns\\RothChat\\Assets\\icons"

-- Export paths for other modules
NS.BORDER_TEXTURE = BORDER_TEXTURE
NS.BORDER_HL_TEXTURE = BORDER_HL_TEXTURE
NS.SCROLL_BTN_TEXTURE = SCROLL_BTN_TEXTURE
NS.ICONS_TEXTURE = ICONS_TEXTURE

-- Scroll-buttons atlas: 128x128, 4 icons 52x52 each in 2x2 grid
-- Each entry = {left, right, top, bottom}
NS.SCROLL_ICONS = {
  TO_BOTTOM   = { 0/128,  52/128,  0/128,  52/128},
  NEW_MESSAGE = {52/128, 104/128,  0/128,  52/128},
  SCROLL_DOWN = { 0/128,  52/128, 52/128, 104/128},
  SCROLL_UP   = {52/128, 104/128, 52/128, 104/128},
}

-- Icons atlas: 4x2 grid, each icon = 0.25 x 0.5
NS.BUTTON_ICONS = {
  OVERFLOW  = {0,    0.25, 0,   0.5},
  MINIMIZE  = {0.25, 0.5,  0,   0.5},
  MAXIMIZE  = {0.5,  0.75, 0,   0.5},
  MENU      = {0.75, 1,    0,   0.5},
  CHANNEL   = {0,    0.25, 0.5, 1  },
  TTS       = {0.25, 0.5,  0.5, 1  },
  QUICKJOIN = {0.5,  0.75, 0.5, 1  },
}

-- CreateShadow: deprecated, border.TGA now handles edges
function NS.CreateShadow(parent)
  return nil
end

function NS.GetChatFrames()
  local frames = {}
  if _G.CHAT_FRAMES then
    -- WoW 8.0+ dynamically tracks all chat frame strings here
    for _, frameName in ipairs(_G.CHAT_FRAMES) do
      local cf = _G[frameName]
      if cf then frames[#frames + 1] = cf end
    end
  else
    -- Fallback for extremely old clients if CHAT_FRAMES doesn't exist
    if not NUM_CHAT_WINDOWS then return frames end
    for i = 1, NUM_CHAT_WINDOWS do
      local cf = _G["ChatFrame" .. i]
      if cf then frames[#frames + 1] = cf end
    end
  end
  return frames
end

-- -----------------------------------------------------------------------------
-- ChatFrame helpers (robust against GetID quirks)
-- -----------------------------------------------------------------------------

function NS.GetChatFrameIndex(chatFrame)
  if not chatFrame then return nil end
  if type(chatFrame.GetID) == "function" then
    local ok, id = pcall(chatFrame.GetID, chatFrame)
    if ok and type(id) == "number" and id >= 1 then
      return id
    end
  end

  if type(chatFrame.GetName) == "function" then
    local name = chatFrame:GetName()
    if type(name) == "string" then
      local n = name:match("^ChatFrame(%d+)$")
      if n then return tonumber(n) end
    end
  end

  return nil
end

function NS.IsDockedChatFrame(chatFrame)
  if not chatFrame then return false end

  -- Modern chat frames expose this directly.
  if chatFrame.isDocked then
    return true
  end

  local id = NS.GetChatFrameIndex(chatFrame)
  if not id then return false end

  -- FloatingChatFrame.lua: FCF_GetChatWindowInfo returns isDocked as value #9.
  local infoFn = _G.FCF_GetChatWindowInfo
  if type(infoFn) == "function" then
    local ok, _, _, _, _, _, _, _, isDocked = pcall(infoFn, id)
    if ok and isDocked ~= nil then
      return isDocked and true or false
    end
  end

  -- Legacy fallback (not present in all builds).
  local fn = _G.FCF_IsChatWindowDocked
  if type(fn) == "function" then
    local ok, res = pcall(fn, id)
    if ok then
      return res and true or false
    end
  end

  return false
end

function NS.GetSelectedDockChatFrame()
  local fn = _G.FCFDock_GetSelectedWindow
  local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
  if type(fn) == "function" and dock then
    local ok, selected = pcall(fn, dock)
    if ok and selected then return selected end
  end

  local selected = _G.SELECTED_CHAT_FRAME
  if selected then
    return selected
  end

  return nil
end

function NS.ResolveActiveDockChatFrame(chatFrame)
  if chatFrame and NS.IsDockedChatFrame(chatFrame) then
    local selected = NS.GetSelectedDockChatFrame()
    if selected then
      return selected
    end
  end
  return chatFrame
end

function NS.AddMessageEventFilter(event, callback)
  if type(event) ~= "string" or type(callback) ~= "function" then return false end

  if _G.ChatFrameUtil and type(_G.ChatFrameUtil.AddMessageEventFilter) == "function" then
    local ok = pcall(_G.ChatFrameUtil.AddMessageEventFilter, event, callback)
    if ok then return true end
  end

  if type(_G.ChatFrame_AddMessageEventFilter) == "function" then
    local ok = pcall(_G.ChatFrame_AddMessageEventFilter, event, callback)
    if ok then return true end
  end

  return false
end

function NS.RemoveMessageEventFilter(event, callback)
  if type(event) ~= "string" or type(callback) ~= "function" then return false end

  if _G.ChatFrameUtil and type(_G.ChatFrameUtil.RemoveMessageEventFilter) == "function" then
    local ok = pcall(_G.ChatFrameUtil.RemoveMessageEventFilter, event, callback)
    if ok then return true end
  end

  if type(_G.ChatFrame_RemoveMessageEventFilter) == "function" then
    local ok = pcall(_G.ChatFrame_RemoveMessageEventFilter, event, callback)
    if ok then return true end
  end

  return false
end

function NS.CollectChatText(chatFrame, maxLines)
  if not chatFrame or type(chatFrame.GetNumMessages) ~= "function" then return "" end

  local okN, n = pcall(chatFrame.GetNumMessages, chatFrame)
  n = okN and (tonumber(n) or 0) or 0
  if n <= 0 then return "" end

  maxLines = tonumber(maxLines) or 400
  local start = math.max(1, n - maxLines + 1)
  local out = {}

  for i = start, n do
    -- GetMessageInfo returns: text, r, g, b, chatTypeID, ...
    local ok, text = pcall(chatFrame.GetMessageInfo, chatFrame, i)
    if ok and text and NS.CanAccessValue(text) then
      if type(text) ~= "string" then
        text = NS.SafeToString(text)
      end
      if type(text) == "string" and text ~= "" then
        out[#out + 1] = text
      end
    end
  end

  if #out == 0 then return "" end
  return table.concat(out, "\n")
end

-- Last-resort fallback: scrape rendered FontStrings (ordering is best-effort).
function NS.CollectChatTextFromFontStrings(chatFrame)
  if not chatFrame or type(chatFrame.GetRegions) ~= "function" then return "" end
  local regions = { chatFrame:GetRegions() }
  if #regions == 0 then return "" end

  local out = {}
  for _, r in ipairs(regions) do
    if r and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText then
      local ok, text = pcall(r.GetText, r)
      if ok and text and type(text) == "string" and text ~= "" and NS.CanAccessValue(text) then
        out[#out + 1] = text
      end
    end
  end

  if #out == 0 then return "" end
  return table.concat(out, "\n")
end

-- ls_Glass-style gradient background (based on ls_Glass by ls-, Apache-2.0)
-- 3-part gradient: left=15% fade-in, solid center, right=45% fade-out
-- Color: pure black (0,0,0) — cleaner than codGray
function NS.ApplyGlassLook(frame, alpha)
  if not frame then return end
  alpha = alpha or 0.4

  if frame.SetBackdrop then frame:SetBackdrop(nil) end

  local frameW = frame.GetWidth and frame:GetWidth() or 300
  local leftW = math.max(8, math.floor(frameW * 0.15 + 0.5))
  local rightW = math.max(8, math.floor(frameW * 0.45 + 0.5))

  -- Left gradient: transparent → opaque
  if not frame.glassLeft then
    frame.glassLeft = frame:CreateTexture(nil, "BACKGROUND")
    frame.glassLeft:SetPoint("TOPLEFT")
    frame.glassLeft:SetPoint("BOTTOMLEFT")
    frame.glassLeft:SetSnapToPixelGrid(false)
    frame.glassLeft:SetTexelSnappingBias(0)
    frame.glassLeft:SetColorTexture(1, 1, 1, 1)
    frame.glassLeft._from = {r = 0, g = 0, b = 0, a = 0}
    frame.glassLeft._to   = {r = 0, g = 0, b = 0, a = alpha}
  end
  frame.glassLeft:SetWidth(leftW)
  frame.glassLeft._to.a = alpha
  frame.glassLeft:SetGradient("HORIZONTAL", frame.glassLeft._from, frame.glassLeft._to)

  -- Right gradient: opaque → transparent
  if not frame.glassRight then
    frame.glassRight = frame:CreateTexture(nil, "BACKGROUND")
    frame.glassRight:SetPoint("TOPRIGHT")
    frame.glassRight:SetPoint("BOTTOMRIGHT")
    frame.glassRight:SetSnapToPixelGrid(false)
    frame.glassRight:SetTexelSnappingBias(0)
    frame.glassRight:SetColorTexture(1, 1, 1, 1)
    frame.glassRight._from = {r = 0, g = 0, b = 0, a = alpha}
    frame.glassRight._to   = {r = 0, g = 0, b = 0, a = 0}
  end
  frame.glassRight:SetWidth(rightW)
  frame.glassRight._from.a = alpha
  frame.glassRight:SetGradient("HORIZONTAL", frame.glassRight._from, frame.glassRight._to)

  -- Solid center fill
  if not frame.glassCenter then
    frame.glassCenter = frame:CreateTexture(nil, "BACKGROUND")
    frame.glassCenter:SetPoint("TOPLEFT", frame.glassLeft, "TOPRIGHT")
    frame.glassCenter:SetPoint("BOTTOMRIGHT", frame.glassRight, "BOTTOMLEFT")
    frame.glassCenter:SetSnapToPixelGrid(false)
    frame.glassCenter:SetTexelSnappingBias(0)
    frame.glassCenter:SetColorTexture(0, 0, 0, 1)
  end
  frame.glassCenter:SetAlpha(alpha)
  frame.glassBg = frame.glassCenter
end

-- Update gradient proportions when frame is resized
function NS.UpdateGlassSize(frame)
  if not frame or not frame.glassLeft then return end
  local w = frame:GetWidth()
  frame.glassLeft:SetWidth(math.max(8, math.floor(w * 0.15 + 0.5)))
  frame.glassRight:SetWidth(math.max(8, math.floor(w * 0.45 + 0.5)))
end

-- Simple solid background for buttons, overlay panels, etc.
function NS.ApplyGlassSolid(frame, alpha)
  if not frame then return end
  alpha = alpha or 0.6

  if frame.SetBackdrop then frame:SetBackdrop(nil) end

  if not frame.glassSolid then
    frame.glassSolid = frame:CreateTexture(nil, "BACKGROUND")
    frame.glassSolid:SetAllPoints()
    frame.glassSolid:SetSnapToPixelGrid(false)
    frame.glassSolid:SetTexelSnappingBias(0)
  end
  frame.glassSolid:SetColorTexture(0, 0, 0, alpha)
  frame.glassBg = frame.glassSolid
end

-- Bordered backdrop using ls_Glass border.TGA (Apache-2.0)
function NS.ApplyGlassBackdrop(frame, alpha, xOff, yOff)
  if not frame then return end
  alpha = alpha or 0.8
  xOff = xOff or 0
  yOff = yOff or 2

  if frame.__glassBackdrop then
    frame.__glassBackdrop:SetBackdropColor(0, 0, 0, alpha)
    frame.__glassBackdrop:SetBackdropBorderColor(0, 0, 0, alpha)
    return
  end

  local bd = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  bd:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
  bd:SetPoint("TOPLEFT", xOff, -yOff)
  bd:SetPoint("BOTTOMRIGHT", -xOff, yOff)
  bd:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = BORDER_TEXTURE,
    tile = true,
    tileEdge = true,
    tileSize = 8,
    edgeSize = 8,
  })
  bd:SetBackdropColor(0, 0, 0, alpha)
  bd:SetBackdropBorderColor(0, 0, 0, alpha)

  -- Fix Blizzard Center positioning gap (from ls_Glass)
  local center = bd.Center or (bd.NineSlice and bd.NineSlice.Center)
  if center then
    center:ClearAllPoints()
    center:SetPoint("TOPLEFT", bd, "TOPLEFT", 4, -4)
    center:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -4, 4)
  end

  frame.__glassBackdrop = bd
  frame.glassBg = bd
end

-- 3-part highlight using border-highlight.TGA (ls_Glass, Apache-2.0)
-- Creates left(8x8) + middle(stretches) + right(8x8) highlight textures
function NS.CreateHighlight(frame, layer, r, g, b, yOff)
  if not frame then return end
  layer = layer or "HIGHLIGHT"
  yOff = yOff or -2

  -- Default color: Blizzard selected tab color (warm gold)
  if not r then
    local c = DEFAULT_TAB_SELECTED_COLOR_TABLE
    if c then
      r, g, b = c.r, c.g, c.b
    else
      r, g, b = 1, 0.82, 0
    end
  end

  local hlLeft = frame:CreateTexture(nil, layer)
  hlLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOff)
  hlLeft:SetTexture(BORDER_HL_TEXTURE)
  hlLeft:SetVertexColor(r, g, b)
  hlLeft:SetTexCoord(0, 1, 0.5, 1)
  hlLeft:SetSize(8, 8)

  local hlRight = frame:CreateTexture(nil, layer)
  hlRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, yOff)
  hlRight:SetTexture(BORDER_HL_TEXTURE)
  hlRight:SetVertexColor(r, g, b)
  hlRight:SetTexCoord(1, 0, 0.5, 1)
  hlRight:SetSize(8, 8)

  local hlMiddle = frame:CreateTexture(nil, layer)
  hlMiddle:SetPoint("TOPLEFT", hlLeft, "TOPRIGHT", 0, 0)
  hlMiddle:SetPoint("TOPRIGHT", hlRight, "TOPLEFT", 0, 0)
  hlMiddle:SetTexture(BORDER_HL_TEXTURE)
  hlMiddle:SetVertexColor(r, g, b)
  hlMiddle:SetTexCoord(0, 1, 0, 0.5)
  hlMiddle:SetSize(8, 8)

  return hlLeft, hlMiddle, hlRight
end
