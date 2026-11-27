#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "ad-reporter-check-classification CronJob runs every 5 minutes, offset from the other CronJobs" {
  schedule=$(resource CronJob ad-reporter-check-classification | yq '.spec.schedule')
  [ "$schedule" = "4-59/5 * * * *" ]
}

@test "ad-reporter-check-classification CronJob runs the check_classification module from the published backend image" {
  image=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].image')
  [ "$image" = "registry.morrisons.site/graph-ad-reporter:v0.0.0" ]

  command=$(resource CronJob ad-reporter-check-classification | yq -o=json -I=0 '.spec.jobTemplate.spec.template.spec.containers[0].command')
  [ "$command" = '["uv","run","python","-m","ad_reporter.cronjobs.check_classification"]' ]
}

@test "ad-reporter-check-classification CronJob wires the Discord webhook env vars from the shared secret" {
  confirmed_secret=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.name')
  confirmed_key=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.key')
  suspicious_key=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].env[1].valueFrom.secretKeyRef.key')
  [ "$confirmed_secret" = "ad-reporter-discord-webhooks" ]
  [ "$confirmed_key" = "confirmed-webhook-url" ]
  [ "$suspicious_key" = "suspicious-webhook-url" ]
}

