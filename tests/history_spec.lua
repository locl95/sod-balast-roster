test("History.GetRecentChatSummary returns recent chat window metadata", function(t)
  local ctx = t.newContext()
  ctx.setNow(500)

  local first = ctx.ns.History.AddChannelMessage("Alice", "hello", 10)
  ctx.setNow(510)
  local second = ctx.ns.History.AddChannelMessage("Bob", "hi", 11)
  ctx.ns.History.Add("joined_channel", "Carol")

  local summary = ctx.ns.History.GetRecentChatSummary(50)
  t.assertEqual(summary.count, 2)
  t.assertEqual(summary.oldestAt, first.at)
  t.assertEqual(summary.latestAt, second.at)
  t.assertEqual(summary.firstId, first.id)
  t.assertEqual(summary.lastId, second.id)
end)

test("History.AddImported deduplicates equivalent remote chat messages", function(t)
  local ctx = t.newContext()
  ctx.setNow(700)
  ctx.ns.History.AddChannelMessage("Alice", "same text", nil)

  local imported, added = ctx.ns.History.AddImported({
    id = "remote:1",
    source = "Remote",
    name = "Alice",
    type = "channel_message",
    details = "same text",
    at = 701,
  })

  t.assertNil(imported)
  t.assertEqual(added, false)
  t.assertEqual(#ctx.ns.History.GetEntries(), 1)
end)

test("History.AddImported deduplicates relayed chat messages with small peer clock skew", function(t)
  local ctx = t.newContext()
  ctx.setNow(1000)
  ctx.ns.History.AddChannelMessage("Alice", "same text", 10)

  local imported, added = ctx.ns.History.AddImported({
    id = "remote:skew",
    source = "Remote",
    name = "Alice",
    type = "channel_message",
    details = "same text",
    at = 1004,
  })

  t.assertNil(imported)
  t.assertEqual(added, false)
  t.assertEqual(#ctx.ns.History.GetEntries(), 1)
end)

test("History.AddChannelMessage still keeps distinct repeated local messages", function(t)
  local ctx = t.newContext()
  ctx.setNow(1200)
  local first = ctx.ns.History.AddChannelMessage("Alice", "same text", 10)

  ctx.setNow(1204)
  local second = ctx.ns.History.AddChannelMessage("Alice", "same text", 11)

  t.assertTrue(first ~= nil)
  t.assertTrue(second ~= nil)
  t.assertEqual(#ctx.ns.History.GetEntries(), 2)
end)

test("History.AddImported promotes hash ID to canonical lineId on content match", function(t)
  local ctx = t.newContext()
  ctx.setNow(800)
  -- AddChannelMessage with no lineId produces a hash ID.
  local local_entry = ctx.ns.History.AddChannelMessage("Alice", "upgrade me", nil)
  t.assertFalse(string.match(local_entry.id, "^chan:%d+$") ~= nil, "precondition: hash ID expected")

  -- Remote sends same message with a canonical lineId.
  local imported, added = ctx.ns.History.AddImported({
    id = "chan:999",
    source = "Remote",
    name = "Alice",
    type = "channel_message",
    details = "upgrade me",
    at = 800,
  })

  t.assertNil(imported)
  t.assertEqual(added, false)
  -- The existing entry should now carry the canonical ID.
  local entries = ctx.ns.History.GetEntries()
  t.assertEqual(#entries, 1)
  t.assertEqual(entries[1].id, "chan:999")
end)
