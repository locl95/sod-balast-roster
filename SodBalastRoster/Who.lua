local addonName, ns = ...

local Utils = ns.Utils
local Store = ns.Store
local History = ns.History
local Who = {
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
      return info.fullName or info.name, info.fullGuildName, info.level, info.raceStr, info.filename, info.area
    end
  end

  if GetWhoInfo then
    local name, guild, level, race, class, zone, classFile = GetWhoInfo(index)
    return name, guild, level, race, classFile or class, zone
  end

  return nil
end

local function applyWhoResult(targetName, guild, level, classFile, zone)
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
end

function Who.RequestOneFromHardwareEvent(name)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() or Who.activeName then
    return
  end

  local now = Utils.Now()
  if now - Who.lastSendAt < ns.Constants.whoRequestInterval then
    return
  end

  Who.activeName = name
  Who.activeAt = now
  Who.lastSendAt = now
  Store.MarkWhoRequested(name, now)
  ns.Utils.Print("who query: " .. tostring(name))
  sendWho(string.format('n-"%s"', name))
end

function Who.HandleWhoListUpdate()
  local count = getWhoCount()
  local targetName = Who.activeName
  local applied = 0
  local firstMatch = nil
  local firstResult = nil

  for index = 1, count do
    local name, guild, level, _, classFile, zone = getWhoInfo(index)
    name = Utils.NormalizeName(name)
    if name then
      if not firstResult then
        firstResult = {
          name = name,
          guild = guild,
          level = level,
          classFile = classFile,
          zone = zone,
        }
      end

      if targetName and name == targetName then
        firstMatch = {
          name = name,
          guild = guild,
          level = level,
          classFile = classFile,
          zone = zone,
        }
      end

      local member = Store.GetMember(name)
      if member and member.name == name and member.isOnlineInChannel then
        applyWhoResult(name, guild, level, classFile, zone)
        applied = applied + 1

        if targetName and name == targetName then
          ns.Utils.Print("who applied: " .. name)
        end
      end
    end
  end

  if targetName and applied == 0 and firstMatch then
    applyWhoResult(targetName, firstMatch.guild, firstMatch.level, firstMatch.classFile, firstMatch.zone)
    ns.Utils.Print("who applied target: " .. targetName)
    applied = applied + 1
  elseif targetName and applied == 0 and count == 1 and firstResult then
    applyWhoResult(targetName, firstResult.guild, firstResult.level, firstResult.classFile, firstResult.zone)
    ns.Utils.Print("who applied single result: " .. targetName)
    applied = applied + 1
  end

  if targetName and applied == 0 then
    ns.Utils.Print("who no match: " .. targetName .. " (results=" .. tostring(count) .. ")")
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
