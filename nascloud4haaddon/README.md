# nasCloud4HAaddon

Minimal Home Assistant add-on that configures a WireGuard client and publishes your HA instance through haos.app.

## What it does
- Reads add-on options (enable, subdomain, HA port)
- Writes `/data/config/nasCloud/cloud.cnf` (if missing, copies defaults)
- Runs `/opt/haos/cloud.sh` which registers with the broker and brings up WireGuard

## Options (UI)
- `nasweb_cloud` (bool): enable/disable cloud
- `nasweb_cloud_subdomain` (string, optional): requested subdomain
- `nasweb_cloud_port` (int): internal HA HTTP port (default 8123)

## Required config
File: `/data/config/nasCloud/cloud.cnf`
- `AUTH_USER`, `AUTH_PASS`, `SERVER_URL`, `SERVER_IP`, `CLIENT_ID`
- Defaults are copied from `/opt/haos/cloud.cnf.default` on first start

## Notes
- Add-on needs `NET_ADMIN` and `/dev/net/tun` for WireGuard.
- `wireguard-go` is included as a userspace fallback; kernel WireGuard still works when available.
- Logs: `/data/cloud.log`
