Subfactory = {}
Subfactory.__index = Subfactory


function Subfactory:_init(name, icon)
    BaseClass._init(self, name)
    self.icon = icon
    self.timescale = 60
    self.notes = ""
    self.ingredients = {}
    self.products = {}
    self.byproducts = {}
    self.data_tables = {
        ingredient = self.ingredients, 
        product = self.products, 
        byproduct = self.byproducts
    }
    self.counter = {
        ingredient_index = 0,
        ingredient_count = 0,
        product_index = 0,
        product_count = 0,
        byproduct_index = 0,
        byproduct_count = 0,
    }
end


function Subfactory:set_icon(icon)
    self.icon = icon
end

function Subfactory:get_icon()
    return self.icon
end


function Subfactory:set_timescale(timescale)
    self.timescale = timescale
end

function Subfactory:get_timescale()
    return self.timescale
end


function Subfactory:set_notes(notes)
    self.notes = notes
end

function Subfactory:get_notes()
    return self.notes
end


function Subfactory:add(type, dataset)
    local index = type .. "_index"
    local count = type .. "_count"
    self.counter[index] = self.counter[index] + 1
    self.counter[count] = self.counter[count] + 1
    dataset:set_gui_position(self.counter[count])
    self.data_tables[type][self.counter[index]] = dataset
    return self.counter[index]
end

function Subfactory:delete(type, id)
    self.counter[type .. "_count"] = self.counter[type .. "_count"] - 1
    update_positions(self.data_tables[type], self.data_tables[type][id]:get_gui_position())
    self.data_tables[type][id] = nil
end


function Subfactory:get_count(type)
    return self.counter[type .. "_count"]
end

function Subfactory:get(type, id)
    return self.data_tables[type][id]
end

function Subfactory:get_in_order(type)
    return order_by_position(self.data_tables[type])
end


-- Returns true when a product already exists in given subfactory
function Subfactory:product_exists(product_name)
    for _, product in pairs(self.products) do
        if product.name == product_name then return true end
    end
    return false
end


function Subfactory:update_validity()
    for _, table in ipairs(data_tables) do
        for _, dataset in pairs(table) do
            if not dataset:check_validity() then
                self.valid = false
                return
            end
        end
    end
    self.valid = true
end

function Subfactory:remove_invalid_datasets()
    for table_name, table in pairs(data_tables) do
        for id, dataset in pairs(table) do
            if not dataset:is_valid() then
                self.delete(table_name, id)
            end
        end
    end
    self.valid = true
end

function Subfactory:shift(type, id, direction)
    shift_position(self.data_tables[type], id, direction, self.counter[type .. "_count"])
end