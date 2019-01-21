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
local icon_color_indexes = {red = 0, yellow = 36, green = 72, cyan = 108}
for color, y in pairs(icon_color_indexes) do
    data.raw["gui-style"].default["fp_button_icon_" .. color] = {
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