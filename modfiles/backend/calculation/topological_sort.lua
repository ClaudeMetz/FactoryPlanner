local _topological_sort = {}

---@class SortNode
---@field id ObjectID
---@field products table<SolverItemKey, integer>
---@field ingredients table<SolverItemKey, integer>
---@field visited integer?

---@class SortEdge
---@field item_key SolverItemKey
---@field cost number
---@field source_node_id integer


---@param floor Floor
---@return ObjectID[]
function _topological_sort.sort_floor(floor)
    -- Collect the products/ingredients on each line
    local line_nodes = {}  ---@type table<integer, SortNode>
    for line_object in floor:iterator() do
        local line_node = { id = line_object.id, products = {}, ingredients = {} }  ---@type SortNode
        if line_object.class == "Floor" then
            local product_index = 1
            for _, item in pairs(line_object.products) do
                local item_key = solver.util.pack_item(item.proto.name, item.proto.type)
                line_node.products[item_key] = product_index
                product_index = product_index + 1
            end
            for _, item in pairs(line_object.byproducts) do
                local item_key = solver.util.pack_item(item.proto.name, item.proto.type)
                line_node.products[item_key] = product_index
                product_index = product_index + 1
            end
            local ingredient_index = 1
            for _, item in pairs(line_object.ingredients) do
                local item_key = solver.util.pack_item(item.proto.name, item.proto.type)
                line_node.ingredients[item_key] = ingredient_index
                ingredient_index = ingredient_index + 1
            end
        elseif line_object.class == "Line" then
            local product_index = 1
            for _, item in pairs(line_object.recipe.products) do
                local item_key = solver.util.pack_item(item.name, item.type)
                line_node.products[item_key] = product_index
                product_index = product_index + 1
            end
            local ingredient_index = 1
            for _, item in pairs(line_object.recipe.ingredients) do
                local item_name = line_object.recipe:get_name_with_temperature(item)
                local item_key = solver.util.pack_item(item_name, item.type)
                line_node.ingredients[item_key] = ingredient_index
                ingredient_index = ingredient_index + 1
            end

            -- TODO: add fuel, power, heat, pollution
        end

        table.insert(line_nodes, line_node)
    end

    local order = {}   ---@type ObjectID[]
    local cycled_items = {}   ---@type table<SolverItemKey, true>
    local iteration = 1

    --- Treat lines as nodes and items as `product -> ingredient` edges
    ---@param index integer
    ---@param path SortEdge[]
    ---@return SortEdge? cycling_edge
    local function depth_first_search(index, path)
        local node = line_nodes[index]

        if not node.visited then
            node.visited = iteration  -- mark as visited
        elseif node.visited < iteration then
            return  -- already sorted
        else -- loop detected
            local weakest_edge = {item_key = "", cost = 0, source_node_id = 0}  ---@type SortEdge
            for i = #path, 1, -1 do
                local edge = path[i]
                if edge.cost > weakest_edge.cost then weakest_edge = edge end
                if edge.source_node_id == node.id then break end
            end

            cycled_items[weakest_edge.item_key] = true
            return weakest_edge
        end


        -- Visit all the neighbours (depth first)
        for item_key, product_index in pairs(node.products) do
            for neighbor_index, neighbor_node in pairs(line_nodes) do
                if neighbor_index ~= index then
                    local ingredient_index = neighbor_node.ingredients[item_key]
                    if ingredient_index then
                        local edge = { item_key = item_key, cost = 0.0, source_node_id = node.id }  ---@as SortEdge

                        -- Calculate the cost heuristic for this edge
                        -- Assume no more than 1000 products/ingredients per floor
                        if cycled_items[item_key] then
                            edge.cost = 1e6
                        else
                            edge.cost = product_index * 1000 + ingredient_index
                        end

                        table.insert(path, edge)
                        local cycling_edge = depth_first_search(neighbor_index, path)
                        table.remove(path)

                        -- In the case of cycling, break the cycle on the selected edge
                        if cycling_edge and cycling_edge ~= edge then
                            node.visited = nil
                            return cycling_edge
                        end
                    end
                end
            end
        end

        -- All the neighbors (if any, excuding cycles) have been added to the sorted list
        -- Add this node as well
        table.insert(order, node.id)
    end

    for index, node in pairs(line_nodes) do
        if not node.visited then
            depth_first_search(index, {})
            iteration = iteration + 1
        end
    end

    return order
end

return _topological_sort
