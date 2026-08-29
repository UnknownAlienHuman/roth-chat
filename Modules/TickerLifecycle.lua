-- RothChat - Ticker lifecycle extension.
-- Rebinds the primary AddMessage feed after Blizzard creates, closes, docks or
-- reconfigures chat frames. Ticker.lua keeps animation/queue ownership.

local ADDON_NAME, NS = ...
local RothChat = _G.RothChat
if not RothChat then return end

local Ticker = RothChat.modules and RothChat.modules.Ticker
if not Ticker then return end

local owner = {}
local refreshKey = {}
local originalEnable = Ticker.OnEnable
local originalDisable = Ticker.OnDisable

local function QueueRefresh(core)
  NS.RunNextFrame(refreshKey, function()
    if core:IsModuleActive("Ticker") and type(Ticker.Refresh) == "function" then
      Ticker:Refresh(core)
    end
  end, "RothChat:TickerLifecycleRefresh")
end

function Ticker:OnEnable(core)
  local result = originalEnable(self, core)

  core:OffOwner(owner)
  core:On("CHAT_FRAME_READY", function(_, core2)
    QueueRefresh(core2)
  end, owner)
  core:On("CHAT_FRAME_CLOSED", function(_, core2)
    QueueRefresh(core2)
  end, owner)
  core:On("CHAT_LAYOUT_CHANGED", function(_, core2)
    QueueRefresh(core2)
  end, owner)

  return result
end

function Ticker:OnDisable(core)
  NS.CancelScheduled(refreshKey)
  core:OffOwner(owner)
  return originalDisable(self, core)
end
