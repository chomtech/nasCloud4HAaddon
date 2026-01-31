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

## Wymagana konfiguracja
Plik: `/data/config/nasCloud/cloud.cnf`
- `AUTH_USER`, `AUTH_PASS`, `SERVER_URL`, `SERVER_IP`, `CLIENT_ID`
- Domyślny plik jest kopiowany z `/opt/haos/cloud.cnf.default` przy pierwszym starcie

## Uwagi
- Dodatek wymaga `NET_ADMIN` oraz `/dev/net/tun` (WireGuard).
- `wireguard-go` jest zostawiony jako userspace fallback; kernelowy WireGuard nadal działa.
- Logi: `/data/cloud.log`
