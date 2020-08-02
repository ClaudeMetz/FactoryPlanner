local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    local preferences = player_table.preferences

    local mb_defaults = preferences.mb_defaults
    mb_defaults.machine = mb_defaults.module
    mb_defaults.module = nil

    local optional_columns = preferences.optional_production_columns
    preferences.pollution_column = optional_columns.pollution_column
    preferences.line_comment_column = optional_columns.line_comments
    preferences.optional_production_columns = nil
end

function migration.subfactory(subfactory)
end

function migration.packed_subfactory(packed_subfactory)
end

return migration