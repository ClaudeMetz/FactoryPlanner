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


data.raw["gui-style"].default["fp_button_icon_red"] = {
    type = "button_style",
    parent = "fp_button_icon",
    default_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 111,
          y = 180
        }
    },
    hovered_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 148,
          y = 180
        }
    },
    clicked_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 185,
          y = 180
        }
    }
}

data.raw["gui-style"].default["fp_button_icon_yellow"] = {
    type = "button_style",
    parent = "fp_button_icon",
    default_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 111,
          y = 216
        }
    },
    hovered_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 148,
          y = 216
        }
    },
    clicked_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 185,
          y = 216
        }
    }
}

data.raw["gui-style"].default["fp_button_icon_green"] = {
    type = "button_style",
    parent = "fp_button_icon",
    default_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 111,
          y = 252
        }
    },
    hovered_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 148,
          y = 252
        }
    },
    clicked_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__core__/graphics/gui.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 185,
          y = 252
        }
    }
}

data.raw["gui-style"].default["fp_button_icon_cyan"] = {
    type = "button_style",
    parent = "fp_button_icon",
    padding = 3,
    width = 36,
    height = 36,
    default_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__FactoryPlanner__/graphics/icons/gui_cyan.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 0,
          y = 0
        }
    },
    hovered_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__FactoryPlanner__/graphics/icons/gui_cyan.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 37,
          y = 0
        }
    },
    clicked_graphical_set =
      {
        type = "monolith",
        monolith_border = 1,
        monolith_image =
        {
          filename = "__FactoryPlanner__/graphics/icons/gui_cyan.png",
          priority = "extra-high-no-scale",
          width = 36,
          height = 36,
          x = 74,
          y = 0
        }
    }
}
