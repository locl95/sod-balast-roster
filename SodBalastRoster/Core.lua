local addonName, ns = ...

local Core = CreateFrame("Frame")
ns.Core = Core
ns.version = "0.1.6"

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
  local donors = ns.Store.SelectBootstrapDonors(ns.Constants.maxBootstrapDonors)
  for _, donor in ipairs(donors) do
    ns.Comm.QueueHello(donor, "bootstrap")
    ns.Comm.SendRosterSummary(donor)
    ns.Comm.SendChatSummary(donor)
  end
end

local function getNoticeCandidateNames(playerName, playerName2)
  local names = {}
  local seen = {}

  local function addName(name)
    name = ns.Utils.NormalizeName(name)
    if not name or seen[name] then
      return
    end

    seen[name] = true
    names[#names + 1] = name
  end

  addName(playerName)
  addName(playerName2)
  return names
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

local function printCommDebugLogs(limit)
  local logs = ns.Store.GetCommDebugLogs()
  local count = #logs
  limit = math.max(1, tonumber(limit) or 20)

  ns.Utils.Print(string.format("comm debug logs: showing %d of %d", math.min(limit, count), count))
  local startIndex = math.max(1, count - limit + 1)
  for index = startIndex, count do
    local entry = logs[index]
    ns.Utils.Print(string.format(
      "[%s] %s %s %s%s",
      date("%H:%M:%S", entry.at or ns.Utils.Now()),
      tostring(entry.direction or "?"),
      tostring(entry.peer or "?"),
      tostring(entry.payload or ""),
      entry.context and entry.context ~= "" and string.format(" [%s]", entry.context) or ""
    ))
  end
end

local function printNoticeDebugLogs(limit)
  local logs = ns.Store.GetNoticeDebugLogs()
  local count = #logs
  limit = math.max(1, tonumber(limit) or 20)

  ns.Utils.Print(string.format("notice debug logs: showing %d of %d", math.min(limit, count), count))
  local startIndex = math.max(1, count - limit + 1)
  for index = startIndex, count do
    local entry = logs[index]
    ns.Utils.Print(string.format(
      "[%s] %s text=%s player=%s player2=%s channel=%s base=%s raw=%s",
      date("%H:%M:%S", entry.at or ns.Utils.Now()),
      tostring(entry.event or "?"),
      tostring(entry.text or ""),
      tostring(entry.playerName or ""),
      tostring(entry.playerName2 or ""),
      tostring(entry.channelName or ""),
      tostring(entry.channelBaseName or ""),
      tostring(entry.raw or "")
    ))
  end
end

local function handleDebugCommCommand(argument)
  argument = ns.Utils.Trim(argument or "")

  if argument == "on" then
    ns.Store.SetCommDebugEnabled(true)
    ns.Utils.Print("comm debug enabled")
    return
  end

  if argument == "off" then
    ns.Store.SetCommDebugEnabled(false)
    ns.Utils.Print("comm debug disabled")
    return
  end

  if argument == "clear" then
    ns.Store.ClearCommDebugLogs()
    ns.Utils.Print("comm debug logs cleared")
    return
  end

  if argument == "" or argument == "show" then
    printCommDebugLogs(20)
    return
  end

  local showLimit = string.match(argument, "^show%s+(%d+)$")
  if showLimit then
    printCommDebugLogs(tonumber(showLimit))
    return
  end

  ns.Utils.Print("usage: /sb debug comm on|off|show [n]|clear")
end

local function handleDebugNoticeCommand(argument)
  argument = ns.Utils.Trim(argument or "")

  if argument == "on" then
    ns.Store.SetNoticeDebugEnabled(true)
    ns.Utils.Print("notice debug enabled")
    return
  end

  if argument == "off" then
    ns.Store.SetNoticeDebugEnabled(false)
    ns.Utils.Print("notice debug disabled")
    return
  end

  if argument == "clear" then
    ns.Store.ClearNoticeDebugLogs()
    ns.Utils.Print("notice debug logs cleared")
    return
  end

  if argument == "" or argument == "show" then
    printNoticeDebugLogs(20)
    return
  end

  local showLimit = string.match(argument, "^show%s+(%d+)$")
  if showLimit then
    printNoticeDebugLogs(tonumber(showLimit))
    return
  end

  ns.Utils.Print("usage: /sb debug notice on|off|show [n]|clear")
end

local function logNoticeDebug(eventName, text, playerName, channelName, playerName2, channelBaseName)
  if not ns.Store.IsNoticeDebugEnabled() then
    return
  end

  ns.Store.AppendNoticeDebugLog({
    at = ns.Utils.Now(),
    event = eventName,
    text = text,
    playerName = playerName,
    playerName2 = playerName2,
    channelName = channelName,
    channelBaseName = channelBaseName,
    raw = table.concat({
      tostring(text or ""),
      tostring(playerName or ""),
      tostring(channelName or ""),
      tostring(playerName2 or ""),
      tostring(channelBaseName or ""),
    }, " | "),
  })
end

Core.RunDebug = runDebug

local function handleSlashCommand(message)
  message = ns.Utils.Trim(message or "")

  if message == "debug" then
    runDebug()
    return
  end

  local debugCommand = string.match(message, "^debug%s+(.+)$")
  if debugCommand then
    local subcommand, argument = string.match(debugCommand, "^(%S+)%s*(.-)$")
    if subcommand == "comm" then
      handleDebugCommCommand(argument)
      return
    end
    if subcommand == "notice" then
      handleDebugNoticeCommand(argument)
      return
    end
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

  if event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" or event == "CHAT_MSG_CHANNEL_NOTICE_USER" then
    if event == "CHAT_MSG_CHANNEL_NOTICE" or event == "CHAT_MSG_CHANNEL_NOTICE_USER" then
      local text, playerName, _, channelName, playerName2, _, _, _, channelBaseName = ...
      logNoticeDebug(event, text, playerName, channelName, playerName2, channelBaseName)
      if ns.Utils.IsTargetChannel(channelName, channelBaseName) and ns.Utils.IsJoinOrLeaveNotice(text) then
        local now = ns.Utils.Now()
        local names = getNoticeCandidateNames(playerName, playerName2)

        for _, name in ipairs(names) do
          if name ~= ns.Utils.PlayerName() then
            if text == "JOINED" or text == "YOU_JOINED" or text == "YOU_CHANGED" or text == "CHANGED" then
              local member, justJoined = ns.Store.MarkObservedByNotice(name, now)
              if justJoined then
                ns.History.Add("joined_channel", name)
              end
              if member and member.hasAddon then
                ns.Comm.QueueProfileRequest(name)
              else
                ns.Comm.ProbeObservedPeer(name, now)
              end
            elseif text == "LEFT" or text == "YOU_LEFT" then
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
      local now = ns.Utils.Now()
      local member, justJoined = ns.Store.MarkObservedInChannel(sender, now)
      local normalizedSender = ns.Utils.NormalizeName(sender)
      if justJoined and ns.Utils.NormalizeName(sender) ~= ns.Utils.PlayerName() then
        ns.History.Add("joined_channel", sender)
      end
      if member and member.name ~= ns.Utils.PlayerName() and member.hasAddon then
        ns.Comm.QueueProfileRequest(member.name)
      elseif normalizedSender and normalizedSender ~= ns.Utils.PlayerName() then
        ns.Comm.ProbeObservedPeer(normalizedSender, now)
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
Core:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")
Core:RegisterEvent("CHAT_MSG_CHANNEL")
Core:RegisterEvent("CHAT_MSG_ADDON")
Core:RegisterEvent("WHO_LIST_UPDATE")
