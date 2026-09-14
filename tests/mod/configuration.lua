---@diagnostic disable

-- run.sh copies the selected suite into this mod and writes its command-line options
local configurations = require("suite.suite")
local options = require("options")
assert(#configurations > 0, "Suite has no configurations")

local selected_name = options.configuration or configurations[1].name
local selected, names = nil, {}
for _, configuration in ipairs(configurations) do
    local name = configuration.name
    assert(type(name) == "string" and name:match("^[%w][%w_-]*$"), "Invalid configuration name")
    assert(not names[name], "Duplicate configuration: " .. name)
    names[name] = true
    if name == selected_name then selected = configuration end
end
assert(selected, "Unknown configuration: " .. selected_name)

local cases = {}
for name in pairs(selected.cases) do
    if name:find(options.filter) then table.insert(cases, name) end
end
table.sort(cases)

local suffix = (#configurations > 1) and (" [" .. selected_name .. "]") or ""
return {name=selected_name, suffix=suffix, cases=selected.cases, names=cases, configurations=configurations}
