item_views = {}

local timescale_map = {[1] = "second", [60] = "minute"}

local processors = {}  -- individual functions for each kind of view state

---@param metadata ItemViewsData
---@param raw_amount number
---@param item_proto FPItemPrototype | FPFuelPrototype
---@return number? button_number
---@return LocalisedString tooltip
function processors.items_per_timescale(metadata, raw_amount, item_proto, _)
    local raw_number = raw_amount * metadata.timescale
    local button_number = lib.format.button_number(raw_number)

    local tooltip_number = lib.format.number(raw_number, metadata.formatting_precision)
    local plural_parameter = (tooltip_number == "1") and 1 or 2
    local type_string = (item_proto.type == "fluid") and {"fp.l_fluid"} or {"fp.pl_item", plural_parameter}
    local tooltip = {"", tooltip_number, " ", type_string, "/", metadata.timescale_string}

    return button_number, tooltip
end

---@param metadata ItemViewsData
---@param raw_amount number
---@param item_proto FPItemPrototype | FPFuelPrototype
---@return number? button_number
---@return LocalisedString tooltip
function processors.throughput(metadata, raw_amount, item_proto, _)
    local raw_number, unit_name = nil, nil

    if item_proto.type == "fluid" then
        raw_number = raw_amount / metadata.pumping_speed
        unit_name = "pump"
    else
        raw_number = raw_amount * metadata.throughput_multiplier
        unit_name = metadata.belts_or_lanes:sub(1, -2)
    end

    local button_number = lib.format.button_number(raw_number)

    local tooltip_number = lib.format.number(raw_number, metadata.formatting_precision)
    local plural_parameter = (tooltip_number == "1") and 1 or 2
    local tooltip = {"", tooltip_number, " ", {"fp.pl_" .. unit_name, plural_parameter}}

    return button_number, tooltip
end

---@param metadata ItemViewsData
---@param raw_amount number
---@param item_proto FPItemPrototype | FPFuelPrototype
---@param machine_amount number?
---@return number? button_number
---@return LocalisedString tooltip
function processors.items_per_second_per_machine(metadata, raw_amount, item_proto, machine_amount)
    local adjusted_count = (math.ceil((machine_amount or 1) - MAGIC_NUMBERS.margin_of_error))
    if adjusted_count == 0 then return 0, nil end  -- avoid division by zero

    local raw_number = raw_amount / adjusted_count
    local button_number = lib.format.button_number(raw_number)

    local tooltip_number = lib.format.number(raw_number, metadata.formatting_precision)
    local plural_parameter = (tooltip_number == "1") and 1 or 2
    local type_string = (item_proto.type == "fluid") and {"fp.l_fluid"} or {"fp.pl_item", plural_parameter}
    -- If machine_amount is nil, this shouldn't show /machine
    local per_machine = (machine_amount ~= nil) and {"", "/", {"fp.pl_machine", 1}} or ""
    local tooltip = {"", tooltip_number, " ", type_string, "/", {"fp.second"}, per_machine}

    return button_number, tooltip
end

---@param metadata ItemViewsData
---@param raw_amount number
---@param item_proto FPItemPrototype | FPFuelPrototype
---@return number? button_number
---@return LocalisedString tooltip
function processors.stacks_per_timescale(metadata, raw_amount, item_proto, _)
    if item_proto.type == "fluid" then return nil, {"fp.fluid_item"} end

    local raw_number = (raw_amount * metadata.timescale) / item_proto.stack_size--[[@as uint]]
    local button_number = lib.format.button_number(raw_number)

    local tooltip_number = lib.format.number(raw_number, metadata.formatting_precision)
    local plural_parameter = (tooltip_number == "1") and 1 or 2
    local tooltip = {"", tooltip_number, " ", {"fp.pl_stack", plural_parameter}, "/", metadata.timescale_string}

    return button_number, tooltip
end

---@param metadata ItemViewsData
---@param raw_amount number
---@param item_proto FPItemPrototype | FPFuelPrototype
---@return number? button_number
---@return LocalisedString tooltip
function processors.wagons_per_timescale(metadata, raw_amount, item_proto, _)
    local wagon_capacity = (item_proto.type == "fluid") and metadata.fluid_wagon_capacity
        or metadata.cargo_wagon_capactiy * item_proto.stack_size--[[@as uint]]
    local raw_number = (raw_amount * metadata.timescale) / wagon_capacity
    local button_number = lib.format.button_number(raw_number)

    local tooltip_number = lib.format.number(raw_number, metadata.formatting_precision)
    local plural_parameter = (tooltip_number == "1") and 1 or 2
    local tooltip = {"", tooltip_number, " ", {"fp.pl_wagon", plural_parameter}, "/", metadata.timescale_string}

    return button_number, tooltip
end

---@param metadata ItemViewsData
---@param raw_amount number
---@param item_proto FPItemPrototype | FPFuelPrototype
---@return number? button_number
---@return LocalisedString tooltip
function processors.rockets_per_timescale(metadata, raw_amount, item_proto, _)
    if item_proto.type == "fluid" then return nil, {"fp.fluid_item"} end
    if item_proto.weight > metadata.lift_capacity then return nil, {"fp.item_too_heavy"} end

    local total_weight = raw_amount * metadata.timescale * item_proto.weight--[[@as Weight]]
    local raw_number = total_weight / metadata.lift_capacity
    local button_number = lib.format.button_number(raw_number)

    local tooltip_number = lib.format.number(raw_number, metadata.formatting_precision)
    local plural_parameter = (tooltip_number == "1") and 1 or 2
    local tooltip = {"", tooltip_number, " ", {"fp.pl_rocket", plural_parameter}, "/", metadata.timescale_string}

    return button_number, tooltip
end


---@param player LuaPlayer
---@param proto FPItemPrototype | FPFuelPrototype
---@param item_amount number
---@param machine_amount number?
---@return (number | -1 | nil) button_number
---@return LocalisedString tooltip_line
function item_views.process_item(player, proto, item_amount, machine_amount)
    local views_data = lib.globals.ui_state(player).views_data  ---@cast views_data -nil

    if item_amount == nil or (item_amount ~= 0 and item_amount < views_data.adjusted_margin_of_error) then
        return -1, nil
    end

    if proto.type == "entity" then
        local amount = (proto.fixed_unit) and item_amount or item_amount * views_data.timescale
        local button_number = lib.format.button_number(amount)
        local tooltip_number = lib.format.number(amount, views_data.formatting_precision)
        local unit = proto.fixed_unit or {"fp.per_timescale", {"fp." .. timescale_map[views_data.timescale]}}
        return button_number, {"", tooltip_number, " ", unit}
    else
        local view_preferences = lib.globals.preferences(player).item_views
        local selected_view = view_preferences.views[view_preferences.selected_index]--[[@cast -nil]].name
        local processor = processors[selected_view]  ---@cast processor -nil
        local number, tooltip = processor(views_data, item_amount, proto, machine_amount)
        return number, tooltip
    end
end


---@class ItemViewsData
---@field views table<string, ItemViewData>
---@field timescale Timescale
---@field timescale_string LocalisedString
---@field adjusted_margin_of_error number
---@field belts_or_lanes "belts" | "lanes"
---@field throughput_multiplier number
---@field formatting_precision integer
---@field pumping_speed number
---@field lift_capacity number
---@field cargo_wagon_capactiy number
---@field fluid_wagon_capacity number

---@class ItemViewData
---@field index integer
---@field caption LocalisedString
---@field tooltip LocalisedString

---@param default DefaultPrototype
---@return LuaEntityPrototype prototype
---@return LocalisedString quality_string
local function proto_and_quality_string(default)
    local proto = prototypes.entity[default.proto.name]
    local quality = (default.quality and default.quality.always_show)
        and {"", " (", default.quality.rich_text, ")"} or ""
    return proto, quality
end

---@param player LuaPlayer
function item_views.rebuild_data(player)
    local preferences = lib.globals.preferences(player)
    local timescale_string = timescale_map[preferences.timescale]

    local belt_proto = defaults.get(player, "belts").proto  --[[@as FPBeltPrototype]]
    local belts_or_lanes = preferences.belts_or_lanes
    local throughput_divisor = (belts_or_lanes == "belts") and belt_proto.throughput or (belt_proto.throughput / 2)

    local default_pump = defaults.get(player, "pumps")  ---@cast default_pump.proto FPPumpPrototype
    local pump_proto, pump_quality = proto_and_quality_string(default_pump)

    local default_silo = defaults.get(player, "silos")  ---@cast default_silo.proto FPSiloPrototype
    local _, silo_quality = proto_and_quality_string(default_silo)

    local default_cargo_wagon = defaults.get(player, "wagons", "cargo-wagon")
    ---@cast default_cargo_wagon.proto FPWagonPrototype
    local cargo_wagon_proto, cargo_wagon_quality = proto_and_quality_string(default_cargo_wagon)

    local default_fluid_wagon = defaults.get(player, "wagons", "fluid-wagon")
    ---@cast default_fluid_wagon.proto FPWagonPrototype
    local fluid_wagon_proto, fluid_wagon_quality = proto_and_quality_string(default_fluid_wagon)

    lib.globals.ui_state(player).views_data = {
        views = {
            items_per_timescale = {
                index = 1,
                caption = {"", {"fp.pu_item", 2}, "/", {"fp.unit_" .. timescale_string}},
                tooltip = {"fp.view_tt", {"fp.items_per_timescale", {"fp." .. timescale_string}}}
            },
            throughput = {
                index = 2,
                caption = {"", belt_proto.rich_text, " ", default_pump.proto.rich_text},
                tooltip = {"fp.view_tt", {"fp.throughput", {"fp.pl_" .. belts_or_lanes:sub(1, -2), 2},
                    belt_proto.rich_text, belt_proto.localised_name, default_pump.proto.rich_text,
                    default_pump.proto.localised_name, pump_quality}}
            },
            items_per_second_per_machine = {
                index = 3,
                caption = {"", {"fp.pu_item", 2}, "/", {"fp.unit_second"}, "/[img=fp_generic_assembler]"},
                tooltip = {"fp.view_tt", {"fp.items_per_second_per_machine"}}
            },
            stacks_per_timescale = {
                index = 4,
                caption = {"", "[img=fp_stack]", "/", {"fp.unit_" .. timescale_string}},
                tooltip = {"fp.view_tt", {"fp.stacks_per_timescale", {"fp." .. timescale_string}}}
            },
            wagons_per_timescale = {
                index = 5,
                caption = {"", default_cargo_wagon.proto.rich_text, default_fluid_wagon.proto.rich_text,
                    "/", {"fp.unit_" .. timescale_string}},
                tooltip = {"fp.view_tt", {"fp.wagons_per_timescale", {"fp." .. timescale_string},
                    default_cargo_wagon.proto.rich_text, default_cargo_wagon.proto.localised_name,
                    cargo_wagon_quality, default_fluid_wagon.proto.rich_text,
                    default_fluid_wagon.proto.localised_name, fluid_wagon_quality}}
            },
            rockets_per_timescale = {
                index = 6,
                caption = {"", "[img=fp_silo_rocket]", "/", {"fp.unit_" .. timescale_string}},
                tooltip = {"fp.view_tt", {"fp.rockets_per_timescale", {"fp." .. timescale_string},
                    default_silo.proto.rich_text, default_silo.proto.localised_name, silo_quality}}
            }
        },
        timescale = preferences.timescale,
        timescale_string = {"fp.unit_" .. timescale_map[preferences.timescale]}--[[@as LocalisedString]],
        adjusted_margin_of_error = MAGIC_NUMBERS.margin_of_error / preferences.timescale,
        belts_or_lanes = belts_or_lanes,
        throughput_multiplier = 1 / throughput_divisor,
        formatting_precision = MAGIC_NUMBERS.formatting_precision,
        pumping_speed = pump_proto.get_pumping_speed(default_pump.quality--[[@cast -nil]].name) * 60,
        lift_capacity = default_silo.proto--[[@as FPSiloPrototype]].rocket_lift_weight,
        cargo_wagon_capactiy = cargo_wagon_proto.get_inventory_size(defines.inventory.cargo_wagon,
            default_cargo_wagon.quality--[[@cast -nil]].name),
        fluid_wagon_capacity = fluid_wagon_proto.get_fluid_capacity(default_fluid_wagon.quality--[[@cast -nil]].name)
    }  ---@as ItemViewsData
end

---@class ItemViewPreferences
---@field views ItemViewPreference[]
---@field selected_index integer

---@class ItemViewPreference
---@field name string
---@field enabled boolean

---@return ItemViewPreferences
function item_views.default_preferences()
    return {
        views = {
            {name="items_per_timescale", enabled=true},
            {name="throughput", enabled=true},
            {name="items_per_second_per_machine", enabled=true},
            {name="stacks_per_timescale", enabled=false},
            {name="wagons_per_timescale", enabled=false},
            {name="rockets_per_timescale", enabled=false}
        },
        selected_index = 1
    }
end


---@param player LuaPlayer
---@param func function
local function run_on_all_views(player, func)
    local ui_state = lib.globals.ui_state(player)

    local main_interface = ui_state.main_elements.views_flow
    local compact_interface = ui_state.compact_elements.views_flow

    for _, interface in pairs({main_interface, compact_interface}) do
        if interface ~= nil and interface.valid then func(interface) end
    end
end

---@param player LuaPlayer
function item_views.rebuild_interface(player)
    local view_preferences = lib.globals.preferences(player).item_views
    local views_data = lib.globals.ui_state(player).views_data
    local views = views_data--[[@cast -nil]].views

    ---@param flow LuaGuiElement
    local function rebuild(flow)
        flow.clear()
        local table = flow.add{type="table", name="table_views", column_count=table_size(views)}
        table.style.horizontal_spacing = 0

        -- Iterate preferences for proper ordering
        for index, view_preference in pairs(view_preferences.views) do
            local view = views[view_preference.name]

            ---@class ChangeViewTags
            ---@field view_index integer
            local tags = {mod="fp", on_gui_click="change_view", view_index=index}
            table.add{type="button", tags=tags, caption=view.caption, tooltip=view.tooltip,
                style="fp_button_push", mouse_button_filter={"left"}}
        end
    end

    run_on_all_views(player, rebuild)
    item_views.refresh_interface(player)
end

---@param player LuaPlayer
function item_views.refresh_interface(player)
    local view_preferences = lib.globals.preferences(player).item_views

    ---@param flow LuaGuiElement
    local function refresh(flow)
        for _, view_button in pairs(flow["table_views"].children) do
            local index = view_button.tags--[[@as ChangeViewTags]].view_index
            local preference = view_preferences.views[index]
            view_button.toggled = (view_preferences.selected_index == index)
            view_button.visible = preference--[[@cast -nil]].enabled
        end
    end

    run_on_all_views(player, refresh)
end


---@param player LuaPlayer
---@param new_index integer
local function select_view(player, new_index)
    local view_preferences = lib.globals.preferences(player).item_views
    view_preferences.selected_index = new_index

    item_views.refresh_interface(player)
    local compact_view = lib.globals.ui_state(player).compact_view
    local refresh = (compact_view) and "compact_factory" or "factory"
    lib.gui.run_refresh(player, refresh)
end

---@param player LuaPlayer
---@param direction "standard" | "reverse"
function item_views.cycle_views(player, direction)
    local view_preferences = lib.globals.preferences(player).item_views

    local next_option = view_preferences.selected_index
    local total_options = #view_preferences.views
    local mover = (direction == "standard") and 1 or -1

    while true do
        next_option = next_option + mover
        if next_option > total_options then next_option = 1
        elseif next_option < 1 then next_option = total_options end

        local preference = view_preferences.views[next_option]
        if preference--[[@cast -nil]].enabled then
            select_view(player, next_option)
            break
        end
    end
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "change_view",
            handler = function(player, tags, _)
                ---@cast tags ChangeViewTags
                select_view(player, tags.view_index)
            end
        }
    }
}  ---@as GUIListenerDefinition

listeners.player = {
    fp_cycle_production_views = function(player, _)
        item_views.cycle_views(player, "standard")
    end,
    fp_reverse_cycle_production_views = function(player, _)
        item_views.cycle_views(player, "reverse")
    end
}

return { listeners }
