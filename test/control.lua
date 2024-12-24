if script.active_mods["factorio-test"] then
    require("__factorio-test__/init")({ "basic-tests" })
    -- the first argument is a list of test files (require paths) to run
end