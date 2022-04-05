-- This contains both the UI handling for view states, as well as the amount conversions
view_state = {}

-- ** LOCAL UTIL **
local processors = {}  -- individual functions for each kind of view state
function processors.items_per_timescale(metadata, raw_amount, item_proto, _)
    local tooltip = nil
    if metadata.include_tooltip then
        local tooltip_number = ui_util.format_number(raw_amount, metadata.formatting_precision)
        local plural_parameter = (tooltip_number == "1") and 1 or 2
        local type_string = (item_proto.type == "fluid") and {"fp.l_fluid"} or {"fp.pl_item", plural_parameter}
        tooltip = {"fp.two_word_title", tooltip_number, {"fp.per_title", type_string, metadata.timescale_string}}
    end

    local icon_number = ui_util.format_number_ceil(raw_amount)
    return icon_number, tooltip
end

function processors.belts_or_lanes(metadata, raw_amount, item_proto, _)
    local raw_number = raw_amount * metadata.throughput_multiplier * metadata.timescale_inverse / (item_proto.type == "fluid" and 50 or 1)

    local tooltip = nil
    if metadata.include_tooltip then
        local tooltip_number = ui_util.format_number(raw_number, metadata.formatting_precision)
        local plural_parameter = (tooltip_number == "1") and 1 or 2
        
        if item_proto.type == "fluid" then
            -- 3.5 belts (assuming 50 fluid/barrel)
            tooltip = {"fp.annotated_title", {"fp.two_word_title", tooltip_number, {"fp.pl_" .. metadata.belt_or_lane, plural_parameter}}, {"fp.hint_fluid_belt_barrel"}}
        else
            -- 3.5 belts
            tooltip = {"fp.two_word_title", tooltip_number, {"fp.pl_" .. metadata.belt_or_lane, plural_parameter}}
        end
    end

    local icon_number = ui_util.format_number_ceil((metadata.round_button_numbers) and math.ceil(raw_number) or raw_number)
    return icon_number, tooltip
end

function processors.wagons_per_timescale(metadata, raw_amount, item_proto, _)
    if item_proto.type == "entity" then return nil, nil end

    local wagon_capacity = (item_proto.type == "fluid") and metadata.fluid_wagon_capacity
      or metadata.cargo_wagon_capactiy * item_proto.stack_size
    local wagon_count = raw_amount / wagon_capacity

    local tooltip = nil
    if metadata.include_tooltip then
        local tooltip_number = ui_util.format_number(wagon_count, metadata.formatting_precision)
        local plural_parameter = (tooltip_number == "1") and 1 or 2
        tooltip = {"fp.two_word_title", tooltip_number, {"fp.per_title", {"fp.pl_wagon", plural_parameter},
          metadata.timescale_string}}
    end

    local icon_number = ui_util.format_number_ceil(wagon_count)
    return icon_number, tooltip
end

function processors.items_per_second_per_machine(metadata, raw_amount, item_proto, machine_count)
    local raw_number = raw_amount * metadata.timescale_inverse / (math.ceil(machine_count or 1))

    local tooltip = nil
    if metadata.include_tooltip then
        local tooltip_number = ui_util.format_number(raw_number, metadata.formatting_precision)
        local plural_parameter = (tooltip_number == "1") and 1 or 2
        local type_string = (item_proto.type == "fluid") and {"fp.l_fluid"} or {"fp.pl_item", plural_parameter}
        local item_per_second =  {"fp.per_title", type_string, {"fp.second"}}
        -- If machine_count is nil, this shouldn't show /machine
        local per_machine = (machine_count ~= nil) and {"fp.per_title", "", {"fp.pl_machine", 1}} or ""
        tooltip = {"fp.two_word_title", tooltip_number, {"", item_per_second, per_machine}}
    end

    local icon_number = ui_util.format_number_ceil(raw_number)
    return icon_number, tooltip
end


-- ** TOP LEVEL **
-- Creates metadata relevant for a whole batch of items
function view_state.generate_metadata(player, subfactory, formatting_precision, include_tooltip)
    local player_table = data_util.get("table", player)

    local view_states = player_table.ui_state.view_states
    local current_view_name = view_states[view_states.selected_view_id].name
    local belts_or_lanes = player_table.settings.belts_or_lanes
    local round_button_numbers = player_table.preferences.round_button_numbers
    local throughput = prototyper.defaults.get(player, "belts").throughput
    local throughput_divisor = (belts_or_lanes == "belts") and throughput or (throughput / 2)
    local cargo_wagon_capactiy = prototyper.defaults.get(player, "wagons", global.all_wagons.map["cargo-wagon"]).storage
    local fluid_wagon_capacity = prototyper.defaults.get(player, "wagons", global.all_wagons.map["fluid-wagon"]).storage

    return {
        processor = processors[current_view_name],
        timescale_inverse = 1 / subfactory.timescale,
        timescale_string = {"fp." .. TIMESCALE_MAP[subfactory.timescale]},
        adjusted_margin_of_error = MARGIN_OF_ERROR * subfactory.timescale,
        belt_or_lane = belts_or_lanes:sub(1, -2),
        round_button_numbers = round_button_numbers,
        throughput_multiplier = 1 / throughput_divisor,
        formatting_precision = formatting_precision,
        include_tooltip = include_tooltip,
        cargo_wagon_capactiy = cargo_wagon_capactiy,
        fluid_wagon_capacity = fluid_wagon_capacity
    }
end

function view_state.process_item(metadata, item, item_amount, machine_count)
    local raw_amount = item_amount or item.amount
    if raw_amount == nil or (raw_amount < metadata.adjusted_margin_of_error and item.class ~= "Product") then
        return -1, nil
    end

    return metadata.processor(metadata, raw_amount, item.proto, machine_count)
end


function view_state.rebuild_state(player)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    -- If no subfactory exists yet, choose a default timescale so the UI can build properly
    local timescale = (subfactory) and TIMESCALE_MAP[subfactory.timescale] or "second"
    local singular_bol = data_util.get("settings", player).belts_or_lanes:sub(1, -2)
    local belt_proto = prototyper.defaults.get(player, "belts")
    local cargo_train_proto = prototyper.defaults.get(player, "wagons", global.all_wagons.map["cargo-wagon"])
    local fluid_train_proto = prototyper.defaults.get(player, "wagons", global.all_wagons.map["fluid-wagon"])

    local new_view_states = {
        [1] = {
            name = "items_per_timescale",
            caption = {"fp.per_title", {"fp.pu_item", 2}, {"fp.unit_" .. timescale}},
            tooltip = {"fp.view_state_tt", {"fp.items_per_timescale", {"fp." .. timescale}}}
        },
        [2] = {
            name = "belts_or_lanes",
            caption = {"fp.two_word_title", belt_proto.rich_text, {"fp.pu_" .. singular_bol, 2}},
            tooltip = {"fp.view_state_tt", {"fp.belts_or_lanes", {"fp.pl_" .. singular_bol, 2},
              belt_proto.rich_text, belt_proto.localised_name}}
        },
        [3] = {
            name = "wagons_per_timescale",
            caption = {"fp.per_title", {"fp.pu_wagon", 2}, {"fp.unit_" .. timescale}},
            tooltip = {"fp.view_state_tt", {"fp.wagons_per_timescale", {"fp." .. timescale},
              cargo_train_proto.rich_text, cargo_train_proto.localised_name,
              fluid_train_proto.rich_text, fluid_train_proto.localised_name}}
        },
        [4] = {
            name = "items_per_second_per_machine",
            caption = {"fp.per_title", {"fp.per_title", {"fp.pu_item", 2}, {"fp.unit_second"}},
              "[img=fp_generic_assembler]"},
            tooltip = {"fp.view_state_tt", {"fp.items_per_second_per_machine"}}
        },
        selected_view_id = nil,  -- set below
        timescale = timescale  -- conserve the timescale to rebuild the state
    }

    -- Conserve the previous view selection if possible
    local old_view_states = ui_state.view_states
    local selected_view_id = (old_view_states) and old_view_states.selected_view_id or "items_per_timescale"

    ui_state.view_states = new_view_states
    view_state.select(player, selected_view_id, nil)
end

function view_state.build(player, parent_element)
    local view_states = data_util.get("ui_state", player).view_states

    local table_view_state = parent_element.add{type="table", column_count=#view_states}
    table_view_state.style.horizontal_spacing = 0

    -- Using ipairs is important as we only want to iterate the array-part
    for view_id, _ in ipairs(view_states) do
        table_view_state.add{type="button", tags={mod="fp", on_gui_click="change_view_state", view_id=view_id},
          style="fp_button_push", mouse_button_filter={"left"}}
    end

    return table_view_state
end

function view_state.refresh(player, table_view_state)
    local ui_state = data_util.get("ui_state", player)

    -- Automatically detects a timescale change and refreshes the state if necessary
    local subfactory = ui_state.context.subfactory
    if not subfactory then return
    elseif subfactory.current_timescale ~= ui_state.view_states.timescale then
        view_state.rebuild_state(player)
    end

    for _, view_button in ipairs(table_view_state.children) do
        local view_state = ui_state.view_states[view_button.tags.view_id]
        view_button.caption, view_button.tooltip = view_state.caption, view_state.tooltip
        view_button.style = (view_state.selected) and "fp_button_push_active" or "fp_button_push"
        view_button.style.padding = {0, 12}  -- needs to be re-set when changing the style
        view_button.enabled = (not view_state.selected)
    end
end

function view_state.select(player, selected_view, context_to_refresh)
    local view_states = data_util.get("ui_state", player).view_states

    -- Selected view can be either an id or a name, so we might need to match an id to a name
    local selected_view_id = selected_view
    if type(selected_view) == "string" then
        for view_id, view_state in ipairs(view_states) do
            if view_state.name == selected_view then
                selected_view_id = view_id
                break
            end
        end
    end

    -- Only run any code if the selected view did indeed change
    if view_states.selected_view_id ~= selected_view_id then
        for view_id, view_state in ipairs(view_states) do
            if view_id == selected_view_id then
                view_states.selected_view_id = selected_view_id
                view_state.selected = true
            else
                view_state.selected = false
            end
        end

        -- Optionally refresh the given context after the view has been changed
        if context_to_refresh then main_dialog.refresh(player, context_to_refresh) end
    end
end


-- ** EVENTS **
view_state.gui_events = {
    on_gui_click = {
        {
            name = "change_view_state",
            handler = (function(player, tags, _)
                view_state.select(player, tags.view_id, "production")
            end)
        }
    }
}

view_state.misc_events = {
    fp_cycle_production_views = (function(player, _)
        local ui_state = data_util.get("ui_state", player)

        if ui_state.view_states and main_dialog.is_in_focus(player) then
            -- Choose the next view in the list, wrapping from the end to the beginning
            local new_view_id = (ui_state.view_states.selected_view_id % #ui_state.view_states) + 1
            view_state.select(player, new_view_id, "production")

            -- This avoids the game focusing a random textfield when pressing Tab to change states
            ui_state.main_elements.main_frame.focus()
        end
    end)
}
