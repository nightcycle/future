--!strict
local Option = require("@wally/Option")
local Result = require("@wally/Result")
-- Services
-- Packages
-- Modules
-- Types
type Option<V> = Option.Option<V>
type Result<V, E> = Result.Result<V, E>

export type ErrorType = "Timeout" | "Cancelled" | "Error"
type FutureImpl<V> = {
	__index: FutureImpl<V>,
	__tostring: (self: Future<V>) -> string,
	__eq: (self: Future<V>, other: Future<V>) -> boolean,
	timeout: (self: Future<V>, duration: number) -> Option<V>,
	await: (self: Future<V>) -> V,
	awaitResult: (self: Future<V>) -> Result<V, ErrorType>,
	cancel: (self: Future<V>) -> (),
	on: (self: Future<V>, fn: (r: V) -> ()) -> thread,
	poll: (self: Future<V>) -> Option<V>, --technically this is a Poll<V> not an Option<V> in rust
}
export type Future<V> = typeof(setmetatable(
	{} :: {
		_thread: thread,
		_cancel: () -> (),
		_setError: (ErrorType) -> (),
		_getError: () -> Option<ErrorType>,
		_get: () -> Option<V>,
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
function Future:timeout(duration: number): Option<unknown>
	local start = tick()
	while coroutine.status(self._thread) ~= "dead" and tick() < start + duration do
		task.wait()
	end
	self._setError("Timeout")
	self._cancel()
	return self._get()
end

function Future:await(): unknown
	while coroutine.status(self._thread) ~= "dead" do
		task.wait()
	end
	return self._get():expect(debug.traceback(`future was cancelled`, 1))
end

function Future:awaitResult(): Result<unknown, ErrorType>
	while coroutine.status(self._thread) ~= "dead" do
		task.wait()
	end
	return self._get():match(function(value: unknown): Result<unknown, ErrorType>
		return Result.ok(value)
	end, function(): Result<unknown, ErrorType>
		return Result.err(self._getError():unwrapOr("Cancelled" :: any) :: any)
	end)
end

function Future:cancel(): ()
	if coroutine.status(self._thread) ~= "dead" then
		self._setError("Cancelled")
		self._cancel()
	end
end

function Future:poll(): Option<unknown>
	return self._get()
end

function Future:on(fn: (unknown) -> ()): thread
	local thread = task.spawn(function()
		fn(self:await())
	end)
	return thread
end

function new<V>(fn: () -> V, onCancel: Option<(ErrorType) -> ()>): Future<V>
	local value: Option<Result<V, string>> = Option.none()
	local errOption: Option<ErrorType> = Option.none()

	local thread = task.spawn(function()
		local res = Result.try(fn)
		res:inspectErr(function(err: string)
			errOption = Option.some("Error" :: any)
		end)
		value = Option.some(Result.try(fn))
	end)

	local isCancelled = false
	local self: Future<V> = setmetatable({
		_thread = thread,
		_setError = function(errType: ErrorType)
			if not isCancelled then
				errOption = Option.some(errType :: any)
			end
		end,
		_cancel = function()
			if not isCancelled then
				isCancelled = true
				local success, msg = pcall(function()
					if coroutine.status(thread) ~= "dead" then
						task.cancel(thread)
					end
				end)
				if not success then
					warn(msg)
				end
				onCancel:inspect(function(callback)
					callback(errOption:unwrapOr("Cancelled" :: any))
				end)
			end
		end,
		_getError = function(): Option<ErrorType>
			return errOption
		end,
		_get = function(): Option<V>
			return value:match(function(result: Result<V, string>): Option<V>
				return Option.some(result:unwrap())
			end, function(): Option<V>
				return Option.none()
			end)
		end,
	}, Future :: FutureImpl<any>)
	table.freeze(self)
	return self
end

local complexFrom: (<V>(fn: () -> V, onCancel: (ErrorType) -> ()) -> Future<V>) & (<V>(fn: () -> V) -> Future<V>) = function<V>(
	fn: (
	) -> V,
	onCancel: (
		(ErrorType) -> ()
	)?
): Future<
	V
>
	if onCancel then
		return new(fn, Option.some(onCancel))
	else
		return new(fn, Option.none())
	end
end

return {
	from = complexFrom,
}
