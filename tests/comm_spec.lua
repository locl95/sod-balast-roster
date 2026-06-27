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

test("Comm.HandleHistoryEvent imports CMSG as channel_message", function(t)
  local ctx = t.newContext()

  ctx.ns.Comm.HandleHistoryEvent({
    "CMSG",
    "4",
    "chan:500",
    "1500",
    "Remote",
    "Alice",
    "hello from peer",
  }, "Remote")

  local entries = ctx.ns.History.GetEntries()
  t.assertEqual(#entries, 1)
  t.assertEqual(entries[1].id, "chan:500")
  t.assertEqual(entries[1].type, "channel_message")
  t.assertEqual(entries[1].name, "Alice")
  t.assertEqual(entries[1].source, "Remote")
  t.assertEqual(entries[1].details, "hello from peer")
end)

test("Comm.HandleHistoryEvent updates sender chat sync for CMSG", function(t)
  local ctx = t.newContext()

  ctx.ns.Comm.HandleHistoryEvent({
    "CMSG",
    "4",
    "chan:501",
    "1600",
    "Remote",
    "Bob",
    "ping",
  }, "Remote")

  t.assertEqual(ctx.ns.Store.GetChatSyncAt("Remote"), 1600)
end)
