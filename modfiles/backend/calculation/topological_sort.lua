local _topological_sort = {}

---@class SortNode
---@field id ObjectID
---@field products table<SolverItemKey, true>
---@field ingredients table<SolverItemKey, true>
---@field edges SortEdge[]
---@field visited boolean?
---@field explored boolean?

---@class SortEdge
---@field item_key SolverItemKey
---@field src integer
---@field dst integer

--- Returns the reverse topological order of the lines in the given floor.
--- Treat lines as nodes and items as `product -> ingredient` edges
---@param floor Floor
---@return ObjectID[]
function _topological_sort.sort_floor(floor)
    -- Collect the products/ingredients on each line
    local nodes = {}  ---@type table<integer, SortNode>
    for line_object in floor:iterator() do
        local node = {
            id = line_object.id,
            products = {},
            ingredients = {},
            edges = {}
        }  ---@type SortNode

        if line_object.class == "Floor" then
            for _, item in pairs(line_object.products) do
                local item_key = solver.util.pack_item(item.proto.name, item.proto.type)
                node.products[item_key] = true
            end
            for _, item in pairs(line_object.byproducts) do
                local item_key = solver.util.pack_item(item.proto.name, item.proto.type)
                node.products[item_key] = true
            end
            for _, item in pairs(line_object.ingredients) do
                local item_key = solver.util.pack_item(item.proto.name, item.proto.type)
                node.ingredients[item_key] = true
            end
        elseif line_object.class == "Line" then
            for _, item in pairs(line_object.recipe.products) do
                local item_key = solver.util.pack_item(item.name, item.type)
                node.products[item_key] = true
            end
            for _, item in pairs(line_object.recipe.ingredients) do
                local item_name = line_object.recipe:get_name_with_temperature(item)
                local item_key = solver.util.pack_item(item_name, item.type)
                node.ingredients[item_key] = true
            end

            -- TODO: add fuel, power, heat, pollution
        end

        table.insert(nodes, node)
    end

    -- Generate the graph
    for index, node in pairs(nodes) do
        for item_key, _ in pairs(node.products) do
            for neighbor_index, neighbor_node in pairs(nodes) do
                if neighbor_index ~= index and neighbor_node.ingredients[item_key] then
                    local edge = {
                        item_key = item_key,
                        src = index,
                        dst = neighbor_index
                    }  ---@as SortEdge

                    table.insert(node.edges, edge)
                end
            end
        end
    end

    local order = {}   ---@type ObjectID[]
    local cycled_items = {}   ---@type table<SolverItemKey, true>

    ---@param index integer
    ---@param path SortEdge[]
    ---@return SortEdge? cycling_edge
    local function depth_first_search(index, path)
        local node = nodes[index]

        if node.explored then
            return
        elseif node.visited then  -- loop detected
            local cycling_edge  ---@type SortEdge
            for i = #path, 1, -1 do
                local edge = path[i]

                -- If this cycle contains an item that was looped before, prefer to break it there
                if cycled_items[edge.item_key] then cycling_edge = edge end

                if edge.src == index then  -- reached the start of the cycle
                    cycling_edge = cycling_edge or edge
                    cycled_items[cycling_edge.item_key] = true
                    return cycling_edge
                end
            end
        end

        -- Visit all the neighbours (depth first)
        node.visited = true
        for _, edge in pairs(node.edges) do
            if not cycled_items[edge.item_key] then
                table.insert(path, edge)
                local cycling_edge = depth_first_search(edge.dst, path)
                table.remove(path)

                -- In the case of cycling, break the cycle on the selected edge
                if cycling_edge and cycling_edge ~= edge then
                    node.visited = nil
                    return cycling_edge
                end
            end
        end

        -- Add this node after all neighbors were explored
        table.insert(order, node.id)
        node.explored = true
    end

    for index, node in pairs(nodes) do
        if not node.explored then depth_first_search(index, {}) end
    end

    return order
end

return _topological_sort
