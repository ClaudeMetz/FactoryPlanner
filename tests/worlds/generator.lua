---@diagnostic disable

-- Checks that the generator interprets synthetic prototypes correctly: each case
-- defines its own prototypes and asserts what storage.prototypes ends up with.
--
-- All cases load into the same game, so generic categories ("fluid-fuel", "fluid-heat",
-- "chemical") contain members from more than one of them: they assert membership and
-- targeted absences, never exclusive category contents.

return {
    cases = {
        testGeneratorPrototypes = require("cases.generator-prototypes"),
        testBoilerPrototypes = require("cases.boiler-prototypes"),
        testFluidEnergyPrototypes = require("cases.fluid-energy-prototypes")
    }
}
