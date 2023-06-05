ui_util = {
}

-- This function is only called when Recipe Book is active, so no need to check for the mod
---@param player LuaPlayer
---@param type string
---@param name string
function ui_util.open_in_recipebook(player, type, name)
    local message = nil

    if remote.call("RecipeBook", "version") ~= RECIPEBOOK_API_VERSION then
        message = {"fp.error_recipebook_version_incompatible"}
    else
        local was_opened = remote.call("RecipeBook", "open_page", player.index, type, name)
        if not was_opened then message = {"fp.error_recipebook_lookup_failed", {"fp.pl_" .. type, 1}} end
    end

    if message then util.messages.raise(player, "error", message, 1) end
end
