-- NEW STUFF
data.raw["gui-style"].default["fp_scroll_pane_inside_content_frame"] = {
    type = "scroll_pane_style",
    extra_padding_when_activated = 0,
    padding = 0,
    graphical_set = {
      shadow = default_inner_shadow
    },
    vertical_flow_style = {
      type = "vertical_flow_style",
      padding = 12
    }
}

data.raw["gui-style"].default["fp_scroll_pane_inside_content_frame_bare"] = {
    type = "scroll_pane_style",
    parent = "fp_scroll_pane_inside_content_frame",
    vertical_flow_style = {
        type = "vertical_flow_style",
        padding = 0
    }
}


-- Intended for buttons of size 36
data.raw["gui-style"].default["fp_frame_deep_slots_small"] = {
    type = "frame_style",
    parent = "slot_button_deep_frame",
    background_graphical_set = {
        position = {282, 17},
        corner_size = 8,
        overall_tiling_vertical_size = 28,
        overall_tiling_vertical_spacing = 8,
        overall_tiling_vertical_padding = 4,
        overall_tiling_horizontal_size = 28,
        overall_tiling_horizontal_spacing = 8,
        overall_tiling_horizontal_padding = 4
    }
}

-- Intended for buttons of size 64hx73w
data.raw["gui-style"].default["fp_frame_deep_slots_crafting_groups"] = {
    type = "frame_style",
    parent = "slot_button_deep_frame", -- "crafting_frame"
    background_graphical_set = {
        position = {282, 17},
        corner_size = 8,
        overall_tiling_vertical_size = 46,
        overall_tiling_vertical_spacing = 18,
        overall_tiling_vertical_padding = 9,
        overall_tiling_horizontal_size = 53,
        overall_tiling_horizontal_spacing = 20,
        overall_tiling_horizontal_padding = 10
    }
}

data.raw["gui-style"].default["fp_frame_bordered_stretch"] = {
    type = "frame_style",
    parent = "bordered_frame",
    horizontally_stretchable = "on"
}


-- This style is hacked together from rounded-button and textbox
data.raw["gui-style"].default["fp_sprite-button_inset"] = {
    type = "button_style",
    parent = "icon_button",
    padding = 0,
    default_graphical_set = {
        base = {position = {248, 0}, corner_size = 8}
    },
    hovered_graphical_set = {
        base = {position = {219, 200}, corner_size = 8}
    },
    clicked_graphical_set = {
        base = {position = {265, 0}, corner_size = 8}
    },
    disabled_graphical_set = {
        base = {position = {185, 200}, corner_size = 8}
    }
}

data.raw["gui-style"].default["fp_sprite-button_inset_tiny"] = {
    type = "button_style",
    parent = "fp_sprite-button_inset",
    size = 32
}

-- Cribs from 'dark_rounded_button', but without the stupid shadows
data.raw["gui-style"].default["fp_sprite-button_rounded_dark"] = {
    type = "button_style",
    default_graphical_set = {base = {border = 4, position = {2, 738}, size = 76}},
    hovered_graphical_set =
    {
        base = {border = 4, position = {82, 738}, size = 76},
        glow = offset_by_2_rounded_corners_glow(default_glow_color)
    },
    clicked_graphical_set = {base = {border = 4, position = {162, 738}, size = 76}},
    disabled_graphical_set = {base = {border = 4, position = {2, 738}, size = 76}}
}



-- OLD STUFF
data.raw["gui-style"].default["fp_footer_filler"] = {
    type = "empty_widget_style",
    parent = "draggable_space",
    height = 32,
    left_margin = 0,
    right_margin = 0,
    horizontally_stretchable = "on"
}

data.raw["gui-style"].default["fp_button_titlebar"] = {
    type = "button_style",
    font = "fp-font-15p",
    height = 34
}

data.raw["gui-style"].default["fp_button_titlebar_square"] = {
    type = "button_style",
    parent = "fp_button_titlebar",
    width = 34,
    padding = 0
}

data.raw["gui-style"].default["fp_button_titlebar_square_selected"] = {
    type = "button_style",
    parent = "fp_button_selected",
    height = 34,
    width = 34,
    padding = 0
}

data.raw["gui-style"].default["fp_button_action"] = {
    type = "button_style",
    font = "fp-font-semibold-16p"
}

data.raw["gui-style"].default["fp_button_action_selected"] = {
    type = "button_style",
    parent = "fp_button_selected",
    font = "fp-font-semibold-16p"
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
    minimal_width = 0,
    padding = 0
}

data.raw["gui-style"].default["fp_subfactory_sprite_button"] = {
    type = "button_style",
    parent = "fp_sprite_button",
    height = 38,
    clicked_vertical_offset = 0
}

data.raw["gui-style"].default["fp_subfactory_sprite_button_selected"] = {
    type = "button_style",
    parent = "fp_subfactory_sprite_button",
    default_graphical_set = {
        base = {position = {51, 17}, corner_size = 8},
        --shadow = default_dirt
    },
    hovered_graphical_set = {
        base = {position = {51, 17}, corner_size = 8},
        --shadow = default_dirt
    }
}

data.raw["gui-style"].default["fp_button_selected"] = {
    type = "button_style",
    parent = "button",
    default_graphical_set = {
        base = {position = {51, 17}, corner_size = 8},
        --shadow = default_dirt
    },
    hovered_graphical_set = {
        base = {position = {51, 17}, corner_size = 8},
        --shadow = default_dirt
    }
}

data.raw["gui-style"].default["fp_button_timescale"] = {
    type = "button_style",
    parent = "button",
    height = 26,
    width = 40,
    left_padding = 0,
    right_padding = 0,
    top_padding = 1,
    clicked_vertical_offset = 0
}

data.raw["gui-style"].default["fp_button_timescale_selected"] = {
    type = "button_style",
    parent = "fp_button_timescale",
    disabled_font_color = {},  -- pure black
    disabled_graphical_set = {
        base = {position = {51, 17}, corner_size = 8},
        --shadow = default_dirt
    }
}

data.raw["gui-style"].default["fp_view_selection_button"] = {
    type = "button_style",
    parent = "button",
    width = 100,
    clicked_vertical_offset = 0
}

data.raw["gui-style"].default["fp_view_selection_button_selected"] = {
    type = "button_style",
    parent = "fp_view_selection_button",
    disabled_font_color = {},  -- pure black
    disabled_graphical_set = {
        base = {position = {51, 17}, corner_size = 8},
        --shadow = default_dirt
    }
}


data.raw["gui-style"].default["fp_scroll_pane_items"] = {
    type = "scroll_pane_style",
    graphical_set = {},
    extra_padding_when_activated = 0,
    maximal_height = 124,
    left_margin = 12,
    right_padding = 12
}

data.raw["gui-style"].default["fp_preferences_title_label"] = {
    type = "label_style",
    font = "fp-font-bold-15p"
}

data.raw["gui-style"].default["fp_sprite-button_inset_line"] = {
    type = "button_style",
    parent = "fp_sprite-button_inset",
    height = 32,
    width = 32,
    padding = 2
}

data.raw["gui-style"].default["fp_sprite-button_choose_elem"] = {
    type = "button_style",
    parent = "fp_sprite-button_inset",
    height = 30,
    width = 30,
    padding = 0
}

data.raw["gui-style"].default["fp_sprite-button_tool_green"] = {
    type = "button_style",
    parent = "item_and_count_select_confirm",
    padding = 2,
    left_click_sound = {{ filename = "__core__/sound/gui-click.ogg", volume = 1 }}
}

data.raw["gui-style"].default["fp_table_subgroup"] = {
    type = "table_style",
    horizontal_spacing = 2,
    vertical_spacing = 1
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
        },
        -- The disabled set is the same as the default one, by default
        disabled_graphical_set =
        {
            filename = "__factoryplanner__/graphics/icon_backgrounds.png",
            priority = "extra-high-no-scale",
            position = {0, y},
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
local icons_medium = {"default", "recipe", "disabled", "hidden", "cyan", "red", "yellow", "green", "blank"}
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
    disabled_graphical_set =
    {
        filename = "__factoryplanner__/graphics/icon_backgrounds.png",
        priority = "extra-high-no-scale",
        position = {74, 0},
        size = 36,
        border = 1,
        scale = 1
    }
}

-- Specific style for an already existing product button
data.raw["gui-style"].default["fp_button_existing_product"] = {
    type = "button_style",
    parent = "icon_button",
    size = 32,
    padding = 0,
    disabled_graphical_set =
    {
        filename = "__factoryplanner__/graphics/icon_backgrounds.png",
        priority = "extra-high-no-scale",
        position = {0, 36},
        size = 36,
        border = 1,
        scale = 1
    }
}

--data.raw["gui-style"].default["crafting_queue_slot"].size = 24
--data.raw["gui-style"].default["slot_button"].size = 24