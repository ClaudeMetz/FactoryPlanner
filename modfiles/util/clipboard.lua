local unpackers = {
    Product = require("backend.data.Product").unpack,
    Floor = require("backend.data.Floor").unpack,
    Line = require("backend.data.Line").unpack,
    Machine = require("backend.data.Machine").unpack,
    Beacon = require("backend.data.Beacon").unpack,
    Fuel = require("backend.data.Fuel").unpack,
    Module = require("backend.data.Module").unpack
}

local _clipboard = {}

---@alias CopyableObject Product | Floor | Line | Machine | Beacon | Module | Fuel
---@alias CopyableObjectParent Factory | Floor | Line | ModuleSet

---@class ClipboardEntry
---@field class string
---@field packed_object PackedObject
---@field parent CopyableObjectParent

-- Copies the given object into the player's clipboard as a packed object
---@param player LuaPlayer
---@param object CopyableObject
function _clipboard.copy(player, object)
    local player_table = util.globals.player_table(player)
    player_table.clipboard = {
        class = object.class,
        packed_object = object:pack(),
        parent = object.parent  -- just used for unpacking, will remain a reference even if deleted elsewhere
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
        local clone = unpackers[clip.class](clip.packed_object, clip.parent)  -- always returns fresh object
        clone:validate()
        local success, error = target:paste(clone)

        if success then  -- objects in the clipboard are always valid since it resets on_config_changed
            util.cursor.create_flying_text(player, {"fp.pasted_from_clipboard", {"fp.pu_" .. clip.class:lower(), 1}})

            solver.update(player)
            util.raise.refresh(player, "factory", nil)
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
---@param dummy CopyableObject
---@param parent CopyableObjectParent
function _clipboard.dummy_paste(player, dummy, parent)
    dummy.dummy = true
    parent:insert(dummy)
    _clipboard.paste(player, dummy)
    local last = parent:find_last()  --[[@as CopyableObject]]
    if last.dummy then parent:remove(last) end
end

---@param player LuaPlayer
---@param classes { [CopyableObject]: boolean }
---@return boolean present
function _clipboard.check_classes(player, classes)
    local clip = util.globals.player_table(player).clipboard
    return (clip ~= nil and classes[clip.class])
end

return _clipboard
