const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const cp=require('node:child_process');
const shell=process.env.X28_TEST_SHELL||(process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'/bin/sh');
const root=fs.mkdtempSync(path.join(__dirname,'.control-test-'));
const original=fs.readFileSync(path.join(__dirname,'../overlay/usr/libexec/home-tunnel-control'),'utf8');
const script=original.replace('base=/data/home-tunnel','base=${X28_TEST_ROOT:?}').replaceAll('/data/home-ikev2','"$base/ikev2"').replaceAll('/proc/modules','"$base/modules"');
const base=path.join(root,'state');fs.mkdirSync(base);fs.mkdirSync(path.join(root,'bin'));
const audit=path.join(root,'calls');
for(const name of ['ip','iptables','ip6tables','rmmod','modprobe','lua']){
 const body=name==='ip'?`if [ "$1" = '-6' ]; then printf '%s\\n' "$X28_POLICY6"; else printf '%s\\n' "$X28_POLICY4"; fi`:name==='lua'?'exit "$X28_ACCEL_RESULT"':'exit 99';
 fs.writeFileSync(path.join(root,'bin',name),`#!/bin/sh\nprintf '%s\\n' "${name} $*" >>"$X28_TEST_AUDIT"\n${body}\n`,{mode:0o700});
}
const portable=p=>p.replace(/\\/g,'/').replace(/^([A-Za-z]):/,(_,drive)=>'/'+drive.toLowerCase());
const testScript=path.join(root,'control.sh');fs.writeFileSync(testScript,script);
function run(action,extra={}){
 const result=cp.spawnSync(shell,['-c','PATH="$X28_TEST_BIN:$PATH"; export PATH; exec sh "$X28_TEST_SCRIPT" "$1"','test',action],{
  encoding:'utf8',env:{...process.env,HOME_VPN_OPERATION_LOCKED:'1',X28_ACCEL_RESULT:'0',X28_POLICY4:'',X28_POLICY6:'',X28_TEST_ROOT:portable(base),X28_TEST_BIN:portable(path.join(root,'bin')),X28_TEST_SCRIPT:portable(testScript),X28_TEST_AUDIT:portable(audit),...extra}});
 assert.ifError(result.error);return result;
}
function calls(){return fs.existsSync(audit)?fs.readFileSync(audit,'utf8').trim().split('\n'):[];}
function resetCalls(){if(fs.existsSync(audit))fs.unlinkSync(audit);}
try{
 fs.writeFileSync(path.join(base,'config.json'),'{}');fs.writeFileSync(path.join(base,'modules'),'');
 for(const action of ['enable','guard','attach']){
  const result=run(action);assert.equal(result.status,1,action+' must refuse');
  if(action==='enable')assert.match(result.stderr,/routing is not verified/);
  assert.deepEqual(calls(),[],action+' must not touch networking');
  assert.equal(fs.existsSync(path.join(base,'enabled')),false);
 }
 fs.writeFileSync(path.join(base,'routing-verified'),'native-allowlist-v1\ntest fixture only');
 fs.mkdirSync(path.join(base,'ikev2'));
 for(const flag of ['enabled','routing-owned']){
  fs.writeFileSync(path.join(base,'ikev2',flag),'');resetCalls();
  const result=run('enable');assert.equal(result.status,1);assert.match(result.stderr,/Disable Surfshark/);
  assert.deepEqual(calls(),[],'another VPN must be rejected before network mutation');
  const disabled=run('disable');assert.equal(disabled.status,1);assert.deepEqual(calls(),[],'stale Disable must not restore acceleration owned by IKEv2');
  fs.unlinkSync(path.join(base,'ikev2',flag));
 }
 for(const family of [4,6]){
  resetCalls();const result=run('enable',{['X28_POLICY'+family]:'10000: from all lookup 777'});
  assert.equal(result.status,1);assert.match(result.stderr,/already in use/);
  assert.deepEqual(calls(),family===4?['ip rule show']:['ip rule show','ip -6 rule show']);
  assert.equal(fs.existsSync(path.join(base,'enabled')),false);
 }
 resetCalls();fs.writeFileSync(path.join(base,'enabled'),'');
 assert.equal(run('attach',{X28_ACCEL_RESULT:'1'}).status,1);
 assert.deepEqual(calls(),['lua /usr/libexec/home-tunnel-acceleration.lua verify'],'unverified native acceleration must prevent TUN route installation');
 resetCalls();assert.equal(run('attach').status,0);
 assert.deepEqual(calls(),['lua /usr/libexec/home-tunnel-acceleration.lua verify','ip link show x28tun','ip route replace default dev x28tun table 20280 metric 10']);
 assert.ok(!/\brmmod\b|\bmodprobe\b/.test(original),'Production control must not unload or reload acceleration');
 console.log('PASS: readiness gates, IPv4/IPv6 policy conflicts, verified native acceleration before attach, and no module reload path');
}finally{
 assert.equal(path.dirname(path.resolve(root)),path.resolve(__dirname));assert.ok(path.basename(root).startsWith('.control-test-'));
 fs.rmSync(root,{recursive:true,force:true});
}
