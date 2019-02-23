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
    font = "fp-font-16p",
    height = 29,
    top_padding = 1
}

data.raw["gui-style"].default["fp_button_mini"] = {
    type = "button_style",
    font = "default",
    height = 26,
    top_padding = 0
}

-- Generating prototype styles for the different icon-buttons
local icon_state_indexes = {recipe = 0, disabled = 36, hidden = 72, red = 108, yellow = 144, green = 180, cyan = 216, blank = 252}
for state, y in pairs(icon_state_indexes) do
    data.raw["gui-style"].default["fp_button_icon_" .. state .. "_prototype"] = {
        type = "button_style",
        parent = "icon_button",
        default_graphical_set =
        {
            type = "monolith",
            monolith_border = 1,
            monolith_image =
            {
                filename = "__factoryplanner__/graphics/icon_backgrounds.png",
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
                filename = "__factoryplanner__/graphics/icon_backgrounds.png",
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
                filename = "__factoryplanner__/graphics/icon_backgrounds.png",
                priority = "extra-high-no-scale",
                width = 36,
                height = 36,
                x = 74,
                y = y
            }
        }
    }
end

-- Generates all large-sized sprite-button styles
local icons_large = {"red", "yellow", "green", "cyan", "blank"}
for _, type in ipairs(icons_large) do
    data.raw["gui-style"].default["fp_button_icon_large_" .. type] = {
        type = "button_style",
        parent = "fp_button_icon_" .. type .. "_prototype",
        padding = 2,
        width = 36,
        height = 36,
    }
end

-- Generates all medium-sized sprite-button styles
local icons_medium = {"green", "blank"}
for _, type in ipairs(icons_medium) do
    data.raw["gui-style"].default["fp_button_icon_medium_" .. type] = {
        type = "button_style",
        parent = "fp_button_icon_" .. type .. "_prototype",
        padding = 1,
        width = 32,
        height = 32,
    }
end

-- Generates all small-sized sprite-button styles
local icons_small = {"recipe", "disabled", "hidden"}
for _, type in ipairs(icons_small) do
    data.raw["gui-style"].default["fp_button_icon_small_" .. type] = {
        type = "button_style",
        parent = "fp_button_icon_" .. type .. "_prototype",
        padding = 1,
        width = 28,
        height = 28,
    }
end

-- Specific style for a clicked item_group sprite button
data.raw["gui-style"].default["fp_button_icon_clicked"] = {
    type = "button_style",
    parent = "fp_button_icon_small_recipe",
    default_graphical_set =
    {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
            filename = "__factoryplanner__/graphics/icon_backgrounds.png",
            priority = "extra-high-no-scale",
            width = 36,
            height = 36,
            x = 74,
            y = 0
        }
    }
}