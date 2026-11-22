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

@test "ad-reporter-check-classification CronJob uses the shared verify image" {
  image=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].image')
  [ "$image" = "alpine@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc" ]
}

@test "ad-reporter-check-classification CronJob mounts its script ConfigMap" {
  configmap=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.volumes[0].configMap.name')
  [ "$configmap" = "ad-reporter-check-classification-script" ]
}

@test "ad-reporter-check-classification CronJob wires the Discord webhook env vars from the shared secret" {
  confirmed_secret=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.name')
  confirmed_key=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.key')
  suspicious_key=$(resource CronJob ad-reporter-check-classification | yq '.spec.jobTemplate.spec.template.spec.containers[0].env[1].valueFrom.secretKeyRef.key')
  [ "$confirmed_secret" = "ad-reporter-discord-webhooks" ]
  [ "$confirmed_key" = "confirmed-webhook-url" ]
  [ "$suspicious_key" = "suspicious-webhook-url" ]
}

@test "ad-reporter-check-classification-script ConfigMap is NOT an ArgoCD hook" {
  hook=$(resource ConfigMap ad-reporter-check-classification-script | yq '.metadata.annotations["argocd.argoproj.io/hook"] // "none"')
  [ "$hook" = "none" ]
}

@test "check-classification script talks to the public Pi-hole and graph-claude hostnames, and the in-cluster backend" {
  grep -q 'ad-reporter-backend.ad-reporter.svc.cluster.local' scripts/check-classification.sh
  grep -q 'https://pihole.morrisons.site' scripts/check-classification.sh
  grep -q 'https://graph-claude.morrisons.site' scripts/check-classification.sh
}
