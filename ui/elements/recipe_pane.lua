-- Creates the recipe pane that includes the products, byproducts and ingredients
function add_recipe_pane_to(main_dialog, player)
    main_dialog.add{type="table", name="table_recipe_pane", direction="horizontal", column_count = 4}
    refresh_recipe_pane(player)
end


-- Refreshes the recipe pane by reloading the data
function refresh_recipe_pane(player)
    local table_recipe =  player.gui.center["main_dialog"]["table_recipe_pane"]
    -- Cuts function short if the recipe pane hasn't been initialized yet
    if not table_recipe then return end

    table_recipe.style.horizontally_stretchable = true
    table_recipe.draw_vertical_lines = true
    table_recipe.clear()

    local selected_subfactory_id = global["selected_subfactory_id"]
    -- selected_subfactory_id is always 0 when there are no subfactories
    if selected_subfactory_id ~= 0 then
        -- Info cell
        local flow_info = create_recipe_pane_cell(table_recipe, "info")
        refresh_info_pane(player)
        
        -- Ingredients cell
        create_recipe_pane_cell(table_recipe, "ingredients")

        -- Products cell
        local flow_recipe = create_recipe_pane_cell(table_recipe, "products")
        local products = get_products(selected_subfactory_id)
        create_product_buttons(flow_recipe, products)

        -- Byproducts cell
        create_recipe_pane_cell(table_recipe, "byproducts")

    end
end


-- Constructs the basic structure of a recipe_pane-cell
function create_recipe_pane_cell(table, kind)
    local width = global["main_dialog_dimensions"].width / 4 - 6
    local flow = table.add{type="flow", name="flow_" .. kind, direction="vertical"}
    flow.style.width = width
    local label_title = flow.add{type="label", name="label_" .. kind .. "_title", caption={"", "  ", {"label." ..kind}}}
    label_title.style.font = "fp-button-standard"

    return flow
end


-- Constructs the info pane including timescale settings
function refresh_info_pane(player)
    local flow = player.gui.center["main_dialog"]["table_recipe_pane"]["flow_info"]
    if not flow["flow_info_list"] then
        flow.add{type="flow", name="flow_info_list", direction="vertical"}
    else
        flow["flow_info_list"].clear()
    end

    local timescale = get_subfactory_timescale(global["selected_subfactory_id"])
    local unit = determine_unit(timescale)
    local table_timescale = flow["flow_info_list"].add{type="table", name="table_timescale_buttons", column_count=4}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", " ", {"label.timescale"}, ": "}}
    label_timescale_title.style.top_padding = 1
    label_timescale_title.style.font = "fp-label-large"

    if global["currently_changing_timescale"] then
        table_timescale.add{type="button", name="button_timescale_1", caption="1s", style="fp_button_speed_selection"}
        table_timescale.add{type="button", name="button_timescale_60", caption="1m", style="fp_button_speed_selection"}
        table_timescale.add{type="button", name="button_timescale_3600", caption="1h", style="fp_button_speed_selection"}
    else            
        -- As unit is limited to presets, timescale will always be displayed as 1
        local label_timescale = table_timescale.add{type="label", name="label_timescale", caption="1" .. unit .. "   "}
        label_timescale.style.top_padding = 1
        label_timescale.style.font = "default-bold"
        table_timescale.add{type="button", name="button_change_timescale", caption={"button-text.change"},
          style="fp_button_speed_selection"}
    end

    local table_power_usage = flow["flow_info_list"].add{type="table", name="table_power_usage", column_count=2}
    table_power_usage.add{type="label", name="label_power_usage_title", caption={"", " ",  {"label.power_usage"}, ": "}}
    table_power_usage["label_power_usage_title"].style.font = "fp-label-large"
    local power_usage = "14.7 MW"  -- Placeholder until a later implementation
    table_power_usage.add{type="label", name="label_power_usage", caption=power_usage .. "/" .. unit}
    table_power_usage["label_power_usage"].style.font = "default-bold"
end


-- Handles the timescale changing process
function change_subfactory_timescale(player, timescale)
    set_subfactory_timescale(global["selected_subfactory_id"], timescale)
    global["currently_changing_timescale"] = false
    refresh_info_pane(player)
end


-- Constructs the table containing all product buttons
function create_product_buttons(flow, items)
    local table = flow.add{type="table", name="table_products", column_count = 6}
    table.style.left_padding = 10
    table.style.horizontal_spacing = 10

    if #items ~= 0 then
        for id, product in ipairs(items) do
            local button = table.add{type="sprite-button", name="sprite-button_product_" .. id, 
                sprite="item/" .. product.name, number=product.amount_required}

            button.tooltip = {"", game.item_prototypes[product.name].localised_name, "\n",
              product.amount_produced, " / ", product.amount_required}

            if product.amount_produced == 0 then
                button.style = "fp_button_icon_red"
            elseif product.amount_produced < product.amount_required then
                button.style = "fp_button_icon_yellow"
            elseif product.amount_produced == product.amount_required then
                button.style = "fp_button_icon_green"
            else
                button.style = "fp_button_icon_cyan"
            end
        end
    end

    local button = table.add{type="button", name="sprite-button_add_product", caption="+"}
    button.style.height = 36
    button.style.width = 36
    button.style.top_padding = 0
    button.style.font = "fp-button-large"
end


-- Handles populating the modal dialog to add or edit products
function open_product_dialog(flow_modal_dialog, args)
    if args.edit then
        global["currently_editing_product_id"] = args.product_id
        create_product_dialog_structure(flow_modal_dialog, {"label.edit_product"}, args.product_id)
    else
        create_product_dialog_structure(flow_modal_dialog, {"label.add_product"}, nil)
    end
end

-- Handles submission of the product dialog
function submit_product_dialog(flow_modal_dialog, data)
    currently_editing_product_id = global["currently_editing_product_id"]
    if currently_editing_product_id ~= nil then
        set_product_amount_required(global["selected_subfactory_id"], currently_editing_product_id, data.amount_required)
        global["currently_editing_product_id"] = nil
    else
        add_product(global["selected_subfactory_id"], data.product_name, data.amount_required)
    end
end

-- Checks the entered data for errors and returns it if it's all correct, else returns nil
function check_product_data(flow_modal_dialog)
    local product = flow_modal_dialog["table_product"]["choose-elem-button_product"].elem_value
    local amount = flow_modal_dialog["table_product"]["textfield_product_amount"].text
    local label_product = flow_modal_dialog["table_product"]["label_product"]
    local label_amount = flow_modal_dialog["table_product"]["label_product_amount"]

    -- Resets all error indicators
    set_label_color(label_product, "white")
    set_label_color(label_amount, "white")
    local error_present = false

    if product == nil then
        set_label_color(label_product, "red")
        error_present = true
    end

    -- Matches everything that is not numeric
    if amount == "" or amount:match("[^%d]") or tonumber(amount) <= 0 then
        set_label_color(label_amount, "red")
        error_present = true
    end

    if error_present then
        return nil
    else
        return {product_name=product, amount_required=tonumber(amount)}
    end
end

-- Fills out the modal dialog to add a product
function create_product_dialog_structure(flow_modal_dialog, title, product_id)
    flow_modal_dialog.parent.caption = title

    local product
    if product_id ~= nil then
        product = get_product(global["selected_subfactory_id"], product_id)

        -- Delete
        local button_delete = flow_modal_dialog.add{type="button", name="button_delete_product",
        caption={"button-text.delete"}, style="fp_button_action"}
        set_label_color(button_delete, "red")
    else
        product = {name=nil, amount_required=""}
    end

    local table_product = flow_modal_dialog.add{type="table", name="table_product", column_count=2}
    table_product.style.top_padding = 5
    table_product.style.bottom_padding = 8
    -- Product
    table_product.add{type="label", name="label_product", caption={"label.product"}}
    table_product.add{type="choose-elem-button", name="choose-elem-button_product", elem_type="item", item=product.name}
    if product_id ~= nil then table_product["choose-elem-button_product"].locked = true end

    -- Amount
    table_product.add{type="label", name="label_product_amount", caption={"", {"label.amount"}, "    "}}
    local textfield_product = table_product.add{type="textfield", name="textfield_product_amount", text=product.amount_required}
    textfield_product.style.width = 80
    textfield_product.focus()
end

-- Handles the product deletion process
-- (a bit of misuse of exit_modal_dialog(), but it fits the need)
function handle_product_deletion(player)
    delete_product(global["selected_subfactory_id"], global["currently_editing_product_id"])
    global["currently_editing_product_id"] = nil
    exit_modal_dialog(player, false)
    refresh_main_dialog(player)
end


-- Handles populating the recipe dialog
function open_recipe_dialog(flow_modal_dialog, args)
    local product_name = get_product(global["selected_subfactory_id"], args.product_id).name
    create_recipe_dialog_structure(flow_modal_dialog, {"label.add_recipe"}, product_name)
    local player = game.players[flow_modal_dialog.player_index]
    apply_recipe_filter(player)
end

-- Cleans up when the modal dialog is cancelled
function cleanup_recipe_dialog()
    global["selected_item_group_name"] = nil
end

-- Fills out the modal dialog to choose a recipe
function create_recipe_dialog_structure(flow_modal_dialog, title, search_term)
    flow_modal_dialog.parent.caption = title

    local undesirables = undesirable_recipes()

    -- Filter conditions
    local table_filter_conditions = flow_modal_dialog.add{type="table", name="table_filter_conditions", column_count = 3}
    table_filter_conditions.style.bottom_padding = 6
    table_filter_conditions.style.horizontal_spacing = 8
    table_filter_conditions.add{type="label", name="label_filter_conditions", caption={"label.show"}}
    table_filter_conditions.add{type="checkbox", name="checkbox_filter_condition_enabled", 
      caption={"checkbox.unresearched_recipes"}, state=false}
    table_filter_conditions.add{type="checkbox", name="checkbox_filter_condition_hidden", 
      caption={"checkbox.hidden_recipes"}, state=false}

    table_filter_conditions.add{type="label", name="label_search_recipe", caption={"label.search"}}
    table_filter_conditions.add{type="textfield", name="textfield_search_recipe", text=search_term}
    table_filter_conditions["textfield_search_recipe"].focus()
    
    local sprite_button_search = table_filter_conditions.add{type="sprite-button", 
      name="sprite-button_search_recipe", sprite="utility/go_to_arrow"}
    sprite_button_search.style.height = 25
    sprite_button_search.style.width = 36

    local table_item_groups = flow_modal_dialog.add{type="table", name="table_item_groups", column_count=6}
    table_item_groups.style.horizontal_spacing = 3
    table_item_groups.style.vertical_spacing = 3
    table_item_groups.style.width = 6 * (64 + 1)
    local formatted_recipes = format_recipes_for_display(game.players[flow_modal_dialog.player_index])
    local scroll_pane_height = 0
    for _, group in ipairs(formatted_recipes) do
        -- Item groups
        button_group = table_item_groups.add{type="sprite-button", name="sprite-button_item_group_" .. group.name,
          sprite="item-group/" .. group.name, style="fp_button_icon_item_group"}
        button_group.style.width = 64
        button_group.style.height = 64

        local scroll_pane_subgroups = flow_modal_dialog.add{type="scroll-pane", name="scroll-pane_subgroups_" .. group.name}
        scroll_pane_subgroups.style.bottom_padding = 6
        scroll_pane_subgroups.style.horizontally_stretchable = true
        scroll_pane_subgroups.style.visible = false
        local specific_scroll_pane_height = -20  -- offsets the height-increase on the last row which is superfluous
        local table_subgroup = scroll_pane_subgroups.add{type="table", name="table_subgroup", column_count=1}
        table_subgroup.style.vertical_spacing = 4
        for _, subgroup in ipairs(group.subgroups) do
            -- Item subgroups
            local table_subgroup = table_subgroup.add{type="table", name="table_subgroup_" .. subgroup.name,
              column_count = 12}
            table_subgroup.style.horizontal_spacing = 2
            table_subgroup.style.vertical_spacing = 2
            for _, recipe in ipairs(subgroup.recipes) do
                if undesirables[recipe.name] ~= false and recipe.category ~= "handcrafting" then
                    -- Recipes
                    local button_recipe = table_subgroup.add{type="sprite-button", name="sprite-button_recipe_" .. recipe.name,
                      sprite="recipe/" .. recipe.name, style="fp_button_icon_recipe"}
                    if recipe.hidden then button_recipe.style = "fp_button_icon_recipe_hidden" end
                    if not recipe.enabled then button_recipe.style = "fp_button_icon_recipe_disabled" end
                    button_recipe.tooltip = generate_recipe_tooltip(recipe)
                    button_recipe.style.visible = false
                    if (#table_subgroup.children_names - 1) % 12 == 0 then  -- new row
                        specific_scroll_pane_height = specific_scroll_pane_height + (28+2)
                    end
                end
            end
            specific_scroll_pane_height = specific_scroll_pane_height + 4  -- new subgroup
        end
        scroll_pane_height = math.max(scroll_pane_height, specific_scroll_pane_height)
    end
    -- Set scroll-pane height to be the same for all item groups
    for _, child in ipairs(flow_modal_dialog.children_names) do
        if string.find(child, "^scroll%-pane_subgroups_[a-z-]+$") then
            flow_modal_dialog[child].style.height = math.min(scroll_pane_height, 650)
        end
    end
end

-- Separate function that extracts, formats and sorts all recipes so they can be displayed
-- (kinda crazy way to do all this, but not sure how so sort them otherwise)
function format_recipes_for_display(player)
    local recipes = player.force.recipes

    -- First, categrorize the recipes according to the order of their group, subgroup and themselves
    local unsorted_recipe_tree = {}
    for _, recipe in pairs(recipes) do
        if unsorted_recipe_tree[recipe.group.order] == nil then
            unsorted_recipe_tree[recipe.group.order] = {}
        end
        local group = unsorted_recipe_tree[recipe.group.order]
        if group[recipe.subgroup.order] == nil then
            group[recipe.subgroup.order] = {}
        end
        local subgroup = group[recipe.subgroup.order]
        if subgroup[recipe.order] == nil then
            subgroup[recipe.order] = {}
        end
        table.insert(subgroup[recipe.order], recipe)
    end

    -- Then, sort them according to the orders into a new array
    -- Messy tree structure, but avoids modded situations where multiple recipes have the same order
    local sorted_recipe_tree = {}
    local group_name, subgroup_name
    for _, group in pairsByKeys(unsorted_recipe_tree) do
        table.insert(sorted_recipe_tree, {name=nil, subgroups={}})
        local table_group = sorted_recipe_tree[#sorted_recipe_tree]
        for _, subgroup in pairsByKeys(group) do
            table.insert(table_group.subgroups, {name=nil, recipes={}})
            local table_subgroup = table_group.subgroups[#table_group.subgroups]
            for _, recipe_order in pairsByKeys(subgroup) do
                for _, recipe in ipairs(recipe_order) do
                    if not group_name then group_name = recipe.group.name end
                    if not subgroup_name then subgroup_name = recipe.subgroup.name end
                    table.insert(table_subgroup.recipes, recipe)
                end
            end
            table_subgroup.name = subgroup_name
            subgroup_name = nil
        end
        table_group.name = group_name
        group_name = nil
    end

    return sorted_recipe_tree
end

-- Returns the names of the recipes that shouldn't be included
function undesirable_recipes()
    local undesirables = 
    {
        ["small-plane"] = false,
        ["electric-energy-interface"] = false,
        ["railgun"] = false,
        ["railgun-dart"] = false,
        ["player-port"] = false
    }

    -- Leaves loaders in if LoaderRedux is loaded
    if game.active_mods["LoaderRedux"] == nil then
        undesirables["loader"] = false
        undesirables["fast-loader"] = false
        undesirables["express-loader"] = false
    end

    return undesirables
end

-- Changes the selected item group to the specified one
function change_item_group_selection(player, item_group_name)
    local flow_modal_dialog = player.gui.center["frame_modal_dialog"]["flow_modal_dialog"]
    -- First, change the currently selected one back to normal, if it exists
    if global["selected_item_group_name"] ~= nil then
        local sprite_button = flow_modal_dialog["table_item_groups"]
          ["sprite-button_item_group_" .. global["selected_item_group_name"]]
        if sprite_button ~= nil then
            sprite_button.style = "fp_button_icon_item_group"
            sprite_button.ignored_by_interaction = false
            flow_modal_dialog["scroll-pane_subgroups_" .. global["selected_item_group_name"]].style.visible = false
        end
    end
    -- Then, change the clicked one to the selected status
    global["selected_item_group_name"] = item_group_name
    local sprite_button = flow_modal_dialog["table_item_groups"]["sprite-button_item_group_" .. item_group_name]
    sprite_button.style = "fp_button_icon_clicked"
    sprite_button.ignored_by_interaction = true
    flow_modal_dialog["scroll-pane_subgroups_" .. item_group_name].style.visible = true
end

-- Filters the recipes according to their enabled/hidden-attribute and the search-term
function apply_recipe_filter(player)
    local flow_modal_dialog = player.gui.center["frame_modal_dialog"]["flow_modal_dialog"]
    local unenabled = flow_modal_dialog["table_filter_conditions"]["checkbox_filter_condition_enabled"].state
    local hidden = flow_modal_dialog["table_filter_conditions"]["checkbox_filter_condition_hidden"].state
    local search_term =  flow_modal_dialog["table_filter_conditions"]["textfield_search_recipe"].text:gsub("%s+", "")
    local recipes = player.force.recipes

    local first_visible_group = nil
    for _, group_element in pairs(flow_modal_dialog["table_item_groups"].children) do
        local group_name = string.gsub(group_element.name, "sprite%-button_item_group_", "")
        local group_visible = false
        for _, subgroup_element in pairs(flow_modal_dialog["scroll-pane_subgroups_".. group_name]["table_subgroup"].children) do
            local subgroup_visible = false
            for _, recipe_element in pairs(subgroup_element.children) do
                local recipe_name = string.gsub(recipe_element.name, "sprite%-button_recipe_", "")
                local recipe = recipes[recipe_name]
                local visible = true
                if (not unenabled) and (not recipe.enabled) then
                    visible = false
                end
                if (not hidden) and recipe.hidden then
                    visible = false
                end
                if not recipe_produces_product(recipe, search_term) then
                    visible = false
                end
                if visible == true then 
                    subgroup_visible = true 
                    group_visible = true
                end
                recipe_element.style.visible = visible
            end
            subgroup_element.style.visible = subgroup_visible
        end
        group_element.style.visible = group_visible
        if first_visible_group == nil and group_visible then 
            first_visible_group = group_name 
        end
    end
    if first_visible_group ~= nil then
        local selected_group = global["selected_item_group_name"]
        if selected_group == nil or flow_modal_dialog["table_item_groups"]["sprite-button_item_group_" ..
         selected_group].style.visible == false then
            change_item_group_selection(player, first_visible_group)
        end
    end
end

-- Returns a formatted tooltip string for the given recipe
function generate_recipe_tooltip(recipe)
    local prototypes = {[1] = game.item_prototypes, [2] = game.fluid_prototypes}
    local tooltip = {"", recipe.localised_name, "\n  ", {"tooltip.crafting_time"}, ":  ", recipe.energy,}

    local lists = {"ingredients", "products"}
    for _, item_type in ipairs(lists) do
        tooltip = {"", tooltip, "\n  ", {"tooltip." .. item_type}, ":"}
        local t
        for _, item in ipairs(recipe[item_type]) do
            if item.type == "item" then t = 1 else t = 2 end
            tooltip = {"", tooltip, "\n    ", item.amount, "x ", prototypes[t][item.name].localised_name}
        end
    end

    return tooltip
end

-- Checks whether given recipe produces given product
function recipe_produces_product(recipe, product_name)
    if product_name == "" then return true end
    for _, product in ipairs(recipe.products) do
        if product.name == product_name then
            return true
        end
    end
    return false
end