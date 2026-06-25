local addonName, ns = ...

ns = ns or {}

ns.Constants = {
  channelName = "SODBALAST",
  addonPrefix = "SBRoster",
  protocolVersion = "1",
  scanInterval = 30,
  fullMissingThreshold = 2,
  partialMissingThreshold = 4,
  requestInterval = 1,
  whoRequestInterval = 6,
  whoProfileTTL = 30 * 60,
  profileTTL = 15 * 60,
  historySummaryCooldown = 30,
  historySyncCooldown = 60,
  historySyncWindow = 24 * 60 * 60,
  historySyncLimit = 50,
  maxHistoryEntries = 500,
}

local Utils = {}
ns.Utils = Utils

function Utils.Now()
  return time()
end

function Utils.NormalizeName(name)
  if not name or name == "" then
    return nil
  end

  local normalized = Ambiguate(name, "none")
  if normalized and normalized ~= "" then
    return normalized
  end

  return name
end

function Utils.SafeGuildName()
  return GetGuildInfo("player") or ""
end

function Utils.SafeZoneName()
  return GetRealZoneText() or GetZoneText() or ""
end

function Utils.SafeClassFile()
  local _, classFile = UnitClass("player")
  return classFile or ""
end

function Utils.SafeLevel()
  return UnitLevel("player") or 0
end

function Utils.SafeProfessions()
  local primary1, primary2 = GetProfessions()
  local profession1 = ""
  local profession2 = ""

  if primary1 then
    profession1 = GetProfessionInfo(primary1) or ""
  end

  if primary2 then
    profession2 = GetProfessionInfo(primary2) or ""
  end

  if profession1 ~= "" or profession2 ~= "" then
    return profession1, profession2
  end

  if GetNumSkillLines and GetSkillLineInfo then
    local currentHeader = nil
    local professions = {}

    for index = 1, GetNumSkillLines() do
      local skillName, isHeader = GetSkillLineInfo(index)
      if isHeader then
        currentHeader = skillName
      elseif currentHeader == TRADE_SKILLS and skillName and skillName ~= "" then
        professions[#professions + 1] = skillName
        if #professions >= 2 then
          break
        end
      end
    end

    return professions[1] or "", professions[2] or ""
  end

  return profession1, profession2
end

function Utils.DebugProfessions()
  local lines = {}
  local primary1, primary2, archaeology, fishing, cooking = GetProfessions()

  lines[#lines + 1] = string.format(
    "GetProfessions p1=%s p2=%s arch=%s fish=%s cook=%s",
    tostring(primary1),
    tostring(primary2),
    tostring(archaeology),
    tostring(fishing),
    tostring(cooking)
  )

  if GetProfessionInfo then
    if primary1 then
      local name1, _, skill1, max1, _, _, skillLine1 = GetProfessionInfo(primary1)
      lines[#lines + 1] = string.format(
        "Profession1 name=%s skill=%s/%s skillLine=%s",
        tostring(name1),
        tostring(skill1),
        tostring(max1),
        tostring(skillLine1)
      )
    end

    if primary2 then
      local name2, _, skill2, max2, _, _, skillLine2 = GetProfessionInfo(primary2)
      lines[#lines + 1] = string.format(
        "Profession2 name=%s skill=%s/%s skillLine=%s",
        tostring(name2),
        tostring(skill2),
        tostring(max2),
        tostring(skillLine2)
      )
    end
  end

  if GetNumSkillLines and GetSkillLineInfo then
    local count = GetNumSkillLines()
    lines[#lines + 1] = string.format("GetNumSkillLines=%s", tostring(count))

    for index = 1, count do
      local skillName, isHeader, isExpanded, skillRank, _, _, skillMaxRank = GetSkillLineInfo(index)
      lines[#lines + 1] = string.format(
        "SkillLine[%d] name=%s header=%s expanded=%s rank=%s/%s",
        index,
        tostring(skillName),
        tostring(isHeader),
        tostring(isExpanded),
        tostring(skillRank),
        tostring(skillMaxRank)
      )
    end
  end

  local prof1, prof2 = Utils.SafeProfessions()
  lines[#lines + 1] = string.format("SafeProfessions=%s / %s", tostring(prof1), tostring(prof2))

  return lines
end

function Utils.SplitMessage(message, separator)
  local parts = {}
  if not message or message == "" then
    return parts
  end

  separator = separator or ";"
  local pattern = string.format("([^%s]+)", separator)
  for piece in string.gmatch(message, pattern) do
    parts[#parts + 1] = piece
  end
  return parts
end

function Utils.Trim(text)
  if not text then
    return ""
  end

  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Utils.ContainsInsensitive(text, needle)
  if needle == "" then
    return true
  end

  text = string.lower(text or "")
  needle = string.lower(needle or "")
  return string.find(text, needle, 1, true) ~= nil
end

function Utils.FormatLastSeen(timestamp)
  if not timestamp or timestamp <= 0 then
    return "-"
  end

  local seconds = max(0, Utils.Now() - timestamp)
  if seconds < 60 then
    return string.format("%ds", seconds)
  end

  local minutes = math.floor(seconds / 60)
  if minutes < 60 then
    return string.format("%dm", minutes)
  end

  local hours = math.floor(minutes / 60)
  if hours < 24 then
    return string.format("%dh", hours)
  end

  local days = math.floor(hours / 24)
  return string.format("%dd", days)
end

function Utils.PlayerName()
  return Utils.NormalizeName(UnitName("player"))
end

function Utils.IsTargetChannel(channelName, channelBaseName)
  local target = string.lower(ns.Constants.channelName or "")
  local base = string.lower(channelBaseName or "")
  local full = string.lower(channelName or "")

  if base == target then
    return true
  end

  if full == target then
    return true
  end

  return string.find(full, target, 1, true) ~= nil
end

function Utils.EscapeField(value)
  value = tostring(value or "")
  value = value:gsub("%%", "%%25")
  value = value:gsub(";", "%%3B")
  value = value:gsub("\n", "%%0A")
  value = value:gsub("\r", "%%0D")
  return value
end

function Utils.UnescapeField(value)
  value = tostring(value or "")
  value = value:gsub("%%0D", "\r")
  value = value:gsub("%%0A", "\n")
  value = value:gsub("%%3B", ";")
  value = value:gsub("%%25", "%%")
  return value
end

function Utils.Print(message)
  local prefix = "|cff33ff99SodBalastRoster|r"
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(string.format("%s %s", prefix, tostring(message)))
    return
  end

  print(prefix, message)
end
