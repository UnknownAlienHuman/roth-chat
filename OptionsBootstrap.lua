-- RothChat - lazy Blizzard Settings registration.
-- Options.lua remains the sole category/control owner. This file performs one
-- bounded load-order handshake when Blizzard_Settings is not available yet.
local _, NS = ...
local RothChat = _G.RothChat
local buildOptions = RothChat.InitOptions
local waitFrame

local function StopFallbackWaiter()
  if not waitFrame then return end
  waitFrame:UnregisterEvent("ADDON_LOADED")
  waitFrame:SetScript("OnEvent", nil)
  waitFrame = nil
end

local function RegisterOptions()
  if RothChat.optionsCategoryID then
    StopFallbackWaiter()
    return true
  end
  if not _G.Settings or type(buildOptions) ~= "function" then return false end
  StopFallbackWaiter()
  local ok = NS.SafeCall("RothChat:InitOptions", buildOptions, RothChat)
  return ok and RothChat.optionsCategoryID ~= nil
end

if not RegisterOptions() then
  local continueOnLoaded = _G.EventUtil and _G.EventUtil.ContinueOnAddOnLoaded
  if type(continueOnLoaded) == "function" then
    continueOnLoaded("Blizzard_Settings", RegisterOptions)
  else
    waitFrame = CreateFrame("Frame")
    waitFrame:RegisterEvent("ADDON_LOADED")
    waitFrame:SetScript("OnEvent", function(_, _, loadedAddon)
      if NS.CanAccessValue(loadedAddon) and loadedAddon == "Blizzard_Settings" then
        RegisterOptions()
      end
    end)
  end
end
