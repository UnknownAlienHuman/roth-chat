-- RothChat - lazy Blizzard Settings registration.
-- Options.lua owns category/control construction; this file owns only the
-- one-shot addon-load handshake needed when Blizzard_Settings loads later.
local _, NS = ...
local RothChat = _G.RothChat

local buildOptions = RothChat.InitOptions
local waiting = false
local waitFrame

local function StopFallbackWaiter()
  if not waitFrame then return end
  waitFrame:UnregisterEvent("ADDON_LOADED")
  waitFrame:SetScript("OnEvent", nil)
  waitFrame = nil
end

local function RegisterOptions()
  if RothChat.optionsCategoryID then
    waiting = false
    StopFallbackWaiter()
    return true
  end
  if not _G.Settings or type(buildOptions) ~= "function" then return false end
  waiting = false
  StopFallbackWaiter()
  local ok = NS.SafeCall("RothChat:InitOptions", buildOptions, RothChat)
  return ok and RothChat.optionsCategoryID ~= nil
end

local function WaitForSettings()
  if RegisterOptions() then return true end
  if waiting then return false end
  waiting = true

  local continueOnLoaded = _G.EventUtil and _G.EventUtil.ContinueOnAddOnLoaded
  if type(continueOnLoaded) == "function" then
    continueOnLoaded("Blizzard_Settings", RegisterOptions)
    return false
  end

  waitFrame = CreateFrame("Frame")
  waitFrame:RegisterEvent("ADDON_LOADED")
  waitFrame:SetScript("OnEvent", function(_, _, loadedAddon)
    if NS.CanAccessValue(loadedAddon) and loadedAddon == "Blizzard_Settings" then
      RegisterOptions()
    end
  end)
  return false
end

function RothChat:InitOptions()
  return WaitForSettings()
end
