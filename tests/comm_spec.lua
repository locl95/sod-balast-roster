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

test("Comm.HandleAddonMessage preserves empty INFO fields without shifting advertised chat timestamp", function(t)
  local ctx = t.newContext()

  ctx.ns.Comm.HandleAddonMessage(
    "SBRoster",
    "INFO;4;Cursefettfr;25;WARLOCK;Tirisfal Glades;F R E S H V;Alchemy;Herbalism;136240;;1782588517",
    "WHISPER",
    "Cursefettfr"
  )

  local member = ctx.ns.Store.GetMember("Cursefettfr")
  t.assertEqual(member.zone, "Tirisfal Glades")
  t.assertEqual(member.guildName, "F R E S H V")
  t.assertEqual(member.profession1Icon, "136240")
  t.assertEqual(member.profession2Icon, "")
  t.assertEqual(member.lastHistoryAdvertisedAt, 1782588517)
end)

test("Comm.HandleRosterProfile preserves empty RPRO fields without shifting timestamps", function(t)
  local ctx = t.newContext()

  ctx.ns.Comm.HandleRosterProfile({
    "RPRO",
    "4",
    "Cursefettfr",
    "1",
    "25",
    "WARLOCK",
    "Tirisfal Glades",
    "F R E S H V",
    "Alchemy",
    "Herbalism",
    "136240",
    "",
    "1782591250",
    "1782591208",
  }, "Cursefettfr")

  local member = ctx.ns.Store.GetMember("Cursefettfr")
  t.assertEqual(member.zone, "Tirisfal Glades")
  t.assertEqual(member.guildName, "F R E S H V")
  t.assertEqual(member.profession1Icon, "136240")
  t.assertEqual(member.profession2Icon, "")
  t.assertEqual(member.lastSeenAt, 1782591250)
  t.assertEqual(member.lastProfileAt, 1782591208)
end)

test("Comm.HandleChatSummary skips CREQ when local has strictly more messages (superset guard)", function(t)
  local ctx = t.newContext()
  ctx.setNow(1000)
  local first = ctx.ns.History.AddChannelMessage("Alice", "one", 1)
  local second = ctx.ns.History.AddChannelMessage("Bob", "two", 2)
  local third = ctx.ns.History.AddChannelMessage("Carol", "three", 3)

  -- Remote advertises same latestAt and oldestAt but fewer messages and different IDs.
  -- This is the 3rd-peer scenario: we already absorbed those messages from elsewhere.
  ctx.ns.Comm.HandleChatSummary({
    "CSUM",
    "4",
    "Remote",
    tostring(third.at),
    "2",
    tostring(first.at),
    "remote:1",
    "remote:2",
  }, "Remote")

  t.assertEqual(#ctx.ns.Comm.queue, 0)
end)

test("Comm.HandleChatSummary sends CREQ when remote has older messages local lacks", function(t)
  local ctx = t.newContext()
  ctx.setNow(1000)
  ctx.ns.History.AddChannelMessage("Alice", "one", 1)
  local second = ctx.ns.History.AddChannelMessage("Bob", "two", 2)

  -- Remote advertises the same count and latestAt but an older oldestAt,
  -- meaning it has messages that predate our oldest entry.
  ctx.ns.Comm.HandleChatSummary({
    "CSUM",
    "4",
    "Remote",
    tostring(second.at),
    "2",
    tostring(second.at - 100),
    "remote:old",
    "remote:new",
  }, "Remote")

  t.assertEqual(#ctx.ns.Comm.queue, 1)
  t.assertEqual(ctx.ns.Comm.queue[1].target, "Remote")
end)

test("Comm.HandleInfo peer list queues HELLO instead of marking peers online directly", function(t)
  -- Regression test: peers mentioned in a third-party INFO peer list must NOT be
  -- marked online via MarkAddonSeen, because that resets missedAddonProbes and
  -- pendingAddonProbe, breaking offline detection for crashed/disconnected peers.
  local ctx = t.newContext()
  local store = ctx.ns.Store
  local comm = ctx.ns.Comm

  -- Peer "Alice" is known to be online and has the addon; simulate she is being
  -- probed (pendingAddonProbe=true, missedAddonProbes=1 already accumulated).
  local alice = store.MarkAddonSeen("Alice", 900)
  alice.pendingAddonProbe = true
  alice.missedAddonProbes = 1

  -- "Remote" sends us INFO with Alice in the peer list.
  ctx.setNow(1000)
  comm.HandleInfo({
    "INFO", "4", "Remote",
    "60", "WARRIOR", "Durotar", "Raiders",
    "", "", "", "",
    "0",
    "Alice",
  }, "Remote")

  -- Alice's probe state must be untouched: she has NOT responded to us directly.
  t.assertEqual(alice.missedAddonProbes, 1)
  t.assertTrue(alice.pendingAddonProbe)

  -- A HELLO must have been queued to Alice so we confirm her status directly.
  local helloQueued = false
  for _, msg in ipairs(comm.queue) do
    if msg.target == "Alice" and msg.payload:find("^HELLO") then
      helloQueued = true
      break
    end
  end
  t.assertTrue(helloQueued)
end)

test("Comm.HandleInfo peer list does not resurrect offline peer as online", function(t)
  -- Regression test: an offline peer mentioned in a third-party peer list must
  -- not have isOnlineInChannel set back to true.
  local ctx = t.newContext()
  local store = ctx.ns.Store
  local comm = ctx.ns.Comm

  -- "Bob" was online, got marked offline (e.g. BYE received or probes exhausted).
  store.MarkAddonSeen("Bob", 800)
  store.MarkOffline("Bob")
  t.assertFalse(store.GetMember("Bob").isOnlineInChannel)

  -- "Remote" sends INFO with Bob in the peer list (Remote hasn't caught up yet).
  ctx.setNow(1000)
  comm.HandleInfo({
    "INFO", "4", "Remote",
    "60", "WARRIOR", "Durotar", "Raiders",
    "", "", "", "",
    "0",
    "Bob",
  }, "Remote")

  -- Bob must remain offline.
  t.assertFalse(store.GetMember("Bob").isOnlineInChannel)
end)
