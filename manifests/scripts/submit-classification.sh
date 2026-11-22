#!/bin/sh
set -eu

BACKEND_URL="http://ad-reporter-backend.ad-reporter.svc.cluster.local:8000/graphql"
PIHOLE_URL="https://pihole.morrisons.site"
CLAUDE_URL="https://graph-claude.morrisons.site/"

apk add --no-cache curl jq >/dev/null

graphql() {
  curl -sf -X POST "$1" -H "Content-Type: application/json" -d "$2"
}

resolve_report() {
  report_id="$1"
  resolution_note="$2"
  payload=$(jq -nc --arg id "$report_id" --arg note "$resolution_note" \
    '{query: "mutation($id: ID!, $note: String!) { resolveReport(id: $id, resolutionNote: $note) { id } }", variables: {id: $id, note: $note}}')
  graphql "$BACKEND_URL" "$payload" >/dev/null
}

pihole_sid=$(curl -sf -X POST "$PIHOLE_URL/api/auth" -H "Content-Type: application/json" -d '{"password": ""}' | jq -r '.session.sid')

domain_already_covered() {
  target_domain="$1"
  search_result=$(curl -sf "$PIHOLE_URL/api/search/$target_domain?n=3&partial=false" -H "sid: $pihole_sid")
  gravity_hits=$(echo "$search_result" | jq '.results.gravity | length')
  exact_hits=$(echo "$search_result" | jq '.results.domains.exact | length')
  regex_hits=$(echo "$search_result" | jq '.results.domains.regex | length')
  [ $((gravity_hits + exact_hits + regex_hits)) -gt 0 ]
}

reports=$(graphql "$BACKEND_URL" '{"query":"{ unresolvedReports { id candidateDomains classificationPromptId } }"}' \
  | jq -c '.data.unresolvedReports[] | select(.candidateDomains != null and (.candidateDomains | length) > 0 and .classificationPromptId == null)')

if [ -z "$reports" ]; then
  echo "no reports ready for classification submission"
  exit 0
fi

PROMPT_HEADER="For each of the following domains observed in a user's network traffic shortly after they reported seeing an ad, classify it as one of: \"block\" (confirmed ad/tracker/CMP vendor), \"legit\" (confirmed non-ad infrastructure, e.g. a major cloud/CDN provider or the core domain of a known software publisher), or \"questionable\" (not confidently classifiable either way — search the web if needed). Respond with ONLY a JSON array, no other text, in this exact shape: [{\"domain\": \"...\", \"classification\": \"block\"|\"legit\"|\"questionable\", \"reason\": \"...\"}]."

echo "$reports" | while IFS= read -r report; do
  report_id=$(echo "$report" | jq -r '.id')

  uncovered_domains=""
  for candidate_domain in $(echo "$report" | jq -r '.candidateDomains[]'); do
    if ! domain_already_covered "$candidate_domain"; then
      uncovered_domains="${uncovered_domains}${candidate_domain}
"
    fi
  done

  if [ -z "$uncovered_domains" ]; then
    echo "report $report_id: all candidate domains already covered"
    resolve_report "$report_id" "no ad domain found; candidates already covered"
    continue
  fi

  prompt=$(printf '%s\n\nDomains:\n%s' "$PROMPT_HEADER" "$uncovered_domains")

  submit_body=$(jq -nc --arg prompt "$prompt" \
    '{query: "mutation($prompt: String!) { claude { submitPrompt(prompt: $prompt) { id } } }", variables: {prompt: $prompt}}')
  prompt_job_id=$(graphql "$CLAUDE_URL" "$submit_body" | jq -r '.data.claude.submitPrompt.id')

  echo "report $report_id: submitted classification prompt $prompt_job_id"

  record_body=$(jq -nc --arg id "$report_id" --arg promptId "$prompt_job_id" \
    '{query: "mutation($id: ID!, $promptId: String!) { recordClassificationPromptId(id: $id, promptId: $promptId) { id } }", variables: {id: $id, promptId: $promptId}}')
  graphql "$BACKEND_URL" "$record_body" >/dev/null
done
