#!/usr/bin/env bash
# One-time setup on the server: clone this repo, publish site/, enable the nginx site.
# Run with sudo. Needs git, rsync and nginx, and the wildcard certificate for
# *.henfrydls.com under /etc/letsencrypt/live/henfrydls.com-0001/ (already there).
#
#   sudo deploy/server-setup.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=config.env
source "$here/config.env"
[[ $EUID -eq 0 ]] || { echo "run with sudo: the webroot belongs to www-data" >&2; exit 1; }

for tool in git rsync nginx curl; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
[[ -f /etc/letsencrypt/live/henfrydls.com-0001/fullchain.pem ]] || {
  echo "wildcard certificate not found; adjust deploy/nginx/$DOMAIN.conf or run certbot --nginx -d $DOMAIN first" >&2; exit 1; }

if [[ ! -d "$CHECKOUT/.git" ]]; then
  git clone --quiet --branch main "https://github.com/henfrydls/daylo-web.git" "$CHECKOUT"
fi

mkdir -p "$WEBROOT"
# Old files stay until the whole transfer is done and updated files land together, so a page
# loaded mid-publish never points at a bundle that is not there yet.
rsync -a --delay-updates --delete-after "$CHECKOUT/site/" "$WEBROOT/"
chown -R www-data:www-data "$WEBROOT"

install -m 644 "$CHECKOUT/deploy/nginx/$DOMAIN.conf" "/etc/nginx/sites-available/$DOMAIN"
ln -sfn "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
nginx -t
systemctl reload nginx

# Informative only: the site is already published at this point.
for path in / /privacy/ /demo/ /assets/og.png; do
  printf '%-16s %s\n' "$path" "$(curl -sS -o /dev/null -w '%{http_code}' "https://$DOMAIN$path" || echo "no answer")"
done
