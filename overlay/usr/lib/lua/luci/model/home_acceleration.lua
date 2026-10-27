local fs=require 'nixio.fs'
local n=require 'nixio'
local json=require 'luci.jsonc'
local M={}

-- Keep the transaction logic testable without touching a real driver.
function M.new(ops)
 local api={}
 local function valid(row)
  assert(type(row.name)=='string' and row.name:match('^[%w_.%-]+$') and #row.name<=15,'Invalid interface name')
  assert(type(row.index)=='number' and row.index>=0 and row.index<64,'Invalid acceleration index')
 end
 function api.verify()
  local lan=ops.lan()
  for _,row in ipairs(ops.snapshot()) do
   valid(row)
   assert(not lan[row.name],'LAN acceleration is still registered')
  end
  return true
 end
 function api.off()
  local lan=ops.lan()
  local current=ops.snapshot()
  local journal=ops.load() or {version=1,records={}}
  assert(journal.version==1 and type(journal.records)=='table','Invalid acceleration journal')
  local owned={}
  for _,row in ipairs(journal.records) do valid(row);owned[row.name]=row end
  local selected={}
  for _,row in ipairs(current) do
   valid(row)
   if lan[row.name] then
    assert(not row.name:match('^ccmni'),'Refusing to unregister the cellular interface')
    assert(row.mode=='HW_fast','Unsupported existing acceleration mode')
    assert(not owned[row.name] or owned[row.name].index==row.index,'Interface registration changed')
    selected[#selected+1]=row
   end
  end
  for _,row in ipairs(selected) do
   if not owned[row.name] then
    journal.records[#journal.records+1]=row
    ops.save(journal) -- Journal before changing the driver, including partial failures.
    owned[row.name]=row
   end
   ops.unregister(row.name)
  end
  return api.verify()
 end
 function api.restore()
  local journal=ops.load()
  if not journal then return true end
  assert(journal.version==1 and type(journal.records)=='table','Invalid acceleration journal')
  local current={}
  for _,row in ipairs(ops.snapshot()) do valid(row);current[row.name]=row end
  for _,row in ipairs(journal.records) do
   valid(row)
   assert(row.mode=='HW_fast','Unsupported saved acceleration mode')
   if current[row.name] then
    assert(current[row.name].index==row.index and current[row.name].mode==row.mode,'Existing registration differs')
   elseif ops.exists(row.name) then
    ops.register(row.name)
   end
  end
  local after={}
  for _,row in ipairs(ops.snapshot()) do valid(row);after[row.name]=row end
  for _,row in ipairs(journal.records) do
   if ops.exists(row.name) then
    assert(after[row.name] and after[row.name].index==row.index and after[row.name].mode==row.mode,'Acceleration restoration not verified')
   end
  end
  ops.clear()
  return true
 end
 return api
end

local base='/data/home-tunnel'
local journal_path=base..'/acceleration-journal.json'
local serial=0
local function write(path,value)
 local f=assert(io.open(path,'w'),'Cannot open native acceleration control')
 assert(f:write(value));assert(f:close())
end
local function snapshot()
 assert(fs.access('/proc/hnat/hnat_whitelist') and fs.access('/proc/hnat/hnat_type'),'Unsupported acceleration backend')
 serial=serial+1
 local tag='X28_ACCEL_'..n.getpid()..'_'..serial
 write('/dev/kmsg','<6>'..tag..'_BEGIN\n')
 local f=assert(io.open('/proc/hnat/hnat_whitelist'));assert(f:read('*a')~=nil);assert(f:close())
 f=assert(io.open('/proc/hnat/hnat_type'));assert(f:read('*a')~=nil);assert(f:close())
 write('/dev/kmsg','<6>'..tag..'_END\n')
 local p=assert(io.popen('dmesg'))
 local begun,ended=false,false
 local rows,modes={},{}
 for line in p:lines() do
  if line:find(tag..'_BEGIN',1,true) then begun=true
  elseif begun and line:find(tag..'_END',1,true) then ended=true;break
  elseif begun then
   local index,name=line:match('dst_port%[(%d+)%] = ([%w_.%-]+)')
   if index then rows[#rows+1]={index=tonumber(index),name=name} end
   local iface,mode=line:match('([%w_.%-]+) %-%> ([%w_]+)')
   if iface then modes[iface]=mode end
  end
 end
 p:close()
 assert(begun and ended and #rows>0,'Incomplete acceleration snapshot')
 local indices,names={},{}
 for _,row in ipairs(rows) do
  assert(not indices[row.index] and not names[row.name],'Ambiguous acceleration snapshot')
  indices[row.index]=true;names[row.name]=true
  row.mode=modes[row.name]
  assert(row.mode=='HW_fast' or row.mode=='SW_fast','Incomplete acceleration modes')
 end
 return rows
end
local function lan()
 local result={}
 for name in assert(fs.dir('/sys/class/net/br0/brif'),'LAN bridge is not ready') do
  if name~='.' and name~='..' then
   result[name]=true
   local parent=name:match('^[^.]+');assert(parent,'Unsupported bridge interface')
   result[parent]=true
  end -- Vendor LAN VLANs share the physical Ethernet parent.
 end
 assert(next(result),'LAN bridge has no members')
 return result
end
local ops={snapshot=snapshot,lan=lan,
 load=function()
  local text=fs.readfile(journal_path)
  if not text then return nil end
  return assert(json.parse(text),'Unreadable acceleration journal')
 end,
 save=function(value)
  local temp=journal_path..'.new'
  local text=json.stringify(value)
  local f=assert(n.open(temp,'w','600'))
  assert(f:write(text)==#text);assert(f:sync());assert(f:close())
  assert(fs.rename(temp,journal_path))
 end,
 clear=function() assert(fs.remove(journal_path)) end,
 exists=function(name) return fs.access('/sys/class/net/'..name) end,
 unregister=function(name) write('/proc/hnat/hnat_whitelist','2 '..name..'\n') end,
 register=function(name) write('/proc/hnat/hnat_whitelist','1 '..name..'\n') end}
local engine=M.new(ops)
for _,name in ipairs({'off','verify','restore'}) do
 local operation=name
 M[name]=function()
  local lock=assert(n.open('/tmp/home-tunnel-accel.lock','a','600'))
  assert(lock:lock('tlock'),'Acceleration operation is already running')
  local ok,result=pcall(engine[operation])
  lock:close()
  if not ok then error(result,0) end
  return result
 end
end
return M
