-- 'Class' representing a group of modules in a machine or beacon
ModuleSet = {}

function ModuleSet.init(parent)
    return {
        modules = Collection.init(),
        module_count = 0,
        module_limit = parent.proto.module_limit,
        empty_slots = parent.proto.module_limit,
        total_effects = nil,  -- summarized by calling function
        valid = true,
        class = "ModuleSet",
        parent = parent
    }
end


function ModuleSet.add(self, proto, amount)
    local object = Module.init(proto, amount, self)
    local dataset = Collection.add(self.modules, object)
    ModuleSet.normalize(self, {})  -- adjust metadata
    return dataset
end

function ModuleSet.remove(self, dataset)
    Collection.remove(self.modules, dataset)
    ModuleSet.normalize(self, {})  -- adjust metadata
end

function ModuleSet.replace(self, dataset, object)
    object.parent = self
    local replacement = Collection.replace(self.modules, dataset, object)
    ModuleSet.normalize(self, {})  -- adjust metadata
    return replacement
end

function ModuleSet.clear(self)
    self.modules = Collection.init()
    ModuleSet.normalize(self, {})  -- adjust metadata
end

function ModuleSet.get(self, dataset_id)
    return Collection.get(self.modules, dataset_id)
end

function ModuleSet.get_by_name(self, name)
    return Collection.get_by_name(self.modules, name)
end

function ModuleSet.get_all(self)
    return Collection.get_all(self.modules)
end

function ModuleSet.get_in_order(self, reverse)
    return Collection.get_in_order(self.modules, reverse)
end

function ModuleSet.get_module_kind_amount(self)
    return self.modules.count
end


function ModuleSet.normalize(self, features)
    self.module_limit = self.parent.proto.module_limit

    if features.compatibility then ModuleSet.verify_compatibility(self) end
    if features.trim then ModuleSet.trim(self) end
    if features.sort then ModuleSet.sort(self) end
    if features.effects then ModuleSet.summarize_effects(self) end

    ModuleSet.update_count(self)
    self.empty_slots = self.module_limit - self.module_count
end

function ModuleSet.verify_compatibility(self)
    local modules_to_remove = {}
    for _, module in ipairs(ModuleSet.get_in_order(self)) do
        if not ModuleSet.check_compatibility(self, module.proto) then
            table.insert(modules_to_remove, module)
        end
    end

    -- Actually remove incompatible modules; counts updated by calling function
    for _, module in pairs(modules_to_remove) do ModuleSet.remove(self, module) end
end

function ModuleSet.trim(self)
    local module_count, module_limit = self.module_count, self.module_limit
    -- Return if the module count is within limits
    if module_count <= module_limit then return end

    local modules_to_remove = {}
    -- Traverse modules in reverse to trim them off the end
    for _, module in ipairs(ModuleSet.get_in_order(self, true)) do
        -- Remove a whole module if it brings the count to >= limit
        if (module_count - module.amount) >= module_limit then
            table.insert(modules_to_remove, module)
            module_count = module_count - module.amount
        else  -- Otherwise, diminish the amount on the module appropriately and break
            local new_amount = module.amount - (module_count - module_limit)
            module.amount = new_amount  -- done raw since counts are updated by calling function
            break
        end
    end

    -- Actually remove superfluous modules; counts updated by calling function
    for _, module in pairs(modules_to_remove) do ModuleSet.remove(self, module) end
end

-- Sorts modules in a deterministic fashion so they are in the same order for every line
function ModuleSet.sort(self)
    local modules_by_name = {}
    for _, module in pairs(ModuleSet.get_all(self)) do
        modules_by_name[module.proto.name] = module
    end

    local next_position = 1
    for _, category in ipairs(global.all_modules.categories) do
        for _, module_proto in ipairs(category.modules) do
            local module = modules_by_name[module_proto.name]
            if module then
                module.gui_position = next_position
                next_position = next_position + 1
            end
        end
    end
end

function ModuleSet.summarize_effects(self)
    local effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}
    for _, module in pairs(self.modules.datasets) do
        for name, effect in pairs(module.total_effects) do
            effects[name] = effects[name] + effect
        end
    end
    self.total_effects = effects

    _G[self.parent.class].summarize_effects(self.parent)
end

function ModuleSet.update_count(self)
    local count = 0
    for _, module in pairs(self.modules.datasets) do
        count = count + module.amount
    end
    self.module_count = count
end


function ModuleSet.check_compatibility(self, module_proto)
    return _G[self.parent.class].check_module_compatibility(self.parent, module_proto)
end

function ModuleSet.compile_filter(self)
    local compatible_modules = {}
    for module_name, module_proto in pairs(MODULE_NAME_MAP) do
        if ModuleSet.check_compatibility(self, module_proto) then
            table.insert(compatible_modules, module_name)
        end
    end

    local existing_modules = {}
    for _, module in pairs(self.modules.datasets) do
        table.insert(existing_modules, module.proto.name)
    end

    return {{filter="name", name=compatible_modules},
      {filter="name", mode="and", invert=true, name=existing_modules}}
end


function ModuleSet.paste(self, module)
    if not ModuleSet.check_compatibility(self, module.proto) then
        return false, "incompatible"
    elseif self.empty_slots == 0 then
        return false, "no_empty_slots"
    end

    local desired_amount = math.min(module.amount, self.empty_slots)
    local existing_module = ModuleSet.get_by_name(self, module.proto.name)
    if existing_module then
        Module.set_amount(existing_module, existing_module.amount + desired_amount)
    else
        ModuleSet.add(self, module.proto, desired_amount)
    end
    ModuleSet.normalize(self, {sort=true, effects=true})
    return true, nil
end


function ModuleSet.pack(self)
    return {
        modules = Collection.pack(self.modules, Module),
        -- module_limit restored by ensuing validation
        module_count = self.module_count,
        empty_slots = self.empty_slots,
        class = self.class
    }
end

function ModuleSet.unpack(packed_self)
    local self = packed_self
    self.modules = Collection.unpack(packed_self.modules, self, Module)
    return self
end


-- Needs validation: modules
function ModuleSet.validate(self)
    self.valid = Collection.validate_datasets(self.modules, Module)
    -- .normalize doesn't remove incompatible modules here, the above validation already marks them
    if self.valid and self.parent.valid then ModuleSet.normalize(self, {trim=true, sort=true, effects=true}) end

    return self.valid
end

-- Needs repair: modules
function ModuleSet.repair(self, _)
    Collection.repair_datasets(self.modules, nil, Module)
    ModuleSet.normalize(self, {trim=true, sort=true, effects=true})

    self.valid = true  -- repairing invalid modules removes them, making this set valid
    return true
end
