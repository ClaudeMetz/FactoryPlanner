item_views = {}

---@class ItemViewsData
---@field views table<string, ItemViewData>
---@field timescale Timescale
---@field timescale_string LocalisedString
---@field adjusted_margin_of_error number
---@field formatting_precision integer

---@class ItemViewData
---@field caption LocalisedString
---@field tooltip LocalisedString?
---@field unavailable boolean?
---@field unavailable_for table<string, boolean>?

---@class ItemViewDefinition
---@field prepare fun(player: LuaPlayer, timescale_string: string): ItemViewData
---@field process fun(metadata: ItemViewsData, raw_amount: number, item_proto: FPItemPrototype | FPFuelPrototype, machine_amount: number?): number?, LocalisedString?

---@param metadata ItemViewsData
---@param amount number
---@param unit_name string
---@param suffix LocalisedString?
---@return number? button_number
---@return LocalisedString tooltip
local function format_amount(metadata, amount, unit_name, suffix)
    local button_number = lib.format.button_number(amount)
    local tooltip_number = lib.format.number(amount, metadata.formatting_precision)
    local plural_parameter = (tooltip_number == "1") and 1 or 2
    local unit = (unit_name == "fluid") and {"fp.l_fluid"} or {"fp.pl_" .. unit_name, plural_parameter}
    return button_number, {"", tooltip_number, " ", unit, suffix or ""}
end

---@param default DefaultPrototype
---@return LuaEntityPrototype prototype
---@return LocalisedString quality_string
local function proto_and_quality_string(default)
    local proto = prototypes.entity[default.proto.name]
    local quality = (default.quality and default.quality.always_show)
        and {"", " (", default.quality.rich_text, ")"} or ""
    return proto, quality
end

---@type table<string, ItemViewDefinition>
local view_definitions = {}

view_definitions.items_per_timescale = {
    ---@param _ LuaPlayer
    ---@param timescale_string string
    ---@return ItemViewData
    prepare = function(_, timescale_string)
        return {
            caption = {"", {"fp.pu_item", 2}, "/", {"fp.unit_" .. timescale_string}},
            tooltip = {"fp.view_tt", {"fp.items_per_timescale", {"fp." .. timescale_string}}}
        }
    end,

    ---@param metadata ItemViewsData
    ---@param raw_amount number
    ---@param item_proto FPItemPrototype | FPFuelPrototype
    ---@return number? button_number
    ---@return LocalisedString tooltip
    process = function(metadata, raw_amount, item_proto, _)
        local raw_number = raw_amount * metadata.timescale
        local unit_name = (item_proto.type == "fluid") and "fluid" or "item"
        return format_amount(metadata, raw_number, unit_name, {"", "/", metadata.timescale_string})
    end
}

---@class ThroughputViewData: ItemViewData
---@field belts_or_lanes BeltsOrLanes
---@field multiplier number
---@field pumping_speed number?

view_definitions.throughput = {
    ---@param player LuaPlayer
    ---@return ThroughputViewData view
    prepare = function(player)
        local preferences = lib.globals.preferences(player)
        local belt = defaults.get(player, "belts").proto  ---@as FPBeltPrototype
        local belts_or_lanes, belt_stack = preferences.belts_or_lanes, preferences.belt_stack
        local divisor = (belts_or_lanes == "belts") and belt.throughput or (belt.throughput / 2)
        local unit = {"fp.pl_" .. belts_or_lanes:sub(1, -2), 2}
        local stack_insert = (belt_stack > 1) and {"", {"fp.throughput_insert", belt_stack}, " "} or ""

        local pump = defaults.get_optional(player, "pumps")
        local view = {caption=belt.rich_text, unavailable_for={fluid=not pump},
            belts_or_lanes=belts_or_lanes, multiplier=(1 / divisor) / belt_stack}  ---@type ThroughputViewData
        if not pump then
            view.tooltip = {"fp.view_tt", {"fp.throughput_belts_only", unit, stack_insert, belt.rich_text, belt.localised_name}}
            return view
        end

        ---@cast pump.proto FPPumpPrototype
        local proto, quality = proto_and_quality_string(pump)
        view.caption = {"", belt.rich_text, " ", pump.proto.rich_text}
        view.tooltip = {"fp.view_tt", {"fp.throughput", unit, stack_insert, belt.rich_text, belt.localised_name,
            pump.proto.rich_text, pump.proto.localised_name, quality}}
        view.pumping_speed = proto.get_pumping_speed(pump.quality--[[@cast -nil]].name) * 60
        return view
    end,

    ---@param metadata ItemViewsData
    ---@param raw_amount number
    ---@param item_proto FPItemPrototype | FPFuelPrototype
    ---@return number? button_number
    ---@return LocalisedString tooltip
    process = function(metadata, raw_amount, item_proto, _)
        local view = metadata.views.throughput  ---@as ThroughputViewData
        local raw_number, unit_name = nil, nil

        if item_proto.type == "fluid" then
            raw_number = raw_amount / view.pumping_speed--[[@as number]]
            unit_name = "pump"
        else
            raw_number = raw_amount * view.multiplier
            unit_name = view.belts_or_lanes:sub(1, -2)
        end

        return format_amount(metadata, raw_number, unit_name)
    end
}

view_definitions.items_per_second_per_machine = {
    ---@return ItemViewData
    prepare = function()
        return {
            caption = {"", {"fp.pu_item", 2}, "/", {"fp.unit_second"}, "/[img=fp_generic_assembler]"},
            tooltip = {"fp.view_tt", {"fp.items_per_second_per_machine"}}
        }
    end,

    ---@param metadata ItemViewsData
    ---@param raw_amount number
    ---@param item_proto FPItemPrototype | FPFuelPrototype
    ---@param machine_amount number?
    ---@return number? button_number
    ---@return LocalisedString? tooltip
    process = function(metadata, raw_amount, item_proto, machine_amount)
        local adjusted_count = (math.ceil((machine_amount or 1) - MAGIC_NUMBERS.margin_of_error))
        if adjusted_count == 0 then return 0, nil end  -- avoid division by zero

        local raw_number = raw_amount / adjusted_count
        local unit_name = (item_proto.type == "fluid") and "fluid" or "item"
        -- If machine_amount is nil, this shouldn't show /machine
        local per_machine = (machine_amount ~= nil) and {"", "/", {"fp.pl_machine", 1}} or ""
        return format_amount(metadata, raw_number, unit_name, {"", "/", {"fp.unit_second"}, per_machine})
    end
}

view_definitions.stacks_per_timescale = {
    ---@param _ LuaPlayer
    ---@param timescale_string string
    ---@return ItemViewData
    prepare = function(_, timescale_string)
        return {
            caption = {"", "[img=fp_stack]", "/", {"fp.unit_" .. timescale_string}},
            tooltip = {"fp.view_tt", {"fp.stacks_per_timescale", {"fp." .. timescale_string}}}
        }
    end,

    ---@param metadata ItemViewsData
    ---@param raw_amount number
    ---@param item_proto FPItemPrototype | FPFuelPrototype
    ---@return number? button_number
    ---@return LocalisedString tooltip
    process = function(metadata, raw_amount, item_proto, _)
        if item_proto.type == "fluid" then return nil, {"fp.fluid_item"} end

        local raw_number = (raw_amount * metadata.timescale) / item_proto.stack_size--[[@as uint]]
        return format_amount(metadata, raw_number, "stack", {"", "/", metadata.timescale_string})
    end
}

---@class WagonViewData: ItemViewData
---@field cargo_capacity number?
---@field fluid_capacity number?

view_definitions.wagons_per_timescale = {
    ---@param player LuaPlayer
    ---@param timescale_string string
    ---@return WagonViewData view
    prepare = function(player, timescale_string)
        local cargo = defaults.get_optional(player, "wagons", "cargo-wagon")
        local fluid = defaults.get_optional(player, "wagons", "fluid-wagon")
        local view = {caption={"", {"fp.pu_wagon", 2}, "/", {"fp.unit_" .. timescale_string}},
            unavailable=not cargo and not fluid, unavailable_for={item=not cargo, fluid=not fluid}}  ---@type WagonViewData
        if view.unavailable then
            view.tooltip = {"fp.preference_no_default_prototype", {"fp.pl_wagon", 2}}
            return view
        end

        local cargo_quality, fluid_quality = "", ""  ---@type LocalisedString, LocalisedString
        if cargo then
            ---@cast cargo.proto FPWagonPrototype
            local proto
            proto, cargo_quality = proto_and_quality_string(cargo)
            view.cargo_capacity = proto.get_inventory_size(defines.inventory.cargo_wagon, cargo.quality--[[@cast -nil]].name)
        end
        if fluid then
            ---@cast fluid.proto FPWagonPrototype
            local proto
            proto, fluid_quality = proto_and_quality_string(fluid)
            view.fluid_capacity = proto.get_fluid_capacity(fluid.quality--[[@cast -nil]].name)
        end

        view.caption = {"", cargo and cargo.proto.rich_text or "", fluid and fluid.proto.rich_text or "",
            "/", {"fp.unit_" .. timescale_string}}
        if cargo and fluid then
            view.tooltip = {"fp.view_tt", {"fp.wagons_per_timescale", {"fp." .. timescale_string},
                cargo.proto.rich_text, cargo.proto.localised_name, cargo_quality,
                fluid.proto.rich_text, fluid.proto.localised_name, fluid_quality}}  ---@as LocalisedString
        else
            local wagon = cargo or fluid  ---@cast wagon -nil
            ---@cast wagon.proto FPWagonPrototype
            view.tooltip = {"fp.view_tt", {"fp.wagons_per_timescale_single", {"fp." .. timescale_string},
                wagon.proto.rich_text, wagon.proto.localised_name, cargo and cargo_quality or fluid_quality}}
        end
        return view
    end,

    ---@param metadata ItemViewsData
    ---@param raw_amount number
    ---@param item_proto FPItemPrototype | FPFuelPrototype
    ---@return number? button_number
    ---@return LocalisedString tooltip
    process = function(metadata, raw_amount, item_proto, _)
        local view = metadata.views.wagons_per_timescale  ---@as WagonViewData
        local wagon_capacity = (item_proto.type == "fluid") and view.fluid_capacity
            or view.cargo_capacity--[[@as number]] * item_proto.stack_size--[[@as uint]]
        local raw_number = (raw_amount * metadata.timescale) / wagon_capacity
        return format_amount(metadata, raw_number, "wagon", {"", "/", metadata.timescale_string})
    end
}

---@class RocketViewData: ItemViewData
---@field lift_capacity number?

view_definitions.rockets_per_timescale = {
    ---@param player LuaPlayer
    ---@param timescale_string string
    ---@return RocketViewData view
    prepare = function(player, timescale_string)
        local silo = defaults.get_optional(player, "silos")
        local view = {caption={"", "[img=fp_silo_rocket]", "/", {"fp.unit_" .. timescale_string}},
            unavailable=not silo}  ---@type RocketViewData
        if not silo then
            view.tooltip = {"fp.preference_no_default_prototype", {"fp.pl_silo", 2}}
            return view
        end

        ---@cast silo.proto FPSiloPrototype
        local _, quality = proto_and_quality_string(silo)
        view.tooltip = {"fp.view_tt", {"fp.rockets_per_timescale", {"fp." .. timescale_string},
            silo.proto.rich_text, silo.proto.localised_name, quality}}
        view.lift_capacity = silo.proto.rocket_lift_weight
        return view
    end,

    ---@param metadata ItemViewsData
    ---@param raw_amount number
    ---@param item_proto FPItemPrototype | FPFuelPrototype
    ---@return number? button_number
    ---@return LocalisedString tooltip
    process = function(metadata, raw_amount, item_proto, _)
        if item_proto.type == "fluid" then return nil, {"fp.fluid_item"} end
        local view = metadata.views.rockets_per_timescale  ---@as RocketViewData
        local lift_capacity = view.lift_capacity--[[@as number]]
        if item_proto.weight > lift_capacity then return nil, {"fp.item_too_heavy"} end

        local total_weight = raw_amount * metadata.timescale * item_proto.weight--[[@as Weight]]
        local raw_number = total_weight / lift_capacity
        return format_amount(metadata, raw_number, "rocket", {"", "/", metadata.timescale_string})
    end
}

---@param player LuaPlayer
---@param proto FPItemPrototype | FPFuelPrototype
---@param item_amount number
---@param machine_amount number?
---@return (number | -1 | nil) button_number
---@return LocalisedString? tooltip_line
function item_views.process_item(player, proto, item_amount, machine_amount)
    local views_data = lib.globals.ui_state(player).views_data  ---@cast views_data -nil

    if item_amount == nil or (item_amount ~= 0 and item_amount < views_data.adjusted_margin_of_error) then
        return -1, nil
    end

    if proto.type == "entity" then
        local amount = (proto.fixed_unit) and item_amount or item_amount * views_data.timescale
        local button_number = lib.format.button_number(amount)
        local tooltip_number = lib.format.number(amount, views_data.formatting_precision)
        local unit = proto.fixed_unit or {"fp.per_timescale",
            {"fp." .. lib.gui.timescale_as_string(views_data.timescale)}}
        return button_number, {"", tooltip_number, " ", unit}
    else
        local selected_view = lib.globals.preferences(player).item_views.selected.primary
        local view = views_data.views[selected_view]
        if view.unavailable_for and view.unavailable_for[proto.type] then return nil, nil end
        local processor = view_definitions[selected_view].process
        local number, tooltip = processor(views_data, item_amount, proto, machine_amount)
        return number, tooltip
    end
end

-- Disable unavailable views and keep an enabled view selected
---@param player LuaPlayer
local function reconcile_preferences(player)
    local preferences = lib.globals.preferences(player).item_views
    local data = lib.globals.ui_state(player).views_data  ---@cast data -nil
    local first_enabled, items_view = nil, nil  ---@type string?, ItemViewPreference?
    local selection_enabled = false

    for _, preference in ipairs(preferences.views) do
        if preference.name == "items_per_timescale" then items_view = preference end
        if data.views[preference.name].unavailable then preference.enabled = false end
        if preference.enabled then
            first_enabled = first_enabled or preference.name
            if preference.name == preferences.selected.primary then selection_enabled = true end
        end
    end

    if not first_enabled then
        items_view--[[@cast -nil]].enabled = true
        first_enabled = "items_per_timescale"
    end
    if not selection_enabled then preferences.selected.primary = first_enabled end
end

---@param player LuaPlayer
function item_views.rebuild_data(player)
    local preferences = lib.globals.preferences(player)
    local timescale_string = lib.gui.timescale_as_string(preferences.timescale)

    local prepared_views = {}
    for name, definition in pairs(view_definitions) do
        prepared_views[name] = definition.prepare(player, timescale_string)
    end

    lib.globals.ui_state(player).views_data = {
        views = prepared_views,
        timescale = preferences.timescale,
        timescale_string = {"fp.unit_" .. timescale_string}--[[@as LocalisedString]],
        adjusted_margin_of_error = MAGIC_NUMBERS.margin_of_error / preferences.timescale,
        formatting_precision = MAGIC_NUMBERS.formatting_precision
    }  ---@as ItemViewsData
    reconcile_preferences(player)
end

---@class ItemViewPreferences
---@field views ItemViewPreference[]
---@field selected ItemViewSelection

---@class ItemViewSelection
---@field primary string

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
        selected = {primary="items_per_timescale"}
    }
end


---@param preferences ItemViewPreferences
---@param name string
---@return ItemViewPreference? preference
---@return integer? index
local function find_preference(preferences, name)
    for index, preference in ipairs(preferences.views) do
        if preference.name == name then return preference, index end
    end
    return nil, nil
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
        for _, view_preference in ipairs(view_preferences.views) do
            local view = views[view_preference.name]

            ---@class ChangeViewTags
            ---@field view_name string
            local tags = {mod="fp", on_gui_click="change_view", view_name=view_preference.name}
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
            local name = view_button.tags--[[@as ChangeViewTags]].view_name
            local preference = find_preference(view_preferences, name)
            view_button.toggled = (view_preferences.selected.primary == name)
            view_button.visible = preference--[[@cast -nil]].enabled
        end
    end

    run_on_all_views(player, refresh)
end


---@param player LuaPlayer
---@param name string
local function select_view(player, name)
    local view_preferences = lib.globals.preferences(player).item_views
    local preference = find_preference(view_preferences, name)
    if not preference or not preference.enabled then return end
    view_preferences.selected.primary = name

    item_views.refresh_interface(player)
    local compact_view = lib.globals.ui_state(player).compact_view
    local refresh = (compact_view) and "compact_factory" or "factory"
    lib.gui.run_refresh(player, refresh)
end

---@param player LuaPlayer
---@param direction "standard" | "reverse"
function item_views.cycle_views(player, direction)
    local view_preferences = lib.globals.preferences(player).item_views

    -- The shortcuts can also be used before either interface has been opened.
    if not lib.globals.ui_state(player).views_data then item_views.rebuild_data(player) end

    local _, next_option = find_preference(view_preferences, view_preferences.selected.primary)
    ---@cast next_option -nil
    local total_options = #view_preferences.views
    local mover = (direction == "standard") and 1 or -1

    for _ = 1, total_options do
        next_option = next_option + mover
        if next_option > total_options then next_option = 1
        elseif next_option < 1 then next_option = total_options end

        local preference = view_preferences.views[next_option]  ---@cast preference -nil
        if preference.enabled then
            select_view(player, preference.name)
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
                select_view(player, tags.view_name)
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
