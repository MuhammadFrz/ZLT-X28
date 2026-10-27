local fs = require 'nixio.fs'
local util = require 'luci.util'
local M = {}

local function number(path)
    return tonumber(fs.readfile(path) or '')
end

function M.default_route(text)
    for line in (text or ''):gmatch('[^\n]+') do
        local iface, destination, gateway, flags = line:match('^(%S+)%s+(%x+)%s+(%x+)%s+(%x+)')
        if destination == '00000000' and tonumber(flags, 16) % 2 == 1 then
            return iface
        end
    end
end

function M.neighbors(text)
    local out = {}
    for line in (text or ''):gmatch('[^\n]+') do
        local ip, hw, flags, mac, mask, device = line:match('^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)')
        if mac and mac:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$') and mac ~= '00:00:00:00:00:00' then
            out[#out+1] = {ip=ip, mac=mac, interface=device, complete=flags == '0x2'}
        end
    end
    table.sort(out, function(a,b) return a.ip < b.ip end)
    return out
end

function M.attach_names(neighbors, leases)
    local by_ip = {}
    for line in (leases or ''):gmatch('[^\r\n]+') do
        local expiry, mac, ip, name = line:match('^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)')
        if expiry and name ~= '*' and #name <= 253 and not name:find('%c') then
            by_ip[ip] = {mac=mac:lower(), name=name}
        end
    end
    for _,device in ipairs(neighbors) do
        local lease = by_ip[device.ip]
        if lease and lease.mac == device.mac:lower() then
            device.hostname = lease.name
            device.name_source = 'Vendor DHCP lease'
        end
    end
    return neighbors
end

local function wifi()
    local out = {}
    local l1 = fs.readfile('/etc/wireless/l1profile.dat') or ''
    local paths = l1:match('INDEX0_profile_path=([^\r\n]+)')
    local names = l1:match('INDEX0_main_ifname=([^\r\n]+)')
    if not paths or not names then return out, 'Wi-Fi profile mapping is unavailable.' end
    local ifaces = {}
    for v in names:gmatch('[^;]+') do ifaces[#ifaces+1] = v end
    local i = 0
    local config_devices = {
        ['/etc/wireless/mediatek/mt7915.dbdc.b0.dat']='MT7915D.1.1',
        ['/etc/wireless/mediatek/mt7915.dbdc.b1.dat']='MT7915D.1.2'
    }
    for path in paths:gmatch('[^;]+') do
        i = i + 1
        -- This adapter intentionally supports the verified MT7915 dual-radio mapping only.
        if path:match('^/etc/wireless/[%w_./-]+%.dat$') and ifaces[i] then
            local profile = fs.readfile(path)
            local function field(key)
                return profile and ('\n'..profile):match('\n'..key..'=([^\r\n]*)')
            end
            local iface = ifaces[i]
            local flags = tonumber(fs.readfile('/sys/class/net/'..iface..'/flags') or '')
            local mode = field('WirelessMode') or ''
            local band = mode == '16' and '2.4 GHz' or mode == '17' and '5 GHz' or iface
            out[#out+1] = {band=band, interface=iface, config_device=config_devices[path], ssid=field('SSID1') or 'Unavailable',
                channel=tonumber(field('Channel')), up=flags ~= nil and flags % 2 == 1,
                available=profile ~= nil}
        end
    end
    return out
end

function M.snapshot(include_details)
    local info = util.ubus('system', 'info') or {}
    local iface = M.default_route(fs.readfile('/proc/net/route'))
    local memory = info.memory or {}
    local data = {observed_at=os.time(), uptime=info.uptime, route_interface=iface,
        memory_total=memory.total, memory_available=memory.available,
        vendor_network_available=type(util.ubus('network')) == 'table',
        internet_checked=false}
    if iface and iface:match('^[%w_.:-]+$') then
        data.rx_bytes = number('/sys/class/net/'..iface..'/statistics/rx_bytes')
        data.tx_bytes = number('/sys/class/net/'..iface..'/statistics/tx_bytes')
    end
    if include_details then
        data.wifi, data.wifi_error = wifi()
        data.neighbors = M.attach_names(M.neighbors(fs.readfile('/proc/net/arp')), fs.readfile('/tmp/dnsmasq.leases'))
    end
    return data
end

return M
