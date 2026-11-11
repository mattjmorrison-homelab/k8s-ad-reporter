#!/bin/sh
set -eu

apk add --no-cache curl jq >/dev/null

# This hook fires immediately after ArgoCD applies the new manifests, so the
# pod may still be pulling its image or starting up — retry rather than
# fail on the first check.
check_commit_sha() {
  URL="$1"
  EXPECTED="$2"

  for i in $(seq 1 20); do
    RESPONSE=$(curl -s -o /tmp/response.json -w "%{http_code}" "$URL")

    if [ "$RESPONSE" = "200" ]; then
      DEPLOYED_COMMIT_SHA=$(jq -r '.commit_sha' /tmp/response.json)
      if [ "$DEPLOYED_COMMIT_SHA" = "$EXPECTED" ]; then
        echo "PASS: $URL is running expected commit $EXPECTED"
        return 0
      fi
      echo "attempt $i: $URL reports commit $DEPLOYED_COMMIT_SHA, expected $EXPECTED, retrying..."
    else
      echo "attempt $i: $URL returned status $RESPONSE, retrying..."
    fi
    sleep 15
  done

  echo "FAIL: $URL never reported expected commit $EXPECTED after 20 attempts"
  exit 1
}

check_commit_sha "https://graph-ad-reporter.morrisons.site/version" "$EXPECTED_BACKEND_COMMIT_SHA"
check_commit_sha "https://ad-reporter.morrisons.site/version.json" "$EXPECTED_UI_COMMIT_SHA"
