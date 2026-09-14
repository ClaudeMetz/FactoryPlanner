---@diagnostic disable

local views = require("cases.item-views")
local defaults_cases = require("cases.defaults")
local wagons = require("cases.wagon-views")
local throughput = require("cases.throughput-views")

return {
    cases = {
        testItemViewsFormatting = views.formatting,
        testThroughputViews = throughput.case(true),
        testDefaultsLookup = defaults_cases.lookup,
        testDefaultsMigration = defaults_cases.migration,
        testWagonViews = wagons.case(true, true),
        testWagonRestoration = wagons.restoration,
        testItemViewsMigration = views.migration,
        testItemViewsSelection = views.selection
    }
}
