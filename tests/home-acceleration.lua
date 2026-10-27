local m=assert(loadfile(arg[1]))()
local j=require 'luci.jsonc'
local function clone(x) return j.parse(j.stringify(x)) end
local function fixture()
 local f={rows={{index=1,name='eth0',mode='HW_fast'},{index=4,name='ra0',mode='HW_fast'},{index=41,name='ccmni1',mode='HW_fast'}},calls={}}
 local ops={
  lan=function()return {eth0=true,ra0=true}end,
  snapshot=function()return clone(f.rows)end,
  load=function()return f.saved and clone(f.saved)end,
  save=function(value)f.saved=clone(value);f.calls[#f.calls+1]='save'end,
  clear=function()f.saved=nil;f.calls[#f.calls+1]='clear'end,
  exists=function()return true end,
  unregister=function(name)
   assert(f.saved,'Journal must precede driver changes')
   assert(name~='ccmni1','Cellular registration must remain intact')
   f.calls[#f.calls+1]='remove '..name
   if f.fail_remove==name then error('simulated driver failure') end
   for i,row in ipairs(f.rows)do if row.name==name then table.remove(f.rows,i);return end end
  end,
  register=function(name)
   assert(name~='ccmni1');f.calls[#f.calls+1]='restore '..name
   f.rows[#f.rows+1]={index=name=='eth0' and 1 or 4,name=name,mode='HW_fast'}
  end}
 f.engine=m.new(ops);return f
end
local f=fixture()
assert(not pcall(f.engine.verify));assert(f.engine.off())
assert(#f.rows==1 and f.rows[1].name=='ccmni1')
assert(f.calls[1]=='save' and f.calls[2]=='remove eth0')
assert(f.engine.off());assert(#f.saved.records==2)
assert(f.engine.restore());assert(not f.saved and #f.rows==3)
assert(f.rows[1].name=='ccmni1');assert(f.engine.restore())
f=fixture();f.rows[2].mode='SW_fast'
assert(not pcall(f.engine.off));assert(#f.calls==0 and #f.rows==3)
f=fixture();f.fail_remove='ra0'
assert(not pcall(f.engine.off));assert(#f.saved.records==2 and #f.rows==2)
assert(f.engine.restore());assert(#f.rows==3 and not f.saved)
f=fixture();assert(f.engine.off())
f.rows[#f.rows+1]={index=8,name='ra0',mode='HW_fast'}
assert(not pcall(f.engine.restore));assert(f.saved,'Failed restore must retain its journal')
assert(f.rows[2].name=='ra0' and f.rows[2].index==8,'Foreign registration must not be overwritten')
print('PASS: native acceleration journaling, idempotence, cellular preservation, unsupported modes, partial failure and conflicting restoration')
