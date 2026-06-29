local addonName, ns = ...

local Core = CreateFrame("Frame")
ns.Core = Core
ns.version = "0.1.5"

local refreshUI

local lastRosterSummaryAt = 0
local lastChatSummaryAt = 0
local pendingRescanBurstId = 0
local bootstrapHelloSent = false

local function runScanAndRefresh()
  ns.Channel.EnsureJoined()
  ns.Store.MarkSelfInChannel(ns.Utils.Now())
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
  ns.Comm.SetBootstrapSyncBudget(ns.Constants.maxBootstrapDonors)
  bootstrapHelloSent = true
  ns.Comm.BroadcastHello()
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



local function handleSlashCommand(message)
  message = ns.Utils.Trim(message or "")

  local debugCommand = string.match(message, "^debug%s+(.+)$")
  if debugCommand then
    local subcommand, argument = string.match(debugCommand, "^(%S+)%s*(.-)$")
    if subcommand == "comm" then
      handleDebugCommCommand(argument)
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

  ns.Channel.EnsureJoined()
  ns.Utils.Print("loaded. Use /sb to open.")
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

  if event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then
    -- fires at the START of the logout/quit countdown, while still fully connected
    ns.Comm.BroadcastBye()
    return
  end

  if event == "PLAYER_LOGOUT" then
    -- last-ditch fallback; delivery not guaranteed at this point
    ns.Comm.BroadcastBye()
    return
  end

  if event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
    if event == "CHAT_MSG_CHANNEL_NOTICE" then
      local text, _, _, channelName, _, _, _, _, channelBaseName = ...
      if ns.Utils.IsTargetChannel(channelName, channelBaseName) then
        if (text == "YOU_JOINED" or text == "YOU_CHANGED") and not bootstrapHelloSent then
          bootstrapHelloSent = true
          ns.Comm.BroadcastHello()
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

  local timedOutMembers = ns.Store.DowngradeMissingAddonResponses(now)
  if #timedOutMembers > 0 then
    for _, member in ipairs(timedOutMembers) do
      if member.name ~= ns.Utils.PlayerName() then
        ns.History.Add("left_channel", member.name, "addon_timeout")
      end
    end
    refreshUI()
  end

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

  refreshUI()
end)

Core:RegisterEvent("PLAYER_LOGIN")
Core:RegisterEvent("PLAYER_ENTERING_WORLD")
Core:RegisterEvent("PLAYER_CAMPING")
Core:RegisterEvent("PLAYER_QUITING")
Core:RegisterEvent("PLAYER_LOGOUT")
Core:RegisterEvent("SKILL_LINES_CHANGED")
Core:RegisterEvent("CHANNEL_UI_UPDATE")
Core:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Core:RegisterEvent("CHAT_MSG_CHANNEL")
Core:RegisterEvent("CHAT_MSG_ADDON")
Core:RegisterEvent("WHO_LIST_UPDATE")
