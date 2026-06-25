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
    lastProfileAt = 0,
    lastHistorySyncAt = 0,
    lastHistoryRequestedAt = 0,
    level = 0,
    classFile = "",
    zone = "",
    guildName = "",
    lastRequestedAt = 0,
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

  return member, not wasOnline
end

function Store.MarkOffline(name)
  local member = Store.GetMember(name)
  if not member or not member.isOnlineInChannel then
    return nil, false
  end

  member.isOnlineInChannel = false
  return member, true
end

function Store.MarkMissingFromChannel(activeNames)
  local changed = {}
  for _, member in pairs(Store.GetRoster()) do
    if member.isOnlineInChannel and not activeNames[member.name] then
      member.isOnlineInChannel = false
      changed[#changed + 1] = member
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

  member.hasAddon = true
  member.lastProfileAt = timestamp

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
  end
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
