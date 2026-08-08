---@diagnostic disable

-- Unit tests for the lib utilities, currently covering the formatters.

local formatters = require("cases.lib-formatters")

return {
    cases = {
        testLibFormatNumber = formatters.number,
        testLibFormatSIValue = formatters.SI_value,
        testLibFormatButtonNumber = formatters.button_number
    }
}
