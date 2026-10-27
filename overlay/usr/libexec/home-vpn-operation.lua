local n=require 'nixio'
local protocol,action,name=arg[1],arg[2],arg[3]
if name=='' then name=nil end
local openvpn=protocol=='openvpn' and (action=='prepare' or action=='stop')
if openvpn then
 if name and not name:match('^[%w_]+$') then os.exit(2) end
 if action=='prepare' and not name then os.exit(2) end
elseif (protocol~='tunnel' and protocol~='ikev2') or (action~='enable' and action~='disable' and action~='trial') then os.exit(2) end
local lock=n.open('/tmp/home-vpn-operation.lock','a','600')
if not lock or not lock:lock('tlock') then
 if lock then lock:close() end
 io.stderr:write('Another VPN change is in progress. Try again shortly.\n')
 os.exit(3)
end
local suffix=openvpn and name and (' '..name) or ''
local code=os.execute('HOME_VPN_OPERATION_LOCKED=1 /usr/libexec/home-'..protocol..'-control '..action..suffix)
lock:close()
os.exit(code==0 and 0 or 1)
