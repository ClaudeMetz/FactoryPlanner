---@diagnostic disable

local throughput = require("cases.throughput-views")

return {cases={testThroughputViews=throughput.case(false)}}
