# TODO

## Active

- Handcrafting in utility dialog crashes

- Need generic ('Any temperature') fluids that can be selected as top level products?
- Fluids with temp currently have a without-temperature version, gotten from recipe ingredients. Not sure if desired.

## Bugs

- Wrong localised names for custom machines/recipes etc
- Take care of faded disabled sprite buttons, probably by using toggled or sprite elements

## Features

- Change SimpleItems to be a dict instead of an array so there needs to be no fuss finding stuff
- Balance District items against each other
- Allow Factory products to take their amounts from the District's ingredients
  - This link should not automatically pull new values from the District, for a couple reasons:
    - First, it is annoying since your actual build won't update and thus the totals will be misleading
    - Second, it's technically super difficult since it creates a dependency loop that can't easily be resolved
  - You should just be able to enable this, and then have a way to pull the new amount on demand
  - It should still be possible to have a normal amount too, so you can overproduce as you wish
- Add feature to transfer items from district to district, mimmicing space platform transfers
  - In addition, it would be good if the mod could calculate your rocket and platform needs for the given items
  - Not super simple, needs constraints given by the user, like platform specs, and maybe others
  - Otherwise there won't be a unique solution. Kinda orthogonal in general, but would be helpful to have
- Allow clicking on District items to see their origin/usage. Ideally click to go there directly, but that's
  tricky since they can be from multiple places. Maybe a separate UI is warranted
- Fluid temps - needs dealing with before 2.0
  - Add back distinct items for each fluid temp, so I don't need to carry that info along separately in the solver
  - Have the complex matching logic only when no specific temperature is needed, for the solver and recipe picker
    - No idea how that logic could even work for the matrix solver, probably just can't?
  - Still need a no-temperature item probably, that can be produced with any target temp recipe
  - After this, boiler support should be re-added and made to work with all kinds of boilers

## Low Priority

- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though
- Rocket silo power usage seems very low, likely doesn't consider launch usage
- Agriculture tower implementation
  - Missing energy and pollution production, is different to normal entities
- Improve performance by not making item_views.process iterate the prefs every time
- Could use icons for control, shift, etc for context menus to make them smaller
- Could now store blueprints from the library I think?
- Context menu to change belt directly on belt view button
- Add floating text for all actions that are taken that are not possible
  - Ideally the tooltips and context menu wouldn't show them, but that is tricky
  - It's actually kinda confusing that it shows impossible actions now, should really fix that
- Better icons for custom recipes - mining, spoiling, etc
- Recipe energy of 0 is still awkward (doesn't work properly with matrix solver either)
- Ingredients without amount don't show, but should because any amount would be meaningless
- Also, having a value that's independent of production_ratio (like time) would be nice

## Future Tasks

- Quality calculations: not sure how far I want to go with these
  - Quality odds for products - that's kinda dumb without items themselves supporting quality, soo idk
    - Also solver doesn't support this kinda stuff atm anyways, needs rewrite
  - There's bigger ideas where you could enter X quality Y items per timescale and it would backsolve it
  - Plus more such ideas, but they seem kinda out there currently, need to play with quality myself first
- Item Spoiling - Not super much to do without a lot of effort.
  - Could do a thing where the user enters the time between steps and it takes the spoilage that incurrs into account
  - Maybe some other stuff too, but I'll have to play with it to figure this out. Low priority anyways
- Try using flib's built-in translation/search feature instead of doing it myself, saves me having it in global
- Preferences export would be great. Maybe without migration if that makes it much easier
- Make recalculate_on_factory_change a factory property, not a UI one
  - Also set factories to be recalculated when a prod research finishes
  - Maybe recalculate all factories right away, spread over x ticks instead of waiting for them to be opened
  - Could be useful in other situations that touch all factories as well, such as changing District planet
  - Might want to do a progress bar even, but that's getting complicated now
- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
  - Then, add crafting actions to context menu of machines/modules/recipes maybe even
- Main interface toggles/builds? 4 times when starting a save, which is weird
  - Check refreshes in general, maybe write a tool that flags when multiple refreshes happen in sequence
- Look into building prototypes on_load instead of saving them in global
  - Theoretically better, but the data structures still save direct pointers to them in global
  - Not sure if I want to avoid that by replacing it with a reference that needs to be resolved every time
- Topological ordering tech (see iPad drawing for some testing)
  - This is a method to order recipes in a way that makes them work with the traditional solver, pretty much
  - Is pretty easy to implement from what it looks like, even for recipes with multiple products etc
  - Doesn't work with cycles, so they'd need to be dealt with in some way. Probably just refuse to work at first
  - The applications are diverse: Simplest thing is just a cleanup factory thing where it orders recipes for the user
  - Secondly, it could be used with a quick-recipe dialog, which makes it faster to just pick out recipes until you're
    satisfied. It would need to topological sort it all at the end otherwise it won't always work.
  - The big feature would be a rate calculator-like selection tool that imports everything into FP for you to just see
    the rates, or more importantly change things around if you want to. Would be a killer feature.
      - This obviously needs topological sorting for the machines, but there's also a lot of other challenges. It needs
        to determine lots of things like modules, beacons, match custom recipes. Also fuels, top level products ideally.
      - So it'd be quite a big project, but seeing as RC is as popular as FP, it would be a good strategic move.
      - This could also have an 'update' functionality, where you can update an existing factory's amounts by selecting
        your factory so it's up to date with what you built.
- Solver rewrite
  - Thinking about topological ordering gave me big ideas. The solver could be graph-based as well potentially
  - You would convert it into a topological graph always.
    - That has as a consequence that the factory will always
      be ordered topologically, which is actually great as it removes the need for the user to order recipes. It needs
      additional bookkeeping though, as cyclic and duplicate recipes break the factory and need addressing immediately.
      But that is probably a worthwhile tradeoff. Whether the user should still be able to reorder if they want to is
      to be decided, but probably yes. Maybe through a more cumbersome UI though.
  - With that graph it would just go down the topological order and run the recipes associated with each
    - It would plug in the demanded product amount at the top, and then carry other amounts downwards through the graph
    - It would probably just set the production ratios on everything, and then a second pass calculates it all out
      and does the bookkeeping, which is the easy part and would also be cleaner this way.
  - It is not clear what current features this could still support (machine limit, priority product, etc), so it's hard
    to say whether it'll end up better in the end. Obviating the need for ordering recipes would be great though.
  - In addition, this would (I think!) also easily allow input-based calculations, which is sorely needed
    - The way to do it is to just go through the topological graph in reverse direction, and running the attached recipes
      that way (they would be the ones that consume the node, not produce it, but otherwise it'd be the same.)
    - This has other side effects, such as needing to decide whether a factory is input or output based, and the byproducts
      needing to be renamed to 'additional products/ingredients' or whatever. Lots of UI work but doable.
  - If this turns out to work (big IF!), it would be an amazing way to clean up the solver code which introducing important
    features like input-based calculation and presenting a nicer interface by removing the need for ordering. win-win-win
  - The matrix solver would just remain the same as previously (which is bad for UI complexity), but I think I won't avoid
    writing my own matrix solver (or simplex or whatever) at some point, just because the current situation is rough.
- More technology integration
  - Only unlock mining recipes after at least one of its crafting machine is unlocked. Similar for other custom, or maybe
    even general recipes? Might be overkill for normal recipes, it's a mod problem if you have the recipe but not machine unlocked
    - Can't run detection of this every time, no either cache results, or track technologies actively to determine what is unlocked
  - Similarly, could hide items that are not yet craftable, ie. have no unlocked recipe for them. Similar algo as above needed
  - Recipe (and item?) weighting/distance algorithm
    - It would be really sweet to know how far away a certain recipe is from the current research level
    - The difficulty/distance score could take number of steps required and science amounts for those steps into account, with
      large penalties (multipliers?) for requiring more distinct sciences. Other metrics could be used as well.
    - Since we want it to be relative to the current research status (probably? sometimes for sure), there are performance
      implications for determining this value.
      - Could model the tech tree as-is, with precalculated weights for each node, then traverse this tree backwards from
        the technology in question, adding up the weights as you go along
      - If that doesn't work out, one could save the current score for each tech on its node. Then, when a tech is researched, it
        goes down all its dependents and reduces their score by its own. So reading the distance for any tech is a simple operation.
        Might need to split this updating work over multiple ticks, but that'll have to be tested with Py's or something.
    - This could be used most obviously to sort recipes, not by ingredient complexity, but research 'distance'
    - It could also be used for ... a built-in recipe browser!
      - This weighting tech would be unique as far as I know. I always wanted to do a recipe browser, and this might be the impetus.
      - Just integrating it into FP makes sense, as I already parse a lot of the stuff and it's an added incentive to get the mod.
        Should be usable in a pretty much independent way though ideally.
      - Has a lot of potential for integration with the main mod obviously, what exactly is to be worked out.
      - Would probably be an FNEI-style layout, as that isn't too complicated to do, and doesn't compete with Factoriopedia. I also
        want it to be recipe-only (maybe items too) instead of this huge omnibus mod that RB became.
      - This would be quite a bit of UI work, but the hard work of recipe parsing is already done thankfully.
      - There are a lot of details to work out, and it is pretty orthogonal to the main mod. Solver improvements are more important.
- Custom recipe interface for other mods
  - Have a remote interface that other mods can use to inject their scripted recipes/items/etc into FP on their own
  - Puts the maintenance burden on them instead of me, which makes it feasible
  - Technical side will be pretty complex to work out, plus it has a potentially big API surface

## Waiting on

- Sliders still bugged, this is stupid https://forums.factorio.com/viewtopic.php?p=516440#p516440
- Constant combinator `sections` format rename
- API to open things in Factoriopedia
- No way to show quality on sprite buttons, which is essential in tons of places
  - Seemingly the hacky way to add a sprite to the button does not work, oof
  - Same thing for quality color, which should be used in relevant tooltips
- global_effect on planets, yet another effect that needs to be considered
  - runtime-only, which is problematic since we don't set actual planets
  - Maybe the planet selection should be based on actually-existing surfaces instead of prototypes
- game.evaluate_expression should not error but return something else if expression is invalid
- Ask about whether hover key combos would be possible
  - Could imitate it by keeping track of hover states myself, wouldn't be too horrible

## Release

- Update other language docs for the new `plural_for_parameter` format
- Write changelog description for districts
- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Update mod descriptions to mention SA/2.0 general compatibility
- Sort out Github board for done tasks and deal with pending reports
