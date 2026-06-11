---@diagnostic disable

-- Test cases consist of a runtime check, which is run in the main mod's environment

return {
    testUtilFormatButtonNumber = {
        check = function()
            local function run(input, expected, label)
                local result = util.format.button_number(input)
                local success = math.abs(result - expected) <= 1e-9 * math.max(1, math.abs(expected))
                if not success then
                    error(string.format("FAIL [%s]: %.10g -> expected %.10g, got %.10g",
                        label, input, expected, result))
                end
            end

            -- Spec examples
            run(0.0234567891,  0.1,     "spec -2")
            run(0.2345678912,  0.3,     "spec -1")
            run(2.345678912,   2.4,     "spec 0")
            run(23.45678912,   23.5,    "spec 1")
            run(234.5678912,   235,     "spec 2")
            run(2345.678912,   2400,    "spec 3")
            run(23456.78912,   24000,   "spec 4")
            run(234567.8912,   235000,  "spec 5")
            run(2345678.912,   2.4e6,   "spec 6")
            run(23456789.12,   24e6,    "spec 7")
            run(234567891.2,   235e6,   "spec 8")

            -- Zero and very small (all collapse to 0.1)
            run(0,      0,    "zero")
            run(0.001,  0.1,  "tiny")
            run(0.05,   0.1,  "< 0.1")
            run(0.099,  0.1,  "near 0.1")

            -- Exact clean values (must not bump up)
            run(0.1,   0.1,   "exact 0.1")
            run(2.3,   2.3,   "exact 2.3")
            run(10.0,  10.0,  "exact 10")
            run(23.5,  23.5,  "exact 23.5")
            run(235,   235,   "exact 235")
            run(2400,  2400,  "exact 2.4k")

            -- No-suffix threshold (100): below uses 1 decimal, above uses 0
            run(99.9,   99.9,  "99.9 exact")
            run(99.91,  100,   "99.91 -> 100")
            run(100,    100,   "100 exact")
            run(100.1,  101,   "100.1 -> 101")

            -- k-scale boundary crossings
            run(999,     999,     "999")
            run(999.5,   1000,    "999.5 -> 1.0k")
            run(1000,    1000,    "1k exact")
            run(1001,    1100,    "1001 -> 1.1k")
            run(9999,    10000,   "9.999k -> 10k")
            run(10000,   10000,   "10k exact")
            run(10001,   11000,   "10.001k -> 11k")
            run(99999,   100000,  "99.999k -> 100k")
            run(100000,  100000,  "100k exact")
            run(999999,  1e6,     "999.999k -> 1M")

            -- M-scale
            run(1e6,      1e6,    "1M exact")
            run(1.001e6,  1.1e6,  "1.001M -> 1.1M")
            run(9.999e6,  10e6,   "9.999M -> 10M")
            run(99.9e6,   100e6,  "99.9M -> 100M")
            run(999.9e6,  1e9,    "999.9M -> 1G")

            -- Extended SI: G, T, P, E
            run(2.345e9,   2.4e9,   "G 1-dec")
            run(23.45e9,   24e9,    "G 0-dec")
            run(234.5e9,   235e9,   "G 0-dec b")
            run(2.345e12,  2.4e12,  "T 1-dec")
            run(23.45e12,  24e12,   "T 0-dec")
            run(2.345e15,  2.4e15,  "P 1-dec")
            run(2.345e18,  2.4e18,  "E 1-dec")
            run(234.5e18,  235e18,  "E 0-dec")
        end
    }
}
