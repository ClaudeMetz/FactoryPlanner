local function refresh_production(player, _, _)
    local factory = util.context.get(player, "Factory")
    if factory and factory.valid then
        solver.update(player, factory)
        util.raise.refresh(player, "factory", nil)
    end
end

local function change_floor(player, destination)
    if util.context.ascend_floors(player, destination) then
        -- Only refresh if the floor was indeed changed
        util.raise.refresh(player, "production", nil)
    end
end


local function refresh_production_bar(player)
    local ui_state = util.globals.ui_state(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    local floor = util.context.get(player, "Floor")  --[[@as Floor?]]

    if ui_state.main_elements.main_frame == nil then return end
    local production_bar_elements = ui_state.main_elements.production_bar

    local factory_valid = factory ~= nil and factory.valid
    local current_level = (factory_valid) and floor.level or 1

    production_bar_elements.refresh_button.enabled = factory_valid
    production_bar_elements.level_label.caption = (not factory_valid) and ""
        or {"fp.bold_label", {"", {"fp.level"}, " ", current_level}}

    production_bar_elements.floor_up_button.visible = factory_valid
    production_bar_elements.floor_up_button.enabled = (current_level > 1)

    production_bar_elements.floor_top_button.visible = factory_valid
    production_bar_elements.floor_top_button.enabled = (current_level > 1)

    production_bar_elements.utility_dialog_button.enabled = factory_valid

    util.raise.refresh(player, "view_state", production_bar_elements.view_state_table)
    production_bar_elements.view_state_table.visible = factory_valid
end


local function build_production_bar(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.production_bar = {}

    local parent_flow = main_elements.flows.right_vertical
    local subheader = parent_flow.add{type="frame", direction="horizontal", style="inside_deep_frame"}
    subheader.style.padding = {6, 4}
    subheader.style.height = MAGIC_NUMBERS.subheader_height

    local button_refresh = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="refresh_production"},
        sprite="utility/refresh", style="tool_button", tooltip={"fp.refresh_production"}, mouse_button_filter={"left"}}
    button_refresh.style.top_margin = -2
    main_elements.production_bar["refresh_button"] = button_refresh

    local label_title = subheader.add{type="label", caption={"fp.production"}, style="frame_title"}
    label_title.style.padding = {-1, 8}

    local label_level = subheader.add{type="label"}
    label_level.style.margin = {4, 6, 0, 0}
    main_elements.production_bar["level_label"] = label_level

    local button_floor_up = subheader.add{type="sprite-button", sprite="fp_arrow_line_up",
        tooltip={"fp.floor_up_tt"}, tags={mod="fp", on_gui_click="change_floor", destination="up"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    main_elements.production_bar["floor_up_button"] = button_floor_up

    local button_floor_top = subheader.add{type="sprite-button", sprite="fp_arrow_line_bar_up",
        tooltip={"fp.floor_top_tt"}, tags={mod="fp", on_gui_click="change_floor", destination="top"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_floor_top.style.padding = {3, 2, 1, 2}
    main_elements.production_bar["floor_top_button"] = button_floor_top

    local button_utility_dialog = subheader.add{type="button", caption={"fp.utilities"},
        tooltip={"fp.utility_dialog_tt"}, tags={mod="fp", on_gui_click="open_utility_dialog"},
        style="rounded_button", mouse_button_filter={"left"}}
    button_utility_dialog.style.minimal_width = 0
    button_utility_dialog.style.height = 26
    button_utility_dialog.style.left_margin = 12
    main_elements.production_bar["utility_dialog_button"] = button_utility_dialog

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    util.raise.build(player, "view_state", subheader)
    main_elements.production_bar["view_state_table"] = subheader["table_view_state"]

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
            name = "change_floor",
            handler = (function(player, tags, _)
                change_floor(player, tags.destination)
            end)
        },
        {
            name = "open_utility_dialog",
            handler = (function(player, _, _)
                util.raise.open_dialog(player, {dialog="utility"})
            end)
        }
    }
}

listeners.misc = {
    fp_refresh_production = (function(player, _, _)
        if main_dialog.is_in_focus(player) then refresh_production(player, nil, nil) end
    end),
    fp_up_floor = (function(player, _, _)
        if main_dialog.is_in_focus(player) then change_floor(player, "up") end
    end),
    fp_top_floor = (function(player, _, _)
        if main_dialog.is_in_focus(player) then change_floor(player, "top") end
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
