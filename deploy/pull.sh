#!/usr/bin/env bash
# Deploy on the server: bring the clone up to date and publish site/. Run after each merge to main.
#
#   sudo deploy/pull.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=config.env
source "$here/config.env"
[[ $EUID -eq 0 ]] || { echo "run with sudo: the webroot belongs to www-data" >&2; exit 1; }

git -C "$CHECKOUT" fetch --quiet origin main
git -C "$CHECKOUT" checkout --quiet main
git -C "$CHECKOUT" merge --ff-only --quiet origin/main
# Old files stay until the whole transfer is done and updated files land together, so a page
# loaded mid-publish never points at a bundle that is not there yet.
rsync -a --delay-updates --delete-after "$CHECKOUT/site/" "$WEBROOT/"
chown -R www-data:www-data "$WEBROOT"

echo "published $(git -C "$CHECKOUT" rev-parse --short HEAD) to $WEBROOT"
# Informative only: a failed check after a successful publish should not make the script fail.
curl -sS -o /dev/null -w "https://$DOMAIN/ -> %{http_code}\n" "https://$DOMAIN/" || echo "check failed: $DOMAIN did not answer" >&2
