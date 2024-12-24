-- This isn't a standard dialog so it can be opened independently of others

local function style_textfield(textfield, style)
    textfield.style = style
    textfield.style.margin = {0, 8, 12, 8}
    textfield.style.horizontal_align = "right"
    textfield.style.font = "default-large-semibold"
    textfield:focus()
end

local function run_calculation(player)
    local calculator_elements = util.globals.ui_state(player).calculator_elements
    local textfield = calculator_elements.textfield
    local expression = tostring(util.gui.parse_expression_field(textfield))

    if expression == "nil" then
        style_textfield(textfield, "invalid_value_textfield")
    else
        if expression ~= textfield.text then  -- avoid x = x label
            local history_frame = calculator_elements.history_frame
            local caption = textfield.text .. " = [font=default-semibold]" .. expression .. "[/font]"
            history_frame.add{type="label", caption=caption, index=1}

            local children = history_frame.children
            if #children > 15 then children[#children].destroy() end
        end

        style_textfield(textfield, "textbox")
        textfield.text = expression
    end
end

local function handle_button_click(player, tags, _)
    local textfield = util.globals.ui_state(player).calculator_elements.textfield
    local action = tags.action

    if action == "=" then
        run_calculation(player)
    else
        if action == "AC" then
            textfield.text = ""
        elseif action == "DEL" then
            textfield.text = string.sub(textfield.text, 1, -2)
        else
            textfield.text = textfield.text .. action
        end
        -- Reset textfield so it doesn't stay red
        style_textfield(textfield, "textbox")
    end
end

local button_layout = {
    {"AC", "(", ")", "/"},
    {"7", "8", "9", "*"},
    {"4", "5", "6", "-"},
    {"1", "2", "3", "+"},
    {"DEL", "0", ".", "="}
}

local alternate_labels = {
    ["+"] = "[img=fp_plus]",
    ["-"] = "[img=fp_minus]",
    ["*"] = "[img=fp_multiply]",
    ["/"] = "[img=fp_divide]"
}

local alternate_colors = {
    ["AC"] = {0.8, 0.8, 0.8},
    ["DEL"] = {0.8, 0.8, 0.8},
    ["="] = {0.8, 0.8, 0.8},
    ["("] = {0.7, 0.7, 0.7},
    [")"] = {0.7, 0.7, 0.7}
}

local function build_calculator_dialog(player, elements)
    -- Not visible by default so it can be toggled right after
    local frame = player.gui.screen.add{type="frame", visible=false, direction="vertical"}

    -- Titlebar
    local flow_title = frame.add{type="flow", direction="horizontal", style="frame_header_flow"}
    flow_title.drag_target = frame
    flow_title.add{type="label", caption={"fp.calculator"}, style="fp_label_frame_title", ignored_by_interaction=true}
    flow_title.add{type="empty-widget", style="flib_titlebar_drag_handle", ignored_by_interaction=true}

    flow_title.add{type="sprite-button", sprite="fp_history", tooltip={"fp.toggle_history_tt"}, style="fp_button_frame",
        tags={mod="fp", on_gui_click="toggle_calculator_history"}, auto_toggle=true, mouse_button_filter={"left"}}

    local close_button = flow_title.add{type="sprite-button", sprite="utility/close", style="fp_button_frame",
        tags={mod="fp", on_gui_click="close_calculator_dialog"}, mouse_button_filter={"left"}}
    close_button.style.padding = 1


    local horizontal_flow = frame.add{type="flow", direction="horizontal"}
    horizontal_flow.style.horizontal_spacing = 12

    -- Subheader
    local main_frame = horizontal_flow.add{type="frame", direction="vertical", style="inside_shallow_frame"}
    local subheader = main_frame.add{type="frame", direction="horizontal", style="subheader_frame"}
    subheader.style.maximal_height = 100

    local textfield = subheader.add{type="textfield", clear_and_focus_on_right_click=true,
        tags={mod="fp", on_gui_click="focus_textfield", on_gui_confirmed="calculator_input"}}
    style_textfield(textfield, "textbox")
    elements.textfield = textfield

    -- Buttons
    local button_table = main_frame.add{type="table", column_count=4}
    button_table.style.horizontal_spacing = 0
    button_table.style.vertical_spacing = 0
    for _, button_row in pairs(button_layout) do
        for _, action in pairs(button_row) do
            local label = alternate_labels[action] or action
            local button = button_table.add{type="button", caption=label, style="side_menu_button",
                tags={mod="fp", on_gui_click="calculator_button", action=action}}
            button.style.size = 56
            button.style.font = "default-large-semibold"
            button.style.font_color = alternate_colors[action] or {1, 1, 1}
        end
    end

    -- History
    local history_frame = horizontal_flow.add{type="frame", direction="vertical", visible=false,
        style="inside_shallow_frame"}
    history_frame.style.size = {240, 328}
    history_frame.style.padding = {14, 12}
    elements.history_frame = history_frame

    frame.force_auto_center()
    return frame
end

local function toggle_calculator_dialog(player)
    local ui_state = util.globals.ui_state(player)
    local dialog = ui_state.calculator_elements.frame

    if not dialog or not dialog.valid then
        dialog = build_calculator_dialog(player, ui_state.calculator_elements)
        ui_state.calculator_elements.frame = dialog
    end  ---@cast dialog -nil

    dialog.bring_to_front()
    dialog.visible = not dialog.visible
    -- No player.opened so it can be concurrent
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {  -- central place to catch calculator buttons
            name = "open_calculator_dialog",
            handler = toggle_calculator_dialog
        },
        {
            name = "close_calculator_dialog",
            handler = toggle_calculator_dialog
        },
        {
            name = "toggle_calculator_history",
            handler = (function(player, _, _)
                local ui_state = util.globals.ui_state(player)
                local history_frame = ui_state.calculator_elements.history_frame
                history_frame.visible = not history_frame.visible
            end)
        },
        {
            name = "focus_textfield",
            handler = (function(player, _, _)
                local calculator_elements = util.globals.ui_state(player).calculator_elements
                calculator_elements.textfield.select_all()
            end)
        },
        {
            name = "calculator_button",
            handler = handle_button_click
        }
    },
    on_gui_confirmed = {
        {
            name = "calculator_input",
            handler = run_calculation
        }
    }
}

listeners.misc = {
    fp_toggle_calculator = toggle_calculator_dialog
}

return { listeners }
