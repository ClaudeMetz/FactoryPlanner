-- Handles populating the modules dialog for either 'add'- or 'edit'-actions
function open_modules_dialog(flow_modal_dialog)
    local player = game.players[flow_modal_dialog.player_index]
    local ui_state = get_ui_state(player)
    local line = ui_state.context.line
    local module = ui_state.selected_object

    if module == nil then  -- Meaning this is adding a module
        create_modules_dialog_structure(flow_modal_dialog, {"label.add_module"}, line, nil)
    else  -- meaning this is an edit
        create_modules_dialog_structure(flow_modal_dialog, {"label.edit_module"}, line, module)
    end
end

-- Handles submission of the modules dialog
function close_modules_dialog(flow_modal_dialog, action, data)
    local player = game.players[flow_modal_dialog.player_index]
    local ui_state = get_ui_state(player)
    local line = ui_state.context.line
    local module = ui_state.selected_object

    if action == "submit" then
        local new_module = Module.init_by_proto(ui_state.modal_data.selected_module, tonumber(data.amount))
        if module == nil then  -- new module
            Line.add(line, new_module, true)
        else  -- edit existing module (it's easier to replace in the case the selected module changed)
            Line.replace(line, module, new_module, true)
        end

    elseif action == "delete" then  -- only possible on edit
        Line.remove(line, module, true)
    end

    update_calculations(player, ui_state.context.subfactory)
end


-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_modules_condition_instructions(modal_data)
    local instruction_2_label
    if (modal_data.empty_slots == 1) then
        instruction_2_label = {"", {"label.module_instruction_2_1"}, "1"}
    else
        instruction_2_label = {"", {"label.module_instruction_2_1"}, {"label.module_instruction_2_2"},
          modal_data.empty_slots}
    end

    return {
        data = {
            item_sprite = (function(flow_modal_dialog) return
              flow_modal_dialog["flow_module_bar"]["sprite-button_module"].sprite end),
            amount = (function(flow_modal_dialog) return
               flow_modal_dialog["flow_module_bar"]["textfield_module_amount"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.module_instruction_1"},
                check = (function(data) return (data.item_sprite == "" or data.amount == "") end),
                refocus = nil,
                show_on_edit = true
            },
            [2] = {
                label = instruction_2_label,
                check = (function(data) return (data.amount ~= "" and (tonumber(data.amount) == nil 
                          or tonumber(data.amount) <= 0 or tonumber(data.amount) > modal_data.empty_slots)) end),
                refocus = (function(flow) flow["flow_module_bar"]["textfield_module_amount"].focus() end),
                show_on_edit = true
            }
        }
    }
end

-- Fills out the modal dialog to add/edit a module
function create_modules_dialog_structure(flow_modal_dialog, title, line, module)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    flow_modal_dialog.parent.caption = title
    flow_modal_dialog.style.bottom_margin = 8

    -- Adjustments if the product is being edited
    local sprite = (module ~= nil) and module.sprite or nil
    local amount = (module ~= nil) and module.amount or ""

    -- Module bar
    flow = flow_modal_dialog.add{type="flow", name="flow_module_bar", direction="horizontal"}
    flow.style.bottom_margin = 8
    flow.style.horizontal_spacing = 8
    flow.style.vertical_align = "center"

    flow.add{type="label", name="label_module", caption={"label.module"}}
    local button = flow.add{type="sprite-button", name="sprite-button_module", sprite=sprite, style="slot_button"}
    button.style.width = 28
    button.style.height = 28
    button.style.right_margin = 12

    flow.add{type="label", name="label_module_amount", caption={"label.amount"}}
    local textfield = flow.add{type="textfield", name="textfield_module_amount", text=amount}
    textfield.style.width = 40
    
    local button_max = flow.add{type="button", name="fp_button_max_modules", caption={"button-text.max"},
    style="fp_button_mini", tooltip={"tooltip.max_modules"}}
    button_max.style.left_margin = 4
    button_max.style.top_margin = 1

    if module == nil then
        -- Set and lock the textfield and max-button if the module amount has to be 1
        if Line.empty_slots(line) == 1 then
            textfield.text = "1"
            textfield.enabled = false
            button_max.enabled = false
        end
    else  -- focus textfield on edit
        textfield.focus()
    end

    -- Module selection
    flow_modal_dialog.add{type="label", name="label_module_selection",
      caption={"", {"label.select_module"}, ":"}, style="fp_preferences_title_label"}

    local flow_modules = flow_modal_dialog.add{type="flow", name="flow_module_selection", direction="vertical"}
    flow_modules.style.top_margin = 4
    flow_modules.style.left_margin = 6
    for _, category in pairs(global.all_modules.categories) do
        local flow_category = flow_modules.add{type="flow", name="flow_module_category_" .. category.id,
          direction="horizontal"}
        flow_category.style.bottom_margin = 4

        for _, module in pairs(category.modules) do
            local characteristics = Line.get_module_characteristics(line, module)
            if characteristics.compatible then
                local button_module = flow_category.add{type="sprite-button", name="fp_sprite-button_module_selection_"
                  .. category.id .. "_" .. module.id, sprite="item/" .. module.name}
                local tooltip = module.localised_name
                local style = "fp_button_icon_medium_hidden"

                local selected_module = ui_state.modal_data.selected_module
                if selected_module ~= nil and selected_module.name == module.name then
                    style = "fp_button_icon_medium_green"
                    tooltip = {"", tooltip, "\n", {"tooltip.current_module"}}
                elseif characteristics.existing_amount ~= nil then
                    button_module.number = characteristics.existing_amount
                    style = "fp_button_icon_medium_cyan"
                    tooltip = {"", tooltip, "\n", {"tooltip.existing_module_a"}, " ", characteristics.existing_amount, " ",
                      {"tooltip.existing_module_b"}}
                end

                tooltip = {"", tooltip, ui_util.generate_module_effects_tooltip_proto(module)}

                button_module.tooltip = tooltip
                button_module.style = style
                button_module.style.padding = 2
            end
        end

        -- Hide this category if it has no compatible modules
        if #flow_category.children_names == 0 then flow_category.visible = false end
    end
end


-- Reacts to a picker item button being pressed
function handle_modules_module_click(player, button)
    if button.style.name ~= "fp_button_icon_medium_cyan" then  -- do nothing on existing modules
        local modal_data = get_ui_state(player).modal_data
        local split_name = ui_util.split(button.name, "_")
        local module_proto = global.all_modules.categories[split_name[5]].modules[split_name[6]]
        modal_data.selected_module = module_proto
        
        local flow_module_bar = player.gui.center["fp_frame_modal_dialog"]["flow_modal_dialog"]["flow_module_bar"]
        flow_module_bar["sprite-button_module"].sprite = button.sprite
        if modal_data.empty_slots ~= 1 then flow_module_bar["textfield_module_amount"].focus() end
    end
end

-- Sets the amount of modules in the dialog to exactly fill up the machine
function max_module_amount(player)
    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog"]["flow_modal_dialog"]
    flow_modal_dialog["flow_module_bar"]["textfield_module_amount"].text = get_ui_state(player).modal_data.empty_slots
end