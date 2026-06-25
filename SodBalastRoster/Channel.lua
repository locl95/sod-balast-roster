local addonName, ns = ...

local Utils = ns.Utils
local Store = ns.Store
local History = ns.History
local Channel = {
  lastScanAt = 0,
  lastScanOk = false,
  lastScanReason = "not_scanned",
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
    return false, "channel_not_visible"
  end

  if SetSelectedDisplayChannel then
    SetSelectedDisplayChannel(displayIndex)
  end

  local _, _, _, _, memberCount = GetChannelDisplayInfo(displayIndex)
  local activeNames = {}

  for rosterIndex = 1, memberCount or 0 do
    local name = GetChannelRosterInfo(displayIndex, rosterIndex)
    name = Utils.NormalizeName(name)

    if name then
      activeNames[name] = true
      local member, justJoined = Store.MarkSeenInChannel(name, timestamp)
      if justJoined then
        History.Add("joined_channel", name)
      end

      if member and member.name ~= Utils.PlayerName() and Store.ShouldRequestProfile(member, timestamp) then
        ns.Comm.QueueProfileRequest(member.name)
      end
    end
  end

  local missingMembers = Store.MarkMissingFromChannel(activeNames)
  for _, member in ipairs(missingMembers) do
    History.Add("left_channel", member.name)
  end

  Channel.lastScanOk = true
  Channel.lastScanReason = nil
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
  }
end
