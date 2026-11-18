-- usage: lua5.2 tests/run.lua [files...]   (default: tests/test_*.lua)
-- A test file returns { name = function() ... end }.
function assert_eq(a, b, msg)
  if a ~= b then
    error((msg and (msg .. ": ") or "") .. "expected " .. tostring(b) .. ", got " .. tostring(a), 2)
  end
end

function assert_near(a, b, eps, msg)
  eps = eps or 1e-9
  if type(a) ~= "number" or type(b) ~= "number" or math.abs(a - b) > eps then
    error((msg and (msg .. ": ") or "") .. "expected " .. tostring(b) .. " +/- " .. eps .. ", got " .. tostring(a), 2)
  end
end

package.path = "fleet-view/?.lua;fleet-view/scripts/?.lua;" .. package.path

local files = { ... }
if #files == 0 then
  local p = io.popen("ls tests/test_*.lua 2>/dev/null")
  for line in p:lines() do files[#files + 1] = line end
  p:close()
end

local passed, failed = 0, 0
for _, f in ipairs(files) do
  local chunk, err = loadfile(f)
  local suite
  if chunk then
    local ok, res = pcall(chunk)
    if ok then suite = res else err = res end
  end
  if type(suite) ~= "table" then
    failed = failed + 1
    print("FAIL " .. f .. ": " .. tostring(err or "file did not return a table"))
  else
    local names = {}
    for n in pairs(suite) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
      local ok, e = xpcall(suite[n], debug.traceback)
      if ok then passed = passed + 1
      else failed = failed + 1; print("FAIL " .. f .. " :: " .. n .. "\n" .. tostring(e)) end
    end
  end
end

print(passed .. " passed" .. (failed > 0 and (", " .. failed .. " failed") or ""))
os.exit(failed == 0 and 0 or 1)
