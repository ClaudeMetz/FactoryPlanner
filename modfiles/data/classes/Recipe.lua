-- This is essentially just a wrapper-'class' for a recipe prototype to add some data to it
Recipe = {}

function Recipe.init_by_id(recipe_id, production_type)
    return {
        proto = global.all_recipes.recipes[recipe_id],
        production_type = production_type,
        valid = true,
        class = "Recipe"
    }
end


function Recipe.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        production_type = self.production_type,
        class = self.class
    }
end

function Recipe.unpack(packed_self)
    return packed_self
end


-- Needs validation: proto
function Recipe.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "recipes", nil)
    return self.valid
end

-- Needs repair:
function Recipe.repair(_, _)
    -- If the prototype is still simplified, it couldn't be fixed by validate, so it has to be removed
    return false
end