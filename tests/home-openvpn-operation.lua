local source=assert(arg[1])
local original_os,original_arg,original_nixio=os,arg,package.loaded.nixio
local function run(arguments)
 local command,code
 package.loaded.nixio={open=function() return {lock=function() return true end,close=function() end} end}
 os=setmetatable({execute=function(value) command=value;return 0 end,
  exit=function(value) code=value;error('test-exit',0) end},{__index=original_os})
 arg=arguments
 local ok,err=pcall(assert(loadfile(source)))
 os, arg, package.loaded.nixio=original_os,original_arg,original_nixio
 assert(not ok and err=='test-exit','Unexpected script failure')
 return command,code
end
local command,code=run({'openvpn','prepare','Netherlands_TCP'})
assert(code==0 and command=='HOME_VPN_OPERATION_LOCKED=1 /usr/libexec/home-openvpn-control prepare Netherlands_TCP')
command,code=run({'openvpn','stop'})
assert(code==0 and command=='HOME_VPN_OPERATION_LOCKED=1 /usr/libexec/home-openvpn-control stop')
command,code=run({'openvpn','stop',''})
assert(code==0 and command=='HOME_VPN_OPERATION_LOCKED=1 /usr/libexec/home-openvpn-control stop')
for _,arguments in ipairs({{'openvpn','prepare'},{'openvpn','prepare','bad;command'},
 {'openvpn','stop','two names'},{'openvpn','up','tun0'},{'other','enable'}}) do
 command,code=run(arguments);assert(code==2 and command==nil,'Unsafe dispatch accepted')
end
command,code=run({'tunnel','enable'})
assert(code==0 and command=='HOME_VPN_OPERATION_LOCKED=1 /usr/libexec/home-tunnel-control enable')
command,code=run({'ikev2','disable'})
assert(code==0 and command=='HOME_VPN_OPERATION_LOCKED=1 /usr/libexec/home-ikev2-control disable')
print('VPN operation validation and existing dispatch passed')
