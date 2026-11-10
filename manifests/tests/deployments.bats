#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "namespace is ad-reporter" {
  ns=$(resource Namespace ad-reporter)
  [ -n "$ns" ]
}

@test "ad-reporter-backend Deployment references graph-ad-reporter's image by repository+tag and exposes port 8000" {
  image=$(resource Deployment ad-reporter-backend | yq '.spec.template.spec.containers[0].image')
  [ "$image" = "registry.morrisons.site/graph-ad-reporter:v0.0.0" ]

  port=$(resource Deployment ad-reporter-backend | yq '.spec.template.spec.containers[0].ports[0].containerPort')
  [ "$port" = "8000" ]
}

@test "ad-reporter-ui Deployment references ui-ad-reporter's image by repository+tag and exposes port 80" {
  image=$(resource Deployment ad-reporter-ui | yq '.spec.template.spec.containers[0].image')
  [ "$image" = "registry.morrisons.site/ui-ad-reporter:v0.0.0" ]

  port=$(resource Deployment ad-reporter-ui | yq '.spec.template.spec.containers[0].ports[0].containerPort')
  [ "$port" = "80" ]
}

@test "both Deployments pull via the ad-reporter-zot-pull-secret" {
  backend_secret=$(resource Deployment ad-reporter-backend | yq '.spec.template.spec.imagePullSecrets[0].name')
  ui_secret=$(resource Deployment ad-reporter-ui | yq '.spec.template.spec.imagePullSecrets[0].name')
  [ "$backend_secret" = "ad-reporter-zot-pull-secret" ]
  [ "$ui_secret" = "ad-reporter-zot-pull-secret" ]
}

@test "ad-reporter-backend runs as the ad-reporter ServiceAccount" {
  sa=$(resource Deployment ad-reporter-backend | yq '.spec.template.spec.serviceAccountName')
  [ "$sa" = "ad-reporter" ]
}

@test "ad-reporter-backend mounts the ad-reporter-data PVC at /data and uses Recreate rollout strategy" {
  mount_path=$(resource Deployment ad-reporter-backend | yq '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "data") | .mountPath')
  [ "$mount_path" = "/data" ]

  claim=$(resource Deployment ad-reporter-backend | yq '.spec.template.spec.volumes[] | select(.name == "data") | .persistentVolumeClaim.claimName')
  [ "$claim" = "ad-reporter-data" ]

  strategy=$(resource Deployment ad-reporter-backend | yq '.spec.strategy.type')
  [ "$strategy" = "Recreate" ]
}
