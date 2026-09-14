---@diagnostic disable

-- Runs hand-computable setups through the full solver stack.

return {{
    name = "normal",
    cases = {
        testSequentialChain = require("suite.sequential-chain")
    }
}}
