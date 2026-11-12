#!/bin/bash
# mybinder-xray start script.
# Used in two ways:
#  1) As the Docker ENTRYPOINT: starts xray setup in the background, then
#     execs the Jupyter command Binder passes (e.g. jupyterhub-singleuser).
#  2) Manually in a Jupyter terminal: ./start.sh  (no args) starts xray and
#     waits briefly, then prints the status.
# It downloads Xray 26.10.31 on first start, generates a FRESH random UUID
# inside the live session only, and writes VLESS+WS config to ~/xray/.
# No UUID, key or subscription link is stored in this repository.
set -u

XRAY_PORT="${PORT:-8080}"
XRAY_VERSION="26.10.31"
XRAY_DIR="${HOME:-/home/jovyan}/xray"
mkdir -p "$XRAY_DIR"

setup_xray() {
  echo "[$(date -Is)] setup start: Xray $XRAY_VERSION, port $XRAY_PORT, path /tk-mybinder"
  cd "$XRAY_DIR" || return 1
  if [ -x "$XRAY_DIR/xray" ]; then
    echo "xray binary already present, reusing it"
  else
    curl -fL --retry 3 --connect-timeout 20 --max-time 300 \
      -o Xray-linux-64.zip \
      "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" || {
        echo "ERROR: failed to download Xray $XRAY_VERSION" >&2
        echo "XRAY_FAILED download" > "$XRAY_DIR/status.txt"
        return 1
      }
    unzip -o Xray-linux-64.zip xray || return 1
    chmod +x "$XRAY_DIR/xray"
    echo "downloaded and extracted xray $XRAY_VERSION"
  fi
  if [ -s "$XRAY_DIR/VLESS_UUID.txt" ]; then
    VLESS_UUID="$(cat "$XRAY_DIR/VLESS_UUID.txt")"
  else
    VLESS_UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())')"
    printf '%s' "$VLESS_UUID" > "$XRAY_DIR/VLESS_UUID.txt"
    echo "generated fresh UUID for this session only"
  fi
  cat > "$XRAY_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": ${XRAY_PORT},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${VLESS_UUID}", "flow": "" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/tk-mybinder" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
EOF
  "$XRAY_DIR/xray" run -c "$XRAY_DIR/config.json" >> "$XRAY_DIR/xray.log" 2>&1 &
  echo "$!" > "$XRAY_DIR/xray.pid"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if kill -0 "$(cat "$XRAY_DIR/xray.pid")" 2>/dev/null; then
      break
    fi
  done
  if kill -0 "$(cat "$XRAY_DIR/xray.pid")" 2>/dev/null; then
    {
      echo "XRAY_RUNNING"
      echo "XRAY_PORT=$XRAY_PORT"
      echo "XRAY_VERSION=$XRAY_VERSION"
      echo "VLESS_UUID=$VLESS_UUID"
      echo "VLESS_WS_PATH=/tk-mybinder"
      echo "PROXY_PATH=/proxy/$XRAY_PORT/tk-mybinder"
    } > "$XRAY_DIR/INFO.txt"
    echo "XRAY_RUNNING port=$XRAY_PORT pid=$(cat "$XRAY_DIR/xray.pid")" > "$XRAY_DIR/status.txt"
    echo "XRAY_RUNNING port=$XRAY_PORT"
  else
    echo "ERROR: xray exited, see $XRAY_DIR/xray.log" >&2
    echo "XRAY_FAILED exited" > "$XRAY_DIR/status.txt"
    return 1
  fi
}

if pgrep -x xray >/dev/null 2>&1; then
  echo "xray already running"
  echo "XRAY_RUNNING (already running)" > "$XRAY_DIR/status.txt"
else
  ( setup_xray >> "$XRAY_DIR/setup.log" 2>&1 & )
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  sleep 1
  grep -q XRAY_RUNNING "$XRAY_DIR/status.txt" 2>/dev/null && break
  grep -q XRAY_FAILED "$XRAY_DIR/status.txt" 2>/dev/null && break
done
cat "$XRAY_DIR/status.txt" 2>/dev/null || echo "setup still running, check ~/xray/setup.log"
cat "$XRAY_DIR/INFO.txt" 2>/dev/null || true
