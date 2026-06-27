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
