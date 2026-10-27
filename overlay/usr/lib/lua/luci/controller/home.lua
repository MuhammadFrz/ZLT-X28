module('luci.controller.home', package.seeall)

function index()
    entry({'admin', 'home'}, firstchild(), _('Home'), 1)
    local titles = {overview='Home', wifi='Wi-Fi', devices='Devices', internet='Internet', settings='Settings'}
    for i, name in ipairs({'overview', 'wifi', 'devices', 'internet', 'settings'}) do
        entry({'admin', 'home', name}, call('page', name), _(titles[name]), i).leaf = true
    end
    entry({'admin', 'home', 'telemetry'}, call('telemetry')).leaf = true
    entry({'admin', 'home', 'tunnel'}, post_on({action=true}, 'tunnel_page'), _('Xray'), 6).leaf = true
    entry({'admin', 'home', 'tunnel_status'}, call('tunnel_status')).leaf = true
    entry({'admin', 'vpn', 'tunnel'}, alias('admin', 'home', 'tunnel'), _('Xray'), 20).leaf = true
end

function tunnel_page()
    local http = luci.http
    local model = require 'luci.model.home_tunnel'
    local action = http.formvalue('action')
    local message, failed
    http.header('Cache-Control', 'no-store')
    if action == 'add_link' then
        local ok,err=model.add_link(http.formvalue('connection_link'))
        message=ok and 'Connection added to your list.' or err;failed=not ok
    elseif action == 'test_all' or action == 'test_node' then
        local index=action=='test_node' and tonumber(http.formvalue('connection')) or nil
        local ok,err=model.start_tests(index, action=='test_node')
        message=ok and 'Connection testing started. Results appear below.' or err;failed=not ok
    elseif action == 'retry' then
        local count,err=model.retry_import();message=count and ('Imported '..count..' connections.') or err;failed=not count
    elseif action == 'cancel_import' then
        model.cancel_import();message='Pending URL removed.'
    elseif action == 'import' then
        local count, err = model.import_subscription(http.formvalue('subscription'))
        message = count and ('Imported ' .. count .. ' connections. Choose one below.') or err
        failed = not count
    elseif action == 'select' then
        local ok, err = model.select(tonumber(http.formvalue('connection')))
        message = ok and 'Connection saved and configuration checked. Network routing is still off.' or err
        failed = not ok
    elseif action == 'enable' or action == 'disable' then
        local ok = false
        if action ~= 'enable' or model.summary().ready then
            ok = os.execute('/usr/libexec/home-tunnel-control '..action..' >/dev/null 2>&1') == 0
        end
        if ok then
            message = action == 'enable' and 'Whole-network tunnel enabled. The connection is starting.' or 'Tunnel disabled. Normal internet restored.'
        elseif action == 'disable' then
            message = 'The tunnel could not be fully disabled. Check the router service status before continuing.'
        elseif not model.summary().ready then
            message = 'Whole-network mode is not ready to enable. Connection and routing verification must finish first.'
        else
            message = 'The tunnel could not be enabled. Check the selected connection and router service status.'
        end
        failed = not ok
    elseif action == 'test' then
        local ok = os.execute('/usr/libexec/home-tunnel-probe >/dev/null 2>&1') == 0
        message = ok and 'HTTPS connection through the selected proxy passed. Whole-network routing is still off.' or 'The proxy test failed. Try a different connection or check your subscription.'
        failed = not ok
    end
    luci.template.render('home/tunnel', {data=model.summary(), message=message, failed=failed, starting=action=='enable' and not failed})
end

function tunnel_status()
    luci.http.header('Cache-Control','no-store')
    luci.http.write_json(require('luci.model.home_tunnel').summary())
end

function page(name)
    local allowed = {overview=true, wifi=true, devices=true, internet=true, settings=true}
    if not allowed[name] then return end
    luci.http.header('Cache-Control', 'no-store')
    local data = require('luci.model.home').snapshot(name ~= 'settings')
    if name == 'overview' or name == 'internet' then
        data.modem = require('luci.model.home_modem').read()
    end
    luci.template.render('home/page', {page=name, data=data})
end

function telemetry()
    luci.http.header('Cache-Control', 'no-store')
    luci.http.write_json(require('luci.model.home').snapshot(false))
end
