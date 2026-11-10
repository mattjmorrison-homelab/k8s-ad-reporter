#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "ad-reporter-verify Job is a PostSync hook with BeforeHookCreation,HookSucceeded delete policy" {
  hook=$(resource Job ad-reporter-verify | yq '.metadata.annotations["argocd.argoproj.io/hook"]')
  policy=$(resource Job ad-reporter-verify | yq '.metadata.annotations["argocd.argoproj.io/hook-delete-policy"]')
  [ "$hook" = "PostSync" ]
  [ "$policy" = "BeforeHookCreation,HookSucceeded" ]
}

@test "ad-reporter-verify Job's expected commit SHAs come from the image tags" {
  backend_sha=$(resource Job ad-reporter-verify | yq '.spec.template.spec.containers[0].env[] | select(.name == "EXPECTED_BACKEND_COMMIT_SHA") | .value')
  ui_sha=$(resource Job ad-reporter-verify | yq '.spec.template.spec.containers[0].env[] | select(.name == "EXPECTED_UI_COMMIT_SHA") | .value')
  [ "$backend_sha" = "v0.0.0" ]
  [ "$ui_sha" = "v0.0.0" ]
}

@test "verify script checks /version on both ad-reporter hostnames" {
  grep -q 'https://graph-ad-reporter.morrisons.site/version' scripts/verify.sh
  grep -q 'https://ad-reporter.morrisons.site/version' scripts/verify.sh
}

@test "ad-reporter-verify-script ConfigMap is also a PostSync hook" {
  hook=$(resource ConfigMap ad-reporter-verify-script | yq '.metadata.annotations["argocd.argoproj.io/hook"]')
  [ "$hook" = "PostSync" ]
}
