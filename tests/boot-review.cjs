const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=fs.mkdtempSync(path.join(__dirname,'.boot-review-test-'));
const portable=p=>p.replace(/\\/g,'/').replace(/^([A-Za-z]):/,(_,d)=>'/'+d.toLowerCase());
const shell=process.env.X28_TEST_SHELL||(process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'/bin/sh');
const source=fs.readFileSync(path.join(__dirname,'../tools/ikev2/boot-review-watchdog.sh'),'utf8')
 .replace('base=/data/home-ikev2/boot-review','base=${X28_BOOT_TEST_ROOT:?}/boot')
 .replace('full=/data/home-ikev2/full-review','full=${X28_BOOT_TEST_ROOT:?}/full')
 .replace('cat /proc/sys/kernel/random/boot_id','cat "$X28_BOOT_TEST_ROOT/current-boot-id"').replace('sleep 300','sleep 0.02');
for(const name of ['boot','full','bin'])fs.mkdirSync(path.join(root,name));
fs.writeFileSync(path.join(root,'watchdog.sh'),source);
fs.writeFileSync(path.join(root,'bin','iptables'),`#!/bin/sh
printf '%s\\n' "$*" >>"$X28_BOOT_TEST_ROOT/calls"
if [ "$X28_IPTABLES_FAILURE" = 1 ];then exit 2;fi
case " $* " in *' -C '*) exit 1;;esac
exit 0
`,{mode:0o700});
fs.writeFileSync(path.join(root,'full','cleanup.sh'),`#!/bin/sh
touch "$X28_BOOT_TEST_ROOT/cleanup-called"
rm -f "$X28_BOOT_TEST_ROOT/full/armed" "$X28_BOOT_TEST_ROOT/boot/armed"
`,{mode:0o700});
function reset(){
 for(const name of ['calls','cleanup-called','boot/armed','full/armed','boot/rollback-status']){
  const p=path.join(root,name);if(fs.existsSync(p))fs.unlinkSync(p);
 }
 fs.writeFileSync(path.join(root,'current-boot-id'),'new');fs.writeFileSync(path.join(root,'boot','before-boot-id'),'old');
}
function run(extra={}){
 const result=cp.spawnSync(shell,['-c','PATH="$X28_BOOT_TEST_ROOT/bin:$PATH";export PATH;exec sh "$X28_BOOT_TEST_ROOT/watchdog.sh"'],{
  encoding:'utf8',timeout:10000,env:{...process.env,X28_BOOT_TEST_ROOT:portable(root),X28_IPTABLES_FAILURE:'0',...extra}});
 assert.ifError(result.error);return result;
}
try{
 reset();fs.writeFileSync(path.join(root,'full','armed'),'');assert.equal(run().status,0);assert.equal(fs.existsSync(path.join(root,'cleanup-called')),false);
 reset();fs.writeFileSync(path.join(root,'boot','armed'),'');assert.equal(run().status,0);assert.equal(fs.existsSync(path.join(root,'calls')),false);
 reset();for(const p of ['boot/armed','full/armed'])fs.writeFileSync(path.join(root,p),'');
 fs.writeFileSync(path.join(root,'current-boot-id'),'old');assert.equal(run().status,0);assert.equal(fs.existsSync(path.join(root,'cleanup-called')),false,'pre-reboot execution must be inert');
 reset();for(const p of ['boot/armed','full/armed'])fs.writeFileSync(path.join(root,p),'');
 assert.equal(run().status,0);assert.equal(fs.existsSync(path.join(root,'cleanup-called')),true);assert.equal(fs.existsSync(path.join(root,'full','armed')),false);
 assert.equal(fs.readFileSync(path.join(root,'boot','rollback-status'),'utf8').trim(),'restored');
 const calls=fs.readFileSync(path.join(root,'calls'),'utf8');assert.match(calls,/--dport 18444/);assert.match(calls,/--dport 15355/);
 reset();for(const p of ['boot/armed','full/armed'])fs.writeFileSync(path.join(root,p),'');
 assert.notEqual(run({X28_IPTABLES_FAILURE:'1'}).status,0);assert.equal(fs.existsSync(path.join(root,'cleanup-called')),true,'fixture errors must restore through the EXIT trap');
 reset();for(const p of ['boot/armed','full/armed'])fs.writeFileSync(path.join(root,p),'');
 fs.unlinkSync(path.join(root,'boot','before-boot-id'));assert.notEqual(run().status,0);
 assert.equal(fs.existsSync(path.join(root,'cleanup-called')),true,'missing boot metadata must restore safely');
 console.log('PASS: unarmed and same-boot guards, post-boot timeout restoration, fixture failures and cleanup');
}finally{assert.equal(path.dirname(root),__dirname);fs.rmSync(root,{recursive:true,force:true});}
