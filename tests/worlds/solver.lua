---@diagnostic disable

-- Runs hand-computable setups through the full solver stack.

return {
    cases = {
        testSequentialChain = require("cases.solver-sequential-chain")
    }
}
