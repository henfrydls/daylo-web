#!/usr/bin/env bash
# Refresh the publishable files in site/ from the latest Daylo release.
#
# Runs on a machine with `gh` logged in (the demo is a workflow artifact, which
# needs authentication to download). It does not commit or deploy: review the
# diff, open a pull request, and run deploy/pull.sh on the server after merge.
#
#   deploy/build.sh              # latest release, its own workflow run
#   RUN_ID=123456 deploy/build.sh  # a specific run, e.g. a workflow_dispatch rebuild of the demo
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
# shellcheck source=config.env
source "$here/config.env"

for tool in gh unzip python3; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
[[ -n "$UMAMI_WEBSITE_ID" ]] || { echo "UMAMI_WEBSITE_ID is empty in deploy/config.env. Create the site in Umami first." >&2; exit 1; }

tag=$(gh release view -R "$APP_REPO" --json tagName -q .tagName)
if [[ -z "${RUN_ID:-}" ]]; then
  RUN_ID=$(gh run list -R "$APP_REPO" --workflow release.yml --limit 50 \
    --json databaseId,headBranch,conclusion \
    --jq "map(select(.headBranch == \"$tag\" and .conclusion == \"success\"))[0].databaseId")
fi
[[ -n "$RUN_ID" && "$RUN_ID" != "null" ]] || { echo "no successful release run found for $tag" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
gh run download "$RUN_ID" -R "$APP_REPO" -n "$DEMO_ARTIFACT" -D "$work/demo"
[[ -f "$work/demo/index.html" ]] || { echo "artifact has no index.html at its root" >&2; exit 1; }

# The app must ship with no analytics of its own. CI already checks the source;
# this checks the exact bytes we are about to publish.
pattern='analytics\.henfrydls\.com|umami|plausible\.io|googletagmanager|google-analytics|sentry\.io|posthog|mixpanel|hotjar'
set +e
hits=$(grep -rIlE "$pattern" "$work/demo"); status=$?
set -e
case $status in
  0) echo "analytics reference found in the demo build:" >&2; echo "$hits" >&2; exit 1 ;;
  1) ;;  # nothing found: the only acceptable outcome
  *) echo "grep failed while scanning the demo (exit $status); refusing to publish" >&2; exit 1 ;;
esac

# Only the demo served from this site carries Umami and the demo notice.
python3 - "$work/demo/index.html" "$UMAMI_HOST" "$UMAMI_WEBSITE_ID" "$DOMAIN" <<'PY'
import sys
path, host, site_id, domain = sys.argv[1:]
html = open(path, encoding="utf-8").read()
# data-domains keeps local copies and forks from reporting into the real site's numbers.
umami = f'    <script defer src="{host}/script.js" data-website-id="{site_id}" data-domains="{domain}"></script>\n  </head>'
notice = '''  <body>
    <div role="note" style="background:#ecfdf5;color:#064e3b;border-bottom:1px solid #a7f3d0;padding:.6rem 1rem;font:500 .875rem/1.45 system-ui,sans-serif;text-align:center">
      This is a demo. Anything you add here stays in this browser only and will not appear in the app when you install it.
      Want to keep it? Use <b>Export Data</b> here and <b>Import Data</b> in the app.
      <a href="/" style="color:#047857;text-decoration:underline;margin-left:.35rem">Get the app</a>
      <span aria-hidden="true" style="margin:0 .35rem;color:#6ee7b7">·</span><a href="/privacy/" style="color:#047857;text-decoration:underline">Privacy</a>
    </div>'''
assert html.count("  </head>") == 1 and html.count("  <body>") == 1, "unexpected index.html layout"
html = html.replace("  </head>", umami, 1).replace("  <body>", notice, 1)
open(path, "w", encoding="utf-8").write(html)
PY

rm -rf "$root/site/demo"
cp -r "$work/demo" "$root/site/demo"

# Landing: version in the JSON-LD, Umami id, and the privacy policy's effective date (set once).
python3 - "$root/site" "$tag" "$UMAMI_WEBSITE_ID" <<'PY'
import re, sys, datetime
site, tag, site_id = sys.argv[1:]
version = tag.lstrip("v")
today = datetime.date.today()
for rel in ("index.html", "privacy/index.html"):
    p = f"{site}/{rel}"; s = open(p, encoding="utf-8").read()
    s = s.replace("__APP_VERSION__", version)
    s = re.sub(r'"softwareVersion": "[^"]*"', f'"softwareVersion": "{version}"', s)
    s = re.sub(r'data-website-id="[^"]*"', f'data-website-id="{site_id}"', s)
    s = s.replace("PUBLISH_DATE_ISO", today.isoformat()).replace("PUBLISH_DATE", today.strftime("%B %-d, %Y"))
    open(p, "w", encoding="utf-8").write(s)
PY

echo "site/ refreshed from $APP_REPO $tag (run $RUN_ID)"
du -sh "$root/site/demo" | sed 's/^/demo: /'
echo "next: git diff, open a pull request, then deploy/pull.sh on the server"
