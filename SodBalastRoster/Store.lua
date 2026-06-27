local addonName, ns = ...

local Utils = ns.Utils
local Store = {}
ns.Store = Store

local defaults = {
  roster = {},
  history = {},
  historyMeta = {
    nextSequence = 1,
  },
  ui = {
    point = "CENTER",
    x = 0,
    y = 0,
    width = 860,
    height = 420,
    onlyOnline = false,
    onlyAddon = false,
    search = "",
    selectedTab = "roster",
  },
  minimap = {
    angle = 220,
    hidden = false,
  },
  chatAlert = {
    point = "TOPRIGHT",
    relativePoint = "TOPRIGHT",
    x = -220,
    y = -120,
  },
}

local function copyDefaults(target, source)
  for key, value in pairs(source) do
    if type(value) == "table" then
      target[key] = target[key] or {}
      copyDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

function Store.Init()
  SodBalastRosterDB = SodBalastRosterDB or {}
  copyDefaults(SodBalastRosterDB, defaults)
  ns.db = SodBalastRosterDB
end

function Store.GetDB()
  if not ns.db then
    Store.Init()
  end
  return ns.db
end

function Store.GetRoster()
  return Store.GetDB().roster
end

function Store.ResetTransientState()
  for _, member in pairs(Store.GetRoster()) do
    member.isOnlineInChannel = false
    member.observedByChat = false
    member.observedByNotice = false
    member.observedByWho = false
  end
end

function Store.GetMember(name)
  name = Utils.NormalizeName(name)
  if not name then
    return nil
  end

  local roster = Store.GetRoster()
  roster[name] = roster[name] or {
    name = name,
    isOnlineInChannel = false,
    hasAddon = false,
    observedByChat = false,
    observedByNotice = false,
    observedByWho = false,
    lastObservedAt = 0,
    lastObservedByChatAt = 0,
    lastObservedByNoticeAt = 0,
    lastObservedByWhoAt = 0,
    lastAddonSeenAt = 0,
    pendingAddonProbe = false,
    lastAddonProbeAt = 0,
    missedAddonProbes = 0,
    firstSeenAt = 0,
    lastSeenAt = 0,
    lastUpdatedAt = 0,
    lastProfileAt = 0,
    lastWhoProfileAt = 0,
    lastHistorySyncAt = 0,
    lastHistoryRequestedAt = 0,
    lastHistoryAdvertisedAt = 0,
    pendingHistorySync = false,
    pendingRosterSync = false,
    lastChatRequestedAt = 0,
    lastChatSyncAt = 0,
    lastRosterRequestedAt = 0,
    lastRosterSyncAt = 0,
    level = 0,
    classFile = "",
    zone = "",
    guildName = "",
    profession1 = "",
    profession2 = "",
    profession1Icon = "",
    profession2Icon = "",
    lastRequestedAt = 0,
    lastWhoRequestedAt = 0,
  }

  local member = roster[name]
  if (member.lastChatSyncAt or 0) == 0 and (member.lastHistorySyncAt or 0) > 0 then
    member.lastChatSyncAt = member.lastHistorySyncAt
  elseif (member.lastHistorySyncAt or 0) == 0 and (member.lastChatSyncAt or 0) > 0 then
    member.lastHistorySyncAt = member.lastChatSyncAt
  end

  return member
end

function Store.UpsertMember(name, patch)
  local member = Store.GetMember(name)
  if not member then
    return nil
  end

  for key, value in pairs(patch) do
    member[key] = value
  end

  return member
end

local function markObserved(member, timestamp, source)
  local wasOnline = member.isOnlineInChannel

  if member.firstSeenAt == 0 then
    member.firstSeenAt = timestamp
  end

  member.isOnlineInChannel = true
  member.lastSeenAt = timestamp
  member.lastObservedAt = timestamp

  if source == "chat" then
    member.observedByChat = true
    member.lastObservedByChatAt = timestamp
  elseif source == "notice" then
    member.observedByNotice = true
    member.lastObservedByNoticeAt = timestamp
  elseif source == "who" then
    member.observedByWho = true
    member.lastObservedByWhoAt = timestamp
  end

  return wasOnline
end

function Store.MarkAddonSeen(name, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil
  end

  timestamp = timestamp or Utils.Now()
  if member.firstSeenAt == 0 then
    member.firstSeenAt = timestamp
  end
  member.isOnlineInChannel = true
  member.lastSeenAt = timestamp
  member.lastObservedAt = timestamp
  member.hasAddon = true
  member.pendingAddonProbe = false
  member.lastAddonSeenAt = timestamp
  member.missedAddonProbes = 0
  return member
end

function Store.MarkObservedInChannel(name, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, false
  end

  local wasOnline = markObserved(member, timestamp, "chat")

  return member, not wasOnline
end

function Store.MarkObservedByNotice(name, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, false
  end

  local wasOnline = markObserved(member, timestamp, "notice")
  return member, not wasOnline
end

function Store.MarkObservedByWho(name, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, false
  end

  local wasOnline = markObserved(member, timestamp, "who")
  return member, not wasOnline
end

function Store.MarkSelfInChannel(timestamp)
  local name = Utils.PlayerName()
  if not name then
    return nil
  end

  local member = Store.GetMember(name)
  if not member then
    return nil
  end

  markObserved(member, timestamp, "notice")
  member.hasAddon = true
  member.lastAddonSeenAt = math.max(member.lastAddonSeenAt or 0, timestamp)
  member.pendingAddonProbe = false
  member.missedAddonProbes = 0
  return member
end

function Store.MarkAddonProbePending(name, timestamp)
  local member = Store.GetMember(name)
  if member then
    member.pendingAddonProbe = true
    member.lastAddonProbeAt = timestamp or Utils.Now()
  end
end

function Store.ShouldProbeObservedAddon(member, timestamp)
  if not member or member.hasAddon then
    return false
  end

  timestamp = timestamp or Utils.Now()
  return timestamp - (member.lastAddonProbeAt or 0) >= (ns.Constants.addonProbeTimeout or 20)
end

function Store.ClearAddonProbe(name)
  local member = Store.GetMember(name)
  if member then
    member.pendingAddonProbe = false
    member.missedAddonProbes = 0
  end
end

function Store.DowngradeMissingAddonResponses(timestamp)
  local changed = {}
  local timeout = ns.Constants.addonProbeTimeout or 20
  local threshold = ns.Constants.partialMissingThreshold or 4

  for _, member in pairs(Store.GetRoster()) do
    if member.isOnlineInChannel and member.hasAddon and member.pendingAddonProbe and (timestamp - (member.lastAddonProbeAt or 0)) >= timeout then
      member.pendingAddonProbe = false
      member.missedAddonProbes = (member.missedAddonProbes or 0) + 1
      if member.missedAddonProbes >= threshold then
        local offlineMember, wasChanged = Store.MarkOffline(member.name)
        if wasChanged and offlineMember then
          changed[#changed + 1] = offlineMember
        end
      end
    end
  end

  return changed
end

function Store.MarkOffline(name)
  local member = Store.GetMember(name)
  if not member or not member.isOnlineInChannel then
    return nil, false
  end

  member.isOnlineInChannel = false
  member.observedByChat = false
  member.observedByNotice = false
  member.observedByWho = false
  member.pendingAddonProbe = false
  member.missedAddonProbes = 0
  return member, true
end

function Store.SetProfile(name, profile, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, nil
  end

  local changes = {}

  local function apply(field, value)
    value = value or ""
    if member[field] ~= value then
      changes[field] = {
        old = member[field],
        new = value,
      }
      member[field] = value
    end
  end

  if profile.level and tonumber(profile.level) then
    local level = tonumber(profile.level)
    if member.level ~= level then
      changes.level = { old = member.level, new = level }
      member.level = level
    end
  end

  apply("classFile", profile.classFile)
  apply("zone", profile.zone)
  apply("guildName", profile.guildName)
  apply("profession1", profile.profession1)
  apply("profession2", profile.profession2)
  apply("profession1Icon", profile.profession1Icon)
  apply("profession2Icon", profile.profession2Icon)

  member.hasAddon = true
  member.pendingAddonProbe = false
  member.lastAddonSeenAt = timestamp
  member.lastProfileAt = timestamp
  if next(changes) ~= nil then
    member.lastUpdatedAt = timestamp
  end

  return member, changes
end

function Store.SetWhoProfile(name, profile, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, nil
  end

  local changes = {}

  local function apply(field, value)
    value = value or ""
    if member[field] ~= value then
      changes[field] = {
        old = member[field],
        new = value,
      }
      member[field] = value
    end
  end

  if profile.level and tonumber(profile.level) then
    local level = tonumber(profile.level)
    if member.level ~= level then
      changes.level = { old = member.level, new = level }
      member.level = level
    end
  end

  apply("classFile", profile.classFile)
  apply("zone", profile.zone)
  apply("guildName", profile.guildName)

  member.observedByWho = true
  member.lastObservedByWhoAt = timestamp
  member.lastWhoProfileAt = timestamp

  return member, changes
end

function Store.ShouldRequestProfile(member, timestamp)
  if not member then
    return false
  end

  if not member.hasAddon then
    return timestamp - (member.lastRequestedAt or 0) >= ns.Constants.profileTTL
  end

  return timestamp - (member.lastProfileAt or 0) >= ns.Constants.profileTTL
end

function Store.MarkProfileRequested(name, timestamp)
  local member = Store.GetMember(name)
  if member then
    member.lastRequestedAt = timestamp
  end
end

function Store.ShouldRequestRoster(member, timestamp)
  if not member or not member.hasAddon then
    return false
  end

  return timestamp - (member.lastRosterRequestedAt or 0) >= ns.Constants.rosterSyncCooldown
end

function Store.MarkRosterRequested(name, timestamp)
  local member = Store.GetMember(name)
  if member then
    member.lastRosterRequestedAt = timestamp
    member.pendingRosterSync = false
  end
end

function Store.MarkRosterSyncPending(name)
  local member = Store.GetMember(name)
  if member then
    member.pendingRosterSync = true
  end
end

function Store.ConsumePendingRosterSync(name)
  local member = Store.GetMember(name)
  if not member or not member.pendingRosterSync then
    return false
  end

  member.pendingRosterSync = false
  return true
end

function Store.MarkRosterSynced(name, timestamp)
  local member = Store.GetMember(name)
  if member then
    member.lastRosterSyncAt = math.max(member.lastRosterSyncAt or 0, timestamp or 0)
  end
end

function Store.ShouldRequestChat(member, timestamp)
  if not member or not member.hasAddon then
    return false
  end

  return timestamp - (member.lastChatRequestedAt or 0) >= ns.Constants.historySyncCooldown
end

function Store.MarkChatRequested(name, timestamp)
  local member = Store.GetMember(name)
  if member then
    member.lastChatRequestedAt = timestamp
    member.pendingHistorySync = false
  end
end

function Store.MarkChatSynced(name, timestamp)
  local member = Store.GetMember(name)
  if member then
    local syncedAt = math.max(member.lastChatSyncAt or 0, timestamp or 0)
    member.lastChatSyncAt = syncedAt
    member.lastHistorySyncAt = math.max(member.lastHistorySyncAt or 0, syncedAt)
  end
end

function Store.GetChatSyncAt(name)
  local member = Store.GetMember(name)
  if not member then
    return 0
  end

  return math.max(member.lastChatSyncAt or 0, member.lastHistorySyncAt or 0)
end

function Store.ShouldRequestWho(member, timestamp)
  if not member or member.hasAddon then
    return false
  end

  local hasProfile = (member.level or 0) > 0 and member.classFile ~= "" and member.zone ~= ""
  if hasProfile and timestamp - (member.lastWhoProfileAt or 0) < ns.Constants.whoProfileTTL then
    return false
  end

  return timestamp - (member.lastWhoRequestedAt or 0) >= ns.Constants.whoRequestInterval
end

function Store.MarkWhoRequested(name, timestamp)
  local member = Store.GetMember(name)
  if member then
    member.lastWhoRequestedAt = timestamp
  end
end

function Store.ShouldRequestHistory(member, timestamp)
  if not member or not member.hasAddon then
    return false
  end

  return timestamp - (member.lastHistoryRequestedAt or 0) >= ns.Constants.historySyncCooldown
end

function Store.MarkHistoryRequested(name, timestamp)
  local member = Store.GetMember(name)
  if member then
    member.lastHistoryRequestedAt = timestamp
    member.pendingHistorySync = false
  end
end

function Store.MarkHistorySyncPending(name)
  local member = Store.GetMember(name)
  if member then
    member.pendingHistorySync = true
  end
end

function Store.ConsumePendingHistorySync(name)
  local member = Store.GetMember(name)
  if not member or not member.pendingHistorySync then
    return false
  end

  member.pendingHistorySync = false
  return true
end

function Store.GetHistorySyncAt(name)
  return Store.GetChatSyncAt(name)
end

function Store.MarkHistorySynced(name, timestamp)
  Store.MarkChatSynced(name, timestamp)
end

function Store.GetHistoryAdvertisedAt(name)
  local member = Store.GetMember(name)
  if not member then
    return 0
  end

  return member.lastHistoryAdvertisedAt or 0
end

function Store.MarkHistoryAdvertised(name, timestamp)
  local member = Store.GetMember(name)
  if member and timestamp and timestamp > (member.lastHistoryAdvertisedAt or 0) then
    member.lastHistoryAdvertisedAt = timestamp
  end
end

function Store.GetUIState()
  return Store.GetDB().ui
end

function Store.GetMinimapState()
  return Store.GetDB().minimap
end

function Store.GetChatAlertState()
  return Store.GetDB().chatAlert
end

function Store.GetLatestRosterUpdatedAt()
  local latest = 0
  for _, member in pairs(Store.GetRoster()) do
    if (member.lastUpdatedAt or 0) > latest then
      latest = member.lastUpdatedAt or 0
    end
  end
  return latest
end

function Store.SetUIFlag(key, value)
  ns.db.ui[key] = value
end

function Store.SaveFramePosition(frame)
  if not frame then
    return
  end

  local point, _, relativePoint, x, y = frame:GetPoint(1)
  local ui = Store.GetUIState()
  ui.point = point or "CENTER"
  ui.relativePoint = relativePoint or ui.point
  ui.x = x or 0
  ui.y = y or 0
  ui.width = math.floor(frame:GetWidth())
  ui.height = math.floor(frame:GetHeight())
end

function Store.SaveChatAlertPosition(frame)
  if not frame then
    return
  end

  local point, _, relativePoint, x, y = frame:GetPoint(1)
  local state = Store.GetChatAlertState()
  state.point = point or "CENTER"
  state.relativePoint = relativePoint or state.point
  state.x = x or 0
  state.y = y or 0
end

function Store.GetVisibleRoster()
  local results = {}
  local ui = Store.GetUIState()
  local search = Utils.Trim(ui.search or "")

  for _, member in pairs(Store.GetRoster()) do
    if (not ui.onlyOnline or member.isOnlineInChannel)
      and (not ui.onlyAddon or member.hasAddon)
      and Utils.ContainsInsensitive(member.name, search) then
      results[#results + 1] = member
    end
  end

  table.sort(results, function(left, right)
    if left.isOnlineInChannel ~= right.isOnlineInChannel then
      return left.isOnlineInChannel
    end

    if (left.level or 0) ~= (right.level or 0) then
      return (left.level or 0) > (right.level or 0)
    end

    return left.name < right.name
  end)

  return results
end

function Store.ExportRosterProfiles(limit, since)
  local results = {}
  local cutoff = Utils.Now() - ns.Constants.rosterSyncWindow
  since = tonumber(since) or 0

  for _, member in pairs(Store.GetRoster()) do
    local hasKnownProfile = member.hasAddon or (member.level or 0) > 0 or member.classFile ~= "" or member.zone ~= "" or member.guildName ~= "" or member.profession1 ~= "" or member.profession2 ~= ""
    local isRecent = (member.lastSeenAt or 0) >= cutoff or member.isOnlineInChannel
    if member.name ~= Utils.PlayerName() and hasKnownProfile and isRecent and (member.lastUpdatedAt or 0) > since then
      results[#results + 1] = member
    end
  end

  table.sort(results, function(left, right)
    return (left.lastUpdatedAt or 0) > (right.lastUpdatedAt or 0)
  end)

  limit = limit or ns.Constants.rosterSyncLimit
  if #results <= limit then
    return results
  end

  local trimmed = {}
  for index = 1, limit do
    trimmed[#trimmed + 1] = results[index]
  end

  return trimmed
end

function Store.GetOnlineAddonMembers()
  local names = {}

  for _, member in pairs(Store.GetRoster()) do
    if member.isOnlineInChannel and member.hasAddon and member.name ~= Utils.PlayerName() then
      names[#names + 1] = member.name
    end
  end

  table.sort(names)
  return names
end

function Store.SelectSyncDonors(maxCount)
  local donors = {}

  for _, member in pairs(Store.GetRoster()) do
    if member.isOnlineInChannel and member.hasAddon and member.name ~= Utils.PlayerName() then
      donors[#donors + 1] = member
    end
  end

  table.sort(donors, function(left, right)
    if (left.lastProfileAt or 0) ~= (right.lastProfileAt or 0) then
      return (left.lastProfileAt or 0) > (right.lastProfileAt or 0)
    end

    if (left.lastSeenAt or 0) ~= (right.lastSeenAt or 0) then
      return (left.lastSeenAt or 0) > (right.lastSeenAt or 0)
    end

    return left.name < right.name
  end)

  maxCount = maxCount or ns.Constants.maxPeriodicDonors
  local results = {}
  for index = 1, math.min(maxCount, #donors) do
    results[#results + 1] = donors[index].name
  end

  return results
end
