local m = assert(loadfile(arg[1]))()
local n = require 'nixio'
local json = require 'luci.jsonc'
local uuid='00000000-0000-4000-8000-000000000001'
local v=m.parse_link('vless://'..uuid..'@example.com:443?security=reality&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=1234&sni=example.com&flow=xtls-rprx-vision#Test')
assert(v.outbound.type=='vless' and v.outbound.tls.reality.enabled)
assert(v.outbound.tls.utls.fingerprint=='chrome')
assert(v.label=='Test' and v.outbound.flow=='xtls-rprx-vision')
local ss=m.parse_link('ss://'..n.bin.b64encode('aes-128-gcm:test:with:colons')..'@example.com:8388#SS')
assert(ss.outbound.password=='test:with:colons')
local trojan=m.parse_link('trojan://a%40b@example.com:443?sni=example.com')
assert(trojan.outbound.password=='a@b' and trojan.outbound.tls.enabled)
local vm=m.parse_link('vmess://'..n.bin.b64encode(json.stringify({add='example.com',port='443',id=uuid,net='ws',path='/socket',tls='tls',host='example.com',ps='VM'})))
assert(vm.outbound.transport.type=='ws' and vm.outbound.tls.enabled)
local nodes, skipped=m.parse_subscription(n.bin.b64encode('trojan://test@example.com:443\nunsupported://invalid\n'))
assert(#nodes==1 and skipped==1)
for _,bad in ipairs({'vless://x@example.com:99999','vless://x@example.com:443?type=xhttp','ss://YWVzOnRlc3Q=@example.com:80?plugin=obfs','trojan://x@example.com:443?allowInsecure=1'}) do
 assert(not pcall(m.parse_link,bad))
end
local c=m.config(v.outbound,false)
assert(c.inbounds[2].type=='tun' and c.inbounds[2].auto_route==false)
assert(c.dns.servers[1].detour=='proxy' and c.route.final=='proxy')
assert(c.outbounds[1].tag=='proxy' and #c.outbounds==1)
assert(m.config(v.outbound,true).inbounds[2]==nil)
assert(v.outbound.tag==nil, 'config must not mutate stored profile')
print('PASS: four link formats, subscription decoding, invalid options, controlled TUN/DNS routing')

local original_state=m.state
m.state=function()return {nodes={v}}end
assert(m.start_tests(nil,true)==nil,'An invalid single-node test must not become a bulk test')
assert(m.start_tests(99,true)==nil)
assert(m.start_tests(1.5,true)==nil)
m.state=original_state
print('PASS: invalid single-connection tests cannot start bulk jobs')
