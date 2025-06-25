--!strict
print("\nawait.lune.luau started")
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
local out = f:await()
print(" - future finished")
assert(started, "Future should have started")
assert(finished, "Future should have finished")
assert(OUTPUT == out, "Future output should match expected value")
print(" - completed successfully")
