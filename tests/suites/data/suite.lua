---@diagnostic disable
local clipboard = require("suite.clipboard")
local machines = require("suite.machines")
local configurations = {{name="normal", cases={
    testClipboardCopySnapshots = clipboard.copy_snapshots,
    testClipboardProductItemCompatibility = clipboard.product_item_compatibility,
    testClipboardPasteFailures = clipboard.paste_failures,
}}}

for name, case in pairs(require("suite.factory-items")) do configurations[1].cases[name] = case end
for name, case in pairs(require("suite.movement")) do configurations[1].cases[name] = case end
configurations[#configurations + 1] = {name="machine-requirements", setup={require("prototypes").machine_requirements},
    cases={testMachineRequirementPacking=machines.packing}}
configurations[#configurations + 1] = {name="research", setup={require("prototypes").research},
    cases={testResearchMachineCalculations=machines.research}}
configurations[#configurations + 1] = {name="fuel-categories", setup={require("prototypes").fuel_categories},
    cases={testFuelSelectionAndDefaults=machines.fuels}}
return configurations
