--!strict
local Option = require("@wally/Option")
local Result = require("@wally/Result")
-- Services
-- Packages
-- Modules
-- Types
type Option<V> = Option.Option<V>
type Result<V, E> = Result.Result<V, E>

export type InterruptType = "Timeout" | "Cancelled" | "Error"
type FutureImpl<V> = {
	__index: FutureImpl<V>,
	__tostring: (self: Future<V>) -> string,
	__eq: (self: Future<V>, other: Future<V>) -> boolean,
	timeout: (self: Future<V>, duration: number) -> Result<V, InterruptType>,
	await: (self: Future<V>) -> V,
	awaitResult: (self: Future<V>) -> Result<V, InterruptType>,
	cancel: (self: Future<V>) -> (),
	on: (self: Future<V>, fn: (r: V) -> ()) -> thread,
	onResult: (self: Future<V>, fn: (r: Result<V, InterruptType>) -> ()) -> thread,
	poll: (self: Future<V>) -> Option<V>, --technically this is a Poll<V> not an Option<V> in rust
	pollResult: (self: Future<V>) -> Option<Result<V, InterruptType>>, --technically this is a Poll<V> not an Option<V> in rust, if err then thead will panic
}
export type Future<V> = typeof(setmetatable(
	{} :: {
		_interrupt: (InterruptType) -> (),
		_get: () -> Option<Result<V, InterruptType>>,
	},
	{} :: FutureImpl<V>
))

-- Constants
-- Variables
-- References
-- Private Functions

-- Class
local Future = {} :: FutureImpl<unknown>
Future.__index = Future

function Future:__eq(other: Future<unknown>): boolean
	return self._get() == (other._get() :: any)
end

function Future:__tostring(): string
	return `Future<{self._get()}>`
end

-- promise inspired addition
function Future:timeout(duration: number): Result<unknown, InterruptType>
	task.delay(duration, function()
		self._interrupt("Timeout")
	end)
	return self:awaitResult()
end

function Future:await(): unknown
	while self._get():isNone() do
		task.wait()
	end
	return self:awaitResult():unwrap()
end

function Future:awaitResult(): Result<unknown, InterruptType>
	while self._get():isNone() do
		task.wait()
	end
	return self._get():unwrap():match(function(v): Result<unknown, InterruptType>
		return Result.ok(v)
	end, function(e): Result<unknown, InterruptType>
		return Result.err(e :: any)
	end)
end

function Future:cancel(): ()
	self._interrupt("Cancelled")
end

function Future:poll(): Option<unknown>
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

function Future:pollResult(): Option<Result<unknown, InterruptType>>
	return self._get()
end

function Future:on(fn: (unknown) -> ()): thread
	return self:onResult(function(res)
		res:inspect(fn)
	end)
end

function Future:onResult(fn: (Result<unknown, InterruptType>) -> ()): thread
	return task.spawn(function()
		fn(self:awaitResult())
	end)
end

function new<V>(fn: () -> V, onInterrupt: Option<(InterruptType) -> ()>): Future<V>
	local output: Option<Result<V, string>> = Option.none()

	local interruptType: Option<InterruptType> = Option.none()
	local thread = task.spawn(function()
		output = Option.some(Result.try(fn))
	end)

	local function interrupt(t: InterruptType): ()
		if interruptType:isNone() or output:isSome() then
			return
		end
		interruptType = Option.some(t :: any)
		onInterrupt:inspect(function(onInt)
			task.spawn(function()
				onInt(t)
			end)
		end)
		task.cancel(thread)
	end

	local self = setmetatable({
		_interrupt = interrupt,
		_get = function(): Option<Result<V, InterruptType>>
			return interruptType:match(function(t): Option<Result<V, InterruptType>>
				return Option.some(Result.err(interruptType:unwrap() :: any))
			end, function(): Option<Result<V, InterruptType>>
				return output:match(function(res)
					return res:match(function(v)
						return Option.some(Result.ok(v))
					end, function(e)
						return Option.some(Result.err("Error" :: any))
					end)
				end, function()
					return Option.none()
				end)
			end)
		end,
	}, Future :: FutureImpl<any>)
	table.freeze(self)
	return self
end

local complexFrom: (<V>(fn: () -> V, onInterrupt: (InterruptType) -> ()) -> Future<V>) & (<V>(fn: () -> V) -> Future<V>) = function<
	V
>(
	fn: (
	) -> V,
	onInterrupt: (
		(InterruptType) -> ()
	)?
): Future<
	V
>
	if onInterrupt then
		return new(fn, Option.some(onInterrupt))
	else
		return new(fn, Option.none())
	end
end

return {
	from = complexFrom,
}
