local files,captured={}
package.loaded['nixio.fs']={readfile=function(p)return files[p]end,access=function(p)return files[p]~=nil end}
package.loaded['luci.model.home_ikev2']={summary=function()return {profiles={{}},selected=1,enabled=false,running=false,ready=false,cleanup_pending=false}end}
package.loaded['luci.model.home_tunnel']={summary=function()return {running=false}end}
package.loaded['luci.jsonc']={stringify=function(v)captured=v;return '{}'end}
local source=assert(loadfile(arg[1]))
source();assert(captured.status=='pending' and captured.rollback=='none' and not captured.boot_changed)
files['/proc/sys/kernel/random/boot_id']='old\n'
files['/data/home-ikev2/boot-review/before-boot-id']='old\n'
source();assert(not captured.boot_changed)
files['/proc/sys/kernel/random/boot_id']='new\n'
files['/data/home-ikev2/boot-review/watchdog-boot-id']='new\n'
source();assert(captured.boot_changed and captured.watchdog_seen and captured.status=='pending')
print('PASS: missing preboot fields and changed-boot/watchdog status')
