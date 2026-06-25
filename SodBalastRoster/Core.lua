local addonName, ns = ...

local Core = CreateFrame("Frame")
ns.Core = Core
ns.version = "0.1.0"

local refreshUI

local function safeCreateUI()
  local ok, result = pcall(ns.UI.Create)
  if not ok then
    ns.Utils.Print("UI create error: " .. tostring(result))
    return nil
  end

  return result
end

local function runDebug()
  ns.Utils.Print("running debug scan")
  Core.lastDebugSummary = "running debug scan"

  local ok, err = pcall(function()
    ns.Channel.EnsureJoined()
    local scanOk, reason = ns.Channel.ScanRoster()
    local status = ns.Channel.DebugStatus()
    local summary = string.format(
      "debug channelId=%s displayIndex=%s visibleCount=%s memberCount=%s resolvedCount=%s scanOk=%s reason=%s",
      tostring(status.channelId),
      tostring(status.displayIndex),
      tostring(status.visibleCount),
      tostring(status.lastMemberCount),
      tostring(status.lastResolvedCount),
      tostring(scanOk),
      tostring(reason)
    )

    Core.lastDebugSummary = summary
    ns.Utils.Print(summary)

    if status.lastResolvedNames and #status.lastResolvedNames > 0 then
      ns.Utils.Print("resolved names: " .. table.concat(status.lastResolvedNames, ", "))
    end

    if status.lastFallbackPlayer then
      ns.Utils.Print("fallback candidate: " .. tostring(status.lastFallbackPlayer))
    end
  end)

  if not ok then
    Core.lastDebugSummary = "debug error: " .. tostring(err)
    ns.Utils.Print("debug error: " .. tostring(err))
  end

  refreshUI()
end

Core.RunDebug = runDebug

local function handleSlashCommand(message)
  message = ns.Utils.Trim(message or "")

  if message == "debug" then
    runDebug()
    return
  end

  local frame = safeCreateUI()
  if not frame then
    return
  end

  ns.UI.Toggle()
end

refreshUI = function()
  if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
    ns.UI.Refresh()
  end
end

local function initialize()
  ns.Store.Init()
  ns.History.Init()
  ns.Store.SetProfile(ns.Utils.PlayerName(), {
    level = ns.Utils.SafeLevel(),
    classFile = ns.Utils.SafeClassFile(),
    zone = ns.Utils.SafeZoneName(),
    guildName = ns.Utils.SafeGuildName(),
  }, ns.Utils.Now())
  ns.Comm.RegisterPrefix()

  SLASH_SODBALASTROSTER1 = "/sb"
  SLASH_SODBALASTROSTER2 = "/sbr"
  SlashCmdList.SODBALASTROSTER = function(message)
    handleSlashCommand(message)
  end

  SLASH_SODBALASTROSTERDEBUG1 = "/sbd"
  SlashCmdList.SODBALASTROSTERDEBUG = function()
    runDebug()
  end

  ns.Channel.EnsureJoined()
  ns.Utils.Print("loaded. Use /sb to open, /sbd or Debug for channel diagnostics.")
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

  if event == "PLAYER_LOGOUT" then
    ns.Comm.BroadcastBye()
    return
  end

  if event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
    ns.Channel.ScanRoster()
    refreshUI()
    return
  end

  if event == "CHAT_MSG_CHANNEL" then
    local message, sender, _, channelName, _, _, _, _, channelBaseName = ...
    if ns.Utils.IsTargetChannel(channelName, channelBaseName) then
      ns.History.AddChannelMessage(sender, message)
      refreshUI()
    end
    return
  end

  if event == "CHAT_MSG_ADDON" then
    ns.Comm.HandleAddonMessage(...)
    refreshUI()
    return
  end

  if event == "WHO_LIST_UPDATE" then
    ns.Who.HandleWhoListUpdate()
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
  ns.Who.CheckTimeout()
  ns.Comm.MaybeBroadcastHistorySummary()

  if ns.Channel.ShouldScan() then
    ns.Channel.EnsureJoined()
    ns.Channel.ScanRoster()
    refreshUI()
  end
end)

Core:RegisterEvent("PLAYER_LOGIN")
Core:RegisterEvent("PLAYER_ENTERING_WORLD")
Core:RegisterEvent("PLAYER_LOGOUT")
Core:RegisterEvent("CHANNEL_UI_UPDATE")
Core:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Core:RegisterEvent("CHAT_MSG_CHANNEL")
Core:RegisterEvent("CHAT_MSG_ADDON")
Core:RegisterEvent("WHO_LIST_UPDATE")
