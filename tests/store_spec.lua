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
