file = "modfiles"
project = "Factory Planner"
title = "Factory Planner Refarence"
all = true
format = "markdown"
dir = "docs"

custom_see_handler("^(https?://.*)$", function(url)
    return url, url
end)