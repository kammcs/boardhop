#!/bin/sh
# Deploy the Boardhop relay to boardhop-relay-1. Idempotent: run it as often as
# you like. From the repo root on any machine with ssh (`sh relay/deploy.sh`),
# or on the box itself.
#
#   RELAY_HOST=deploy@boardhop.relay.kammcs.com   where to deploy
#   RELAY_DOMAIN=boardhop.relay.kammcs.com        what to curl afterwards
#   RELAY_VERSION=<git sha>                       image tag; defaults to HEAD
set -eu

HOST=${RELAY_HOST:-deploy@boardhop.relay.kammcs.com}
DOMAIN=${RELAY_DOMAIN:-boardhop.relay.kammcs.com}
REMOTE=/srv/relay
SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

VERSION=${RELAY_VERSION:-}
if [ -z "$VERSION" ]; then
  VERSION=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo dev)
fi

# On the box itself there is no ssh hop.
if [ -d "$REMOTE" ] && [ "${RELAY_LOCAL:-}" != "0" ]; then
  LOCAL=1
else
  LOCAL=0
fi

run() {
  if [ "$LOCAL" = 1 ]; then sh -c "$1"; else ssh "$HOST" "$1"; fi
}

say() { printf '==> %s\n' "$1"; }

say "deploying $VERSION to $HOST"

run "mkdir -p $REMOTE/src $REMOTE/caddy/data $REMOTE/caddy/config $REMOTE/data/capture"

# The capture secret. Generated once, never printed, never leaves the box.
run "if [ ! -s $REMOTE/relay.env ]; then
       umask 077
       printf 'RELAY_CAPTURE_SECRET=%s\n' \"\$(openssl rand -hex 32)\" > $REMOTE/relay.env
       chmod 600 $REMOTE/relay.env
       echo 'generated a new RELAY_CAPTURE_SECRET'
     else
       chmod 600 $REMOTE/relay.env
       echo 'RELAY_CAPTURE_SECRET already present'
     fi"

# The admin secret for GET /v1/admin/devices. Same rules as the capture
# secret: generated on the box, never printed, never committed.
run "if ! grep -q '^RELAY_ADMIN_SECRET=' $REMOTE/relay.env 2>/dev/null; then
       umask 077
       echo \"RELAY_ADMIN_SECRET=\$(openssl rand -hex 32)\" >> $REMOTE/relay.env
       echo 'generated a new RELAY_ADMIN_SECRET'
     else
       echo 'RELAY_ADMIN_SECRET already present'
     fi"

# Push gateway settings. Not secret in themselves (the .p8 and the service
# account under $REMOTE/secrets are), so they carry defaults; an existing line
# is never overwritten. APNS_KEY_ID is deliberately empty: Apple's Key ID for
# the authentication key is not known yet, and an empty value means "APNs
# disabled", which /healthz reports.
GATEWAY_SETTINGS="APNS_KEY_ID= APNS_TEAM_ID=73W98CESN9 APNS_TOPIC=com.kammcs.boardhop APNS_ENV=sandbox APNS_KEY_FILE=/secrets/apns-authkey.p8 FCM_PROJECT_ID=boardhop-d4b8f FCM_SERVICE_ACCOUNT=/secrets/fcm-service-account.json"

run "umask 077
     for kv in $GATEWAY_SETTINGS; do
       key=\${kv%%=*}
       if ! grep -q \"^\$key=\" $REMOTE/relay.env 2>/dev/null; then
         echo \"\$kv\" >> $REMOTE/relay.env
         echo \"added \$key\"
       fi
     done
     chmod 600 $REMOTE/relay.env"

say "copying the source tree to $REMOTE/src"
if [ "$LOCAL" = 1 ]; then
  tar -C "$SRC" -cf - --exclude=.dart_tool --exclude=build --exclude=.env . | tar -C "$REMOTE/src" -xf -
elif command -v rsync >/dev/null 2>&1; then
  rsync -az --delete --exclude .dart_tool --exclude build --exclude .env "$SRC/" "$HOST:$REMOTE/src/"
else
  # Git Bash on Windows has tar and ssh but no rsync.
  tar -C "$SRC" -cf - --exclude=.dart_tool --exclude=build --exclude=.env . \
    | ssh "$HOST" "rm -rf $REMOTE/src && mkdir -p $REMOTE/src && tar -C $REMOTE/src -xf -"
fi

say "installing compose.yml and the Caddyfile"
run "cp $REMOTE/src/compose.yml $REMOTE/compose.yml && cp $REMOTE/src/caddy/Caddyfile $REMOTE/caddy/Caddyfile"

# compose reads /srv/relay/.env for \${RELAY_VERSION}. The tag being replaced is
# kept as RELAY_PREVIOUS so rollback.sh knows where to go back to.
run "prev=\$(grep '^RELAY_VERSION=' $REMOTE/.env 2>/dev/null | cut -d= -f2 || true)
     : > $REMOTE/.env.new
     if [ -n \"\$prev\" ] && [ \"\$prev\" != '$VERSION' ]; then echo \"RELAY_PREVIOUS=\$prev\" >> $REMOTE/.env.new; fi
     echo 'RELAY_VERSION=$VERSION' >> $REMOTE/.env.new
     mv $REMOTE/.env.new $REMOTE/.env"

say "docker compose up -d --build"
run "cd $REMOTE && docker compose -f $REMOTE/compose.yml up -d --build --remove-orphans"

# `up -d` does not notice a changed Caddyfile (it is a bind mount, not config),
# so reload Caddy explicitly. A broken file fails the reload and leaves the
# running config in place.
say "reloading Caddy"
run "cd $REMOTE && docker compose -f $REMOTE/compose.yml exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile" ||   say "caddy reload skipped (not running yet)"

say "docker compose ps"
run "cd $REMOTE && docker compose -f $REMOTE/compose.yml ps"

say "waiting for https://$DOMAIN/healthz"
i=0
while [ "$i" -lt 30 ]; do
  if curl -fsS --max-time 10 "https://$DOMAIN/healthz"; then
    printf '\n==> deployed %s\n' "$VERSION"
    exit 0
  fi
  i=$((i + 1))
  sleep 2
done

echo "healthz did not answer; recent logs:" >&2
run "cd $REMOTE && docker compose -f $REMOTE/compose.yml logs --tail 40 relay caddy" >&2
exit 1
