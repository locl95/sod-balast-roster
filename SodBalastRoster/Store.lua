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
    debugLogType = "comm",
    sortColumn = "lastSeen",
    sortDirection = "asc",
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
  debug = {
    commEnabled = false,
    commLogs = {},
  },
  notifications = {
    textEnabled = true,
    soundEnabled = true,
  },
  advanced = {
    scanInterval = ns.Constants.scanInterval,
    rosterSummaryInterval = ns.Constants.rosterSummaryInterval,
    chatSummaryInterval = ns.Constants.chatSummaryInterval,
    whoRequestInterval = ns.Constants.whoRequestInterval,
    requestInterval = ns.Constants.requestInterval,
  },
}

-- Claves de "advanced" que se copian a ns.Constants al cargar y al cambiar
-- un slider, para no tener que tocar cada sitio que ya lee ns.Constants.X.
local ADVANCED_CONSTANT_KEYS = {
  "scanInterval",
  "rosterSummaryInterval",
  "chatSummaryInterval",
  "whoRequestInterval",
  "requestInterval",
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
  SodBalastRosterDB.scopes = SodBalastRosterDB.scopes or {}

  local scopeKey = Utils.StorageScopeKey()
  SodBalastRosterDB.scopes[scopeKey] = SodBalastRosterDB.scopes[scopeKey] or {}
  copyDefaults(SodBalastRosterDB.scopes[scopeKey], defaults)

  ns.db = SodBalastRosterDB.scopes[scopeKey]
  Store.ApplyAdvancedConstants()
end

function Store.ApplyAdvancedConstants()
  local advanced = Store.GetAdvancedState()
  for _, key in ipairs(ADVANCED_CONSTANT_KEYS) do
    if advanced[key] then
      ns.Constants[key] = advanced[key]
    end
  end
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
    profession1Skill = 0,
    profession1MaxSkill = 0,
    profession2Skill = 0,
    profession2MaxSkill = 0,
    spec = "",
    specIcon = "",
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

-- En memoria, no persistido: se recrea en cada carga del addon, por lo que
-- modela "visto por primera vez en esta sesion" sin tocar SavedVariables.
local sessionSighted = {}

local function markSessionSighting(name)
  if sessionSighted[name] then
    return false
  end

  sessionSighted[name] = true
  return true
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

  return wasOnline, markSessionSighting(member.name)
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
  return member, markSessionSighting(member.name)
end

function Store.MarkObservedInChannel(name, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, false, false
  end

  local wasOnline, firstThisSession = markObserved(member, timestamp, "chat")

  return member, not wasOnline, firstThisSession
end

function Store.MarkObservedByNotice(name, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, false, false
  end

  local wasOnline, firstThisSession = markObserved(member, timestamp, "notice")
  return member, not wasOnline, firstThisSession
end

function Store.MarkObservedByWho(name, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, false, false
  end

  local wasOnline, firstThisSession = markObserved(member, timestamp, "who")
  return member, not wasOnline, firstThisSession
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
  local member = Store.GetRoster()[name]
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

  local function applyNumber(field, value)
    value = tonumber(value) or 0
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
  applyNumber("profession1Skill", profile.profession1Skill)
  applyNumber("profession1MaxSkill", profile.profession1MaxSkill)
  applyNumber("profession2Skill", profile.profession2Skill)
  applyNumber("profession2MaxSkill", profile.profession2MaxSkill)
  apply("spec", profile.spec)
  apply("specIcon", profile.specIcon)

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

function Store.GetDebugState()
  return Store.GetDB().debug
end

function Store.GetNotificationState()
  return Store.GetDB().notifications
end

function Store.IsNotifyTextEnabled()
  return Store.GetNotificationState().textEnabled ~= false
end

function Store.SetNotifyTextEnabled(enabled)
  Store.GetNotificationState().textEnabled = enabled and true or false
end

function Store.IsNotifySoundEnabled()
  return Store.GetNotificationState().soundEnabled ~= false
end

function Store.SetNotifySoundEnabled(enabled)
  Store.GetNotificationState().soundEnabled = enabled and true or false
end

function Store.GetAdvancedState()
  return Store.GetDB().advanced
end

function Store.SetAdvancedValue(key, value)
  Store.GetAdvancedState()[key] = value
  Store.ApplyAdvancedConstants()
end

function Store.IsCommDebugEnabled()
  return Store.GetDebugState().commEnabled and true or false
end

function Store.SetCommDebugEnabled(enabled)
  Store.GetDebugState().commEnabled = enabled and true or false
end

function Store.GetCommDebugLogs()
  return Store.GetDebugState().commLogs
end

function Store.ClearCommDebugLogs()
  Store.GetDebugState().commLogs = {}
end

function Store.AppendCommDebugLog(entry)
  local logs = Store.GetCommDebugLogs()
  logs[#logs + 1] = entry

  local limit = 200
  if #logs <= limit then
    return
  end

  local trimmed = {}
  local startIndex = #logs - limit + 1
  for index = startIndex, #logs do
    trimmed[#trimmed + 1] = logs[index]
  end
  Store.GetDebugState().commLogs = trimmed
end

function Store.PurgeBlanks()
  local roster = Store.GetRoster()
  local count = 0
  for name, member in pairs(roster) do
    if not member.hasAddon
      and not member.isOnlineInChannel
      and not member.observedByChat
      and not member.observedByNotice
      and not member.observedByWho
      and (member.firstSeenAt or 0) == 0
    then
      roster[name] = nil
      count = count + 1
    end
  end
  return count
end

function Store.HasLegacyData()
  if not SodBalastRosterDB then
    return false
  end

  for key in pairs(SodBalastRosterDB) do
    if key ~= "scopes" then
      return true
    end
  end

  return false
end

function Store.PurgeLegacyData()
  if not SodBalastRosterDB then
    return 0
  end

  local removed = 0
  for key in pairs(SodBalastRosterDB) do
    if key ~= "scopes" then
      SodBalastRosterDB[key] = nil
      removed = removed + 1
    end
  end

  return removed
end

function Store.IsWrongRealmMember(member)
  local myRealm = Utils.PlayerRealmSuffix()
  if not myRealm or not member then
    return false
  end

  local _, realm = Utils.SplitNameRealm(member.name)
  return realm ~= nil and realm ~= myRealm
end

function Store.PurgeWrongRealmMembers()
  local roster = Store.GetRoster()
  local removed = 0

  for name, member in pairs(roster) do
    if Store.IsWrongRealmMember(member) then
      roster[name] = nil
      removed = removed + 1
    end
  end

  return removed
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

local DEFAULT_SORT_COLUMN = "lastSeen"

-- Cada comparador define el orden "ascendente" de su columna; el orden
-- descendente se obtiene invirtiendo los argumentos, así un segundo click
-- siempre invierte exactamente lo que el primero produjo.
local SORT_COMPARATORS = {
  addon = function(left, right)
    if left.hasAddon ~= right.hasAddon then
      return left.hasAddon
    end
    return left.name < right.name
  end,
  name = function(left, right)
    return left.name < right.name
  end,
  level = function(left, right)
    if (left.level or 0) ~= (right.level or 0) then
      return (left.level or 0) < (right.level or 0)
    end
    return left.name < right.name
  end,
  class = function(left, right)
    if (left.classFile or "") ~= (right.classFile or "") then
      return (left.classFile or "") < (right.classFile or "")
    end
    return left.name < right.name
  end,
  spec = function(left, right)
    local leftSpec = tostring(left.specIcon or "")
    local rightSpec = tostring(right.specIcon or "")
    if leftSpec ~= rightSpec then
      return leftSpec < rightSpec
    end
    return left.name < right.name
  end,
  zone = function(left, right)
    if (left.zone or "") ~= (right.zone or "") then
      return (left.zone or "") < (right.zone or "")
    end
    return left.name < right.name
  end,
  guild = function(left, right)
    if (left.guildName or "") ~= (right.guildName or "") then
      return (left.guildName or "") < (right.guildName or "")
    end
    return left.name < right.name
  end,
  profs = function(left, right)
    local leftProf = left.profession1 ~= "" and left.profession1 or (left.profession2 or "")
    local rightProf = right.profession1 ~= "" and right.profession1 or (right.profession2 or "")
    if leftProf ~= rightProf then
      return leftProf < rightProf
    end
    return left.name < right.name
  end,
  -- Comportamiento por defecto: Online primero, luego nivel desc, luego nombre.
  lastSeen = function(left, right)
    if left.isOnlineInChannel ~= right.isOnlineInChannel then
      return left.isOnlineInChannel
    end

    if (left.level or 0) ~= (right.level or 0) then
      return (left.level or 0) > (right.level or 0)
    end

    return left.name < right.name
  end,
}

function Store.SetSortColumn(column)
  if not SORT_COMPARATORS[column] then
    return
  end

  local ui = Store.GetUIState()
  if ui.sortColumn == column then
    ui.sortDirection = (ui.sortDirection == "desc") and "asc" or "desc"
  else
    ui.sortColumn = column
    ui.sortDirection = "asc"
  end
end

function Store.GetSortState()
  local ui = Store.GetUIState()
  return ui.sortColumn or DEFAULT_SORT_COLUMN, ui.sortDirection or "asc"
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

  local sortColumn, sortDirection = Store.GetSortState()
  local comparator = SORT_COMPARATORS[sortColumn] or SORT_COMPARATORS[DEFAULT_SORT_COLUMN]

  table.sort(results, function(left, right)
    if sortDirection == "desc" then
      return comparator(right, left)
    end
    return comparator(left, right)
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

function Store.SelectBootstrapDonors(maxCount)
  local donors = {}

  for _, member in pairs(Store.GetRoster()) do
    if member.hasAddon and member.name ~= Utils.PlayerName() then
      donors[#donors + 1] = member
    end
  end

  table.sort(donors, function(left, right)
    if left.isOnlineInChannel ~= right.isOnlineInChannel then
      return left.isOnlineInChannel
    end

    if (left.lastAddonSeenAt or 0) ~= (right.lastAddonSeenAt or 0) then
      return (left.lastAddonSeenAt or 0) > (right.lastAddonSeenAt or 0)
    end

    if (left.lastSeenAt or 0) ~= (right.lastSeenAt or 0) then
      return (left.lastSeenAt or 0) > (right.lastSeenAt or 0)
    end

    return left.name < right.name
  end)

  maxCount = maxCount or ns.Constants.maxBootstrapDonors
  local results = {}
  for index = 1, math.min(maxCount, #donors) do
    results[#results + 1] = donors[index].name
  end

  return results
end
