-- RothChat - Controls ownership extension.
-- Preserves the Blizzard/previous-addon mouse-wheel state that Controls
-- temporarily replaces while active.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local Controls = RothChat.modules and RothChat.modules.Controls
if not Controls then return end

local owner = {}
local originalEnable = Controls.OnEnable
local originalDisable = Controls.OnDisable

local function CaptureWheelState(chatFrame)
  if not chatFrame or chatFrame.__rothWheelOwnershipCaptured then return end
  chatFrame.__rothWheelOwnershipCaptured = true

  if type(chatFrame.IsMouseWheelEnabled) == "function" then
    local ok, enabled = pcall(chatFrame.IsMouseWheelEnabled, chatFrame)
    if ok then chatFrame.__rothOriginalMouseWheelEnabled = enabled and true or false end
  end
end

local function RestoreWheelState(chatFrame)
  if not chatFrame then return end

  if type(chatFrame.GetScript) == "function" and type(chatFrame.SetScript) == "function" then
    local current = chatFrame:GetScript("OnMouseWheel")
    if current == chatFrame.__rothMouseWheelHandler then
      chatFrame:SetScript("OnMouseWheel", chatFrame.__rothOriginalMouseWheelScript)
    end
  end

  if chatFrame.__rothOriginalMouseWheelEnabled ~= nil and type(chatFrame.EnableMouseWheel) == "function" then
    chatFrame:EnableMouseWheel(chatFrame.__rothOriginalMouseWheelEnabled)
  end

  chatFrame.__rothOriginalMouseWheelEnabled = nil
  chatFrame.__rothWheelOwnershipCaptured = nil
end

function Controls:OnEnable(core)
  -- Register before Controls' own CHAT_FRAME_READY listener so newly created
  -- frames are snapshotted before HookScroll enables/replaces their wheel path.
  core:OffOwner(owner)
  core:On("CHAT_FRAME_READY", function(_, _, chatFrame)
    CaptureWheelState(chatFrame)
  end, owner)

  for _, chatFrame in ipairs(NS.GetActiveChatFrames()) do
    CaptureWheelState(chatFrame)
  end

  return originalEnable(self, core)
end

function Controls:OnDisable(core)
  local result = originalDisable(self, core)
  core:OffOwner(owner)

  for _, chatFrame in ipairs(NS.GetChatFrames()) do
    RestoreWheelState(chatFrame)
  end
  return result
end
