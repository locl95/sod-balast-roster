local bootstrap = dofile("./tests/bootstrap.lua")
local tests = {}

_G.test = function(name, fn)
  tests[#tests + 1] = {
    name = name,
    fn = fn,
  }
end

dofile("./tests/history_spec.lua")
dofile("./tests/store_spec.lua")
dofile("./tests/comm_spec.lua")

local failures = 0

for _, entry in ipairs(tests) do
  local ok, err = pcall(entry.fn, bootstrap)
  if ok then
    io.write("PASS ", entry.name, "\n")
  else
    failures = failures + 1
    io.write("FAIL ", entry.name, "\n")
    io.write("  ", tostring(err), "\n")
  end
end

if failures > 0 then
  io.write(string.format("%d test(s) failed\n", failures))
  os.exit(1)
end

io.write(string.format("All %d tests passed\n", #tests))
