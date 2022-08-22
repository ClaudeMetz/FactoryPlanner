-- Class representing a machine with its attached modules and fuel
Machine = {}

function Machine.init(proto, parent)
    local machine = {
        proto = proto,
        count = 0,
        limit = nil,  -- will be set by the user
        force_limit = false,
        fuel = nil,  -- needs to be set by calling Machine.find_fuel afterwards
        module_set = nil,  -- set right below
        total_effects = nil,
        effects_tooltip = "",
        valid = true,
        parent = parent,
        class = "Machine"
    }
    machine.module_set = ModuleSet.init(machine)

    return machine
end


function Machine.find_fuel(self, player)
    if self.fuel == nil and self.proto.energy_type == "burner" then
        local burner = self.proto.burner

        -- Use the first category of this machine's burner as the default one
        local fuel_category_name, _ = next(burner.categories, nil)
        local fuel_category_id = global.all_fuels.map[fuel_category_name]

        local default_fuel_proto = prototyper.defaults.get(player, "fuels", fuel_category_id)
        self.fuel = Fuel.init(default_fuel_proto)
        self.fuel.parent = self
    end
end

function Machine.summarize_effects(self, mining_prod)
    local effects = self.module_set.total_effects

    effects["base_prod"] = self.proto.base_productivity or nil
    effects["mining_prod"] = mining_prod or nil

    self.total_effects = effects
    self.effects_tooltip = data_util.format_module_effects(effects, false)

    Line.summarize_effects(self.parent)
end

function Machine.check_module_compatibility(self, module_proto)
    local recipe = self.parent.recipe

    if self.proto.module_limit == 0 then return false end

    if next(module_proto.limitations) and recipe.proto.use_limitations
      and not module_proto.limitations[recipe.proto.name] then
        return false
    end

    local allowed_effects = self.proto.allowed_effects
    if allowed_effects == nil then
        return false
    else
        for effect_name, _ in pairs(module_proto.effects) do
            if allowed_effects[effect_name] == false then
                return false
            end
        end
    end

    return true
end


function Machine.paste(self, object)
    if object.class == "Machine" then
        local new_category_id = global.all_machines.map[self.proto.category]
        local new_machine_map = global.all_machines.categories[new_category_id].map

        if new_machine_map[object.proto.name] ~= nil
          and Line.is_machine_applicable(self.parent, object.proto) then
            object.parent = self.parent
            self.parent.machine = object
            Line.summarize_effects(self.parent)
            return true, nil
        else
            return false, "incompatible"
        end
    elseif object.class == "Module" then
       return ModuleSet.paste(self.module_set, object)
    else
        return false, "incompatible_class"
    end
end

function Machine.clone(self)
    local clone = Machine.unpack(Machine.pack(self))
    clone.parent = self.parent
    Machine.validate(clone)
    return clone
end


function Machine.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        limit = self.limit,
        force_limit = self.force_limit,
        fuel = (self.fuel) and Fuel.pack(self.fuel) or nil,
        module_set = ModuleSet.pack(self.module_set),
        class = self.class
    }
end

function Machine.unpack(packed_self)
    local self = packed_self

    self.fuel = (packed_self.fuel) and Fuel.unpack(packed_self.fuel) or nil
    if self.fuel then self.fuel.parent = self end

    self.module_set = ModuleSet.unpack(packed_self.module_set)
    self.module_set.parent = self

    return self
end


-- Needs validation: proto, fuel, module_set
function Machine.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "machines", "category")

    local parent_line = self.parent
    if self.valid and parent_line.valid and parent_line.recipe.valid then
        self.valid = Line.is_machine_applicable(parent_line, self.proto)
    end

    if self.fuel then self.valid = Fuel.validate(self.fuel) and self.valid end

    self.valid = ModuleSet.validate(self.module_set) and self.valid

    return self.valid
end

-- Needs repair: proto, fuel, module_set
function Machine.repair(self, player)
    -- If the prototype is still simplified, it couldn't be fixed by validate
    -- A final possible fix is to replace this machine with the default for its category
    if self.proto.simplified and not Line.change_machine_to_default(self.parent, player) then
        return false  -- if this happens, the whole line can not be salvaged
    end
    self.valid = true  -- if it gets to this, change_machine was successful and the machine is valid
    -- It just might need to cleanup some fuel and/or modules

    if self.fuel and not self.fuel.valid then
        -- If fuel is invalid, replace it with a default value
        if not Fuel.repair(self.fuel) then Machine.find_fuel(self, player) end
    end

    -- Remove invalid modules and normalize the remaining ones
    ModuleSet.repair(self.module_set)

    return true
end
