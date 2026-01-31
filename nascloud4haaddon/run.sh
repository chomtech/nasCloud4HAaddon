#!/usr/bin/with-contenv bash
set -e

note() { echo "[INFO] $*"; }
ok()   { echo "[OK]   $*"; }
err()  { echo "[ERR]  $*"; }

echo "Starting nasCloud4HAaddon..."

HAVE_BASHIO=0
if [ -f /usr/lib/bashio ]; then . /usr/lib/bashio; HAVE_BASHIO=1; fi
OPT_FILE="/data/options.json"

cfg_bool() { # key default_bool
  local key="$1" def="$2" val
  if [ "$HAVE_BASHIO" = "1" ]; then if bashio::config.true "$key"; then echo true; else echo false; fi; return; fi
  val="$(jq -r --arg k "$key" '.[$k] // empty' "$OPT_FILE" 2>/dev/null || true)"
  case "$val" in (true|false) echo "$val";; (*) echo "$def";; esac
}

cfg_str() { # key default_str
  local key="$1" def="$2" val
  if [ "$HAVE_BASHIO" = "1" ]; then val="$(bashio::config "$key" 2>/dev/null || true)"; [ -n "$val" ] && echo "$val" || echo "$def"; return; fi
  val="$(jq -r --arg k "$key" '.[$k] // empty' "$OPT_FILE" 2>/dev/null || true)"; [ -n "$val" ] && echo "$val" || echo "$def"
}

cfg_int() { # key default_int
  local key="$1" def="$2" val
  if [ "$HAVE_BASHIO" = "1" ]; then val="$(bashio::config "$key" 2>/dev/null || true)"; [[ "$val" =~ ^[0-9]+$ ]] && echo "$val" || echo "$def"; return; fi
  val="$(jq -r --arg k "$key" '.[$k] // empty' "$OPT_FILE" 2>/dev/null || true)"; [[ "$val" =~ ^[0-9]+$ ]] && echo "$val" || echo "$def"
}

NASWEB_CLOUD="$(cfg_bool nasweb_cloud false)"
NASWEB_CLOUD_SUBDOMAIN="$(cfg_str nasweb_cloud_subdomain "")"
NASWEB_CLOUD_PORT="$(cfg_int nasweb_cloud_port 8123)"
CLOUD_PUBLIC_DOMAIN="$(cfg_str cloud_public_domain "haos.app")"
CLOUD_HEALTH_INTERVAL="$(cfg_int cloud_health_interval 300)"
AUTH_USER_OPT="$(cfg_str cloud_auth_user "")"
AUTH_PASS_OPT="$(cfg_str cloud_auth_pass "")"
CLIENT_ID_OPT="$(cfg_str cloud_client_id "")"
SERVER_URL_OPT="$(cfg_str cloud_server_url "")"
SERVER_IP_OPT="$(cfg_str cloud_server_ip "")"

CLOUD_DIR=/data/config/nasCloud
CLOUD_CNF="$CLOUD_DIR/cloud.cnf"
CLOUD_DEF=/opt/haos/cloud.cnf.default

mkdir -p "$CLOUD_DIR"
if [ ! -s "$CLOUD_CNF" ] && [ -s "$CLOUD_DEF" ]; then
  cp -f "$CLOUD_DEF" "$CLOUD_CNF"
  note "Placed default cloud.cnf -> $CLOUD_CNF"
fi

if [ -s "$CLOUD_CNF" ]; then
  escape_sed() { printf '%s' "$1" | sed 's/[&|]/\\&/g'; }
  set_kv() {
    local key="$1" val="$2" esc
    esc="$(escape_sed "$val")"
    if grep -q "^${key}=" "$CLOUD_CNF"; then
      sed -i "s|^${key}=.*|${key}=\"${esc}\"|" "$CLOUD_CNF" || true
    else
      printf '%s=\"%s\"\n' "$key" "$val" >>"$CLOUD_CNF"
    fi
  }
  b64_encode() { printf '%s' "$1" | base64 | tr -d '\n'; }

  set_kv "HA_PORT" "$NASWEB_CLOUD_PORT"
  if [ -n "$NASWEB_CLOUD_SUBDOMAIN" ]; then
    set_kv "SUBD_REQUEST" "$NASWEB_CLOUD_SUBDOMAIN"
  fi
  if [ -n "$AUTH_USER_OPT" ]; then
    set_kv "AUTH_USER" "$AUTH_USER_OPT"
  fi
  if [ -n "$AUTH_PASS_OPT" ]; then
    set_kv "AUTH_PASS" "$(b64_encode "$AUTH_PASS_OPT")"
  fi
  if [ -n "$CLIENT_ID_OPT" ]; then
    set_kv "CLIENT_ID" "$CLIENT_ID_OPT"
  fi
  if [ -n "$SERVER_URL_OPT" ]; then
    set_kv "SERVER_URL" "$SERVER_URL_OPT"
  fi
  if [ -n "$SERVER_IP_OPT" ]; then
    set_kv "SERVER_IP" "$SERVER_IP_OPT"
  fi
fi

if [ "$NASWEB_CLOUD" = "true" ]; then
  note "Cloud enabled, starting /opt/haos/cloud.sh"
  /opt/haos/cloud.sh || err "cloud.sh failed (see /data/cloud.log)"

  if [ -n "$NASWEB_CLOUD_SUBDOMAIN" ] && [ -n "$CLOUD_PUBLIC_DOMAIN" ]; then
    if [ "$CLOUD_HEALTH_INTERVAL" -ge 60 ]; then
      HEALTH_URL="https://${NASWEB_CLOUD_SUBDOMAIN}.${CLOUD_PUBLIC_DOMAIN}"
      note "Healthcheck enabled: ${HEALTH_URL} every ${CLOUD_HEALTH_INTERVAL}s"
      (
        command -v curl >/dev/null 2>&1 || { err "Healthcheck disabled: curl not found"; exit 0; }
        # Give DNS/proxy a moment to propagate on startup
        sleep 30
        while :; do
          ok_hc=0
          attempt=1
          while [ "$attempt" -le 3 ]; do
            curl_out="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "$HEALTH_URL" 2>&1)"
            curl_rc=$?
            http_code=""
            curl_err=""
            if [ "$curl_rc" -eq 0 ]; then
              http_code="$curl_out"
            else
              curl_err="$curl_out"
            fi
            if [ -n "$http_code" ] && [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
              ok_hc=1
              break
            fi
            err "Healthcheck attempt ${attempt}/3 failed (code=${http_code:-na}) ${curl_err:+err=${curl_err}}"
            attempt=$((attempt+1))
            sleep 5
          done
          if [ "$ok_hc" -ne 1 ]; then
            err "Healthcheck failed, restarting cloud.sh"
            /opt/haos/cloud.sh || err "cloud.sh failed (see /data/cloud.log)"
          fi
          sleep "$CLOUD_HEALTH_INTERVAL"
        done
      ) &
    else
      note "Healthcheck disabled (interval < 60)"
    fi
  else
    note "Healthcheck disabled (missing subdomain or public domain)"
  fi
else
  note "Cloud disabled, skipping cloud.sh"
fi

ok "Startup complete"
# keep container alive if cloud.sh exits fast
sleep infinity
