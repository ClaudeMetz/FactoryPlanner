
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

local ignoredFunctions =
{
	[debug.sethook] = true
}

local namedSources =
{
	["[string \"local n, v = \"serpent\", \"0.30\" -- (C) 2012-17...\"]"] = "serpent",
}


local function startCommand(command)
	Profiler.Start(command.parameter ~= nil)
end
local function stopCommand(command)
	Profiler.Stop(command.parameter ~= nil, nil)
end
ignoredFunctions[startCommand] = true
ignoredFunctions[stopCommand] = true


commands.add_command("startProfiler", "Starts profiling", startCommand)
commands.add_command("stopProfiler", "Stops profiling", stopCommand)


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

	debug.sethook(function(event)
		local info = debug_getinfo(2, "nSf")

		if ignoredFunctions[info.func] then
			return
		end

		if event == "call" or event == "tail call" then
			local prevCall = stack[stack_count]
			if excludeCalledMs then
				prevCall.profiler.stop()
			end

			local what = info.what
			local name
			if what == "C" then
				name = string_format("C function %q", info.name or "anonymous")
			else
				local source = info.short_src
				local namedSource = namedSources[source]
				if namedSource ~= nil then
					source = namedSource
				elseif string.sub(source, 1, 1) == "@" then
					source = string.sub(source, 1)
				end
				name = string_format("%q in %q, line %d", info.name or "anonymous", source, info.linedefined)
			end

			local prevCall_next = prevCall.next
			if prevCall_next == nil then
				prevCall_next = { }
				prevCall.next = prevCall_next
			end

			local currCall = prevCall_next[name]
			local profilerStartFunc
			if currCall == nil then
				local prof = create_profiler()
				currCall =
				{
					name = name,
					calls = 1,
					profiler = prof,
				}
				prevCall_next[name] = currCall
				profilerStartFunc = prof.reset
			else
				currCall.calls = currCall.calls + 1
				profilerStartFunc = currCall.profiler.restart
			end

			stack_count = stack_count + 1
			stack[stack_count] = currCall

			profilerStartFunc()
		end

		if event == "return" or event == "tail call" then
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
ignoredFunctions[Profiler.Start] = true

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
		text[#text + 1] = string.format("Reason: %s\n", message)
	end
	log(text)
	Profiler.CallTree = nil
	Profiler.IsRunning = false
end
ignoredFunctions[Profiler.Stop] = true

return Profiler
