# nasCloud4HAaddon

Minimalny dodatek Home Assistant, który konfiguruje klienta WireGuard i udostępnia HA przez haos.app.

## Co robi
- Czyta opcje dodatku (włącz/wyłącz, subdomena, port HA)
- Tworzy `/data/config/nasCloud/cloud.cnf` (kopiuje domyślne ustawienia)
- Uruchamia `/opt/haos/cloud.sh`, który rejestruje się w brokerze i zestawia WireGuard

## Opcje (UI)
- `nasweb_cloud` (bool): włączenie/wyłączenie chmury
- `nasweb_cloud_subdomain` (string, opcjonalnie): żądana subdomena
- `nasweb_cloud_port` (int): port HTTP HA (domyślnie 8123)
- `cloud_public_domain` (string): domena publiczna do healthcheck (domyślnie `haos.app`)
- `cloud_health_interval` (int): interwał healthcheck w sekundach (domyślnie 300)
- `cloud_auth_user` (string): użytkownik brokera
- `cloud_auth_pass` (string): hasło brokera (zapisywane w `cloud.cnf` jako base64)
- `cloud_client_id` (string): wymagany identyfikator klienta
- `cloud_server_url` (string, opcjonalnie): nadpisanie adresu brokera
- `cloud_server_ip` (string, opcjonalnie): nadpisanie hosta/IP brokera

## Wymagana konfiguracja
Plik: `/data/config/nasCloud/cloud.cnf`
- `AUTH_USER`, `AUTH_PASS`, `SERVER_URL`, `SERVER_IP`, `CLIENT_ID`
- Domyślny plik jest kopiowany z `/opt/haos/cloud.cnf.default` przy pierwszym starcie

## Uwagi
- Dodatek wymaga `NET_ADMIN` oraz `/dev/net/tun` (WireGuard).
- `wireguard-go` jest zostawiony jako userspace fallback; kernelowy WireGuard nadal działa.
- Dodatek zapisuje `cloud_auth_pass` jako base64 w `cloud.cnf`, a `cloud.sh` dekoduje przed Basic Auth.
- Logi: `/data/cloud.log`

## Trusted proxies (HA)
Jeśli wchodzisz do HA przez publiczną subdomenę, może być potrzebne dodanie IP proxy do `trusted_proxies` w `configuration.yaml`.
Sprawdź logi HA, odczytaj IP proxy i dopisz je ręcznie.
