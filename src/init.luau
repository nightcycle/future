--!strict
local Option = require("@pkg/@nightcycle/option")
local Result = require("@pkg/@nightcycle/result")
local Error = require("@pkg/@nightcycle/error")
local LuneUtil = require("@pkg/@nightcycle/lune-util")
-- Services
-- Packages
-- Modules
-- Types
type Option<V> = Option.Option<V>
type Result<V, E> = Result.Result<V, E>
type Error<E, D> = Error.Error<E, D>

export type InterruptType = "Timeout" | "Cancelled"
type FutureImpl<V> = {
	timeout: (self: any, duration: number) -> Result<V, InterruptType>,
	await: (self: any) -> V,
	awaitResult: (self: any) -> Result<V, InterruptType>,
	cancel: (self: any) -> (),
	poll: (self: any) -> Option<V>,
}
export type Future<V> = FutureImpl<V>

-- Constants
-- Variables
-- References
-- Private Functions

-- Class
local Future = {} :: FutureImpl<unknown>

-- promise inspired addition
function Future:timeout(duration: number)
	LuneUtil.Task.delay(duration, function()
		self._interrupt("Timeout")
	end)
	return self:awaitResult()
end

function Future:await(): unknown
	return self:awaitResult():match(function(v)
		return v
	end, function(t)
		error("Future did not complete because: " .. tostring(t))
	end)
end

function Future:awaitResult()
	self._start()
	return self._yieldUntil()
end

function Future:cancel(): ()
	self._interrupt("Cancelled")
end

function Future:poll()
	return self._get():match(function(res)
		return res:match(function(v)
			return Option.some(v)
		end, function(e)
			return Option.none()
		end)
	end, function()
		return Option.none()
	end)
end

local DeprecatedFuture: any = Future
DeprecatedFuture.__index = Future

function DeprecatedFuture:__eq(other: Future<unknown>): boolean
	local ot: any = other
	return self._get() == (ot._get() :: any)
end

function DeprecatedFuture:__tostring(): string
	return `Future<{self._get()}>`
end

function DeprecatedFuture:pollResult()
	return self._get()
end

function new<V>(fn: () -> V)
	local output: Option<V> = Option.none()
	local interruptType: Option<InterruptType> = Option.none()
	local thread: Option<thread> = Option.none()

	local function interrupt(t: InterruptType)
		if interruptType:isSome() or output:isSome() then
			return
		end
		interruptType = Option.some(t :: any)
		thread:inspect(function(t)
			if t then
				LuneUtil.Task.cancel(t)
			end
		end)
	end

	local function yieldUntil(): Result<V, InterruptType>
		while output:isNone() and interruptType:isNone() do
			LuneUtil.Task.wait()
		end
		return interruptType:match(function(t)
			return Result.err(t :: InterruptType)
		end, function()
			return Result.ok(output:expect("Future should have output by now"))
		end) :: Result<V, any>
	end

	local function start()
		if interruptType:isSome() or output:isSome() then
			return
		end
		thread = Option.some(LuneUtil.Task.spawn(function()
			output = Option.some(fn())
		end))
	end

	local self = setmetatable({
		_interrupt = interrupt,
		_start = start,
		_yieldUntil = yieldUntil,
		_get = function()
			return interruptType:match(function(t)
				return Option.some(Result.err(t))
			end, function()
				return output:match(function(v)
					return Option.some(Result.ok(v))
				end, function()
					return Option.none()
				end)
			end)
		end,
	}, Future :: FutureImpl<any>)
	table.freeze(self)
	return self :: any
end

return {
	from = function<V>(fn: () -> V): Future<V>
		return new(fn)
	end,
}
