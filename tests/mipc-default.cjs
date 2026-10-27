const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../overlay/www/luci-static/resources/protocol/mipc.js'), 'utf8');
const options = {};
const network = {
  registerPatternVirtual() {},
  registerErrorCode() {},
  registerProtocol(name, implementation) { return implementation; }
};
const protocol = new Function('rpc', 'form', 'network', '_', source)(
  {declare() { return () => Promise.resolve([]); }},
  {Value: {}, ListValue: {}, Flag: {}}, network, text => text
);
const section = {
  taboption(tab, type, name) {
    return options[name] = {values: [], value(v) {this.values.push(v);}, depends() {}};
  }
};
protocol.renderFormOptions.call({getL3Device() {return null;}, getDevice() {return null;}}, section);
assert.ok(options.iptype.values.includes(options.iptype.default), 'IP type default must match a selectable value');
console.log('PASS: cellular IP type default matches a selectable value');
