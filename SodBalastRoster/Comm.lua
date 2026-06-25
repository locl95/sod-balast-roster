local addonName, ns = ...

local Utils = ns.Utils
local Store = ns.Store
local History = ns.History
local Comm = {
  queue = {},
  queued = {},
  lastRequestAt = 0,
}
ns.Comm = Comm

function Comm.RegisterPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ns.Constants.addonPrefix)
    return
  end

  if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(ns.Constants.addonPrefix)
  end
end

local function sendAddonWhisper(payload, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(ns.Constants.addonPrefix, payload, "WHISPER", target)
    return
  end

  if SendAddonMessage then
    SendAddonMessage(ns.Constants.addonPrefix, payload, "WHISPER", target)
  end
end

function Comm.QueueProfileRequest(name)
  name = Utils.NormalizeName(name)
  if not name or Comm.queued[name] then
    return
  end

  Comm.queued[name] = true
  Comm.queue[#Comm.queue + 1] = name
end

function Comm.SendRequest(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  Store.MarkProfileRequested(name, Utils.Now())
  sendAddonWhisper("REQ;1", name)
end

function Comm.SendInfo(target)
  if not target then
    return
  end

  local playerName = Utils.PlayerName() or ""
  local payload = table.concat({
    "INFO",
    ns.Constants.protocolVersion,
    playerName,
    tostring(Utils.SafeLevel()),
    Utils.SafeClassFile(),
    Utils.SafeZoneName(),
    Utils.SafeGuildName(),
  }, ";")

  sendAddonWhisper(payload, target)
end

function Comm.FlushQueue()
  if #Comm.queue == 0 then
    return
  end

  local now = Utils.Now()
  if now - Comm.lastRequestAt < ns.Constants.requestInterval then
    return
  end

  local target = table.remove(Comm.queue, 1)
  Comm.queued[target] = nil
  Comm.lastRequestAt = now
  Comm.SendRequest(target)
end

function Comm.HandleInfo(parts, sender)
  local senderName = Utils.NormalizeName(sender)
  local payloadName = Utils.NormalizeName(parts[3])
  local name = payloadName or senderName
  if not name then
    return
  end

  local existing = Store.GetMember(name)
  local hadAddon = existing and existing.hasAddon or false
  local hadProfile = existing and (existing.lastProfileAt or 0) > 0 or false
  local _, changes = Store.SetProfile(name, {
    level = parts[4],
    classFile = parts[5],
    zone = parts[6],
    guildName = parts[7],
  }, Utils.Now())

  if not changes then
    return
  end

  if not hadAddon or not hadProfile then
    History.Add("profile_discovered", name)
  end

  if changes.level then
    History.Add("level_changed", name, string.format("%s -> %s", tostring(changes.level.old), tostring(changes.level.new)))
  end
  if changes.zone then
    History.Add("zone_changed", name, string.format("%s -> %s", changes.zone.old or "", changes.zone.new or ""))
  end
  if changes.guildName then
    History.Add("guild_changed", name, string.format("%s -> %s", changes.guildName.old or "", changes.guildName.new or ""))
  end
end

function Comm.HandleAddonMessage(prefix, text, _, sender)
  if prefix ~= ns.Constants.addonPrefix then
    return
  end

  local senderName = Utils.NormalizeName(sender)
  if senderName == Utils.PlayerName() then
    return
  end

  local parts = Utils.SplitMessage(text, ";")
  local messageType = parts[1]
  local version = parts[2]
  if version ~= ns.Constants.protocolVersion then
    return
  end

  if messageType == "REQ" then
    Comm.SendInfo(senderName)
    return
  end

  if messageType == "INFO" then
    Comm.HandleInfo(parts, senderName)
  end
end
