local action=arg[1]
if action~='off' and action~='verify' and action~='restore' then os.exit(2) end
local ok,err=pcall(function() return require('luci.model.home_acceleration')[action]() end)
if not ok then io.stderr:write(tostring(err),'\n');os.exit(1) end
