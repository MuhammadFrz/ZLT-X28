package.loaded['luci.util']={}
package.loaded['luci.jsonc']={}
local model=assert(loadfile(arg[1]))()
assert(model.normalize(nil).available==false)
assert(model.normalize({success=false,message='NO_AUTH'}).available==false)
local raw={success=true,network_type_str='4G',network_operator='<Carrier>',RSRP='-72',RSRQ='-7',SINR='24',
 RSRP_5G='',RSRQ_5G='-256',SINR_5G='nan',currentband='1+3',currentband_5g='',IMSI='private',CELL_ID='private',token='private'}
local out=model.normalize(raw)
assert(out.available and out.lte.rsrp==-72 and out.lte.rsrq==-7 and out.lte.sinr==24)
assert(out.nr.rsrp==nil and out.nr.rsrq==nil and out.nr.sinr==nil)
assert(out.operator=='<Carrier>' and out.band_lte=='1+3')
assert(out.IMSI==nil and out.CELL_ID==nil and out.token==nil)
raw.SINR='0'
assert(model.normalize(raw).lte.sinr==0)
raw.network_operator=string.rep('x',100)
assert(model.normalize(raw).operator==nil)
print('PASS: modem normalization, zero values, sentinels, missing/auth failure, sensitive-field exclusion')
