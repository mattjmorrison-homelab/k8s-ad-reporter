# ad-reporter

Helm chart and deployment manifests for the "I just saw an ad" reporter:
a one-button PWA (`ui-ad-reporter`) plus a GraphQL API + SQLite store
(`graph-ad-reporter`) behind it.

Split out from the app source repos (which keep just source, tests, and
CI) so the two lifecycles don't get coupled: this repo's changes sync via
ArgoCD immediately on merge to `main`, while `graph-ad-reporter`'s and
`ui-ad-reporter`'s changes go through their own build/test/publish
pipelines and land here only via a `values.yaml` bump once they publish a
real image.

See `.github/docs/ad-reporter-plan.md` in `admin-github` for the full
cross-repo rollout this repo is one piece of.

## Placeholder images

`graph-ad-reporter` and `ui-ad-reporter` haven't published a real image
yet (their CI publish steps are still gated on other in-flight work), so
`manifests/values.yaml`'s `backend`/`ui` `image.digest` and `commitSha`
fields are syntactically-valid placeholders. Update both once each repo
publishes.
