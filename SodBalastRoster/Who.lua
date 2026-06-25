local addonName, ns = ...

local Utils = ns.Utils
local Store = ns.Store
local History = ns.History
local Who = {
  queue = {},
  queued = {},
  activeName = nil,
  activeAt = 0,
  lastSendAt = 0,
}
ns.Who = Who

local function sendWho(query)
  if C_FriendList and C_FriendList.SendWho then
    C_FriendList.SendWho(query)
    return
  end

  if SendWho then
    SendWho(query)
  end
end

local function getWhoCount()
  if C_FriendList and C_FriendList.GetNumWhoResults then
    return C_FriendList.GetNumWhoResults() or 0
  end

  if GetNumWhoResults then
    return GetNumWhoResults() or 0
  end

  return 0
end

local function getWhoInfo(index)
  if C_FriendList and C_FriendList.GetWhoInfo then
    local info = C_FriendList.GetWhoInfo(index)
    if info then
      return info.fullName or info.name, info.guild, info.level, info.raceStr, info.filename or info.classFilename, info.zone
    end
  end

  if GetWhoInfo then
    local name, guild, level, race, class, zone, classFile = GetWhoInfo(index)
    return name, guild, level, race, classFile or class, zone
  end

  return nil
end

function Who.QueueRequest(name)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() or Who.queued[name] then
    return
  end

  Who.queued[name] = true
  Who.queue[#Who.queue + 1] = name
end

function Who.FlushQueue()
  if Who.activeName or #Who.queue == 0 then
    return
  end

  local now = Utils.Now()
  if now - Who.lastSendAt < ns.Constants.whoRequestInterval then
    return
  end

  local name = table.remove(Who.queue, 1)
  Who.queued[name] = nil
  Who.activeName = name
  Who.activeAt = now
  Who.lastSendAt = now
  Store.MarkWhoRequested(name, now)
  sendWho("n-" .. name)
end

function Who.HandleWhoListUpdate()
  if not Who.activeName then
    return
  end

  local targetName = Who.activeName
  local count = getWhoCount()

  for index = 1, count do
    local name, guild, level, _, classFile, zone = getWhoInfo(index)
    name = Utils.NormalizeName(name)
    if name == targetName then
      local _, changes = Store.SetWhoProfile(targetName, {
        level = level,
        classFile = classFile,
        zone = zone,
        guildName = guild,
      }, Utils.Now())

      if changes and changes.level then
        History.Add("level_changed", targetName, string.format("%s -> %s", tostring(changes.level.old), tostring(changes.level.new)))
      end
      if changes and changes.zone then
        History.Add("zone_changed", targetName, string.format("%s -> %s", changes.zone.old or "", changes.zone.new or ""))
      end
      if changes and changes.guildName then
        History.Add("guild_changed", targetName, string.format("%s -> %s", changes.guildName.old or "", changes.guildName.new or ""))
      end
      break
    end
  end

  Who.activeName = nil
  Who.activeAt = 0
end

function Who.CheckTimeout()
  if Who.activeName and Utils.Now() - Who.activeAt >= 10 then
    Who.activeName = nil
    Who.activeAt = 0
  end
end
