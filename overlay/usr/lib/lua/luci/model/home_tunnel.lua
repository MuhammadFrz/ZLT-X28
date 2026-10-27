local M = {}
local json = require 'luci.jsonc'
local fs = require 'nixio.fs'
local nixio = require 'nixio'
local util = require 'luci.util'
local base = '/data/home-tunnel'

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
local function unescape(s)
    return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end
local function decode64(s)
    s = s:gsub('%s', ''):gsub('-', '+'):gsub('_', '/')
    if s:find('[^%w+/=]') then error('Invalid base64 data') end
    s = s .. string.rep('=', (4 - #s % 4) % 4)
    return assert(nixio.bin.b64decode(s), 'Invalid base64 data')
end
local function scalar(s, name)
    if type(s) ~= 'string' or #s == 0 or #s > 2048 or s:find('%c') then
        error('Missing or invalid ' .. name)
    end
    return s
end
local function hostport(s)
    local host, port = s:match('^%[([^%]]+)%]:(%d+)$')
    if not host then host, port = s:match('^([^:]+):(%d+)$') end
    port = tonumber(port)
    if not host or not port or port < 1 or port > 65535 then error('Invalid server address or port') end
    scalar(host, 'server')
    if host:find('[%s/@?#]') then error('Invalid server address') end
    return host, port
end
local function query(s)
    local q = {}
    for part in (s or ''):gmatch('[^&]+') do
        local k, v = part:match('^([^=]+)=(.*)$')
        if k then
            k, v = unescape(k), unescape(v)
            if q[k] then error('Duplicate connection parameter') end
            q[k] = v
        end
    end
    return q
end
local function transport(kind, path, host, service)
    if not kind or kind == '' or kind == 'tcp' or kind == 'raw' or kind == 'none' then return nil end
    if kind == 'ws' then
        if (path or ''):find('%?ed=') then error('WebSocket early-data links require manual configuration') end
        return {type='ws', path=path ~= '' and path or '/', headers=host and host ~= '' and {Host=host} or nil}
    elseif kind == 'grpc' then
        return {type='grpc', service_name=service or ''}
    elseif kind == 'httpupgrade' then
        return {type='httpupgrade', path=path or '/', host=host}
    end
    error('Unsupported transport: ' .. tostring(kind))
end
local function tls(q, forced)
    local security = q.security or (forced and 'tls' or 'none')
    if q.allowInsecure == '1' or q.insecure == '1' then error('Insecure TLS links are not accepted') end
    if security == 'none' or security == '' then return nil end
    if security ~= 'tls' and security ~= 'reality' then error('Unsupported connection security') end
    local t = {enabled=true, server_name=q.sni or q.serverName}
    if q.alpn and q.alpn ~= '' then
        t.alpn = {}
        for a in q.alpn:gmatch('[^,]+') do t.alpn[#t.alpn+1] = a end
    end
    if q.fp and q.fp ~= '' then t.utls={enabled=true, fingerprint=q.fp} end
    if security == 'reality' then
        t.utls = t.utls or {enabled=true, fingerprint='chrome'}
        t.reality = {enabled=true, public_key=scalar(q.pbk, 'Reality public key'), short_id=q.sid or ''}
    end
    return t
end

function M.parse_link(link)
    link = trim(link)
    local scheme, rest = link:match('^(%w+)://(.+)$')
    if not scheme then error('Expected a connection link') end
    local body, label = rest:match('^(.-)#(.*)$')
    rest = body or rest
    label = label and unescape(label) or scheme:upper()
    label = label:gsub('%c', ' '):sub(1, 120)
    local o
    if scheme == 'vmess' then
        local v = json.parse(decode64(rest))
        if type(v) ~= 'table' then error('Invalid VMess JSON') end
        local port = tonumber(v.port)
        if not port or port < 1 or port > 65535 then error('Invalid VMess port') end
        o = {type='vmess', server=scalar(v.add, 'server'), server_port=port,
             uuid=scalar(v.id, 'UUID'), security=v.scy or 'auto', alter_id=tonumber(v.aid) or 0}
        if v.type and v.type ~= '' and v.type ~= 'none' then error('Unsupported VMess header type') end
        o.transport = transport(v.net, v.path, v.host, v.path)
        o.tls = tls({security=v.tls == 'tls' and 'tls' or 'none', sni=v.sni or v.host, alpn=v.alpn, fp=v.fp})
        label = (type(v.ps) == 'string' and v.ps ~= '' and v.ps or label):gsub('%c',' '):sub(1,120)
    elseif scheme == 'vless' or scheme == 'trojan' or scheme == 'ss' then
        local main, args = rest:match('^(.-)%?(.*)$')
        main = main or rest
        local q = query(args)
        if scheme == 'ss' and not main:find('@',1,true) then main = decode64(main) end
        local user, address = main:match('^(.*)@([^@]+)$')
        if not user then error('Missing connection credentials') end
        address = address:gsub('/$', '')
        local host, port = hostport(address)
        o = {type=scheme == 'ss' and 'shadowsocks' or scheme, server=host, server_port=port}
        if scheme == 'ss' then
            if q.plugin and q.plugin ~= '' then error('Shadowsocks plugins require manual configuration') end
            user = unescape(user)
            if not user:find(':',1,true) then user = decode64(user) end
            o.method, o.password = user:match('^([^:]+):(.*)$')
            scalar(o.method, 'Shadowsocks method'); scalar(o.password, 'Shadowsocks password')
        else
            if scheme == 'vless' then
                o.uuid = scalar(unescape(user), 'UUID')
                if q.encryption and q.encryption ~= 'none' then error('Unsupported VLESS encryption') end
                if q.flow and q.flow ~= '' then o.flow = q.flow end
            else o.password = scalar(unescape(user), 'Trojan password') end
            if q.headerType and q.headerType ~= '' and q.headerType ~= 'none' then error('Unsupported TCP header type') end
            o.transport = transport(q.type, q.path, q.host, q.serviceName)
            o.tls = tls(q, scheme == 'trojan')
        end
    else error('Unsupported connection protocol') end
    return {label=label, outbound=o}
end

function M.parse_subscription(body)
    if type(body) ~= 'string' or #body > 1048576 then error('Subscription is too large') end
    body = trim(body)
    if not body:find('://',1,true) then body = decode64(body) end
    local nodes, skipped = {}, 0
    for line in body:gmatch('[^\r\n]+') do
        if #nodes >= 128 then error('Subscription contains too many connections') end
        if trim(line) ~= '' then
            local ok, node = pcall(M.parse_link, line)
            if ok then nodes[#nodes+1] = node else skipped = skipped + 1 end
        end
    end
    if #nodes == 0 then error('No supported connection links found. Export a standard V2Ray subscription, not Clash YAML or a web page.') end
    return nodes, skipped
end

function M.config(outbound, test)
    -- The imported links supply one outbound only; routes and DNS stay under our control.
    local o = json.parse(json.stringify(outbound))
    local cached = json.parse(fs.readfile(base .. '/server-address.json') or '')
    if cached and cached.hostname == o.server and type(cached.address) == 'string' then
        if o.tls and not o.tls.server_name then o.tls.server_name = o.server end
        o.server = cached.address
    end
    o.tag = 'proxy'
    o.domain_resolver = 'bootstrap'
    local inbounds = {{type='mixed', tag='probe', listen='127.0.0.1', listen_port=10880}}
    if not test then
        inbounds[#inbounds+1] = {type='tun', tag='lan-tun', interface_name='x28tun',
            address={'172.31.255.1/30'}, mtu=1400, auto_route=false, stack='gvisor'}
    end
    return {log={level='error', timestamp=true},
        dns={servers={{type='tcp', tag='tunnel-dns', server='8.8.8.8', detour='proxy'},
                     {type='udp', server='8.8.8.8', tag='bootstrap'}}, final='tunnel-dns', strategy='ipv4_only'},
        inbounds=inbounds, outbounds={o},
        route={rules={{inbound={'lan-tun'}, port={53}, action='hijack-dns'}}, final='proxy'}}
end

local function write_private(path, data)
    local f = assert(nixio.open(path, 'w', '600'), 'Could not create private configuration')
    fs.chmod(path, '600')
    assert(f:writeall(data)); f:close()
end

function M.write_private(path, data) write_private(path, data) end

function M.save_state(state)
    write_private(base .. '/subscription.new', json.stringify(state))
    assert(fs.rename(base .. '/subscription.new', base .. '/subscription.json'))
end

function M.state()
    local s = json.parse(fs.readfile(base .. '/subscription.json') or '')
    if type(s) ~= 'table' or type(s.nodes) ~= 'table' then return {nodes={}} end
    return s
end

function M.add_link(link)
    if fs.access(base .. '/enabled') or fs.access('/tmp/home-tunnel-tests.lock') then
        return nil, 'Wait for testing to finish or disable the tunnel before importing.'
    end
    if type(link) ~= 'string' or #link > 16384 then return nil, 'Enter a connection link.' end
    local ok, node = pcall(M.parse_link, link)
    if not ok then return nil, tostring(node):gsub('^.-:%d+: ', '') end
    local s = M.state()
    if #s.nodes >= 128 then return nil, 'The connection list is full.' end
    node.source = 'Manual'
    s.nodes[#s.nodes+1] = node
    M.save_state(s)
    return true
end

function M.start_tests(index, single)
    local s = M.state()
    if single and not index then return nil, 'Unknown connection.' end
    if #s.nodes == 0 then return nil, 'Import connections first.' end
    if index and (index % 1 ~= 0 or not s.nodes[index]) then return nil, 'Unknown connection.' end
    if not fs.mkdir('/tmp/home-tunnel-tests.lock', '700') then return nil, 'Connection testing is already running.' end
    local queue = {}
    for i in ipairs(s.nodes) do if not index or index == i then queue[#queue+1] = i end end
    write_private(base .. '/test-queue.json', json.stringify(queue))
    local previous = json.parse(fs.readfile(base .. '/test-results.json') or '') or {}
    previous.running=true;previous.done=0;previous.total=#queue;previous.started_at=os.time();previous.nodes=previous.nodes or {}
    for _,i in ipairs(queue) do previous.nodes[tostring(i)]={status='queued'} end
    write_private(base .. '/test-results.json', json.stringify(previous))
    os.execute('umask 077; lua /usr/libexec/home-tunnel-tests.lua >/dev/null 2>&1 & echo $! >/tmp/home-tunnel-tests.pid')
    return true
end

function M.test_config(s)
    local c = M.config(s.nodes[1].outbound, true)
    c.inbounds={};c.outbounds={};c.route={rules={}}
    c.dns={servers={{type='udp',tag='bootstrap',server='8.8.8.8'}},final='bootstrap',strategy='ipv4_only'}
    for i,node in ipairs(s.nodes) do
        local o=M.config(node.outbound,true).outbounds[1]
        o.tag='node-'..i
        c.outbounds[#c.outbounds+1]=o
        c.inbounds[#c.inbounds+1]={type='mixed',tag='test-'..i,listen='127.0.0.1',listen_port=12080+i}
        c.route.rules[#c.route.rules+1]={inbound={'test-'..i},action='route',outbound=o.tag}
    end
    return c
end

function M.import_subscription(url)
    if fs.access(base .. '/enabled') then return nil, 'Disable whole-network mode before replacing connections.' end
    if fs.access('/tmp/home-tunnel-tests.lock') then return nil, 'Wait for connection testing to finish before importing.' end
    if type(url) ~= 'string' or #url > 4096 or url:find('[%c%s]') or not url:match('^https://[^/]+') then
        return nil, 'Enter an HTTPS subscription URL.'
    end
    if not fs.mkdir(base .. '/import.lock', '700') then return nil, 'Another import is running. Try again shortly.' end
    local ok, result = pcall(function()
        local escaped = url:gsub('\\','\\\\'):gsub('"','\\"')
        write_private(base .. '/fetch.conf', 'url = "' .. escaped .. '"\n')
        local cmd = "umask 077; curl --noproxy '*' --proto '=https' --proto-redir '=https' -fLsS " ..
          "--max-redirs 2 --connect-timeout 8 --max-time 20 --max-filesize 1048576 " ..
          "-A 'v2rayNG' -K /data/home-tunnel/fetch.conf -o /data/home-tunnel/subscription.download 2>/dev/null"
        local code=os.execute(cmd)
        if code ~= 0 then
            write_private(base .. '/pending-import-time', tostring(os.time()))
            local exit=math.floor(code/256)
            local reasons={[6]='DNS resolution failed',[7]='Provider connection failed',[22]='Provider returned an HTTP error',[28]='Download timed out',[35]='TLS handshake failed',[60]='TLS certificate verification failed'}
            error((reasons[exit] or 'Subscription download failed')..'. The URL is held privately for retry; cancel to remove it.')
        end
        local nodes, skipped = M.parse_subscription(fs.readfile(base .. '/subscription.download'))
        local state=M.state()
        local source='Subscription '..tostring((state.source_count or 0)+1)
        if #state.nodes+#nodes>128 then error('Import would exceed 128 connections') end
        for _,node in ipairs(nodes) do node.source=source;state.nodes[#state.nodes+1]=node end
        state.source_count=(state.source_count or 0)+1;state.skipped=skipped;state.imported_at=os.time()
        M.save_state(state)
        -- Do not persist the subscription URL or echo it in the response.
        return #nodes
    end)
    if ok then fs.remove(base .. '/fetch.conf'); fs.remove(base .. '/pending-import-time') end
    fs.remove(base .. '/subscription.download')
    fs.remove(base .. '/subscription.new'); fs.rmdir(base .. '/import.lock')
    if ok then return result end
    -- Parser errors contain no raw credentials; strip source location from user-facing messages.
    return nil, tostring(result):gsub('^.-:%d+: ', '')
end

function M.retry_import()
    local cfg=fs.readfile(base .. '/fetch.conf') or ''
    local quoted=cfg:match('url = ("[^\n]+")')
    local url=quoted and json.parse(quoted)
    if type(url)~='string' then return nil,'No pending import. Enter the URL again.' end
    return M.import_subscription(url)
end

function M.cancel_import()
    fs.remove(base .. '/fetch.conf');fs.remove(base .. '/pending-import-time')
end

function M.select(index)
    if fs.access(base .. '/enabled') or fs.access(base .. '/probe.lock') or fs.access(base .. '/import.lock') then
        return nil, 'Wait for the current operation or disable whole-network mode first.'
    end
    local s = M.state()
    local node = s.nodes[index]
    if not node then return nil, 'Select a connection from the imported subscription.' end
    write_private(base .. '/probe.new', json.stringify(M.config(node.outbound, true)))
    local checked = os.execute('/data/home-tunnel/bin/sing-box check -c /data/home-tunnel/probe.new >/dev/null 2>&1') == 0
    if not checked then fs.remove(base .. '/probe.new'); return nil, 'This connection uses options the installed client does not accept.' end
    assert(fs.rename(base .. '/probe.new', base .. '/probe.json'))
    write_private(base .. '/config.json', json.stringify(M.config(node.outbound, false)))
    write_private(base .. '/selected.json', json.stringify({index=index, label=node.label, type=node.outbound.type}))
    return true
end

function M.summary()
    local s = M.state()
    local pending_at=tonumber(fs.readfile(base .. '/pending-import-time') or '')
    if pending_at and os.time()-pending_at>1800 then M.cancel_import();pending_at=nil end
    local result = {nodes={}, skipped=s.skipped or 0, imported_at=s.imported_at,
        ready=(fs.readfile(base .. '/routing-verified') or ''):match('^native%-allowlist%-v1\n') ~= nil, pending=pending_at ~= nil, runtime=fs.access(base .. '/bin/sing-box'), enabled=fs.access(base .. '/enabled')}
    local test = json.parse(fs.readfile(base .. '/test-results.json') or '') or {nodes={}}
    test.running = fs.access('/tmp/home-tunnel-tests.lock') and true or false
    result.tests={running=test.running,done=test.done or 0,total=test.total or 0}
    for i,n in ipairs(s.nodes) do
        result.nodes[#result.nodes+1]={index=i,label=n.label,type=n.outbound.type,source=n.source or 'Subscription',test=(test.nodes or {})[tostring(i)]}
    end
    local pid = tonumber(fs.readfile('/tmp/home-tunnel.pid') or '')
    result.running = pid and (fs.readfile('/proc/'..pid..'/comm') or ''):match('^sing%-box') ~= nil or false
    result.selected = json.parse(fs.readfile(base .. '/selected.json') or '')
    return result
end

return M
