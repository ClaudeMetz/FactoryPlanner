local Object = require("backend.data.Object")
local Module = require("backend.data.Module")

---@alias ModuledObject Machine | Beacon

---@class ModuleSet: Object, ObjectMethods
---@field class "ModuleSet"
---@field parent ModuledObject
---@field first Module?
---@field module_count integer
---@field module_limit integer
---@field empty_slots integer
local ModuleSet = Object.methods()
ModuleSet.__index = ModuleSet
script.register_metatable("ModuleSet", ModuleSet)

---@param parent ModuledObject
---@return ModuleSet
local function init(parent)
    local object = Object.init({
        first = nil,

        module_count = 0,
        -- 0 as placeholder for simplified parents
        module_limit = parent.proto.module_limit or 0,
        empty_slots = parent.proto.module_limit or 0,

        parent = parent
    }, "ModuleSet", ModuleSet)  --[[@as ModuleSet]]
    return object
end


function ModuleSet:index()
    OBJECT_INDEX[self.id] = self
    for module in self:iterator() do module:index() end
end


---@param module Module
---@param relative_object Module?
---@param direction NeighbourDirection?
function ModuleSet:insert(module, relative_object, direction)
    module.parent = self
    self:_insert(module, relative_object, direction)
    self:count_modules()
end

---@param module Module
function ModuleSet:remove(module)
    module.parent = nil
    self:_remove(module)
    self:count_modules()
end

---@param module Module
---@param new_module Module
function ModuleSet:replace(module, new_module)
    new_module.parent = self
    self:_replace(module, new_module)
    self:count_modules()
end


---@param filter ObjectFilter
---@param pivot Module?
---@param direction NeighbourDirection?
---@return Module? module
function ModuleSet:find(filter, pivot, direction)
    return self:_find(filter, pivot, direction)  --[[@as Module?]]
end

---@return Module?
function ModuleSet:find_last()
    return self:_find_last()  --[[@as Module?]]
end

---@param filter ObjectFilter?
---@param pivot Module?
---@param direction NeighbourDirection?
---@return fun(): Module?
function ModuleSet:iterator(filter, pivot, direction)
    return self:_iterator(filter, pivot, direction)
end

---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot Module?
---@return number count
function ModuleSet:count(filter, pivot, direction)
    return self:_count(filter, pivot, direction)
end


---@class ModuleNormalizeFeatures
---@field compatibility boolean?
---@field trim boolean?
---@field sort boolean?
---@field effects boolean?

---@param features ModuleNormalizeFeatures
function ModuleSet:normalize(features)
    self.module_limit = self.parent.proto.module_limit

    if features.compatibility then self:verify_compatibility() end
    if features.trim then self:trim() end
    if features.sort then self:sort() end
    if features.effects then self.parent:summarize_effects() end

    self:count_modules()
end

function ModuleSet:count_modules()
    local count = 0
    for module in self:iterator() do
        count = count + module.amount
    end
    self.module_count = count
    self.empty_slots = self.module_limit - self.module_count
end

function ModuleSet:verify_compatibility()
    local modules_to_remove = {}
    for module in self:iterator() do
        if not self:check_compatibility(module.proto) then
            table.insert(modules_to_remove, module)
        end
    end

    -- Actually remove incompatible modules; counts updated by calling function
    for _, module in pairs(modules_to_remove) do self:remove(module) end
end

function ModuleSet:trim()
    local module_count, module_limit = self.module_count, self.module_limit
    -- Return if the module count is within limits
    if module_count <= module_limit then return end

    local modules_to_remove = {}
    -- Traverse modules in reverse to trim them off the end
    for module in self:iterator(nil, self:find_last(), "previous") do
        -- Remove a whole module if it brings the count to >= limit
        if (module_count - module.amount) >= module_limit then
            table.insert(modules_to_remove, module)
            module_count = module_count - module.amount
        else  -- Otherwise, diminish the amount on the module appropriately and break
            local new_amount = module.amount - (module_count - module_limit)
            module:set_amount(new_amount)
            break
        end
    end

    -- Actually remove superfluous modules; counts updated by calling function
    for _, module in pairs(modules_to_remove) do self:remove(module) end
end

-- Sorts modules in a deterministic fashion so they are in the same order for every line
function ModuleSet:sort()
    local modules_by_name = {}
    for module in self:iterator() do
        modules_by_name[module.proto.name] = module
    end

    self.first = nil
    for _, category in ipairs(storage.prototypes.modules) do
        for _, module_proto in ipairs(category.members) do
            local module = modules_by_name[module_proto.name]
            if module then
                module.previous, module.next = nil, nil
                self:_insert(module)
            end
        end
    end
end

---@return ModuleEffects
function ModuleSet:get_effects()
    local effects = ftable.shallow_copy(BLANK_EFFECTS)
    for module in self:iterator() do
        for name, effect in pairs(module.total_effects) do
            effects[name] = effects[name] + effect
        end
    end
    return effects
end


---@param module_proto FPModulePrototype
---@return boolean compatible
function ModuleSet:check_compatibility(module_proto)
    if not self.parent:uses_effects() then
        return false
    else
        local all_allowed_effects = {self.parent.proto.allowed_effects}
        local recipe_allowed_effects = self.parent.parent.recipe_proto.allowed_effects
        -- No allowed_effects means all effects are allowed in this case
        if recipe_allowed_effects then table.insert(all_allowed_effects, recipe_allowed_effects) end

        for _, allowed_effects in pairs(all_allowed_effects) do
            for name, value in pairs(module_proto.effects) do
                -- Effects only need to be in the allowed list if they are considered positive
                if not allowed_effects[name] and util.effects.is_positive(name, value) then
                    return false
                end
            end
        end
    end
    return true
end

---@return ItemPrototypeFilter[]
function ModuleSet:compile_filter()
    local compatible_modules = {}
    for module_name, module_proto in pairs(MODULE_NAME_MAP) do
        if self:check_compatibility(module_proto) then
            table.insert(compatible_modules, module_name)
        end
    end

    return {{filter="name", name=compatible_modules}}
end


function ModuleSet:clear()
    self.first = nil
    self:normalize({effects=true})
end


---@return DefaultModuleData[]
function ModuleSet:compile_default()
    local modules_default = {}
    for module in self:iterator() do
        table.insert(modules_default, {
            prototype = module.proto.name,
            quality = module.quality_proto.name,
            amount = module.amount
        })
    end
    return modules_default
end

---@param default_data DefaultModule[]
---@return boolean equals
function ModuleSet:equals_default(default_data)
    if not default_data then return (self.module_count == 0) end
    if #default_data ~= self:count() then return false end

    local indexed_default = {}
    for _, default in pairs(default_data) do
        indexed_default[default.proto.name] = default
    end
    for module in self:iterator() do
        local default = indexed_default[module.proto.name]
        if not default or default.quality.name ~= module.quality_proto.name
                or default.amount ~= module.amount then
            return false
        end
    end
    return true
end

---@param module_default DefaultModule[]
function ModuleSet:ingest_default(module_default)
    if not module_default then return end  -- no default to ingest
    for _, default_module in pairs(module_default) do
        self:insert(Module.init(default_module.proto, default_module.amount, default_module.quality))
    end
    -- Compatibility check necessary because the module might not be compatible with the recipe
    self:normalize({compatibility=true, trim=true, sort=true, effects=true})  -- normalize for outdated defaults
end


---@param module Module
---@return boolean success
---@return string? error
function ModuleSet:paste(module)
    if not self:check_compatibility(module.proto) then
        return false, "incompatible"
    elseif self.empty_slots == 0 then
        return false, "no_empty_slots"
    end

    local desired_amount = math.min(module.amount, self.empty_slots)
    local existing_module = self:find({proto=module.proto})
    if existing_module then
        existing_module:set_amount(existing_module.amount + desired_amount)
    else
        self:insert(module)
        module:set_amount(desired_amount)
    end

    self:normalize({sort=true, effects=true})
    return true, nil
end


---@class PackedModuleSet: PackedObject
---@field class "ModuleSet"
---@field modules PackedModule[]?

---@return PackedModuleSet packed_self
function ModuleSet:pack()
    return {
        class = self.class,
        modules = self:_pack()
    }
end

---@param packed_self PackedModuleSet
---@param parent ModuledObject
---@return ModuleSet module_sets
local function unpack(packed_self, parent)
    local unpacked_self = init(parent)

    unpacked_self.first = Object.unpack(packed_self.modules, Module.unpack, unpacked_self)  --[[@as Module]]

    return unpacked_self
end


---@return boolean valid
function ModuleSet:validate()
    self.valid = self:_validate()

    if self.valid and self.parent.valid then
        if not self.module_count or not self.empty_slots then  -- when validating an unpacked ModuleSet
            self.module_limit = self.parent.proto.module_limit
            self:count_modules()
        end

        -- .normalize doesn't remove incompatible modules here, the above validation already marks them
        self:normalize({trim=true, sort=true, effects=true})
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function ModuleSet:repair(player)
    self:_repair(player)
    self:normalize({trim=true, sort=true, effects=true})

    self.valid = true
    return self.valid
end

return {init = init, unpack = unpack}
