#!/usr/bin/env bash
# One-time setup on the server: clone this repo, publish site/, enable the nginx site, get a certificate.
# Run as root (or with sudo). Needs git, rsync, nginx and certbot already installed.
#
#   CERTBOT_EMAIL=you@example.com sudo -E deploy/server-setup.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=config.env
source "$here/config.env"

for tool in git rsync nginx certbot; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done

if [[ ! -d "$CHECKOUT/.git" ]]; then
  git clone --branch main "https://github.com/henfrydls/daylo-web.git" "$CHECKOUT"
fi

mkdir -p "$WEBROOT"
rsync -a --delete "$CHECKOUT/site/" "$WEBROOT/"
chown -R www-data:www-data "$WEBROOT"

install -m 644 "$CHECKOUT/deploy/nginx/$DOMAIN.conf" "/etc/nginx/sites-available/$DOMAIN"
ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
nginx -t
systemctl reload nginx

if [[ -n "${CERTBOT_EMAIL:-}" ]]; then
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --redirect
else
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect
fi

curl -sSI "https://$DOMAIN/" | head -1
curl -sSI "https://$DOMAIN/demo/" | head -1
