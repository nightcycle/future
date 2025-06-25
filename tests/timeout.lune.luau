--!strict
print("\ntimeout.lune.luau started")
-- Packages
local luneUtil = require("@pkg/@nightcycle/lune-util")
local future = require("../src")

local OUTPUT = 1

do
	local started = false
	local finished = false
	local f = future.from(function()
		started = true
		luneUtil.Task.wait(2)
		finished = true
		return OUTPUT
	end)
	print(" - future to kill created")
	luneUtil.Task.wait(0.2)
	assert(not started, "Future should not have started yet")
	local outRes = f:timeout(0.25)
	assert(started, "Future should have started")
	assert(not finished, "Future should have not finished")
	assert("Timeout" == outRes:unwrapErr(), "Future output is not a timeout error")
	print(" - killed successfully")
end

do
	local started = false
	local finished = false
	local f = future.from(function()
		started = true
		luneUtil.Task.wait(2)
		finished = true
		return OUTPUT
	end)
	print(" - future to complete created")
	luneUtil.Task.wait(0.2)
	assert(not started, "Future should not have started yet")
	local outRes = f:timeout(3)
	assert(started, "Future should have started")
	assert(finished, "Future should have finished")
	assert(OUTPUT == outRes:unwrap(), "Future output is not a timeout error")
	print(" - completed successfully")
end
