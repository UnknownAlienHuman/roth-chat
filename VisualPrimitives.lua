-- RothChat - sole owner of reusable addon decoration.
local _, NS = ...

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

-- ls_Glass-style gradient background (based on ls_Glass by ls-, Apache-2.0)
-- 3-part gradient: left=15% fade-in, solid center, right=45% fade-out
-- Color: pure black (0,0,0) — cleaner than codGray
function NS.ApplyGlassLook(frame, alpha)
  if not NS.CanAccessObject(frame) then return end
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
    frame.glassLeft._from = CreateColor(0, 0, 0, 0)
    frame.glassLeft._to   = CreateColor(0, 0, 0, alpha)
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
    frame.glassRight._from = CreateColor(0, 0, 0, alpha)
    frame.glassRight._to   = CreateColor(0, 0, 0, 0)
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
  frame.glassLeft:Show()
  frame.glassCenter:Show()
  frame.glassRight:Show()
end

-- Update gradient proportions when frame is resized
function NS.UpdateGlassSize(frame)
  if not NS.CanAccessObject(frame) or not frame.glassLeft then return end
  local w = NS.SafeNumber(frame:GetWidth(), 1)
  frame.glassLeft:SetWidth(math.max(8, math.floor(w * 0.15 + 0.5)))
  frame.glassRight:SetWidth(math.max(8, math.floor(w * 0.45 + 0.5)))
end

-- Simple solid background for buttons, overlay panels, etc.
function NS.ApplyGlassSolid(frame, alpha)
  if not NS.CanAccessObject(frame) then return end
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
  frame.glassSolid:Show()
end

-- Bordered backdrop using ls_Glass border.TGA (Apache-2.0)
function NS.ApplyGlassBackdrop(frame, alpha, xOff, yOff)
  if not NS.CanAccessObject(frame) then return end
  alpha = alpha or 0.8
  xOff = xOff or 0
  yOff = yOff or 2

  if frame.__glassBackdrop then
    frame.__glassBackdrop:ClearAllPoints()
    frame.__glassBackdrop:SetPoint("TOPLEFT", xOff, -yOff)
    frame.__glassBackdrop:SetPoint("BOTTOMRIGHT", -xOff, yOff)
    frame.__glassBackdrop:Show()
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
  if not NS.CanAccessObject(frame) then return end
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

  local existing = frame.__rothHighlight
  if existing then
    for _, region in ipairs(existing) do
      region:SetVertexColor(r, g, b)
      region:SetDrawLayer(layer)
      region:Show()
    end
    existing[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOff)
    existing[3]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, yOff)
    return existing[1], existing[2], existing[3]
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

  frame.__rothHighlight = { hlLeft, hlMiddle, hlRight }
  return hlLeft, hlMiddle, hlRight
end

-- Hide only addon-created decoration; native region state belongs to Style.
local VISUAL_KEYS = { "__glassBackdrop", "__scrollIcon", "glassLeft", "glassCenter", "glassRight", "glassSolid", "glassBorder" }
function NS.HideRothVisuals(frame)
  if not NS.CanAccessObject(frame) then return end
  for _, key in ipairs(VISUAL_KEYS) do
    local region = frame[key]
    if region and NS.CanAccessObject(region) and region.Hide then region:Hide() end
  end
  if frame.__rothHighlight then
    for _, region in ipairs(frame.__rothHighlight) do
      if NS.CanAccessObject(region) and region.Hide then region:Hide() end
    end
  end
end
