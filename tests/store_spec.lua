test("Store migrates legacy history sync timestamp into chat sync", function(t)
  local ctx = t.newContext()
  local member = ctx.ns.Store.GetMember("Remote")
  member.lastHistorySyncAt = 42
  member.lastChatSyncAt = 0

  member = ctx.ns.Store.GetMember("Remote")

  t.assertEqual(member.lastChatSyncAt, 42)
  t.assertEqual(ctx.ns.Store.GetChatSyncAt("Remote"), 42)
end)

test("Store.SetProfile applies spec and specIcon", function(t)
  local ctx = t.newContext()
  ctx.ns.Store.UpsertMember("Remote", {})

  local member, changes = ctx.ns.Store.SetProfile("Remote", {
    spec = "Fire",
    specIcon = "135813",
  }, 100)

  t.assertEqual(member.spec, "Fire")
  t.assertEqual(member.specIcon, "135813")
  t.assertEqual(changes.spec.new, "Fire")
end)

test("Store.MarkChatSynced keeps chat and legacy history timestamps aligned", function(t)
  local ctx = t.newContext()
  ctx.ns.Store.MarkChatSynced("Remote", 123)

  local member = ctx.ns.Store.GetMember("Remote")
  t.assertEqual(member.lastChatSyncAt, 123)
  t.assertEqual(member.lastHistorySyncAt, 123)
  t.assertEqual(ctx.ns.Store.GetHistorySyncAt("Remote"), 123)
end)

test("Store.DowngradeMissingAddonResponses marks addon peer offline after repeated missed probes", function(t)
  local ctx = t.newContext()
  local store = ctx.ns.Store
  local now = 1000
  local member = store.MarkAddonSeen("Remote", now)
  member.hasAddon = true

  store.MarkAddonProbePending("Remote", now - 30)
  local changed = store.DowngradeMissingAddonResponses(now)
  t.assertEqual(#changed, 0)
  t.assertEqual(member.missedAddonProbes, 1)
  t.assertTrue(member.isOnlineInChannel)

  store.MarkAddonProbePending("Remote", now - 30)
  changed = store.DowngradeMissingAddonResponses(now)
  t.assertEqual(#changed, 1)
  t.assertFalse(member.isOnlineInChannel)
  t.assertEqual(changed[1].name, "Remote")
end)

test("Store.Init scopes saved variables by project and realm", function(t)
  local ctx = t.newContext()

  ctx.ns.Store.GetMember("SoDPlayer")

  _G.WOW_PROJECT_ID = 2
  ctx.env.realmName = "Stitches"
  ctx.ns.Store.Init()

  t.assertNil(ctx.ns.Store.GetRoster().SoDPlayer)

  ctx.ns.Store.GetMember("HardcorePlayer")

  _G.WOW_PROJECT_ID = 11
  ctx.env.realmName = "Wild Growth"
  ctx.ns.Store.Init()

  t.assertTrue(ctx.ns.Store.GetRoster().SoDPlayer ~= nil)
  t.assertNil(ctx.ns.Store.GetRoster().HardcorePlayer)
end)

test("Store.PurgeLegacyData removes unscoped data left by pre-scoping saved variables", function(t)
  local ctx = t.newContext()

  ctx.ns.Store.GetMember("SoDPlayer")
  t.assertFalse(ctx.ns.Store.HasLegacyData())

  _G.SodBalastRosterDB.roster = { LegacyPlayer = { name = "LegacyPlayer" } }

  t.assertTrue(ctx.ns.Store.HasLegacyData())

  local removed = ctx.ns.Store.PurgeLegacyData()
  t.assertTrue(removed > 0)
  t.assertFalse(ctx.ns.Store.HasLegacyData())
  t.assertTrue(_G.SodBalastRosterDB.scopes ~= nil)
  t.assertTrue(ctx.ns.Store.GetRoster().SoDPlayer ~= nil)
end)

test("Store.PurgeWrongRealmMembers removes entries synced from a different realm", function(t)
  local ctx = t.newContext()
  ctx.env.realmName = "Wild Growth"

  t.assertEqual(ctx.ns.Utils.PlayerRealmSuffix(), "WildGrowth")

  ctx.ns.Store.GetMember("SameRealmFriend")
  ctx.ns.Store.GetMember("Alice-WildGrowth")
  ctx.ns.Store.GetMember("Mongooser-LivingFlame")

  t.assertFalse(ctx.ns.Store.IsWrongRealmMember(ctx.ns.Store.GetMember("SameRealmFriend")))
  t.assertFalse(ctx.ns.Store.IsWrongRealmMember(ctx.ns.Store.GetMember("Alice-WildGrowth")))
  t.assertTrue(ctx.ns.Store.IsWrongRealmMember(ctx.ns.Store.GetMember("Mongooser-LivingFlame")))

  local removed = ctx.ns.Store.PurgeWrongRealmMembers()

  t.assertEqual(removed, 1)
  t.assertTrue(ctx.ns.Store.GetRoster().SameRealmFriend ~= nil)
  t.assertTrue(ctx.ns.Store.GetRoster()["Alice-WildGrowth"] ~= nil)
  t.assertNil(ctx.ns.Store.GetRoster()["Mongooser-LivingFlame"])
end)
