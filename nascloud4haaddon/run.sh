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

CLOUD_DIR=/data/config/nasCloud
CLOUD_CNF="$CLOUD_DIR/cloud.cnf"
CLOUD_DEF=/opt/haos/cloud.cnf.default

mkdir -p "$CLOUD_DIR"
if [ ! -s "$CLOUD_CNF" ] && [ -s "$CLOUD_DEF" ]; then
  cp -f "$CLOUD_DEF" "$CLOUD_CNF"
  note "Placed default cloud.cnf -> $CLOUD_CNF"
fi

if [ -s "$CLOUD_CNF" ]; then
  sed -i "s/^HA_PORT=.*/HA_PORT=\"$NASWEB_CLOUD_PORT\"/" "$CLOUD_CNF" || true
  if [ -n "$NASWEB_CLOUD_SUBDOMAIN" ]; then
    sed -i "s/^SUBD_REQUEST=.*/SUBD_REQUEST=\"$NASWEB_CLOUD_SUBDOMAIN\"/" "$CLOUD_CNF" || true
  fi
fi

if [ "$NASWEB_CLOUD" = "true" ]; then
  note "Cloud enabled, starting /opt/haos/cloud.sh"
  /opt/haos/cloud.sh || err "cloud.sh failed (see /data/cloud.log)"
else
  note "Cloud disabled, skipping cloud.sh"
fi

ok "Startup complete"
# keep container alive if cloud.sh exits fast
sleep infinity
