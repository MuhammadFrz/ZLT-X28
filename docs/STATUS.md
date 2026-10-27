# Verification scope and limitations

This preview targets a specific ZLT X28 vendor MT6890/OpenWrt 19.07 runtime. It is a source overlay, not an official OpenWrt release, flashable image or general installer. Runtime binaries, accounts, private connection configurations and router audit records are not included.

## Interface

Responsive home pages, SVG navigation, telemetry and legacy form compatibility repairs are included. Automated JavaScript tests cover status transitions, polling/backoff, switches and selected vendor defaults. Rendering and functionality can differ on other firmware variants.

## Xray-labelled proxy mode

The existing interface label uses a separately installed sing-box backend. Recorded native integration checks covered LAN TCP/UDP traffic, DNS, fail-closed loss/recovery and startup on the tested runtime. Those observations are not a guarantee for other kernels, hardware acceleration implementations or network conditions.

## OpenVPN

The native OpenVPN integration contains managed-profile hooks for LAN policy routing, tunnel NAT, DNS and journaled acceleration handling. A managed TCP profile passed real LAN HTTPS, TCP/UDP DNS and native Start/Stop checks. Authentication alone does not prove whole-network forwarding; each intended profile needs the routing integration and independent verification.

A blackhole route and forwarding guards are intended to prevent ordinary WAN fallback during unexpected tunnel loss. Explicit Stop restores ordinary internet. A new forced-outage check and reboot/startup verification were not performed for this integration. IPv6 forwarding is blocked in managed mode rather than advertised as tunneled.

## IKEV2

This feature remains experimental and activation-gated. Warm traffic and recovery checks passed, but automatic startup after a controlled restart was not verified. Do not describe it as production-ready or assume profile changes resolve the startup issue.

## Local regression checks

JavaScript checks in `tests/*.cjs` run with Node and use mocks for privileged operations. Shell checks require a POSIX shell. Lua checks require Lua 5.1 and the stated LuCI/native dependencies; model tests take the corresponding source path as an argument. Passing unit tests does not replace testing native routing, kernel cleanup and recovery on the target hardware.

Preserve local management and prepare restoration before native trials. Never add provider credentials, subscriptions, device backups or private runtime logs to the repository.
