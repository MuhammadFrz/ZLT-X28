const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../overlay/www/luci-static/home/tunnel.js'),'utf8');
const state={textContent:'Internet blocked',classList:{toggle(name,value){this.on=value;}}};
const notice={hidden:false};
const label={},action={},toggle={setAttribute(n,v){this[n]=v;},form:{dataset:{},querySelector(){return action;}},querySelector(){return label;}};
const progress={textContent:''};
const sort={value:'latency',addEventListener(){}};
const list={children:[]};
const timers=new Map();let next=0,fail=false;
const data={ready:true,selected:{index:1},enabled:true,running:false,nodes:[],tests:{running:false,total:0}};
const document={hidden:false,addEventListener(){},querySelector(s){return {'[data-tunnel-results]':{dataset:{tunnelResults:'/status'}},'[data-tunnel-state]':state,'[data-vpn-switch]':toggle,'[data-tunnel-start-message]':notice}[s];},querySelectorAll(){return [];},getElementById(id){return {'tunnel-connections':list,'connection-sort':sort,'tunnel-test-progress':progress}[id];}};
vm.runInNewContext(source,{document,AbortController,setTimeout(fn,delay){timers.set(++next,{fn,delay});return next;},clearTimeout(id){timers.delete(id);},fetch(){return fail?Promise.reject(new Error('offline')):Promise.resolve({ok:true,json:()=>Promise.resolve(data)});}});
const settle=()=>new Promise(resolve=>setImmediate(resolve));
async function tick(delay){const entry=[...timers].find(([,t])=>t.delay===delay);assert.ok(entry,'poll scheduled at '+delay);timers.delete(entry[0]);entry[1].fn();await settle();}
(async()=>{
 await settle();assert.equal(state.textContent,'Internet blocked');assert.equal(notice.hidden,false);assert.equal(toggle['aria-checked'],'true');assert.equal(action.value,'disable');
 data.running=true;await tick(2000);assert.equal(state.textContent,'Running');assert.equal(state.classList.on,true);assert.equal(notice.hidden,true);
 data.running=false;await tick(10000);assert.equal(state.textContent,'Internet blocked');assert.equal(state.classList.on,false);
 fail=true;await tick(2000);assert.equal(state.textContent,'Internet blocked');assert.match(progress.textContent,/Could not refresh/);
 fail=false;data.enabled=false;await tick(10000);assert.equal(state.textContent,'Off');assert.equal(toggle['aria-checked'],'false');assert.equal(action.value,'enable');assert.equal(toggle.disabled,false);assert.equal(state.classList.on,false);
 console.log('Tunnel status transitions, retry and notice cleanup passed');
})().catch(e=>{console.error(e);process.exitCode=1;});
