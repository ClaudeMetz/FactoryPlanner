test("Hello, World!", function()
    assert.not_equal("Hello", "World")
    assert.are_equal(game.surfaces[1].name, "nauvis")
end)

test("Can call API", function()
    if remote.interfaces["factoryplanner"] then
        assert.are_equal("pong", remote.call("factoryplanner", "ping"))
    end
end)