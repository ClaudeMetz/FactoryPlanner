local simplex_engine = {}


---@alias PrototypeName string
---@alias ItemSet {PrototypeName: true}
---@alias ItemArray Array<PrototypeName>
---@alias ResultMap {ObjectId: SimplexFloorResult}

---@class SimplexFloorResult

---@class SimplexLineResult

---@param factory Factory
function simplex_engine.solve(factory)
    local results = {}  ---@type ResultMap

    -- Solve floors
    local target_items = {}  ---@type ItemArray
    for item in factory:iterator() do
        target_items[item.proto.name] = item.required_amount
    end
    simplex_engine.solve_floor(factory.top_floor, results, target_items)

    -- Update GUI
    simplex_engine.update_factory(factory)
end


---@param floor Floor
---@param results ResultMap
---@param target_items ItemArray?
function simplex_engine.solve_floor(floor, results, target_items)
    local product_set = {}  ---@type ItemSet
    local intermediate_set = {}  ---@type ItemSet
    local ingredient_set = {}  ---@type ItemSet

    for line_object in floor:iterator() do
        
    end
end


---@param factory Factory
function simplex_engine.update_factory(factory)
    for item in factory:iterator() do
        item.amount = 0
    end
    simplex_engine.update_floor(factory.top_floor)
end


---@param floor Floor
function simplex_engine.update_floor(floor)
    for _, item in pairs(floor.products) do
        item.amount = 0
    end
    for _, item in pairs(floor.byproducts) do
        item.amount = 0
    end
    for _, item in pairs(floor.ingredients) do
        item.amount = 0
    end
    for line_object in floor:iterator() do
        if line_object.class == "Floor" then
            simplex_engine.update_floor(line_object)
        elseif line_object.class == "Line" then
            simplex_engine.update_line(line_object)
        end
    end
end

---@param line Line
function simplex_engine.update_line(line)
    line.machine.amount = 0
    for _, item in pairs(line.products) do
        item.amount = 0
    end
    for _, item in pairs(line.byproducts) do
        item.amount = 0
    end
    for _, item in pairs(line.ingredients) do
        item.amount = 0
    end
end


return simplex_engine