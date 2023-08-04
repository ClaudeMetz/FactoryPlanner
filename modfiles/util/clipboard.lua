local unpackers = {
    Product = require("backend.data.Product").unpack,
    Floor = require("backend.data.Floor").unpack,
    Line = require("backend.data.Line").unpack
}

local _clipboard = {}

-- TODO clean up

---@alias CopyableObject Product | LineObject | Machine | Beacon | Module | Fuel
--@alias FPParentObject District | Factory | Floor | Line | ModuleSet

---@class ClipboardEntry
---@field class string
---@field packed_object PackedObject
--@field parent FPParentObject

-- Copies the given object into the player's clipboard as a packed object
---@param player LuaPlayer
---@param object CopyableObject
function _clipboard.copy(player, object)
    local player_table = util.globals.player_table(player)
    player_table.clipboard = {
        class = object.class,
        packed_object = object:pack(),
        --parent = object.parent  -- just used for unpacking, will remain a reference even if deleted elsewhere
    }
    util.cursor.create_flying_text(player, {"fp.copied_into_clipboard", {"fp.pu_" .. object.class:lower(), 1}})
    util.raise.refresh(player, "paste_button", nil)
end

-- Tries pasting the player's clipboard content onto the given target
---@param player LuaPlayer
---@param target CopyableObject
function _clipboard.paste(player, target)
    local clip = util.globals.player_table(player).clipboard

    if clip == nil then
        util.cursor.create_flying_text(player, {"fp.clipboard_empty"})
    else
        --local level = (clip.class == "Line") and (target.parent.level or 1) or nil
        --local clone = _G[clip.class].unpack(ftable.deep_copy(clip.object), level)
        local clone = unpackers[clip.class](clip.packed_object)  -- always returns fresh object
        --clone.parent = clip.parent  -- not very elegant to retain the parent here, but it's an easy solution
        clone:validate()

        local success, error = target:paste(clone)
        if success then  -- objects in the clipboard are always valid since it resets on_config_changed
            util.cursor.create_flying_text(player, {"fp.pasted_from_clipboard", {"fp.pu_" .. clip.class:lower(), 1}})

            solver.update(player, util.context.get(player, "Factory"))
            util.raise.refresh(player, "subfactory", nil)
        else
            local object_lower, target_lower = {"fp.pl_" .. clip.class:lower(), 1}, {"fp.pl_" .. target.class:lower(), 1}
            if error == "incompatible_class" then
                util.cursor.create_flying_text(player, {"fp.clipboard_incompatible_class", object_lower, target_lower})
            elseif error == "incompatible" then
                util.cursor.create_flying_text(player, {"fp.clipboard_incompatible", object_lower})
            elseif error == "already_exists" then
                util.cursor.create_flying_text(player, {"fp.clipboard_already_exists", target_lower})
            elseif error == "no_empty_slots" then
                util.cursor.create_flying_text(player, {"fp.clipboard_no_empty_slots"})
            elseif error == "recipe_irrelevant" then
                util.cursor.create_flying_text(player, {"fp.clipboard_recipe_irrelevant"})
            end
        end
    end
end

---@param player LuaPlayer
---@param classes { [CopyableObject]: boolean }
---@return boolean present
function _clipboard.check_classes(player, classes)
    local clip = util.globals.player_table(player).clipboard
    return (clip ~= nil and classes[clip.class])
end

return _clipboard
