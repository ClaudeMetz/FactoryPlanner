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

data.raw["gui-style"].default["trans-image-button-style"] = {
    type = "button_style",
    parent = "icon_button",
	default_graphical_set = {
		type = "monolith",
		monolith_image = {
            filename = "__FactoryPlanner__/graphics/icons/blank.png",
            width = 32,
	        height = 32,
		}
    }
}