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
# The Android download, android/Daylo-<version>.apk, is not in the repository (17 MB per
# release); it is fetched below, so the sync must neither delete nor replace it.
rsync -a --delay-updates --delete-after --exclude '/android/*.apk' "$CHECKOUT/site/" "$WEBROOT/"

# Served from this domain rather than GitHub: opened from another app, Chrome's custom tab stalls
# on GitHub's redirect to its file host. The version is the one the landing names (its JSON-LD),
# so the file the buttons point to always exists. Taken whole into a temporary name and moved into
# place only if it is an APK, so a failed download never replaces a good file. Older ones go,
# except the one before, which a page cached a moment ago may still ask for.
apk_version=$(sed -n 's/.*"softwareVersion": *"\([0-9.]*\)".*/\1/p' "$CHECKOUT/site/index.html" | head -n1)
if [[ -n "$apk_version" ]]; then
  apk="Daylo-$apk_version.apk"
  mkdir -p "$WEBROOT/android"
  tmp="$WEBROOT/android/.$apk.part"
  if [[ -s "$WEBROOT/android/$apk" ]]; then
    echo "android/$apk already there"
  elif curl -fsSL -o "$tmp" "https://github.com/$APP_REPO/releases/download/v$apk_version/Daylo-android-arm64.apk" \
     && [[ $(head -c 2 "$tmp") == "PK" ]] && [[ $(stat -c %s "$tmp") -gt 5000000 ]]; then
    mv -f "$tmp" "$WEBROOT/android/$apk"
    echo "android/$apk fetched"
  else
    rm -f "$tmp"
    echo "android/$apk NOT fetched: the v$apk_version download failed or was not an APK" >&2
  fi
  ls -1t "$WEBROOT/android/"Daylo-*.apk 2>/dev/null | tail -n +3 | xargs -r rm -f
  rm -f "$WEBROOT/android/daylo.apk"   # the unversioned name served before 1.4.1's landing named it
else
  echo "android download NOT updated: could not read the version from site/index.html" >&2
fi
chown -R www-data:www-data "$WEBROOT"

echo "published $(git -C "$CHECKOUT" rev-parse --short HEAD) to $WEBROOT"
# Informative only: a failed check after a successful publish should not make the script fail.
curl -sS -o /dev/null -w "https://$DOMAIN/ -> %{http_code}\n" "https://$DOMAIN/" || echo "check failed: $DOMAIN did not answer" >&2
