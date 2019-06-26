-- This is essentially just a wrapper-'class' for a recipe prototype to add some data to it
Recipe = {}

function Recipe.init(recipe_id)
    local proto = global.all_recipes.recipes[recipe_id]
    return {
        proto = proto,
        energy = proto.energy,
        sprite = ui_util.generate_recipe_sprite(proto),
        valid = true,
        class = "Recipe"
    }
end

-- Updates the given recipe with a new proto
function Recipe.update(self, proto)
    self.proto = proto
    self.energy = proto.energy
    self.sprite = ui_util.generate_recipe_sprite(proto)
end


-- Update the validity of this recipe
function Recipe.update_validity(self)
    local proto_name = (type(self.proto) == "string") and self.proto or self.proto.name
    local new_recipe_id = new.all_recipes.map[proto_name]
    
    if new_recipe_id ~= nil then
        Recipe.update(self, new.all_recipes.recipes[new_recipe_id])
        self.valid = true
    else
        self.proto = self.proto.name
        self.valid = false
    end

    return self.valid
end

-- Tries to repair this recipe, deletes it otherwise (by returning false)
-- If this is called, the recipe is invalid and has a string saved to proto
function Recipe.attempt_repair(self, player)
    local current_recipe_id = global.all_recipes.map[self.proto]
    if current_recipe_id ~= nil then
        Recipe.update(self, global.all_recipes.recipes[current_recipe_id])
        self.valid = true
    end

    return self.valid
end