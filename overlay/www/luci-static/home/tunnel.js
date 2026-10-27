(function(){
 'use strict';
 var card=document.querySelector('[data-tunnel-results]');if(!card)return;
 var list=document.getElementById('tunnel-connections'),sort=document.getElementById('connection-sort'),timer,pending=false;
 function reorder(){
  var rows=Array.from(list.children),mode=sort.value;
  rows.sort(function(a,b){
   if(mode==='latency'){var x=parseFloat(a.dataset.latency),y=parseFloat(b.dataset.latency);if(!isFinite(x))x=Infinity;if(!isFinite(y))y=Infinity;if(x!==y)return x-y;}
   if(mode==='source'){var s=a.dataset.source.localeCompare(b.dataset.source);if(s)return s;}
   return a.dataset.name.localeCompare(b.dataset.name);
  });rows.forEach(function(row){list.appendChild(row);});
 }
 function poll(){
  if(pending||document.hidden)return;pending=true;
  var controller=new AbortController(),timeout=setTimeout(function(){controller.abort();},8000);
  fetch(card.dataset.tunnelResults,{credentials:'same-origin',cache:'no-store',signal:controller.signal}).then(function(r){if(!r.ok)throw new Error();return r.json();}).then(function(data){
   var state=document.querySelector('[data-tunnel-state]'),starting=document.querySelector('[data-tunnel-start-message]');
   if(state){state.textContent=data.enabled?(data.running?'Running':'Internet blocked'):'Off';state.classList.toggle('is-on',!!(data.enabled&&data.running));}
   var toggle=document.querySelector('[data-vpn-switch]');
   if(toggle&&toggle.form.dataset.switching!=='true'){
    toggle.setAttribute('aria-checked',data.enabled?'true':'false');
    toggle.querySelector('[data-vpn-switch-label]').textContent=data.enabled?'On':'Off';
    toggle.form.querySelector('[data-vpn-switch-action]').value=data.enabled?'disable':'enable';
    toggle.disabled=!data.enabled&&(!data.ready||!data.selected);
   }
   if(starting&&(!data.enabled||data.running))starting.hidden=true;
   data.nodes.forEach(function(node){
    var row=list.querySelector('[data-connection-index="'+node.index+'"]');if(!row)return;
    var t=node.test||{},label=row.querySelector('[data-test-result]');
    label.textContent=typeof t.latency_ms==='number'?t.latency_ms+' ms':({failed:'Failed',timeout:'Timed out',testing:'Testing…',queued:'Queued'})[t.status]||'Not tested';
    label.classList.toggle('is-ok',t.status==='ok');label.classList.toggle('is-failed',t.status==='failed'||t.status==='timeout');row.dataset.latency=typeof t.latency_ms==='number'?t.latency_ms:'';
   });
   document.getElementById('tunnel-test-progress').textContent=data.tests.running?'Testing '+data.tests.done+' of '+data.tests.total:data.tests.total?'Testing complete · '+data.tests.done+' of '+data.tests.total:data.nodes.length+' connections';
   document.querySelectorAll('[data-test-button]').forEach(function(b){b.disabled=data.tests.running;});reorder();
   timer=setTimeout(poll,data.tests.running||(data.enabled&&!data.running)?2000:10000);
  }).catch(function(){document.getElementById('tunnel-test-progress').textContent='Could not refresh test results. Check your session or local connection.';timer=setTimeout(poll,10000);}).finally(function(){clearTimeout(timeout);pending=false;});
 }
 sort.addEventListener('change',reorder);reorder();
 document.addEventListener('visibilitychange',function(){clearTimeout(timer);if(!document.hidden)poll();});poll();
}());
