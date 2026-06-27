local addonName, ns = ...

local Core = CreateFrame("Frame")
ns.Core = Core
ns.version = "0.1.4"

local refreshUI

local lastRosterSummaryAt = 0
local lastChatSummaryAt = 0
local pendingRescanBurstId = 0

local function runScanAndRefresh()
  ns.Channel.EnsureJoined()
  ns.Channel.ScanRoster()
  if ns.ChatAlert then
    ns.ChatAlert.Refresh()
  end
  refreshUI()
end

local function scheduleRescanBurst()
  pendingRescanBurstId = pendingRescanBurstId + 1
  local burstId = pendingRescanBurstId
  local delays = { 0.5, 1.5, 3.0 }

  for _, delay in ipairs(delays) do
    C_Timer.After(delay, function()
      if burstId ~= pendingRescanBurstId then
        return
      end

      runScanAndRefresh()
    end)
  end
end

local function requestBootstrapSync()
  ns.Comm.SendRosterSummaries(ns.Constants.maxBootstrapDonors)
  ns.Comm.SendChatSummaries(ns.Constants.maxBootstrapDonors)
end

local function refreshLocalProfile(shouldBroadcast)
  local profession1, profession2, profession1Icon, profession2Icon = ns.Utils.SafeProfessions()
  local _, changes = ns.Store.SetProfile(ns.Utils.PlayerName(), {
    level = ns.Utils.SafeLevel(),
    classFile = ns.Utils.SafeClassFile(),
    zone = ns.Utils.SafeZoneName(),
    guildName = ns.Utils.SafeGuildName(),
    profession1 = profession1,
    profession2 = profession2,
    profession1Icon = profession1Icon,
    profession2Icon = profession2Icon,
  }, ns.Utils.Now())

  if shouldBroadcast and changes then
    ns.Comm.BroadcastInfo()
  end

  return changes
end

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
      "debug channelId=%s displayIndex=%s visibleCount=%s memberCount=%s resolvedCount=%s stableScans=%s bestEffort=%s scanOk=%s reason=%s",
      tostring(status.channelId),
      tostring(status.displayIndex),
      tostring(status.visibleCount),
      tostring(status.lastMemberCount),
      tostring(status.lastResolvedCount),
      tostring(status.stableScanCount),
      tostring(status.bestEffort),
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

    local onlineMembers = {}
    for _, member in pairs(ns.Store.GetRoster()) do
      if member.isOnlineInChannel then
        onlineMembers[#onlineMembers + 1] = member
      end
    end

    table.sort(onlineMembers, function(left, right)
      return left.name < right.name
    end)

    ns.Utils.Print("local online roster count: " .. tostring(#onlineMembers))
    for _, member in ipairs(onlineMembers) do
      ns.Utils.Print(string.format(
        "member name=%s addon=%s online=%s level=%s class=%s zone=%s guild=%s lastSeen=%s lastObserved=%s lastAddonSeen=%s sources=chat:%s notice:%s who:%s",
        tostring(member.name),
        tostring(member.hasAddon),
        tostring(member.isOnlineInChannel),
        tostring(member.level or 0),
        tostring(member.classFile or ""),
        tostring(member.zone or ""),
        tostring(member.guildName or ""),
        tostring(member.lastSeenAt or 0),
        tostring(member.lastObservedAt or 0),
        tostring(member.lastAddonSeenAt or 0),
        tostring(member.observedByChat),
        tostring(member.observedByNotice),
        tostring(member.observedByWho)
      ))
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
  ns.Store.ResetTransientState()
  ns.History.Init()
  refreshLocalProfile(false)
  ns.Comm.RegisterPrefix()
  ns.MinimapButton.Create()
  ns.ChatAlert.Create()
  ns.ChatAlert.Refresh()

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
    refreshLocalProfile(true)
    runScanAndRefresh()
    requestBootstrapSync()
    scheduleRescanBurst()
  end)
end

Core:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    initialize()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    refreshLocalProfile(true)
    ns.Channel.EnsureJoined()
    C_Timer.After(2, function()
      runScanAndRefresh()
      requestBootstrapSync()
      scheduleRescanBurst()
    end)
    return
  end

  if event == "SKILL_LINES_CHANGED" then
    refreshLocalProfile(true)
    if ns.ChatAlert then
      ns.ChatAlert.Refresh()
    end
    refreshUI()
    return
  end

  if event == "PLAYER_LOGOUT" then
    ns.Comm.BroadcastBye()
    return
  end

  if event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
    if event == "CHAT_MSG_CHANNEL_NOTICE" then
      local text, playerName, _, channelName, playerName2, _, _, _, channelBaseName = ...
      if ns.Utils.IsTargetChannel(channelName, channelBaseName) and ns.Utils.IsJoinOrLeaveNotice(text) then
        local targetName = ns.Utils.NormalizeName(playerName2)
        local sourceName = ns.Utils.NormalizeName(playerName)
        local name = targetName or sourceName

        if name and name ~= ns.Utils.PlayerName() then
          if text == "JOINED" or text == "YOU_JOINED" or text == "YOU_CHANGED" then
            local member, justJoined = ns.Store.MarkObservedByNotice(name, ns.Utils.Now())
            if justJoined then
              ns.History.Add("joined_channel", name)
            end
            if member and member.hasAddon then
              ns.Comm.QueueProfileRequest(name)
            end
          elseif text == "LEFT" or text == "YOU_LEFT" then
            local now = ns.Utils.Now()
            local member = ns.Store.GetMember(name)
            if member then
              if now > (member.lastSeenAt or 0) then
                member.lastSeenAt = now
              end
              if now > (member.lastObservedAt or 0) then
                member.lastObservedAt = now
              end
              if now > (member.lastObservedByNoticeAt or 0) then
                member.lastObservedByNoticeAt = now
              end
            end
            ns.Store.MarkOffline(name)
            ns.History.Add("left_channel", name)
          end
        end
      end
    end

      if ns.ChatAlert then
        ns.ChatAlert.Refresh()
      end

      runScanAndRefresh()
      scheduleRescanBurst()
      return
  end

  if event == "CHAT_MSG_CHANNEL" then
    local message, sender, _, channelName, _, _, _, _, channelBaseName, _, lineId = ...
    if ns.Utils.IsTargetChannel(channelName, channelBaseName) then
      local member, justJoined = ns.Store.MarkObservedInChannel(sender, ns.Utils.Now())
      local normalizedSender = ns.Utils.NormalizeName(sender)
      if justJoined and ns.Utils.NormalizeName(sender) ~= ns.Utils.PlayerName() then
        ns.History.Add("joined_channel", sender)
      end
      if member and member.name ~= ns.Utils.PlayerName() and member.hasAddon then
        ns.Comm.QueueProfileRequest(member.name)
      end
      ns.History.AddChannelMessage(sender, message, lineId)
      if ns.ChatAlert then
        if normalizedSender and normalizedSender ~= ns.Utils.PlayerName() then
          ns.ChatAlert.MarkPendingChat()
        end
        ns.ChatAlert.Refresh()
      end
      refreshUI()
    end
    return
  end

  if event == "CHAT_MSG_ADDON" then
    ns.Comm.HandleAddonMessage(...)
    if ns.ChatAlert then
      ns.ChatAlert.Refresh()
    end
    refreshUI()
    return
  end

  if event == "WHO_LIST_UPDATE" then
    ns.Who.HandleWhoListUpdate()
    if ns.ChatAlert then
      ns.ChatAlert.Refresh()
    end
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

  local now = ns.Utils.Now()
  ns.Comm.ProbeOnlineAddonMembers(now)
  if now - lastRosterSummaryAt >= ns.Constants.rosterSummaryInterval then
    ns.Comm.SendRosterSummaries(ns.Constants.maxPeriodicDonors)
    lastRosterSummaryAt = now
  end

  if now - lastChatSummaryAt >= ns.Constants.chatSummaryInterval then
    ns.Comm.SendChatSummaries(ns.Constants.maxPeriodicDonors)
    lastChatSummaryAt = now
  end

  if ns.Channel.ShouldScan() then
    runScanAndRefresh()
  end
end)

Core:RegisterEvent("PLAYER_LOGIN")
Core:RegisterEvent("PLAYER_ENTERING_WORLD")
Core:RegisterEvent("PLAYER_LOGOUT")
Core:RegisterEvent("SKILL_LINES_CHANGED")
Core:RegisterEvent("CHANNEL_UI_UPDATE")
Core:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Core:RegisterEvent("CHAT_MSG_CHANNEL")
Core:RegisterEvent("CHAT_MSG_ADDON")
Core:RegisterEvent("WHO_LIST_UPDATE")
