#!/bin/sh
set -eu

BACKEND_URL="http://ad-reporter-backend.ad-reporter.svc.cluster.local:8000/graphql"
PIHOLE_URL="http://pihole.pihole.svc.cluster.local:8080"
WINDOW_SECONDS=180

apk add --no-cache curl jq >/dev/null

reports=$(curl -sf -X POST "$BACKEND_URL" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ ad { unresolved { id timestamp candidateDomains } } }"}' \
  | jq -c '.data.ad.unresolved[]')

if [ -z "$reports" ]; then
  echo "no unresolved reports"
  exit 0
fi

queries=$(curl -sf "$PIHOLE_URL/api/queries?length=500" | jq -c '.queries')

echo "$reports" | while IFS= read -r report; do
  id=$(echo "$report" | jq -r '.id')
  already=$(echo "$report" | jq -r '.candidateDomains')

  if [ "$already" != "null" ]; then
    echo "report $id: already collected, skipping"
    continue
  fi

  report_epoch=$(echo "$report" | jq -r '
    .timestamp | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601
  ')

  domains=$(echo "$queries" | jq -c --argjson epoch "$report_epoch" --argjson window "$WINDOW_SECONDS" '
    [ .[] | select(.status == "FORWARDED" or .status == "CACHE" or .status == "CACHE_STALE")
           | select(.time >= ($epoch - $window) and .time <= ($epoch + $window))
           | .domain
    ] | unique
  ')

  echo "report $id: found domains $domains"

  payload=$(jq -nc --arg id "$id" --argjson domains "$domains" \
    '{query: "mutation($id: ID!, $domains: [String!]!) { ad { recordCandidateDomains(id: $id, domains: $domains) { id } } }", variables: {id: $id, domains: $domains}}')

  curl -sf -X POST "$BACKEND_URL" -H "Content-Type: application/json" -d "$payload" >/dev/null
done
