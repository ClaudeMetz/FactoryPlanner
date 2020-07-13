-- This is essentially just a wrapper-'class' for a recipe prototype to add some data to it
Recipe = {}

function Recipe.init_by_id(recipe_id, production_type)
    local proto = global.all_recipes.recipes[recipe_id]
    return {
        proto = proto,
        production_type = production_type,
        valid = true,
        class = "Recipe"
    }
end


-- Needs validation: proto
function Recipe.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "recipes", nil)
    return self.valid
end

-- Needs repair: proto
function Recipe.repair(_, _)
    -- If the prototype is still simplified, it couldn't be fixed by validate, so it has to be removed
    return false
end