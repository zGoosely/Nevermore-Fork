--!strict

local MemorizeUtils = {}

local function getMemoizeKey(...: any): string
	local values = table.pack(...)
	local parts = table.create(values.n)

	for index = 1, values.n do
		parts[index] = tostring(values[index])
	end

	return table.concat(parts, ',')
end

function MemorizeUtils.memoize(fn: (...any) -> any)
	local cache = {}

	return function(...)
		local key = getMemoizeKey(...)
		if cache[key] == nil then
			cache[key] = fn(...)
		end
		return cache[key]
	end
end

function MemorizeUtils.timed(fn: (...any) -> any, ttl: number)
	local cache = {}

	return function(...)
		local key = getMemoizeKey(...)
		local entry = cache[key]
		local now = tick()

		if not entry or now - entry.time > ttl then
			cache[key] = {
				value = fn(...),
				time = now,
			}
		end

		return cache[key].value
	end
end

function MemorizeUtils.lruMemoize(fn: (...any) -> any, maxSize: number)
	local cache = {}
	local order = {}

	return function(...)
		local key = getMemoizeKey(...)

		if cache[key] then
			for i, k in ipairs(order) do
				if k == key then
					table.remove(order, i)
					break
				end
			end
			table.insert(order, key)
			return cache[key]
		end

		local result = fn(...)
		cache[key] = result
		table.insert(order, key)

		if #order > maxSize then
			local oldest = table.remove(order, 1)
			cache[oldest :: string] = nil
		end

		return result
	end
end

return MemorizeUtils
