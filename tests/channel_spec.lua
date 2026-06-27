test("Channel.ScanRoster records addon timeout as left_channel", function(t)
  local ctx = t.newContext()
  local store = ctx.ns.Store
  local channel = ctx.ns.Channel

  local member = store.MarkAddonSeen("Remote", 900)
  member.hasAddon = true
  store.MarkAddonProbePending("Remote", 970)
  member.missedAddonProbes = 3

  ctx.setNow(1000)
  ctx.setChannelMemberCount(1)
  local ok = channel.ScanRoster()

  t.assertTrue(ok)
  t.assertFalse(member.isOnlineInChannel)
  t.assertEqual(channel.lastScanReason, "roster_unavailable")

  local entries = ctx.ns.History.GetEntries()
  t.assertEqual(#entries, 1)
  t.assertEqual(entries[1].type, "left_channel")
  t.assertEqual(entries[1].name, "Remote")
  t.assertEqual(entries[1].details, "addon_timeout")
end)
