#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "ad-reporter-zot-pull-secret ExternalSecret pulls from the right remote key and renders a dockerconfigjson" {
  key=$(resource ExternalSecret ad-reporter-zot-pull-secret | yq '.spec.data[0].remoteRef.key')
  [ "$key" = "homelab/service/k8s-zot/k8s-ad-reporter/zot-pull" ]

  type=$(resource ExternalSecret ad-reporter-zot-pull-secret | yq '.spec.target.template.type')
  [ "$type" = "kubernetes.io/dockerconfigjson" ]

  target=$(resource ExternalSecret ad-reporter-zot-pull-secret | yq '.spec.target.name')
  [ "$target" = "ad-reporter-zot-pull-secret" ]
}

@test "SecretStore authenticates as the k8s-ad-reporter Kubernetes-auth role via the ad-reporter ServiceAccount" {
  role=$(resource SecretStore openbao | yq '.spec.provider.vault.auth.kubernetes.role')
  sa=$(resource SecretStore openbao | yq '.spec.provider.vault.auth.kubernetes.serviceAccountRef.name')
  [ "$role" = "k8s-ad-reporter" ]
  [ "$sa" = "ad-reporter" ]
}

@test "ad-reporter-discord-webhooks ExternalSecret pulls both webhook URLs from the right remote keys" {
  confirmed_key=$(resource ExternalSecret ad-reporter-discord-webhooks | yq '.spec.data[0].remoteRef.key')
  suspicious_key=$(resource ExternalSecret ad-reporter-discord-webhooks | yq '.spec.data[1].remoteRef.key')
  [ "$confirmed_key" = "homelab/service/admin-discord/k8s-ad-reporter/confirmed-webhook-url" ]
  [ "$suspicious_key" = "homelab/service/admin-discord/k8s-ad-reporter/suspicious-webhook-url" ]

  target=$(resource ExternalSecret ad-reporter-discord-webhooks | yq '.spec.target.name')
  [ "$target" = "ad-reporter-discord-webhooks" ]
}

@test "the chart renders exactly the two expected ExternalSecrets" {
  count=$(echo "$RENDERED" | yq eval-all '[select(.kind == "ExternalSecret")] | length' -)
  [ "$count" = "2" ]
}
