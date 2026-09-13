---@diagnostic disable

local views = require("cases.item-views")

return {
    cases = {
        testItemViewsMigration = views.migration,
        testItemViewsSelection = views.selection
    }
}
