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

local captured
NS.Schedule("arity", 0, function(...) captured = NS.Pack(...) end, nil, 1, nil, 3, nil)
env:Advance()
assert(captured.n == 4 and captured[1] == 1 and captured[2] == nil and captured[3] == 3)
assert(not NS.Schedule("opaque", 0, function() error("must not run") end, nil, env.inaccessible))

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
local target = env.frame.alpha + 0.001
NS.FadeTo(env.frame, target, 1)
env:Advance(2)
assert(env.frame.alpha == target, "old fade must not overwrite an immediate completion")
env.frame.alpha = env.inaccessible
NS.FadeTo(env.frame, 0, 1)
env:Advance(1)
assert(rawequal(env.frame.alpha, env.inaccessible), "opaque alpha must not be read or replaced")
env.frame.alpha = 1

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
