--!strict
local Option = require("@wally/Option")
local Result = require("@wally/Result")
local Error = require("@wally/Error")
-- Services
-- Packages
-- Modules
-- Types
type Option<V> = Option.Option<V>
type Result<V, E> = Result.Result<V, E>
type Error<E, D> = Error.Error<E, D>

export type InterruptType = "Timeout" | "Cancelled"
export type InterruptError = Error<"Interrupt", InterruptType> | Error<"Panic", string>
type FutureImpl<V> = {
	__index: FutureImpl<V>,
	__tostring: (self: any) -> string,
	__eq: (self: any, other: Future<V>) -> boolean,
	timeout: (self: any, duration: number) -> Result<V, InterruptError>,
	await: (self: any) -> V,
	awaitResult: (self: any) -> Result<V, InterruptError>,
	cancel: (self: any) -> (),
	on: (self: any, fn: (r: V) -> ()) -> thread,
	onResult: (self: any, fn: (r: Result<V, InterruptError>) -> ()) -> thread,
	poll: (self: any) -> Option<V>, --technically this is a Poll<V> not an Option<V> in rust
	pollResult: (self: any) -> Option<Result<V, InterruptError>>, --technically this is a Poll<V> not an Option<V> in rust, if err then thead will panic
}
export type Future<V> = typeof(setmetatable(
	{} :: {
		_interrupt: (InterruptType) -> (),
		_get: () -> Option<Result<V, InterruptError>>,
	},
	{} :: FutureImpl<V>
))

-- Constants
-- Variables
-- References
-- Private Functions
function getIfRobloxEnv(): boolean
	local isRobloxEnv = pcall(function()
		local _ = task.spawn
	end)
	return isRobloxEnv
end

function taskSpawn(fn: () -> ()): thread
	if getIfRobloxEnv() then
		return task.spawn(fn)
	else
		local req: any = require
		local task = req("@lune/task")
		return task.spawn(fn)
	end
end

function taskCancel(thread: thread): ()
	if getIfRobloxEnv() then
		return task.cancel(thread)
	else
		local req: any = require
		local task = req("@lune/task")
		return task.cancel(thread)
	end
end

function taskWait(amount: number?)
	if getIfRobloxEnv() then
		return task.wait(amount)
	else
		local req: any = require
		local task = req("@lune/task")
		return task.wait(amount)
	end
end

function taskDelay(amount: number, fn: () -> ())
	if getIfRobloxEnv() then
		return task.delay(amount, fn)
	else
		local req: any = require
		local task = req("@lune/task")
		return task.delay(amount, fn)
	end
end

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
function Future:timeout(duration: number): Result<unknown, InterruptError>
	taskDelay(duration, function()
		self._interrupt("Timeout")
	end)
	return self:awaitResult()
end

function Future:await(): unknown
	while self._get():isNone() do
		taskWait()
	end
	return self:awaitResult():unwrap()
end

function Future:awaitResult(): Result<unknown, InterruptError>
	while self._get():isNone() do
		taskWait()
	end
	return self._get():unwrap():match(function(v): Result<unknown, InterruptError>
		return Result.ok(v)
	end, function(e): Result<unknown, InterruptError>
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

function Future:pollResult(): Option<Result<unknown, InterruptError>>
	return self._get()
end

function Future:on(fn: (unknown) -> ()): thread
	return self:onResult(function(res)
		res:inspect(fn)
	end)
end

function Future:onResult(fn: (Result<unknown, InterruptError>) -> ()): thread
	return taskSpawn(function()
		fn(self:awaitResult())
	end)
end

function new<V>(fn: () -> V, onInterrupt: Option<(InterruptType) -> ()>): Future<V>
	local trace = Error.trace(1)

	local output: Option<Result<V, string>> = Option.none()

	local interruptType: Option<InterruptType> = Option.none()
	local thread = taskSpawn(function()
		output = Option.some(Result.try(fn))
	end)

	local function interrupt(t: InterruptType): ()
		if interruptType:isNone() or output:isSome() then
			return
		end
		interruptType = Option.some(t :: any)
		onInterrupt:inspect(function(onInt)
			taskSpawn(function()
				onInt(t)
			end)
		end)
		taskCancel(thread)
	end

	local self = setmetatable({
		_interrupt = interrupt,
		_get = function(): Option<Result<V, InterruptError>>
			return interruptType:match(function(t): Option<Result<V, InterruptError>>
				return Option.some(
					Result.err(
						Error.new("Interrupt" :: any)
							:body(t :: any)
							:title("Future Interrupted")
							:description("A public facing future method was called that interrupted the future")
							:trace(trace)
							:build() :: InterruptError
					)
				)
			end, function(): Option<Result<V, InterruptError>>
				return output:match(function(res)
					return res:match(function(v)
						return Option.some(Result.ok(v))
					end, function(e)
						return Option.some(
							Result.err(
								Error.new("Panic" :: any)
									:body(e)
									:title("Future Panicked")
									:description("Future encountered an error within the provided process")
									:trace(trace)
									:build() :: InterruptError
							)
						)
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
