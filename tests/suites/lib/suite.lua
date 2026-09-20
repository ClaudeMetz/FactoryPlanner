---@diagnostic disable

-- Tests for lib utilities: formatters and clipboard operations.

local formatters = require("suite.formatters")
local clipboard = require("suite.clipboard")
local factory_items = require("suite.factory-items")

return {{
    name = "normal",
    cases = {
        testFactoryItemDefinitions = factory_items.definitions,
        testFactoryItemMigration = factory_items.migration,
        testMachineLimitMigration = factory_items.machine_limits,
        testFactoryItemPicker = factory_items.picker,
        testLibFormatNumber = formatters.number,
        testLibFormatSIValue = formatters.SI_value,
        testLibFormatButtonNumber = formatters.button_number,
        testLibClipboardCopySnapshots = clipboard.copy_snapshots,
        testLibClipboardCopyProduct = clipboard.copy_product,
        testLibClipboardProductItemCompatibility = clipboard.product_item_compatibility,
        testLibClipboardPasteOntoRecipe = clipboard.paste_onto_recipe,
        testLibClipboardPasteFailures = clipboard.paste_failures,
        testLibClipboardCutLineCollapsesSubfloor = clipboard.cut_line_collapses_subfloor,
        testLibClipboardCutSubfloor = clipboard.cut_subfloor,
        testLibClipboardCutBeacon = clipboard.cut_beacon,
        testLibClipboardCutModules = clipboard.cut_modules,
        testLibClipboardCutProduct = clipboard.cut_product,
        testLibClipboardCutRestrictions = clipboard.cut_restrictions
    }
}}
