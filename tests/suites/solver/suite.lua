---@diagnostic disable

-- Runs hand-computable setups through the full solver stack.

return {{
    name = "normal",
    cases = {
        testMachineRequirements = require("suite.machine-requirements"),
        testSequentialChain = require("suite.sequential-chain")
    }
}}
