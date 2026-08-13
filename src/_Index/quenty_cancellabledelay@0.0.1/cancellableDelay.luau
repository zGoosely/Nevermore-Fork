--!strict
--[=[
	A version of `task.delay` that can be cancelled.

	@class cancellableDelay
]=]

--[=[
	Runs `func` after `timeoutInSeconds`, returning a function that cancels the
	still-pending call.

	@within cancellableDelay
	@param timeoutInSeconds number
	@param func (T...) -> ...any
	@param ... T... -- args passed to func
	@return () -> () -- call to cancel
]=]
local function cancellableDelay<T...>(timeoutInSeconds: number, func: (T...) -> ...any, ...: T...): () -> ()
	assert(type(timeoutInSeconds) == "number", "Bad timeoutInSeconds")
	assert(type(func) == "function", "Bad func")

	local args: any? = table.pack(...)

	local running: thread?
	task.spawn(function()
		running = coroutine.running()
		task.wait(timeoutInSeconds)
		local localArgs = args
		running = nil
		args = nil
		func(table.unpack(localArgs :: any, 1, localArgs.n))
	end)

	return function()
		if running then
			coroutine.close(running)
			running = nil
			args = nil
		end
	end
end

return cancellableDelay
