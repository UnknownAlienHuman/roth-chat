-- RothChat - idempotent visual primitives.
-- Util.lua creates the original Glass assets. This layer makes repeated
-- enable/disable cycles reuse and reshow those same regions instead of stacking
-- textures or leaving hidden backdrop frames hidden forever.

local ADDON_NAME, NS = ...
NS = NS or {}

local originalApplyGlassLook = NS.ApplyGlassLook
local originalApplyGlassSolid = NS.ApplyGlassSolid
local originalApplyGlassBackdrop = NS.ApplyGlassBackdrop
local originalCreateHighlight = NS.CreateHighlight

local function Show(region)
  if region and type(region.Show) == "function" then region:Show() end
end

function NS.ApplyGlassLook(frame, alpha)
  if originalApplyGlassLook then originalApplyGlassLook(frame, alpha) end
  if not frame then return end
  Show(frame.glassLeft)
  Show(frame.glassCenter)
  Show(frame.glassRight)
end

function NS.ApplyGlassSolid(frame, alpha)
  if originalApplyGlassSolid then originalApplyGlassSolid(frame, alpha) end
  if not frame then return end
  Show(frame.glassSolid)
end

function NS.ApplyGlassBackdrop(frame, alpha, xOffset, yOffset)
  if originalApplyGlassBackdrop then originalApplyGlassBackdrop(frame, alpha, xOffset, yOffset) end
  if frame then Show(frame.__glassBackdrop) end
end

function NS.CreateHighlight(frame, layer, r, g, b, yOffset)
  if not frame then return end

  local existing = frame.__rothHighlight
  if existing then
    for index = 1, #existing do Show(existing[index]) end
    return existing[1], existing[2], existing[3]
  end

  if not originalCreateHighlight then return end
  local left, middle, right = originalCreateHighlight(frame, layer, r, g, b, yOffset)
  frame.__rothHighlight = { left, middle, right }
  return left, middle, right
end

function NS.HideRothVisuals(frame)
  if not frame then return end
  if frame.__glassBackdrop and frame.__glassBackdrop.Hide then frame.__glassBackdrop:Hide() end
  if frame.__scrollIcon and frame.__scrollIcon.Hide then frame.__scrollIcon:Hide() end
  if frame.__rothHighlight then
    for index = 1, #frame.__rothHighlight do
      local region = frame.__rothHighlight[index]
      if region and region.Hide then region:Hide() end
    end
  end
  for _, key in ipairs({ "glassLeft", "glassCenter", "glassRight", "glassSolid", "glassBorder" }) do
    local region = frame[key]
    if region and region.Hide then region:Hide() end
  end
end
