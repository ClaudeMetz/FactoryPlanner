-- ** LOCAL UTIL **
-- Adds a box with title and optional scope switch for the given type of utility
local function add_utility_box(player, modal_elements, parent_name, type, show_tooltip, show_switch)
    local bordered_frame = modal_elements[parent_name].add{type="frame", direction="vertical",
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

function utility_structures.components(player, modal_data)
    local preferences = util.globals.preferences(player)
    local scope = preferences.utility_scopes.components
    local skip_done = (preferences.done_column == true)
    local modal_elements = modal_data.modal_elements

    if modal_elements.components_box == nil then
        local components_box, custom_flow, scope_switch = add_utility_box(player, modal_data.modal_elements,
            "content_frame", "components", true, true)
        modal_elements.components_box = components_box
        modal_elements.scope_switch = scope_switch

        local function action_button(sprite, action)
            local button = custom_flow.add{type="sprite-button", sprite=sprite, tags={mod="fp", on_gui_click=action},
                style="fp_sprite-button_rounded_sprite", mouse_button_filter={"left"}}
            button.style.size = 29
            button.style.padding = 0
            return button
        end
        modal_elements.combinator_button = action_button("item/constant-combinator", "utility_item_combinator")
        modal_elements.request_button = action_button("item/logistic-robot", "utility_request_items")

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

    local relevant_object = util.context.get(player, scope)
    if scope == "Factory" then relevant_object = relevant_object--[[@as Factory]].top_floor end
    local component_data = relevant_object--[[@as Floor]]:get_component_data(skip_done, nil)

    local function refresh_component_flow(type)
        local component_row = modal_elements["components_" .. type .. "_flow"]
        component_row.clear()

        local main_inventory = (player.character) and player.character.get_main_inventory() or nil
        local frame_components = component_row.add{type="frame", direction="horizontal", style="fp_frame_light_slots"}
        local table_components = frame_components.add{type="table", column_count=10, style="filter_slot_table"}

        for _, component in pairs(component_data[type .. "s"]) do
            if component.amount > 0 then
                local proto, quality_proto, required_amount = component.proto, component.quality_proto, component.amount
                local item_id = {name = proto.name, quality = quality_proto.name}
                local amount_in_inventory = (main_inventory) and main_inventory.get_item_count(item_id) or 0
                local missing_amount = required_amount - amount_in_inventory

                if missing_amount > 0 then
                    table.insert(modal_data.missing_items, {
                        type = "item",
                        name = proto.name,
                        quality = quality_proto.name,
                        comparator = "=",
                        count = missing_amount,
                        required_count = required_amount
                    })
                end

                local button_style = nil
                if amount_in_inventory == 0 then button_style = "flib_slot_button_red"
                elseif missing_amount > 0 then button_style = "flib_slot_button_yellow"
                else button_style = "flib_slot_button_green" end

                local title_line = (not quality_proto.always_show) and {"fp.tt_title",proto.localised_name}
                    or {"fp.tt_title_with_note", proto.localised_name, quality_proto.rich_text}
                local tooltip = {"fp.components_needed_tt", title_line, amount_in_inventory, required_amount}

                local category_id = (proto.data_type == "items") and proto.category_id
                    or prototyper.util.find("items", nil, "item").id
                local proto_id = (proto.data_type == "items") and proto.id
                    or prototyper.util.find("items", proto.name, "item").id
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

    local any_missing_items = (next(modal_data.missing_items) ~= nil)
    local no_items_necessary = {"fp.utility_no_items_necessary", {"fp.pl_" .. scope:lower(), 1}}
    local function configure_button(name)
        local button = modal_elements[name .. "_button"]
        button.enabled = any_missing_items
        button.tooltip = (any_missing_items) and {"fp.utility_" .. name .. "_tt"} or no_items_necessary
    end
    configure_button("combinator")
    configure_button("request")
end

function utility_structures.blueprints(player, modal_data)
    local modal_elements = modal_data.modal_elements
    local blueprints = util.context.get(player, "Factory").blueprints
    local blueprint_limit = MAGIC_NUMBERS.blueprint_limit

    if modal_elements.blueprints_box == nil then
        local blueprints_box = add_utility_box(player, modal_elements, "content_frame", "blueprints", true, false)
        blueprints_box.style.margin = {4, 0}
        modal_elements["blueprints_box"] = blueprints_box

        local frame_blueprints = blueprints_box.add{type="frame", direction="horizontal", style="fp_frame_light_slots"}
        local table_blueprints = frame_blueprints.add{type="table", column_count=blueprint_limit,
            style="filter_slot_table"}
        table_blueprints.style.width = blueprint_limit * 40
        modal_elements["blueprints_table"] = table_blueprints
    end

    local table_blueprints =  modal_elements["blueprints_table"]
    table_blueprints.clear()

    local function format_signal(signal)
        -- signal.type is nil if it's really "item", plus we need to translate the virtual type
        local type = (signal.type == "virtual") and "virtual-signal" or "item"
        return (type .. "/" .. signal.name)
    end

    local blueprint = modal_data.utility_inventory[1]  -- re-usable inventory slot
    for index, blueprint_string in pairs(blueprints) do
        blueprint.import_stack(blueprint_string)
        local blueprint_book = blueprint.is_blueprint_book

        local tooltip = {"", (blueprint.label or "Blueprint"), "\n", MODIFIER_ACTIONS["act_on_blueprint"].tooltip}
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
            tags={mod="fp", on_gui_click="utility_store_blueprint"}, style="fp_sprite-button_inset",
            mouse_button_filter={"left"}}
        button_add.style.padding = 4
        button_add.style.margin = 4
    end
end

function utility_structures.notes(player, modal_data)
    local utility_box = add_utility_box(player, modal_data.modal_elements, "content_frame", "notes", false, false)

    local notes = util.context.get(player, "Factory").notes
    local text_box = utility_box.add{type="text-box", text=notes,
        tags={mod="fp", on_gui_text_changed="factory_notes"}}
    text_box.style.vertically_stretchable = true
    text_box.style.minimal_height = 320
    text_box.style.width = 480
    text_box.word_wrap = true
end

function utility_structures.productivity_boni(player, modal_data)
    local current_factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local attach_factory_products = util.globals.preferences(player).attach_factory_products

    if not modal_data.modal_elements["productivity_boni_table"] then
        local boni_box = add_utility_box(player, modal_data.modal_elements, "secondary_frame",
            "productivity_boni", true, false)

        local flow_import = boni_box.add{type="flow", direction="horizontal"}
        flow_import.style.vertical_align = "center"
        flow_import.style.bottom_margin = 8
        flow_import.add{type="label", caption={"fp.import_from"}, style="bold_label"}
        flow_import.add{type="empty-widget", style="flib_horizontal_pusher"}

        local factory_names = {}
        modal_data.factory_index = {}  -- used to find the factory later
        for factory in current_factory.parent:iterator() do
            if factory.id ~= current_factory.id then
                local factory_name = factory:tostring(attach_factory_products, true)
                table.insert(factory_names, factory_name)
                table.insert(modal_data.factory_index, factory.id)  -- will match dropdown index
            end
        end
        local enabled = (#factory_names > 0)
        local dropdown_factory = flow_import.add{type="drop-down", items=factory_names, enabled=enabled}
        dropdown_factory.style.maximal_width = 225
        modal_data.modal_elements["factory_dropdown"] = dropdown_factory

        flow_import.add{type="sprite-button", tags={mod="fp", on_gui_click="import_productivity_boni"},
            style="flib_tool_button_light_green", tooltip={"fp.import_from_tt"}, enabled=enabled,
            sprite="utility/check_mark", mouse_button_filter={"left"}}


        local table = boni_box.add{type="table", column_count=3}
        table.style.column_alignments[2] = "center"
        table.style.column_alignments[3] = "center"
        table.style.horizontal_spacing = 16
        modal_data.modal_elements["productivity_boni_table"] = table

        boni_box.add{type="empty-widget", style="flib_vertical_pusher"}
    end
    local table = modal_data.modal_elements["productivity_boni_table"]
    table.clear()

    table.add{type="label", caption={"fp.pu_recipe", 1}, style="bold_label"}
    table.add{type="label", caption={"fp.current"}, style="bold_label"}
    table.add{type="label", caption={"fp.custom"}, style="bold_label"}

    for recipe_name in pairs(PRODUCTIVITY_RECIPES) do
        local recipe_proto = prototyper.util.find("recipes", recipe_name, nil)  --[[@as FPRecipePrototype]]
        local caption = (recipe_name == "custom-mining")
            and {"", "[img=utility/mining_drill_productivity_bonus_modifier_icon]  ", {"fp.mining_recipes"}}
            or {"", "[recipe=" .. recipe_name .. "]  ", recipe_proto.localised_name}
        table.add{type="label", caption=caption}.style.width = 250

        local productivity = util.get_recipe_productivity(player.force, recipe_name)
        local percentage = ("%+d"):format(math.floor((productivity * 100) + 0.5)) .. "%"
        table.add{type="label", caption=percentage}

        local current_bonus = current_factory.productivity_boni[recipe_name]
        local current_percentage = (current_bonus) and current_bonus * 100 or nil
        local textfield_bonus = table.add{type="textfield", text=current_percentage,
            tags={mod="fp", on_gui_text_changed="productivity_bonus", recipe_name=recipe_name}}
        util.gui.setup_numeric_textfield(textfield_bonus, false, false)
        textfield_bonus.style.width = 52
    end
end


local function handle_scope_change(player, tags, event)
    local utility_scope = (event.element.switch_state == "left") and "Factory" or "Floor"
    util.globals.preferences(player).utility_scopes[tags.utility_type] = utility_scope

    local modal_data = util.globals.modal_data(player)
    utility_structures.components(player, modal_data)
end

local function handle_item_request(player, _, _)
    local fly_text = util.cursor.create_flying_text

    if not player.force.character_logistic_requests then
        fly_text(player, {"fp.utility_logistics_not_researched"})
    elseif player.character == nil then  -- happens when the editor is active for example
        fly_text(player, {"fp.utility_logistics_no_character"})
    else
        local requester_point = player.character.get_requester_point()  -- will exist at this point
        local new_section = requester_point.add_section()

        local missing_items = util.globals.modal_data(player).missing_items
        for index, item in pairs(missing_items) do
            new_section.set_slot(index, {
                value = {
                    name = item.name,
                    quality = item.quality,
                    comparator = item.comparator
                },
                min = item.required_count
            })
        end

        fly_text(player, {"fp.utility_logistics_request_set"})
    end
end

local function handle_item_handcraft(player, tags, event)
    local fly_text = util.cursor.create_flying_text
    if not player.character then fly_text(player, {"fp.utility_crafting_no_character"}); return end

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
        local recipe_name = prototyper.util.find("recipes", recipe_id, nil).name
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


local function import_productivity_boni(player, _, event)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local selected_index = modal_data.modal_elements.factory_dropdown.selected_index
    local export_factory = OBJECT_INDEX[modal_data.factory_index[selected_index]]  --[[@as Factory]]
    if not export_factory then return end  -- dropdown starts blank

    local import_factory = util.context.get(player, "Factory")  --[[@as Factory]]
    import_factory.productivity_boni = ftable.deep_copy(export_factory.productivity_boni)

    utility_structures.productivity_boni(player, modal_data)
    modal_data.recalculate = true

    util.cursor.create_flying_text(player, {"fp.utility_productivity_imported"})
end


local function open_utility_dialog(player, modal_data)
    modal_data.utility_inventory = game.create_inventory(1)  -- used for blueprint decoding

    -- Left side
    utility_structures.components(player, modal_data)
    utility_structures.blueprints(player, modal_data)
    utility_structures.notes(player, modal_data)

    -- Right side
    utility_structures.productivity_boni(player, modal_data)
end

local function close_utility_dialog(player, _)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    if modal_data.recalculate then
        local factory = util.context.get(player, "Factory")  --[[@as Factory]]
        solver.update(player, factory)
        util.raise.refresh(player, "factory")
    end
    modal_data.utility_inventory.destroy()
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
                util.cursor.set_item_combinator(player, missing_items)
                util.raise.close_dialog(player, "cancel")
                main_dialog.toggle(player)
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
            actions_table = {
                pick_up = {shortcut="left", show=true},
                delete = {shortcut="control-right", show=true}
            },
            handler = handle_blueprint_click
        },
        {
            name = "import_productivity_boni",
            handler = import_productivity_boni
        }
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
        },
        {
            name = "productivity_bonus",
            handler = (function(player, tags, event)
                local factory = util.context.get(player, "Factory")  --[[@as Factory]]
                local bonus = tonumber(event.element.text)  -- nil if invalid or empty
                factory.productivity_boni[tags.recipe_name] = (bonus) and bonus / 100 or nil
                util.globals.modal_data(player).recalculate = true
            end)
        }
    }
}

listeners.dialog = {
    dialog = "utility",
    metadata = (function(_) return {
        caption = {"fp.utilities"},
        secondary_frame = true
    } end),
    open = open_utility_dialog,
    close = close_utility_dialog
}

listeners.misc = {
    on_player_main_inventory_changed = handle_inventory_change
}

return { listeners }
