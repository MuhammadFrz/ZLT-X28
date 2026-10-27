const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname,'../overlay/www/luci-static/home/home.js'),'utf8');
const settle = () => new Promise(resolve => setImmediate(resolve));

function harness(page) {
 const elements = Object.fromEntries(['home-observed','home-route-status','home-route-interface','home-download','home-upload','home-received','home-refresh'].map(key=>[key,{textContent:'',addEventListener(){}}]));
 const events = {}, timers = new Map(); let next = 0, calls = 0;
 const fixture = {observed_at:10,route_interface:'ccmni1',rx_bytes:100,tx_bytes:100};
 const grid = {getAttribute(name){return name==='data-home-page'?page:'/telemetry';}};
 const document = {
  hidden:false,body:{classList:{toggle(){}}},
  getElementById(key){return elements[key]||null;},
  querySelector(selector){return selector==='[data-telemetry]'?grid:null;},querySelectorAll(){return [];},
  addEventListener(name,callback){events[name]=callback;}
 };
 vm.runInNewContext(source, {
  document,AbortController,MutationObserver:class {observe(){}},
  setTimeout(callback,delay){timers.set(++next,{callback,delay});return next;},
  clearTimeout(id){timers.delete(id);},
  fetch(){calls++;return fixture.fail?Promise.reject(new Error('offline')):Promise.resolve({ok:true,json(){return Promise.resolve({...fixture});}});},
  location:{reload(){}}
 });
 return {elements,document,events,fixture,timers,get calls(){return calls;},
  tick(){const timer=Array.from(timers.values()).find(t=>t.delay>=5000&&t.delay!==8000);assert.ok(timer,'poll scheduled');timer.callback();}
 };
}

(async()=>{
 const h=harness('overview');await settle();
 assert.equal(h.calls,1);assert.equal(h.elements['home-download'].textContent,'Measuring…');
 Object.assign(h.fixture,{observed_at:20,rx_bytes:200,tx_bytes:200});h.tick();await settle();
 assert.equal(h.elements['home-download'].textContent,'10.0 B/s');
 Object.assign(h.fixture,{observed_at:30,route_interface:'ccmni2',rx_bytes:100000});h.tick();await settle();
 assert.equal(h.elements['home-download'].textContent,'Measuring…','route change must reset rate baseline');
 Object.assign(h.fixture,{observed_at:40,rx_bytes:0});h.tick();await settle();
 assert.equal(h.elements['home-download'].textContent,'Measuring…','counter reset must not create negative rates');
 h.fixture.fail=true;h.tick();await settle();
 assert.equal(h.elements['home-download'].textContent,'Unavailable');
 assert.equal(h.elements['home-route-status'].textContent,'Status unavailable');
 assert.ok(Array.from(h.timers.values()).some(t=>t.delay===10000),'error backs off polling');
 const before=h.calls;h.document.hidden=true;h.events.visibilitychange();await settle();assert.equal(h.calls,before);
 for(const page of ['wifi','devices','settings']){const snapshot=harness(page);await settle();assert.equal(snapshot.calls,0,page+' must not poll');}
 console.log('PASS: actual rate deltas, route/counter reset, offline state, backoff, hidden page, snapshot-only pages');
})().catch(error=>{console.error(error);process.exitCode=1;});
