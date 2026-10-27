local fs=require 'nixio.fs'
local n=require 'nixio'
local j=require 'luci.jsonc'
local m=require 'luci.model.home_ikev2'
local base='/data/home-ikev2'
local function write(path,value)
 local f=assert(n.open(path,'w','600'));local ok=f:writeall(value);f:close();assert(ok)
 assert(fs.chmod(path,'600'))
end
local function public4(value)
 local a,b,c,d=value:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
 a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
 if not a or a>223 or a==0 or a==10 or a==127 or b>255 or c>255 or d>255 then return false end
 return not (a==169 and b==254 or a==172 and b>=16 and b<=31 or a==192 and b==168 or a==100 and b>=64 and b<=127)
end
if arg[1]=='prepare' then
 assert(not fs.access(base..'/enabled'),'Disable IKEv2 before preparing a different profile')
 local p=assert(m.selected_profile())
 local address=p.server
 if not public4(address) then
  assert(not address:find(':',1,true),'IPv6 endpoint activation is not verified on this router')
  assert(address:match('^[a-z0-9][a-z0-9%.%-]*%.surfshark%.com$'),'A public server address is required')
  -- Only the selected VPN server hostname is resolved outside the tunnel.
  local command="curl --noproxy '*' -fsS --connect-timeout 4 --max-time 8 --resolve dns.google:443:8.8.8.8 "..
   "'https://dns.google/resolve?name="..address.."&type=A' 2>/dev/null"
  local reply=j.parse(require('luci.util').exec(command))
  address=nil
  if type(reply)=='table' and reply.Status==0 then
   for _,answer in ipairs(reply.Answer or {}) do
    if answer.type==1 and type(answer.data)=='string' and public4(answer.data) then address=answer.data;break end
   end
  end
  assert(address,'Could not securely resolve the server; use its verified public IP with its certificate hostname')
 end
 p.server=address
 assert(fs.mkdirr(base..'/active'));assert(fs.chmod(base..'/active','700'))
 write(base..'/active/ca.pem',p.certificate)
 local config=assert(m.test_configuration(p))
 config=config:gsub('version = 2','version = 2\n dpd_delay = 15s',1)
 config=config:gsub('/check/ca.pem','/active/ca.pem',1)
 config=config:gsub(' start_action = none',' reqid = 20290\n set_mark_out = 0x4f43/0xffffffff\n dpd_action = restart\n start_action = none',1)
 write(base..'/active/swanctl.conf',config)
 write(base..'/active/server',address..'\n')
 write(base..'/active/strongswan.conf',[[charon {
 install_routes = no
 install_virtual_ip = no
 initiator_only = yes
 threads = 16
 load = des md4 openssl random nonce pem x509 pkcs1 pkcs8 pubkey constraints revocation kdf kernel-netlink socket-default vici eap-identity eap-mschapv2
 plugins {
  vici {
   socket = unix:///data/home-ikev2/control/charon.vici
  }
  kernel-netlink {
   install_routes_xfrmi = no
  }
 }
 filelog {
  stderr {
   default = 0
   flush_line = yes
  }
 }
}
swanctl {
 load = des md4 openssl random nonce pem x509 pkcs1 pkcs8 pubkey constraints revocation kdf
}
]])
elseif arg[1]=='observe' then
 local raw=fs.readfile(base..'/control/sa.raw') or ''
 local list=raw:match('local%-vips%s*=%s*%[([^%]]+)%]') or ''
 local vip=list:match('%d+%.%d+%.%d+%.%d+')
 assert(vip and require('luci.ip').new(vip) and raw:match('state%s*=%s*INSTALLED'),'No installed IKEv2 child')
 write(base..'/control/vip',vip..'\n')
else os.exit(2) end
