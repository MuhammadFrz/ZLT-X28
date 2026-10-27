module('luci.controller.home_ikev2',package.seeall)

function index()
    entry({'admin','vpn','ikev2'},post_on({action=true},'page'),_('IKEV2'),19).leaf=true
    entry({'admin','vpn','ikev2_status'},call('status')).leaf=true
end

function status()
    luci.http.header('Cache-Control','no-store')
    luci.http.write_json(require('luci.model.home_ikev2').summary())
end

function page()
    local http=luci.http
    local model=require 'luci.model.home_ikev2'
    http.header('Cache-Control','no-store')
    local message,failed
    if http.formvalue('action')=='save' then
        local ok,err=model.save(http.formvalue('server'),http.formvalue('username'),http.formvalue('password'),http.formvalue('certificate'),http.formvalue('label'),http.formvalue('identity'))
        failed=not ok
        message=ok and 'IKEv2 profile added privately. Your selection and network connection are unchanged.' or err
    elseif http.formvalue('action')=='select' then
        local ok,err=model.select(tonumber(http.formvalue('profile')))
        failed=not ok
        message=ok and 'Profile selected. No connection has been started.' or err
    elseif http.formvalue('action')=='enable' or http.formvalue('action')=='disable' then
        local action=http.formvalue('action')
        local ok=false
        if action=='disable' or model.summary().ready then
            ok=os.execute('/usr/libexec/home-ikev2-control '..action..' >/dev/null 2>&1')==0
        end
        failed=not ok
        message=ok and (action=='enable' and 'IKEv2 enabled. Connecting; internet stays blocked until the tunnel is ready.' or 'IKEv2 disabled. Normal internet restored.') or
            'The change did not complete. Check the connection status; use Disable to restore normal internet if protection is enabled.'
    end
    luci.template.render('home/ikev2',{data=model.summary(),message=message,failed=failed})
end
