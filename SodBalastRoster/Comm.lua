local addonName, ns = ...

local Utils = ns.Utils
local Store = ns.Store
local History = ns.History
local Comm = {
  queue = {},
  queued = {},
  lastSendAt = 0,
  lastHistorySummaryAt = 0,
  bootstrapSyncBudget = 0,
}
ns.Comm = Comm

local logCommTraffic

function Comm.RegisterPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ns.Constants.addonPrefix)
    return
  end

  if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(ns.Constants.addonPrefix)
  end
end

local function sendAddonWhisper(payload, target, context)
  logCommTraffic("OUT", target, payload, context)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(ns.Constants.addonPrefix, payload, "WHISPER", target)
    return
  end

  if SendAddonMessage then
    SendAddonMessage(ns.Constants.addonPrefix, payload, "WHISPER", target)
  end
end


logCommTraffic = function(direction, peer, payload, context)
  if not Store.IsCommDebugEnabled() then
    return
  end

  Store.AppendCommDebugLog({
    at = Utils.Now(),
    direction = direction,
    peer = Utils.NormalizeName(peer) or tostring(peer or ""),
    payload = tostring(payload or ""),
    context = tostring(context or ""),
  })
end

local function queueMessage(target, payload, key, context)
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
    context = context,
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

local function encodeRosterProfile(member)
  return table.concat({
    "RPRO",
    ns.Constants.protocolVersion,
    Utils.EscapeField(member.name or ""),
    member.hasAddon and "1" or "0",
    tostring(member.level or 0),
    Utils.EscapeField(member.classFile or ""),
    Utils.EscapeField(member.zone or ""),
    Utils.EscapeField(member.guildName or ""),
    Utils.EscapeField(member.profession1 or ""),
    Utils.EscapeField(member.profession2 or ""),
    tostring(member.profession1Icon or ""),
    tostring(member.profession2Icon or ""),
    tostring(member.lastSeenAt or 0),
    tostring(member.lastUpdatedAt or 0),
    Utils.EscapeField(member.spec or ""),
    tostring(member.specIcon or ""),
    tostring(member.profession1Skill or 0),
    tostring(member.profession1MaxSkill or 0),
    tostring(member.profession2Skill or 0),
    tostring(member.profession2MaxSkill or 0),
  }, ";")
end

local function encodeChatMessage(entry)
  return table.concat({
    "CMSG",
    ns.Constants.protocolVersion,
    Utils.EscapeField(entry.id),
    tostring(entry.at or 0),
    Utils.EscapeField(entry.source or ""),
    Utils.EscapeField(entry.name or ""),
    Utils.EscapeField(entry.details or ""),
  }, ";")
end

function Comm.QueueProfileRequest(name)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  Store.MarkProfileRequested(name, Utils.Now())
  queueMessage(name, string.format("REQ;%s", ns.Constants.protocolVersion), "REQ|" .. name)
end

function Comm.QueueHello(name, context)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  queueMessage(name, string.format("HELLO;%s;%s", ns.Constants.protocolVersion, Utils.PlayerName() or ""), "HELLO|" .. name, context)
end

function Comm.BroadcastHello()
  local self = Utils.PlayerName()
  local sent = 0
  for _, member in pairs(Store.GetRoster()) do
    if member.hasAddon and member.name ~= self then
      Comm.QueueHello(member.name, "broadcast")
      sent = sent + 1
    end
  end
  return sent > 0
end

function Comm.SetBootstrapSyncBudget(n)
  Comm.bootstrapSyncBudget = n or 0
end

function Comm.ProbeObservedPeer(name, timestamp)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  local member = Store.GetMember(name)
  if not Store.ShouldProbeObservedAddon(member, timestamp or Utils.Now()) then
    return
  end

  Store.MarkHistorySyncPending(name)
  Store.MarkRosterSyncPending(name)
  Store.MarkAddonProbePending(name, timestamp or Utils.Now())
  Comm.QueueHello(name)
end

function Comm.QueueHistoryRequest(name)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  Comm.QueueChatRequest(name, Store.GetChatSyncAt(name))
end

function Comm.QueueRosterRequest(name)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  local sinceAt = Store.GetLatestRosterUpdatedAt()
  Store.MarkRosterRequested(name, Utils.Now())
  queueMessage(name, string.format("RREQ;%s;%s", ns.Constants.protocolVersion, tostring(sinceAt)), "RREQ|" .. name)
end

function Comm.QueueChatRequest(name, sinceAt)
  name = Utils.NormalizeName(name)
  if not name or name == Utils.PlayerName() then
    return
  end

  sinceAt = tonumber(sinceAt) or History.GetLatestChatAt()
  Store.MarkChatRequested(name, Utils.Now())
  queueMessage(name, string.format("CREQ;%s;%s", ns.Constants.protocolVersion, tostring(sinceAt)), "CREQ|" .. name)
end

function Comm.SendInfo(target)
  if not target then
    return
  end

  local playerName = Utils.PlayerName() or ""
  local profession1, profession2, profession1Icon, profession2Icon, profession1Skill, profession1MaxSkill, profession2Skill, profession2MaxSkill = Utils.SafeProfessions()
  local spec, specIcon = Utils.SafeSpec()

  local onlinePeers = Store.GetOnlineAddonMembers()
  local peerList = {}
  for _, name in ipairs(onlinePeers) do
    if name ~= playerName and name ~= target and #peerList < 5 then
      peerList[#peerList + 1] = name
    end
  end

  local payload = table.concat({
    "INFO",
    ns.Constants.protocolVersion,
    playerName,
    tostring(Utils.SafeLevel()),
    Utils.SafeClassFile(),
    Utils.SafeZoneName(),
    Utils.SafeGuildName(),
    Utils.EscapeField(profession1),
    Utils.EscapeField(profession2),
    tostring(profession1Icon or ""),
    tostring(profession2Icon or ""),
    tostring(History.GetLatestChatAt()),
    table.concat(peerList, ","),
    Utils.EscapeField(spec),
    tostring(specIcon or ""),
    tostring(profession1Skill or 0),
    tostring(profession1MaxSkill or 0),
    tostring(profession2Skill or 0),
    tostring(profession2MaxSkill or 0),
  }, ";")

  sendAddonWhisper(payload, target)
end

function Comm.BroadcastInfo()
  local peers = Store.GetOnlineAddonMembers()
  for _, name in ipairs(peers) do
    Comm.SendInfo(name)
  end
end

function Comm.ProbeOnlineAddonMembers(now)
  now = now or Utils.Now()

  for _, name in ipairs(Store.GetOnlineAddonMembers()) do
    local member = Store.GetMember(name)
    if member and not member.pendingAddonProbe and (now - math.max(member.lastAddonSeenAt or 0, member.lastObservedAt or 0)) >= ns.Constants.addonProbeTimeout then
      Store.MarkAddonProbePending(name, now)
      Comm.QueueHello(name)
    end
  end
end

function Comm.SendRosterSummary(target)
  queueMessage(target, string.format("RSUM;%s;%s;%s;%s", ns.Constants.protocolVersion, Utils.PlayerName() or "", tostring(Store.GetLatestRosterUpdatedAt()), tostring(#Store.ExportRosterProfiles(ns.Constants.rosterSyncLimit, 0))), string.format("RSUM|%s", target))
end

function Comm.SendChatSummary(target)
  local summary = History.GetRecentChatSummary(ns.Constants.historySyncLimit)
  queueMessage(target, string.format(
    "CSUM;%s;%s;%s;%s;%s;%s;%s",
    ns.Constants.protocolVersion,
    Utils.PlayerName() or "",
    tostring(summary.latestAt),
    tostring(summary.count),
    tostring(summary.oldestAt),
    Utils.EscapeField(summary.firstId),
    Utils.EscapeField(summary.lastId)
  ), string.format("CSUM|%s", target))
end

function Comm.SendRosterSummaries(maxDonors)
  local donors = Store.SelectSyncDonors(maxDonors or ns.Constants.maxPeriodicDonors)
  for _, donor in ipairs(donors) do
    Comm.QueueHello(donor)
    Comm.SendRosterSummary(donor)
  end
end

function Comm.SendChatSummaries(maxDonors)
  local donors = Store.SelectSyncDonors(maxDonors or ns.Constants.maxPeriodicDonors)
  for _, donor in ipairs(donors) do
    Comm.QueueHello(donor)
    Comm.SendChatSummary(donor)
  end
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
  local events = History.ExportChatSince(sinceAt, ns.Constants.historySyncLimit)
  for index, entry in ipairs(events) do
    queueMessage(target, encodeChatMessage(entry), string.format("CMSG|%s|%s", target, entry.id or index))
  end
end

function Comm.SendRosterProfiles(target)
  local profiles = Store.ExportRosterProfiles(ns.Constants.rosterSyncLimit, 0)
  for _, member in ipairs(profiles) do
    queueMessage(target, encodeRosterProfile(member), string.format("RPRO|%s|%s", target, member.name))
  end
end

function Comm.SendRosterProfilesSince(target, sinceAt)
  local profiles = Store.ExportRosterProfiles(ns.Constants.rosterSyncLimit, sinceAt)
  for _, member in ipairs(profiles) do
    queueMessage(target, encodeRosterProfile(member), string.format("RPRO|%s|%s", target, member.name))
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
  sendAddonWhisper(item.payload, item.target, item.context)
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
  local version = parts[2]
  local advertisedAt = 0
  local profession1 = ""
  local profession2 = ""
  local profession1Icon = ""
  local profession2Icon = ""

  if version == "1" then
    advertisedAt = tonumber(parts[10]) or 0
    profession1 = Utils.UnescapeField(parts[8])
    profession2 = Utils.UnescapeField(parts[9])
  else
    advertisedAt = tonumber(parts[12]) or 0
    profession1 = Utils.UnescapeField(parts[8])
    profession2 = Utils.UnescapeField(parts[9])
    profession1Icon = parts[10]
    profession2Icon = parts[11]
  end

  local member, changes = Store.SetProfile(name, {
    level = parts[4],
    classFile = parts[5],
    zone = parts[6],
    guildName = parts[7],
    profession1 = profession1,
    profession2 = profession2,
    profession1Icon = profession1Icon,
    profession2Icon = profession2Icon,
    profession1Skill = parts[16],
    profession1MaxSkill = parts[17],
    profession2Skill = parts[18],
    profession2MaxSkill = parts[19],
    spec = Utils.UnescapeField(parts[14]),
    specIcon = parts[15],
  }, Utils.Now())

  Store.MarkHistoryAdvertised(name, advertisedAt)

  -- Bootstrap sync: los primeros N en responder al channel HELLO se convierten en donors
  if Comm.bootstrapSyncBudget > 0 then
    Comm.bootstrapSyncBudget = Comm.bootstrapSyncBudget - 1
    Comm.QueueChatRequest(name, Store.GetChatSyncAt(name))
    Comm.QueueRosterRequest(name)
  end

  if not changes then
    if Store.ConsumePendingHistorySync(name) and Store.ShouldRequestChat(member, Utils.Now()) then
      Comm.QueueChatRequest(name, Store.GetChatSyncAt(name))
    end
    if Store.ConsumePendingRosterSync(name) and Store.ShouldRequestRoster(member, Utils.Now()) then
      Comm.QueueRosterRequest(name)
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

  if Store.ConsumePendingHistorySync(name) and Store.ShouldRequestChat(member, Utils.Now()) then
    Comm.QueueChatRequest(name, Store.GetChatSyncAt(name))
  end
  if Store.ConsumePendingRosterSync(name) and Store.ShouldRequestRoster(member, Utils.Now()) then
    Comm.QueueRosterRequest(name)
  end

  local peerListStr = parts[13]
  if peerListStr and peerListStr ~= "" then
    local self = Utils.PlayerName()
    for rawPeer in string.gmatch(peerListStr, "[^,]+") do
      local peer = Utils.NormalizeName(rawPeer)
      if peer and peer ~= self then
        -- Queue a direct HELLO to confirm this peer's status.
        -- Do NOT call MarkAddonSeen here: accepting a third-party peer list as
        -- proof of online status resets missedAddonProbes and pendingAddonProbe,
        -- which breaks DowngradeMissingAddonResponses and keeps offline peers
        -- stuck as online indefinitely.
        Comm.QueueHello(peer)
      end
    end
  end
end

function Comm.HandleHistoryRequest(parts, sender)
  local sinceAt = tonumber(parts[3]) or 0
  Comm.SendHistorySince(sender, sinceAt)
end

function Comm.HandleRosterRequest(parts, sender)
  local sinceAt = tonumber(parts[3]) or 0
  Comm.SendRosterProfilesSince(sender, sinceAt)
end

function Comm.HandleRosterSummary(parts, sender)
  local name = Utils.NormalizeName(parts[3]) or Utils.NormalizeName(sender)
  local latestRosterAt = tonumber(parts[4]) or 0
  if not name or latestRosterAt <= Store.GetLatestRosterUpdatedAt() then
    return
  end

  local member = Store.UpsertMember(name, { hasAddon = true })
  if Store.ShouldRequestRoster(member, Utils.Now()) then
    Comm.QueueRosterRequest(name)
  end
end

function Comm.HandleChatSummary(parts, sender)
  local name = Utils.NormalizeName(parts[3]) or Utils.NormalizeName(sender)
  local latestChatAt = tonumber(parts[4]) or 0
  local advertisedCount = tonumber(parts[5]) or 0
  local advertisedOldestAt = tonumber(parts[6]) or 0
  local advertisedFirstId = Utils.UnescapeField(parts[7])
  local advertisedLastId = Utils.UnescapeField(parts[8])
  if not name then
    return
  end

  local localSummary = History.GetRecentChatSummary(ns.Constants.historySyncLimit)
  local needsSync = latestChatAt > localSummary.latestAt
    or advertisedCount ~= localSummary.count
    or advertisedOldestAt ~= localSummary.oldestAt
    or advertisedFirstId ~= localSummary.firstId
    or advertisedLastId ~= localSummary.lastId

  if not needsSync then
    return
  end

  -- Superconjunto: solo saltamos el CREQ si todas estas condiciones son ciertas:
  --   1. Nuestro mensaje mas reciente es igual o mas nuevo (no nos falta el final)
  --   2. Tenemos al menos tantos mensajes (no nos falta cantidad)
  --   3. Tenemos estrictamente MAS mensajes (somos un superconjunto seguro),
  --      O bien los IDs de los extremos coinciden (misma ventana, divergencia interna ya resuelta)
  --   4. Nuestro mensaje mas antiguo es igual o mas antiguo (no nos falta el principio)
  -- La condicion 3 evita suprimir el CREQ cuando el remoto tiene la misma cantidad
  -- pero IDs distintos, lo que indicaria mensajes diferentes que aun necesitamos importar.
  local idsSame = localSummary.firstId == advertisedFirstId and localSummary.lastId == advertisedLastId
  local isSuperset = localSummary.latestAt >= latestChatAt
    and localSummary.count >= advertisedCount
    and (localSummary.count > advertisedCount or idsSame)
    and (advertisedOldestAt == 0 or localSummary.oldestAt <= advertisedOldestAt)
  if isSuperset then
    return
  end

  local member = Store.UpsertMember(name, { hasAddon = true })
  if Store.ShouldRequestChat(member, Utils.Now()) then
    local sinceAt = math.max(0, advertisedOldestAt - 1)
    Comm.QueueChatRequest(name, sinceAt)
  end
end

function Comm.HandleHistoryEvent(parts, sender)
  local entry

  if parts[1] == "CMSG" then
    entry = {
      id = Utils.UnescapeField(parts[3]),
      at = tonumber(parts[4]) or 0,
      source = Utils.UnescapeField(parts[5]),
      name = Utils.UnescapeField(parts[6]),
      type = "channel_message",
      details = Utils.UnescapeField(parts[7]),
    }
  else
    entry = {
      id = Utils.UnescapeField(parts[3]),
      at = tonumber(parts[4]) or 0,
      source = Utils.UnescapeField(parts[5]),
      name = Utils.UnescapeField(parts[6]),
      type = Utils.UnescapeField(parts[7]),
      details = Utils.UnescapeField(parts[8]),
    }
  end

  local _, added = History.AddImported(entry)
  if added then
    Store.MarkChatSynced(sender, entry.at)
    return
  end

  Store.MarkChatSynced(sender, entry.at)
end

function Comm.HandleRosterProfile(parts, sender)
  local name = Utils.NormalizeName(Utils.UnescapeField(parts[3]))
  if not name or name == Utils.PlayerName() then
    return
  end

  local hasAddon = parts[4] == "1"
  local timestamp = tonumber(parts[13]) or 0
  local member = Store.UpsertMember(name, {
    hasAddon = hasAddon,
    firstSeenAt = Store.GetMember(name).firstSeenAt,
    lastSeenAt = math.max(Store.GetMember(name).lastSeenAt or 0, timestamp),
  })

  Store.SetProfile(name, {
    level = parts[5],
    classFile = Utils.UnescapeField(parts[6]),
    zone = Utils.UnescapeField(parts[7]),
    guildName = Utils.UnescapeField(parts[8]),
    profession1 = Utils.UnescapeField(parts[9]),
    profession2 = Utils.UnescapeField(parts[10]),
    profession1Icon = parts[11],
    profession2Icon = parts[12],
    profession1Skill = parts[17],
    profession1MaxSkill = parts[18],
    profession2Skill = parts[19],
    profession2MaxSkill = parts[20],
    spec = Utils.UnescapeField(parts[15]),
    specIcon = parts[16],
  }, tonumber(parts[14]) or (timestamp > 0 and timestamp or Utils.Now()))

  if member then
    member.hasAddon = hasAddon
  end

  Store.MarkRosterSynced(sender, timestamp)
end

function Comm.HandleAddonMessage(prefix, text, _, sender)
  if prefix ~= ns.Constants.addonPrefix then
    return
  end

  local senderName = Utils.NormalizeName(sender)
  if senderName == Utils.PlayerName() then
    return
  end

  logCommTraffic("IN", senderName, text)

  local _, firstThisSession = Store.MarkAddonSeen(senderName, Utils.Now())
  if firstThisSession and ns.Notify then
    ns.Notify.PlayerDiscovered(senderName)
  end

  local parts = Utils.SplitMessage(text, ";")
  local messageType = parts[1]
  local version = parts[2]
  if not Utils.IsSupportedProtocolVersion(version) then
    return
  end

  if messageType == "REQ" then
    Comm.SendInfo(senderName)
    return
  end

  if messageType == "HELLO" then
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

  if messageType == "RREQ" then
    Comm.HandleRosterRequest(parts, senderName)
    return
  end

  if messageType == "RSUM" then
    Comm.HandleRosterSummary(parts, senderName)
    return
  end

  if messageType == "CSUM" then
    Comm.HandleChatSummary(parts, senderName)
    return
  end

  if messageType == "HEVT" or messageType == "CMSG" then
    Comm.HandleHistoryEvent(parts, senderName)
    return
  end

  if messageType == "CREQ" then
    Comm.HandleHistoryRequest(parts, senderName)
    return
  end

  if messageType == "RPRO" then
    Comm.HandleRosterProfile(parts, senderName)
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
