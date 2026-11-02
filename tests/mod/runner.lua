---@diagnostic disable

local configuration = require("configuration")
local fixtures = require("fixtures")

local context = {
    classes = {
        District = require("__factoryplanner__.backend.data.District"),
        Factory = require("__factoryplanner__.backend.data.Factory"),
        FactoryItem = require("__factoryplanner__.backend.data.FactoryItem"),
        Floor = require("__factoryplanner__.backend.data.Floor"),
        Line = require("__factoryplanner__.backend.data.Line"),
        Machine = require("__factoryplanner__.backend.data.Machine"),
        Beacon = require("__factoryplanner__.backend.data.Beacon"),
        Module = require("__factoryplanner__.backend.data.Module"),
        Fuel = require("__factoryplanner__.backend.data.Fuel"),
    }
}

local function run()
    local player = game.players[1]
    assert(player and storage.players[player.index], "Test player was not initialized")
    local names = configuration.names

    local lines, error_count = {}, 0
    for index, name in ipairs(names) do
        local ok, error, clean = fixtures.run(context, configuration.cases[name].check)
        local label = name .. configuration.suffix
        if ok then
            table.insert(lines, "  ✓ " .. label)
        else
            error_count = error_count + 1
            table.insert(lines, "  ✗ " .. label .. ": " .. tostring(error):gsub("\n", "\n    "))
        end
        if not clean then
            -- Later cases cannot be trusted after incomplete cleanup
            for remaining = index + 1, #names do
                error_count = error_count + 1
                lines[#lines + 1] = "  ✗ " .. names[remaining] .. configuration.suffix .. ": skipped after cleanup failure"
            end
            break
        end
    end

    if #names == 0 then
        table.insert(lines, "  ✗ no test cases selected" .. configuration.suffix)
    end

    -- run.py lifts everything between these markers out of the game log for display
    log("FPTEST_REPORT\n" .. table.concat(lines, "\n") .. "\nFPTEST_REPORT_END")
    log(string.format("FPTEST_PASSED %d", #names - error_count))
    script.finish_test(#names > 0 and error_count == 0)
end

-- Test mode exits after this tick when run calls script.finish_test
return {{game = {on_tick = run}}}
