-- This contains both the UI handling for view states, as well as the amount conversions

-- ** LOCAL UTIL **
local function cycle_views(player, direction)
    local ui_state = util.globals.ui_state(player)

    if ui_state.view_states and main_dialog.is_in_focus(player) or compact_dialog.is_in_focus(player) then
        local selected_view_id, view_state_count = ui_state.view_states.selected_view_id, #ui_state.view_states
        local new_view_id = nil  -- need to make sure this is wrapped properly in either direction
        if direction == "standard" then
            new_view_id = (selected_view_id == view_state_count) and 1 or (selected_view_id + 1)
        else  -- direction == "reverse"
            new_view_id = (selected_view_id == 1) and view_state_count or (selected_view_id - 1)
        end
        view_state.select(player, new_view_id)

        local refresh = (ui_state.compact_view) and "compact_factory" or "production"
        util.raise.refresh(player, refresh)

        -- This avoids the game focusing a random textfield when pressing Tab to change states
        local main_frame = ui_state.main_elements.main_frame
        if main_frame ~= nil then main_frame.focus() end
    end
end


local processors = {}  -- individual functions for each kind of view state
function processors.items_per_timescale(metadata, raw_amount, item_proto, _)
    local number = util.format.number(raw_amount, metadata.formatting_precision)

    local plural_parameter = (number == "1") and 1 or 2
    local type_string = (item_proto.type == "fluid") and {"fp.l_fluid"} or {"fp.pl_item", plural_parameter}
    local tooltip = {"", number, " ", type_string, "/", metadata.timescale_string}

    return number, tooltip
end

function processors.belts_or_lanes(metadata, raw_amount, item_proto, _)
    if item_proto.type == "entity" then return nil, nil end  -- ore deposits don't make sense here

    local divisor = (item_proto.type == "fluid") and 50 or 1
    local raw_number = raw_amount * metadata.throughput_multiplier * metadata.timescale_inverse / divisor
    local number = util.format.number(raw_number, metadata.formatting_precision)

    local plural_parameter = (number == "1") and 1 or 2
    local tooltip = {"", number, " ", {"fp.pl_" .. metadata.belt_or_lane, plural_parameter}}

    local return_number = (metadata.round_button_numbers) and math.ceil(raw_number - 0.001) or number
    return return_number, tooltip
end

function processors.wagons_per_timescale(metadata, raw_amount, item_proto, _)
    if item_proto.type == "entity" then return nil, nil end  -- ore deposits don't make sense here

    local wagon_capacity = (item_proto.type == "fluid") and metadata.fluid_wagon_capacity
        or metadata.cargo_wagon_capactiy * item_proto.stack_size
    local wagon_count = raw_amount / wagon_capacity
    local number = util.format.number(wagon_count, metadata.formatting_precision)

    local plural_parameter = (number == "1") and 1 or 2
    local tooltip = {"", number, " ", {"fp.pl_wagon", plural_parameter}, "/", metadata.timescale_string}

    return number, tooltip
end

function processors.items_per_second_per_machine(metadata, raw_amount, item_proto, machine_count)
    if machine_count == 0 then return 0, "" end  -- avoid division by zero
    if item_proto.type == "entity" then return nil, nil end  -- ore deposits don't make sense here

    local raw_number = raw_amount * metadata.timescale_inverse / (math.ceil((machine_count or 1) - 0.001))
    local number = util.format.number(raw_number, metadata.formatting_precision)

    local plural_parameter = (number == "1") and 1 or 2
    local type_string = (item_proto.type == "fluid") and {"fp.l_fluid"} or {"fp.pl_item", plural_parameter}
    -- If machine_count is nil, this shouldn't show /machine
    local per_machine = (machine_count ~= nil) and {"", "/", {"fp.pl_machine", 1}} or ""
    local tooltip = {"", number, " ", type_string, "/", {"fp.second"}, per_machine}

    return number, tooltip
end


local function refresh_view_state(player)
    local ui_state = util.globals.ui_state(player)

    -- Automatically detects a timescale change and refreshes the state if necessary
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    if factory == nil then return end

    local relevant_elements = (ui_state.compact_view) and "compact_elements" or "main_elements"
    local table_view_state = ui_state[relevant_elements].view_state_table

    for _, view_button in ipairs(table_view_state.children) do
        local view_state = ui_state.view_states[view_button.tags.view_id]
        view_button.caption = view_state.caption
        view_button.tooltip = view_state.tooltip
        view_button.toggled = (view_state.selected)
    end
end


local function build_view_state(player, parent_element)
    local view_states = util.globals.ui_state(player).view_states

    local table_view_state = parent_element.add{type="table", name="table_view_state", column_count=#view_states}
    table_view_state.style.horizontal_spacing = 0

    -- Using ipairs is important as we only want to iterate the array-part
    for view_id, _ in ipairs(view_states) do
        local button = table_view_state.add{type="button", mouse_button_filter={"left"},
            tags={mod="fp", on_gui_click="change_view_state", view_id=view_id}}
        button.style.height = 26
        button.style.minimal_width = 0
        button.style.padding = {0, 12}
    end
end


-- ** TOP LEVEL **
view_state = {}

-- Creates metadata relevant for a whole batch of items
function view_state.generate_metadata(player)
    local player_table = util.globals.player_table(player)

    local view_states = player_table.ui_state.view_states
    local current_view_name = view_states[view_states.selected_view_id].name
    local belts_or_lanes = player_table.preferences.belts_or_lanes
    local round_button_numbers = player_table.preferences.round_button_numbers
    local throughput = prototyper.defaults.get(player, "belts").throughput
    local throughput_divisor = (belts_or_lanes == "belts") and throughput or (throughput / 2)
    local default_cargo_wagon = prototyper.defaults.get(player, "wagons", PROTOTYPE_MAPS.wagons["cargo-wagon"].id)
    local default_fluid_wagon = prototyper.defaults.get(player, "wagons", PROTOTYPE_MAPS.wagons["fluid-wagon"].id)

    return {
        processor = processors[current_view_name],
        timescale_inverse = 1 / view_states.timescale,
        timescale_string = {"fp." .. TIMESCALE_MAP[view_states.timescale]},
        adjusted_margin_of_error = MAGIC_NUMBERS.margin_of_error * view_states.timescale,
        belt_or_lane = belts_or_lanes:sub(1, -2),
        round_button_numbers = round_button_numbers,
        throughput_multiplier = 1 / throughput_divisor,
        formatting_precision = 4,
        cargo_wagon_capactiy = default_cargo_wagon.storage,
        fluid_wagon_capacity = default_fluid_wagon.storage
    }
end

function view_state.process_item(metadata, item, item_amount, machine_count)
    local raw_amount = item_amount or item.amount
    if raw_amount == nil or (raw_amount ~= 0 and raw_amount < metadata.adjusted_margin_of_error) then
        return -1, nil
    end

    return metadata.processor(metadata, raw_amount, item.proto, machine_count)
end


function view_state.rebuild_state(player)
    local player_table = util.globals.player_table(player)
    local default_timescale = player_table.preferences.default_timescale

    local relevant_object_type = (player_table.ui_state.districts_view) and "District" or "Factory"
    local relevant_object = util.context.get(player, relevant_object_type)

    local timescale = (relevant_object) and relevant_object.timescale or default_timescale
    local timescale_string = TIMESCALE_MAP[timescale]
    local singular_bol = util.globals.preferences(player).belts_or_lanes:sub(1, -2)
    local belt_proto = prototyper.defaults.get(player, "belts")
    local default_cargo_wagon = prototyper.defaults.get(player, "wagons", PROTOTYPE_MAPS.wagons["cargo-wagon"].id)
    local default_fluid_wagon = prototyper.defaults.get(player, "wagons", PROTOTYPE_MAPS.wagons["fluid-wagon"].id)

    local new_view_states = {
        [1] = {
            name = "items_per_timescale",
            caption = {"", {"fp.pu_item", 2}, "/", {"fp.unit_" .. timescale_string}},
            tooltip = {"fp.view_state_tt", {"fp.items_per_timescale", {"fp." .. timescale_string}}}
        },
        [2] = {
            name = "belts_or_lanes",
            caption = {"", belt_proto.rich_text, " ", {"fp.pu_" .. singular_bol, 2}},
            tooltip = {"fp.view_state_tt", {"fp.belts_or_lanes", {"fp.pl_" .. singular_bol, 2},
                 belt_proto.rich_text, belt_proto.localised_name}}
        },
        [3] = {
            name = "wagons_per_timescale",
            caption = {"", {"fp.pu_wagon", 2}, "/", {"fp.unit_" .. timescale_string}},
            tooltip = {"fp.view_state_tt", {"fp.wagons_per_timescale", {"fp." .. timescale_string},
                default_cargo_wagon.rich_text, default_cargo_wagon.localised_name,
                default_fluid_wagon.rich_text, default_fluid_wagon.localised_name}}
        },
        [4] = {
            name = "items_per_second_per_machine",
            caption = {"", {"fp.pu_item", 2}, "/", {"fp.unit_second"}, "/[img=fp_generic_assembler]"},
            tooltip = {"fp.view_state_tt", {"fp.items_per_second_per_machine"}}
        },
        -- Retain for use in metadata generation
        timescale = timescale,
        selected_view_id = nil  -- set below
    }

    -- Conserve the previous view selection if possible
    local old_view_states = player_table.ui_state.view_states
    local selected_view_id = (old_view_states) and old_view_states.selected_view_id or "items_per_timescale"

    player_table.ui_state.view_states = new_view_states
    view_state.select(player, selected_view_id)
end

function view_state.select(player, selected_view)
    local view_states = util.globals.ui_state(player).view_states

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
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "change_view_state",
            handler = (function(player, tags, _)
                view_state.select(player, tags.view_id)

                local compact_view = util.globals.ui_state(player).compact_view
                local refresh = (compact_view) and "compact_factory" or "production"
                util.raise.refresh(player, refresh)
            end)
        }
    }
}

listeners.misc = {
    fp_cycle_production_views = (function(player, _)
        cycle_views(player, "standard")
    end),
    fp_reverse_cycle_production_views = (function(player, _)
        cycle_views(player, "reverse")
    end),

    build_gui_element = (function(player, event)
        if event.trigger == "view_state" then
            build_view_state(player, event.parent)
        end
    end),
    refresh_gui_element = (function(player, event)
        if event.trigger == "view_state" then
            -- Only react to exact trigger as the elements containing
            --   the view state will refresh it otherwise
            refresh_view_state(player)
        end
    end)
}

return { listeners }
