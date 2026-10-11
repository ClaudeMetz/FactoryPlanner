---@diagnostic disable

local helpers = require("helpers")

return {
    check = function()
        local c = helpers.collector()
        local field = game.players[1].gui.screen.add{type="textfield"}

        for _, text in ipairs{"1/0", "-1/0", "0/0", "10^400", "", "1+"} do
            for _, positive in ipairs{false, true} do
                field.text = text
                c.check(lib.gui.parse_expression_field(field, positive) == nil,
                    "Reject invalid expression: " .. text)
                c.check(not lib.gui.confirm_expression_field(field, positive) and field.text == text,
                    "Invalid expressions must remain unconfirmed and unchanged: " .. text)
            end
        end

        for _, case in ipairs{
            {"2*(3+4)", true, 14},
            {"1.5k+2M", true, 2001500},
            {"1/4", true, 0.25},
            {"10^308", true, 1e308},
            {"0", false, 0},
            {"-5", false, -5},
            {"0", true, nil},
            {"-5", true, nil}
        } do
            field.text = case[1]
            c.check(lib.gui.parse_expression_field(field, case[2]) == case[3],
                "Preserve finite expression validation: " .. case[1])
        end

        field.destroy()
        c.done()
    end
}
