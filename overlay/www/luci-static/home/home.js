(function () {
 'use strict';
 var doc=document, sidebar=doc.getElementById('home-sidebar'), toggle=doc.getElementById('home-menu-toggle');
 function menu(open) {doc.body.classList.toggle('nav-open',open);if(toggle)toggle.setAttribute('aria-expanded',String(open));}
 if(toggle)toggle.addEventListener('click',function(){menu(!doc.body.classList.contains('nav-open'));});
 doc.addEventListener('keydown',function(e){if(e.key==='Escape'&&doc.body.classList.contains('nav-open')){menu(false);if(toggle)toggle.focus();}});
 var advanced=doc.getElementById('home-open-advanced');
 if(advanced)advanced.addEventListener('click',function(){menu(true);var details=sidebar.querySelector('details');details.open=true;details.querySelector('summary').focus();});
 function node(tag,text,cls){var n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
 function controlIcons(){
  doc.querySelectorAll('.cbi-dropdown>span.open,.cbi-dropdown>span.more').forEach(function(span){
   if(span.querySelector('svg'))return;
   var svg=doc.createElementNS('http://www.w3.org/2000/svg','svg'),path=doc.createElementNS('http://www.w3.org/2000/svg','path');
   svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('fill','none');svg.setAttribute('stroke','currentColor');svg.setAttribute('stroke-width','2');svg.setAttribute('aria-hidden','true');
   path.setAttribute('d',span.classList.contains('open')?'m6 9 6 6 6-6':'M5 12h.01M12 12h.01M19 12h.01');path.setAttribute('stroke-linecap','round');
   svg.appendChild(path);span.textContent='';span.appendChild(svg);
  });
 }
 doc.addEventListener('luci-loaded',controlIcons);controlIcons();
 new MutationObserver(function(changes){
  if(changes.some(function(change){return Array.from(change.addedNodes).some(function(n){return n.nodeType===1&&(n.matches('.cbi-dropdown')||n.querySelector('.cbi-dropdown'));});}))controlIcons();
 }).observe(doc.body,{childList:true,subtree:true});
 var wifiForm=doc.querySelector('form[data-wifi-editor]');
 if(wifiForm){
  var controls=Array.from(wifiForm.elements), initial=new Map(), dirty=false, submitting=false;
  function value(control){return /^(checkbox|radio)$/.test(control.type)?control.checked:control.value;}
  controls.forEach(function(control){initial.set(control,value(control));});
  function dirtyStatus(){dirty=controls.some(function(control){return control.name&&control.type!=='hidden'&&!/^(submit|reset|button)$/.test(control.type)&&value(control)!==initial.get(control);});var status=doc.getElementById('wifi-dirty-status');if(status){status.textContent=dirty?'You have unsaved changes':'No unsaved changes';status.classList.toggle('is-dirty',dirty);}}
  var labelNames={'SSID':'Network name (SSID)','Auth Mode':'Security mode','Key':'Wi-Fi password','Hidden':'Hide network name'};
  wifiForm.querySelectorAll('table:not(#vif-cfg-station)>tbody>tr').forEach(function(row,index){
   var cells=Array.from(row.cells);if(!cells.length)return;var label=cells[0],name=label.textContent.trim(),field=cells[1]&&cells[1].querySelector('input:not([type=hidden]),select,textarea');
   if(labelNames[name])label.textContent=labelNames[name];
   label.id=label.id||'wifi-label-'+index;
   if(field){
    if(!field.id)field.id='wifi-field-'+index;
    if(field.type==='radio'||field.type==='checkbox'){cells[1].setAttribute('role','group');cells[1].setAttribute('aria-labelledby',label.id);cells[1].querySelectorAll('input').forEach(function(input){var text=input.nextSibling&&input.nextSibling.textContent.trim();if(text)input.setAttribute('aria-label',label.textContent.trim()+': '+text);});}
    else{var caption=node('label',label.textContent);caption.htmlFor=field.id;label.textContent='';label.appendChild(caption);}
   }
   if(cells[2]&&!cells[2].textContent.trim()&&!cells[2].querySelector('input:not([type=hidden]),select,textarea,a,img'))cells[2].classList.add('empty-help');
  });
  wifiForm.addEventListener('input',dirtyStatus);wifiForm.addEventListener('change',dirtyStatus);
  wifiForm.addEventListener('reset',function(){setTimeout(dirtyStatus,0);});
  wifiForm.addEventListener('submit',function(event){if(!event.defaultPrevented)submitting=true;});
  window.addEventListener('load',function(){controls.forEach(function(control){initial.set(control,value(control));});dirtyStatus();});
  window.addEventListener('beforeunload',function(event){if(dirty&&!submitting){event.preventDefault();event.returnValue='';}});
 }
 function renderMenu(ui,tree,path,level){
  var fragment=doc.createDocumentFragment();
  var items=ui.menu.getChildren(tree);
  if(path==='admin/vpn'){
   var vpnOrder={ikev2:0,openvpn:1,tunnel:2};
   items.sort(function(a,b){return (vpnOrder[a.name]===undefined?99:vpnOrder[a.name])-(vpnOrder[b.name]===undefined?99:vpnOrder[b.name]);});
  }
  items.forEach(function(item){
   if(item.name==='home'||item.name==='logout')return;
   var next=path+'/'+item.name, children=ui.menu.getChildren(item);
   if(children.length&&level<3){var details=node('details');details.appendChild(node('summary',item.title));details.appendChild(renderMenu(ui,item,next,level+1));fragment.appendChild(details);}
   else{var a=node('a',item.title);a.href=L.url(next);fragment.appendChild(a);}
  });return fragment;
 }
 var nav=doc.getElementById('home-advanced-nav');
 if(nav&&typeof L!=='undefined')L.require('ui').then(function(ui){ui.menu.flushCache();return ui.menu.load().then(function(tree){nav.textContent='';nav.appendChild(renderMenu(ui,tree.children.admin,'admin',0));});}).catch(function(){nav.textContent='Advanced navigation could not load. Reload this page to try again.';});
 var grid=doc.querySelector('[data-telemetry]');if(!grid)return;
 var status=doc.getElementById('home-observed'), refresh=doc.getElementById('home-refresh'), previous=null, timer=null, pending=false, failures=0;
 var page=grid.getAttribute('data-home-page');
 if(page==='settings')return;
 if(page==='wifi'||page==='devices'){
  if(refresh)refresh.addEventListener('click',function(){location.reload();});
  return;
 }
 function text(id,value){var n=doc.getElementById(id);if(n)n.textContent=value;}
 function bytes(n){if(typeof n!=='number'||!isFinite(n))return 'Unavailable';var u=['B','KB','MB','GB','TB'],i=0;while(n>=1024&&i<u.length-1){n/=1024;i++;}return n.toFixed(1)+' '+u[i];}
 function rate(now,before,seconds){return typeof now==='number'&&typeof before==='number'&&now>=before&&seconds>0?bytes((now-before)/seconds)+'/s':'Measuring…';}
 function schedule(){clearTimeout(timer);if(!doc.hidden)timer=setTimeout(poll,Math.min(30000,5000*Math.pow(2,failures)));}
 function poll(){
  if(pending||doc.hidden)return;pending=true;
  var controller=new AbortController(), timeout=setTimeout(function(){controller.abort();},8000);
  fetch(grid.getAttribute('data-telemetry'),{credentials:'same-origin',cache:'no-store',signal:controller.signal}).then(function(r){if(!r.ok)throw new Error('Status request failed');return r.json();}).then(function(data){
   if(typeof data.observed_at!=='number')throw new Error('Invalid status response');
   var seconds=previous&&previous.route_interface===data.route_interface?data.observed_at-previous.observed_at:0;
   text('home-route-status',data.route_interface?'Uplink route available':'No uplink route');
   text('home-route-interface',data.route_interface?'Default route through '+data.route_interface:'No default IPv4 route was found.');
   text('home-download',rate(data.rx_bytes,previous&&previous.rx_bytes,seconds));
   text('home-upload',rate(data.tx_bytes,previous&&previous.tx_bytes,seconds));text('home-received',bytes(data.rx_bytes));
   if(status)status.textContent='Live counters refreshed '+new Date().toLocaleTimeString()+' · Wi-Fi and device summaries are page snapshots';
   previous=data;failures=0;
  }).catch(function(){failures++;text('home-download','Unavailable');text('home-upload','Unavailable');text('home-route-status','Status unavailable');if(status)status.textContent='Live status could not refresh. Earlier values may be stale. Check your session or local connection.';}).finally(function(){
   clearTimeout(timeout);pending=false;schedule();
  });
 }
 if(refresh)refresh.addEventListener('click',function(){location.reload();});
 doc.addEventListener('visibilitychange',function(){clearTimeout(timer);previous=null;if(!doc.hidden)poll();});poll();
}());
