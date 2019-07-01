-- 'Class' representing an module
Module = {}

-- Initialised by passing a prototype from the all_moduless global table
function Module.init_by_proto(proto, amount)
    local category = global.all_modules.categories[global.all_modules.map[proto.category]]
    return {
        proto = proto,
        category = category,
        amount = amount,
        sprite = ("item/" .. proto.name),
        valid = true,
        class = "Module"
    }
end

-- Initialised by passing a category- and module prototype-id
function Module.init_by_ids(category_id, id, amount)
    local proto = global.all_modules.categories[category_id].modules[id]
    Module.init_by_proto(proto, amount)
end


-- Updates the given module with a new proto
function Module.update(self, proto)
    self.proto = proto
    self.sprite = ("item/" .. proto.name)
end


-- Update the validity of this module
function Module.update_validity(self)
    local category_name = (type(self.category) == "string") and self.category or self.category.name
    local new_category_id = new.all_modules.map[category_name]
    
    if new_category_id ~= nil then
        self.category = new.all_modules.categories[new_category_id]

        local proto_name = (type(self.proto) == "string") and self.proto or self.proto.name
        local new_module_id = self.category.map[proto_name]

        if new_module_id ~= nil then
            Module.update(self, self.category.modules[new_module_id])
            self.valid = true
        else
            self.proto = self.proto.name
            self.valid = false
        end
    else
        self.category = self.category.name
        self.proto = self.proto.name
        self.valid = false
    end

    -- Check whether the module is still compatible with it's machine 
    if self.valid then  -- only makes sense if the module is still valid at this point
        local characteristics = Line.get_module_characteristics(self.parent, self.proto)
        self.valid = characteristics.compatible
    end
    
    return self.valid
end

-- Tries to repair this module, deletes it otherwise (by returning false)
-- If this is called, the module is invalid and has a string saved to proto (and maybe to category)
function Module.attempt_repair(self, player)
    -- First, try and repair the category if necessary
    if type(self.category) == "string" then
        local current_category_id = global.all_modules.map[self.category]
        if current_category_id ~= nil then
            self.category = global.all_modules.categories[current_category_id]
        else  -- delete immediately if no matching category can be found
            return false
        end
    end
    
    -- At this point, category is always valid (and proto is always a string)
    local current_module_id = self.category.map[self.proto]
    if current_module_id ~= nil then
        Module.update(self, self.category.modules[current_module_id])
        self.valid = true
    else
        self.valid = false
    end

    -- Check whether the module is still compatible with it's machine, else remove it
    if self.valid then  -- only makes sense if the module is still valid at this point
        local characteristics = Line.get_module_characteristics(self.parent, self.proto)
        self.valid = characteristics.compatible
    end

    return self.valid
end