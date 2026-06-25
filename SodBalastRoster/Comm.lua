local addonName, ns = ...

local Utils = ns.Utils
local Store = ns.Store
local History = ns.History
local Comm = {
  queue = {},
  queued = {},
  lastSendAt = 0,
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

local function queueMessage(target, payload, key)
  target = Utils.NormalizeName(target)
  if not target or not payload then
    return
  end

  key = key or string.format("%s|%s", target, payload)
  if Comm.queued[key] then
    return
  end

  Comm.queued[key] = true
  Comm.queue[#Comm.queue + 1] = {
    target = target,
    payload = payload,
    key = key,
  }
end

local function encodeHistoryEntry(entry)
  return table.concat({
    "HEVT",
    ns.Constants.protocolVersion,
    Utils.EscapeField(entry.id),
    tostring(entry.at or 0),
    Utils.EscapeField(entry.source or ""),
    Utils.EscapeField(entry.name or ""),
    Utils.EscapeField(entry.type or ""),
    Utils.EscapeField(entry.details or ""),
  }, ";")
end

function Comm.QueueProfileRequest(name)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  Store.MarkProfileRequested(name, Utils.Now())
  queueMessage(name, "REQ;1", "REQ|" .. name)
end

function Comm.QueueHistoryRequest(name)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  local sinceAt = Store.GetHistorySyncAt(name)
  Store.MarkHistoryRequested(name, Utils.Now())
  queueMessage(name, string.format("HREQ;%s;%s", ns.Constants.protocolVersion, tostring(sinceAt)), "HREQ|" .. name)
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

function Comm.SendBye(target)
  if not target then
    return
  end

  local playerName = Utils.PlayerName() or ""
  local payload = table.concat({
    "BYE",
    ns.Constants.protocolVersion,
    playerName,
  }, ";")

  sendAddonWhisper(payload, target)
end

function Comm.BroadcastBye()
  local peers = Store.GetOnlineAddonMembers()
  for _, name in ipairs(peers) do
    Comm.SendBye(name)
  end
end

function Comm.SendHistorySince(target, sinceAt)
  local events = History.ExportRecentSince(sinceAt, ns.Constants.historySyncLimit)
  for index, entry in ipairs(events) do
    queueMessage(target, encodeHistoryEntry(entry), string.format("HEVT|%s|%s", target, entry.id or index))
  end
end

function Comm.FlushQueue()
  if #Comm.queue == 0 then
    return
  end

  local now = Utils.Now()
  if now - Comm.lastSendAt < ns.Constants.requestInterval then
    return
  end

  local item = table.remove(Comm.queue, 1)
  Comm.queued[item.key] = nil
  Comm.lastSendAt = now
  sendAddonWhisper(item.payload, item.target)
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
  local member, changes = Store.SetProfile(name, {
    level = parts[4],
    classFile = parts[5],
    zone = parts[6],
    guildName = parts[7],
  }, Utils.Now())

  if not changes then
    if member and Store.ShouldRequestHistory(member, Utils.Now()) then
      Comm.QueueHistoryRequest(name)
    end
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

  if member and Store.ShouldRequestHistory(member, Utils.Now()) then
    Comm.QueueHistoryRequest(name)
  end
end

function Comm.HandleHistoryRequest(parts, sender)
  local sinceAt = tonumber(parts[3]) or 0
  Comm.SendHistorySince(sender, sinceAt)
end

function Comm.HandleHistoryEvent(parts, sender)
  local entry = {
    id = Utils.UnescapeField(parts[3]),
    at = tonumber(parts[4]) or 0,
    source = Utils.UnescapeField(parts[5]),
    name = Utils.UnescapeField(parts[6]),
    type = Utils.UnescapeField(parts[7]),
    details = Utils.UnescapeField(parts[8]),
  }

  local _, added = History.AddImported(entry)
  if added then
    Store.MarkHistorySynced(sender, entry.at)
    return
  end

  Store.MarkHistorySynced(sender, entry.at)
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
    return
  end

  if messageType == "HREQ" then
    Comm.HandleHistoryRequest(parts, senderName)
    return
  end

  if messageType == "HEVT" then
    Comm.HandleHistoryEvent(parts, senderName)
    return
  end

  if messageType == "BYE" then
    local name = Utils.NormalizeName(parts[3]) or senderName
    local member, changed = Store.MarkOffline(name)
    if changed and member then
      History.Add("left_channel", member.name, "logout")
    end
  end
end
