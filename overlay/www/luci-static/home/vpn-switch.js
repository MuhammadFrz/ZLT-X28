(function(){
 'use strict';
 document.querySelectorAll('[data-vpn-switch-form]').forEach(function(form){
  form.addEventListener('submit',function(){
   form.dataset.switching='true';
   var button=form.querySelector('[data-vpn-switch]');
   button.disabled=true;button.setAttribute('aria-busy','true');
   button.querySelector('[data-vpn-switch-label]').textContent='Switching…';
  });
 });
}());
