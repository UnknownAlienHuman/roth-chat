-- Mutation contracts exercise the real production registries and native hook.
local env = assert(loadfile("tests/support/runtime.lua"))().New()
local core, registeredFilters = env.core, env.filters

-- Event bus: removing the next listener must not skip the independent tail;
-- additions begin with the next outer dispatch only.
do
  local calls = {}
  local ownerA, ownerB, ownerC, ownerD = {}, {}, {}, {}
  local added = false

  core:On("BUS", function()
    calls[#calls + 1] = "A"
    core:OffOwner(ownerB)
    if not added then
      added = true
      core:On("BUS", function() calls[#calls + 1] = "D" end, ownerD)
    end
  end, ownerA)
  core:On("BUS", function() calls[#calls + 1] = "B" end, ownerB)
  core:On("BUS", function() calls[#calls + 1] = "C" end, ownerC)

  core:Emit("BUS")
  assert(table.concat(calls) == "AC")
  calls = {}
  core:Emit("BUS")
  assert(table.concat(calls) == "ACD")
end

-- Message filters preserve the tuple while allowing removal/addition during the
-- same event without skipping later callbacks.
do
  local event = "CHAT_MSG_SAY"
  local ownerA, ownerB, ownerC, ownerD = {}, {}, {}, {}
  local calls = {}
  local added = false

  core:RegisterMessageFilter(ownerA, event, function(_, _, text)
    calls[#calls + 1] = "A"
    core:UnregisterMessageFilters(ownerB)
    if not added then
      added = true
      core:RegisterMessageFilter(ownerD, event, function(_, _, value)
        calls[#calls + 1] = "D"
        return false, value .. "D"
      end, 25)
    end
    return false, text .. "A"
  end, 10)
  core:RegisterMessageFilter(ownerB, event, function(_, _, text)
    calls[#calls + 1] = "B"
    return false, text .. "B"
  end, 20)
  core:RegisterMessageFilter(ownerC, event, function(_, _, text)
    calls[#calls + 1] = "C"
    return false, text .. "C"
  end, 30)

  local dispatcher = assert(registeredFilters[event])
  local discard, text, sender, trailing = dispatcher(nil, event, "x", "sender", nil)
  assert(discard == false)
  assert(text == "xAC" and sender == "sender" and trailing == nil)
  assert(table.concat(calls) == "AC")

  calls = {}
  discard, text, sender, trailing = dispatcher(nil, event, "x", "sender", nil)
  assert(discard == false)
  assert(text == "xADC" and sender == "sender" and trailing == nil)
  assert(table.concat(calls) == "ADC")
end

-- Additions begin on the next message; removals take effect during dispatch.
do
  local calls = {}
  local ownerA, ownerB, ownerC, ownerD = {}, {}, {}, {}
  local added = false
  core:RegisterAddMessageHook(function()
    calls[#calls + 1] = "A"
    core:UnregisterAddMessageHooks(ownerB)
    if not added then
      added = true
      core:RegisterAddMessageHook(function() calls[#calls + 1] = "D" end, ownerD, 25)
    end
  end, ownerA, 10)
  core:RegisterAddMessageHook(function() calls[#calls + 1] = "B" end, ownerB, 20)
  core:RegisterAddMessageHook(function() calls[#calls + 1] = "C" end, ownerC, 30)
  env.frame:AddMessage("message")
  assert(table.concat(calls) == "AC")
  calls = {}
  env.frame:AddMessage("message")
  assert(table.concat(calls) == "ADC")
  for _, owner in ipairs({ownerA, ownerB, ownerC, ownerD}) do core:UnregisterAddMessageHooks(owner) end
end

-- Opaque colors are omitted; trailing line/access metadata never reaches modules.
do
  local owner, calls = {}, 0
  core:RegisterAddMessageHook(function(...)
    calls = calls + 1
    assert(select("#", ...) == 5)
    local frame, text, r, g, b = ...
    assert(frame == env.frame and text == "message")
    assert(r == nil and g == 0.5 and b == 1)
  end, owner)
  env.frame:AddMessage("message", env.inaccessible, 0.5, 9, env.inaccessible, "lineID")
  assert(calls == 1)
  env.restricted = true
  env.frame:AddMessage("message", 1, 1, 1)
  env.restricted = false
  env.frame.inaccessible = true
  env.frame:AddMessage("message", 1, 1, 1)
  env.frame.inaccessible = nil
  env.frame:AddMessage(env.inaccessible, 1, 1, 1)
  assert(calls == 1)
  core:UnregisterAddMessageHooks(owner)
end

-- Diagnostics do not recursively re-enter a failing message consumer.
do
  local calls, owner = 0, {}
  core:RegisterAddMessageHook(function() calls = calls + 1; error(env.inaccessible) end, owner)
  env.frame:AddMessage("message")
  assert(calls == 1)
  core:UnregisterAddMessageHooks(owner)
end

-- A denied native AddMessage hook is terminal for that frame lifetime. Native
-- layout updates must not turn one denied operation into a retry/error loop.
do
  local denied = { AddMessage = function() end }
  local attempts = 0
  local originalHook = hooksecurefunc
  hooksecurefunc = function(target, method, callback)
    if target == denied and method == "AddMessage" then
      attempts = attempts + 1
      error("denied")
    end
    return originalHook(target, method, callback)
  end
  core:EnsureAddMsgHookForFrame(denied)
  core:EnsureAddMsgHookForFrame(denied)
  hooksecurefunc = originalHook
  assert(attempts == 1, "denied AddMessage hooks must not be retried")
  assert(core._addMsgHooked[denied] == false)
end

print("core_dispatch_mutation_spec: ok")
