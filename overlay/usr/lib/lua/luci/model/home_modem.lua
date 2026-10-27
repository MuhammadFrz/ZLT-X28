local util = require 'luci.util'
local json = require 'luci.jsonc'
local M = {}

local function text(value)
    if type(value) ~= 'string' or #value > 96 then return nil end
    value = value:gsub('%c', '')
    return #value > 0 and value or nil
end

local function metric(value, low, high)
    local n = tonumber(value)
    if n and n == n and n >= low and n <= high then return n end
end

function M.normalize(raw)
    if type(raw) ~= 'table' or raw.success ~= true then
        return {available=false}
    end
    return {available=true, network_type=text(raw.network_type_str), operator=text(raw.network_operator),
        band_lte=text(raw.currentband), band_nr=text(raw.currentband_5g),
        lte={rsrp=metric(raw.RSRP,-200,0), rsrq=metric(raw.RSRQ,-100,0), sinr=metric(raw.SINR,-100,100)},
        nr={rsrp=metric(raw.RSRP_5G,-200,0), rsrq=metric(raw.RSRQ_5G,-100,0), sinr=metric(raw.SINR_5G,-100,100)}}
end

function M.read()
    -- Fixed read-only command traced to the stock UI; never accept a caller-supplied command or URL.
    local command = [[/usr/bin/curl -fsS --noproxy '*' --connect-timeout 1 --max-time 2 -H 'Content-Type: application/json' ]]
        .. [[--data '{"cmd":205,"method":"GET","language":"EN","sessionId":""}' http://192.168.70.1/cgi-bin/http.cgi 2>/dev/null]]
    local ok, raw = pcall(json.parse, util.exec(command) or '')
    local out = M.normalize(ok and raw or nil)
    out.observed_at = os.time()
    return out
end

return M
