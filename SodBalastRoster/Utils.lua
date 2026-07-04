local addonName, ns = ...

ns = ns or {}

ns.Constants = {
  channelName = "SODBALAST",
  addonPrefix = "SBRoster",
  protocolVersion = "5",
  scanInterval = 30,
  fullMissingThreshold = 2,
  partialMissingThreshold = 2,
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

local function computeSpec()
  local bestName, bestIcon, bestPoints = "", "", 0
  for tab = 1, GetNumTalentTabs() do
    -- SoD anadio "id" y "description" al frente/medio de la tupla en el patch 4.4.0 (2024-04-30):
    -- id, name, description, icon, pointsSpent, ... = GetTalentTabInfo(tab)
    local _, name, _, icon, pointsSpent = GetTalentTabInfo(tab)
    if name and (pointsSpent or 0) > bestPoints then
      bestName, bestIcon, bestPoints = name, icon, pointsSpent
    end
  end

  if bestPoints <= 0 then
    return "", ""
  end

  return bestName, bestIcon
end

function Utils.SafeSpec()
  if not (GetNumTalentTabs and GetTalentTabInfo) then
    return "", ""
  end

  local ok, name, icon = pcall(computeSpec)
  if not ok then
    return "", ""
  end

  return name or "", icon or ""
end

function Utils.DebugSpec()
  local lines = {}

  lines[#lines + 1] = string.format(
    "GetNumTalentTabs=%s GetTalentTabInfo=%s",
    tostring(GetNumTalentTabs ~= nil),
    tostring(GetTalentTabInfo ~= nil)
  )

  if GetNumTalentTabs then
    local ok, numTabs = pcall(GetNumTalentTabs)
    lines[#lines + 1] = string.format("GetNumTalentTabs() ok=%s value=%s", tostring(ok), tostring(numTabs))

    if ok and GetTalentTabInfo then
      for tab = 1, tonumber(numTabs) or 0 do
        local okTab, id, name, description, icon, pointsSpent = pcall(GetTalentTabInfo, tab)
        lines[#lines + 1] = string.format(
          "GetTalentTabInfo(%d) ok=%s id=%s name=%s description=%s icon=%s pointsSpent=%s",
          tab,
          tostring(okTab),
          tostring(id),
          tostring(name),
          tostring(description),
          tostring(icon),
          tostring(pointsSpent)
        )
      end
    end
  end

  local spec, specIcon = Utils.SafeSpec()
  lines[#lines + 1] = string.format("SafeSpec name=%s icon=%s", tostring(spec), tostring(specIcon))

  return lines
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
  return version == "1" or version == "2" or version == "3" or version == "4" or version == "5"
end

function Utils.CompareVersions(a, b)
  local partsA = tostring(a or "0"):gmatch("%d+")
  local partsB = tostring(b or "0"):gmatch("%d+")

  while true do
    local segmentA, segmentB = partsA(), partsB()
    if not segmentA and not segmentB then
      return 0
    end

    segmentA = tonumber(segmentA) or 0
    segmentB = tonumber(segmentB) or 0
    if segmentA ~= segmentB then
      return segmentA > segmentB and 1 or -1
    end
  end
end

function Utils.IsVersionNewer(candidate, current)
  if not candidate or candidate == "" then
    return false
  end

  return Utils.CompareVersions(candidate, current) > 0
end

function Utils.SafeProfessions()
  local primary1, primary2 = GetProfessions()
  local profession1 = ""
  local profession2 = ""
  local profession1Icon = ""
  local profession2Icon = ""
  local profession1Skill = 0
  local profession1MaxSkill = 0
  local profession2Skill = 0
  local profession2MaxSkill = 0

  if primary1 then
    local name1, icon1, skill1, max1 = GetProfessionInfo(primary1)
    profession1 = name1 or ""
    profession1Icon = Utils.ResolveProfessionIcon(profession1, icon1)
    profession1Skill = skill1 or 0
    profession1MaxSkill = max1 or 0
  end

  if primary2 then
    local name2, icon2, skill2, max2 = GetProfessionInfo(primary2)
    profession2 = name2 or ""
    profession2Icon = Utils.ResolveProfessionIcon(profession2, icon2)
    profession2Skill = skill2 or 0
    profession2MaxSkill = max2 or 0
  end

  if profession1 ~= "" or profession2 ~= "" then
    return profession1, profession2, profession1Icon, profession2Icon, profession1Skill, profession1MaxSkill, profession2Skill, profession2MaxSkill
  end

  if GetNumSkillLines and GetSkillLineInfo then
    local professions = {}

    for index = 1, GetNumSkillLines() do
      local skillName, isHeader, _, skillRank, _, _, skillMaxRank, isAbandonable = GetSkillLineInfo(index)
      if not isHeader and isAbandonable and skillName and skillName ~= "" and (skillRank or 0) > 0 and (skillMaxRank or 0) > 0 then
        professions[#professions + 1] = {
          name = skillName,
          icon = Utils.ResolveProfessionIcon(skillName),
          skill = skillRank or 0,
          maxSkill = skillMaxRank or 0,
        }
        if #professions >= 2 then
          break
        end
      end
    end

    return professions[1] and professions[1].name or "",
      professions[2] and professions[2].name or "",
      professions[1] and professions[1].icon or "",
      professions[2] and professions[2].icon or "",
      professions[1] and professions[1].skill or 0,
      professions[1] and professions[1].maxSkill or 0,
      professions[2] and professions[2].skill or 0,
      professions[2] and professions[2].maxSkill or 0
  end

  return profession1, profession2, profession1Icon, profession2Icon, profession1Skill, profession1MaxSkill, profession2Skill, profession2MaxSkill
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
  local startIndex = 1

  while true do
    local separatorIndex = string.find(message, separator, startIndex, true)
    if not separatorIndex then
      parts[#parts + 1] = string.sub(message, startIndex)
      break
    end

    parts[#parts + 1] = string.sub(message, startIndex, separatorIndex - 1)
    startIndex = separatorIndex + #separator
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

function Utils.SplitNameRealm(fullName)
  if not fullName or fullName == "" then
    return fullName, nil
  end

  local name, realm = string.match(fullName, "^([^%-]+)%-(.+)$")
  if not name then
    return fullName, nil
  end

  return name, realm
end

function Utils.RealmName()
  if not GetRealmName then
    return "unknown"
  end

  return Utils.Trim(GetRealmName() or "")
end

function Utils.PlayerRealmSuffix()
  local realm = Utils.RealmName()
  if not realm or realm == "" or realm == "unknown" then
    return nil
  end

  local suffix = (realm:gsub("%s+", ""))
  if suffix == "" then
    return nil
  end

  return suffix
end

function Utils.StorageScopeKey()
  local projectId = tostring(WOW_PROJECT_ID or "unknown")
  local realmName = string.lower(Utils.RealmName())
  if realmName == "" then
    realmName = "unknown"
  end

  return string.format("%s:%s", projectId, realmName)
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
