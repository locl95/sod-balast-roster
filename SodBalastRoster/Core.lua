local addonName, ns = ...

local Core = CreateFrame("Frame")
ns.Core = Core

local function refreshUI()
  if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
    ns.UI.Refresh()
  end
end

local function initialize()
  ns.Store.Init()
  ns.Store.SetProfile(ns.Utils.PlayerName(), {
    level = ns.Utils.SafeLevel(),
    classFile = ns.Utils.SafeClassFile(),
    zone = ns.Utils.SafeZoneName(),
    guildName = ns.Utils.SafeGuildName(),
  }, ns.Utils.Now())
  ns.Comm.RegisterPrefix()
  ns.UI.Create()

  SLASH_SODBALASTROSTER1 = "/sb"
  SLASH_SODBALASTROSTER2 = "/sbr"
  SlashCmdList.SODBALASTROSTER = function()
    ns.UI.Toggle()
  end

  ns.Channel.EnsureJoined()
  C_Timer.After(2, function()
    ns.Channel.ScanRoster()
    refreshUI()
  end)
end

Core:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    initialize()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    ns.Channel.EnsureJoined()
    return
  end

  if event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
    ns.Channel.ScanRoster()
    refreshUI()
    return
  end

  if event == "CHAT_MSG_ADDON" then
    ns.Comm.HandleAddonMessage(...)
    refreshUI()
  end
end)

Core.elapsed = 0
Core:SetScript("OnUpdate", function(_, elapsed)
  Core.elapsed = Core.elapsed + elapsed
  if Core.elapsed < 1 then
    return
  end

  Core.elapsed = 0
  ns.Comm.FlushQueue()

  if ns.Channel.ShouldScan() then
    ns.Channel.EnsureJoined()
    ns.Channel.ScanRoster()
    refreshUI()
  end
end)

Core:RegisterEvent("PLAYER_LOGIN")
Core:RegisterEvent("PLAYER_ENTERING_WORLD")
Core:RegisterEvent("CHANNEL_UI_UPDATE")
Core:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Core:RegisterEvent("CHAT_MSG_ADDON")
