#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "ad-reporter-data PVC is ReadWriteOnce with 1Gi requested" {
  mode=$(resource PersistentVolumeClaim ad-reporter-data | yq '.spec.accessModes[0]')
  storage=$(resource PersistentVolumeClaim ad-reporter-data | yq '.spec.resources.requests.storage')
  [ "$mode" = "ReadWriteOnce" ]
  [ "$storage" = "1Gi" ]
}

@test "ad-reporter-data PVC has exactly one access mode" {
  count=$(resource PersistentVolumeClaim ad-reporter-data | yq '.spec.accessModes | length')
  [ "$count" = "1" ]
}
