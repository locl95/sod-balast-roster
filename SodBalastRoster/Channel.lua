local addonName, ns = ...

local Utils = ns.Utils
local Store = ns.Store
local History = ns.History
local Channel = {
  lastScanAt = 0,
  lastScanOk = false,
  lastScanReason = "not_scanned",
  lastMemberCount = 0,
  lastResolvedCount = 0,
  lastResolvedNames = {},
  lastFallbackPlayer = nil,
}
ns.Channel = Channel

local function getChannelRosterName(channelIndex, rosterIndex)
  if C_ChatInfo and C_ChatInfo.GetChannelRosterInfo then
    local name = C_ChatInfo.GetChannelRosterInfo(channelIndex, rosterIndex)
    return name
  end

  if GetChannelRosterInfo then
    local name = GetChannelRosterInfo(channelIndex, rosterIndex)
    return name
  end

  return nil
end

function Channel.EnsureJoined()
  local channelId = Channel.GetChannelId()
  if channelId and channelId > 0 then
    return channelId
  end

  JoinPermanentChannel(ns.Constants.channelName)
  return 0
end

function Channel.GetChannelId()
  local channelId = select(1, GetChannelName(ns.Constants.channelName))
  if channelId and channelId > 0 then
    return channelId
  end
  return 0
end

function Channel.FindDisplayIndex()
  local channelId = Channel.GetChannelId()
  local count = GetNumDisplayChannels and GetNumDisplayChannels() or 0
  for index = 1, count do
    local name, header, _, channelNumber = GetChannelDisplayInfo(index)
    if not header and (name == ns.Constants.channelName or channelNumber == channelId) then
      return index
    end
  end
  return nil
end

function Channel.ScanRoster()
  local timestamp = Utils.Now()
  Channel.lastScanAt = timestamp

  local channelId = Channel.GetChannelId()
  local displayIndex = Channel.FindDisplayIndex()
  if not displayIndex then
    Channel.lastScanOk = false
    Channel.lastScanReason = "channel_not_visible"
    Channel.lastMemberCount = 0
    Channel.lastResolvedCount = 0
    Channel.lastResolvedNames = {}
    Channel.lastFallbackPlayer = nil
    return false, "channel_not_visible"
  end

  if SetSelectedDisplayChannel then
    SetSelectedDisplayChannel(displayIndex)
  end

  local _, _, _, _, memberCount = GetChannelDisplayInfo(displayIndex)
  local activeNames = {}
  local resolvedNames = {}
  Channel.lastMemberCount = memberCount or 0
  Channel.lastFallbackPlayer = nil

  for rosterIndex = 1, memberCount or 0 do
    local name = getChannelRosterName(displayIndex, rosterIndex)
    name = Utils.NormalizeName(name)

    if name then
      activeNames[name] = true
      resolvedNames[#resolvedNames + 1] = name
      local member, justJoined = Store.MarkSeenInChannel(name, timestamp)
      if justJoined then
        History.Add("joined_channel", name)
      end

      if member and member.name ~= Utils.PlayerName() and Store.ShouldRequestProfile(member, timestamp) then
        ns.Comm.QueueProfileRequest(member.name)
      end
    end
  end

  Channel.lastResolvedNames = resolvedNames
  Channel.lastResolvedCount = #resolvedNames

  if Channel.lastResolvedCount == 0 and (memberCount or 0) > 0 then
    Channel.lastFallbackPlayer = Utils.PlayerName()
    Channel.lastScanReason = "roster_names_unresolved"
  end

  local missingMembers = Store.MarkMissingFromChannel(activeNames)
  for _, member in ipairs(missingMembers) do
    History.Add("left_channel", member.name)
  end

  Channel.lastScanOk = true
  if Channel.lastScanReason ~= "roster_names_unresolved" then
    Channel.lastScanReason = nil
  end
  return true, nil
end

function Channel.ShouldScan()
  return Utils.Now() - Channel.lastScanAt >= ns.Constants.scanInterval
end

function Channel.DebugStatus()
  local channelId = Channel.GetChannelId()
  local displayIndex = Channel.FindDisplayIndex()
  local visibleCount = 0

  if displayIndex then
    visibleCount = select(5, GetChannelDisplayInfo(displayIndex)) or 0
  end

  return {
    channelId = channelId,
    displayIndex = displayIndex,
    visibleCount = visibleCount,
    lastScanAt = Channel.lastScanAt,
    lastScanOk = Channel.lastScanOk,
    lastScanReason = Channel.lastScanReason,
    lastMemberCount = Channel.lastMemberCount,
    lastResolvedCount = Channel.lastResolvedCount,
    lastResolvedNames = Channel.lastResolvedNames,
    lastFallbackPlayer = Channel.lastFallbackPlayer,
  }
end
