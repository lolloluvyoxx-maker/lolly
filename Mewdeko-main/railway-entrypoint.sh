#!/bin/bash
set -e

# Unica variabile obbligatoria: TOKEN
: "${TOKEN:?Imposta la variabile TOKEN con il token del bot}"
# Toglie virgolette, backslash e spazi dal token
TOKEN="$(printf '%s' "$TOKEN" | tr -d "\"'\\\\[:space:]")"
OWNER="$(printf '%s' "${OWNER_ID:-0}" | tr -dc '0-9')"; OWNER="${OWNER:-0}"

# Lavalink (musica): opzionale. Senza un server il bot parte lo stesso,
# solo i comandi musicali non funzionano.
LAVALINK_URL="${LAVALINK_URL:-http://127.0.0.1:2333}"
LAVALINK_PASSWORD="${LAVALINK_PASSWORD:-youshallnotpass}"

DATA_DIR="${DATA_DIR:-/data}"
PGDATA="$DATA_DIR/postgres"
REDIS_DIR="$DATA_DIR/redis"
PGBIN="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"
mkdir -p "$PGDATA" "$REDIS_DIR"
chown -R postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"
pg() { runuser -u postgres -- "$PGBIN/$@"; }

# --- PostgreSQL locale ---
if [ ! -f "$PGDATA/PG_VERSION" ]; then
  echo "[railway] Creo il database PostgreSQL..."
  pg initdb -D "$PGDATA" -U postgres --auth=trust -E UTF8
fi

# Avvio idempotente: se e' gia' attivo non lo riavvio; se e' rimasto
# appeso o con un postmaster.pid orfano lo ripulisco prima di partire.
if ! "$PGBIN/pg_isready" -h 127.0.0.1 -p 5432 -q; then
  if pg pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
    pg pg_ctl -D "$PGDATA" -m immediate -w stop || true
  fi
  rm -f "$PGDATA/postmaster.pid"
  pg pg_ctl -D "$PGDATA" -w -t 60 \
    -o "-c listen_addresses=127.0.0.1 -c unix_socket_directories=/tmp" \
    -l /tmp/postgres.log start
fi
for i in $(seq 1 60); do
  "$PGBIN/pg_isready" -h 127.0.0.1 -p 5432 -q && break
  sleep 1
done
"$PGBIN/pg_isready" -h 127.0.0.1 -p 5432 -q || { echo "[railway] PostgreSQL non risponde"; cat /tmp/postgres.log; exit 1; }

if ! pg psql -h 127.0.0.1 -U postgres -tAc \
     "SELECT 1 FROM pg_database WHERE datname='mewdeko'" | grep -q 1; then
  pg createdb -h 127.0.0.1 -U postgres mewdeko
fi

# --- Redis locale ---
if ! redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG; then
  redis-server --daemonize yes --bind 127.0.0.1 --port 6379 \
    --dir "$REDIS_DIR" --save 300 1 --appendonly no --logfile /tmp/redis.log
fi
for i in $(seq 1 30); do redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG && break; sleep 1; done

# --- credentials.json ---
cat > /app/credentials.json <<JSON
{
  "Token": "${TOKEN}",
  "OwnerIds": [${OWNER}],
  "PsqlConnectionString": "Host=127.0.0.1;Port=5432;Database=mewdeko;Username=postgres",
  "RedisConnections": "127.0.0.1:6379",
  "LavalinkUrl": "${LAVALINK_URL}",
  "LavalinkPassword": "${LAVALINK_PASSWORD}",
  "IsApiEnabled": false,
  "TotalShards": 1,
  "IsMasterInstance": true,
  "PostgresSetupCompleted": true
}
JSON

# --- avvio bot, con spegnimento pulito dei database ---
set +e
dotnet Mewdeko.dll &
BOT=$!
trap 'kill -TERM $BOT 2>/dev/null' TERM INT
wait $BOT
wait $BOT 2>/dev/null
CODE=$?
redis-cli -h 127.0.0.1 shutdown save 2>/dev/null || true
pg pg_ctl -D "$PGDATA" -m fast -w stop 2>/dev/null || true
exit $CODE
