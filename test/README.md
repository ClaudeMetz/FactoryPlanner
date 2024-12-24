This is a proof-of-concept test suite. To run it, install and have active
factorio-test mod (might need to reveal "internal" category on mod browser) at
the same time as the mod in this directory.

This is done as a separate mod to `factoryplanner` for two reasons:
* Enables custom items and recipes to be defined. This not only can make tests
  resilient to base game changes, it also enables testing of scenarios that may
  only be present in mods.
* Easy way to separate out all the test infrastructure from the main mod.

A limitation of this is we can only test via an exposed API ... but that's
probably a good thing for resilient tests anyway.