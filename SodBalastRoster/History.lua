local addonName, ns = ...

local Utils = ns.Utils
local History = {}
ns.History = History

function History.GetEntries()
  return ns.db.history
end

function History.Trim()
  local entries = History.GetEntries()
  while #entries > ns.Constants.maxHistoryEntries do
    table.remove(entries, 1)
  end
end

function History.Add(eventType, name, details)
  local entry = {
    type = eventType,
    name = Utils.NormalizeName(name) or "?",
    at = Utils.Now(),
    details = details,
  }

  local entries = History.GetEntries()
  entries[#entries + 1] = entry
  History.Trim()
  return entry
end
