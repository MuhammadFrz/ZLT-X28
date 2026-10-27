(function(){
 'use strict';
 var doc=document,serial=0;
 function tables(){
  doc.querySelectorAll('.home-main .table,.home-main table').forEach(function(table){
   if(table.closest('.home-wifi-editor,.cbi-dropdown,.home-table-scroll'))return;
   var wrapper=doc.createElement('div');wrapper.className='home-table-scroll';wrapper.id='home-table-scroll-'+(++serial);
   wrapper.setAttribute('role','region');wrapper.setAttribute('aria-label','Scrollable data table');wrapper.tabIndex=0;
   table.parentNode.insertBefore(wrapper,table);wrapper.appendChild(table);table.classList.add('home-data-table');
   if(location.pathname.endsWith('/network/diagnostics')||table.closest('#MULTI_AP_SETTINGS')){table.classList.add('home-layout-table');wrapper.removeAttribute('tabindex');wrapper.removeAttribute('role');wrapper.removeAttribute('aria-label');}
   var rows=Array.from(table.querySelectorAll(':scope > .tr,:scope > tbody > tr,:scope > tr'));
   if(!table.querySelector('.th,th')&&rows.length&&rows.every(function(row){return row.children.length<=2;})){
    table.classList.add('home-keyvalue-table');wrapper.removeAttribute('tabindex');wrapper.removeAttribute('role');wrapper.removeAttribute('aria-label');
   }
  });
 }
 function iconButtons(){
  doc.querySelectorAll('main button').forEach(function(button){
   var text=button.textContent.trim();if(!/^[«»<>]$/.test(text)||button.querySelector('svg'))return;
   var left=text==='«'||text==='<',svg=doc.createElementNS('http://www.w3.org/2000/svg','svg'),path=doc.createElementNS('http://www.w3.org/2000/svg','path');
   svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('class','home-inline-icon');svg.setAttribute('fill','none');svg.setAttribute('stroke','currentColor');svg.setAttribute('stroke-width','2');svg.setAttribute('aria-hidden','true');
   path.setAttribute('d',left?'m15 5-7 7 7 7':'m9 5 7 7-7 7');svg.appendChild(path);button.textContent='';button.appendChild(svg);button.setAttribute('aria-label',left?'Previous page':'Next page');
  });
  doc.querySelectorAll('main input[type=button]:not([name])').forEach(function(input){if(/^Update\s*[»>]$/.test(input.value))input.value='Update';});
 }
 tables();iconButtons();doc.addEventListener('luci-loaded',function(){tables();iconButtons();});
 var observer=new MutationObserver(function(changes){
  if(changes.some(function(c){return Array.from(c.addedNodes).some(function(n){return n.nodeType===1&&(n.matches('table,.table,button,input[type=button]')||n.querySelector('table,.table,button,input[type=button]'));});})){tables();iconButtons();}
 });observer.observe(doc.body,{childList:true,subtree:true});
 function placeTooltips(event){
  var owner=event.target.closest&&event.target.closest('.cbi-tooltip-container');if(!owner)return;
  owner.querySelectorAll('.cbi-tooltip').forEach(function(tip){
   var anchor=owner.getBoundingClientRect();tip.style.position='fixed';tip.style.width='max-content';tip.style.maxWidth=Math.max(120,window.innerWidth-24)+'px';
   var box=tip.getBoundingClientRect();tip.style.left=Math.max(12,Math.min(anchor.left,window.innerWidth-box.width-12))+'px';
   tip.style.top=Math.max(12,anchor.bottom+box.height+12<window.innerHeight?anchor.bottom+8:anchor.top-box.height-8)+'px';
  });
 }
 doc.addEventListener('pointerover',placeTooltips);doc.addEventListener('focusin',placeTooltips);
}());
