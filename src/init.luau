--!strict
local Option = require("@wally/Option")
local Result = require("@wally/Result")
-- Services
-- Packages
-- Modules
-- Types
type Option<V> = Option.Option<V>
type Result<V, E> = Result.Result<V, E>
type FutureImpl<V> = {
	__index: FutureImpl<V>,
	__tostring: (self: Future<V>) -> string,
	__eq: (self: Future<V>, other: Future<V>) -> boolean,
	await: (self: Future<V>) -> V,
	cancel: (self: Future<V>) -> (),
	on: (self: Future<V>, fn: (r: V) -> ()) -> thread,
	poll: (self: Future<V>) -> Option<V>, --technically this is a Poll<V> not an Option<V> in rust
}
export type Future<V> = typeof(setmetatable(
	{} :: {
		_thread: thread,
		_cancel: () -> (),
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

function Future:await(): unknown
	while coroutine.status(self._thread) ~= "dead" do
		task.wait()
	end
	return self._get():unwrap()
end

function Future:cancel(): ()
	if coroutine.status(self._thread) ~= "dead" then
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

return {
	from = function<V>(fn: () -> V): Future<V>
		local value: Option<Result<V, string>> = Option.none()
		local thread = task.spawn(function()
			value = Option.some(Result.try(fn))
		end)

		local isCancelled = false
		local self: Future<V> = setmetatable({
			_thread = thread,
			_cancel = function()
				if isCancelled then
					isCancelled = false
					if coroutine.status(thread) ~= "dead" then
						task.cancel(thread)
					end
				end
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
	end,
}
