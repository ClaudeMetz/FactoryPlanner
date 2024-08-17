local District = require("backend.data.District")

-- ** LOCAL UTIL **
local function refresh_production(player, _, _)
    local factory = util.context.get(player, "Factory")
    if factory and factory.valid then
        solver.update(player, factory)
        util.raise.refresh(player, "factory")
    end
end


local function refresh_production_bar(player)
    local ui_state = util.globals.ui_state(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]

    if ui_state.main_elements.main_frame == nil then return end
    local production_bar_elements = ui_state.main_elements.production_bar

    local districts_view = ui_state.districts_view
    local factory_valid = factory ~= nil and factory.valid

    production_bar_elements.factory_flow.visible = (not districts_view)
    production_bar_elements.district_flow.visible = districts_view

    local valid_factory_selected = (factory and factory.valid) or false

    if not districts_view then
        -- Power + Emissions
        production_bar_elements.power_emissions_flow.visible = valid_factory_selected
        if valid_factory_selected then
            local top_floor = factory.top_floor
            local label_power = production_bar_elements.power_label
            label_power.caption = {"fp.bold_label", util.format.SI_value(top_floor.power, "W", 3)}
            label_power.tooltip = {"", {"fp.u_power"}, ": ", util.format.SI_value(top_floor.power, "W", 5)}

            local label_emissions = production_bar_elements.emissions_label
            label_emissions.caption = {"fp.bold_label", util.format.SI_value(top_floor.emissions, "E/m", 3)}
            label_emissions.tooltip = util.gui.format_emissions(top_floor.emissions, factory.parent)
        end

        -- Validity label
        local invalid_factory_selected = (factory and not factory.valid) or false
        production_bar_elements.validity_label.visible = invalid_factory_selected
    end

    production_bar_elements.timescale_switch.visible = valid_factory_selected

    util.raise.refresh(player, "view_state")
    ui_state.main_elements.view_state_table.visible = factory_valid
end


local function build_production_bar(player)
    local ui_state = util.globals.ui_state(player)
    local main_elements = ui_state.main_elements
    main_elements.production_bar = {}

    local parent_flow = main_elements.flows.right_vertical
    local subheader = parent_flow.add{type="frame", direction="horizontal", style="inside_deep_frame"}
    subheader.style.padding = {6, 4}
    subheader.style.height = MAGIC_NUMBERS.subheader_height
    -- Not really sure why setting the width here is necessary, but it is
    subheader.style.width = ui_state.main_dialog_dimensions.width - MAGIC_NUMBERS.list_width
        - (3 * MAGIC_NUMBERS.frame_spacing)

    local button_refresh = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="refresh_production"},
        sprite="utility/refresh", style="tool_button", tooltip={"fp.refresh_production"}, mouse_button_filter={"left"}}
    button_refresh.style.top_margin = -2
    main_elements.production_bar["refresh_button"] = button_refresh


    -- Factory bar
    local flow_factory = subheader.add{type="flow", direction="horizontal"}
    main_elements.production_bar["factory_flow"] = flow_factory

    local label_factory = flow_factory.add{type="label", caption={"fp.pu_factory", 1}, style="frame_title"}
    label_factory.style.padding = {-1, 8}

    local flow_power_emissions = flow_factory.add{type="flow", direction="horizontal"}
    flow_power_emissions.style.margin = {3, 0, 0, 12}
    main_elements.production_bar["power_emissions_flow"] = flow_power_emissions
    local label_power_value = flow_power_emissions.add{type="label"}
    main_elements.production_bar["power_label"] = label_power_value
    flow_power_emissions.add{type="label", caption="|"}
    local label_emissions_value = flow_power_emissions.add{type="label"}
    main_elements.production_bar["emissions_label"] = label_emissions_value

    local label_invalid = flow_factory.add{type="label", caption={"fp.invalid"}, style="bold_red_label"}
    label_invalid.style.top_margin = 4
    main_elements.production_bar["validity_label"] = label_invalid

    -- District bar
    local flow_districts = subheader.add{type="flow", direction="horizontal"}
    main_elements.production_bar["district_flow"] = flow_districts

    local label_districts = flow_districts.add{type="label", caption={"fp.pu_district", 2}, style="frame_title"}
    label_districts.style.padding = {-1, 8}

    local button_add = flow_districts.add{type="button", caption={"fp.add_district"}, style="fp_button_green",
        tags={mod="fp", on_gui_click="add_district"}, mouse_button_filter={"left"}}
    button_add.style.height = 26
    button_add.style.left_margin = 12
    button_add.style.minimal_width = 0

    -- Shared bar
    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local flow_timescale = subheader.add{type="flow", direction="horizontal"}
    flow_timescale.style.margin = {4, 16, 0, 0}

    local switch_state = (util.globals.preferences(player).timescale == 1) and "left" or "right"
    local switch_timescale = flow_timescale.add{type="switch", tooltip={"fp.timescale_tt"}, switch_state=switch_state,
        left_label_caption={"", "/", {"fp.second"}}, right_label_caption={"", "/", {"fp.minute"}},
        tags={mod="fp", on_gui_switch_state_changed="toggle_timescale"}}
    switch_timescale.style.margin = {0, 4}
    main_elements.production_bar["timescale_switch"] = switch_timescale

    util.raise.build(player, "view_state", subheader)
    main_elements["view_state_table"] = subheader["table_view_state"]

    refresh_production_bar(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "refresh_production",
            timeout = 20,
            handler = (function(player, _, _)
                if DEV_ACTIVE then  -- implicit mod reload for easier development
                    util.gui.reset_player(player)  -- destroys all FP GUIs
                    util.gui.toggle_mod_gui(player)  -- fixes the mod gui button after its been destroyed
                    game.reload_mods()  -- toggle needs to be delayed by a tick since the reload is not instant
                    game.print("Mods reloaded")
                    util.nth_tick.register((game.tick + 1), "interface_toggle", {player_index=player.index})
                else
                    refresh_production(player, nil, nil)
                end
            end)
        },
        {
            name = "add_district",
            handler = (function(player, _, _)
                local realm = util.globals.player_table(player).realm
                local new_district = District.init()
                realm:insert(new_district)
                util.context.set(player, new_district)
                util.raise.refresh(player, "all")
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "toggle_timescale",
            handler = (function(player, _, event)
                local new_timescale = (event.element.switch_state == "left") and 1 or 60
                util.globals.preferences(player).timescale = new_timescale

                view_state.rebuild_state(player)
                util.raise.refresh(player, "factory")
            end)
        }
    }
}

listeners.misc = {
    fp_refresh_production = (function(player, _, _)
        if main_dialog.is_in_focus(player) then refresh_production(player, nil, nil) end
    end),

    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_production_bar(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {production_bar=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_production_bar(player) end
    end)
}

return { listeners }
