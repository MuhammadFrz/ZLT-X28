'use strict';
'require rpc';
'require form';
'require network';

var callFileList = rpc.declare({
	object: 'file',
	method: 'list',
	params: [ 'path' ],
	expect: { entries: [] },
	filter: function(list, params) {
		var rv = [];
		for (var i = 0; i < list.length; i++)
			if (list[i].name.match(/^ccmni/))
				rv.push(params.path + list[i].name);
		return rv.sort();
	}
});

network.registerPatternVirtual(/^ccmni.+$/);
network.registerErrorCode('NO_APN', _('No APN'));
network.registerErrorCode('NO_SUBSCRIBER', _('No IMEI'));
network.registerErrorCode('SIM_NOT_INITIALIZED', _('SIM is not ready'));
network.registerErrorCode('CONNECT_FAILED', _('Unable to connect'));

return network.registerProtocol('ql_mipc', {
	getI18n: function() {
		return _('Quectel MIPC Cellular');
	},

	getIfname: function() {
		return this._ubus('l3_device') || 'ccmni%s'.format(this.sid);
	},

	getOpkgPackage: function() {
		return 'mipc-wan';
	},

	isFloating: function() {
		return true;
	},

	isVirtual: function() {
		return true;
	},

	getDevices: function() {
		return null;
	},

	containsDevice: function(ifname) {
		return (network.getIfnameOf(ifname) == this.getIfname());
	},

	renderFormOptions: function(s) {
		var dev = this.getL3Device() || this.getDevice(), o;

		s.taboption('general', form.Value, 'apn', _('*APN'));

		o = s.taboption('general', form.ListValue, 'auth', _('Authentication Type'));
		o.value('both', 'PAP/CHAP');
		o.value('pap', 'PAP');
		o.value('chap', 'CHAP');
		o.value('none', 'NONE');
		o.default = 'none';

		o = s.taboption('general', form.Value, 'username', _('PAP/CHAP username'));
		o.depends('auth', 'pap');
		o.depends('auth', 'chap');
		o.depends('auth', 'both');

		o = s.taboption('general', form.Value, 'password', _('PAP/CHAP password'));
		o.depends('auth', 'pap');
		o.depends('auth', 'chap');
		o.depends('auth', 'both');
		o.password = true;

		o = s.taboption('general', form.ListValue, 'iptype', _('IP Type'));
		o.value('3', 'IPv4/IPv6');
		o.value('1', 'IPv4');
		o.value('2', 'IPv6');
		o.default = '3';

		s.taboption('general', form.Value, 'iaapn', _('IA APN'));

		o = s.taboption('general', form.Value, 'rattype', _('RAT Type (AT+ERAT)'));
		o.value('1', 'WCDMA only');
		o.value('2', 'GSM/WCDMA');
		o.value('3', 'LTE only');
		o.value('5', 'LTE/WCDMA');
		o.value('6', 'LTE, GSM/WCDMA');
		o.value('15', 'NR 5G only');
		o.value('19', 'NR 5G, LTE');
		o.value('21', 'NR 5G, LTE and WCDMA');
		o.value('22', 'NR 5G, LTE, TD-SCDMA and GSM');
		o.default = '19';

		o = s.taboption('general', form.Value, 'auto_conf', _('Auto configuration by SIM'));
		o.value('0', 'No');
		o.value('1', 'Yes');
		o.default = '1';
	}
});
