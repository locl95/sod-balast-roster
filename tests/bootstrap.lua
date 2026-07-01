local Bootstrap = {}

local function installGlobals(env)
  _G.__SBR_TEST_ENV = env
  _G.SodBalastRosterDB = nil
  _G.max = math.max
  _G.Ambiguate = function(name)
    if not name then
      return nil
    end

    return tostring(name):match("^[^-]+") or tostring(name)
  end
  _G.UnitName = function(unit)
    if unit == "player" then
      return env.playerName
    end

    return nil
  end
  _G.GetRealmName = function()
    return env.realmName or "Wild Growth"
  end
  _G.time = function()
    return env.now
  end
  _G.GetGuildInfo = function()
    return env.guildName or ""
  end
  _G.GetRealZoneText = function()
    return env.zoneName or ""
  end
  _G.GetZoneText = function()
    return env.zoneName or ""
  end
  _G.UnitClass = function()
    return "Warrior", env.classFile or "WARRIOR"
  end
  _G.UnitLevel = function()
    return env.level or 60
  end
  _G.GetSpellInfo = function(spell)
    return spell, nil, nil
  end
  _G.GetProfessions = function()
    return nil, nil, nil, nil, nil
  end
  _G.GetNumSkillLines = function()
    return 0
  end
  _G.GetSkillLineInfo = function()
    return nil
  end
  _G.JoinPermanentChannel = function(name)
    env.joinedChannels[#env.joinedChannels + 1] = name
  end
  _G.GetChannelName = function(name)
    if name == env.channel.name then
      return env.channel.id
    end

    return 0
  end
  _G.GetNumDisplayChannels = function()
    return env.channel.displayCount
  end
  _G.GetChannelDisplayInfo = function(index)
    if index ~= env.channel.displayIndex then
      return nil
    end

    return env.channel.name, false, false, env.channel.id, env.channel.memberCount, true, "CHANNEL_CATEGORY_CUSTOM", 0
  end
  _G.SetSelectedDisplayChannel = function(index)
    env.channel.selectedDisplayIndex = index
  end
  _G.C_Timer = {
    After = function(_, callback)
      callback()
    end,
  }
  _G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function()
    end,
    SendAddonMessage = function(prefix, payload, channel, target)
      env.sentAddonMessages[#env.sentAddonMessages + 1] = {
        prefix = prefix,
        payload = payload,
        channel = channel,
        target = target,
      }
    end,
  }
  _G.SendAddonMessage = function(prefix, payload, channel, target)
    env.sentAddonMessages[#env.sentAddonMessages + 1] = {
      prefix = prefix,
      payload = payload,
      channel = channel,
      target = target,
    }
  end
  _G.DEFAULT_CHAT_FRAME = {
    AddMessage = function()
    end,
  }
  _G.WOW_PROJECT_ID = env.projectId or 11
end

local function loadAddonFile(path, ns)
  local chunk = assert(loadfile(path))
  return chunk("SodBalastRoster", ns)
end

function Bootstrap.newContext()
  local env = {
    now = 1000,
    playerName = "Tester",
    realmName = "Wild Growth",
    projectId = 11,
    classFile = "WARRIOR",
    zoneName = "Durotar",
    guildName = "Raiders",
    level = 60,
    sentAddonMessages = {},
    joinedChannels = {},
    channel = {
      id = 1,
      name = "SODBALAST",
      displayIndex = 1,
      displayCount = 1,
      memberCount = 2,
      selectedDisplayIndex = nil,
    },
  }

  installGlobals(env)

  local ns = {}
  local basePath = "./SodBalastRoster/"
  loadAddonFile(basePath .. "Utils.lua", ns)
  loadAddonFile(basePath .. "Store.lua", ns)
  loadAddonFile(basePath .. "History.lua", ns)
  loadAddonFile(basePath .. "Comm.lua", ns)
  loadAddonFile(basePath .. "Channel.lua", ns)

  ns.Store.Init()
  ns.Store.ResetTransientState()
  ns.History.Init()

  return {
    ns = ns,
    env = env,
    resetDB = function()
      _G.SodBalastRosterDB = nil
      ns.Store.Init()
      ns.Store.ResetTransientState()
      ns.History.Init()
    end,
    setNow = function(value)
      env.now = value
    end,
    setChannelMemberCount = function(value)
      env.channel.memberCount = value
    end,
  }
end

function Bootstrap.assertEqual(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEqual failed") .. string.format(" (expected=%s, actual=%s)", tostring(expected), tostring(actual)), 2)
  end
end

function Bootstrap.assertTrue(value, message)
  if not value then
    error(message or "assertTrue failed", 2)
  end
end

function Bootstrap.assertNil(value, message)
  if value ~= nil then
    error((message or "assertNil failed") .. string.format(" (actual=%s)", tostring(value)), 2)
  end
end

function Bootstrap.assertFalse(value, message)
  if value then
    error(message or "assertFalse failed", 2)
  end
end

return Bootstrap
