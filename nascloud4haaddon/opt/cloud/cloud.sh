#!/bin/bash
# NASweb Cloud client for HAOS (BusyBox-friendly)
set -euo pipefail

LOG="/data/cloud.log"
CNF_DIR="/data/config/nasCloud"
CNF_FILE="${CNF_DIR}/cloud.cnf"
WG_DIR="/etc/wireguard"
WG_IF="wgclient"
WG_CONF="${WG_DIR}/${WG_IF}.conf"
PRIV="${CNF_DIR}/client_private.key"
PUB="${CNF_DIR}/client_public.key"

mkdir -p "$CNF_DIR" "$WG_DIR"
touch "$LOG"

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

# ───── Konfiguracja ─────
if [ ! -f "$CNF_FILE" ]; then
  log "❌ No config file: $CNF_FILE"
  exit 1
fi
# shellcheck source=/dev/null
. "$CNF_FILE"

# Wymagane pola brokera
for v in AUTH_USER AUTH_PASS SERVER_URL SERVER_IP; do
  if [ -z "${!v:-}" ]; then log "❌ Config error: missing $v"; exit 1; fi
done

# Port HA (z cnf; domyślnie 8123)
HA_PORT="${HA_PORT:-8123}"
SUBD="${SUBD_REQUEST:-}"

# AUTH_PASS może być base64; jeśli nie, zostanie tak jak jest
AUTH_PASS="$(echo "$AUTH_PASS" | base64 -d 2>/dev/null || echo "$AUTH_PASS")"

# Docelowy HA: auto 172.30.32.1:HA_PORT jeśli brak LOCAL_FORWARD
if [ -z "${LOCAL_FORWARD:-}" ]; then
  LOCAL_FORWARD="172.30.32.1:${HA_PORT}"
fi

# ───── CLIENT_ID ─────
[ -n "$CLIENT_ID" ] || { log "❌ Missing CLIENT_ID"; exit 3; }
log "ℹ️  CLIENT_ID=$CLIENT_ID"

# ───── Klucze WireGuard w /data ─────
ensure_keys(){
  if [ ! -s "$PRIV" ] || [ ! -s "$PUB" ]; then
    umask 077
    wg genkey | tee "$PRIV" | wg pubkey > "$PUB"
    chmod 600 "$PRIV"; chmod 644 "$PUB"
    log "🔑 Generated new WireGuard keys"
  fi
}
ensure_keys
CLIENT_PUBKEY="$(cat "$PUB")"

# ───── Parser JSON (jq -> fallback) ─────
have_jq=0; command -v jq >/dev/null 2>&1 && have_jq=1
json_get(){
  local j="$1" k="$2" val=""
  if [ "$have_jq" -eq 1 ]; then
    val="$(echo "$j" | jq -r --arg k "$k" '.[$k] // empty' 2>/dev/null || true)"
  else
    val="$(echo "$j" | grep -o "\"$k\":\"[^\"]*\"" | head -n1 | cut -d'"' -f4)"
  fi
  echo "$val"
}
contains_err(){
  echo "$1" | grep -qiE "Public key mismatch|duplicate|err4|err5|reset public"
}

# ───── Zapytanie do brokera ─────
do_request(){
  local cmd="$1"
  curl -s -u "$AUTH_USER:$AUTH_PASS" -X POST \
    -d "id=$CLIENT_ID" \
    -d "pubkey=$CLIENT_PUBKEY" \
    -d "port=$HA_PORT" \
    -d "web=http" \
    -d "subdomain=$SUBD" \
    -d "cmd=$cmd" \
    "$SERVER_URL"
}
request_and_maybe_reset(){
  local cmd="$1" resp
  resp="$(do_request "$cmd")"
  echo "$resp" >>"$LOG"
  echo "$resp" >/tmp/haos.remote 2>/dev/null || true

  if [ -z "$resp" ]; then
    log "❌ No response from broker"
    return 1
  fi
  if contains_err "$resp"; then
    log "⚠️  Key mismatch/duplicate — Reset_Public"
    umask 077
    wg genkey | tee "$PRIV" | wg pubkey > "$PUB"
    chmod 600 "$PRIV"; chmod 644 "$PUB"
    CLIENT_PUBKEY="$(cat "$PUB")"
    resp="$(do_request "Reset_Public")"
    echo "$resp" >>"$LOG"
    echo "$resp" >/tmp/haos.remote 2>/dev/null || true
    if [ -z "$resp" ]; then
      log "❌ No response after Reset_Public"
      return 1
    fi
  fi
  printf "%s" "$resp"
}

JSON_RESP="$(request_and_maybe_reset "${1:-}")" || true
if [ -z "$JSON_RESP" ]; then
  log "❌ Invalid server response (empty)"
  exit 1
fi

SERV_PUBKEY="$(json_get "$JSON_RESP" "server_pubkey")"
WG_INST_IP="$(json_get "$JSON_RESP" "wg_server_ip")"
SERVER_PORT="$(json_get "$JSON_RESP" "port")"
CLIENT_IP="$(json_get "$JSON_RESP" "client_ip")"
SUB_ACK="$(json_get "$JSON_RESP" "sub_ack")"

if [ -z "$SERV_PUBKEY" ] || [ -z "$SERVER_IP" ] || [ -z "$SERVER_PORT" ] || [ -z "$CLIENT_IP" ]; then
  log "❌ Invalid server response"
  exit 1
fi

# ───── Rozbij LOCAL_FORWARD (IP:PORT) ─────
LF_IP="$LOCAL_FORWARD"
LF_PORT="$HA_PORT"
if echo "$LOCAL_FORWARD" | grep -q ':'; then
  LF_IP="${LOCAL_FORWARD%%:*}"
  LF_PORT="${LOCAL_FORWARD##*:}"
fi

# ───── Ustal interfejs wyjściowy (do MASQUERADE) ─────
OUT_IF="$(ip route get "$LF_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev"){print $(i+1); exit}}')"
# jeśli nie wykryto – trudno, zrobimy MASQUERADE bez -o

# ───── Zbuduj wgclient.conf ─────
if [ -n "$LF_IP" ] && [ -n "$LF_PORT" ]; then
  {
    echo "[Interface]"
    echo "Address = ${CLIENT_IP}"
    echo "PrivateKey = $(cat "$PRIV")"
    if [ -n "$OUT_IF" ]; then
      echo "PostUp = iptables -t nat -A PREROUTING -i ${WG_IF} -p tcp --dport ${HA_PORT} -j DNAT --to-destination ${LF_IP}:${LF_PORT}; iptables -A FORWARD -p tcp -d ${LF_IP} --dport ${LF_PORT} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT; iptables -t nat -A POSTROUTING -o ${OUT_IF} -p tcp -d ${LF_IP} --dport ${LF_PORT} -j MASQUERADE"
      echo "PostDown = iptables -t nat -D PREROUTING -i ${WG_IF} -p tcp --dport ${HA_PORT} -j DNAT --to-destination ${LF_IP}:${LF_PORT}; iptables -D FORWARD -p tcp -d ${LF_IP} --dport ${LF_PORT} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT; iptables -t nat -D POSTROUTING -o ${OUT_IF} -p tcp -d ${LF_IP} --dport ${LF_PORT} -j MASQUERADE"
    else
      echo "PostUp = iptables -t nat -A PREROUTING -i ${WG_IF} -p tcp --dport ${HA_PORT} -j DNAT --to-destination ${LF_IP}:${LF_PORT}; iptables -A FORWARD -p tcp -d ${LF_IP} --dport ${LF_PORT} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT; iptables -t nat -A POSTROUTING -p tcp -d ${LF_IP} --dport ${LF_PORT} -j MASQUERADE"
      echo "PostDown = iptables -t nat -D PREROUTING -i ${WG_IF} -p tcp --dport ${HA_PORT} -j DNAT --to-destination ${LF_IP}:${LF_PORT}; iptables -D FORWARD -p tcp -d ${LF_IP} --dport ${LF_PORT} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT; iptables -t nat -D POSTROUTING -p tcp -d ${LF_IP} --dport ${LF_PORT} -j MASQUERADE"
    fi
    echo
    echo "[Peer]"
    echo "PublicKey = ${SERV_PUBKEY}"
    echo "Endpoint = ${SERVER_IP}:${SERVER_PORT}"
    echo "AllowedIPs = ${WG_INST_IP}"
    echo "PersistentKeepalive = 25"
  } >"$WG_CONF"
else
  cat >"$WG_CONF" <<EOF
[Interface]
Address = ${CLIENT_IP}
PrivateKey = $(cat "$PRIV")

[Peer]
PublicKey = ${SERV_PUBKEY}
Endpoint = ${SERVER_IP}:${SERVER_PORT}
AllowedIPs = ${WG_INST_IP}
PersistentKeepalive = 25
EOF
fi

log "✅ WireGuard config written to ${WG_CONF}"

# ───── Start WG (bez ip_forward) ─────
export WG_I_PREFER_BUGGY_USERSPACE=1
export WG_QUICK_USERSPACE_IMPLEMENTATION="wireguard-go"
export WG_QUICK_USERSPACE_BIN="/usr/local/bin/wireguard-go"

wg-quick down "$WG_IF" >/dev/null 2>&1 || true
if wg-quick up "$WG_IF" >/tmp/wg.log 2>&1; then
  log "✅ WireGuard client started successfully"
else
  log "❌ WireGuard failed — see /tmp/wg.log"
  tail -n 80 /tmp/wg.log | tee -a "$LOG"
  exit 1
fi

if [ -n "$SUB_ACK" ]; then
  log "🌐 Subdomain acknowledged: $SUB_ACK"
fi

log "✔ Cloud setup complete"
exit 0
