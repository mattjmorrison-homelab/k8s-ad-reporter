#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "ad-reporter-backend Service targets port 8000" {
  port=$(resource Service ad-reporter-backend | yq '.spec.ports[0].port')
  target=$(resource Service ad-reporter-backend | yq '.spec.ports[0].targetPort')
  selector=$(resource Service ad-reporter-backend | yq '.spec.selector.app')
  [ "$port" = "8000" ]
  [ "$target" = "8000" ]
  [ "$selector" = "ad-reporter-backend" ]
}

@test "ad-reporter-ui Service targets port 80" {
  port=$(resource Service ad-reporter-ui | yq '.spec.ports[0].port')
  target=$(resource Service ad-reporter-ui | yq '.spec.ports[0].targetPort')
  selector=$(resource Service ad-reporter-ui | yq '.spec.selector.app')
  [ "$port" = "80" ]
  [ "$target" = "80" ]
  [ "$selector" = "ad-reporter-ui" ]
}

@test "Ingress routes ad-reporter.morrisons.site to ad-reporter-ui:80" {
  service=$(resource Ingress ad-reporter | yq '.spec.rules[] | select(.host == "ad-reporter.morrisons.site") | .http.paths[0].backend.service.name')
  port=$(resource Ingress ad-reporter | yq '.spec.rules[] | select(.host == "ad-reporter.morrisons.site") | .http.paths[0].backend.service.port.number')
  [ "$service" = "ad-reporter-ui" ]
  [ "$port" = "80" ]
}

@test "Ingress routes graph-ad-reporter.morrisons.site to ad-reporter-backend:8000" {
  service=$(resource Ingress ad-reporter | yq '.spec.rules[] | select(.host == "graph-ad-reporter.morrisons.site") | .http.paths[0].backend.service.name')
  port=$(resource Ingress ad-reporter | yq '.spec.rules[] | select(.host == "graph-ad-reporter.morrisons.site") | .http.paths[0].backend.service.port.number')
  [ "$service" = "ad-reporter-backend" ]
  [ "$port" = "8000" ]
}

@test "Ingress has exactly two host rules" {
  count=$(resource Ingress ad-reporter | yq '.spec.rules | length')
  [ "$count" = "2" ]
}
