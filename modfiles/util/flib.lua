-- Raiguard does not keep the flib API stable, so I copy the stuff I need here

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

local flib = {}

--- Retrieve a shallow copy of a portion of an array, selected from `start` to `end` inclusive.
---
--- The original array **will not** be modified.
---
--- ### Examples
---
--- ```lua
--- local arr = {10, 20, 30, 40, 50, 60, 70, 80, 90}
--- local sliced = table.slice(arr, 3, 7) -- {30, 40, 50, 60, 70}
--- log(serpent.line(arr)) -- {10, 20, 30, 40, 50, 60, 70, 80, 90} (unchanged)
--- ```
--- @generic V
--- @param arr flib.Array<V>
--- @param start number? default: `1`
--- @param stop number? Stop at this index. If zero or negative, will stop `n` items from the end of the array (default: `#arr`).
--- @return flib.Array<V> A new array with the copied values.
function flib.slice(arr, start, stop)
    local output = {}
    local n = #arr

    start = start or 1
    stop = stop or n
    stop = stop <= 0 and (n + stop) or stop

    if start < 1 or start > n then
        return {}
    end

    local k = 1
    for i = start, stop do
        output[k] = arr[i]
        k = k + 1
    end
    return output
end

--- Recursively copies the contents of a table into a new table. Does not create new copies of Factorio objects.
--- @generic T
--- @param tbl T
--- @return T
function flib.deep_copy(tbl)
  local lookup_table = {}
  local function _copy(tbl)
    if type(tbl) ~= "table" then
      return tbl
    elseif lookup_table[tbl] then
      return lookup_table[tbl]
    end
    local new_table = {}
    lookup_table[tbl] = new_table
    for index, value in pairs(tbl) do
      new_table[_copy(index)] = _copy(value)
    end
    return setmetatable(new_table, getmetatable(tbl))
  end
  return _copy(tbl)
end

--- Shallowly copies the contents of a table into a new table.
--- The parent table will have a new table reference, but any subtables within it will still have the same table reference.
--- Does not copy metatables.
--- @generic T
--- @param tbl T
--- @param use_rawset boolean? Use rawset to set the values (ignores metamethods).
--- @return T The copied table.
function flib.shallow_copy(tbl, use_rawset)
  local output = {}
  for k, v in pairs(tbl) do
    if use_rawset then
      rawset(output, k, v)
    else
      output[k] = v
    end
  end
  return output
end

return flib
