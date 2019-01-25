data.raw["gui-style"].default["fp_button_exit"] = {
    type = "button_style",
    font = "default-listbox",
    height = 30,
    width = 30,
    top_padding = 2,
    left_padding = 6
}

data.raw["gui-style"].default["fp_button_with_spacing"] = {
    type = "button_style",
    left_padding = 12,
    right_padding = 12
}

data.raw["gui-style"].default["fp_button_action"] = {
    type = "button_style",
    parent = "fp_button_with_spacing",
    font = "fp-button-standard",
    height = 29,
    top_padding = 1
}

data.raw["gui-style"].default["fp_button_speed_selection"] = {
    type = "button_style",
    font = "default",
    height = 26,
    top_padding = 0
}


data.raw["gui-style"].default["fp_button_icon"] = {
    type = "button_style",
    parent = "icon_button",
    padding = 3,
    width = 36,
    height = 36,
}

-- Generating styles for the different icon-buttons
local icon_state_indexes = {item_group = 0, disabled = 36, hidden = 72, red = 108, yellow = 144, green = 180, cyan = 216, blank = 252}
for state, y in pairs(icon_state_indexes) do
    data.raw["gui-style"].default["fp_button_icon_" .. state] = {
        type = "button_style",
        parent = "fp_button_icon",
        default_graphical_set =
        {
            type = "monolith",
            monolith_border = 1,
            monolith_image =
            {
                filename = "__FactoryPlanner__/graphics/icons/icon_backgrounds.png",
                priority = "extra-high-no-scale",
                width = 36,
                height = 36,
                x = 0,
                y = y
            }
        },
        hovered_graphical_set =
        {
            type = "monolith",
            monolith_border = 1,
            monolith_image =
            {
                filename = "__FactoryPlanner__/graphics/icons/icon_backgrounds.png",
                priority = "extra-high-no-scale",
                width = 36,
                height = 36,
                x = 37,
                y = y
            }
        },
        clicked_graphical_set =
        {
            type = "monolith",
            monolith_border = 1,
            monolith_image =
            {
                filename = "__FactoryPlanner__/graphics/icons/icon_backgrounds.png",
                priority = "extra-high-no-scale",
                width = 36,
                height = 36,
                x = 74,
                y = y
            }
        }
    }
end

-- Specific style for a clicked item_group sprite button
data.raw["gui-style"].default["fp_button_icon_clicked"] = {
    type = "button_style",
    parent = "fp_button_icon",
    default_graphical_set =
    {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
            filename = "__FactoryPlanner__/graphics/icons/icon_backgrounds.png",
            priority = "extra-high-no-scale",
            width = 36,
            height = 36,
            x = 74,
            y = 0
        }
    }
}

data.raw["gui-style"].default["fp_button_icon_recipe"] = {
    type = "button_style",
    parent = "fp_button_icon_item_group",
    padding = 1,
    width = 28,
    height = 28,
}

data.raw["gui-style"].default["fp_button_icon_recipe_disabled"] = {
    type = "button_style",
    parent = "fp_button_icon_disabled",
    padding = 1,
    width = 28,
    height = 28,
}

data.raw["gui-style"].default["fp_button_icon_recipe_hidden"] = {
    type = "button_style",
    parent = "fp_button_icon_hidden",
    padding = 1,
    width = 28,
    height = 28,
}