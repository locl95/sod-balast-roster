test("Store migrates legacy history sync timestamp into chat sync", function(t)
  local ctx = t.newContext()
  local member = ctx.ns.Store.GetMember("Remote")
  member.lastHistorySyncAt = 42
  member.lastChatSyncAt = 0

  member = ctx.ns.Store.GetMember("Remote")

  t.assertEqual(member.lastChatSyncAt, 42)
  t.assertEqual(ctx.ns.Store.GetChatSyncAt("Remote"), 42)
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
