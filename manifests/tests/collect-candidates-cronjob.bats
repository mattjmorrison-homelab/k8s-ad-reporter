#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "ad-reporter-collect-candidates CronJob runs every 5 minutes" {
  schedule=$(resource CronJob ad-reporter-collect-candidates | yq '.spec.schedule')
  [ "$schedule" = "*/5 * * * *" ]
}

@test "ad-reporter-collect-candidates CronJob runs the collect_candidates module from the published backend image" {
  image=$(resource CronJob ad-reporter-collect-candidates | yq '.spec.jobTemplate.spec.template.spec.containers[0].image')
  [ "$image" = "registry.morrisons.site/graph-ad-reporter:v0.0.0" ]

  command=$(resource CronJob ad-reporter-collect-candidates | yq -o=json -I=0 '.spec.jobTemplate.spec.template.spec.containers[0].command')
  [ "$command" = '["uv","run","python","-m","ad_reporter.cronjobs.collect_candidates"]' ]
}
