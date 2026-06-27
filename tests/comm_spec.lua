test("Comm.HandleChatSummary requests sync when remote chat window diverges", function(t)
  local ctx = t.newContext()
  ctx.setNow(1000)
  local first = ctx.ns.History.AddChannelMessage("Alice", "one", 1)
  local second = ctx.ns.History.AddChannelMessage("Bob", "two", 2)

  ctx.ns.Comm.HandleChatSummary({
    "CSUM",
    "4",
    "Remote",
    tostring(second.at),
    "2",
    tostring(first.at),
    "remote:1",
    "remote:2",
  }, "Remote")

  t.assertEqual(#ctx.ns.Comm.queue, 1)
  t.assertEqual(ctx.ns.Comm.queue[1].payload, string.format("CREQ;4;%s", tostring(first.at - 1)))
  t.assertEqual(ctx.ns.Comm.queue[1].target, "Remote")
end)

test("Comm.HandleChatSummary skips sync when summaries already match", function(t)
  local ctx = t.newContext()
  ctx.setNow(1200)
  local first = ctx.ns.History.AddChannelMessage("Alice", "one", 1)
  local second = ctx.ns.History.AddChannelMessage("Bob", "two", 2)

  ctx.ns.Comm.HandleChatSummary({
    "CSUM",
    "4",
    "Remote",
    tostring(second.at),
    "2",
    tostring(first.at),
    first.id,
    second.id,
  }, "Remote")

  t.assertEqual(#ctx.ns.Comm.queue, 0)
end)

test("Comm.QueueHistoryRequest uses canonical chat sync timestamp", function(t)
  local ctx = t.newContext()
  local member = ctx.ns.Store.GetMember("Remote")
  member.lastHistorySyncAt = 77
  member.lastChatSyncAt = 0

  ctx.ns.Comm.QueueHistoryRequest("Remote")

  t.assertEqual(#ctx.ns.Comm.queue, 1)
  t.assertEqual(ctx.ns.Comm.queue[1].payload, "CREQ;4;77")
end)

test("Comm.ProbeOnlineAddonMembers queues hello for stale addon peer", function(t)
  local ctx = t.newContext()
  local store = ctx.ns.Store
  local comm = ctx.ns.Comm

  local member = store.MarkAddonSeen("Remote", 900)
  member.lastAddonSeenAt = 900
  member.lastObservedAt = 900

  comm.ProbeOnlineAddonMembers(1000)

  t.assertEqual(#comm.queue, 1)
  t.assertEqual(comm.queue[1].payload, "HELLO;4;Tester")
  t.assertTrue(member.pendingAddonProbe)
end)
