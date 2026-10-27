local files,requests={},{}
local certificate='-----BEGIN CERTIFICATE-----\nQUJD\n-----END CERTIFICATE-----\n'
local profile={server='45.136.155.55',identity='tr-ist.prod.surfshark.com',username='test',password='test',certificate=certificate}
package.loaded['nixio.fs']={access=function(p)return files[p]~=nil end,readfile=function(p)return files[p]end,mkdirr=function()return true end,chmod=function()return true end}
package.loaded.nixio={open=function(p,_,mode)
 assert(mode=='600');return {writeall=function(_,s)files[p]=s;return #s end,close=function()end}
end}
local answer={Status=0,Answer={{type=1,data='45.136.155.55'}}}
package.loaded['luci.jsonc']={parse=function()return answer end}
package.loaded['luci.util']={exec=function(command)requests[#requests+1]=command;return '{}'end}
package.loaded['luci.ip']={new=function(value)return value=='10.20.30.40' and {} or nil end}
package.loaded['luci.model.home_ikev2']={selected_profile=function()return profile end,test_configuration=function(p)
 return 'version = 2\n remote_addrs = '..p.server..'\n /data/home-ikev2/check/ca.pem\n start_action = none\n'
end}
local source=assert(loadfile(arg[1]))
arg[1]='prepare';source()
assert(#requests==0,'IP profile must not trigger hostname lookup')
local config=files['/data/home-ikev2/active/swanctl.conf']
assert(config:find('set_mark_out = 0x4f43/0xffffffff',1,true))
assert(config:find('dpd_delay = 15s',1,true) and config:find('reqid = 20290',1,true))
assert(config:find('/active/ca.pem',1,true) and not config:find('/check/ca.pem',1,true))
assert(files['/data/home-ikev2/active/strongswan.conf']:find('load = des md4 openssl',1,true),'built-in crypto must precede OpenSSL')
profile.server='tr-ist.prod.surfshark.com';source()
assert(#requests==1 and requests[1]:find('--resolve dns.google:443:8.8.8.8',1,true))
assert(requests[1]:find('name=tr-ist.prod.surfshark.com&type=A',1,true),'resolve only the VPN server hostname')
for _,value in ipairs({'10.10.34.35','127.0.0.1','169.254.1.1','192.168.70.1','172.16.1.1','100.64.1.1','224.0.0.1'}) do
 profile.server='tr-ist.prod.surfshark.com';answer.Answer[1].data=value
 assert(not pcall(source),'nonpublic bootstrap result must fail: '..value)
end
arg[1]='observe'
files['/data/home-ikev2/control/sa.raw']='local-vips=[10.20.30.40] child-sas={isolated={state=INSTALLED}}'
source();assert(files['/data/home-ikev2/control/vip']=='10.20.30.40\n')
files['/data/home-ikev2/control/sa.raw']='local-vips=[10.20.30.40] child-sas={isolated={state=INSTALLING}}'
assert(not pcall(source),'a pending child must not be attached')
print('PASS: private runtime generation, IP and hostname bootstrap, sinkhole rejection, crypto order and installed-child gating')
