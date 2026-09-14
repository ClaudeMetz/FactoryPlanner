---@diagnostic disable

local items = require("suite.items")
local defaults_cases = require("suite.defaults")
local wagons = require("suite.wagons")
local throughput = require("suite.throughput")
local rockets = require("suite.rockets")

-- Each configuration gets a fresh game; its cases share the same prototypes
return {
    {
        name = "normal",
        cases = {
            testItemViewsFormatting = items.formatting,
            testThroughputViews = throughput.case(true),
            testDefaultsLookup = defaults_cases.lookup,
            testDefaultsMigration = defaults_cases.migration,
            testWagonViews = wagons.case(true, true),
            testWagonRestoration = wagons.restoration,
            testItemViewsMigration = items.migration,
            testItemViewsSelection = items.selection
        }
    },
    {name="no-cargo-wagons", cases={testWagonViews=wagons.case(false, true)}},
    {name="no-fluid-wagons", cases={testWagonViews=wagons.case(true, false)}},
    {name="no-wagons", cases={testWagonViews=wagons.case(false, false)}},
    {name="no-pumps", cases={testThroughputViews=throughput.case(false)}},
    {name="no-orbital-silos", cases={testRocketViews=rockets}}
}
