if helpers.stage ~= "runtime" then return {} end

local unpackers = {
    TLProduct = require("backend.data.TLProduct").unpack,
    Floor = require("backend.data.Floor").unpack,
    Line = require("backend.data.Line").unpack,
    Machine = require("backend.data.Machine").unpack,
    Beacon = require("backend.data.Beacon").unpack,
    Fuel = require("backend.data.Fuel").unpack,
    Module = require("backend.data.Module").unpack
}

local _clipboard = {}

---@alias CopyableObject Floor | Line | Machine | Beacon | Module | Fuel | SimpleItem
---@alias CopyableObjectClass "Floor" | "Line" | "Machine" | "Beacon" | "Module" | "Fuel" | "SimpleItem"
---@alias CopyableObjectParent Factory | Floor | Line | ModuleSet | Machine

---@class ClipboardEntry
---@field class CopyableObjectClass
---@field packed_object PackedObject
---@field parent CopyableObjectParent?

-- Copies the given object into the player's clipboard as a packed object
---@param player LuaPlayer
---@param object CopyableObject
function _clipboard.copy(player, object)
    local player_table = lib.globals.player_table(player)
    player_table.clipboard = {
        class = object.class,
        packed_object = (object.pack ~= nil) and object:pack(true) or object,
        parent = object.parent  -- just used for unpacking, will remain a reference even if deleted elsewhere
    }

    lib.cursor.create_flying_text(player, {"fp.copied_into_clipboard", {"fp.pu_" .. object.class:lower(), 1}})
    lib.gui.run_refresh(player, "paste_button")
end

-- Tries pasting the player's clipboard content onto the given target
---@param player LuaPlayer
---@param target CopyableObject
---@return boolean success
function _clipboard.paste(player, target)
    local clip = lib.globals.player_table(player).clipboard

    if clip == nil then
        lib.cursor.create_flying_text(player, {"fp.clipboard_empty"})
        return false
    else
        local clone
        if clip.parent then  -- only real objects have parents
            clone = unpackers[clip.class](clip.packed_object, clip.parent)  ---@as CopyableObject
            ---@cast clone -SimpleItem
            clone:validate()
        else
            clone = lib.flib.shallow_copy(clip.packed_object)  ---@as SimpleItem
        end
        local success, error = target:paste(clone, player)

        if success then  -- objects in the clipboard are always valid since it resets on_config_changed
            lib.cursor.create_flying_text(player, {"fp.pasted_from_clipboard", {"fp.pu_" .. clip.class:lower(), 1}})

            solver.update(player)
            lib.gui.run_refresh(player, "production")
        else
            local object_lower, target_lower = {"fp.pl_" .. clip.class:lower(), 1}, {"fp.pl_" .. target.class:lower(), 1}
            if error == "incompatible_class" then
                lib.cursor.create_flying_text(player, {"fp.clipboard_incompatible_class", object_lower, target_lower})
            elseif error == "incompatible" then
                lib.cursor.create_flying_text(player, {"fp.clipboard_incompatible", object_lower})
            elseif error == "already_exists" then
                lib.cursor.create_flying_text(player, {"fp.clipboard_already_exists", target_lower})
            elseif error == "no_empty_slots" then
                lib.cursor.create_flying_text(player, {"fp.clipboard_no_empty_slots"})
            elseif error == "recipe_irrelevant" then
                lib.cursor.create_flying_text(player, {"fp.clipboard_recipe_irrelevant"})
            end
        end
        return success
    end
end

---@param player LuaPlayer
---@param dummy CopyableObject
---@param parent CopyableObjectParent
function _clipboard.dummy_paste(player, dummy, parent)
    parent:insert(dummy)
    if not _clipboard.paste(player, dummy) then
        -- Prevent collapsing the floor on `Floor:remove()`
        parent:remove(dummy, true)
    end
end

---@param player LuaPlayer
---@param classes table<CopyableObject, boolean>
---@return boolean present
function _clipboard.check_classes(player, classes)
    local clip = lib.globals.player_table(player).clipboard
    return (clip ~= nil and classes[clip.class])
end

return _clipboard
