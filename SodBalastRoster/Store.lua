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
  return ns.db
end

function Store.GetRoster()
  return ns.db.roster
end

function Store.ResetTransientState()
  for _, member in pairs(Store.GetRoster()) do
    member.isOnlineInChannel = false
    member.missingScans = 0
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
    firstSeenAt = 0,
    lastSeenAt = 0,
    missingScans = 0,
    lastProfileAt = 0,
    lastWhoProfileAt = 0,
    lastHistorySyncAt = 0,
    lastHistoryRequestedAt = 0,
    lastHistoryAdvertisedAt = 0,
    pendingHistorySync = false,
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

  return roster[name]
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

function Store.MarkSeenInChannel(name, timestamp)
  local member = Store.GetMember(name)
  if not member then
    return nil, false
  end

  local wasOnline = member.isOnlineInChannel
  if member.firstSeenAt == 0 then
    member.firstSeenAt = timestamp
  end

  member.isOnlineInChannel = true
  member.lastSeenAt = timestamp
  member.missingScans = 0

  return member, not wasOnline
end

function Store.MarkOffline(name)
  local member = Store.GetMember(name)
  if not member or not member.isOnlineInChannel then
    return nil, false
  end

  member.isOnlineInChannel = false
  member.missingScans = 0
  return member, true
end

function Store.MarkMissingFromChannel(activeNames, threshold)
  threshold = threshold or ns.Constants.fullMissingThreshold or 2
  local changed = {}
  for _, member in pairs(Store.GetRoster()) do
    if member.isOnlineInChannel and not activeNames[member.name] then
      member.missingScans = (member.missingScans or 0) + 1
      if member.missingScans >= threshold then
        member.isOnlineInChannel = false
        member.missingScans = 0
        changed[#changed + 1] = member
      end
    elseif member.isOnlineInChannel then
      member.missingScans = 0
    end
  end
  return changed
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
  member.lastProfileAt = timestamp

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
  local member = Store.GetMember(name)
  if not member then
    return 0
  end

  return member.lastHistorySyncAt or 0
end

function Store.MarkHistorySynced(name, timestamp)
  local member = Store.GetMember(name)
  if member and timestamp and timestamp > (member.lastHistorySyncAt or 0) then
    member.lastHistorySyncAt = timestamp
  end
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
  return ns.db.ui
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
