local fixtures = {
 ['/proc/net/route']='Iface Destination Gateway Flags\nccmni1 00000000 00000000 0001 0 0\n',
 ['/proc/net/arp']='IP address HW type Flags HW address Mask Device\n192.168.70.20 0x1 0x2 02:00:00:00:00:01 * br-lan\n',
 ['/sys/class/net/ccmni1/statistics/rx_bytes']='1024',
 ['/sys/class/net/ccmni1/statistics/tx_bytes']='512',
 ['/etc/wireless/l1profile.dat']='INDEX0_profile_path=/etc/wireless/radio.dat\nINDEX0_main_ifname=ra0\n',
 ['/etc/wireless/radio.dat']='SSID1=<unsafe & name>\nWirelessMode=16\nChannel=6\nWPAPSK1=must-not-leak\n',
 ['/sys/class/net/ra0/flags']='0x1003'
}
package.loaded['nixio.fs']={readfile=function(path) return fixtures[path] end}
package.loaded['luci.util']={ubus=function(object,method)
 if object=='system' then return {uptime=100,memory={total=1000,available=400}} end
 return nil
end}
local model = assert(loadfile(arg[1]))()
assert(model.default_route(fixtures['/proc/net/route'])=='ccmni1')
assert(model.default_route('')==nil)
assert(model.default_route('eth0 00000000 00000000 0000')==nil)
assert(#model.neighbors('bad input')==0)
assert(#model.neighbors('1.2.3.4 0x1 0x0 00:00:00:00:00:00 * eth0')==0)
local data=model.snapshot(true)
assert(data.vendor_network_available==false and data.internet_checked==false)
assert(data.rx_bytes==1024 and data.tx_bytes==512)
assert(#data.neighbors==1 and data.neighbors[1].complete==true)
assert(data.wifi[1].ssid=='<unsafe & name>' and data.wifi[1].up==true)
assert(data.wifi[1].band=='2.4 GHz' and data.wifi[1].password==nil)
assert(data.wifi[1].WPAPSK1==nil)
assert(model.snapshot(false).wifi==nil)
fixtures['/etc/wireless/l1profile.dat']='INDEX0_profile_path=/etc/wireless/mediatek/mt7915.dbdc.b0.dat\nINDEX0_main_ifname=ra0\n'
fixtures['/etc/wireless/mediatek/mt7915.dbdc.b0.dat']=fixtures['/etc/wireless/radio.dat']
assert(model.snapshot(true).wifi[1].config_device=='MT7915D.1.1')
fixtures['/proc/net/route']=''
assert(model.snapshot(false).rx_bytes==nil)
fixtures['/etc/wireless/l1profile.dat']=''
assert(#model.snapshot(true).wifi==0)
local named=model.attach_names({{ip='192.168.70.2',mac='AA:BB:CC:DD:EE:FF'},{ip='192.168.70.3',mac='00:11:22:33:44:55'}},
 '9999999999 aa:bb:cc:dd:ee:ff 192.168.70.2 Family-laptop *\n9999999999 aa:aa:aa:aa:aa:aa 192.168.70.3 Wrong-device *')
assert(named[1].hostname=='Family-laptop')
assert(named[2].hostname==nil,'Must not attach a name when the lease MAC differs')
local unknown=model.attach_names({{ip='192.168.70.4',mac='00:11:22:33:44:55'}},'0 00:11:22:33:44:55 192.168.70.4 * *')
assert(unknown[1].hostname==nil,'Missing names must remain unknown')
print('PASS: route, neighbors, verified DHCP names, missing data, Wi-Fi mapping and credential exclusion')
