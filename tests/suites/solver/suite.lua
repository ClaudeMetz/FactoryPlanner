---@diagnostic disable
return {
    {name="input-targets", setup={require("prototypes").input_targets}, cases=require("suite.input-targets")},
    {name="machine-requirements", setup={require("prototypes").machine_requirements}, cases=require("suite.machine-requirements")},
    {name="sequential", setup={require("prototypes").sequential_chain}, cases=require("suite.sequential-chain")},
    {name="research", setup={require("prototypes").research, require("suite.research").setup},
        cases=require("suite.research").cases}
}
