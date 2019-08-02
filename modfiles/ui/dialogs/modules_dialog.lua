-- This file handles both modules and beacons modal dialogs, because a lot of functionality is shared

-- *** MODULES ***
-- Handles populating the modules dialog for either 'add'- or 'edit'-actions
function open_module_dialog(flow_modal_dialog)
    local player = game.players[flow_modal_dialog.player_index]
    local ui_state = get_ui_state(player)
    local line = ui_state.context.line
    local module = ui_state.selected_object
    
    if module == nil then  -- Meaning this is adding a module
        create_module_beacon_dialog_structure(flow_modal_dialog, {"label.add_module"}, "module", line, nil, nil)
    else  -- meaning this is an edit
        create_module_beacon_dialog_structure(flow_modal_dialog, {"label.edit_module"}, "module", line, module, nil)
    end
end

-- Handles submission of the modules dialog
function close_module_dialog(flow_modal_dialog, action, data)
    local player = game.players[flow_modal_dialog.player_index]
    local ui_state = get_ui_state(player)
    local line = ui_state.context.line
    local module = ui_state.selected_object

    if action == "submit" then
        local new_module = Module.init_by_proto(ui_state.modal_data.selected_module, tonumber(data.module_amount))
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
function get_module_condition_instructions(modal_data)
    return {
        data = {
            module_sprite = (function(flow_modal_dialog) return
              flow_modal_dialog["flow_module_bar"]["sprite-button_module"].sprite end),
            module_amount = (function(flow_modal_dialog) return
               flow_modal_dialog["flow_module_bar"]["textfield_module_amount"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.module_instruction_1"},
                check = (function(data) return (data.module_sprite == "" or data.module_amount == "") end),
                refocus = nil,
                show_on_edit = true
            },
            [2] = {
                label = generate_module_condition_text(modal_data),
                check = (function(data) return (data.module_amount ~= "" and (tonumber(data.module_amount) == nil 
                          or tonumber(data.module_amount) <= 0 or tonumber(data.module_amount) > modal_data.empty_slots)) end),
                refocus = (function(flow) flow["flow_module_bar"]["textfield_module_amount"].focus() end),
                show_on_edit = true
            }
        }
    }
end


-- *** BEACONS ***
-- Handles populating the beacons dialog for either 'add'- or 'edit'-actions
function open_beacon_dialog(flow_modal_dialog)
    local player = game.players[flow_modal_dialog.player_index]
    local ui_state = get_ui_state(player)
    local line = ui_state.context.line
    local beacon = ui_state.selected_object
    
    if beacon == nil then  -- Meaning this is adding a beacon
        create_module_beacon_dialog_structure(flow_modal_dialog, {"label.add_beacon"}, "beacon", line, nil, nil)
    else  -- meaning this is an edit
        create_module_beacon_dialog_structure(flow_modal_dialog, {"label.edit_beacon"}, "beacon", line, nil, beacon)
    end
end

-- Handles submission of the beacons dialog
function close_beacon_dialog(flow_modal_dialog, action, data)
    local player = game.players[flow_modal_dialog.player_index]
    local ui_state = get_ui_state(player)
    local line = ui_state.context.line
    
    if action == "submit" then
        -- It makes no difference if this is an edit or not, the beacon gets replaced anyway
        local new_beacon = Beacon.init_by_protos(ui_state.modal_data.selected_beacon, tonumber(data.beacon_amount),
          ui_state.modal_data.selected_module, tonumber(data.module_amount))
        Line.set_beacon(line, new_beacon)   

    elseif action == "delete" then  -- only possible on edit
        Line.set_beacon(line, nil)
    end

    update_calculations(player, ui_state.context.subfactory)
end


-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_beacon_condition_instructions(modal_data)
    return {
        data = {
            beacon_amount = (function(flow_modal_dialog) return
               flow_modal_dialog["flow_beacon_bar"]["textfield_beacon_amount"].text end),
            module_sprite = (function(flow_modal_dialog) return
              flow_modal_dialog["flow_module_bar"]["sprite-button_module"].sprite end),
            module_amount = (function(flow_modal_dialog) return
               flow_modal_dialog["flow_module_bar"]["textfield_module_amount"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.beacon_instruction_1"},
                -- Beacon sprite can never be not set, as it is prefilled with the default
                check = (function(data) return (data.module_sprite == "") end),
                refocus = nil,
                show_on_edit = true
            },
            [2] = {
                label = {"label.beacon_instruction_2"},
                check = (function(data) return (data.beacon_amount == "" or (tonumber(data.beacon_amount) == nil
                          or tonumber(data.beacon_amount) <= 0)) end),
                refocus = (function(flow) flow["flow_beacon_bar"]["textfield_beacon_amount"].focus() end),
                show_on_edit = true
            },
            [3] = {
                label = generate_module_condition_text(modal_data),
                -- This condition is messy, but makes total sense, I swear
                check = (function(data) return (data.module_sprite ~= "" and (data.module_amount == ""
                          or (tonumber(data.module_amount) == nil or tonumber(data.module_amount) <= 0
                          or tonumber(data.module_amount) > modal_data.empty_slots))) end),
                refocus = (function(flow) flow["flow_module_bar"]["textfield_module_amount"].focus() end),
                show_on_edit = true
            }
        }
    }
end


-- *** SHARED ***
-- Generates the module condition text for beacons, so it can be updated when the selected beacon changes
function generate_module_condition_text(modal_data)
    if (modal_data.empty_slots == 1) then
        return {"", {"label.module_instruction_2_1"}, "1"}
    else
        return {"", {"label.module_instruction_2_1"}, {"label.module_instruction_2_2"},
          modal_data.empty_slots}
    end
end


-- Fills out the modal dialog to add/edit a module
function create_module_beacon_dialog_structure(flow_modal_dialog, title, type, line, module, beacon)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    flow_modal_dialog.parent.caption = title
    flow_modal_dialog.style.bottom_margin = 8

    -- Beacon bar
    if type == "beacon" then create_prototype_line(flow_modal_dialog, "beacon", line, beacon) end
    
    -- Module bar
    module = (type == "beacon" and beacon ~= nil) and beacon.module or module
    create_prototype_line(flow_modal_dialog, "module", line, module)

    -- Beacon selection
    if type == "beacon" and #global.all_beacons.beacons > 1 then
        flow_modal_dialog.add{type="label", name="label_beacon_selection",
          caption={"", {"label.select_beacon"}, ":"}, style="fp_preferences_title_label"}

        local flow_beacons = flow_modal_dialog.add{type="flow", name="flow_beacon_selection", direction="horizontal"}
        flow_beacons.style.top_margin = 4
        flow_beacons.style.left_margin = 6
        flow_beacons.style.bottom_margin = 6

        local selected_beacon = ui_state.modal_data.selected_beacon
        for _, beacon_proto in pairs(global.all_beacons.beacons) do
            local button_beacon = flow_beacons.add{type="sprite-button", name="fp_sprite-button_beacon_selection_"
              .. beacon_proto.id, sprite="entity/" .. beacon_proto.name, mouse_button_filter={"left"}}
            local tooltip = beacon_proto.localised_name
            local style = "fp_button_icon_medium_hidden"

            if beacon ~= nil and selected_beacon ~= nil and selected_beacon.name == beacon_proto.name then
                style = "fp_button_icon_medium_green"
                tooltip = {"", tooltip, "\n", {"tooltip.current_beacon"}}
            end
            tooltip = {"", tooltip, "\n", ui_util.generate_beacon_attributes_tooltip(beacon_proto)}

            button_beacon.tooltip = tooltip
            button_beacon.style = style
            button_beacon.style.padding = 2
        end
    end
    
    -- Module selection
    flow_modal_dialog.add{type="label", name="label_module_selection",
    caption={"", {"label.select_module"}, ":"}, style="fp_preferences_title_label"}
    refresh_module_selection(flow_modal_dialog, ui_state, type, line)
end


-- Adds a prototype line to the modal dialog flow to specify either a module or beacon
function create_prototype_line(flow_modal_dialog, type, line, object)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local modal_data = ui_state.modal_data

    -- Adjustments if the object is being edited
    local sprite, tooltip, amount = nil, nil, ""
    if object ~= nil then
        sprite = object.sprite
        tooltip = object.proto.localised_name
        amount = object.amount
    elseif type == "beacon" then
        local preferred_beacon = get_preferences(player).preferred_beacon
        modal_data.selected_beacon = preferred_beacon
        sprite = preferred_beacon.sprite
        tooltip = preferred_beacon.localised_name
    end

    flow = flow_modal_dialog.add{type="flow", name="flow_" .. type .. "_bar", direction="horizontal"}
    flow.style.bottom_margin = 8
    flow.style.horizontal_spacing = 8
    flow.style.vertical_align = "center"

    flow.add{type="label", name="label_" .. type, caption={"label." .. type}}
    local button = flow.add{type="sprite-button", name="sprite-button_" .. type, sprite=sprite, tooltip=tooltip,
      style="slot_button"}
    button.style.width = 28
    button.style.height = 28
    button.style.right_margin = 12

    flow.add{type="label", name="label_" .. type .. "_amount", caption={"label.amount"}}
    local textfield = flow.add{type="textfield", name="textfield_" .. type .. "_amount", text=amount}
    textfield.style.width = 40
    
    local focus = true
    if type == "module" then  -- only add max button if this is a module
        local button_max = flow.add{type="button", name="fp_button_max_modules", caption={"button-text.max"},
          style="fp_button_mini", tooltip={"tooltip.max_modules"}, mouse_button_filter={"left"}}
        button_max.style.left_margin = 4
        button_max.style.top_margin = 1

        -- Update module bar textfield and max-button and focus
        update_module_bar(flow_modal_dialog, ui_state)
        if ui_state.selected_object == nil then focus = false end
    end

    -- focus textfield on edit
    if focus then textfield.focus() end
end


-- Refreshes the module selection interface (used if the selected beacon changes)
function refresh_module_selection(flow_modal_dialog, ui_state, type, line)
    local flow_modules = flow_modal_dialog["flow_module_selection"]
    if flow_modules == nil then
        flow_modules = flow_modal_dialog.add{type="flow", name="flow_module_selection", direction="vertical"}
        flow_modules.style.top_margin = 4
        flow_modules.style.left_margin = 6
    else
        flow_modules.clear()
    end
   
    local selected_module = ui_state.modal_data.selected_module
    local selected_beacon = ui_state.modal_data.selected_beacon

    for _, category in pairs(global.all_modules.categories) do
        local flow_category = flow_modules.add{type="flow", name="flow_module_category_" .. category.id,
          direction="horizontal"}
        flow_category.style.bottom_margin = 4

        for _, module in pairs(category.modules) do
            local characteristics = (type == "module") and Line.get_module_characteristics(line, module)
              or get_beacon_module_characteristics(selected_beacon, module)

            if characteristics.compatible then
                local button_module = flow_category.add{type="sprite-button", name="fp_sprite-button_module_selection_"
                  .. category.id .. "_" .. module.id, sprite="item/" .. module.name, mouse_button_filter={"left"}}
                local tooltip = module.localised_name
                local style = "fp_button_icon_medium_hidden"

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


-- Reacts to a module/beacon being picked
function handle_module_beacon_picker_click(player, button)
    local ui_state = get_ui_state(player)
    local modal_data = ui_state.modal_data
    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog"]["flow_modal_dialog"]
    
    local split_name = ui_util.split(button.name, "_")
    if split_name[3] == "module" then
        if button.style.name ~= "fp_button_icon_medium_cyan" then  -- do nothing on existing modules
            local module_proto = global.all_modules.categories[split_name[5]].modules[split_name[6]]
            modal_data.selected_module = module_proto
            
            -- Don't focus the module textfield if the beacon textfield exists and doesn't have a valid value
            local beacon_bar = flow_modal_dialog["flow_beacon_bar"]
            local focus = (beacon_bar == nil or tonumber(beacon_bar["textfield_beacon_amount"].text) ~= nil)
              and "module" or "beacon"
            set_sprite_button(flow_modal_dialog, "module", module_proto, focus)

            -- Take focus away from the module amount textfield if it is locked at 1
            if modal_data.empty_slots == 1 then flow_modal_dialog.focus() end
        end
    else  -- "beacon"
        local beacon_proto = global.all_beacons.beacons[split_name[5]]
        modal_data.selected_beacon = beacon_proto
        modal_data.empty_slots = beacon_proto.module_limit

        -- Set the module in the interface
        set_sprite_button(flow_modal_dialog, "beacon", beacon_proto, "beacon")

        -- The module textfield and max-button might need to be locked (limit=1)
        update_module_bar(flow_modal_dialog, ui_state)

        -- The allowed modules might be different with the newly selected beacon, so refresh them
        refresh_module_selection(flow_modal_dialog, ui_state, "beacon", nil)

        -- Update the condition text (a bit hacky)
        local label_instruction_3 = generate_module_condition_text(modal_data)
        flow_modal_dialog.parent["table_modal_dialog_conditions"]
          ["label_subfactory_instruction_3"].caption = label_instruction_3
    end
end

-- Sets the sprite-button of the given type to the given proto and it's amount
function set_sprite_button(flow_modal_dialog, type, proto, focus)
    local bar = flow_modal_dialog["flow_" .. type .. "_bar"]
    bar["sprite-button_" .. type].sprite = proto.sprite
    bar["sprite-button_" .. type].tooltip = proto.localised_name
    -- Focus the specified textfield
    flow_modal_dialog["flow_" .. focus .. "_bar"]["textfield_" .. focus .. "_amount"].focus()
end

-- Updates the module textfield and max-button
function update_module_bar(flow_modal_dialog, ui_state)
    -- Set and lock the textfield and max-button if the module amount has to be 1
    local single_choice = (ui_state.modal_data.empty_slots == 1)
    local bar = flow_modal_dialog["flow_module_bar"]
    if single_choice then bar["textfield_module_amount"].text = "1" end
    bar["textfield_module_amount"].enabled = not single_choice
    bar["fp_button_max_modules"].enabled = not single_choice
end


-- Sets the amount of modules in the dialog to exactly fill up the machine
function max_module_amount(player)
    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog"]["flow_modal_dialog"]
    flow_modal_dialog["flow_module_bar"]["textfield_module_amount"].text = get_ui_state(player).modal_data.empty_slots
end


-- Returns a table indicating the compatability of the given module with this beacon
-- (mimics Line.get_module_characteristics(line, module) functionality)
function get_beacon_module_characteristics(beacon_proto, module_proto)
    local compatible = true

    local allowed_effects = beacon_proto.allowed_effects
    if allowed_effects == nil then
        compatible = false
    else
        for effect_name, _ in pairs(module_proto.effects) do
            if allowed_effects[effect_name] == false then
                compatible = false
            end
        end
    end
    
    return { compatible = compatible }
end