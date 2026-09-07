#!/usr/bin/env bash
# Deploy on the server: bring the clone up to date and publish site/. Run after each merge to main.
#
#   sudo deploy/pull.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=config.env
source "$here/config.env"

git -C "$CHECKOUT" fetch --quiet origin main
git -C "$CHECKOUT" checkout --quiet main
git -C "$CHECKOUT" merge --ff-only --quiet origin/main
rsync -a --delete "$CHECKOUT/site/" "$WEBROOT/"
chown -R www-data:www-data "$WEBROOT"

echo "published $(git -C "$CHECKOUT" rev-parse --short HEAD) to $WEBROOT"
curl -sSI "https://$DOMAIN/" | head -1
