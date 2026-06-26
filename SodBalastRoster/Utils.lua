local addonName, ns = ...

ns = ns or {}

ns.Constants = {
  channelName = "SODBALAST",
  addonPrefix = "SBRoster",
  protocolVersion = "4",
  scanInterval = 30,
  fullMissingThreshold = 2,
  partialMissingThreshold = 4,
  requestInterval = 1,
  addonProbeTimeout = 20,
  whoRequestInterval = 6,
  whoProfileTTL = 30 * 60,
  profileTTL = 15 * 60,
  rosterSummaryInterval = 5 * 60,
  rosterSyncCooldown = 5 * 60,
  rosterSyncWindow = 7 * 24 * 60 * 60,
  rosterSyncLimit = 50,
  chatSummaryInterval = 3 * 60,
  historySyncCooldown = 60,
  historySyncWindow = 24 * 60 * 60,
  historySyncLimit = 50,
  maxBootstrapDonors = 2,
  maxPeriodicDonors = 1,
  maxHistoryEntries = 500,
}

local Utils = {}
ns.Utils = Utils

local professionIconNameMap

local function buildProfessionIconNameMap()
  if professionIconNameMap then
    return professionIconNameMap
  end

  professionIconNameMap = {}

  local spellIds = {
    2259, -- Alchemy
    2018, -- Blacksmithing
    7411, -- Enchanting
    4036, -- Engineering
    2108, -- Leatherworking
    3908, -- Tailoring
    2550, -- Cooking
    3273, -- First Aid
    7620, -- Fishing
    2366, -- Herbalism
    2575, -- Mining
    8613, -- Skinning
  }

  for _, spellId in ipairs(spellIds) do
    local name, _, texture = GetSpellInfo(spellId)
    if name and texture then
      professionIconNameMap[name] = texture
    end
  end

  return professionIconNameMap
end

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

function Utils.ResolveProfessionIcon(name, icon)
  if icon and icon ~= 0 and icon ~= "" then
    return tonumber(icon) or icon
  end

  if not name or name == "" then
    return ""
  end

  local _, _, texture = GetSpellInfo(name)
  if texture then
    return texture
  end

  local nameMap = buildProfessionIconNameMap()
  return nameMap[name] or ""
end

function Utils.IsSupportedProtocolVersion(version)
  return version == "1" or version == "2" or version == "3" or version == "4"
end

function Utils.SafeProfessions()
  local primary1, primary2 = GetProfessions()
  local profession1 = ""
  local profession2 = ""
  local profession1Icon = ""
  local profession2Icon = ""

  if primary1 then
    local name1, icon1 = GetProfessionInfo(primary1)
    profession1 = name1 or ""
    profession1Icon = Utils.ResolveProfessionIcon(profession1, icon1)
  end

  if primary2 then
    local name2, icon2 = GetProfessionInfo(primary2)
    profession2 = name2 or ""
    profession2Icon = Utils.ResolveProfessionIcon(profession2, icon2)
  end

  if profession1 ~= "" or profession2 ~= "" then
    return profession1, profession2, profession1Icon, profession2Icon
  end

  if GetNumSkillLines and GetSkillLineInfo then
    local professions = {}

    for index = 1, GetNumSkillLines() do
      local skillName, isHeader, _, skillRank, _, _, skillMaxRank, isAbandonable = GetSkillLineInfo(index)
      if not isHeader and isAbandonable and skillName and skillName ~= "" and (skillRank or 0) > 0 and (skillMaxRank or 0) > 0 then
        professions[#professions + 1] = {
          name = skillName,
          icon = Utils.ResolveProfessionIcon(skillName),
        }
        if #professions >= 2 then
          break
        end
      end
    end

    return professions[1] and professions[1].name or "", professions[2] and professions[2].name or "", professions[1] and professions[1].icon or "", professions[2] and professions[2].icon or ""
  end

  return profession1, profession2, profession1Icon, profession2Icon
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
      local skillName, isHeader, isExpanded, skillRank, _, _, skillMaxRank, isAbandonable = GetSkillLineInfo(index)
      lines[#lines + 1] = string.format(
        "SkillLine[%d] name=%s header=%s expanded=%s rank=%s/%s abandonable=%s",
        index,
        tostring(skillName),
        tostring(isHeader),
        tostring(isExpanded),
        tostring(skillRank),
        tostring(skillMaxRank),
        tostring(isAbandonable)
      )
    end
  end

  local prof1, prof2, icon1, icon2 = Utils.SafeProfessions()
  lines[#lines + 1] = string.format("SafeProfessions=%s / %s icons=%s / %s", tostring(prof1), tostring(prof2), tostring(icon1), tostring(icon2))

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
