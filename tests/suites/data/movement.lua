---@diagnostic disable

return {
    testFactoryShiftArchiveBoundaries = {check=function(context)
        local district = lib.globals.player_table(context.player).realm.first
        local function add(name, archived)
            local factory = context.classes.Factory.init(name, "sequential")
            factory.archived = archived or false
            district:insert(factory)
            return factory
        end
        local first = add("First")
        local hidden = add("Archived", true)
        local last = add("Last")
        local archived = add("Archived", true)

        district:shift(first, "next", 10)
        assert(first.previous == last and first.next == archived, "Archive filtering must apply")
        district:shift(first, "next", 1)
        assert(first.previous == last and first.next == archived, "Filtered trailing entries provide no destination")
        district:shift(first, "previous")
        assert(first.previous == hidden and first.next == last)
        district:shift(first, "previous", 1)
        assert(first.previous == hidden and first.next == last, "Filtered leading entries provide no destination")

        first.archived = true
        district:shift(first, "next")
        assert(archived.next == first and first.next == nil)
        first.archived = false
        district:shift(first, "next")
        assert(first.previous == archived and first.next == nil, "Unarchived factory already follows all active factories")
    end},

    testSubfloorShiftBoundaries = {check=function(context)
        local floor = context.classes.Floor.init(2, "sequential")
        local defining, second, third = context.classes.Line.init(), context.classes.Line.init(), context.classes.Line.init()
        floor:insert(defining)
        floor:insert(second)
        floor:insert(third)

        floor:shift(defining, "next")
        assert(floor.first == defining and defining.next == second, "The defining recipe cannot move")
        floor:shift(third, "previous", 10)
        assert(floor.first == defining and defining.next == third and third.next == second)
        floor:shift(third, "previous")
        assert(floor.first == defining and defining.next == third, "Shift to start must preserve the defining recipe")
        floor:shift(third, "next")
        assert(defining.next == second and second.next == third and third.next == nil)
        floor:shift(third, "next")
        assert(second.next == third and third.next == nil, "Shift to end must leave the last line in place")
    end}
}
