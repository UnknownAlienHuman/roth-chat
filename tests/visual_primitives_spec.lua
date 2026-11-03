-- Production decoration must reuse regions and survive disable/re-enable.
local env = assert(loadfile("tests/support/runtime.lua"))().New()
local NS = env.ns
local textures, backdrops = 0, 0
_G.CreateColor = function(r, g, b, a)
  return { r = r, g = g, b = b, a = a, GetRGBA = function(self) return self.r, self.g, self.b, self.a end }
end
local function Decorate(object)
  object.points = {}
  function object:SetPoint(...) self.points[#self.points + 1] = {...} end
  function object:ClearAllPoints() self.points = {} end
  function object:SetAllPoints() end
  function object:SetWidth(width) self.width = width end
  function object:GetWidth() return self.width or 300 end
  function object:SetSize(w, h) self.width, self.height = w, h end
  function object:SetSnapToPixelGrid() end
  function object:SetTexelSnappingBias() end
  function object:SetColorTexture(...) self.color = {...} end
  function object:SetGradient(_, from, to) assert(from.GetRGBA and to.GetRGBA); self.gradient = {from, to} end
  function object:SetAlpha(alpha) self.alpha = alpha end
  function object:Show() self.shown = true end
  function object:Hide() self.shown = false end
  function object:SetBackdrop(value) self.backdrop = value end
  function object:SetBackdropColor(...) self.backdropColor = {...} end
  function object:SetBackdropBorderColor(...) self.borderColor = {...} end
  function object:SetFrameLevel(level) self.level = level end
  function object:GetFrameLevel() return self.level or 1 end
  function object:SetTexture(texture) self.texture = texture end
  function object:SetVertexColor(...) self.vertex = {...} end
  function object:SetTexCoord(...) self.coords = {...} end
  function object:SetDrawLayer(layer) self.layer = layer end
  function object:CreateTexture()
    textures = textures + 1
    return Decorate({})
  end
  return object
end
local originalCreateFrame = CreateFrame
_G.CreateFrame = function(...)
  backdrops = backdrops + 1
  return Decorate(originalCreateFrame(...))
end
assert(loadfile("VisualPrimitives.lua"))("RothChat", NS)
local frame = Decorate(env.frame)
NS.ApplyGlassLook(frame, 0.2)
assert(textures == 3 and frame.glassLeft.shown and frame.glassRight.shown)
NS.HideRothVisuals(frame)
assert(not frame.glassLeft.shown)
NS.ApplyGlassLook(frame, 0.4)
assert(textures == 3 and frame.glassLeft.shown and frame.glassLeft._to.a == 0.4)
NS.ApplyGlassBackdrop(frame, 0.3, 1, 2)
local backdrop = frame.__glassBackdrop
NS.HideRothVisuals(frame)
NS.ApplyGlassBackdrop(frame, 0.6, 3, 4)
assert(backdrops == 1 and backdrop == frame.__glassBackdrop and backdrop.shown)
assert(#backdrop.points == 2 and backdrop.points[1][2] == 3 and backdrop.points[1][3] == -4)
local left, middle, right = NS.CreateHighlight(frame, "HIGHLIGHT", 1, 0.5, 0.2, 0)
assert(textures == 6)
NS.HideRothVisuals(frame)
local reused = NS.CreateHighlight(frame, "OVERLAY", 0.2, 0.4, 0.6, -2)
assert(reused == left and textures == 6 and left.shown and middle.shown and right.shown)
assert(left.vertex[1] == 0.2 and left.layer == "OVERLAY")
print("visual_primitives_spec: ok")
