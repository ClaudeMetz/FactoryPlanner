-- Sets the font color of the given label / button-label
function set_label_color(ui_element, color)
    if color == "red" then
        ui_element.style.font_color = {r = 1}
    elseif color == "white" or color == "default" then
        ui_element.style.font_color = {r = 1, g = 1, b = 1}
    end
end


-- Determines unit of given timescale, currently limited to presets
function determine_unit(timescale)
    if timescale == 1 then
        return "s"
    elseif timescale == 60 then
        return "m"
    elseif timescale == 3600 then
        return "h"
    end
end


-- Jank-ass function to approximate the pixel dimensions of a given string
-- Fails for some strings (eg. monotone strings and others) due to kerning, but ¯\_(ツ)_/¯
function determine_pixelsize_of(string)
    local alphabet_pixelcounts = get_alphabet_pixelcounts()
    local size = 0
    for i = 1, #string do
        local c = string:sub(i,i)
        size = size + alphabet_pixelcounts[c] + 2
    end
    return size
end


-- Returns the pixelsize of letters+numbers with font 'fp-button-standard' (16p font)
function get_alphabet_pixelcounts()
    return {
        a = 9,
        b = 8,
        c = 7,
        d = 8,
        e = 8,
        f = 6,
        g = 9,
        h = 7,
        i = 2,
        j = 4,
        k = 7,
        l = 2,
        m = 13,
        n = 7,
        o = 9,
        p = 8,
        q = 8,
        r = 5,
        s = 8,
        t = 6,
        u = 7,
        v = 8,
        q = 13,
        x = 8,
        y = 8,
        z = 7,
        A = 10,
        B = 9,
        C = 8,
        D = 9,
        E = 8,
        F = 8,
        G = 9,
        H = 9,
        I = 2,
        J = 4,
        K = 9,
        L = 7,
        M = 12,
        N = 9,
        O = 10,
        P = 9,
        Q = 10,
        R = 9,
        S = 9,
        T = 9,
        U = 9,
        V = 10,
        W = 15,
        X = 9,
        Y = 9,
        Z = 9,
        ["0"] = 9,
        ["1"] = 6,
        ["2"] = 8,
        ["3"] = 8,
        ["4"] = 9,
        ["5"] = 8,
        ["6"] = 9,
        ["7"] = 8,
        ["8"] = 9,
        ["9"] = 9,
        [" "] = 4
    }
end

-- Returns string of given table for debugging
function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end