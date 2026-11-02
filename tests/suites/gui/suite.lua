---@diagnostic disable

local items = require("suite.items")
local availability = require("suite.availability")
local wagons, throughput, rockets = availability.wagons, availability.throughput, availability.rockets
local production = require("suite.production")

-- Each configuration gets a fresh game; its cases share the same prototypes
local configurations = {
    {
        name = "normal",
        setup = {require("prototypes").target_items},
        cases = {
            testItemViewsFormatting = items.formatting,
            testThroughputViews = throughput.case(true),
            testWagonViews = wagons.case(true, true),
            testItemViewsSelection = items.selection
        }
    },
    {name="no-cargo-wagons", setup={wagons.case(false, true).setup}, cases={testWagonViews=wagons.case(false, true)}},
    {name="no-fluid-wagons", setup={wagons.case(true, false).setup}, cases={testWagonViews=wagons.case(true, false)}},
    {name="no-wagons", setup={wagons.case(false, false).setup}, cases={testWagonViews=wagons.case(false, false)}},
    {name="no-pumps", setup={throughput.case(false).setup}, cases={testThroughputViews=throughput.case(false)}},
    {name="no-orbital-silos", setup={rockets.setup}, cases={testRocketViews=rockets}}
}

for _, module in ipairs{"item-boxes", "targets", "movement"} do
    for name, case in pairs(require("suite." .. module)) do
        assert(not configurations[1].cases[name], "Duplicate test: " .. name)
        configurations[1].cases[name] = case
    end
end
configurations[1].cases.testDistrictFactoryMove = require("suite.district-list")
configurations[#configurations + 1] = {name="input-targets", setup={require("prototypes").input_targets}, cases=production.inputs}
configurations[#configurations + 1] = {name="machine-requirements", setup={require("prototypes").machine_requirements}, cases=production.machines}
configurations[#configurations + 1] = {name="surplus", setup={require("prototypes").sequential_chain}, cases=production.surplus}
for name, case in pairs(require("suite.clipboard")) do
    configurations[1].cases["testClipboard_" .. name] = case
end
return configurations
