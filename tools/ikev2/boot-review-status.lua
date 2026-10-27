local fs=require 'nixio.fs'
local j=require 'luci.jsonc'
local base='/data/home-ikev2/boot-review'
local current=fs.readfile('/proc/sys/kernel/random/boot_id')
local before=fs.readfile(base..'/before-boot-id')
local i=require('luci.model.home_ikev2').summary()
local t=require('luci.model.home_tunnel').summary()
local function trim(s)return s and s:gsub('%s+$','') or nil end
print('BOOT_REVIEW_JSON '..j.stringify({
 boot_changed=current~=nil and before~=nil and current~=before,
 watchdog_seen=current~=nil and current==fs.readfile(base..'/watchdog-boot-id'),
 enabled=i.enabled,running=i.running,ready=i.ready,cleanup_pending=i.cleanup_pending,
 selected=i.selected,profiles=#i.profiles,xray_enabled=t.enabled or false,xray_running=t.running,
 armed=fs.access(base..'/armed') and true or false,
 status=trim(fs.readfile(base..'/status')) or 'pending',rollback=trim(fs.readfile(base..'/rollback-status')) or 'none',
 uptime_seconds=tonumber((fs.readfile('/proc/uptime') or ''):match('^[%d%.]+')),
 boot_entry=fs.access('/etc/rc.d/S18home-ikev2') and true or false
}))
