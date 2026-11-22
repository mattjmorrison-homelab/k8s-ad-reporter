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

pihole_sid() {
  curl -sf -X POST "$PIHOLE_URL/api/auth" -H "Content-Type: application/json" -d '{"password": ""}' | jq -r '.session.sid'
}

escaped_domain_regex() {
  printf '%s' "$1" | sed 's/\./\\./g'
}

block_domain() {
  target_domain="$1"
  report_id="$2"
  sid=$(pihole_sid)
  pattern="(\\.|^)$(escaped_domain_regex "$target_domain")\$"
  deny_body=$(jq -nc --arg pattern "$pattern" --arg comment "ad-reporter: report $report_id" \
    '{domain: [$pattern], comment: $comment, enabled: true}')
  curl -sf -X POST "$PIHOLE_URL/api/domains/deny/regex" -H "Content-Type: application/json" -H "sid: $sid" -d "$deny_body" >/dev/null
}

notify_discord() {
  webhook_url="$1"
  message="$2"
  notify_body=$(jq -nc --arg content "$message" '{content: $content}')
  curl -sf -X POST "$webhook_url" -H "Content-Type: application/json" -d "$notify_body" >/dev/null
}

parse_classification_entries() {
  raw_response="$1"
  if parsed=$(echo "$raw_response" | jq -c '.' 2>/dev/null); then
    echo "$parsed"
    return 0
  fi
  stripped=$(echo "$raw_response" | sed -n 's/.*\(\[.*\]\).*/\1/p')
  if [ -n "$stripped" ] && parsed=$(echo "$stripped" | jq -c '.' 2>/dev/null); then
    echo "$parsed"
    return 0
  fi
  return 1
}

reports=$(graphql "$BACKEND_URL" '{"query":"{ unresolvedReports { id classificationPromptId } }"}' \
  | jq -c '.data.unresolvedReports[] | select(.classificationPromptId != null)')

if [ -z "$reports" ]; then
  echo "no reports awaiting classification results"
  exit 0
fi

echo "$reports" | while IFS= read -r report; do
  report_id=$(echo "$report" | jq -r '.id')
  prompt_job_id=$(echo "$report" | jq -r '.classificationPromptId')

  job_query=$(jq -nc --arg id "$prompt_job_id" \
    '{query: "query($id: ID!) { claude { promptJob(id: $id) { status response error } } }", variables: {id: $id}}')
  job=$(graphql "$CLAUDE_URL" "$job_query" | jq -c '.data.claude.promptJob')
  status=$(echo "$job" | jq -r '.status')

  case "$status" in
    PENDING)
      echo "report $report_id: classification prompt $prompt_job_id still pending"
      ;;
    FAILED)
      job_error=$(echo "$job" | jq -r '.error // "unknown error"')
      echo "report $report_id: classification prompt $prompt_job_id failed: $job_error"
      resolve_report "$report_id" "classification failed: $job_error"
      ;;
    COMPLETED)
      job_response=$(echo "$job" | jq -r '.response')
      if ! entries=$(parse_classification_entries "$job_response"); then
        echo "report $report_id: could not parse classification response"
        resolve_report "$report_id" "could not parse classification response"
        continue
      fi

      blocked_domains=""
      questionable_count=0

      entry_count=$(echo "$entries" | jq 'length')
      index=0
      while [ "$index" -lt "$entry_count" ]; do
        entry=$(echo "$entries" | jq -c ".[$index]")
        entry_domain=$(echo "$entry" | jq -r '.domain')
        entry_classification=$(echo "$entry" | jq -r '.classification')
        entry_reason=$(echo "$entry" | jq -r '.reason')

        case "$entry_classification" in
          block)
            block_domain "$entry_domain" "$report_id"
            notify_discord "$CONFIRMED_WEBHOOK_URL" "Blocked ad domain \`$entry_domain\` for report $report_id: $entry_reason"
            blocked_domains="${blocked_domains}${entry_domain}, "
            ;;
          questionable)
            notify_discord "$SUSPICIOUS_WEBHOOK_URL" "Questionable domain \`$entry_domain\` for report $report_id: $entry_reason"
            questionable_count=$((questionable_count + 1))
            ;;
          legit)
            true
            ;;
        esac

        index=$((index + 1))
      done

      if [ -n "$blocked_domains" ]; then
        summary="blocked ${blocked_domains%, }"
      else
        summary="no domains blocked"
      fi
      if [ "$questionable_count" -gt 0 ]; then
        summary="$summary, $questionable_count questionable"
      fi
      resolve_report "$report_id" "$summary"
      ;;
  esac
done
