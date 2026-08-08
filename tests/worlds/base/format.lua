---@diagnostic disable

-- Unit tests for the formatting utilities. No prototype dependencies, so this
-- world can move to nobase once the minimal world is proven in CI.

local helpers = require("helpers")

return {
    cases = {
        testUtilFormatNumber = {
            check = function()
                local c = helpers.collector()
                local function run(number, precision, expected, label)
                    local result = lib.format.number(number, precision)
                    c.check(result == expected, string.format("[%s]: number(%g, %d) -> expected %q, got %q",
                        label, number, precision, expected, result))
                end

                -- Large numbers use %d to avoid %g's scientific notation
                run(1000,  3, "1000",  "1k threshold")
                run(9999,  3, "9999",  "4 digit")
                run(12345, 3, "12345", "5 digit")

                -- Past 1e15, %d can't represent the value, so scientific notation takes over
                run(999999999999999, 3, "999999999999999", "just under scientific threshold")
                run(1e15,   3, "1e+15",   "scientific threshold")
                run(1.5e27, 3, "1.5e+27", "sig figs in scientific notation")
                run(1e27,   3, "1e+27",   "past the largest SI prefix")

                -- Normal range: 3 sig figs via %g
                run(999,  3, "999",  "just under 1k")
                run(123,  3, "123",  "3 digit")
                run(12.3, 3, "12.3", "1 decimal")
                run(1.23, 3, "1.23", "2 decimal")
                run(1,    3, "1",    "1")

                -- Numbers < 1: precision reduced by leading zero count
                run(0.5,   3, "0.5",  "0.5")
                run(0.567, 3, "0.57", "0.567 -> 2 sig figs")
                run(0.123, 3, "0.12", "0.123 -> 2 sig figs")
                run(0.05,  3, "0.05", "0.05")

                -- Tiny positive numbers show ≤ threshold; zero stays "0"
                run(0.001,  3, "0.001",   "threshold boundary")
                run(0.0009, 3, "≤0.001",  "tiny positive")
                run(0,      3, "0",       "zero")

                -- Precision 4
                run(10000,  4, "10000",   "10k threshold at precision 4")
                run(9999,   4, "9999",    "4 digit at precision 4")
                run(1.234,  4, "1.234",   "4 sig figs")
                run(0.00009, 4, "≤0.0001", "tiny at precision 4")
                run(1.23e27, 4, "1.23e+27", "scientific at precision 4")

                c.done()
            end
        },

        testUtilFormatSIValue = {
            check = function()
                local c = helpers.collector()
                local function run(value, unit, precision, expected_num, expected_prefix, label)
                    local result = lib.format.SI_value(value, unit, precision)
                    local num_str, prefix = result[2], result[3]
                    local prefix_key = (type(prefix) == "table") and prefix[1] or prefix

                    c.check(num_str == expected_num,
                        string.format("[%s] number: expected %q, got %q", label, expected_num, num_str))
                    c.check(prefix_key == expected_prefix,
                        string.format("[%s] prefix: expected %q, got %q", label, expected_prefix, prefix_key))
                end

                -- Base scale (no prefix)
                run(0,   "W", 3, "0 ",   "", "zero")
                run(1,   "W", 3, "1 ",   "", "1W")
                run(500, "W", 3, "500 ", "", "500W")
                run(999, "W", 3, "999 ", "", "999W")

                -- Round-up bump: values above 999 bump to next tier to avoid %g scientific notation
                run(999.5, "W", 3, "1 ",   "fp.prefix_kilo", "999.5W -> 1kW")

                -- Kilo
                run(1000,  "W", 3, "1 ",   "fp.prefix_kilo", "1kW")
                run(1500,  "W", 3, "1.5 ", "fp.prefix_kilo", "1.5kW")
                run(12000, "W", 3, "12 ",  "fp.prefix_kilo", "12kW")

                -- Mega, Giga
                run(1e6,   "W", 3, "1 ",   "fp.prefix_mega", "1MW")
                run(1.5e6, "W", 3, "1.5 ", "fp.prefix_mega", "1.5MW")
                run(1e9,   "W", 3, "1 ",   "fp.prefix_giga", "1GW")

                -- Yotta is the last prefix, past it the base unit is used with scientific notation
                run(1e24,     "W", 3, "1 ",         "fp.prefix_yotta", "1YW")
                run(9.99e26,  "W", 3, "999 ",       "fp.prefix_yotta", "999YW")
                run(9.993e26, "W", 3, "9.99e+26 ",  "",                "would-be 1000YW -> scientific")
                run(1e27,     "W", 3, "1e+27 ",     "",                "1e27W")
                run(1e45,     "W", 3, "1e+45 ",     "",                "1e45W")
                run(-1e27,    "W", 3, "-1e+27 ",    "",                "negative scientific")

                -- Negative values
                run(-500,  "W", 3, "-500 ", "",               "-500W")
                run(-1500, "W", 3, "-1.5 ", "fp.prefix_kilo", "-1.5kW")

                -- Emissions unit
                run(1500, "E/m", 3, "1.5 ", "fp.prefix_kilo", "1.5k E/m")

                c.done()
            end
        },

        testUtilFormatButtonNumber = {
            check = function()
                local c = helpers.collector()
                local function run(input, expected, label)
                    local result = lib.format.button_number(input)
                    local success = math.abs(result - expected) <= 1e-9 * math.max(1, math.abs(expected))
                    c.check(success, string.format("[%s]: %.10g -> expected %.10g, got %.10g",
                        label, input, expected, result))
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

                c.done()
            end
        }
    }
}
