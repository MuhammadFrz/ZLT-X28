const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=fs.mkdtempSync(path.join(__dirname,'.ike-control-test-')),base=path.join(root,'state'),bin=path.join(root,'bin'),audit=path.join(root,'audit');
fs.mkdirSync(base);fs.mkdirSync(bin);fs.mkdirSync(path.join(base,'tunnel'));fs.mkdirSync(path.join(base,'bin'));
const portable=p=>p.replace(/\\/g,'/').replace(/^([A-Za-z]):/,(_,d)=>'/'+d.toLowerCase());
const original=fs.readFileSync(path.join(__dirname,'../overlay/usr/libexec/home-ikev2-control'),'utf8');
const script=path.join(root,'control.sh');
fs.writeFileSync(script,original.replace('base=/data/home-ikev2','base=${X28_TEST_ROOT:?}').replaceAll('/data/home-tunnel','"$base/tunnel"'));
for(const name of ['ip','iptables','ip6tables','lua','pidof']){
 const body=name==='ip'?`case "$*" in 'rule show') printf '%s\\n' "$X28_POLICY4";; '-6 rule show') printf '%s\\n' "$X28_POLICY6";; 'xfrm state count') echo 'SAD count 0';; 'xfrm policy count') echo 'SPD IN  0 OUT 0 FWD 0';; esac`:
  name==='pidof'?'exit 1':name==='lua'?'exit "${X28_LUA_RESULT:-7}"':`case "$*" in *'-C -t '*|*'-I -t '*) exit 2;;esac;exit 0`;
 fs.writeFileSync(path.join(bin,name),`#!/bin/sh\nprintf '%s\\n' '${name}'" $*" >>"$X28_TEST_AUDIT"\n${body}\n`,{mode:0o700});
}
function run(action,extra={}){
 if(fs.existsSync(audit))fs.unlinkSync(audit);
 const result=cp.spawnSync(process.env.X28_TEST_SHELL||(process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'/bin/sh'),
  ['-c','PATH="$X28_TEST_BIN:$PATH";export PATH;exec sh "$X28_TEST_SCRIPT" "$1"','test',action],{
   encoding:'utf8',env:{...process.env,HOME_VPN_OPERATION_LOCKED:'1',X28_TEST_ROOT:portable(base),X28_TEST_BIN:portable(bin),
    X28_TEST_SCRIPT:portable(script),X28_TEST_AUDIT:portable(audit),X28_POLICY4:'',X28_POLICY6:'',...extra}});
 assert.ifError(result.error);return {result,calls:fs.existsSync(audit)?fs.readFileSync(audit,'utf8').trim().split('\n'):[]};
}
try{
 for(const action of ['enable','trial','guard','attach']){const r=run(action);assert.notEqual(r.result.status,0);assert.deepEqual(r.calls,[],action+' gate must precede network commands');}
 assert.equal(run('detach').result.status,0);assert.deepEqual(run('detach').calls,[],'unowned cleanup must do nothing');
 fs.writeFileSync(path.join(base,'routing-verified'),'native-xfrm-v1\n');
 for(const flag of ['enabled','acceleration-journal.json']){
  fs.writeFileSync(path.join(base,'tunnel',flag),'');const r=run('enable');assert.notEqual(r.result.status,0);assert.deepEqual(r.calls,[]);
  fs.unlinkSync(path.join(base,'tunnel',flag));
 }
 for(const family of [4,6]){
  const r=run('enable',{['X28_POLICY'+family]:'10010: from all lookup 777'});assert.notEqual(r.result.status,0);
  assert.ok(r.calls.every(s=>s==='pidof charon'||s==='ip rule show'||s==='ip -6 rule show'||s==='ip route show table 20280'||s==='ip -6 route show table 20280'||s==='ip xfrm state count'||s==='ip xfrm policy count'),'priority conflict must not mutate networking');
 }
 for(const name of ['charon','swanctl','xfrmi','owned-xfrm'])fs.writeFileSync(path.join(base,'bin',name),'#!/bin/sh\nexit 0\n',{mode:0o700});
 const r=run('enable');assert.notEqual(r.result.status,0);assert.equal(r.calls.at(-1),'lua /usr/libexec/home-ikev2-config.lua prepare');
 assert.equal(fs.existsSync(path.join(base,'enabled')),false,'failed preparation must not enable blocking or touch routing');
 fs.mkdirSync(path.join(base,'control'));fs.writeFileSync(path.join(base,'control','vip'),'10.20.30.40\n');
 fs.writeFileSync(path.join(base,'enabled'),'');fs.writeFileSync(path.join(base,'routing-owned'),'');
 const attached=run('attach',{X28_LUA_RESULT:'0'});assert.equal(attached.result.status,0,attached.result.stderr);
 assert.ok(attached.calls.some(s=>s.startsWith('iptables -w 3 -t mangle -C FORWARD')),'TCP sizing must use vendor-supported table argument order');
 assert.ok(fs.existsSync(path.join(base,'control','attached')));
 assert.ok(original.indexOf('acceleration restore\n lua /usr/libexec/home-ikev2-xfrm.lua')>0,'ordinary routing must be restored before kernel cleanup can fail');
 assert.ok(!/\brmmod\b|\bmodprobe\b|route flush|xfrm (state|policy) flush/.test(original),'never unload drivers or flush unrelated routes/SAs');
 console.log('PASS: IKEv2 readiness/watchdog gates, mutual exclusion, IPv4/IPv6 conflicts, preparation failure and cleanup ownership');
}finally{assert.equal(path.dirname(root),__dirname);fs.rmSync(root,{recursive:true,force:true});}
