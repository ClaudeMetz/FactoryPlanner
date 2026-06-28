-- 2.0 ranslator module from flib, the 2.1 one requires providing requests in root scope, which I can't
---@diagnostic disable

if helpers.stage ~= "runtime" then return {} end

--[[
MIT License

Copyright (c) 2020 raiguard

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

--[[ if ... ~= "__flib__.dictionary" then
  return require("__flib__.dictionary")
end ]]

--local gui = require("__flib__.gui")
--local mod_gui = require("__core__.lualib.mod-gui")
--local table = require("__flib__.table")
local flib_table = {}

--- Find and return the first key containing the given value.
---
--- ### Examples
---
--- ```lua
--- local tbl = {"foo", "bar"}
--- local key_of_foo = table.find(tbl, "foo") -- 1
--- local key_of_baz = table.find(tbl, "baz") -- nil
--- ```
--- @generic K, V
--- @param tbl table<K, V> The table to search.
--- @param value V The value to match. Must have an `eq` metamethod set, otherwise will error.
--- @return K? key The first key corresponding to `value`, if any.
function flib_table.find(tbl, value)
  for k, v in pairs(tbl) do
    if v == value then
      return k
    end
  end
end



--- @class flib.DictionaryStorage
--- @field init_ran boolean
--- @field raw table<string, flib.Dictionary>
--- @field raw_count integer
--- @field to_translate string[]
--- @field translated table<string, table<string, flib.TranslatedDictionary>?>
--- @field wip flib.DictionaryWipData?

--- @class flib.DictionaryWipData
--- @field dict string
--- @field dicts table<string, flib.TranslatedDictionary>
--- @field finished boolean
--- @field key string?
--- @field last_batch_end flib.DictionaryTranslationRequest?
--- @field language string
--- @field received_count integer
--- @field requests table<uint, flib.DictionaryTranslationRequest>
--- @field request_tick uint
--- @field translator LuaPlayer

--- Utilities for creating dictionaries of localised string translations.
--- ```lua
--- local flib_dictionary = require("__flib__.dictionary")
--- ```
--- @class flib_dictionary : event_handler
local flib_dictionary = {}

local request_timeout_ticks = (60 * 5)

--- @param init_only boolean?
--- @return flib.DictionaryStorage
local function get_data(init_only)
  if not storage.__flib or not storage.__flib.dictionary then
    error("Dictionary module was not properly initialized - ensure that all lifecycle events are handled.")
  end
  local data = storage.__flib.dictionary
  if init_only and data.init_ran then
    error("Dictionaries cannot be modified after initialization.")
  end
  return data
end

--- @param language string
--- @return LuaPlayer?
local function get_translator(language)
  for _, player in pairs(game.players) do
    if player.connected and player.locale == language then
      return player
    end
  end
end

--[[ --- @param data flib.DictionaryStorage
local function update_gui(data)
  local wip = data.wip
  for _, player in pairs(game.players) do
    local frame_flow = mod_gui.get_frame_flow(player)
    local window = frame_flow.flib_translation_progress
    if wip then
      if not window then
        _, window = gui.add(frame_flow, {
          type = "frame",
          name = "flib_translation_progress",
          style = mod_gui.frame_style,
          direction = "vertical",
          {
            type = "label",
            style = "frame_title",
            caption = { "gui.flib-translating-dictionaries" },
            tooltip = { "gui.flib-translating-dictionaries-description" },
          },
          {
            type = "frame",
            name = "pane",
            style = "inside_shallow_frame_with_padding",
            --- @diagnostic disable-next-line: missing-fields
            style_mods = { top_padding = 8 },
            direction = "vertical",
          },
        })
      end
      local pane = window.pane --[[@as LuaGuiElement] ]
      local mod_flow = pane[script.mod_name]
      if not mod_flow then
        _, mod_flow = gui.add(pane, {
          type = "flow",
          name = script.mod_name,
          style_mods = { vertical_align = "center", top_margin = 4, horizontal_spacing = 8 },
          {
            type = "label",
            style = "caption_label",
            --- @diagnostic disable-next-line: missing-fields
            style_mods = { minimal_width = 130 },
            caption = { "?", { "mod-name." .. script.mod_name }, script.mod_name },
            ignored_by_interaction = true,
          },
          { type = "empty-widget", style = "flib_horizontal_pusher" },
          { type = "label", name = "language", style = "bold_label", ignored_by_interaction = true },
          {
            type = "progressbar",
            name = "bar",
            --- @diagnostic disable-next-line: missing-fields
            style_mods = { top_margin = 1, width = 100 },
            ignored_by_interaction = true,
          },
          {
            type = "label",
            name = "percentage",
            style = "bold_label",
            --- @diagnostic disable-next-line: missing-fields
            style_mods = { width = 24, horizontal_align = "right" },
            ignored_by_interaction = true,
          },
        })
      end
      local progress = wip.received_count / data.raw_count
      mod_flow.language.caption = wip.language
      mod_flow.bar.value = progress --[[@as double] ]
      mod_flow.percentage.caption = tostring(math.min(math.floor(progress * 100), 99)) .. "%"
      mod_flow.tooltip =
        { "", (wip.dict or { "gui.flib-finishing" }), "\n" .. wip.received_count .. " / " .. data.raw_count }
    else
      if window then
        local mod_flow = window.pane[script.mod_name]
        if mod_flow then
          mod_flow.destroy()
        end
        if #window.pane.children == 0 then
          window.destroy()
        end
      end
    end
  end
end ]]

--- @param data flib.DictionaryStorage
--- @return boolean success
local function request_next_batch(data)
  local raw = data.raw
  local wip = data.wip --[[@as flib.DictionaryWipData]]
  if wip.finished then
    wip.last_batch_end = nil
    return false
  end
  wip.last_batch_end = { language = wip.language, dict = wip.dict, key = wip.key }
  local requests, strings = {}, {}
  for i = 1, game.is_multiplayer() and 5 or 50 do
    local string
    repeat
      wip.key, string = next(raw[wip.dict], wip.key)
      if not wip.key then
        wip.dict = next(raw, wip.dict)
        if not wip.dict then
          -- We are done!
          wip.finished = true
        end
      end
    until string or wip.finished
    if wip.finished then
      break
    end
    local request = { dict = wip.dict, key = wip.key }
    requests[i] = request
    strings[i] = string
  end

  if not requests[1] then
    return false -- Finished
  end

  local translator = wip.translator
  if not translator.valid or not translator.connected or translator.locale ~= wip.language then
    local new_translator = get_translator(wip.language)
    if new_translator then
      wip.translator = new_translator
    else
      -- Cancel this translation
      data.wip = nil
      return false
    end
  end

  local ids = wip.translator.request_translations(strings)
  if not ids then
    return false
  end
  for i = 1, #ids do
    wip.requests[ids[i]] = requests[i]
  end
  --- @diagnostic disable-next-line: missing-fields
  wip.request_tick = game.tick

  --update_gui(data)

  return true
end

--- @param data flib.DictionaryStorage
local function handle_next_language(data)
  if not next(data.raw) then
    -- This can happen if handle_next_language is called during on_init or on_configuration_changed
    return
  end
  while not data.wip and #data.to_translate > 0 do
    local next_language = table.remove(data.to_translate, 1)
    if next_language then
      local translator = get_translator(next_language)
      if translator then
        -- Start translation
        local dicts = {}
        for name in pairs(data.raw) do
          dicts[name] = {}
        end
        --- @type flib.DictionaryWipData
        data.wip = {
          dict = next(data.raw),
          dicts = dicts,
          finished = false,
          --- @type string?
          key = nil,
          language = next_language,
          received_count = 0,
          --- @type table<uint, flib.DictionaryTranslationRequest>
          requests = {},
          request_tick = 0,
          translator = translator,
        }
        request_next_batch(data)
      end
    end
  end
end

-- Events

flib_dictionary.on_player_dictionaries_ready = script.generate_event_name()
--- Called when a player's dictionaries are ready to be used. Handling this event is not required.
--- @class flib.on_player_dictionaries_ready: EventData
--- @field player_index uint

-- Lifecycle handlers

function flib_dictionary.on_init()
  if not storage.__flib then
    storage.__flib = {}
  end
  --- @type flib.DictionaryStorage
  storage.__flib.dictionary = {
    init_ran = false,
    player_language_requests = {},
    player_languages = {},
    raw = {},
    raw_count = 0,
    to_translate = {},
    translated = {},
    wip = nil,
  }
  for player_index, player in pairs(game.players) do
    if player.connected then
      flib_dictionary.on_player_joined_game({
        name = defines.events.on_player_joined_game,
        tick = game.tick,
        --- @cast player_index uint
        player_index = player_index,
      })
    end
  end
end

flib_dictionary.on_configuration_changed = flib_dictionary.on_init

function flib_dictionary.on_tick()
  local data = get_data()
  if not data.init_ran then
    data.init_ran = true
  end

  handle_next_language(data)

  local wip = data.wip
  if not wip then
    return
  end

  if game.tick - wip.request_tick > request_timeout_ticks then
    local request = wip.last_batch_end
    if not request then
      -- Remove WIP because we actually finished somehow? This should never happen I think
      error("We're screwed")
    end
    wip.dict = request.dict
    wip.finished = false
    wip.key = request.key
    wip.requests = {}
    request_next_batch(data)
    --update_gui(data)
  end
end

--- @param e EventData.on_string_translated
function flib_dictionary.on_string_translated(e)
  local data = get_data()
  local id = e.id

  handle_next_language(data)

  local wip = data.wip
  if not wip then
    return
  end

  local request = wip.requests[id]
  if request then
    wip.requests[id] = nil
    wip.received_count = wip.received_count + 1
    if e.translated then
      wip.dicts[request.dict][request.key] = e.result
    end
  end

  while wip and not next(wip.requests) and not request_next_batch(data) do
    if wip.finished then
      data.translated[wip.language] = wip.dicts
      data.wip = nil
      for player_index, player in pairs(game.players) do
        if player.locale == wip.language then
          script.raise_event(flib_dictionary.on_player_dictionaries_ready, { player_index = player_index })
        end
      end
    end
    handle_next_language(data)
    --update_gui(data)
    wip = data.wip
  end
end

--- @param e EventData.on_player_joined_game
function flib_dictionary.on_player_joined_game(e)
  local player = game.get_player(e.player_index) --- @unwrap
  if not player then
    return
  end
  local language = player.locale
  local data = get_data()
  if data.translated[language] then
    script.raise_event(flib_dictionary.on_player_dictionaries_ready, { player_index = e.player_index })
    return
  elseif data.wip and data.wip.language == language then
    return
  elseif flib_table.find(data.to_translate, language) then
    return
  end
  table.insert(data.to_translate, language)
  handle_next_language(data)
  --update_gui(data)
end

flib_dictionary.on_player_locale_changed = flib_dictionary.on_player_joined_game

--- Handle all non-bootstrap events with default event handlers. Will not overwrite any existing handlers. If you have
--- custom handlers for on_tick, on_string_translated, or on_player_joined_game, ensure that you call the corresponding
--- module lifecycle handler..
function flib_dictionary.handle_events()
  for id, handler in pairs(flib_dictionary.events) do
    if not script.get_event_handler(id) then
      script.on_event(id, handler)
    end
  end
end

--- For use with `__core__/lualib/event_handler`. Pass `flib_dictionary` into `handler.add_lib` to
--- handle all relevant events automatically.
flib_dictionary.events = {
  [defines.events.on_player_joined_game] = flib_dictionary.on_player_joined_game,
  [defines.events.on_player_locale_changed] = flib_dictionary.on_player_locale_changed,
  [defines.events.on_string_translated] = flib_dictionary.on_string_translated,
  [defines.events.on_tick] = flib_dictionary.on_tick,
}

-- Dictionary creation

--- Create a new dictionary. The name must be unique.
--- @param name string
--- @param initial_strings flib.Dictionary?
function flib_dictionary.new(name, initial_strings)
  local data = get_data(true)
  local raw = data.raw
  if raw[name] then
    error("Attempted to create dictionary '" .. name .. "' twice.")
  end
  raw[name] = initial_strings or {}
  if initial_strings then
    data.raw_count = data.raw_count + table_size(initial_strings)
  end
end

--- Add the given string to the dictionary.
--- @param dict_name string
--- @param key string
--- @param localised LocalisedString
function flib_dictionary.add(dict_name, key, localised)
  local data = get_data(true)
  local raw = data.raw[dict_name]
  if not raw then
    error("Dictionary '" .. dict_name .. "' does not exist.")
  end
  if not raw[key] then
    data.raw_count = data.raw_count + 1
  end
  raw[key] = localised
end

--- Get all dictionaries for the player. Will return `nil` if the player's language has not finished translating.
--- @param player_index uint
--- @return table<string, flib.TranslatedDictionary>?
function flib_dictionary.get_all(player_index)
  local player = game.get_player(player_index)
  if not player then
    return
  end
  return get_data().translated[player.locale]
end

--- Get the specified dictionary for the player. Will return `nil` if the dictionary has not finished translating.
--- @param player_index uint
--- @param dict_name string
--- @return flib.TranslatedDictionary?
function flib_dictionary.get(player_index, dict_name)
  local data = get_data()
  if not data.raw[dict_name] then
    error("Dictionary '" .. dict_name .. "' does not exist.")
  end
  local language_dicts = flib_dictionary.get_all(player_index) or {}
  return language_dicts[dict_name]
end

--- @class flib.DictionaryLanguageRequest
--- @field player LuaPlayer
--- @field tick uint

--- @class flib.DictionaryTranslationRequest
--- @field language string
--- @field dict string
--- @field key string

--- Localised strings identified by an internal key. Keys must be unique and language-agnostic.
--- @alias flib.Dictionary table<string, LocalisedString>

--- Translations are identified by their internal key. If the translation failed, then it will not be present. Locale
--- fallback groups can be used if every key needs a guaranteed translation.
--- @alias flib.TranslatedDictionary table<string, string>

return flib_dictionary
