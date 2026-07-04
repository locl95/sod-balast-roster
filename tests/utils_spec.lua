test("Utils.SplitMessage preserves empty fields", function(t)
  local ctx = t.newContext()
  local parts = ctx.ns.Utils.SplitMessage("A;B;;D;", ";")

  t.assertEqual(#parts, 5)
  t.assertEqual(parts[1], "A")
  t.assertEqual(parts[2], "B")
  t.assertEqual(parts[3], "")
  t.assertEqual(parts[4], "D")
  t.assertEqual(parts[5], "")
end)

test("Utils.CompareVersions orders numerically, not lexically", function(t)
  local ctx = t.newContext()
  local Utils = ctx.ns.Utils

  t.assertEqual(Utils.CompareVersions("1.2.10", "1.2.9"), 1)
  t.assertEqual(Utils.CompareVersions("1.2.9", "1.2.10"), -1)
  t.assertEqual(Utils.CompareVersions("1.0.0", "1.0.0"), 0)
  t.assertEqual(Utils.CompareVersions("1.2", "1.2.1"), -1)
end)

test("Utils.IsVersionNewer treats missing/empty candidate as not newer", function(t)
  local ctx = t.newContext()
  local Utils = ctx.ns.Utils

  t.assertFalse(Utils.IsVersionNewer(nil, "1.0.0"))
  t.assertFalse(Utils.IsVersionNewer("", "1.0.0"))
  t.assertTrue(Utils.IsVersionNewer("1.0.1", "1.0.0"))
  t.assertFalse(Utils.IsVersionNewer("1.0.0", "1.0.0"))
end)
