local fs=require 'nixio.fs'
local j=require 'luci.jsonc'
local m=require 'luci.model.home_tunnel'
local base='/data/home-tunnel'
local pid
local function save(results)
    m.write_private(base..'/test-results.new',j.stringify(results))
    assert(fs.rename(base..'/test-results.new',base..'/test-results.json'))
end
local results=j.parse(fs.readfile(base..'/test-results.json') or '') or {nodes={},done=0,total=0}
local ok=xpcall(function()
    local s=m.state()
    local queue=assert(j.parse(fs.readfile(base..'/test-queue.json')))
    m.write_private(base..'/test-runtime.json',j.stringify(m.test_config(s)))
    assert(os.execute('/data/home-tunnel/bin/sing-box check -c /data/home-tunnel/test-runtime.json >/dev/null 2>&1')==0)
    local pipe=assert(io.popen('umask 077; /data/home-tunnel/bin/sing-box run -c /data/home-tunnel/test-runtime.json >/data/home-tunnel/tests.log 2>&1 & echo $!'))
    pid=assert(tonumber(pipe:read('*l')));pipe:close()
    os.execute('sleep 1')
    for _,index in ipairs(queue) do
        results.nodes[tostring(index)]={status='testing'};save(results)
        local cmd="curl --noproxy '' --socks5-hostname 127.0.0.1:"..(12080+index)..
          " -fLsS --connect-timeout 5 --max-time 8 -o /dev/null -w '%{time_total}' https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null; echo :$?"
        local p=assert(io.popen(cmd));local output=p:read('*a');p:close()
        local elapsed,exit=output:match('([%d.]+):(%d+)')
        local value=tonumber(elapsed)
        if exit=='0' and value and value>0 then
            results.nodes[tostring(index)]={status='ok',latency_ms=math.floor(value*1000+0.5),checked_at=os.time()}
        else
            results.nodes[tostring(index)]={status=exit=='28' and 'timeout' or 'failed',checked_at=os.time()}
        end
        results.done=results.done+1;save(results)
    end
end,function() return 'Connection-test job failed' end)
if pid then os.execute('kill '..pid..' 2>/dev/null') end
if not ok then
    for _,v in pairs(results.nodes or {}) do if v.status=='queued' or v.status=='testing' then v.status='failed' end end
end
results.running=false;results.finished_at=os.time();save(results)
fs.remove(base..'/test-runtime.json');fs.remove(base..'/test-queue.json')
fs.remove('/tmp/home-tunnel-tests.pid');fs.rmdir('/tmp/home-tunnel-tests.lock')
