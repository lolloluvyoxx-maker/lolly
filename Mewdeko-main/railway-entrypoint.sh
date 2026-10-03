#!/bin/bash
set -e

: "${TOKEN:?Imposta la variabile TOKEN con il token del bot}"
# Toglie virgolette, backslash e spazi dal token
TOKEN="$(printf '%s' "$TOKEN" | tr -d "\"'\\\\[:space:]")"
OWNER="$(printf '%s' "${OWNER_ID:-0}" | tr -dc '0-9')"; OWNER="${OWNER:-0}"

DATA_DIR="${DATA_DIR:-/data}"
PGDATA="$DATA_DIR/postgres"
REDIS_DIR="$DATA_DIR/redis"
PGBIN="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"
mkdir -p "$PGDATA" "$REDIS_DIR"
chown -R postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"

# --- PostgreSQL locale ---
if [ ! -f "$PGDATA/PG_VERSION" ]; then
  echo "[railway] Creo il database PostgreSQL..."
  runuser -u postgres -- "$PGBIN/initdb" -D "$PGDATA" -U postgres --auth=trust -E UTF8
fi
runuser -u postgres -- "$PGBIN/pg_ctl" -D "$PGDATA" -w -t 60 \
  -o "-c listen_addresses=127.0.0.1 -c unix_socket_directories=/tmp" \
  -l /tmp/postgres.log start
if ! runuser -u postgres -- "$PGBIN/psql" -h 127.0.0.1 -U postgres -tAc \
     "SELECT 1 FROM pg_database WHERE datname='mewdeko'" | grep -q 1; then
  runuser -u postgres -- "$PGBIN/createdb" -h 127.0.0.1 -U postgres mewdeko
fi

# --- Redis locale ---
redis-server --daemonize yes --bind 127.0.0.1 --port 6379 \
  --dir "$REDIS_DIR" --save 300 1 --appendonly no --logfile /tmp/redis.log
for i in $(seq 1 30); do redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG && break; sleep 1; done

# --- credentials.json ---
cat > /app/credentials.json <<JSON
{
  "Token": "${TOKEN}",
  "OwnerIds": [${OWNER}],
  "PsqlConnectionString": "Host=127.0.0.1;Port=5432;Database=mewdeko;Username=postgres",
  "RedisConnections": "127.0.0.1:6379",
  "IsApiEnabled": false,
  "TotalShards": 1,
  "IsMasterInstance": true,
  "PostgresSetupCompleted": true
}
JSON

# --- avvio bot, con spegnimento pulito dei database ---
dotnet Mewdeko.dll &
BOT=$!
trap 'kill -TERM $BOT 2>/dev/null' TERM INT
wait $BOT || true
wait $BOT 2>/dev/null
CODE=$?
redis-cli -h 127.0.0.1 shutdown save 2>/dev/null || true
runuser -u postgres -- "$PGBIN/pg_ctl" -D "$PGDATA" -m fast stop 2>/dev/null || true
exit $CODE
