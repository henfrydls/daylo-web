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
# android/daylo.apk is not in the repository (17 MB per release); it is fetched below, so the
# sync must neither delete nor replace it.
rsync -a --delay-updates --delete-after --exclude '/android/daylo.apk' "$CHECKOUT/site/" "$WEBROOT/"

# The Android download is served from this domain rather than GitHub: opened from another app,
# Chrome's custom tab stalls on GitHub's redirect to its file host. The file is the latest
# release's APK, taken whole into a temporary name and moved into place only if it looks like
# one, so a failed or partial download never replaces a good file.
apk_tag=$(curl -fsSL "https://api.github.com/repos/$APP_REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
if [[ -n "$apk_tag" ]]; then
  mkdir -p "$WEBROOT/android"
  tmp="$WEBROOT/android/.daylo.apk.part"
  if curl -fsSL -o "$tmp" "https://github.com/$APP_REPO/releases/download/$apk_tag/Daylo-android-arm64.apk" \
     && [[ $(head -c 2 "$tmp") == "PK" ]] && [[ $(stat -c %s "$tmp") -gt 5000000 ]]; then
    mv -f "$tmp" "$WEBROOT/android/daylo.apk"
    echo "android/daylo.apk is $apk_tag"
  else
    rm -f "$tmp"
    echo "android/daylo.apk NOT updated: the $apk_tag download failed or was not an APK" >&2
  fi
else
  echo "android/daylo.apk NOT updated: could not read the latest release" >&2
fi
chown -R www-data:www-data "$WEBROOT"

echo "published $(git -C "$CHECKOUT" rev-parse --short HEAD) to $WEBROOT"
# Informative only: a failed check after a successful publish should not make the script fail.
curl -sS -o /dev/null -w "https://$DOMAIN/ -> %{http_code}\n" "https://$DOMAIN/" || echo "check failed: $DOMAIN did not answer" >&2
