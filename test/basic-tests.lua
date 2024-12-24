test("Hello, World!", function()
    assert.not_equal("Hello", "World")
    assert.are_equal(game.surfaces[1].name, "nauvis")
end)

test("Can call API", function()
    if remote.interfaces["factoryplanner"] then
        assert.are_equal("pong", remote.call("factoryplanner", "ping"))
    end
end)

test("Can access data", function()
    -- Can assume single player, so player index of 1.
    local realm = remote.call("factoryplanner", "get_realm", 1)

    assert.are_equal("New District", realm.first.name)
end)