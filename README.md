# ZLT X28 — Simple Home Router

A community LuCI interface and router software overlay for the ZLT X28 vendor MT6890/OpenWrt 19.07 runtime. It retains the vendor kernel, modem and firmware base.

Based on [EngineerMazeed/ZLT-X28](https://github.com/EngineerMazeed/ZLT-X28), originally authored by RVKSU. The upstream MIT license and copyright notice are retained in [LICENSE](LICENSE). This fork adds a redesigned interface, compatibility repairs and VPN management work. Third-party components retain their own licenses and notices.

**Preview software for the tested vendor runtime. This is source code, not a flashable firmware image or a general installer.** Installing an unrelated OpenWrt image is not part of this project. Review the verification limits before applying changes to a router.

## Improvements

- Home, Wi-Fi, devices, internet and settings pages with responsive layouts and SVG navigation.
- Shared repairs for legacy LuCI forms, tabs, tables, toggles and status displays.
- Xray-labelled whole-network proxy management using sing-box, including single-link and subscription imports, individual/all connection tests and sorting.
- OpenVPN integration that handles vendor LAN policy routing, tunnel NAT, DNS and native acceleration for the explicitly managed profile.
- Experimental IKEV2 profiles and native XFRM cleanup work.

## What has been verified

| Area | Scope and limits |
| --- | --- |
| Interface | Responsive pages and shared LuCI compatibility repairs; see the [verification summary](docs/STATUS.md). |
| Xray-labelled proxy mode | Recorded LAN TCP/UDP, DNS, failure/recovery and reboot checks passed on the tested router. The implementation uses sing-box, which is separately installed. |
| OpenVPN | A managed TCP profile passed real LAN HTTPS and TCP/UDP DNS, plus native Stop/Start verification. LAN integration requires explicit managed-profile hooks; authentication alone does not verify forwarding. OpenVPN reboot/startup and a new forced-outage test were not performed. See [OpenVPN limitations](docs/STATUS.md#openvpn). |
| IKEV2 | Warm traffic and recovery checks passed, but automatic startup after a controlled restart was not verified. Activation remains gated. See [IKEV2 limitations](docs/STATUS.md#ikev2). |

These are recorded results for one vendor runtime, not a guarantee for every X28 variant or network. No provider accounts, private connection configurations, credentials or subscription links are bundled.

## Access on the tested installation

LuCI is available at `http://192.168.70.1:4153/cgi-bin/luci/`. The vendor interface remains on its existing ports. The VPN menu contains **IKEV2**, **OpenVPN** and **Xray**; on mobile, open Menu first. Your router's address can differ.

For the managed whole-network modes, unexpected tunnel loss is intended to block internet traffic while local management remains reachable. Explicit Stop/Disable restores ordinary internet. Consult each mode's status document for the checks actually performed.

## Repository layout

- `overlay/`: controllers, models, templates, theme assets, helpers and services.
- `tests/`: Lua, JavaScript, shell and native-helper regression checks.
- `tools/ikev2/`: build sources and guarded diagnostic tools; these are not unattended installation scripts.
- `docs/`: public verification summary, limitations and the [original upstream README](docs/UPSTREAM_README.md). Private router audit reports are excluded.
- Original upstream archives and `uhttpd`: retained upstream assets.
- `SHA256SUMS.json`: packaged source integrity manifest, excluding itself.

Lua 5.1 tests take their corresponding model/script path; JavaScript regression checks run with Node. Native routing and acceleration checks require the matching vendor runtime. Do not publish router dumps or provider credentials when sharing diagnostic results.
