data.raw["gui-style"]["default"]["fp_footer_filler"] = {
    type = "frame_style",
    height = 32,
    graphical_set = data.raw["gui-style"]["default"]["draggable_space"].graphical_set,
    use_header_filler = false,
    horizontally_stretchable = "on"
    --left_margin = data.raw["gui-style"]["default"]["draggable_space"].left_margin,
    --right_margin = data.raw["gui-style"]["default"]["draggable_space"].right_margin,
}

data.raw["gui-style"].default["fp_button_titlebar"] = {
    type = "button_style",
    font = "fp-font-15p",
    height = 34
}

data.raw["gui-style"].default["fp_button_action"] = {
    type = "button_style",
    font = "fp-font-16p"
}

data.raw["gui-style"].default["fp_button_mini"] = {
    type = "button_style",
    parent = "rounded_button",
    height = 26,
    minimal_width = 0,
    left_padding = 4,
    right_padding = 4
}

data.raw["gui-style"].default["fp_sprite_button"] = {
    type = "button_style",
    parent = "button",
    padding = 0
}

data.raw["gui-style"].default["fp_subfactory_sprite_button"] = {
    type = "button_style",
    parent = "fp_sprite_button",
    height = 38
}

data.raw["gui-style"].default["fp_subfactory_sprite_button_selected"] = {
    type = "button_style",
    parent = "fp_button_icon_large_blank",
    height = 38,
    minimal_width = 0
}

data.raw["gui-style"].default["fp_scroll_pane_items"] = {
    type = "scroll_pane_style",
    graphical_set = {},
    extra_padding_when_activated = 0,
    maximal_height = 124,
    left_margin = 12,
    right_padding = 12
}


-- Generating prototype styles for the different icon-buttons
local icon_state_indexes = {recipe = 0, disabled = 36, hidden = 72, red = 108, yellow = 144, green = 180, cyan = 216, blank = 252}
for state, y in pairs(icon_state_indexes) do
    data.raw["gui-style"].default["fp_button_icon_" .. state .. "_prototype"] = {
        type = "button_style",
        parent = "icon_button",
        default_graphical_set =
        {
            filename = "__factoryplanner__/graphics/icon_backgrounds.png",
            priority = "extra-high-no-scale",
            position = {0, y},
            size = 36,
            border = 1,
            scale = 1
        },
        hovered_graphical_set =
        {
            filename = "__factoryplanner__/graphics/icon_backgrounds.png",
            priority = "extra-high-no-scale",
            position = {37, y},
            size = 36,
            border = 1,
            scale = 1
        },
        clicked_graphical_set =
        {
            filename = "__factoryplanner__/graphics/icon_backgrounds.png",
            priority = "extra-high-no-scale",
            position = {74, y},
            size = 36,
            border = 1,
            scale = 1
        }
    }
end

data.raw["gui-style"].default["fp_button_icon_default_prototype"] = {
    type = "button_style",
    parent = "icon_button",
}

-- Generates all large-sized sprite-button styles
local icons_large = {"recipe", "red", "yellow", "green", "cyan", "blank"}
for _, type in ipairs(icons_large) do
    data.raw["gui-style"].default["fp_button_icon_large_" .. type] = {
        type = "button_style",
        parent = "fp_button_icon_" .. type .. "_prototype",
        size = 36,
    }
end

-- Generates all medium-sized sprite-button styles
local icons_medium = {"default", "recipe", "disabled", "hidden", "red", "green", "blank"}
for _, type in ipairs(icons_medium) do
    data.raw["gui-style"].default["fp_button_icon_medium_" .. type] = {
        type = "button_style",
        parent = "fp_button_icon_" .. type .. "_prototype",
        size = 32
    }
end

-- Specific style for a clicked item_group sprite button
data.raw["gui-style"].default["fp_button_icon_clicked"] = {
    type = "button_style",
    parent = "fp_button_icon_medium_recipe",
    default_graphical_set =
    {
        filename = "__factoryplanner__/graphics/icon_backgrounds.png",
        priority = "extra-high-no-scale",
        position = {74, 0},
        size = 36,
        border = 1,
        scale = 1
    },
    hovered_graphical_set =
    {
        filename = "__factoryplanner__/graphics/icon_backgrounds.png",
        priority = "extra-high-no-scale",
        position = {74, 0},
        size = 36,
        border = 1,
        scale = 1
    },
    clicked_graphical_set =
    {
        filename = "__factoryplanner__/graphics/icon_backgrounds.png",
        priority = "extra-high-no-scale",
        position = {74, 0},
        size = 36,
        border = 1,
        scale = 1
    }
}