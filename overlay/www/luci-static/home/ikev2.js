(function(){
 'use strict';
 var card=document.querySelector('[data-ikev2-status]');if(!card)return;
 var timer,pending=false;
 function poll(){
  if(pending||document.hidden)return;pending=true;
  var controller=new AbortController(),timeout=setTimeout(function(){controller.abort();},8000);
  fetch(card.dataset.ikev2Status,{credentials:'same-origin',cache:'no-store',signal:controller.signal}).then(function(r){
   if(!r.ok)throw new Error();return r.json();
  }).then(function(data){
   var badge=card.querySelector('[data-ikev2-badge]');
   badge.textContent=data.enabled?(data.running?'Connected':'Internet blocked'):(data.cleanup_pending?'Off · recovery pending':'Off');
   badge.classList.toggle('is-on',!!data.running);
   card.querySelector('[data-ikev2-description]').textContent=data.enabled?
    'Internet is restricted to IKEV2. If the connection stops, internet stays blocked; local router management remains available.':
    'IKEV2 is off. Turn it on to use the selected profile for all devices. Turning it off restores normal internet.';
   var toggle=card.querySelector('[data-vpn-switch]');
   if(toggle.form.dataset.switching!=='true'){
    toggle.setAttribute('aria-checked',data.enabled?'true':'false');
    toggle.querySelector('[data-vpn-switch-label]').textContent=data.enabled?'On':'Off';
    toggle.form.querySelector('[data-vpn-switch-action]').value=data.enabled?'disable':'enable';
    toggle.disabled=!data.enabled&&(!data.ready||data.cleanup_pending||!data.selected);
   }
   document.querySelectorAll('.ikev2-profile button').forEach(function(button){
    var input=button.form.querySelector('[name="profile"]'),selected=Number(input.value)===data.selected;
    button.disabled=data.enabled||data.cleanup_pending||selected;button.textContent=selected?'Selected':'Select profile';
   });
   timer=setTimeout(poll,data.enabled&&!data.running?2000:10000);
  }).catch(function(){timer=setTimeout(poll,5000);}).finally(function(){clearTimeout(timeout);pending=false;});
 }
 document.addEventListener('visibilitychange',function(){if(!document.hidden){clearTimeout(timer);poll();}});
 poll();
}());
