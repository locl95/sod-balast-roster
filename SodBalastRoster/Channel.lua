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
  stableScanCount = 0,
}
ns.Channel = Channel

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

  local displayIndex = Channel.FindDisplayIndex()
  if not displayIndex then
    Channel.lastScanOk = false
    Channel.lastScanReason = "channel_not_visible"
    Channel.lastMemberCount = 0
    Channel.lastResolvedCount = 0
    Channel.lastResolvedNames = {}
    Channel.lastFallbackPlayer = nil
    Channel.stableScanCount = 0
    return false, "channel_not_visible"
  end

  if SetSelectedDisplayChannel then
    SetSelectedDisplayChannel(displayIndex)
  end

  local _, _, _, _, memberCount = GetChannelDisplayInfo(displayIndex)
  Channel.lastMemberCount = memberCount or 0
  Channel.lastFallbackPlayer = nil

  Store.MarkSelfInChannel(timestamp)

  Channel.lastResolvedNames = {}
  Channel.lastResolvedCount = 0
  Channel.lastScanReason = memberCount and memberCount > 0 and "roster_best_effort_disabled" or nil
  Channel.stableScanCount = 0

  Store.DowngradeMissingAddonResponses(timestamp)

  Channel.lastScanOk = true
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
    bestEffort = true,
    lastScanAt = Channel.lastScanAt,
    lastScanOk = Channel.lastScanOk,
    lastScanReason = Channel.lastScanReason,
    lastMemberCount = Channel.lastMemberCount,
    lastResolvedCount = Channel.lastResolvedCount,
    lastResolvedNames = Channel.lastResolvedNames,
    lastFallbackPlayer = Channel.lastFallbackPlayer,
    stableScanCount = Channel.stableScanCount,
  }
end
