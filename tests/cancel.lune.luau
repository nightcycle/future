--!strict
print("\ncancel.lune.luau started")
-- Packages
local luneUtil = require("@pkg/@nightcycle/lune-util")
local future = require("../src")

local started = false
local finished = false
local OUTPUT = 1

local f = future.from(function()
	started = true
	luneUtil.Task.wait(2)
	finished = true
	return OUTPUT
end)
print(" - future created")
luneUtil.Task.wait(0.2)
assert(not started, "Future should not have started yet")
luneUtil.Task.spawn(function()
	local out = f:awaitResult()
	assert(out:unwrapErr() == "Cancelled", "Future should have cancelled")
end)
luneUtil.Task.wait(0.2) -- Wait for the future to complete
f:cancel()
luneUtil.Task.wait(2)
assert(started, "Future should have started")
assert(finished == false, "Future should have not finished")
print(" - completed successfully")
