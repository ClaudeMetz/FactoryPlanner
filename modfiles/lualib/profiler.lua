-- Work of the elusive Boodals, taken straight from https://github.com/Boodals/Factorio-Profiler

local table_sort = table.sort
local string_rep = string.rep
local string_format = string.format
local string_len = string.len
local string_sub = string.sub
local string_gsub = string.gsub
local debug_getinfo = debug.getinfo


--	Call
--		name (string)
--		calls (int)
--		profiler (LuaProfiler)
--		next (Array of Call)


local Profiler =
{
	--	Call
	CallTree = nil,
	IsRunning = false,
}


commands.add_command("startProfiler", "Starts profiling", function(command)
	Profiler.Start(command.parameter ~= nil)
end)
commands.add_command("stopProfiler", "Stops profiling", function(command)
	Profiler.Stop(command.parameter ~= nil, nil)
end)


local assert_raw = assert
function assert(expr, ...)
	if not expr then
		Profiler.Stop(false, "Assertion failed")
	end
	assert_raw(expr, ...)
end
local error_raw = error
function error(...)
	Profiler.Stop(false, "Error raised")
	error_raw(...)
end

function Profiler.Start(excludeCalledMs)
	if Profiler.IsRunning then
		return
	end

	local create_profiler = game.create_profiler

	Profiler.IsRunning = true

	Profiler.CallTree =
	{
		name = "root",
		calls = 0,
		profiler = create_profiler(),
		next = { },
	}

	--	Array of Call
	local stack = { [0] = Profiler.CallTree  }
	local stack_count = 0

	debug.sethook(function(type)
		local info = debug_getinfo(2)

		if type == "call" then
			local prevCall = stack[stack_count]
			if excludeCalledMs then
				prevCall.profiler.stop()
			end

			if info.name == "error" then
				Profiler.Stop(false, "Error raised")
				return
			end
			local source = string_gsub(info.source, "[\n\t]", "")
			if string_len(source) > 75 then --for some reason serpent's "source" is the entire source code..
				source = string_sub(source, 1, 75) .. "..."
			end
			local name = string_format("%q at %q, line %d", info.name or "anonymous", source, info.linedefined)

			local prevCall_next = prevCall.next
			if prevCall_next == nil then
				prevCall_next = { }
				prevCall.next = prevCall_next
			end

			local currCall = prevCall_next[name]
			local profilerStartFunc
			if currCall == nil then
				currCall =
				{
					name = name,
					calls = 1,
					profiler = create_profiler(),
				}
				prevCall_next[name] = currCall
				profilerStartFunc = currCall.profiler.reset
			else
				currCall.calls = currCall.calls + 1
				profilerStartFunc = currCall.profiler.restart
			end

			stack_count = stack_count + 1
			stack[stack_count] = currCall

			profilerStartFunc()

		elseif type == "return" then
			if stack_count > 0 then
				stack[stack_count].profiler.stop()
				stack[stack_count] = nil
				stack_count = stack_count - 1

				if excludeCalledMs then
					stack[stack_count].profiler.restart()
				end
			end
		end
	end, "cr")
end

local function DumpTree(averageMs)
	local function sort_Call(a, b)
		return a.calls > b.calls
	end
	local fullStr = { "" }
	local str = fullStr
	local line = 1

	local function recurse(curr, depth)

		local sort = { }
		local i = 1
		for k, v in pairs(curr) do
			sort[i] = v
			i = i + 1
		end
		table_sort(sort, sort_Call)

		for i = 1, #sort do
			local call = sort[i]

			if line >= 19 then --Localised string can only have up to 20 parameters
				local newStr = { "" } --So nest them!
				str[line + 1] = newStr
				str = newStr
				line = 1
			end

			if averageMs then
				call.profiler.divide(call.calls)
			end

			str[line + 1] = string_format("\n%s%dx %s. %s ", string_rep("\t", depth), call.calls, call.name, averageMs and "Average" or "Total")
			str[line + 2] = call.profiler
			line = line + 2

			local next = call.next
			if next ~= nil then
				recurse(next, depth + 1)
			end
		end
	end
	if Profiler.CallTree.next ~= nil then
		recurse(Profiler.CallTree.next, 0)
		return fullStr
	end
	return "No calls"
end

function Profiler.Stop(averageMs, message)
	if not Profiler.IsRunning then
		return
	end

	debug.sethook()

	local text = { "", "\n\n----------PROFILER DUMP----------\n", DumpTree(averageMs), "\n\n----------PROFILER STOPPED----------\n" }
	if message ~= nil then
		text = { "", "Reason: " .. message .. "\n" }
	end
	log(text)
	Profiler.CallTree = nil
	Profiler.IsRunning = false
end

return Profiler
