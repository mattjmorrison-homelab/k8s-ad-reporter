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

@test "ad-reporter-collect-candidates-script ConfigMap is NOT an ArgoCD hook" {
  hook=$(resource ConfigMap ad-reporter-collect-candidates-script | yq '.metadata.annotations["argocd.argoproj.io/hook"] // "none"')
  [ "$hook" = "none" ]
}

@test "collect-candidates script talks to in-cluster Services, not public hostnames" {
  grep -q 'ad-reporter-backend.ad-reporter.svc.cluster.local' scripts/collect-candidates.sh
  grep -q 'pihole.pihole.svc.cluster.local' scripts/collect-candidates.sh
}
