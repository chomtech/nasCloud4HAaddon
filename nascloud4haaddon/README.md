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
- `cloud_public_domain` (string): public domain used for health checks (default `haos.app`)
- `cloud_health_interval` (int): healthcheck interval in seconds (default 300)
- `cloud_auth_user` (string): broker username
- `cloud_auth_pass` (string): broker password (stored as base64 in `cloud.cnf`)
- `cloud_client_id` (string): required client identifier
- `cloud_server_url` (string, optional): override broker URL
- `cloud_server_ip` (string, optional): override broker hostname/IP

## Required config
File: `/data/config/nasCloud/cloud.cnf`
- `AUTH_USER`, `AUTH_PASS`, `SERVER_URL`, `SERVER_IP`, `CLIENT_ID`
- Defaults are copied from `/opt/haos/cloud.cnf.default` on first start

## Notes
- Add-on needs `NET_ADMIN` and `/dev/net/tun` for WireGuard.
- `wireguard-go` is included as a userspace fallback; kernel WireGuard still works when available.
- The add-on stores `cloud_auth_pass` as base64 in `cloud.cnf`, then `cloud.sh` decodes it before Basic Auth.
- Logs: `/data/cloud.log`

## Trusted proxies (HA)
If you access HA via the public subdomain, you may need to add the proxy IP to `trusted_proxies` in `configuration.yaml`.
Check the HA logs for the proxy IP and add it there manually.
