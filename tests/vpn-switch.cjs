const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
let submit;
const label={},button={setAttribute(name,value){this[name]=value;},querySelector(){return label;}};
const form={dataset:{},addEventListener(name,fn){assert.equal(name,'submit');submit=fn;},querySelector(){return button;}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../overlay/www/luci-static/home/vpn-switch.js'),'utf8'),{document:{querySelectorAll(){return [form];}}});
submit();assert.equal(form.dataset.switching,'true');assert.equal(button.disabled,true);assert.equal(button['aria-busy'],'true');
assert.equal(label.textContent,'Switching…');
for(const file of ['ikev2','tunnel']){
 const html=fs.readFileSync(path.join(__dirname,'../overlay/usr/lib/lua/luci/view/home',file+'.htm'),'utf8');
 assert.match(html,/role="switch"/);assert.match(html,/aria-checked=/);assert.match(html,/name="token"/);assert.match(html,/data-vpn-switch-action/);
 assert.ok(!/<button[^>]*data-vpn-switch[^>]*name="action"/.test(html),'POST action stays in a hidden field when the switch is disabled during submission');
}
console.log('PASS: accessible switches, CSRF/POST preservation and busy feedback');
