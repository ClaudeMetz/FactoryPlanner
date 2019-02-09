BaseClass = {}
BaseClass.__index = BaseClass


function BaseClass:_init(name)
    self.name = name
    self.valid = true
    self.gui_position = nil
end


function BaseClass:set_name(name)
    self.name = name
end

function BaseClass:get_name()
    return self.name
end


function BaseClass:is_valid()
    return self.valid
end

function BaseClass:check_validity()
    self.valid = (game.item_prototypes[self.name] or game.fluid_prototypes[self.name])
    return self.valid
end


function BaseClass:set_gui_position(gui_position)
    self.gui_position = gui_position
end

function BaseClass:get_gui_position()
    return self.gui_position
end


-- Require-statements at the end so BaseClass is available for inheritance
require("Factory")
require("Subfactory")
require("Product")