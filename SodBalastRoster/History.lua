local addonName, ns = ...

local Utils = ns.Utils
local History = {}
ns.History = History

local function buildLegacyId(entry, index)
  return string.format("legacy:%s:%s:%s", tostring(entry.at or 0), tostring(entry.name or "?"), tostring(index))
end

local function rebuildIndex()
  ns.historyIndex = {}
  local entries = ns.db.history

  for index, entry in ipairs(entries) do
    entry.id = entry.id or buildLegacyId(entry, index)
    entry.source = entry.source or Utils.PlayerName() or "unknown"
    ns.historyIndex[entry.id] = true
  end
end

local function nextEventId()
  local meta = ns.db.historyMeta
  local source = Utils.PlayerName() or "unknown"
  local sequence = meta.nextSequence or 1
  meta.nextSequence = sequence + 1
  return string.format("%s:%s", source, sequence), source
end

local function buildChannelMessageId(name, details, lineId, at)
  if lineId and lineId ~= 0 and lineId ~= "" then
    return string.format("chan:%s", tostring(lineId))
  end

  local bucket = math.floor((tonumber(at) or Utils.Now()) / 2)
  return string.format("chan:%s:%s:%s", Utils.NormalizeName(name) or "?", Utils.Trim(details or ""), bucket)
end

local function hasEquivalentChannelMessage(name, details, at)
  local normalizedName = Utils.NormalizeName(name) or "?"
  details = Utils.Trim(details or "")
  at = tonumber(at) or 0

  for _, entry in ipairs(ns.db.history) do
    if entry.type == "channel_message"
      and (Utils.NormalizeName(entry.name) or "?") == normalizedName
      and Utils.Trim(entry.details or "") == details
      and math.abs((tonumber(entry.at) or 0) - at) <= 2 then
      return true
    end
  end

  return false
end

local function insertEntry(entry)
  local entries = ns.db.history
  entries[#entries + 1] = entry
  table.sort(entries, function(left, right)
    if (left.at or 0) ~= (right.at or 0) then
      return (left.at or 0) < (right.at or 0)
    end

    return tostring(left.id or "") < tostring(right.id or "")
  end)
  History.Trim()
  ns.historyIndex[entry.id] = true
  return entry
end

function History.Init()
  ns.historyDirty = false
  rebuildIndex()
end

function History.GetEntries()
  return ns.db.history
end

function History.Trim()
  local entries = History.GetEntries()
  while #entries > ns.Constants.maxHistoryEntries do
    table.remove(entries, 1)
  end
  rebuildIndex()
end

function History.Add(eventType, name, details)
  local id, source = nextEventId()
  local entry = {
    id = id,
    source = source,
    type = eventType,
    name = Utils.NormalizeName(name) or "?",
    at = Utils.Now(),
    details = details,
  }

  ns.historyDirty = true
  return insertEntry(entry)
end

function History.AddWithId(eventId, eventType, name, details, at, source)
  if not eventId or ns.historyIndex[eventId] then
    return nil
  end

  local entry = {
    id = eventId,
    source = source or Utils.PlayerName() or "unknown",
    type = eventType,
    name = Utils.NormalizeName(name) or "?",
    at = tonumber(at) or Utils.Now(),
    details = details,
  }

  ns.historyDirty = true
  return insertEntry(entry)
end

function History.AddImported(entry)
  if not entry or not entry.id or ns.historyIndex[entry.id] then
    return nil, false
  end

  if entry.type == "channel_message" and hasEquivalentChannelMessage(entry.name, entry.details, entry.at) then
    return nil, false
  end

  local imported = {
    id = entry.id,
    source = Utils.NormalizeName(entry.source) or "remote",
    type = entry.type,
    name = Utils.NormalizeName(entry.name) or "?",
    at = tonumber(entry.at) or Utils.Now(),
    details = entry.details,
  }

  return insertEntry(imported), true
end

function History.AddChannelMessage(sender, message, lineId)
  message = Utils.Trim(message or "")
  if message == "" then
    return nil
  end

  local now = Utils.Now()
  if hasEquivalentChannelMessage(sender, message, now) then
    return nil
  end

  return History.AddWithId(buildChannelMessageId(sender, message, lineId, now), "channel_message", sender, message, now, Utils.NormalizeName(sender) or "channel")
end

function History.GetLatestTimestamp()
  local latest = 0
  for _, entry in ipairs(History.GetEntries()) do
    if (entry.at or 0) > latest then
      latest = entry.at
    end
  end
  return latest
end

function History.ExportRecentSince(sinceAt, limit)
  sinceAt = tonumber(sinceAt) or 0
  limit = limit or ns.Constants.historySyncLimit

  local windowStart = Utils.Now() - ns.Constants.historySyncWindow
  local eligible = {}

  for _, entry in ipairs(History.GetEntries()) do
    if (entry.at or 0) > sinceAt and (entry.at or 0) >= windowStart then
      eligible[#eligible + 1] = entry
    end
  end

  if #eligible <= limit then
    return eligible
  end

  local startIndex = #eligible - limit + 1
  local recent = {}
  for index = startIndex, #eligible do
    recent[#recent + 1] = eligible[index]
  end

  return recent
end
