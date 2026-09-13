#!/bin/sh
# Roll the relay back to a previously built image. With no argument it uses
# RELAY_PREVIOUS from /srv/relay/.env (deploy.sh records it); pass a tag to pick
# one from `docker images boardhop-relay`. Caddy is left alone.
set -eu

HOST=${RELAY_HOST:-deploy@boardhop.relay.kammcs.com}
DOMAIN=${RELAY_DOMAIN:-boardhop.relay.kammcs.com}
REMOTE=/srv/relay
TAG=${1:-}

if [ -d "$REMOTE" ] && [ "${RELAY_LOCAL:-}" != "0" ]; then LOCAL=1; else LOCAL=0; fi
run() { if [ "$LOCAL" = 1 ]; then sh -c "$1"; else ssh "$HOST" "$1"; fi; }

if [ -z "$TAG" ]; then
  TAG=$(run "grep '^RELAY_PREVIOUS=' $REMOTE/.env 2>/dev/null | cut -d= -f2" || true)
fi
if [ -z "$TAG" ]; then
  echo "no previous tag recorded; available images:" >&2
  run "docker images boardhop-relay --format '{{.Tag}}\t{{.CreatedSince}}'" >&2
  echo "usage: sh relay/rollback.sh <tag>" >&2
  exit 1
fi

echo "==> rolling back to boardhop-relay:$TAG"
run "docker image inspect boardhop-relay:$TAG >/dev/null"

# Point compose at the old image and restart it without rebuilding.
run "cur=\$(grep '^RELAY_VERSION=' $REMOTE/.env 2>/dev/null | cut -d= -f2 || true)
     : > $REMOTE/.env.new
     if [ -n \"\$cur\" ]; then echo \"RELAY_PREVIOUS=\$cur\" >> $REMOTE/.env.new; fi
     echo 'RELAY_VERSION=$TAG' >> $REMOTE/.env.new
     mv $REMOTE/.env.new $REMOTE/.env
     cd $REMOTE && docker compose -f $REMOTE/compose.yml up -d --no-build relay"

run "cd $REMOTE && docker compose -f $REMOTE/compose.yml ps"

i=0
while [ "$i" -lt 20 ]; do
  if curl -fsS --max-time 10 "https://$DOMAIN/healthz"; then
    printf '\n==> rolled back to %s\n' "$TAG"
    exit 0
  fi
  i=$((i + 1))
  sleep 2
done
echo "healthz did not answer after the rollback" >&2
exit 1
