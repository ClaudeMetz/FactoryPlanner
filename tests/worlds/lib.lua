---@diagnostic disable

-- Tests for lib utilities: formatters and clipboard operations.

local formatters = require("cases.lib-formatters")
local clipboard = require("cases.lib-clipboard")

return {
    cases = {
        testLibFormatNumber = formatters.number,
        testLibFormatSIValue = formatters.SI_value,
        testLibFormatButtonNumber = formatters.button_number,
        testLibClipboardCopySnapshots = clipboard.copy_snapshots,
        testLibClipboardCopyProduct = clipboard.copy_product,
        testLibClipboardPasteOntoRecipe = clipboard.paste_onto_recipe,
        testLibClipboardPasteFailures = clipboard.paste_failures,
        testLibClipboardCutLineCollapsesSubfloor = clipboard.cut_line_collapses_subfloor,
        testLibClipboardCutSubfloor = clipboard.cut_subfloor,
        testLibClipboardCutBeacon = clipboard.cut_beacon,
        testLibClipboardCutModules = clipboard.cut_modules,
        testLibClipboardCutProduct = clipboard.cut_product,
        testLibClipboardCutRestrictions = clipboard.cut_restrictions
    }
}
