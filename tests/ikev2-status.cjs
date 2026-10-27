const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const timers=new Map();let seq=0,fail=false;
const badge={textContent:'Off',classList:{toggle(n,v){this.on=v;}}},description={},label={},action={},toggle={setAttribute(n,v){this[n]=v;},form:{dataset:{},querySelector(){return action;}},querySelector(){return label;}};
const nodes={'[data-ikev2-badge]':badge,'[data-ikev2-description]':description,'[data-vpn-switch]':toggle};
const card={dataset:{ikev2Status:'/status'},querySelector:s=>nodes[s]};
const data={enabled:false,running:false,selected:4,ready:false,cleanup_pending:false};
const document={hidden:false,querySelector:()=>card,querySelectorAll:()=>[],addEventListener(){}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../overlay/www/luci-static/home/ikev2.js'),'utf8'),{
 document,AbortController,fetch:()=>fail?Promise.reject(new Error()):Promise.resolve({ok:true,json:()=>Promise.resolve(data)}),
 setTimeout(fn,delay){timers.set(++seq,{fn,delay});return seq;},clearTimeout(id){timers.delete(id);}
});
const settle=()=>new Promise(resolve=>setImmediate(resolve));
async function tick(delay){const entry=[...timers].find(([,t])=>t.delay===delay);assert.ok(entry);timers.delete(entry[0]);entry[1].fn();await settle();}
(async()=>{
 await settle();assert.equal(badge.textContent,'Off');assert.equal(toggle.disabled,true);assert.equal(action.value,'enable');
 data.ready=true;data.enabled=true;await tick(10000);assert.equal(badge.textContent,'Internet blocked');assert.equal(toggle.disabled,false);assert.equal(action.value,'disable');assert.equal(toggle['aria-checked'],'true');
 data.running=true;await tick(2000);assert.equal(badge.textContent,'Connected');assert.equal(badge.classList.on,true);
 data.running=false;await tick(10000);assert.equal(badge.textContent,'Internet blocked');
 fail=true;await tick(2000);assert.equal(badge.textContent,'Internet blocked','failed polls must not invent a healthy connection');
 fail=false;data.enabled=false;data.cleanup_pending=true;await tick(5000);assert.equal(badge.textContent,'Off · recovery pending');assert.equal(toggle.disabled,true);
 data.cleanup_pending=false;await tick(10000);assert.equal(badge.textContent,'Off');assert.equal(toggle.disabled,false);
 console.log('PASS: IKEv2 status transitions, activation gate, fail-closed status, recovery controls and poll retries');
})().catch(e=>{console.error(e);process.exitCode=1;});
