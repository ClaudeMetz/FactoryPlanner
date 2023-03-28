-- ** LLOG **
LLOG_EXCLUDES = {}

-- Internally used logging function for a single table
local function _llog(table_to_print)
    local excludes = LLOG_EXCLUDES or {}  -- Optional custom excludes defined by the parent mod

    if type(table_to_print) ~= "table" then return (tostring(table_to_print)) end

    local tab_width, super_space = 2, ""
    for _=0, tab_width-1, 1 do super_space = super_space .. " " end

    local function format(table_part, depth)
        if not next(table_part) then return "{}" end

        local spacing = ""
        for _=0, depth-1, 1 do spacing = spacing .. " " end
        local super_spacing = spacing .. super_space

        local out, first_element = "{", true
        local preceding_name = 0

        for name, value in pairs(table_part) do
            local element = tostring(value)
            if type(value) == "string" then
                element = "'" .. element .. "'"
            elseif type(value) == "table" then
                if excludes[name] ~= nil then
                    element = value.name or "EXCLUDE"
                else
                    element = format(value, depth+tab_width)
                end
            end

            local comma = (first_element) and "" or ","
            first_element = false

            -- Print string and continuous numerical keys only
            local key = (type(name) == "number" and preceding_name+1 ~= name) and "" or (name .. " = ")
            preceding_name = name

            out = out .. comma .. "\n" .. super_spacing .. key .. element
        end

        return (out .. "\n" .. spacing .. "}")
    end

    return format(table_to_print, 0)
end

-- User-facing function, handles multiple tables at being passed at once
function llog(...)
    local info = debug.getinfo(2, "Sl")
    local out = "\n" .. info.short_src .. ":" .. info.currentline .. ":"

    local arg_nr = table_size({...})
    if arg_nr == 0 then
        out = out .. " No arguments"
    elseif arg_nr == 1 then
        out = out .. " " .. _llog(select(1, ...))
    else
        for index, table_to_print in ipairs{...} do
            out = out .. "\n" .. index .. ": " ..  _llog(table_to_print)
        end
    end

    log(out)
end


script.on_event(defines.events.on_game_created_from_scenario, function()
    llog("Factory Planner test suite initiated")
    game.autosave_enabled = false
    --game.speed = 1000
end)
