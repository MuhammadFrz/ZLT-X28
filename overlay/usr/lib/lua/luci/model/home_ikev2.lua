local M = {}
local fs = require 'nixio.fs'
local nixio = require 'nixio'
local json = require 'luci.jsonc'
local util = require 'luci.util'
local ip = require 'luci.ip'
local base = '/data/home-ikev2'

local function hostname(server)
    if #server>253 or not server:match('^[a-z0-9][a-z0-9%.%-]*%.surfshark%.com$') or server:find('%.%.') then return false end
    for label in server:gmatch('[^.]+') do
        if #label>63 or label:match('^%-') or label:match('%-$') then return false end
    end
    return true
end

function M.validate(server, username, password, certificate, identity)
    server = type(server)=='string' and server:lower():gsub('^%s+',''):gsub('%s+$','') or ''
    identity = type(identity)=='string' and identity:lower():gsub('^%s+',''):gsub('%s+$','') or ''
    local address=not server:find('[^a-f0-9:.]') and ip.new(server) or nil
    if address then
        if not hostname(identity) then return nil,'When using a server IP, enter its provider certificate hostname too.' end
    elseif hostname(server) then
        if identity~='' and identity~=server then return nil,'For a hostname connection, use that same hostname for certificate verification.' end
        identity=server
    else
        return nil,'Enter a valid supported server hostname or IPv4/IPv6 address, without a URL, port or subnet.'
    end
    for label,value in pairs({username=username or '', password=password or ''}) do
        if type(value)~='string' or #value<1 or #value>512 or value:find('%c') then
            return nil, 'Enter a valid manual-service '..label..'.'
        end
    end
    certificate = type(certificate)=='string' and certificate:gsub('\r\n','\n'):gsub('^%s+',''):gsub('%s+$','') or ''
    if #certificate>32768 or not certificate:match('^%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-\n[A-Za-z0-9+/=\n]+\n%-%-%-%-%-END CERTIFICATE%-%-%-%-%-$') then
        return nil, 'Paste the PEM CA certificate downloaded from your provider’s IKEV2 manual setup.'
    end
    return {server=server, identity=identity, username=username, password=password, certificate=certificate..'\n'}
end

local function store()
    local raw=fs.readfile(base..'/profiles.json')
    if raw then
        local saved=json.parse(raw)
        if type(saved)~='table' or type(saved.profiles)~='table' then return nil,'Saved IKEv2 profiles could not be read. Existing files were retained.' end
        return saved
    end
    local legacy=json.parse(fs.readfile(base..'/profile.json') or '')
    if type(legacy)=='table' and legacy.server and legacy.username and legacy.password and legacy.certificate then
        legacy.label=legacy.server
        return {profiles={legacy},selected=1}
    end
    return {profiles={}}
end

function M.summary()
    local saved,err=store()
    local result={prepared=fs.access(base..'/runtime-verified') and true or false,profiles={},error=err}
    result.enabled=fs.access(base..'/enabled') and true or false
    result.cleanup_pending=not result.enabled and (fs.access(base..'/routing-owned') or fs.access(base..'/xfrm-cleanup-pending')) and true or false
    result.ready=(fs.readfile(base..'/routing-verified') or ''):match('^native%-xfrm%-v1\n?$')~=nil
    local pid=(fs.readfile(base..'/control/daemon.pid') or ''):match('^(%d+)%s*$')
    local heartbeat=tonumber(fs.readfile(base..'/control/heartbeat') or '')
    local age=heartbeat and os.time()-heartbeat
    result.running=result.enabled and fs.access(base..'/control/attached') and pid~=nil and
        fs.readlink('/proc/'..pid..'/exe')==base..'/bin/charon' and age~=nil and age>=0 and age<12 or false
    if saved then
        result.selected=saved.selected
        for i,profile in ipairs(saved.profiles) do
            result.profiles[#result.profiles+1]={index=i,label=profile.label or profile.server,server=profile.server,identity=profile.identity or profile.server}
        end
    end
    return result
end

function M.selected_profile()
    local saved,err=store()
    if not saved then return nil,err end
    local profile=saved.profiles[saved.selected or 0]
    if not profile then return nil,'Choose an IKEv2 profile first.' end
    return M.validate(profile.server,profile.username,profile.password,profile.certificate,profile.identity)
end

function M.test_configuration(profile)
    local p,err=M.validate(profile.server,profile.username,profile.password,profile.certificate,profile.identity)
    if not p then return nil,err end
    local function quote(s)return '"'..s:gsub('\\','\\\\'):gsub('"','\\"')..'"' end
    local hex=p.password:gsub('.',function(c)return string.format('%02x',c:byte()) end)
    return 'connections {\n surfshark {\n version = 2\n remote_addrs = '..p.server..'\n vips = 0.0.0.0\n encap = yes\n'..
        ' local {\n auth = eap-mschapv2\n id = '..quote(p.username)..'\n eap_id = '..quote(p.username)..'\n }\n'..
        ' remote {\n auth = pubkey\n id = '..p.identity..'\n cacerts = '..base..'/check/ca.pem\n }\n'..
        ' children {\n isolated {\n local_ts = dynamic\n remote_ts = 0.0.0.0/0\n if_id_in = 20290\n if_id_out = 20290\n start_action = none\n }\n }\n }\n}\n'..
        'secrets {\n eap-surfshark {\n id = '..quote(p.username)..'\n secret = 0x'..hex..'\n }\n}\n'
end

local function persist(saved)
    local temporary=base..'/profiles.new'
    local file=nixio.open(temporary,'w','600')
    local payload=json.stringify(saved)
    local ok=file and file:writeall(payload)
    if file then file:close() end
    if not ok or not fs.chmod(temporary,'600') or not fs.rename(temporary,base..'/profiles.json') then
        fs.unlink(temporary);return nil,'Could not securely save the IKEv2 settings.'
    end
    return true
end

local function acquire()
    if not fs.mkdirr(base) then return nil,'Could not prepare private storage.' end
    if not fs.chmod(base,'700') then return nil,'Could not protect private storage.' end
    local lock=nixio.open(base..'/profile.lock','w','600')
    if not lock then return nil,'Could not lock private storage.' end
    if not lock:lock('tlock') then lock:close();return nil,'Another settings update is running. Try again.' end
    return lock
end

function M.select(index)
    local operation=nixio.open('/tmp/home-vpn-operation.lock','a','600')
    if not operation or not operation:lock('tlock') then
        if operation then operation:close() end
        return nil,'Another VPN change is in progress. Try again shortly.'
    end
    local lock,err=acquire();if not lock then operation:close();return nil,err end
    local function done(ok,message) lock:close();operation:close();return ok,message end
    if fs.access(base..'/enabled') or fs.access(base..'/routing-owned') then
        return done(nil,'Disable IKEv2 and finish restoring normal internet before selecting another profile.')
    end
    local saved; saved,err=store()
    if not saved then return done(nil,err) end
    if type(index)~='number' or index%1~=0 or not saved.profiles[index] then return done(nil,'Choose an existing IKEv2 profile.') end
    saved.selected=index
    local ok;ok,err=persist(saved);return done(ok,err)
end

function M.save(server, username, password, certificate, label, identity)
    local profile,err=M.validate(server,username,password,certificate,identity)
    if not profile then return nil,err end
    label=label or ''
    if type(label)~='string' or #label>160 or label:find('%c') then return nil,'Use a profile name of up to 160 bytes without control characters.' end
    profile.label=label~='' and label or profile.server
    local lock;lock,err=acquire();if not lock then return nil,err end
    local saved;saved,err=store()
    if not saved then lock:close();return nil,err end
    if #saved.profiles>=32 then lock:close();return nil,'Up to 32 IKEv2 profiles can be saved.' end
    local certpath=base..'/certificate.check'
    local certfile=nixio.open(certpath,'w','600')
    local certok=certfile and certfile:writeall(profile.certificate)
    if certfile then certfile:close() end
    local details=certok and util.exec('/usr/bin/openssl x509 -in '..certpath..' -noout -text 2>/dev/null') or ''
    local current=certok and os.execute('/usr/bin/openssl x509 -in '..certpath..' -noout -checkend 0 >/dev/null 2>&1')==0
    fs.unlink(certpath)
    if not current or not details:find('CA:TRUE',1,true) then
        lock:close();return nil,'The certificate must be a valid, unexpired CA certificate. Download it from your provider’s IKEV2 manual setup.'
    end
    saved.profiles[#saved.profiles+1]=profile
    saved.selected=saved.selected or 1
    local ok;ok,err=persist(saved);lock:close();return ok,err
end

return M
