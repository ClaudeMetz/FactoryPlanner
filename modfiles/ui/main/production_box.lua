local Line = require("backend.data.Line")

-- ** LOCAL UTIL **
local function refresh_production(player, _, _)
    local factory = util.context.get(player, "Factory")
    if factory and factory.valid then
        solver.update(player, factory)
        util.raise.refresh(player, "factory", nil)
    end
end

local function paste_line(player, _, _)
    local floor = util.context.get(player, "Floor")  --[[@as Floor]]

    local dummy_line = Line.init({}, "produce")
    util.clipboard.dummy_paste(player, dummy_line, floor)
end

-- Changes the floor to either be the top one or the one above the current one
local function change_floor(player, destination)
    if util.context.descend_floors(player, destination) then
        -- Only refresh if the floor was indeed changed
        util.raise.refresh(player, "production", nil)
    end
end


local function refresh_paste_button(player)
    local main_elements = util.globals.main_elements(player)
    if not main_elements.production_box then return end

    local line_copied = util.clipboard.check_classes(player, {Floor=true, Line=true})
    main_elements.production_box.paste_button.visible = line_copied
end


local function refresh_production_box(player)
    local ui_state = util.globals.ui_state(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local floor = util.context.get(player, "Floor")  --[[@as Floor]]

    if ui_state.main_elements.main_frame == nil then return end
    local production_box_elements = ui_state.main_elements.production_box

    local factory_valid = factory and factory.valid
    local current_level = (factory_valid) and floor.level or 1
    local any_lines_present = (factory_valid) and (floor:count() > 0) or false

    production_box_elements.refresh_button.enabled =
        (not factory.archived and factory_valid and any_lines_present)
    production_box_elements.level_label.caption = (not factory_valid) and ""
        or {"fp.bold_label", {"", {"fp.level"}, " ", current_level}}

    production_box_elements.floor_up_button.visible = (factory_valid)
    production_box_elements.floor_up_button.enabled = (current_level > 1)

    production_box_elements.floor_top_button.visible = (factory_valid)
    production_box_elements.floor_top_button.enabled = (current_level > 1)

    production_box_elements.separator_line.visible = (factory_valid)
    production_box_elements.utility_dialog_button.visible = (factory_valid)

    util.raise.refresh(player, "view_state", production_box_elements.view_state_table)
    production_box_elements.view_state_table.visible = (factory_valid)

    -- This structure is stupid and huge, but not sure how to do it more elegantly
    production_box_elements.instruction_label.visible = false
    if not factory.archived then
        if factory == nil then
            production_box_elements.instruction_label.caption = {"fp.production_instruction_factory"}
            production_box_elements.instruction_label.visible = true
        elseif factory_valid and not any_lines_present then
            if factory:count() == 0 then
                production_box_elements.instruction_label.caption = {"fp.production_instruction_product"}
                production_box_elements.instruction_label.visible = true
            else
                production_box_elements.instruction_label.caption = {"fp.production_instruction_recipe"}
                production_box_elements.instruction_label.visible = true
            end
        end
    end

    refresh_paste_button(player)
end

local function build_production_box(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.production_box = {}

    local parent_flow = main_elements.flows.right_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}

    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}
    subheader.style.maximal_height = 100  -- large value to nullify maximal_height
    subheader.style.padding = {8, 8, 6, 8}

    local button_refresh = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="refresh_production"},
        sprite="utility/refresh", style="tool_button", tooltip={"fp.refresh_production"}, mouse_button_filter={"left"}}
    main_elements.production_box["refresh_button"] = button_refresh

    local label_title = subheader.add{type="label", caption={"fp.production"}, style="frame_title"}
    label_title.style.padding = {0, 8}

    local label_level = subheader.add{type="label"}
    label_level.style.right_margin = 8
    main_elements.production_box["level_label"] = label_level

    local button_floor_up = subheader.add{type="sprite-button", sprite="fp_sprite_arrow_line_up",
        tooltip={"fp.floor_up_tt"}, tags={mod="fp", on_gui_click="change_floor", destination="up"},
        style="fp_sprite-button_rounded_mini", mouse_button_filter={"left"}}
    main_elements.production_box["floor_up_button"] = button_floor_up

    local button_floor_top = subheader.add{type="sprite-button", sprite="fp_sprite_arrow_line_bar_up",
        tooltip={"fp.floor_top_tt"}, tags={mod="fp", on_gui_click="change_floor", destination="top"},
        style="fp_sprite-button_rounded_mini", mouse_button_filter={"left"}}
    main_elements.production_box["floor_top_button"] = button_floor_top

    local separator = subheader.add{type="line", direction="vertical"}
    separator.style.margin = {0, 8}
    main_elements.production_box["separator_line"] = separator

    local button_utility_dialog = subheader.add{type="button", caption={"fp.utilities"},
        tooltip={"fp.utility_dialog_tt"}, tags={mod="fp", on_gui_click="open_utility_dialog"},
        style="fp_button_rounded_mini", mouse_button_filter={"left"}}
    main_elements.production_box["utility_dialog_button"] = button_utility_dialog

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    util.raise.build(player, "view_state", subheader)
    main_elements.production_box["view_state_table"] = subheader["table_view_state"]

    local label_instruction = frame_vertical.add{type="label", style="bold_label"}
    label_instruction.style.margin = 20
    main_elements.production_box["instruction_label"] = label_instruction

    local flow_production_table = frame_vertical.add{type="flow", direction="horizontal"}
    main_elements.production_box["production_table_flow"] = flow_production_table

    local button_paste = frame_vertical.add{type="button", caption={"fp.paste_line"}, tooltip={"fp.paste_line_tt"},
        style="fp_button_rounded_mini", tags={mod="fp", on_gui_click="paste_line"}, mouse_button_filter={"left"}}
    button_paste.style.margin = {6, 12}
    main_elements.production_box["paste_button"] = button_paste

    frame_vertical.add{type="empty-widget", style="flib_vertical_pusher"}

    local frame_messages = frame_vertical.add{type="frame", direction="vertical",
        visible=false, style="fp_frame_messages"}
    main_elements["messages_frame"] = frame_messages

    refresh_production_box(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "refresh_production",
            timeout = 20,
            handler = refresh_production
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
        },
        {
            name = "paste_line",
            handler = paste_line
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
            build_production_box(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {production_box=true, production_detail=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_production_box(player)
        elseif event.trigger == "paste_button" then refresh_paste_button(player) end
    end)
}

return { listeners }
