-- This contains both the UI handling for view states, as well as the amount conversions
view_state = {}

-- ** LOCAL UTIL **
local processors = {}  -- individual functions for each kind of view state
function processors.items_per_timescale(metadata, raw_amount, item_type, _)
    local number = ui_util.format_number(raw_amount, metadata.formatting_precision)

    local tooltip = nil
    if metadata.include_tooltip then
        local plural_parameter = (number == "1") and 1 or 2
        local type_string = (item_type == "fluid") and {"fp.pl_fluid", 1} or {"fp.pl_item", plural_parameter}
        tooltip = {"fp.two_word_title", number, {"fp.per_title", type_string, metadata.timescale_string}}
    end

    return number, tooltip
end

function processors.belts_or_lanes(metadata, raw_amount, item_type, _)
    if item_type == "fluid" then return nil, nil end

    local raw_number = raw_amount * metadata.throughput_multiplier * metadata.timescale_inverse
    local number = ui_util.format_number(raw_number, metadata.formatting_precision)

    local tooltip = nil
    if metadata.include_tooltip then
        local plural_parameter = (number == "1") and 1 or 2
        tooltip = {"fp.two_word_title", number, {"fp.pl_" .. metadata.belt_or_lane, plural_parameter}}
    end

    local return_number = (metadata.round_button_numbers) and math.ceil(raw_number) or number
    return return_number, tooltip
end

function processors.items_per_second_per_machine(metadata, raw_amount, item_type, machine_count)
    local raw_number = raw_amount * metadata.timescale_inverse / (machine_count or 1)
    local number = ui_util.format_number(raw_number, metadata.formatting_precision)

    local tooltip = nil
    if metadata.include_tooltip then
        local plural_parameter = (number == "1") and 1 or 2
        local type_string = (item_type == "fluid") and {"fp.pl_fluid", 1} or {"fp.pl_item", plural_parameter}
        local item_per_second =  {"fp.per_title", type_string, {"fp.second"}}
        -- If machine_count is nil, this is a top level item and shouldn't show /machine
        local per_machine = (machine_count ~= nil) and {"fp.per_title", "", {"fp.pl_machine", 1}} or ""
        tooltip = {"fp.two_word_title", number, {"", item_per_second, per_machine}}
    end

    return number, tooltip
end

local function handle_view_state_change(player, new_view_name)
    local view_states = data_util.get("ui_state", player).view_states

    if view_states and main_dialog.is_in_focus(player) then
        if new_view_name ~= nil then
            view_state.select(player, new_view_name)
        else
            local new_view_id = view_states.selected_view.id % #view_states + 1
            view_state.select(player, view_states[new_view_id].name)
        end

        main_dialog.refresh(player, "production")
    end
end


-- ** TOP LEVEL **
-- Creates metadata relevant for a whole batch of items
function view_state.generate_metadata(player, subfactory, formatting_precision, include_tooltip)
    local player_table = data_util.get("table", player)

    local selected_view = player_table.ui_state.view_states.selected_view
    local belts_or_lanes = player_table.settings.belts_or_lanes
    local round_button_numbers = player_table.preferences.round_button_numbers
    local throughput = prototyper.defaults.get(player, "belts").throughput
    local throughput_divisor = (belts_or_lanes == "belts") and throughput or (throughput / 2)

    return {
        processor = processors[selected_view.name],
        timescale_inverse = 1 / subfactory.timescale,
        timescale_string = {"fp." .. TIMESCALE_MAP[subfactory.timescale]},
        belt_or_lane = belts_or_lanes:sub(1, -2),
        round_button_numbers = round_button_numbers,
        throughput_multiplier = 1 / throughput_divisor,
        formatting_precision = formatting_precision,
        include_tooltip = include_tooltip
    }
end

function view_state.process_item(metadata, item, item_amount, machine_count)
    local raw_amount = item_amount or item.amount
    if raw_amount == nil or (raw_amount < MARGIN_OF_ERROR and item.class ~= "Product") then
        return -1, nil
    end

    return metadata.processor(metadata, raw_amount, item.proto.type, machine_count)
end


function view_state.rebuild_state(player)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    -- If no subfactory exists yet, choose a default timescale so the UI can build properly
    local timescale = (subfactory) and TIMESCALE_MAP[subfactory.timescale] or "second"
    local singular_bol = data_util.get("settings", player).belts_or_lanes:sub(1, -2)
    local bl_sprite = prototyper.defaults.get(player, "belts").rich_text

    local new_view_states = {
        [1] = {
            name = "items_per_timescale",
            caption = {"fp.per_title", {"fp.pu_item", 2}, {"fp.unit_" .. timescale}},
            tooltip = {"fp.view_state_tt", {"fp.items_per_timescale", {"fp." .. timescale}}}
        },
        [2] = {
            name = "belts_or_lanes",
            caption = {"fp.two_word_title", bl_sprite, {"fp.pu_" .. singular_bol, 2}},
            tooltip = {"fp.view_state_tt", {"fp.belts_or_lanes", {"fp.pl_" .. singular_bol, 2}}}
        },
        [3] = {
            name = "items_per_second_per_machine",
            caption = {"fp.per_title", {"fp.per_title", {"fp.pu_item", 2}, {"fp.unit_second"}},
              "[img=fp_generic_assembler]"},
            tooltip = {"fp.view_state_tt", {"fp.items_per_second_per_machine"}}
        }
    }

    -- Conserve the previous view selection if possible
    local old_view_states = ui_state.view_states
    local selected_view_name = (old_view_states) and old_view_states.selected_view.name or "items_per_timescale"

    ui_state.view_states = new_view_states
    view_state.select(player, selected_view_name)
end


function view_state.build(player, parent_element)
    local view_states = data_util.get("ui_state", player).view_states

    local table_view_state = parent_element.add{type="table", column_count=#view_states}
    table_view_state.style.horizontal_spacing = 0

    -- Using ipairs is important as we only want to iterate the array-part
    for _, view_state in ipairs(view_states) do
        table_view_state.add{type="button", name="fp_button_view_state_" .. view_state.name,
          style="fp_button_push", mouse_button_filter={"left"}}
    end

    return table_view_state
end

function view_state.refresh(player,  table_view_state)
    local view_states = data_util.get("ui_state", player).view_states

    for _, view_state in ipairs(view_states) do
        local view_button = table_view_state["fp_button_view_state_" .. view_state.name]
        view_button.caption, view_button.tooltip = view_state.caption, view_state.tooltip
        view_button.style = (view_state.selected) and "fp_button_push_active" or "fp_button_push"
        view_button.style.padding = {0, 12}  -- needs to be re-set when changing the style
        view_button.enabled = (not view_state.selected)
    end
end

function view_state.select(player, view_name)
    local view_states = data_util.get("ui_state", player).view_states

    if view_states.selected_view and view_states.selected_view.name == view_name then return false end

    for view_id, view_state in ipairs(view_states) do
        view_state.id = view_id

        if view_state.name == view_name then
            view_states.selected_view = view_state
            view_state.selected = true
        else
            view_state.selected = false
        end
    end

    return true  -- return that the view state was indeed changed
end


-- ** EVENTS **
view_state.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_button_view_state_[a-z_]+$",
            handler = (function(player, element, _)
                local view_name = string.gsub(element.name, "fp_button_view_state_", "")
                view_state.select(player, view_name)
                main_dialog.refresh(player, "production")
            end)
        }
    }
}

view_state.misc_events = {
    fp_cycle_production_views = (function(player, _)
        handle_view_state_change(player, nil)
    end)
}