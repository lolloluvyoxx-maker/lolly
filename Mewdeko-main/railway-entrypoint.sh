#!/bin/bash
set -e

: "${TOKEN:?Imposta la variabile TOKEN con il token del bot}"

# Pulisce il token: toglie virgolette, apici, backslash e spazi/a capo
TOKEN="$(printf '%s' "$TOKEN" | tr -d "\"'\\\\[:space:]")"

# --- Postgres: da DATABASE_URL (postgresql://user:pass@host:port/db) ---
if [ -n "$DATABASE_URL" ]; then
  rest="${DATABASE_URL#*://}"
  userpass="${rest%%@*}"
  hostpart="${rest#*@}"
  PGU="${userpass%%:*}"
  PGP="${userpass#*:}"
  hostport="${hostpart%%/*}"
  PGD="${hostpart#*/}"; PGD="${PGD%%\?*}"
  PGH="${hostport%%:*}"
  PGPORT_="${hostport#*:}"
  PSQL="Host=${PGH};Port=${PGPORT_};Database=${PGD};Username=${PGU};Password=${PGP}"
else
  PSQL="Host=${PGHOST};Port=${PGPORT:-5432};Database=${PGDATABASE};Username=${PGUSER};Password=${PGPASSWORD}"
fi

# --- Redis: da REDIS_URL (redis://default:pass@host:port) ---
if [ -n "$REDIS_URL" ]; then
  rest="${REDIS_URL#*://}"
  userpass="${rest%%@*}"
  hostport="${rest#*@}"
  RP="${userpass#*:}"
  REDIS="${hostport},password=${RP}"
else
  REDIS="${REDISHOST}:${REDISPORT:-6379},password=${REDISPASSWORD}"
fi

OWNER="${OWNER_ID:-0}"

cat > /app/credentials.json <<JSON
{
  "Token": "${TOKEN}",
  "OwnerIds": [${OWNER}],
  "PsqlConnectionString": "${PSQL}",
  "RedisConnections": "${REDIS}",
  "IsApiEnabled": false,
  "TotalShards": 1,
  "IsMasterInstance": true,
  "PostgresSetupCompleted": true
}
JSON

exec dotnet Mewdeko.dll
