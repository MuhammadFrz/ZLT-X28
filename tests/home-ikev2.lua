local files, modes, output, certvalid, locked = {}, {}, {}, true, false
local objects,count={},0
local operation_busy=false
local links={}
local function copy(value)
 if type(value)~='table' then return value end
 local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local fs = {readlink=function(p)return links[p]end,access=function(p)return files[p]~=nil end,readfile=function(p)return files[p]end,
 mkdirr=function()return true end,chmod=function(p,m)modes[p]=m;return true end,
 unlink=function(p)files[p]=nil end,rename=function(a,b)files[b]=files[a];files[a]=nil;return true end}
package.loaded['nixio.fs']=fs
package.loaded['luci.jsonc']={stringify=function(p)count=count+1;output=copy(p);objects[tostring(count)]=copy(p);return tostring(count) end,parse=function(s)return copy(objects[s])end}
package.loaded['luci.util']={exec=function()return certvalid and 'CA:TRUE' or '' end}
package.loaded['luci.ip']={new=function(value)
 if value=='203.0.113.7' or value=='2001:db8::1' then return {} end
end}
package.loaded['nixio']={open=function(p,_,m)
 modes[p]=m
 return {lock=function()if p:match('home%-vpn%-operation.lock$') then return not operation_busy end;if locked then return false end;locked=true;return true end,
 writeall=function(_,s)files[p]=s;return #s end,close=function()if p:match('profile.lock$') then locked=false end end}
end}
local execute=os.execute;os.execute=function()return certvalid and 0 or 1 end
local m=assert(loadfile(arg[1]))()
local certificate='-----BEGIN CERTIFICATE-----\nQUJD\n-----END CERTIFICATE-----'
local profile=assert(m.validate(' US-NYC.PROD.SURFSHARK.COM ','manual-user','secret',certificate))
assert(profile.server=='us-nyc.prod.surfshark.com')
assert(not m.validate('203.0.113.7','user','secret',certificate))
assert(not m.validate('203.0.113.7','user','secret',certificate,'evil.com'))
for _,address in ipairs({'203.0.113.7','2001:db8::1'}) do
 local p=assert(m.validate(address,'user','secret',certificate,'a.surfshark.com'))
 local c=assert(m.test_configuration(p))
 assert(c:find('remote_addrs = '..address,1,true) and c:find('id = a.surfshark.com',1,true))
end
assert(not m.validate('999.999.999.999','user','secret',certificate,'a.surfshark.com'))
local config=assert(m.test_configuration(profile))
assert(config:find('if_id_out = 20290',1,true) and config:find('start_action = none',1,true))
assert(config:find('auth = pubkey',1,true) and config:find('id = us-nyc.prod.surfshark.com',1,true))
assert(config:find('secret = 0x736563726574',1,true) and not config:find('secret = secret',1,true))
profile.username='quote"\\#}'
assert(m.test_configuration(profile):find('id = "quote\\"\\\\#}"',1,true),'escape configuration metacharacters')
for _,host in ipairs({'https://us.surfshark.com','evil.com','surfshark.com.evil.com','a..surfshark.com','-a.surfshark.com','a-.surfshark.com',string.rep('a',64)..'.surfshark.com','a.surfshark.com;id'}) do
 assert(not m.validate(host,'user','secret',certificate),host)
end
assert(not m.validate('a.surfshark.com','user','a\nb',certificate))
assert(not m.validate('a.surfshark.com','user','secret','invalid'))
objects.legacy={server='old.surfshark.com',username='original',password='original-secret',certificate=certificate}
files['/data/home-ikev2/profile.json']='legacy'
assert(m.summary().profiles[1].server=='old.surfshark.com')
assert(m.save('a.surfshark.com','user','secret',certificate,'Second profile'))
assert(#output.profiles==2 and output.profiles[1].password=='original-secret','legacy profile preserved')
assert(output.profiles[2].password=='secret' and modes['/data/home-ikev2/profiles.new']=='600')
assert(output.selected==1,'adding a profile must not switch selection')
assert(m.select(2))
assert(output.selected==2 and #output.profiles==2)
assert(not m.select(3) and not m.select(1.5))
files['/data/home-ikev2/enabled']=''
assert(not m.select(1) and not locked,'selection must not change an enabled VPN')
files['/data/home-ikev2/enabled']=nil
files['/data/home-ikev2/routing-owned']=''
assert(not m.select(1) and not locked,'unfinished cleanup must block selection')
files['/data/home-ikev2/routing-owned']=nil
operation_busy=true;assert(not m.select(1));operation_busy=false
assert(output.selected==2,'rejected selection must preserve the chosen profile')
files['/data/home-ikev2/enabled']=''
files['/data/home-ikev2/control/attached']=''
files['/data/home-ikev2/control/daemon.pid']='123\n'
files['/data/home-ikev2/control/heartbeat']=tostring(os.time())
links['/proc/123/exe']='/data/home-ikev2/bin/charon'
assert(m.summary().running,'fresh live daemon and attachment must report running')
files['/data/home-ikev2/control/heartbeat']=tostring(os.time()-30)
assert(not m.summary().running,'stale heartbeat must not report connected')
files['/data/home-ikev2/control/heartbeat']=tostring(os.time())
links['/proc/123/exe']='/usr/bin/foreign'
assert(not m.summary().running,'PID reuse must not report connected')
files['/data/home-ikev2/enabled']=nil
files['/data/home-ikev2/xfrm-cleanup-pending']=''
assert(m.summary().cleanup_pending,'isolated kernel cleanup must remain visible after routing is restored')
files['/data/home-ikev2/xfrm-cleanup-pending']=nil
assert(not m.summary().running,'disabled VPN must not report connected')

local summary=m.summary();assert(summary.selected==2 and summary.profiles[2].label=='Second profile')
assert(summary.profiles[2].password==nil and summary.profiles[2].username==nil and summary.profiles[2].certificate==nil)
assert(modes['/data/home-ikev2']=='700' and not locked)
certvalid=false
assert(not m.save('a.surfshark.com','user','replacement',certificate))
assert(output.profiles[2].password=='secret' and #output.profiles==2,'invalid certificate must retain prior profiles')
assert(not files['/data/home-ikev2/certificate.check'] and not locked)
os.execute=execute
files['/data/home-ikev2/profiles.json']='CORRUPT'
certvalid=true
assert(not m.save('a.surfshark.com','user','secret',certificate))
assert(files['/data/home-ikev2/profiles.json']=='CORRUPT','corrupt storage must not be overwritten')
print('PASS: IKEv2 validation, private atomic storage, legacy migration, multiple profiles, selection, credential redaction and prior-profile preservation')
