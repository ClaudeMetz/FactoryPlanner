---@diagnostic disable

-- Covers the research pseudo-recipes: setup defines science packs, labs and
-- technologies, check asserts what the generator made of them.
--
-- Each lab input set buckets the technologies it can research (their packs a subset
-- of the inputs) by time and amount profile: costs merge when they only differ in
-- which amount-1 packs they use, distinct above-1 amounts stay apart. A recipe takes
-- the packs its bucket's technologies actually use, at their real amounts, and
-- produces the research item of its time. Sets no technology matches don't exist,
-- and neither do items for times only they observe. Machine categories are keyed on
-- the input set, so all buckets of one set share machines and defaults, and a lab
-- joins every category whose set is a subset of its inputs. Recipes show their
-- set's first lab by entity order as their icon; the items get the time-badged
-- flask.
--
-- Times are chosen so no base technology shares one: base uses 5/10/15/30/35/45/60s,
-- these use 17/19/23/31/47/150s. That keeps the absence assertions meaningful even
-- though all cases load into the same game.
--
-- Coverage:
--   tech-a       17s, packs 1+2+3      merges with tech-b: all amounts are 1
--   tech-b       17s, pack 1           same time through a subset technology
--   tech-amount2 17s, pack 1 amount 2  distinct amount profile, its own recipe
--   tech-c       31s, pack 1           second time, reaching both sets via subset
--   tech-union12 23s, packs 1+2        with tech-union13, neither set containing the
--   tech-union13 23s, packs 1+3        other: the bucket's ingredients are the union
--   tech-hidden  19s, pack 1           hidden technology, skipped
--   tech-none    47s, hidden-lab pack  only a hidden lab takes it: no set, and its
--                                      time doesn't exist for any set
--   tech-minutes 150s, pack 1          minute formatting and icon path
--   tech-trigger trigger-based         no science units at all, skipped

local helpers = require("helpers")

return {
    setup = function()
        local deepcopy = require("util").table.deepcopy

        -- ** SCIENCE PACKS **

        -- Item orders deliberately disagree with the name order (pack-2 sorts last),
        -- so the order-based ingredient sorting and sprite pick are provably not
        -- falling back to name order
        local packs = {}
        for suffix, order in pairs({["1"] = "test-a-1", ["2"] = "test-a-9",
                ["3"] = "test-a-3", ["none"] = "test-a-4", ["unused"] = "test-a-5"}) do
            local pack = deepcopy(data.raw.item["automation-science-pack"])
            pack.name = "test-research-pack-" .. suffix
            pack.order = order
            table.insert(packs, pack)
        end
        data:extend(packs)

        -- Normal is changed only to give the drain tests a non-trivial multiplier.
        -- Other machine calculations use a synthetic FP-quality object at runtime,
        -- since Factorio rejects additional qualities with the feature flag disabled.
        data.raw.quality.normal.science_pack_drain_multiplier = 0.5

        -- ** LABS **

        local function test_lab(name, overrides)
            local lab = deepcopy(data.raw.lab.lab)
            lab.name = name
            lab.fast_replaceable_group = nil
            lab.next_upgrade = nil
            lab.inputs = {"test-research-pack-1", "test-research-pack-2", "test-research-pack-3"}
            for key, value in pairs(overrides) do lab[key] = value end
            return lab
        end

        data:extend{
            test_lab("test-research-lab-a", {researching_speed = 2}),
            test_lab("test-research-lab-b", {researching_speed = 1, science_pack_drain_rate_percent = 70}),
            test_lab("test-research-lab-quality-drain", {science_pack_drain_rate_percent = 70,
                uses_quality_drain_modifier = true, quality_affects_module_slots = true}),
            test_lab("test-research-lab-clamped-drain", {science_pack_drain_rate_percent = 1,
                uses_quality_drain_modifier = true}),
            test_lab("test-research-lab-restricted", {inputs = {"test-research-pack-1"}}),
            -- Visible, but no technology uses its only pack, so its set is dropped
            test_lab("test-research-lab-unused", {inputs = {"test-research-pack-unused"}}),
            -- One set shared by two labs whose entity order disagrees with their name
            -- order, so the recipe icon provably follows the order
            test_lab("test-research-lab-pair-a", {order = "b",
                inputs = {"test-research-pack-1", "test-research-pack-2"}}),
            test_lab("test-research-lab-pair-z", {order = "a",
                inputs = {"test-research-pack-1", "test-research-pack-2"}}),
            -- The game refuses to load a technology no lab at all accepts, so the
            -- unaccepted-pack scenario means acceptance by a hidden lab only
            test_lab("test-research-lab-hidden", {inputs = {"test-research-pack-none"}, hidden = true})
        }

        -- ** TECHNOLOGIES **

        local function test_tech(name, overrides)
            local tech = deepcopy(data.raw.technology["automation"])
            tech.name = name
            tech.prerequisites = nil
            tech.effects = nil
            tech.unit = {count = 10, time = 17,
                ingredients = {{"test-research-pack-1", 1}}}
            for key, value in pairs(overrides) do tech[key] = value end
            return tech
        end

        data:extend{
            test_tech("test-research-tech-a", {
                effects = {{type = "laboratory-productivity", modifier = 0.1}},
                unit = {count = 10, time = 17, ingredients = {
                    {"test-research-pack-1", 1}, {"test-research-pack-2", 1},
                    {"test-research-pack-3", 1}}}
            }),
            test_tech("test-research-tech-b", {}),
            test_tech("test-research-tech-amount2", {unit = {count = 10, time = 17, ingredients = {
                {"test-research-pack-1", 2}}}}),
            test_tech("test-research-tech-c", {unit = {count = 10, time = 31, ingredients = {
                {"test-research-pack-1", 1}}}}),
            test_tech("test-research-tech-union12", {unit = {count = 10, time = 23, ingredients = {
                {"test-research-pack-1", 1}, {"test-research-pack-2", 1}}}}),
            test_tech("test-research-tech-union13", {unit = {count = 10, time = 23, ingredients = {
                {"test-research-pack-1", 1}, {"test-research-pack-3", 1}}}}),
            test_tech("test-research-tech-hidden", {hidden = true,
                unit = {count = 10, time = 19, ingredients = {{"test-research-pack-1", 1}}}}),
            test_tech("test-research-tech-none", {unit = {count = 10, time = 47, ingredients = {
                {"test-research-pack-none", 1}}}}),
            test_tech("test-research-tech-minutes", {unit = {count = 10, time = 150,
                ingredients = {{"test-research-pack-1", 1}}}}),
            test_tech("test-research-tech-trigger", {unit = nil,
                research_trigger = {type = "craft-item", item = "iron-plate", count = 1}})
        }
    end,

    check = function(context)
        local c = helpers.collector()
        local find = prototyper.util.find

        local single_set = "test-research-pack-1"
        local pair_set = "test-research-pack-1-test-research-pack-2"
        local multi_set = "test-research-pack-1-test-research-pack-2-test-research-pack-3"
        local unused_set = "test-research-pack-unused"
        local single_category = "research-" .. single_set
        local pair_category = "research-" .. pair_set
        local multi_category = "research-" .. multi_set

        -- One recipe per lab input set and observed cost bucket
        local function check_recipe(signature, ticks, category)
            local name = "impostor-research-" .. signature .. "-" .. ticks
            local proto = find("recipes", name)
            if not proto then
                c.check(false, name .. ": missing")
                return nil
            end
            c.check(proto.categories[category] ~= nil, name .. ": missing category " .. category)
            return proto
        end

        local multi = check_recipe(multi_set, 1020, multi_category)
        local single = check_recipe(single_set, 1020, single_category)
        local slow = check_recipe(single_set, 1860, single_category)
        -- Subset technologies reach bigger sets: 31s comes from a pack-1-only tech
        local multi_slow = check_recipe(multi_set, 1860, multi_category)
        -- The amount-2 technology is its own bucket in both sets
        local amount2 = check_recipe(single_set, "1020-test-research-pack-1-2", single_category)
        local multi_amount2 = check_recipe(multi_set, "1020-test-research-pack-1-2", multi_category)

        -- Same time, two technologies whose packs contain neither the other
        local union_multi = check_recipe(multi_set, 1380, multi_category)
        local union_pair = check_recipe(pair_set, 1380, pair_category)
        local minutes = check_recipe(single_set, 9000, single_category)
        local multi_minutes = check_recipe(multi_set, 9000, multi_category)

        -- Base's 15s only comes from technologies using none of the test packs
        c.check(find("recipes", "impostor-research-" .. single_set .. "-900") == nil,
            "single: time generated from a base technology matching no test pack")
        -- Neither 23s technology fits the single-pack set, so it has no such bucket
        c.check(find("recipes", "impostor-research-" .. single_set .. "-1380") == nil,
            "single: 23s offered despite accepting neither union technology")
        c.check(find("recipes", "impostor-research-" .. single_set .. "-1140") == nil,
            "single: hidden technology was offered")
        c.check(find("recipes", "impostor-research-" .. unused_set .. "-9000") == nil,
            "unused: recipe generated for a set matching no technologies")

        if multi then
            -- research_unit_energy is given in ticks: a 17s tech must yield 17, not 1020
            c.check(multi.energy == 17, "multi: expected energy 17, got " .. multi.energy)
            -- Labs a and b tie on entity order, so the name decides the recipe icon
            c.check(multi.sprite == "entity/test-research-lab-a",
                "multi: expected lab-a's entity icon, got " .. multi.sprite)
            -- tech-a's three packs merged with tech-b's one, all at amount 1
            c.check(#multi.ingredients == 3, "multi: expected the bucket's three packs")
            -- Ingredients follow item order (1, 3, 2), not name order
            c.check(multi.ingredients[2].name == "test-research-pack-3"
                and multi.ingredients[3].name == "test-research-pack-2",
                "multi: expected ingredients sorted by item order")
            -- The name counts the recipe's own packs, not the whole lab input set
            c.check(multi.localised_name[2] == 3, "multi: expected a pack count of 3 in the name")
            c.check(multi.localised_name[3] == 17 and multi.localised_name[4][1] == "fp.unit_second",
                "multi: expected a 17-second localised name")
            c.check(multi.allowed_effects.productivity and multi.allowed_effects.speed,
                "multi: modules must be allowed, gated by the lab entity instead")
            c.check(multi.productivity_recipe == "custom-research",
                "multi: missing the force-wide research productivity key")
        end
        if single then
            -- The amount-2 technology sits in its own bucket, not here
            c.check(single.ingredients[1].amount == 1, "single: expected ingredient amount 1")
            c.check(single.sprite == "entity/test-research-lab-restricted",
                "single: expected the restricted lab's entity icon, got " .. single.sprite)
        end
        if amount2 then
            c.check(#amount2.ingredients == 1 and amount2.ingredients[1].amount == 2,
                "amount2: expected the single pack at amount 2")
        end
        if multi_amount2 then
            -- Buckets take only the packs their technologies use, so this one matches
            -- the amount-2 cost exactly despite living in the full set's category
            c.check(#multi_amount2.ingredients == 1
                and multi_amount2.ingredients[1].name == "test-research-pack-1"
                and multi_amount2.ingredients[1].amount == 2,
                "multi-amount2: expected only the single pack at amount 2")
            c.check(multi_amount2.localised_name[2] == 1,
                "multi-amount2: expected a pack count of 1 in the name")
        end
        if union_multi then
            -- Packs 1+2 and 1+3 at one time merge into a single bucket taking all three
            c.check(#union_multi.ingredients == 3,
                "union-multi: expected the union of both technologies' packs")
        end
        if union_pair then
            -- The same time in a set that accepts only one of the two technologies
            c.check(#union_pair.ingredients == 2
                and union_pair.ingredients[1].name == "test-research-pack-1"
                and union_pair.ingredients[2].name == "test-research-pack-2",
                "union-pair: expected only the packs this set accepts")
            -- pair-z sorts last by name but first by entity order, which is what counts
            c.check(union_pair.sprite == "entity/test-research-lab-pair-z",
                "union-pair: expected the lower-ordered lab's icon, got " .. union_pair.sprite)
        end
        if multi_slow then
            c.check(#multi_slow.ingredients == 1 and multi_slow.ingredients[1].amount == 1,
                "multi-slow: expected only the 31s technology's single pack")
        end
        if minutes then
            c.check(minutes.localised_name[3] == "2.5"
                    and minutes.localised_name[4][1] == "fp.unit_minute",
                "minutes: expected a 2.5-minute localised name")
        end
        if single and slow then
            c.check(single.order < slow.order, "single: recipes must order by ascending time")
        end
        if single and multi then
            c.check(single.order < multi.order, "single: smaller pack set must order first")
        end

        -- Every research recipe produces the research item of its time
        for _, pair in ipairs({{multi, 1020}, {single, 1020}, {slow, 1860},
                {multi_slow, 1860}, {amount2, 1020}, {multi_amount2, 1020},
                {union_multi, 1380}, {union_pair, 1380}, {minutes, 9000},
                {multi_minutes, 9000}}) do
            local recipe, ticks = pair[1], pair[2]
            if recipe then
                c.check(recipe.products[1].name == "custom-research-" .. ticks
                    and recipe.products[1].amount == 1,
                    recipe.name .. ": expected 1 custom-research-" .. ticks .. " as product")
            end
        end

        -- The hidden lab creates no set, and its 47s doesn't exist for any set.
        -- Trigger technologies have no science units, which would show up as an
        -- ingredient-less recipe (and crash the solver's minimum_energy handling as a
        -- free product).
        for _, recipe_proto in pairs(storage.prototypes.recipes) do
            local name = recipe_proto.name
            if name:find("^impostor%-research%-") then
                c.check(not name:find("test%-research%-pack%-none"),
                    "hidden lab's set offered anyway: " .. name)
                c.check(not name:find("%-2820$"), "hidden lab's time offered anyway: " .. name)
                c.check(not name:find("%-1140$"), "hidden technology's time offered anyway: " .. name)
                c.check(not name:find("test%-research%-pack%-unused"),
                    "unused lab's set offered anyway: " .. name)
                c.check(#recipe_proto.ingredients > 0, "research recipe without ingredients: " .. name)
            end
        end

        -- One research item per observed time, living in the dedicated research
        -- group; the pack sets exist only as recipes
        for _, ticks in ipairs({1020, 1380, 1860, 9000}) do
            local item = find("items", "custom-research-" .. ticks, "entity")
            if item then
                c.check(item.type == "entity" and item.hidden == false
                    and item.fixed_unit == nil and item.ingredient_only == false,
                    "item: expected a visible entity item without a fixed unit")
                c.check(item.group.name == prototypes.item_subgroup["science-pack"].group.name
                    and item.subgroup.name == "fp_research",
                    "item: expected the science packs' group and the fake fp_research subgroup")
                c.check(item.sprite == "fp_research_" .. ticks,
                    "item: expected the composed time icon, got " .. item.sprite)
            else
                c.check(false, "item: missing the research item for " .. ticks)
            end
        end
        c.check(find("items", "custom-research", "entity") == nil,
            "item: time-less item created despite the per-time model")
        c.check(find("items", "custom-research-" .. single_set, "entity") == nil,
            "item: per-set item created despite the per-time model")
        -- The hidden lab's 47s is observed by no usable set, so its item doesn't exist
        c.check(find("items", "custom-research-2820", "entity") == nil,
            "item: hidden lab's time got an item anyway")
        c.check(find("items", "custom-research-1140", "entity") == nil,
            "item: hidden technology's time got an item anyway")

        local minute_item = find("items", "custom-research-9000", "entity")
        if minute_item then
            c.check(minute_item.localised_name[2] == "2.5"
                    and minute_item.localised_name[3][1] == "fp.unit_minute",
                "item: expected a 2.5-minute localised name")
        end

        -- Labs join every category whose pack set is a subset of their inputs
        local function lab_categories(name)
            local categories = {}
            for _, category in pairs(storage.prototypes.machines) do
                for _, member in pairs(category.members) do
                    if member.name == name then categories[member.category] = member end
                end
            end
            return categories
        end

        for _, lab_name in ipairs({"test-research-lab-a", "test-research-lab-b"}) do
            local categories = lab_categories(lab_name)
            c.check(categories[single_category] ~= nil and categories[multi_category] ~= nil,
                lab_name .. ": expected membership in both research categories")
        end
        local restricted = lab_categories("test-research-lab-restricted")
        c.check(restricted[single_category] ~= nil, "restricted lab: missing its single-pack category")
        c.check(restricted[multi_category] == nil, "restricted lab: joined a category it can't research")
        c.check(next(lab_categories("test-research-lab-unused")) == nil,
            "unused lab: generated despite its set matching no technologies")

        local lab_a = lab_categories("test-research-lab-a")[single_category]
        if lab_a then
            c.check(lab_a.prototype_category == "lab", "lab-a: expected prototype_category lab")
            c.check(helpers.approx(lab_a.speed, 2), "lab-a: expected researching speed 2")
            c.check(helpers.approx(lab_a.resource_drain_rate, 1), "lab-a: expected drain rate 1")
        end
        local lab_b = lab_categories("test-research-lab-b")[single_category]
        if lab_b then
            c.check(helpers.approx(lab_b.speed, 1), "lab-b: expected researching speed 1")
            c.check(helpers.approx(lab_b.resource_drain_rate, 0.7), "lab-b: expected drain rate 0.7")
        end

        -- Exercise the runtime Machine calculations without involving any solver.
        local normal_quality = find("qualities", "normal")
        c.check(helpers.approx(normal_quality.science_pack_drain_multiplier, 0.5),
            "quality: science-pack drain multiplier was not preserved")
        local test_quality = {
            name = "synthetic-research-quality",
            lab_research_speed_multiplier = 1.6,
            science_pack_drain_multiplier = 0.5,
            lab_module_slots_bonus = 3
        }

        local function calculated_lab(name)
            local proto = lab_categories(name)[multi_category]
            if not proto then c.check(false, name .. ": missing machine"); return nil end
            local machine = context.classes.Machine.init({}, proto)
            machine.quality_proto = test_quality
            return machine
        end
        local lab_b_calculated = calculated_lab("test-research-lab-b")
        local quality_lab_calculated = calculated_lab("test-research-lab-quality-drain")
        local clamped_lab_calculated = calculated_lab("test-research-lab-clamped-drain")

        if lab_b_calculated then
            c.check(helpers.approx(lab_b_calculated:get_speed(), 1.6),
                "lab-b: expected quality to multiply researching speed")
            c.check(helpers.approx(lab_b_calculated:get_resource_drain_rate(), 0.7),
                "lab-b: quality drain modifier should be ignored")
            c.check(lab_b_calculated:get_module_limit() == lab_b_calculated.proto.module_limit,
                "lab-b: quality added slots without the opt-in flag")
            c.check(helpers.approx(lab_b_calculated:get_energy_usage(),
                    lab_b_calculated.proto.energy_usage),
                "lab-b: quality unexpectedly changed lab energy usage")
        end
        if quality_lab_calculated then
            c.check(helpers.approx(quality_lab_calculated:get_resource_drain_rate(), 0.35),
                "quality-drain lab: expected an above-floor drain rate of 0.35")
            c.check(quality_lab_calculated:get_module_limit()
                    == quality_lab_calculated.proto.module_limit + 3,
                "quality-drain lab: expected three quality module slots")
        end
        if clamped_lab_calculated then
            c.check(helpers.approx(clamped_lab_calculated:get_resource_drain_rate(), 0.01),
                "clamped-drain lab: expected the minimum drain rate of 0.01")
        end

        c.check(PRODUCTIVITY_RECIPES["custom-research"] == true,
            "custom-research missing from PRODUCTIVITY_RECIPES")

        -- The utility dialog and factory calculations consume this helper, so verify
        -- that it reads and converts the game's force-wide lab bonus.
        local force = game.players[1].force
        local previous_bonus = force.laboratory_productivity_bonus
        force.laboratory_productivity_bonus = 0.125
        c.check(lib.get_recipe_productivity(force, "custom-research") == 1250,
            "expected the 12.5% lab bonus at effect precision")
        force.laboratory_productivity_bonus = previous_bonus

        c.done()
    end
}
