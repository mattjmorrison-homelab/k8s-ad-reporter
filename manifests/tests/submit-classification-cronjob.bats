#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "ad-reporter-submit-classification CronJob runs every 5 minutes, offset from the other CronJobs" {
  schedule=$(resource CronJob ad-reporter-submit-classification | yq '.spec.schedule')
  [ "$schedule" = "2-59/5 * * * *" ]
}

@test "ad-reporter-submit-classification CronJob uses the shared verify image" {
  image=$(resource CronJob ad-reporter-submit-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].image')
  [ "$image" = "alpine@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc" ]
}

@test "ad-reporter-submit-classification CronJob mounts its script ConfigMap" {
  configmap=$(resource CronJob ad-reporter-submit-classification | yq '.spec.jobTemplate.spec.template.spec.volumes[0].configMap.name')
  [ "$configmap" = "ad-reporter-submit-classification-script" ]
}

@test "ad-reporter-submit-classification-script ConfigMap is NOT an ArgoCD hook" {
  hook=$(resource ConfigMap ad-reporter-submit-classification-script | yq '.metadata.annotations["argocd.argoproj.io/hook"] // "none"')
  [ "$hook" = "none" ]
}

@test "submit-classification script talks to the public Pi-hole and federated gateway hostnames, and the in-cluster backend" {
  grep -q 'ad-reporter-backend.ad-reporter.svc.cluster.local' scripts/submit-classification.sh
  grep -q 'https://pihole.morrisons.site' scripts/submit-classification.sh
  grep -q 'https://graphql.morrisons.site' scripts/submit-classification.sh
}
