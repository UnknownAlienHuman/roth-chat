-- Shared fades expose conflict-safe owner cancellation without changing legacy callers.
local namedFrames = {}
local now = 100

local function NewFrame(name)
  local frame = { alpha = 0, scripts = {} }
  function frame:GetAlpha() return self.alpha end
  function frame:SetAlpha(value) self.alpha = value end
  function frame:GetScript(script) return self.scripts[script] end
  function frame:SetScript(script, callback) self.scripts[script] = callback end
  namedFrames[name] = frame
  return frame
end

_G.CreateFrame = function(_, name) return NewFrame(name) end
_G.GetTime = function() return now end
_G.canaccessvalue = function() return true end
_G.canaccessallvalues = function() return true end

local NS = {
  CanAccessObject = function(value) return type(value) == "table" end,
  SafeCall = function(_, callback, ...)
    local ok, a, b, c = pcall(callback, ...)
    return ok, a, b, c
  end,
}

assert(loadfile("Util.lua"))("RothChat", NS)
local fader = assert(namedFrames.RothChatFader)
local frame = NewFrame("Target")
local ownerA, ownerB = {}, {}

NS.FadeTo(frame, 1, 1, nil, ownerA)
assert(NS.IsFading(frame) and fader:GetScript("OnUpdate"), "an animated fade must start the shared updater")
assert(not NS.StopOwnedFade(frame, ownerB), "a foreign owner must not cancel the fade")
fader:GetScript("OnUpdate")(fader, 0.5)
assert(frame.alpha > 0 and frame.alpha < 1)

-- Same target with a different owner is a replacement, not callback coalescing.
NS.FadeTo(frame, 1, 1, nil, ownerB)
assert(not NS.StopOwnedFade(frame, ownerA))
assert(NS.StopOwnedFade(frame, ownerB))
assert(not NS.IsFading(frame))
assert(fader:GetScript("OnUpdate") == nil, "stopping the final owned fade must idle the updater")

-- Immediate writes do not leave a stale ownership record.
NS.FadeTo(frame, 0.25, 0, nil, ownerA)
assert(frame.alpha == 0.25)
assert(not NS.StopOwnedFade(frame, ownerA))

-- Legacy unowned fades remain cancellable through the existing API.
NS.FadeTo(frame, 0.75, 1)
assert(not NS.StopOwnedFade(frame, ownerA))
NS.StopFading(frame)
assert(fader:GetScript("OnUpdate") == nil)

print("fade_ownership_spec: ok")
