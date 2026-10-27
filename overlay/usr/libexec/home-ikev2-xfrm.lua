local fs=require 'nixio.fs'
local base='/data/home-ikev2'
if not fs.access(base..'/routing-owned') and not fs.access(base..'/xfrm-cleanup-pending') then return end
assert(fs.access(base..'/bin/owned-xfrm'),'The ownership-scoped kernel helper is not installed')
assert(os.execute('timeout 20 '..base..'/bin/owned-xfrm --delete-owned')==0,'Owned kernel cleanup failed; ownership retained')
if fs.access(base..'/xfrm-cleanup-pending') then
 assert(fs.unlink(base..'/xfrm-cleanup-pending'),'Could not clear the completed cleanup marker')
end
