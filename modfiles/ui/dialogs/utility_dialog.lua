-- ** LOCAL UTIL **
-- Adds a box with title and optional scope switch for the given type of utility
local function add_utility_box(player, modal_elements, type, show_tooltip, show_switch)
    local bordered_frame = modal_elements.content_frame.add{type="frame", direction="vertical",
        style="fp_frame_bordered_stretch"}
    modal_elements[type .. "_box"] = bordered_frame

    local flow_title_bar = bordered_frame.add{type="flow", direction="horizontal"}
    flow_title_bar.style.vertical_align = "center"
    flow_title_bar.style.margin = {2, 0, 4, 0}

    -- Title
    local caption = (show_tooltip) and {"fp.info_label", {"fp.utility_title_".. type}} or {"fp.utility_title_".. type}
    local tooltip = (show_tooltip) and {"fp.utility_title_" .. type .. "_tt"}
    local label_title = flow_title_bar.add{type="label", caption=caption, tooltip=tooltip, style="caption_label"}
    label_title.style.top_margin = -2

    -- Empty flow for custom controls
    flow_title_bar.add{type="empty-widget", style="flib_horizontal_pusher"}
    local flow_custom = flow_title_bar.add{type="flow"}
    flow_custom.style.right_margin = 12

    -- Scope switch
    local scope_switch = nil
    if show_switch then
        local utility_scope = util.globals.preferences(player).utility_scopes[type]
        local switch_state = (utility_scope == "Factory") and "left" or "right"
        scope_switch = flow_title_bar.add{type="switch", switch_state=switch_state,
            tags={mod="fp", on_gui_switch_state_changed="utility_change_scope", utility_type=type},
            left_label_caption={"fp.pu_factory", 1}, right_label_caption={"fp.pu_floor", 1}}
    end

    return bordered_frame, flow_custom, scope_switch
end


local utility_structures = {}

local function update_request_button(player, modal_data, factory)
    local modal_elements = modal_data.modal_elements

    local button_enabled, switch_enabled = true, true
    local caption = ""  ---@type LocalisedString
    local tooltip = ""  ---@type LocalisedString
    local font_color = {}

    if factory.item_request_proxy ~= nil then
        caption = {"fp.cancel_request"}
        font_color = {0.8, 0, 0}
        switch_enabled = false

    else
        local scope = util.globals.preferences(player).utility_scopes.components
        local scope_string = {"fp.pl_" .. scope:lower(), 1}
        caption, tooltip = {"fp.request_items"}, {"fp.request_items_tt", scope_string}

        if not player.force.character_logistic_requests then
            tooltip = {"fp.warning_with_icon", {"fp.request_logistics_not_researched"}}
            button_enabled = false
        elseif not next(modal_data.missing_items) then
            tooltip = {"fp.warning_with_icon", {"fp.utility_no_items_necessary", scope_string}}
            button_enabled = false
        elseif player.character == nil then  -- happens when the editor is active for example
            tooltip = {"fp.warning_with_icon", {"fp.request_no_character"}}
            button_enabled = false
        end
    end

    modal_elements.request_button.caption = caption
    modal_elements.request_button.tooltip = tooltip
    modal_elements.request_button.style.font_color = font_color
    modal_elements.request_button.enabled = button_enabled
    modal_elements.scope_switch.enabled = switch_enabled
end

function utility_structures.components(player, modal_data)
    local preferences = util.globals.preferences(player)
    local scope = preferences.utility_scopes.components
    local skip_done = (preferences.done_column == true)
    local modal_elements = modal_data.modal_elements

    if modal_elements.components_box == nil then
        local components_box, custom_flow, scope_switch = add_utility_box(player, modal_data.modal_elements,
            "components", true, true)
        modal_elements.components_box = components_box
        modal_elements.scope_switch = scope_switch

        local button_combinator = custom_flow.add{type="sprite-button", sprite="item/constant-combinator",
            tooltip={"fp.ingredients_to_combinator_tt"}, tags={mod="fp", on_gui_click="utility_item_combinator"},
            style="fp_sprite-button_rounded_mini", mouse_button_filter={"left"}}
        button_combinator.style.size = 29
        button_combinator.style.padding = 0
        modal_elements.combinator_button = button_combinator

        local button_request = custom_flow.add{type="button", tags={mod="fp", on_gui_click="utility_request_items"},
            style="rounded_button", mouse_button_filter={"left"}}
        button_request.style.minimal_width = 0
        modal_elements.request_button = button_request

        local table_components = components_box.add{type="table", column_count=2}
        table_components.style.horizontal_spacing = 24
        table_components.style.vertical_spacing = 8

        local function add_component_row(type)
            table_components.add{type="label", caption={"fp.pu_" .. type, 2}, style="semibold_label"}

            local flow = table_components.add{type="flow", direction="horizontal"}
            modal_elements["components_" .. type .. "_flow"] = flow
        end

        add_component_row("machine")
        add_component_row("module")
    end

    local component_data, relevant_object = nil, util.context.get(player, scope)
    if scope == "Factory" then relevant_object = relevant_object--[[@as Factory]].top_floor end
    component_data = relevant_object--[[@as Floor]]:get_component_data(skip_done, nil)

    local function refresh_component_flow(type)
        local component_row = modal_elements["components_" .. type .. "_flow"]
        component_row.clear()

        local inventory_contents = modal_data.inventory_contents
        local frame_components = component_row.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
        local table_components = frame_components.add{type="table", column_count=10, style="filter_slot_table"}

        for _, component in pairs(component_data[type .. "s"]) do
            if component.amount > 0 then
                local proto, required_amount = component.proto, component.amount
                local amount_in_inventory = inventory_contents[proto.name] or 0
                local missing_amount = required_amount - amount_in_inventory

                if missing_amount > 0 then
                    local signal = {type=proto.type or "item", name=proto.name}
                    modal_data.missing_items[signal] = missing_amount
                end

                local button_style = nil
                if amount_in_inventory == 0 then button_style = "flib_slot_button_red"
                elseif missing_amount > 0 then button_style = "flib_slot_button_yellow"
                else button_style = "flib_slot_button_green" end

                local tooltip = {"fp.components_needed_tt", {"fp.tt_title", proto.localised_name},
                    amount_in_inventory, required_amount}

                local category_id = (proto.data_type == "items") and proto.category_id
                    or PROTOTYPE_MAPS.items["item"].id  -- modules/beacons are always an 'item'
                local proto_id = (proto.data_Type == "items") and proto.id
                    or PROTOTYPE_MAPS.items["item"].members[proto.name].id
                table_components.add{type="sprite-button", sprite=proto.sprite, number=required_amount, tooltip=tooltip,
                    tags={mod="fp", on_gui_click="utility_craft_items", category_id=category_id, item_id=proto_id,
                    missing_amount=missing_amount}, style=button_style, mouse_button_filter={"left-and-right"}}
            end
        end

        if not next(table_components.children_names) then
            frame_components.visible = false
            local label = component_row.add{type="label", caption={"fp.no_components_needed", {"fp.pl_" .. type, 2}}}
            label.style.margin = {10, 0}
        end
    end

    modal_data.missing_items = {}  -- a flat structure works because there is no overlap between machines and modules
    refresh_component_flow("machine")
    refresh_component_flow("module")


    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    factory:validate_item_request_proxy()

    local any_missing_items = (next(modal_data.missing_items) ~= nil)
    modal_elements.combinator_button.enabled = any_missing_items
    modal_elements.combinator_button.tooltip = (any_missing_items) and {"fp.utility_combinator_tt"}
        or {"fp.warning_with_icon", {"fp.utility_no_items_necessary", {"fp.pl_" .. scope:lower(), 1}}}

    update_request_button(player, modal_data, factory)
end

function utility_structures.blueprints(player, modal_data)
    local modal_elements = modal_data.modal_elements
    local blueprints = util.context.get(player, "Factory").blueprints
    local blueprint_limit = MAGIC_NUMBERS.blueprint_limit

    if modal_elements.blueprints_box == nil then
        local blueprints_box = add_utility_box(player, modal_data.modal_elements, "blueprints", true, false)
        modal_elements["blueprints_box"] = blueprints_box

        local frame_blueprints = blueprints_box.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
        local table_blueprints = frame_blueprints.add{type="table", column_count=blueprint_limit,
            style="filter_slot_table"}
        table_blueprints.style.width = blueprint_limit * 40
        modal_elements["blueprints_table"] = table_blueprints
    end

    local table_blueprints =  modal_elements["blueprints_table"]
    table_blueprints.clear()

    local tutorial_tt = (util.globals.preferences(player).tutorial_mode)
        and util.actions.tutorial_tooltip("act_on_blueprint", nil, player) or nil

    local function format_signal(signal)
        -- This is screwed up, it never returns signal.type for some reason
        local type = (signal.type == "virtual") and "virtual-signal" or "item"
        return (type .. "/" .. signal.name)
    end

    local blueprint = modal_data.utility_inventory[1]  -- re-usable inventory slot
    for index, blueprint_string in pairs(blueprints) do
        blueprint.import_stack(blueprint_string)
        local blueprint_book = blueprint.is_blueprint_book

        local tooltip = {"", (blueprint.label or "Blueprint"), tutorial_tt}
        local sprite = (blueprint_book) and "item/blueprint-book" or "item/blueprint"
        local button = table_blueprints.add{type="sprite-button", sprite=sprite, tooltip=tooltip,
            tags={mod="fp", on_gui_click="act_on_blueprint", index=index}, mouse_button_filter={"left-and-right"}}

        local icons = (not blueprint_book) and blueprint.preview_icons
            or blueprint.get_inventory(defines.inventory.item_main)[1].preview_icons
        if icons then  -- this is jank-hell
            local icon_count = #icons
            local flow = button.add{type="flow", direction="horizontal", ignored_by_interaction=true}
            local top_margin = (blueprint_book) and 4 or 7

            if icon_count == 1 then
                local sprite_icon = flow.add{type="sprite", sprite=format_signal(icons[1].signal)}
                sprite_icon.style.margin = {top_margin, 0, 0, 7}
            else
                flow.style.padding = {4, 0, 0, 3}
                local table = flow.add{type="table", column_count=2}
                table.style.cell_padding = -3
                if icon_count == 2 then table.style.top_margin = top_margin end
                for _, icon in pairs(icons) do
                    table.add{type="sprite", sprite=format_signal(icon.signal)}
                end
            end
        end

        blueprint.clear()
    end

    if #blueprints < blueprint_limit then
        local button_add = table_blueprints.add{type="sprite-button", sprite="utility/add",
            tags={mod="fp", on_gui_click="utility_store_blueprint"}, style="fp_sprite-button_inset_add_slot",
            mouse_button_filter={"left"}}
        button_add.style.padding = 3
    end
end

function utility_structures.notes(player, modal_data)
    local utility_box = add_utility_box(player, modal_data.modal_elements, "notes", false, false)

    local notes = util.context.get(player, "Factory").notes
    local text_box = utility_box.add{type="text-box", text=notes,
        tags={mod="fp", on_gui_text_changed="factory_notes"}}
    text_box.style.size = {480, 250}
    text_box.word_wrap = true
    text_box.style.top_margin = -2
end


local function handle_scope_change(player, tags, event)
    local utility_scope = (event.element.switch_state == "left") and "Factory" or "Floor"
    util.globals.preferences(player).utility_scopes[tags.utility_type] = utility_scope

    local modal_data = util.globals.modal_data(player)
    utility_structures.components(player, modal_data)
end

local function handle_item_request(player, _, _)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]

    if factory.item_request_proxy then  -- if an item_proxy is set, cancel it
        factory:destroy_item_request_proxy()
    else
        local modules = {}
        for signal, amount in pairs(modal_data.missing_items) do modules[signal.name] = amount end

        -- This crazy way to request items actually works, and is way easier than setting logistic requests
        -- The advantage that is has is that the delivery is one-time, not a constant request
        -- The disadvantage is that it's weird to have construction bots bring you stuff
        factory.item_request_proxy = player.surface.create_entity{name="item-request-proxy",
            position=player.position, force=player.force, target=player.character, modules=modules}
    end

    update_request_button(player, modal_data, factory)
end

local function handle_item_handcraft(player, tags, event)
    local fly_text = util.cursor.create_flying_text
    if not player.character then fly_text(player, {"fp.utility_no_character"}); return end

    local permissions = player.permission_group
    local forbidden = (permissions and not permissions.allows_action(defines.input_action.craft))
    if forbidden then fly_text(player, {"fp.utility_no_crafting"}); return end

    local desired_amount = (event.button == defines.mouse_button_type.right) and 5 or 1
    local amount_to_craft = math.min(desired_amount, tags.missing_amount)

    if amount_to_craft <= 0 then fly_text(player, {"fp.utility_no_demand"}); return end

    local recipes = RECIPE_MAPS["produce"][tags.category_id][tags.item_id]
    if not recipes then fly_text(player, {"fp.utility_no_recipe"}); return end

    local success = false
    for recipe_id, _ in pairs(recipes) do
        local recipe_name = global.prototypes.recipes[recipe_id].name
        local craftable_amount = player.get_craftable_count(recipe_name)

        if craftable_amount > 0 then
            success = true
            local crafted_amount = math.min(amount_to_craft, craftable_amount)
            player.begin_crafting{count=crafted_amount, recipe=recipe_name, silent=true}
            amount_to_craft = amount_to_craft - crafted_amount
            break
        end
    end
    if not success then fly_text(player, {"fp.utility_no_resources"}); end
end

local function handle_inventory_change(player)
    local ui_state = util.globals.ui_state(player)

    if ui_state.modal_dialog_type == "utility" then
        ui_state.modal_data.inventory_contents = player.get_main_inventory().get_contents()
        utility_structures.components(player, ui_state.modal_data)
    end
end


local function store_blueprint(player, _, _)
    local fly_text = util.cursor.create_flying_text

    if player.is_cursor_empty() then
        fly_text(player, {"fp.utility_cursor_empty"}); return
    end
    local cursor = player.cursor_stack
    if not (cursor.is_blueprint or cursor.is_blueprint_book) then
        if cursor.valid_for_read then
            fly_text(player, {"fp.utility_no_blueprint"}); return
        else
            fly_text(player, {"fp.utility_blueprint_from_library"}); return
        end
    end
    if cursor.is_blueprint then
        if not cursor.is_blueprint_setup() then fly_text(player, {"fp.utility_blueprint_not_setup"}); return end
    else -- blueprint book
        local inventory = cursor.get_inventory(defines.inventory.item_main)
        if inventory.is_empty() then fly_text(player, {"fp.utility_blueprint_book_empty"}); return end
    end

    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    table.insert(factory.blueprints, cursor.export_stack())
    fly_text(player, {"fp.utility_blueprint_stored"});
    player.clear_cursor()  -- doesn't delete blueprint, but puts it back in the inventory

    utility_structures.blueprints(player, util.globals.modal_data(player))
end

local function handle_blueprint_click(player, tags, action)
    local blueprints = util.context.get(player, "Factory").blueprints

    if action == "pick_up" then
        player.cursor_stack.import_stack(blueprints[tags.index])
        util.raise.close_dialog(player, "cancel")
        main_dialog.toggle(player)

    elseif action == "delete" then
        table.remove(blueprints, tags.index)
        utility_structures.blueprints(player, util.globals.modal_data(player))
    end
end


local function open_utility_dialog(player, modal_data)
    -- Add the players' relevant inventory components to modal_data
    modal_data.inventory_contents = player.get_main_inventory().get_contents()
    modal_data.utility_inventory = game.create_inventory(1)  -- used for blueprint decoding

    utility_structures.components(player, modal_data)
    utility_structures.blueprints(player, modal_data)
    utility_structures.notes(player, modal_data)
end

local function close_utility_dialog(player, _)
    util.globals.modal_data(player).utility_inventory.destroy()
    util.raise.refresh(player, "factory_info", nil)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "utility_item_combinator",
            timeout = 20,
            handler = (function(player, _, _)
                local missing_items = util.globals.modal_data(player).missing_items
                local success = util.cursor.set_item_combinator(player, missing_items)
                if success then util.raise.close_dialog(player, "cancel"); main_dialog.toggle(player) end
            end)
        },
        {
            name = "utility_request_items",
            timeout = 20,
            handler = handle_item_request
        },
        {
            name = "utility_craft_items",
            handler = handle_item_handcraft
        },
        {
            name = "utility_store_blueprint",
            handler = store_blueprint
        },
        {
            name = "act_on_blueprint",
            modifier_actions = {
                pick_up = {"left"},
                delete = {"control-right"}
            },
            handler = handle_blueprint_click
        },
    },
    on_gui_switch_state_changed = {
        {
            name = "utility_change_scope",
            handler = handle_scope_change
        }
    },
    on_gui_text_changed = {
        {
            name = "factory_notes",
            handler = (function(player, _, event)
                util.context.get(player, "Factory").notes = event.element.text
            end)
        }
    }
}

listeners.dialog = {
    dialog = "utility",
    metadata = (function(_) return {
        caption = {"fp.utilities"},
        create_content_frame = true
    } end),
    open = open_utility_dialog,
    close = close_utility_dialog
}

listeners.misc = {
    on_player_main_inventory_changed = handle_inventory_change
}

return { listeners }
