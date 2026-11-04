-- Actual shared scheduler, cancellation, fade and ordinary-value boundaries.
local env = assert(loadfile("tests/support/runtime.lua"))().New()
local NS, core = env.ns, env.core
assert(NS.SafeToString(env.inaccessible) == "")
assert(NS.Utf8Len(env.inaccessible) == 0 and NS.Utf8Sub(env.inaccessible, 4) == "")
assert(NS.Utf8Len("Привет🙂") == 7)
assert(NS.Utf8Sub("Привет🙂", 3) == "При")
assert(NS.SafeTrunc("Привет🙂", 6) == "Привет...")
assert(NS.SafeTrunc("abc", 3) == "abc")
assert(NS.SafeNumber(0/0, 2) == 2 and NS.SafeNumber(math.huge, 3) == 3)

-- Table access queries are fallible and their result is independently gated.
local source, target = { copied = true }, { preserved = true }
local originalCanAccessTable = canaccesstable
canaccesstable = function(value)
  if value == source then error("denied table query") end
  return originalCanAccessTable(value)
end
assert(NS.CopyTable(source, target) == target and target.preserved and target.copied == nil)
canaccesstable = function(value)
  if value == source then return env.inaccessible end
  return originalCanAccessTable(value)
end
assert(NS.CopyTable(source, target) == target and target.copied == nil)
canaccesstable = originalCanAccessTable
assert(NS.CopyTable(source, target) == target and target.copied == true)

local captured
NS.Schedule("arity", 0, function(...) captured = NS.Pack(...) end, nil, 1, nil, 3, nil)
env:Advance()
assert(captured.n == 4 and captured[1] == 1 and captured[2] == nil and captured[3] == 3)
assert(not NS.Schedule("opaque", 0, function() error("must not run") end, nil, env.inaccessible))
assert(not NS.Schedule(env.inaccessible, 0, function() error("opaque key ran") end))
assert(not NS.Schedule("opaque-label", 0, function() error("opaque label ran") end, env.inaccessible))
NS.CancelScheduled(env.inaccessible)

-- Both jobs are already due. Whichever runs first cancels the other.
local count = 0
NS.Schedule("a", 0, function() count = count + 1; NS.CancelScheduled("b") end)
NS.Schedule("b", 0, function() count = count + 1; NS.CancelScheduled("a") end)
env:Advance()
assert(count == 1, "cancellation must invalidate an already captured due job")

-- Completing a near-target fade cancels the previous animation.
env.frame.alpha = 0
NS.FadeTo(env.frame, 1, 1)
env:Advance(0.1)
local targetAlpha = env.frame.alpha + 0.001
NS.FadeTo(env.frame, targetAlpha, 1)
env:Advance(2)
assert(env.frame.alpha == targetAlpha, "old fade must not overwrite an immediate completion")
env.frame.alpha = env.inaccessible
NS.FadeTo(env.frame, 0, 1)
env:Advance(1)
assert(rawequal(env.frame.alpha, env.inaccessible), "opaque alpha must not be read or replaced")
env.frame.alpha = 1

-- Fade inputs and retained callbacks/owners must already be ordinary.
env.frame.alpha = 0.25
assert(not NS.FadeTo(env.frame, env.inaccessible, 1))
assert(not NS.FadeTo(env.frame, 1, env.inaccessible))
assert(not NS.FadeTo(env.frame, 1, 1, env.inaccessible))
assert(not NS.FadeTo(env.frame, 1, 1, nil, env.inaccessible))
assert(env.frame.alpha == 0.25 and not NS.IsFading(env.frame))

-- Method lookup/invocation failure is isolated per frame and cannot stop a
-- different valid fade sharing the updater.
local badGet = CreateFrame("Frame")
badGet.alpha = 0
function badGet:GetAlpha() error("denied alpha read") end
assert(not NS.FadeTo(badGet, 1, 1))

local badSet = CreateFrame("Frame")
badSet.alpha = 0
function badSet:SetAlpha() error("denied alpha write") end
local good = CreateFrame("Frame")
good.alpha = 0
assert(NS.FadeTo(badSet, 1, 1))
assert(NS.FadeTo(good, 1, 1))
env:Advance(1)
assert(good.alpha == 1 and not NS.IsFading(good))
assert(not NS.IsFading(badSet), "a failing frame must be retired without poisoning the updater")

-- A same-owner request with a different duration is a replacement, not stale
-- callback coalescing with the old timing contract.
local durationOwner = {}
env.frame.alpha = 0
assert(NS.FadeTo(env.frame, 1, 10, nil, durationOwner))
env:Advance(1)
assert(env.frame.alpha > 0 and env.frame.alpha < 1)
assert(NS.FadeTo(env.frame, 1, 1, nil, durationOwner))
env:Advance(1)
assert(env.frame.alpha == 1 and not NS.IsFading(env.frame))

-- A completion queued in the same update remains cancellable by another one.
local fadeA, fadeB, completions = CreateFrame("Frame"), CreateFrame("Frame"), 0
fadeA.alpha, fadeB.alpha = 0, 0
NS.FadeTo(fadeA, 1, 1, function()
  completions = completions + 1
  NS.StopFading(fadeB)
end)
NS.FadeTo(fadeB, 1, 1, function()
  completions = completions + 1
  NS.StopFading(fadeA)
end)
env:Advance(1)
assert(completions == 1, "cancelled completion must not run from an earlier snapshot")
NS.StopFading(env.inaccessible, 0)
NS.StopFading(env.frame, env.inaccessible)
assert(env.frame.alpha == 1, "denied alpha must not replace current presentation")

-- SetAlpha post-hooks may synchronously replace the just-completed fade.
local reverse = CreateFrame("Frame")
reverse.alpha = 0
local setAlpha, reversed = reverse.SetAlpha, false
function reverse:SetAlpha(alpha)
  setAlpha(self, alpha)
  if alpha == 1 and not reversed then
    reversed = true
    NS.FadeTo(self, 0, 1)
  end
end
NS.FadeTo(reverse, 1, 1)
env:Advance(1)
assert(reversed and reverse.alpha == 1)
env:Advance(1)
assert(reverse.alpha == 0, "completion cleanup must preserve the replacement fade")

-- Combat jobs retain one current request per key and preserve nil arity.
local applied
for index = 1, 1000 do
  assert(core:DeferKeyed("layout", function(...) applied = NS.Pack(...) end, index, nil))
end
assert(core._deferredCount == 1 and #core._deferred == 1)
env.combat = true
core:RunDeferred()
assert(applied == nil)
env.combat = false
core:RunDeferred()
assert(applied.n == 2 and applied[1] == 1000 and core._deferredCount == 0)
core:DeferKeyed("cancelled", function() error("cancelled job ran") end)
core:CancelDeferred("cancelled")
core:RunDeferred()
assert(core._deferredCount == 0 and #core._deferred == 0)

print("util_spec: ok")
