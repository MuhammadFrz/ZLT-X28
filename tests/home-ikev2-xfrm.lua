local files,calls={},{}
local base='/data/home-ikev2'
package.loaded['nixio.fs']={access=function(p)return files[p]end,unlink=function(p)files[p]=nil;return true end}
local result=0
local execute=os.execute
os.execute=function(command)calls[#calls+1]=command;return result end
local source=assert(loadfile(arg[1]))
source();assert(#calls==0,'unowned state must never invoke cleanup')
files[base..'/routing-owned']=true
assert(not pcall(source) and #calls==0,'missing helper must preserve ownership')
files[base..'/bin/owned-xfrm']=true
source();assert(files[base..'/routing-owned'],'active routing ownership must remain')
assert(calls[1]=='timeout 20 /data/home-ikev2/bin/owned-xfrm --delete-owned')
files[base..'/routing-owned']=nil;files[base..'/xfrm-cleanup-pending']=true
result=256;assert(not pcall(source));assert(files[base..'/xfrm-cleanup-pending'],'failed cleanup must retain its marker')
result=0;source();assert(not files[base..'/xfrm-cleanup-pending'])
local count=#calls;source();assert(#calls==count,'completed cleanup is a no-op')
os.execute=execute
print('PASS: helper delegation, ownership gating, failure preservation and successful marker cleanup')
