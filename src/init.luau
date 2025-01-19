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
	await: (self: Future<V>) -> Result<V, string>,
	cancel: (self: Future<V>) -> (),
	on: (self: Future<V>, fn: (r: Result<V, string>) -> ()) -> thread,
	poll: (self: Future<V>) -> Option<Result<V, string>>, --technically this is a Poll<V> not an Option<V> in rust
}
export type Future<V> = typeof(setmetatable(
	{} :: {
		_thread: thread,
		_cancel: () -> (),
		_get: () -> Option<Result<V, string>>,
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

function Future:__tostring(): string
	return `Future<{self._get()}>`
end

function Future:await(): Result<unknown, string>
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

function Future:poll(): Option<Result<unknown, string>>
	return self._get()
end

function Future:on(fn: (Result<unknown, string>) -> ()): thread
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

		local tracebackMsg = debug.traceback("", 1)

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
			_get = function()
				return value:match(function(result: Result<V, string>): Option<Result<V, string>>
					return Option.some(result)
				end, function(): Option<Result<V, string>>
					if isCancelled then
						return Option.some(Result.err(`Future was cancelled\n{tracebackMsg}`))
					else
						return Option.none()
					end
				end)
			end,
		}, Future :: FutureImpl<any>)
		table.freeze(self)
		return self
	end,
}
