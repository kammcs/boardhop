#!/bin/sh
# Publish the Boardhop marketing site to the relay box.
#
# The site is a megabyte of static files with no backend, so it rides along on
# the machine that already runs Caddy rather than earning a host of its own.
# It shares nothing with the relay but the web server: its own site block, its
# own document root, its own access log, and no route from it reaches the relay
# container.
#
# From the repo root, on any machine with ssh:
#
#   SITE_DOMAIN=preview.boardhop.dev sh website/deploy.sh
#
#   SITE_DOMAIN   required the first time; remembered in /srv/relay/.env after
#   SITE_ALIAS    a second hostname that 301s to SITE_DOMAIN; defaults to
#                 www.<SITE_DOMAIN>. Set it to "none" for no alias at all.
#   SITE_HOST     where to deploy (default deploy@boardhop.relay.kammcs.com)
#   SITE_USER     basic-auth username, to put the site behind a password
#   SITE_PASSWORD basic-auth password; hashed on the box, never stored in clear
#
# Idempotent. Run it as often as you like; it only ever replaces /srv/site and
# reloads Caddy, and a bad Caddyfile fails the reload with the running config
# left in place, so the relay keeps answering either way.
set -eu

HOST=${SITE_HOST:-deploy@boardhop.relay.kammcs.com}
RELAY=/srv/relay
REMOTE=$RELAY/site
SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO=$(CDPATH= cd -- "$SRC/.." && pwd)

say() { printf '==> %s\n' "$1"; }

# On the box itself there is no ssh hop.
if [ -d "$RELAY" ] && [ "${SITE_LOCAL:-}" != "0" ]; then LOCAL=1; else LOCAL=0; fi
run() {
  if [ "$LOCAL" = 1 ]; then sh -c "$1"; else ssh "$HOST" "$1"; fi
}

# The domain is remembered in /srv/relay/.env, which is what compose reads for
# the caddy container's SITE_DOMAIN, so it only has to be given once.
DOMAIN=${SITE_DOMAIN:-}
if [ -z "$DOMAIN" ]; then
  DOMAIN=$(run "grep '^SITE_DOMAIN=' $RELAY/.env 2>/dev/null | cut -d= -f2" || true)
fi
if [ -z "$DOMAIN" ]; then
  echo "SITE_DOMAIN is not set and none is recorded on the box." >&2
  echo "Run: SITE_DOMAIN=<hostname> sh website/deploy.sh" >&2
  exit 2
fi
# The www alias. Defaults to www.<domain>; "none" parks it on a .localhost
# name, which Caddy serves with an internal certificate and never takes to
# Let's Encrypt.
ALIAS=${SITE_ALIAS:-}
if [ -z "$ALIAS" ]; then
  ALIAS=$(run "grep '^SITE_ALIAS=' $RELAY/.env 2>/dev/null | cut -d= -f2" || true)
fi
[ -z "$ALIAS" ] && ALIAS="www.$DOMAIN"
[ "$ALIAS" = none ] && ALIAS=boardhop-site-www.localhost

say "publishing to https://$DOMAIN (alias $ALIAS)"

# A hostname that does not resolve here yet cannot pass an HTTP-01 challenge,
# and .dev is HSTS-preloaded, so there is no plain-HTTP fallback to fall back
# to. Say so now rather than after a failed deploy.
for h in "$DOMAIN" "$ALIAS"; do
  case $h in *.localhost) continue ;; esac
  got=$(curl -s --max-time 8 "https://dns.google/resolve?name=$h&type=A" |
    grep -o '"data":"[0-9][0-9.]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$got" ]; then
    echo "warning: $h has no A record yet; Caddy will retry the certificate" >&2
  else
    say "$h resolves to $got"
  fi
done

# Create the document root before compose can: Docker creates a missing bind
# mount source itself, owned by root, and then the deploy user cannot write it.
# It lives under /srv/relay precisely so that no sudo is involved.
run "mkdir -p $REMOTE $RELAY/caddy/site-extra"

# $REMOTE is bind-mounted into the running Caddy container, so it has to be
# updated *in place*. Removing and recreating the directory -- which is what
# the obvious `rm -rf && tar -x` does -- gives it a new inode while the
# container goes on holding the old one, so Caddy serves an empty directory
# and every page 404s until the container is recreated. Learned the hard way.
#
# So: extract over the top, never touching the mount point itself, then prune
# whatever the archive did not contain, from a manifest of what should exist.
EXCLUDES="--exclude=deploy.sh --exclude=tools --exclude=README.md"

say "copying the site to $REMOTE"
if [ "$LOCAL" = 1 ]; then
  tar -C "$SRC" -cf - $EXCLUDES . | tar -C "$REMOTE" -xf -
else
  tar -C "$SRC" -cf - $EXCLUDES . | ssh "$HOST" "tar -C $REMOTE -xf -"
fi

# The site's filenames are web assets: no spaces, no newlines. A plain read
# loop is therefore safe, and far easier to read than NUL plumbing.
say "pruning anything the site no longer contains"
(cd "$SRC" && find . -type f ! -name deploy.sh ! -name README.md ! -path './tools/*' |
  sed 's|^\./||' | LC_ALL=C sort) | run "cat > $REMOTE/.manifest"
run "cd $REMOTE &&
     find . -type f ! -name .manifest ! -name .have | sed 's|^\./||' | LC_ALL=C sort > .have &&
     LC_ALL=C comm -23 .have .manifest | while read -r f; do rm -f \"\$f\" && echo \"removed \$f\"; done
     rm -f .have .manifest
     find . -type d -empty -delete 2>/dev/null || true"

# The site block lives in the relay's Caddyfile and its document root is a
# mount in the relay's compose.yml, so both have to be current on the box or
# the site simply is not served. Install them here rather than making a site
# deploy depend on someone having run relay/deploy.sh first; neither file
# carries anything relay-version-specific, and the running image comes from
# RELAY_VERSION in .env, which this script does not touch.
say "installing compose.yml and the Caddyfile"
put() { # put <local file> <remote path>
  if [ "$LOCAL" = 1 ]; then cp "$1" "$2"; else ssh "$HOST" "cat > $2" < "$1"; fi
}
put "$REPO/relay/compose.yml" "$RELAY/compose.yml"
put "$REPO/relay/caddy/Caddyfile" "$RELAY/caddy/Caddyfile"

# Record the domain for compose, replacing any previous value, and keep every
# other line in .env untouched.
say "recording SITE_DOMAIN in $RELAY/.env"
run "umask 077
     touch $RELAY/.env
     grep -v -e '^SITE_DOMAIN=' -e '^SITE_ALIAS=' $RELAY/.env > $RELAY/.env.new || true
     echo 'SITE_DOMAIN=$DOMAIN' >> $RELAY/.env.new
     echo 'SITE_ALIAS=$ALIAS' >> $RELAY/.env.new
     mv $RELAY/.env.new $RELAY/.env"

# Optional basic auth, for a preview nobody should stumble into. The password
# is hashed on the box and the clear one is never written anywhere.
if [ -n "${SITE_USER:-}" ] && [ -n "${SITE_PASSWORD:-}" ]; then
  say "putting the site behind basic auth for $SITE_USER"
  HASH=$(printf '%s' "$SITE_PASSWORD" |
    run "cd $RELAY && docker compose -f $RELAY/compose.yml exec -T caddy caddy hash-password" |
    tr -d '\r\n')
  run "umask 077
       mkdir -p $RELAY/caddy/site-extra
       printf 'basic_auth {\n\t%s %s\n}\n' '$SITE_USER' '$HASH' > $RELAY/caddy/site-extra/auth.caddyfile"
else
  # No credentials given: leave the fragment in place but empty, so a previous
  # run's password is off and the Caddyfile's import still resolves. An import
  # of a missing file is a hard adapt error.
  say "no SITE_USER/SITE_PASSWORD: the site will be open"
  run "mkdir -p $RELAY/caddy/site-extra
       : > $RELAY/caddy/site-extra/auth.caddyfile"
fi

# compose.yml gained the /srv/site mount and the SITE_DOMAIN environment, so
# the caddy container has to be recreated the first time; after that this is a
# no-op and only the reload below matters.
say "docker compose up -d"
run "cd $RELAY && docker compose -f $RELAY/compose.yml up -d --remove-orphans"

say "reloading Caddy"
run "cd $RELAY && docker compose -f $RELAY/compose.yml exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile"

say "waiting for https://$DOMAIN/ (a new hostname needs a certificate first)"
i=0
while [ "$i" -lt 45 ]; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/" || echo 000)
  # 401 is a success when basic auth is on: the site block is live.
  if [ "$code" = 200 ] || [ "$code" = 401 ]; then
    say "site is up (HTTP $code)"
    say "checking the relay still answers"
    curl -fsS --max-time 10 https://boardhop.relay.kammcs.com/healthz && printf '\n'
    exit 0
  fi
  i=$((i + 1))
  sleep 2
done

echo "the site did not answer; recent caddy logs:" >&2
run "cd $RELAY && docker compose -f $RELAY/compose.yml logs --tail 40 caddy" >&2
exit 1
